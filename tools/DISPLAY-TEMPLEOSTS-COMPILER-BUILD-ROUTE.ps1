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
    [string]$InstallReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedToolsCommit = '37b0457e8735ab8cc34a23f2717fcfb808e6a7a8'
$ExpectedIsoHash = 'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$ExpectedManifestHash = '6556485E4425386687C53F4F626146A2136AE12F38E075E2646C98147D61CB68'
$ExpectedInstallReportHash = '59B0BB29AA5C088114E38FE27FCF5CB5E2D3F59120CD6FD2678DF9D566C75E32'
$ExpectedFileCount = 1057
$PatchedPath = 'Compiler/ICLCC.CPP'
$ExpectedPatchedHash = 'DB1C75A5EE71B07ADAEC32E984146602E73D9A0D606E2B76B8CCCC624E0CDCB8'
$Latin1 = [System.Text.Encoding]::GetEncoding(28591)

$DisplayPaths = @(
    'Compiler/Compiler.PRJ',
    'Compiler/CmpMain.CPP'
)

$BuildArtifactPaths = @(
    'Compiler/Compiler.PRJ',
    'Compiler/CmpMain.CPP',
    'Compiler/Compiler.BIN',
    'Compiler/Compiler.MAP'
)

$ExpectedArtifacts = [ordered]@{
    'Compiler/Compiler.PRJ' = [pscustomobject]@{
        Bytes = 858L
        SHA256 = 'D82BBFE3B9A75B67D5C3E1B6E5EB03628960B81FAC9E3453212AE1163A47F779'
    }
    'Compiler/CmpMain.CPP' = [pscustomobject]@{
        Bytes = 15275L
        SHA256 = 'B4F1DE8EC776EAE47E3FBB77A7E6E23A50FEB9F4EEED6605986D4736283E4B8B'
    }
    'Compiler/Compiler.BIN' = [pscustomobject]@{
        Bytes = 206512L
        SHA256 = '010F06358F26B5804600EE5BD6E6D313209C006C606E5F72C1E68D4028825AD1'
    }
    'Compiler/Compiler.MAP' = [pscustomobject]@{
        Bytes = 202757L
        SHA256 = '8509A6224474915233209975E9D56598FA79E005F616B31B878D4350CED247A5'
    }
}

$BuildLiterals = @(
    'Compiler.PRJ',
    'Compiler.BIN',
    'Compiler.MAP'
)

function Get-FullPrefix([string]$Path) {
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/') +
        [System.IO.Path]::DirectorySeparatorChar
}

function Get-LineNumber([string]$Text, [int]$Offset) {
    if ($Offset -lt 0 -or $Offset -gt $Text.Length) {
        throw "line offset outside text: $Offset"
    }

    $Line = 1
    for ($Index = 0; $Index -lt $Offset; $Index++) {
        if ($Text[$Index] -eq "`n") {
            $Line++
        }
        elseif (
            $Text[$Index] -eq "`r" -and
            ($Index + 1 -ge $Text.Length -or $Text[$Index + 1] -ne "`n")
        ) {
            $Line++
        }
    }
    return $Line
}

function Add-LineNumberedText {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [System.Collections.Generic.List[string]]$Report,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $Lines = [regex]::Split($Text, "\r\n|\n|\r")
    $Report.Add("--- $Path lines 1-$($Lines.Length)")
    for ($LineNumber = 1; $LineNumber -le $Lines.Length; $LineNumber++) {
        $Display = $Lines[$LineNumber - 1].Replace("`t", '<TAB>')
        $Report.Add(("{0:D6}`t{1}" -f $LineNumber, $Display))
    }
}

$Root = (Resolve-Path -LiteralPath $ExtractRoot -ErrorAction Stop).Path
$Manifest = (Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop).Path
$Work = (Resolve-Path -LiteralPath $WorkRoot -ErrorAction Stop).Path
$InstallReport = (Resolve-Path -LiteralPath $InstallReportPath -ErrorAction Stop).Path
$Output = [System.IO.Path]::GetFullPath($OutPath)
$Expanded = [System.IO.Path]::GetFullPath((Join-Path $Root 'expanded'))
$ExpandedPrefix = Get-FullPrefix $Expanded
$WorkPrefix = Get-FullPrefix $Work

if (-not (Test-Path -LiteralPath $Expanded -PathType Container)) {
    throw "expanded corpus directory missing: $Expanded"
}
if (-not (Test-Path -LiteralPath $Work -PathType Container)) {
    throw "work root missing: $Work"
}
if (Test-Path -LiteralPath $Output) {
    throw "output already exists: $Output"
}

$ManifestHash = (Get-FileHash -LiteralPath $Manifest -Algorithm SHA256).Hash
if ($ManifestHash -cne $ExpectedManifestHash) {
    throw "expanded manifest hash mismatch: expected=$ExpectedManifestHash actual=$ManifestHash"
}

