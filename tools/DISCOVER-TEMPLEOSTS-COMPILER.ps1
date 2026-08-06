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
$Latin1 = [System.Text.Encoding]::GetEncoding(28591)
$RegexOptions = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
$NamePattern = '(?<![A-Za-z0-9_])([A-Za-z_][A-Za-z0-9_]{2,63})\s*\('
$CompilerWordPattern = '(?i)(compile|compiler|parse|parser|prs|lexer|opcode|codegen|optimizer|optimize|optpass|peephole|intermediate|regalloc|assembler|disasm|jit)'
$PathPattern = '(?i)(^|[\\/._-])(compiler|compile|parser|prs|lexer|opcode|codegen|optimizer|opt|asm|assembler|jit)([\\/._-]|$)'
$LaterAnchors = @('COCCompile', 'OptPass6', 'OptPass789A', 'CIntermediateCode')

function Get-TextRatio([byte[]]$Bytes) {
    if ($Bytes.Length -eq 0) {
        return 1.0
    }

    $TextBytes = 0L
    foreach ($Byte in $Bytes) {
        if (
            $Byte -eq 9 -or
            $Byte -eq 10 -or
            $Byte -eq 13 -or
            ($Byte -ge 32 -and $Byte -le 126)
        ) {
            $TextBytes++
        }
    }
    return [double]$TextBytes / [double]$Bytes.Length
}

function Count-Ordinal([string]$Text, [string]$Needle) {
    $Count = 0
    $Offset = 0
    while ($Offset -lt $Text.Length) {
        $Hit = $Text.IndexOf($Needle, $Offset, [System.StringComparison]::Ordinal)
        if ($Hit -lt 0) {
            break
        }
        $Count++
        $Offset = $Hit + $Needle.Length
    }
    return $Count
}

$Root = (Resolve-Path -LiteralPath $ExtractRoot -ErrorAction Stop).Path
$Manifest = (Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop).Path
$Output = [System.IO.Path]::GetFullPath($OutPath)
$Expanded = Join-Path $Root 'expanded'

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

$SectionIndex = [Array]::IndexOf($ManifestLines, 'FILES')
if ($SectionIndex -lt 0 -or $SectionIndex + 1 -ge $ManifestLines.Length) {
    throw 'expanded manifest has no FILES section'
}
if ($ManifestLines[$SectionIndex + 1] -cne "path`tbytes`tSHA256") {
    throw 'expanded manifest file header mismatch'
}

$ExpandedPath = [System.IO.Path]::GetFullPath($Expanded)
$ExpandedPrefix = $ExpandedPath.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
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

    $ExpectedBytes = 0L
    if (-not [long]::TryParse($Parts[1], [ref]$ExpectedBytes)) {
        throw "invalid byte count in expanded manifest: $Line"
    }
    if ($Parts[2] -notmatch '^[0-9A-Fa-f]{64}$') {
        throw "invalid SHA256 in expanded manifest: $Line"
    }
    if (-not $SeenPaths.Add($Parts[0])) {
        throw "duplicate path in expanded manifest: $($Parts[0])"
    }

    $NativeRelative = $Parts[0].Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $FullPath = [System.IO.Path]::GetFullPath((Join-Path $ExpandedPath $NativeRelative))
    if (-not $FullPath.StartsWith($ExpandedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "manifest path escapes expanded corpus: $($Parts[0])"
    }
    if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) {
        throw "expanded file missing: $($Parts[0])"
    }

    $Item = Get-Item -LiteralPath $FullPath
    if ($Item.Length -ne $ExpectedBytes) {
        throw "expanded byte count mismatch: $($Parts[0])"
    }

    $ExpectedHash = $Parts[2].ToUpperInvariant()
    $ActualHash = (Get-FileHash -LiteralPath $FullPath -Algorithm SHA256).Hash
    if ($ActualHash -cne $ExpectedHash) {
        throw "expanded SHA256 mismatch: $($Parts[0])"
    }

    $Rows.Add([pscustomobject]@{
        RelativePath = $Parts[0]
        FullPath = $FullPath
        Bytes = $ExpectedBytes
        SHA256 = $ActualHash
    })
}

if ($Rows.Count -eq 0) {
    throw 'expanded manifest contains no files'
}

$AnchorCounts = [ordered]@{}
foreach ($Anchor in $LaterAnchors) {
    $AnchorCounts[$Anchor] = 0L
}

$Candidates = [System.Collections.Generic.List[object]]::new()
$TextFileCount = 0

