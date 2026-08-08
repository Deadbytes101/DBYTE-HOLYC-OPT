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
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedToolsCommit = '37b0457e8735ab8cc34a23f2717fcfb808e6a7a8'
$ExpectedIsoHash = 'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$ExpectedManifestHash = '6556485E4425386687C53F4F626146A2136AE12F38E075E2646C98147D61CB68'
$Latin1 = [System.Text.Encoding]::GetEncoding(28591)
$RegexOptions = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
$PassPattern = '(?<![A-Za-z0-9_])(OptPass[A-Za-z0-9_]*)\s*\('
$ContextRadius = 24

$TargetPaths = @(
    'Compiler/CmpExts.CPP',
    'Compiler/ICLCC.CPP'
)

$ExpectedOrders = [ordered]@{
    'Compiler/CmpExts.CPP' = @(
        'OptPass012',
        'OptPass3',
        'OptPass4',
        'OptPass5',
        'OptPass6',
        'OptPass789'
    )
    'Compiler/ICLCC.CPP' = @(
        'OptPass012',
        'OptPass012',
        'OptPass3',
        'OptPass4',
        'OptPass5',
        'OptPass6',
        'OptPass789',
        'OptPass789',
        'OptPass789'
    )
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
    "PATCH_AUTHORITY`texpanded historical bytes only"
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

$Rows = [System.Collections.Generic.Dictionary[string, object]]::new(
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
    if (-not ($TargetPaths -ccontains $Parts[0])) {
        continue
    }

    $ExpectedBytes = 0L
    if (-not [long]::TryParse($Parts[1], [ref]$ExpectedBytes)) {
        throw "invalid target byte count: $Line"
    }
    if ($Parts[2] -notmatch '^[0-9A-Fa-f]{64}$') {
        throw "invalid target SHA256: $Line"
    }

    $NativeRelative = $Parts[0].Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $FullPath = [System.IO.Path]::GetFullPath((Join-Path $ExpandedPath $NativeRelative))
    if (-not $FullPath.StartsWith($ExpandedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "target path escapes expanded corpus: $($Parts[0])"
    }
    if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) {
        throw "target source missing: $($Parts[0])"
    }

    $Item = Get-Item -LiteralPath $FullPath
    $ActualHash = (Get-FileHash -LiteralPath $FullPath -Algorithm SHA256).Hash
    $ExpectedHash = $Parts[2].ToUpperInvariant()
    if ($Item.Length -ne $ExpectedBytes -or $ActualHash -cne $ExpectedHash) {
        throw "target source identity mismatch: $($Parts[0])"
    }

    $Rows.Add($Parts[0], [pscustomobject]@{
        Path = $Parts[0]
        FullPath = $FullPath
        Bytes = $ExpectedBytes
        SHA256 = $ActualHash
    })
}

foreach ($TargetPath in $TargetPaths) {
    if (-not $Rows.ContainsKey($TargetPath)) {
        throw "target source absent from exact manifest: $TargetPath"
    }
}

$Report = [System.Collections.Generic.List[string]]::new()
foreach ($Line in @(
    'DBYTE-HOLYC-OPT',
    'TEMPLEOSTS 1.10 PIPELINE SOURCE CONTEXT',
    '',
    'CORPUS',
    "tools_commit`t$ExpectedToolsCommit",
    "iso_sha256`t$ExpectedIsoHash",
    "expanded_root`t$ExpandedPath",
    "expanded_manifest`t$Manifest",
    "expanded_manifest_sha256`t$ManifestHash",
    "scan_mode`tRAW-TEXT-LATIN1",
    "filtering`tNONE",
    "context_radius_lines`t$ContextRadius"
)) {
    $Report.Add($Line)
}

foreach ($TargetPath in $TargetPaths) {
    $Row = $Rows[$TargetPath]
    $Bytes = [System.IO.File]::ReadAllBytes($Row.FullPath)
    $Text = $Latin1.GetString($Bytes)
    $Lines = [regex]::Split($Text, "\r\n|\n|\r")
    $Matches = @([regex]::Matches($Text, $PassPattern, $RegexOptions))
    $ObservedNames = @(
        foreach ($Match in $Matches) {
            $Match.Groups[1].Value
        }
    )
    $ExpectedNames = @($ExpectedOrders[$TargetPath])

    if ($ObservedNames.Count -ne $ExpectedNames.Count) {
        throw (
            "raw OptPass count changed: path=$TargetPath " +
            "expected=$($ExpectedNames.Count) actual=$($ObservedNames.Count)"
        )
    }
    for ($Index = 0; $Index -lt $ExpectedNames.Count; $Index++) {
        if ($ObservedNames[$Index] -cne $ExpectedNames[$Index]) {
            throw (
                "raw OptPass order changed: path=$TargetPath index=$Index " +
                "expected=$($ExpectedNames[$Index]) actual=$($ObservedNames[$Index])"
            )
        }
    }

    $Occurrences = [System.Collections.Generic.List[object]]::new()
    $RawWindows = [System.Collections.Generic.List[object]]::new()
    foreach ($Match in $Matches) {
        $Offset = $Match.Groups[1].Index
        $LineNumber = Get-LineNumber $Text $Offset
        $Occurrences.Add([pscustomobject]@{
            Name = $Match.Groups[1].Value
            Line = $LineNumber
            Offset = $Offset
        })
        $RawWindows.Add([pscustomobject]@{
            Start = [Math]::Max(1, $LineNumber - $ContextRadius)
            End = [Math]::Min($Lines.Length, $LineNumber + $ContextRadius)
        })
    }

    $MergedWindows = [System.Collections.Generic.List[object]]::new()
    foreach ($Window in ($RawWindows | Sort-Object Start, End)) {
        if ($MergedWindows.Count -eq 0) {
            $MergedWindows.Add([pscustomobject]@{
                Start = $Window.Start
                End = $Window.End
            })
            continue
        }

        $Last = $MergedWindows[$MergedWindows.Count - 1]
        if ($Window.Start -le $Last.End + 1) {
            if ($Window.End -gt $Last.End) {
                $Last.End = $Window.End
            }
        }
        else {
            $MergedWindows.Add([pscustomobject]@{
                Start = $Window.Start
                End = $Window.End
            })
        }
    }

    foreach ($Line in @(
        '',
        'SOURCE',
        "path`t$TargetPath",
        "bytes`t$($Row.Bytes)",
        "sha256`t$($Row.SHA256)",
        "raw_occurrences`t$($Occurrences.Count)",
        "raw_order`t$($ObservedNames -join ',')",
        '',
        'OCCURRENCES',
        "name`tline`toffset"
    )) {
        $Report.Add($Line)
    }
    foreach ($Occurrence in $Occurrences) {
        $Report.Add("$($Occurrence.Name)`t$($Occurrence.Line)`t$($Occurrence.Offset)")
    }

    $Report.Add('')
    $Report.Add('CONTEXT WINDOWS')
    foreach ($Window in $MergedWindows) {
        $Report.Add("--- $TargetPath lines $($Window.Start)-$($Window.End)")
        for ($LineNumber = $Window.Start; $LineNumber -le $Window.End; $LineNumber++) {
            $Display = $Lines[$LineNumber - 1].Replace("`t", '<TAB>')
            $Report.Add(("{0:D6}`t{1}" -f $LineNumber, $Display))
        }
    }
}

foreach ($Line in @(
    '',
    'BOUNDARY',
    'The displayed files are exact expanded historical bytes from TempleOSTS 1.10.',
    'Raw OptPass matches may be declarations, definitions, comments, or quoted text.',
    'Context windows are display evidence for manual source adjudication only.',
    'No function ownership, compiler entrypoint, or insertion seam is selected.',
    'No source, archive, manifest, or prior evidence file is modified.',
    '',
    "SOURCE CONTEXT STATUS`tSEALED-DISPLAY",
    "PIPELINE STATUS`tCANDIDATE-ONLY",
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
Write-Host "MANIFEST SHA256: $ManifestHash"
foreach ($TargetPath in $TargetPaths) {
    $Row = $Rows[$TargetPath]
    Write-Host "SOURCE:          $TargetPath"
    Write-Host "SOURCE SHA256:   $($Row.SHA256)"
    Write-Host "RAW ORDER:       $(@($ExpectedOrders[$TargetPath]) -join ',')"
}
Write-Host "REPORT:          $Output"
Write-Host "REPORT SHA256:   $ReportHash"
Write-Host 'SOURCE CONTEXT:  SEALED-DISPLAY'
Write-Host 'PIPELINE:        CANDIDATE-ONLY'
Write-Host 'SEAM:            UNRESOLVED'
Write-Host 'PATCH STATUS:    NOT AUTHORIZED'
Write-Host 'VERDICT:         CONTEXT COMPLETE'
