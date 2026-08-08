[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ExtractRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ManifestPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$WorkRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedToolsCommit = '37b0457e8735ab8cc34a23f2717fcfb808e6a7a8'
$ExpectedIsoHash = 'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$ExpectedManifestHash = '6556485E4425386687C53F4F626146A2136AE12F38E075E2646C98147D61CB68'
$ExpectedFileCount = 1057
$TargetPath = 'Compiler/ICLCC.CPP'
$ExpectedTargetBytes = 10465L
$ExpectedTargetHash = '2F7A5A00947504E1D4D7DCFDBC99B16944D44F6C1DCEDABF2DAE6C60E5CD4873'
$Latin1 = [System.Text.Encoding]::GetEncoding(28591)

function Get-Sha256Hex([byte[]]$Bytes) {
    $Hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($Hasher.ComputeHash($Bytes))).Replace('-', '')
    }
    finally {
        $Hasher.Dispose()
    }
}

function Get-FullPrefix([string]$Path) {
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/') +
        [System.IO.Path]::DirectorySeparatorChar
}

$Root = (Resolve-Path -LiteralPath $ExtractRoot -ErrorAction Stop).Path
$Manifest = (Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop).Path
$Expanded = [System.IO.Path]::GetFullPath((Join-Path $Root 'expanded'))
$ExpandedPrefix = Get-FullPrefix $Expanded
$Work = [System.IO.Path]::GetFullPath($WorkRoot)
$WorkPrefix = Get-FullPrefix $Work
$Output = [System.IO.Path]::GetFullPath($OutPath)

if (-not (Test-Path -LiteralPath $Expanded -PathType Container)) {
    throw "expanded corpus directory missing: $Expanded"
}
if (Test-Path -LiteralPath $Work) {
    throw "work root already exists: $Work"
}
if (Test-Path -LiteralPath $Output) {
    throw "output already exists: $Output"
}

$RootFull = [System.IO.Path]::GetFullPath($Root)
if (
    $Work -ceq $RootFull -or
    $Work.StartsWith((Get-FullPrefix $RootFull), [System.StringComparison]::OrdinalIgnoreCase)
) {
    throw "work root must be outside the evidence root: work=$Work evidence=$RootFull"
}

$ManifestHash = (Get-FileHash -LiteralPath $Manifest -Algorithm SHA256).Hash
if ($ManifestHash -cne $ExpectedManifestHash) {
    throw "expanded manifest hash mismatch: expected=$ExpectedManifestHash actual=$ManifestHash"
}

$ManifestLines = [System.IO.File]::ReadAllLines($Manifest)
foreach ($RequiredLine in @(
    'TEMPLEOSTS 1.10 INTERNAL EXPANDED CORPUS',
    "TOOLS_COMMIT`t$ExpectedToolsCommit",
    "ISO_SHA256`t$ExpectedIsoHash",
    "EXTRACTION_LAYER`texpanded",
    "PATCH_AUTHORITY`texpanded historical bytes only",
    "FILE_COUNT`t$ExpectedFileCount"
)) {
    if (-not ($ManifestLines -ccontains $RequiredLine)) {
        throw "expanded manifest missing exact line: $RequiredLine"
    }
}

$SectionIndex = [Array]::IndexOf($ManifestLines, 'FILES')
if ($SectionIndex -lt 0 -or $SectionIndex + 1 -ge $ManifestLines.Length) {
    throw 'expanded manifest has no FILES section'
}
if ($ManifestLines[$SectionIndex + 1] -cne "path`tbytes`tSHA256") {
    throw 'expanded manifest file header mismatch'
}

$Rows = [System.Collections.Generic.List[object]]::new()
$SeenPaths = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)

for ($Index = $SectionIndex + 2; $Index -lt $ManifestLines.Length; $Index++) {
    $Line = $ManifestLines[$Index]
    if ([string]::IsNullOrWhiteSpace($Line) -or $Line -ceq 'BOUNDARY') {
        break
    }

    $Parts = $Line -split "`t", 3
    if ($Parts.Count -ne 3) {
        throw "malformed expanded manifest row: $Line"
    }
    if (-not $SeenPaths.Add($Parts[0])) {
        throw "duplicate path in expanded manifest: $($Parts[0])"
    }

    $ExpectedBytes = 0L
    if (-not [long]::TryParse($Parts[1], [ref]$ExpectedBytes)) {
        throw "invalid byte count in manifest row: $Line"
    }
    if ($Parts[2] -notmatch '^[0-9A-Fa-f]{64}$') {
        throw "invalid SHA256 in manifest row: $Line"
    }

    $Rows.Add([pscustomobject]@{
        Path = $Parts[0]
        Bytes = $ExpectedBytes
        SHA256 = $Parts[2].ToUpperInvariant()
    })
}

