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
    [string]$DiscoveryPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedToolsCommit = '37b0457e8735ab8cc34a23f2717fcfb808e6a7a8'
$ExpectedIsoHash = 'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$Latin1 = [System.Text.Encoding]::GetEncoding(28591)
$RegexOptions = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
$PassPattern = '(?<![A-Za-z0-9_])(OptPass[A-Za-z0-9_]*)\s*\('

function Get-Sha256Hex([byte[]]$Bytes) {
    $Hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($Hasher.ComputeHash($Bytes))).Replace('-', '')
    }
    finally {
        $Hasher.Dispose()
    }
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

$Root = (Resolve-Path -LiteralPath $ExtractRoot -ErrorAction Stop).Path
$Manifest = (Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop).Path
$Discovery = (Resolve-Path -LiteralPath $DiscoveryPath -ErrorAction Stop).Path
$Output = [System.IO.Path]::GetFullPath($OutPath)
$Expanded = Join-Path $Root 'expanded'
$ExpandedPath = [System.IO.Path]::GetFullPath($Expanded)
$ExpandedPrefix = $ExpandedPath.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar

if (-not (Test-Path -LiteralPath $Expanded -PathType Container)) {
    throw "expanded corpus directory missing: $Expanded"
}
if (Test-Path -LiteralPath $Output) {
    throw "output already exists: $Output"
}

$ManifestLines = [System.IO.File]::ReadAllLines($Manifest)
foreach ($RequiredLine in @(
    'TEMPLEOSTS 1.10 INTERNAL EXPANDED CORPUS',
    "TOOLS_COMMIT`t$ExpectedToolsCommit",
    "ISO_SHA256`t$ExpectedIsoHash",
    "EXTRACTION_LAYER`texpanded",
    "PATCH_AUTHORITY`texpanded historical bytes only"
)) {
    if (-not ($ManifestLines -ccontains $RequiredLine)) {
        throw "expanded manifest missing exact line: $RequiredLine"
    }
}

$DiscoveryLines = [System.IO.File]::ReadAllLines($Discovery)
foreach ($RequiredLine in @(
    'TEMPLEOSTS 1.10 COMPILER DISCOVERY',
    "expanded_root`t$ExpandedPath",
    "expanded_manifest`t$Manifest",
    "COMPILER STATUS`tUNRESOLVED",
    "SEAM STATUS`tUNRESOLVED",
    "PATCH STATUS`tNOT-AUTHORIZED"
)) {
    if (-not ($DiscoveryLines -ccontains $RequiredLine)) {
        throw "discovery report missing exact line: $RequiredLine"
    }
}

$SectionIndex = [Array]::IndexOf($ManifestLines, 'FILES')
if ($SectionIndex -lt 0 -or $SectionIndex + 1 -ge $ManifestLines.Length) {
    throw 'expanded manifest has no FILES section'
}
if ($ManifestLines[$SectionIndex + 1] -cne "path`tbytes`tSHA256") {
    throw 'expanded manifest file header mismatch'
}

$CompilerRows = [System.Collections.Generic.List[object]]::new()
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
    if (-not $Parts[0].StartsWith('Compiler/', [System.StringComparison]::OrdinalIgnoreCase)) {
        continue
    }

    $ExpectedBytes = 0L
    if (-not [long]::TryParse($Parts[1], [ref]$ExpectedBytes)) {
        throw "invalid compiler byte count: $Line"
    }
    if ($Parts[2] -notmatch '^[0-9A-Fa-f]{64}$') {
        throw "invalid compiler SHA256: $Line"
    }

    $NativeRelative = $Parts[0].Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $FullPath = [System.IO.Path]::GetFullPath((Join-Path $ExpandedPath $NativeRelative))
    if (-not $FullPath.StartsWith($ExpandedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "compiler path escapes expanded corpus: $($Parts[0])"
    }
    if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) {
        throw "compiler file missing: $($Parts[0])"
    }

    $Item = Get-Item -LiteralPath $FullPath
    $ActualHash = (Get-FileHash -LiteralPath $FullPath -Algorithm SHA256).Hash
    if ($Item.Length -ne $ExpectedBytes -or $ActualHash -cne $Parts[2].ToUpperInvariant()) {
        throw "compiler identity mismatch: $($Parts[0])"
    }

    $CompilerRows.Add([pscustomobject]@{
        Path = $Parts[0]
        FullPath = $FullPath
        Bytes = $ExpectedBytes
        SHA256 = $ActualHash
    })
}

if ($CompilerRows.Count -eq 0) {
    throw 'expanded manifest contains no Compiler/ files'
}
foreach ($RequiredPath in @('Compiler/CmpMain.CPP', 'Compiler/OptPass6.CPP')) {
    $Count = @($CompilerRows | Where-Object { $_.Path -ceq $RequiredPath }).Count
    if ($Count -ne 1) {
        throw "observed compiler candidate count mismatch: path=$RequiredPath count=$Count"
    }
}

$CompilerSetLines = @(
    foreach ($Row in ($CompilerRows | Sort-Object Path)) {
        "$($Row.Path)`t$($Row.Bytes)`t$($Row.SHA256)"
    }
)
$CompilerSetHash = Get-Sha256Hex (
    $Latin1.GetBytes(($CompilerSetLines -join "`n") + "`n")
)
$DiscoveryHash = (Get-FileHash -LiteralPath $Discovery -Algorithm SHA256).Hash
$Occurrences = [System.Collections.Generic.List[object]]::new()
$Contexts = [System.Collections.Generic.List[string]]::new()