$InstallReportHash = (Get-FileHash -LiteralPath $InstallReport -Algorithm SHA256).Hash
if ($InstallReportHash -cne $ExpectedInstallReportHash) {
    throw "install report hash mismatch: expected=$ExpectedInstallReportHash actual=$InstallReportHash"
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
$RowsByPath = [System.Collections.Generic.Dictionary[string, object]]::new(
    [System.StringComparer]::Ordinal
)
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

    $Row = [pscustomobject]@{
        Path = $Parts[0]
        Bytes = $ExpectedBytes
        SHA256 = $Parts[2].ToUpperInvariant()
    }
    $Rows.Add($Row)
    $RowsByPath.Add($Row.Path, $Row)
}

if ($Rows.Count -ne $ExpectedFileCount) {
    throw "manifest row count mismatch: expected=$ExpectedFileCount actual=$($Rows.Count)"
}

foreach ($ArtifactPath in $BuildArtifactPaths) {
    if (-not $RowsByPath.ContainsKey($ArtifactPath)) {
        throw "build artifact absent from exact manifest: $ArtifactPath"
    }
    $Row = $RowsByPath[$ArtifactPath]
    $Expected = $ExpectedArtifacts[$ArtifactPath]
    if ($Row.Bytes -ne $Expected.Bytes -or $Row.SHA256 -cne $Expected.SHA256) {
        throw "build artifact manifest identity mismatch: $ArtifactPath"
    }
}

$ChangedPaths = [System.Collections.Generic.List[string]]::new()
$WorkspacePaths = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)