if ($Rows.Count -ne $ExpectedFileCount) {
    throw "manifest row count mismatch: expected=$ExpectedFileCount actual=$($Rows.Count)"
}

$TargetRows = @($Rows | Where-Object { $_.Path -ceq $TargetPath })
if ($TargetRows.Count -ne 1) {
    throw "target source row count mismatch: path=$TargetPath count=$($TargetRows.Count)"
}
$TargetRow = $TargetRows[0]
if (
    $TargetRow.Bytes -ne $ExpectedTargetBytes -or
    $TargetRow.SHA256 -cne $ExpectedTargetHash
) {
    throw "target source manifest identity mismatch: path=$TargetPath"
}

New-Item -ItemType Directory -Path $Work -Force | Out-Null

$Copied = 0
foreach ($Row in $Rows) {
    $NativeRelative = $Row.Path.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $Source = [System.IO.Path]::GetFullPath((Join-Path $Expanded $NativeRelative))
    $Destination = [System.IO.Path]::GetFullPath((Join-Path $Work $NativeRelative))

    if (-not $Source.StartsWith($ExpandedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "source path escapes expanded corpus: $($Row.Path)"
    }
    if (-not $Destination.StartsWith($WorkPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "destination path escapes work root: $($Row.Path)"
    }
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "manifest source missing: $($Row.Path)"
    }

    $SourceItem = Get-Item -LiteralPath $Source
    $SourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
    if ($SourceItem.Length -ne $Row.Bytes -or $SourceHash -cne $Row.SHA256) {
        throw "source identity mismatch before copy: $($Row.Path)"
    }

    $DestinationDirectory = Split-Path -Parent $Destination
    if ($DestinationDirectory) {
        New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null
    }
    [System.IO.File]::Copy($Source, $Destination, $false)

    $DestinationItem = Get-Item -LiteralPath $Destination
    $DestinationHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
    if ($DestinationItem.Length -ne $Row.Bytes -or $DestinationHash -cne $Row.SHA256) {
        throw "copied identity mismatch: $($Row.Path)"
    }

    $Copied++
}

if ($Copied -ne $ExpectedFileCount) {
    throw "copied file count mismatch: expected=$ExpectedFileCount actual=$Copied"
}

$TargetNative = $TargetPath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
$EvidenceTarget = [System.IO.Path]::GetFullPath((Join-Path $Expanded $TargetNative))
$WorkTarget = [System.IO.Path]::GetFullPath((Join-Path $Work $TargetNative))

$BaselineBytes = [System.IO.File]::ReadAllBytes($WorkTarget)
$BaselineHash = Get-Sha256Hex $BaselineBytes
if ($BaselineBytes.Length -ne $ExpectedTargetBytes -or $BaselineHash -cne $ExpectedTargetHash) {
    throw "work target baseline identity mismatch: $TargetPath"
}

$Text = $Latin1.GetString($BaselineBytes)
if ($Text.Contains("`r`n")) {
    $Newline = "`r`n"
}
elseif ($Text.Contains("`n")) {
    $Newline = "`n"
}
elseif ($Text.Contains("`r")) {
    $Newline = "`r"
}
else {
    throw "target source has no detectable line ending: $TargetPath"
}

$Before = '  LCCHeaderPut(lx,7,FALSE);'
$After = '  code_size=OptPass789(lx,fun_class,reg_offsets,NULL,NULL);'
$Needle = $Before + $Newline + $After
$NeedleCount = [regex]::Matches(
    $Text,
    [regex]::Escape($Needle),
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
).Count
if ($NeedleCount -ne 1) {
    throw "sealed seam needle count mismatch: expected=1 actual=$NeedleCount"
}

$Assertion = @(
    $Before,
    '  if (lx->pass!=7)',
    '    LexExcept(lx,"ST_OPT_INTERNAL_ERROR");',
    $After
) -join $Newline

$PatchedText = $Text.Replace($Needle, $Assertion)
$PatchedAssertionCount = [regex]::Matches(
    $PatchedText,
    [regex]::Escape($Assertion),
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
).Count
if ($PatchedAssertionCount -ne 1) {
    throw "patched assertion count mismatch: expected=1 actual=$PatchedAssertionCount"
}

$WorkTargetItem = Get-Item -LiteralPath $WorkTarget
if ($WorkTargetItem.IsReadOnly) {
    $WorkTargetItem.IsReadOnly = $false
}

$PatchedBytes = $Latin1.GetBytes($PatchedText)
[System.IO.File]::WriteAllBytes($WorkTarget, $PatchedBytes)

$PatchedHash = Get-Sha256Hex ([System.IO.File]::ReadAllBytes($WorkTarget))
if ($PatchedHash -ceq $ExpectedTargetHash) {
    throw 'patched target hash did not change'
}

$EvidenceHashAfter = (Get-FileHash -LiteralPath $EvidenceTarget -Algorithm SHA256).Hash
if ($EvidenceHashAfter -cne $ExpectedTargetHash) {
    throw "evidence target changed unexpectedly: $EvidenceTarget"
}

$Changed = [System.Collections.Generic.List[string]]::new()
foreach ($Row in $Rows) {
    $NativeRelative = $Row.Path.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $Destination = [System.IO.Path]::GetFullPath((Join-Path $Work $NativeRelative))
    $Item = Get-Item -LiteralPath $Destination
    $Hash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash

    if ($Row.Path -ceq $TargetPath) {
        if ($Hash -cne $PatchedHash) {
            throw "patched target hash changed during verification: $TargetPath"
        }
        $Changed.Add($Row.Path)
    }
    elseif ($Item.Length -ne $Row.Bytes -or $Hash -cne $Row.SHA256) {
        throw "non-target workspace file differs from manifest: $($Row.Path)"
    }
}

if ($Changed.Count -ne 1 -or $Changed[0] -cne $TargetPath) {
    throw "workspace changed-file contract failed: count=$($Changed.Count)"
}

$Report = [System.Collections.Generic.List[string]]::new()
foreach ($Line in @(
    'DBYTE-HOLYC-OPT',
    'TEMPLEOSTS 1.10 NO-REWRITE SEAM INSTALL',
    '',
    'CORPUS',
    "tools_commit`t$ExpectedToolsCommit",
    "iso_sha256`t$ExpectedIsoHash",
    "expanded_manifest`t$Manifest",
    "expanded_manifest_sha256`t$ManifestHash",
    "source_root`t$Expanded",
    "work_root`t$Work",
    "manifest_files`t$ExpectedFileCount",
    "copied_files`t$Copied",
    '',
    'SEALED SEAM',
    "path`t$TargetPath",
    "function`tLCCCompile",
    "after`tLCCHeaderPut(lx,7,FALSE);",
    "before`tcode_size=OptPass789(lx,fun_class,reg_offsets,NULL,NULL);",
    "baseline_bytes`t$ExpectedTargetBytes",
    "baseline_sha256`t$ExpectedTargetHash",
    "patched_bytes`t$($PatchedBytes.Length)",
    "patched_sha256`t$PatchedHash",
    '',
    'INSERTED ASSERTION',
    'if (lx->pass!=7)',
    '  LexExcept(lx,"ST_OPT_INTERNAL_ERROR");',
    '',
    'BOUNDARY',
    'The evidence tree remains unchanged.',
    'All 1057 manifest files were copied and verified before patching.',
    'Exactly one workspace file differs from the expanded manifest.',
    'The changed file is Compiler/ICLCC.CPP.',
    'The inserted assertion reads lx->pass and performs no valid-path write.',
    'No intermediate-code transformation is installed.',
    'No pass number, jump-table target, register mask, sizing loop, or emission path is changed.',
    '',
    "WORKSPACE STATUS`tEXACT-COPY-PLUS-ONE-ASSERTION",
    "SEAM STATUS`tSEALED",
    "PATCH CLASS`tNO-REWRITE-ASSERTION",
    "OPTIMIZER TRANSFORMATIONS`tNONE",
    "BUILD STATUS`tNOT-OBSERVED",
    "GUEST DIFFERENTIAL STATUS`tNOT-OBSERVED",
    '',
    'REPORTS ARE CLAIMS, NOT EVIDENCE.'
)) {
    $Report.Add($Line)
}

$OutputDirectory = Split-Path -Parent $Output
if ($OutputDirectory) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
[System.IO.File]::WriteAllText(
    $Output,
    (($Report -join "`n") + "`n"),
    [System.Text.UTF8Encoding]::new($false)
)

$ReportHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash
Write-Host "MANIFEST FILES:      $ExpectedFileCount/$ExpectedFileCount"
Write-Host "COPIED FILES:        $Copied/$ExpectedFileCount"
Write-Host "EVIDENCE ICLCC:      $ExpectedTargetHash"
Write-Host "PATCHED ICLCC:       $PatchedHash"
Write-Host "CHANGED FILES:       $($Changed.Count)"
Write-Host "REPORT:              $Output"
Write-Host "REPORT SHA256:       $ReportHash"
Write-Host 'WORKSPACE:           EXACT-COPY-PLUS-ONE-ASSERTION'
Write-Host 'SEAM:                SEALED'
Write-Host 'PATCH CLASS:         NO-REWRITE-ASSERTION'
Write-Host 'OPT TRANSFORMS:      NONE'
Write-Host 'BUILD:               NOT-OBSERVED'
Write-Host 'VERDICT:             INSTALL COMPLETE'