foreach ($Row in $Rows) {
    if ($Row.Bytes -gt 16MB) {
        continue
    }

    $Bytes = [System.IO.File]::ReadAllBytes($Row.FullPath)
    $Ratio = Get-TextRatio $Bytes
    if ($Ratio -lt 0.70) {
        continue
    }

    $TextFileCount++
    $Text = $Latin1.GetString($Bytes)
    foreach ($Anchor in $LaterAnchors) {
        $AnchorCounts[$Anchor] += Count-Ordinal $Text $Anchor
    }

    $Names = [System.Collections.Generic.Dictionary[string, int]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($Match in [regex]::Matches($Text, $NamePattern, $RegexOptions)) {
        $Name = $Match.Groups[1].Value
        if (-not [regex]::IsMatch($Name, $CompilerWordPattern, $RegexOptions)) {
            continue
        }

        if ($Names.ContainsKey($Name)) {
            $Names[$Name]++
        }
        else {
            $Names.Add($Name, 1)
        }
    }

    $PathHit = [regex]::IsMatch($Row.RelativePath, $PathPattern, $RegexOptions)
    if (-not $PathHit -and $Names.Count -eq 0) {
        continue
    }

    $NameRows = @(
        $Names.GetEnumerator() |
            Sort-Object `
                @{ Expression = 'Value'; Descending = $true },
                @{ Expression = 'Key'; Descending = $false } |
            Select-Object -First 24
    )

    $TotalCalls = 0
    foreach ($NameRow in $NameRows) {
        $TotalCalls += $NameRow.Value
    }

    $Score = $Names.Count * 10 + [Math]::Min($TotalCalls, 50)
    if ($PathHit) {
        $Score += 100
    }

    $NameText = @(
        foreach ($NameRow in $NameRows) {
            "$($NameRow.Key):$($NameRow.Value)"
        }
    ) -join ','

    $Candidates.Add([pscustomobject]@{
        Score = $Score
        Path = $Row.RelativePath
        Bytes = $Row.Bytes
        SHA256 = $Row.SHA256
        TextRatio = $Ratio
        FunctionNames = $NameText
    })
}

$OrderedCandidates = @(
    $Candidates |
        Sort-Object `
            @{ Expression = 'Score'; Descending = $true },
            @{ Expression = 'Path'; Descending = $false }
)

$Report = [System.Collections.Generic.List[string]]::new()
foreach ($Line in @(
    'DBYTE-HOLYC-OPT',
    'TEMPLEOSTS 1.10 COMPILER DISCOVERY',
    '',
    'CORPUS',
    "tools_commit`t$ExpectedToolsCommit",
    "iso_sha256`t$ExpectedIsoHash",
    "expanded_root`t$ExpandedPath",
    "expanded_manifest`t$Manifest",
    "expanded_files_verified`t$($Rows.Count)",
    "text_like_files`t$TextFileCount",
    '',
    'LATER ERA ANCHORS'
)) {
    $Report.Add($Line)
}

foreach ($Anchor in $LaterAnchors) {
    $Report.Add("$Anchor`t$($AnchorCounts[$Anchor])")
}

foreach ($Line in @(
    '',
    'CANDIDATES',
    "score`tpath`tbytes`tSHA256`ttext_ratio`tfunction_names"
)) {
    $Report.Add($Line)
}

foreach ($Candidate in $OrderedCandidates) {
    $RatioText = $Candidate.TextRatio.ToString(
        '0.0000',
        [System.Globalization.CultureInfo]::InvariantCulture
    )
    $Report.Add(
        "$($Candidate.Score)`t$($Candidate.Path)`t$($Candidate.Bytes)`t" +
        "$($Candidate.SHA256)`t$RatioText`t$($Candidate.FunctionNames)"
    )
}

foreach ($Line in @(
    '',
    'BOUNDARY',
    'This report catalogs exact expanded files and compiler-like function names.',
    'Candidate scores are navigation aids, not proof of compiler ownership.',
    'Later-era anchor absence is evidence against reusing the 5.03 seam names.',
    'No compiler source, optimizer pass, or insertion seam is selected here.',
    'No source or archive file is modified by this discovery pass.',
    '',
    "COMPILER STATUS`tUNRESOLVED",
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
Write-Host "EXPANDED FILES: $($Rows.Count)/$($Rows.Count)"
Write-Host "TEXT FILES:     $TextFileCount"
Write-Host "CANDIDATES:     $($OrderedCandidates.Count)"
foreach ($Anchor in $LaterAnchors) {
    Write-Host ("ANCHOR {0}: {1}" -f $Anchor, $AnchorCounts[$Anchor])
}
Write-Host "REPORT:         $Output"
Write-Host "REPORT SHA256:  $ReportHash"
Write-Host 'COMPILER:       UNRESOLVED'
Write-Host 'SEAM:           UNRESOLVED'
Write-Host 'PATCH STATUS:   NOT AUTHORIZED'
Write-Host 'VERDICT:        DISCOVERY COMPLETE'