foreach ($Row in $Rows) {
    $NativeRelative = $Row.Path.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $EvidenceFile = [System.IO.Path]::GetFullPath((Join-Path $Expanded $NativeRelative))
    $WorkFile = [System.IO.Path]::GetFullPath((Join-Path $Work $NativeRelative))

    if (-not $EvidenceFile.StartsWith($ExpandedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "evidence path escapes expanded corpus: $($Row.Path)"
    }
    if (-not $WorkFile.StartsWith($WorkPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "workspace path escapes work root: $($Row.Path)"
    }
    if (-not (Test-Path -LiteralPath $EvidenceFile -PathType Leaf)) {
        throw "evidence file missing: $($Row.Path)"
    }
    if (-not (Test-Path -LiteralPath $WorkFile -PathType Leaf)) {
        throw "workspace file missing: $($Row.Path)"
    }

    $EvidenceItem = Get-Item -LiteralPath $EvidenceFile
    $EvidenceHash = (Get-FileHash -LiteralPath $EvidenceFile -Algorithm SHA256).Hash
    if ($EvidenceItem.Length -ne $Row.Bytes -or $EvidenceHash -cne $Row.SHA256) {
        throw "evidence identity mismatch: $($Row.Path)"
    }

    $WorkItem = Get-Item -LiteralPath $WorkFile
    $WorkHash = (Get-FileHash -LiteralPath $WorkFile -Algorithm SHA256).Hash
    if ($Row.Path -ceq $PatchedPath) {
        if ($WorkHash -cne $ExpectedPatchedHash) {
            throw "patched workspace identity mismatch: $($Row.Path)"
        }
        $ChangedPaths.Add($Row.Path)
    }
    elseif ($WorkItem.Length -ne $Row.Bytes -or $WorkHash -cne $Row.SHA256) {
        throw "unexpected workspace difference: $($Row.Path)"
    }

    [void]$WorkspacePaths.Add($Row.Path)
}

$WorkFiles = @(Get-ChildItem -LiteralPath $Work -Recurse -File)
if ($WorkFiles.Count -ne $ExpectedFileCount) {
    throw "workspace file count mismatch: expected=$ExpectedFileCount actual=$($WorkFiles.Count)"
}

foreach ($WorkFile in $WorkFiles) {
    $FullPath = [System.IO.Path]::GetFullPath($WorkFile.FullName)
    if (-not $FullPath.StartsWith($WorkPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "enumerated workspace path escapes work root: $FullPath"
    }
    $Relative = $FullPath.Substring($WorkPrefix.Length).Replace(
        [System.IO.Path]::DirectorySeparatorChar,
        '/'
    )
    if (-not $WorkspacePaths.Contains($Relative)) {
        throw "extra workspace file not present in manifest: $Relative"
    }
}

if ($ChangedPaths.Count -ne 1 -or $ChangedPaths[0] -cne $PatchedPath) {
    throw "workspace changed-file contract failed: count=$($ChangedPaths.Count)"
}

$RawReferences = [System.Collections.Generic.List[object]]::new()
foreach ($Row in $Rows) {
    $NativeRelative = $Row.Path.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $WorkFile = [System.IO.Path]::GetFullPath((Join-Path $Work $NativeRelative))
    $Bytes = [System.IO.File]::ReadAllBytes($WorkFile)
    $Text = $Latin1.GetString($Bytes)

    foreach ($Literal in $BuildLiterals) {
        $SearchFrom = 0
        while ($SearchFrom -lt $Text.Length) {
            $Offset = $Text.IndexOf(
                $Literal,
                $SearchFrom,
                [System.StringComparison]::Ordinal
            )
            if ($Offset -lt 0) {
                break
            }

            $RawReferences.Add([pscustomobject]@{
                Path = $Row.Path
                Literal = $Literal
                Line = Get-LineNumber $Text $Offset
                Offset = $Offset
            })
            $SearchFrom = $Offset + $Literal.Length
        }
    }
}

$Report = [System.Collections.Generic.List[string]]::new()
foreach ($Line in @(
    'DBYTE-HOLYC-OPT',
    'TEMPLEOSTS 1.10 COMPILER BUILD ROUTE CONTEXT',
    '',
    'CORPUS',
    "tools_commit`t$ExpectedToolsCommit",
    "iso_sha256`t$ExpectedIsoHash",
    "expanded_manifest`t$Manifest",
    "expanded_manifest_sha256`t$ManifestHash",
    "install_report`t$InstallReport",
    "install_report_sha256`t$InstallReportHash",
    "evidence_root`t$Expanded",
    "work_root`t$Work",
    "manifest_files`t$ExpectedFileCount",
    "workspace_files`t$($WorkFiles.Count)",
    "changed_files`t$($ChangedPaths.Count)",
    "changed_path`t$($ChangedPaths[0])",
    "patched_iclcc_sha256`t$ExpectedPatchedHash",
    '',
    'BUILD ARTIFACT IDENTITIES',
    "path`tbytes`tSHA256"
)) {
    $Report.Add($Line)
}

foreach ($ArtifactPath in $BuildArtifactPaths) {
    $Expected = $ExpectedArtifacts[$ArtifactPath]
    $Report.Add("$ArtifactPath`t$($Expected.Bytes)`t$($Expected.SHA256)")
}

$Report.Add('')
$Report.Add('RAW BUILD-NAME REFERENCES')
$Report.Add("path`tliteral`tline`toffset")
foreach ($Reference in ($RawReferences | Sort-Object Path, Offset, Literal)) {
    $Report.Add(
        "$($Reference.Path)`t$($Reference.Literal)`t$($Reference.Line)`t$($Reference.Offset)"
    )
}

foreach ($DisplayPath in $DisplayPaths) {
    $NativeRelative = $DisplayPath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $WorkFile = [System.IO.Path]::GetFullPath((Join-Path $Work $NativeRelative))
    $Text = $Latin1.GetString([System.IO.File]::ReadAllBytes($WorkFile))
    $Report.Add('')
    $Report.Add('SOURCE DISPLAY')
    $Report.Add("path`t$DisplayPath")
    $Report.Add("bytes`t$($ExpectedArtifacts[$DisplayPath].Bytes)")
    $Report.Add("sha256`t$($ExpectedArtifacts[$DisplayPath].SHA256)")
    Add-LineNumberedText -Report $Report -Path $DisplayPath -Text $Text
}

foreach ($Line in @(
    '',
    'BOUNDARY',
    'The evidence corpus and installed workspace were re-verified before display.',
    'The workspace contains the exact 1057-file copy plus the one authorized assertion.',
    'Compiler.PRJ and CmpMain.CPP are displayed as raw Latin-1 source text.',
    'Build-name references are raw exact-literal matches and carry no execution claim.',
    'No build command, loader entry, output replacement, or guest execution is selected.',
    'No evidence or workspace file is modified by this tool.',
    '',
    "WORKSPACE STATUS`tEXACT-COPY-PLUS-ONE-ASSERTION",
    "BUILD ROUTE STATUS`tRAW-DISPLAY-ONLY",
    "BUILD STATUS`tNOT-OBSERVED",
    "GUEST STATUS`tNOT-OBSERVED",
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
Write-Host "WORKSPACE FILES:     $($WorkFiles.Count)/$ExpectedFileCount"
Write-Host "CHANGED FILES:       $($ChangedPaths.Count)"
Write-Host "PATCHED ICLCC:       $ExpectedPatchedHash"
Write-Host "BUILD REFERENCES:    $($RawReferences.Count)"
Write-Host "REPORT:              $Output"
Write-Host "REPORT SHA256:       $ReportHash"
Write-Host 'WORKSPACE:           EXACT-COPY-PLUS-ONE-ASSERTION'
Write-Host 'BUILD ROUTE:         RAW-DISPLAY-ONLY'
Write-Host 'BUILD:               NOT-OBSERVED'
Write-Host 'VERDICT:             BUILD ROUTE CONTEXT COMPLETE'