foreach ($Row in $CompilerRows) {
    if ($Row.Bytes -gt 16MB) {
        continue
    }

    $Bytes = [System.IO.File]::ReadAllBytes($Row.FullPath)
    $Text = $Latin1.GetString($Bytes)
    $Lines = [regex]::Split($Text, "\r\n|\n|\r")

    foreach ($Match in [regex]::Matches($Text, $PassPattern, $RegexOptions)) {
        $Offset = $Match.Groups[1].Index
        $LineNumber = Get-LineNumber $Text $Offset
        $Occurrences.Add([pscustomobject]@{
            Path = $Row.Path
            Name = $Match.Groups[1].Value
            Line = $LineNumber
            Offset = $Offset
        })

        if ($Row.Path -ceq 'Compiler/CmpMain.CPP') {
            $Start = [Math]::Max(1, $LineNumber - 4)
            $End = [Math]::Min($Lines.Length, $LineNumber + 4)
            $Contexts.Add("--- $($Row.Path) $($Match.Groups[1].Value) line $LineNumber offset $Offset")
            for ($ContextLine = $Start; $ContextLine -le $End; $ContextLine++) {
                $Display = $Lines[$ContextLine - 1].Replace("`t", '<TAB>')
                $Contexts.Add(("{0:D6}`t{1}" -f $ContextLine, $Display))
            }
        }
    }
}

$PipelineFiles = @(
    $Occurrences |
        Group-Object Path |
        ForEach-Object {
            $Ordered = @($_.Group | Sort-Object Offset)
            $Names = @($Ordered | Select-Object -ExpandProperty Name)
            $Unique = @($Names | Sort-Object -Unique)
            [pscustomobject]@{
                Path = $_.Name
                Occurrences = $Ordered.Count
                Unique = $Unique.Count
                OrderedNames = ($Names -join ',')
                OrderedLines = (@($Ordered | ForEach-Object { "$($_.Name)@$($_.Line)" }) -join ',')
            }
        } |
        Sort-Object `
            @{ Expression = 'Unique'; Descending = $true },
            @{ Expression = 'Occurrences'; Descending = $true },
            @{ Expression = 'Path'; Descending = $false }
)

$Report = [System.Collections.Generic.List[string]]::new()
foreach ($Line in @(
    'DBYTE-HOLYC-OPT',
    'TEMPLEOSTS 1.10 COMPILER PIPELINE RAW TRACE',
    '',
    'CORPUS',
    "tools_commit`t$ExpectedToolsCommit",
    "iso_sha256`t$ExpectedIsoHash",
    "expanded_root`t$ExpandedPath",
    "expanded_manifest`t$Manifest",
    "discovery_report`t$Discovery",
    "discovery_sha256`t$DiscoveryHash",
    "compiler_files_verified`t$($CompilerRows.Count)",
    "compiler_set_sha256`t$CompilerSetHash",
    "scan_mode`tRAW-TEXT-LATIN1",
    "filtering`tNONE",
    '',
    'PIPELINE FILE CANDIDATES',
    "path`tpass_occurrences`tunique_pass_names`tordered_names`tordered_occurrences"
)) {
    $Report.Add($Line)
}

foreach ($File in $PipelineFiles) {
    $Report.Add(
        "$($File.Path)`t$($File.Occurrences)`t$($File.Unique)`t" +
        "$($File.OrderedNames)`t$($File.OrderedLines)"
    )
}

foreach ($Line in @(
    '',
    'ALL RAW OptPass OCCURRENCES',
    "path`tname`tline`toffset"
)) {
    $Report.Add($Line)
}
foreach ($Hit in ($Occurrences | Sort-Object Path, Offset)) {
    $Report.Add("$($Hit.Path)`t$($Hit.Name)`t$($Hit.Line)`t$($Hit.Offset)")
}

$Report.Add('')
$Report.Add('CmpMain RAW CONTEXT')
foreach ($Line in $Contexts) {
    $Report.Add($Line)
}

foreach ($Line in @(
    '',
    'BOUNDARY',
    'Compiler/ is an exact candidate set verified against the expanded manifest.',
    'OptPass occurrences are raw Latin-1 text matches and are not code-only claims.',
    'Occurrences may include declarations, definitions, comments, or quoted text.',
    'The trace reports byte order and source context, not function ownership.',
    'No compiler entrypoint, pass boundary, or insertion seam is selected here.',
    'No source, archive, manifest, or discovery file is modified.',
    '',
    "COMPILER SET STATUS`tEXACT-CANDIDATE",
    "PIPELINE STATUS`tRAW-TRACE-ONLY",
    "SEAM STATUS`tUNRESOLVED",
    "PATCH STATUS`tNOT-AUTHORIZED",
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
Write-Host "COMPILER FILES:      $($CompilerRows.Count)/$($CompilerRows.Count)"
Write-Host "COMPILER SET SHA256: $CompilerSetHash"
Write-Host 'SCAN MODE:           RAW-TEXT-LATIN1'
Write-Host "PASS OCCURRENCES:    $($Occurrences.Count)"
Write-Host "PIPELINE FILES:      $($PipelineFiles.Count)"
foreach ($File in @($PipelineFiles | Select-Object -First 10)) {
    Write-Host (
        "PIPELINE FILE: {0} occurrences={1} unique={2} order={3}" -f
        $File.Path,
        $File.Occurrences,
        $File.Unique,
        $File.OrderedNames
    )
}
Write-Host "REPORT:              $Output"
Write-Host "REPORT SHA256:       $ReportHash"
Write-Host 'COMPILER SET:        EXACT-CANDIDATE'
Write-Host 'PIPELINE:            RAW-TRACE-ONLY'
Write-Host 'SEAM:                UNRESOLVED'
Write-Host 'PATCH STATUS:        NOT AUTHORIZED'
Write-Host 'VERDICT:             TRACE COMPLETE'
