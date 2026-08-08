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
$ExpectedIclccHash = '2F7A5A00947504E1D4D7DCFDBC99B16944D44F6C1DCEDABF2DAE6C60E5CD4873'
$Latin1 = [System.Text.Encoding]::GetEncoding(28591)
$RegexOptions = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant

$Targets = @(
    [pscustomobject]@{
        Path = 'Compiler/ICLCC.CPP'
        Patterns = [string[]]@('OptPass6', 'OptPass789')
        Counts = [int[]]@(1, 3)
        Radius = 40
    },
    [pscustomobject]@{
        Path = 'Compiler/OptPass6.CPP'
        Patterns = [string[]]@('OptPass6')
        Counts = [int[]]@(1)
        Radius = 120
    },
    [pscustomobject]@{
        Path = 'Compiler/OptPass789.CPP'
        Patterns = [string[]]@('OptPass789')
        Counts = [int[]]@(1)
        Radius = 120
    }
)

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

function Get-MergedWindows {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Occurrences,

        [Parameter(Mandatory = $true)]
        [int]$LineCount,

        [Parameter(Mandatory = $true)]
        [int]$Radius
    )

    $Raw = [System.Collections.Generic.List[object]]::new()
    foreach ($Occurrence in $Occurrences) {
        $Raw.Add([pscustomobject]@{
            Start = [Math]::Max(1, $Occurrence.Line - $Radius)
            End = [Math]::Min($LineCount, $Occurrence.Line + $Radius)
        })
    }

    $Merged = [System.Collections.Generic.List[object]]::new()
    foreach ($Window in ($Raw | Sort-Object Start, End)) {
        if ($Merged.Count -eq 0) {
            $Merged.Add([pscustomobject]@{
                Start = $Window.Start
                End = $Window.End
            })
            continue
        }

        $Last = $Merged[$Merged.Count - 1]
        if ($Window.Start -le $Last.End + 1) {
            if ($Window.End -gt $Last.End) {
                $Last.End = $Window.End
            }
        }
        else {
            $Merged.Add([pscustomobject]@{
                Start = $Window.Start
                End = $Window.End
            })
        }
    }

    return @($Merged)
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

$TargetPaths = @($Targets | Select-Object -ExpandProperty Path)
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
    if ($Parts[0] -ceq 'Compiler/ICLCC.CPP' -and $ActualHash -cne $ExpectedIclccHash) {
        throw "ICLCC source hash mismatch: expected=$ExpectedIclccHash actual=$ActualHash"
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
    'TEMPLEOSTS 1.10 PASS BOUNDARY CONTEXT',
    '',
    'CORPUS',
    "tools_commit`t$ExpectedToolsCommit",
    "iso_sha256`t$ExpectedIsoHash",
    "expanded_root`t$ExpandedPath",
    "expanded_manifest`t$Manifest",
    "expanded_manifest_sha256`t$ManifestHash",
    "scan_mode`tRAW-TEXT-LATIN1",
    "filtering`tNONE"
)) {
    $Report.Add($Line)
}

foreach ($Target in $Targets) {
    $Row = $Rows[$Target.Path]
    $Bytes = [System.IO.File]::ReadAllBytes($Row.FullPath)
    $Text = $Latin1.GetString($Bytes)
    $Lines = [regex]::Split($Text, "\r\n|\n|\r")
    $Occurrences = [System.Collections.Generic.List[object]]::new()

    for ($PatternIndex = 0; $PatternIndex -lt $Target.Patterns.Count; $PatternIndex++) {
        $Name = $Target.Patterns[$PatternIndex]
        $ExpectedCount = $Target.Counts[$PatternIndex]
        $Pattern = '(?<![A-Za-z0-9_])' + [regex]::Escape($Name) + '\s*\('
        $Matches = @([regex]::Matches($Text, $Pattern, $RegexOptions))
        if ($Matches.Count -ne $ExpectedCount) {
            throw (
                "raw occurrence count changed: path=$($Target.Path) name=$Name " +
                "expected=$ExpectedCount actual=$($Matches.Count)"
            )
        }

        foreach ($Match in $Matches) {
            $Offset = $Match.Index
            $Occurrences.Add([pscustomobject]@{
                Name = $Name
                Line = Get-LineNumber $Text $Offset
                Offset = $Offset
            })
        }
    }

    $OrderedOccurrences = @($Occurrences | Sort-Object Offset)
    $Windows = @(
        Get-MergedWindows `
            -Occurrences $OrderedOccurrences `
            -LineCount $Lines.Length `
            -Radius $Target.Radius
    )

    foreach ($Line in @(
        '',
        'SOURCE',
        "path`t$($Target.Path)",
        "bytes`t$($Row.Bytes)",
        "sha256`t$($Row.SHA256)",
        "context_radius_lines`t$($Target.Radius)",
        '',
        'OCCURRENCES',
        "name`tline`toffset"
    )) {
        $Report.Add($Line)
    }

    foreach ($Occurrence in $OrderedOccurrences) {
        $Report.Add("$($Occurrence.Name)`t$($Occurrence.Line)`t$($Occurrence.Offset)")
    }

    $Report.Add('')
    $Report.Add('CONTEXT WINDOWS')
    foreach ($Window in $Windows) {
        $Report.Add("--- $($Target.Path) lines $($Window.Start)-$($Window.End)")
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
    'Raw name matches and context are evidence for manual contract adjudication.',
    'No function parser, comment filter, quote filter, or semantic classifier is used.',
    'No insertion seam or source patch is authorized by this display report.',
    'No source, archive, manifest, or prior evidence file is modified.',
    '',
    "PASS CONTEXT STATUS`tSEALED-DISPLAY",
    "PIPELINE OWNER STATUS`tLCCCompile-SEALED",
    "SEAM STATUS`tCANDIDATE-NOT-SEALED",
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
foreach ($Target in $Targets) {
    $Row = $Rows[$Target.Path]
    Write-Host "SOURCE:          $($Target.Path)"
    Write-Host "SOURCE SHA256:   $($Row.SHA256)"
}
Write-Host "REPORT:          $Output"
Write-Host "REPORT SHA256:   $ReportHash"
Write-Host 'PASS CONTEXT:    SEALED-DISPLAY'
Write-Host 'PIPELINE OWNER:  LCCCompile-SEALED'
Write-Host 'SEAM:            CANDIDATE-NOT-SEALED'
Write-Host 'PATCH STATUS:    NOT-AUTHORIZED'
Write-Host 'VERDICT:         PASS CONTEXT COMPLETE'
