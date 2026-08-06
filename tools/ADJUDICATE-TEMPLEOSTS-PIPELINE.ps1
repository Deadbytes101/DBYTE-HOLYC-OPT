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
$FunctionPattern = '(?<![A-Za-z0-9_])([A-Za-z_][A-Za-z0-9_]*)\s*\('
$PassPattern = '(?<![A-Za-z0-9_])(OptPass[A-Za-z0-9_]*)\s*\('
$ControlNames = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
foreach ($Name in @(
    'if', 'for', 'while', 'switch', 'catch', 'sizeof', 'offsetof',
    'return', 'break', 'continue', 'goto', 'asm'
)) {
    [void]$ControlNames.Add($Name)
}

function Get-Sha256Hex([byte[]]$Bytes) {
    $Hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $Hash = $Hasher.ComputeHash($Bytes)
        return ([System.BitConverter]::ToString($Hash)).Replace('-', '')
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

function Mask-NonCode([string]$Text) {
    $Chars = $Text.ToCharArray()
    $Index = 0

    while ($Index -lt $Chars.Length) {
        $Ch = $Chars[$Index]
        $Next = if ($Index + 1 -lt $Chars.Length) { $Chars[$Index + 1] } else { [char]0 }

        if ($Ch -eq '/' -and $Next -eq '/') {
            $Chars[$Index] = ' '
            $Chars[$Index + 1] = ' '
            $Index += 2
            while (
                $Index -lt $Chars.Length -and
                $Chars[$Index] -ne "`r" -and
                $Chars[$Index] -ne "`n"
            ) {
                $Chars[$Index] = ' '
                $Index++
            }
            continue
        }

        if ($Ch -eq '/' -and $Next -eq '*') {
            $Start = $Index
            $Chars[$Index] = ' '
            $Chars[$Index + 1] = ' '
            $Index += 2
            $Closed = $false

            while ($Index + 1 -lt $Chars.Length) {
                $Current = $Chars[$Index]
                $Following = $Chars[$Index + 1]
                if ($Current -eq '*' -and $Following -eq '/') {
                    $Chars[$Index] = ' '
                    $Chars[$Index + 1] = ' '
                    $Index += 2
                    $Closed = $true
                    break
                }
                if ($Current -ne "`r" -and $Current -ne "`n") {
                    $Chars[$Index] = ' '
                }
                $Index++
            }

            if (-not $Closed) {
                throw "unterminated block comment at offset $Start"
            }
            continue
        }

        if ($Ch -eq '"' -or $Ch -eq "'") {
            $Quote = $Ch
            $Start = $Index
            $Chars[$Index] = ' '
            $Index++
            $Escaped = $false
            $Closed = $false

            while ($Index -lt $Chars.Length) {
                $Current = $Chars[$Index]
                if ($Current -ne "`r" -and $Current -ne "`n") {
                    $Chars[$Index] = ' '
                }

                if ($Escaped) {
                    $Escaped = $false
                }
                elseif ($Current -eq '\') {
                    $Escaped = $true
                }
                elseif ($Current -eq $Quote) {
                    $Index++
                    $Closed = $true
                    break
                }
                $Index++
            }

            if (-not $Closed) {
                throw "unterminated quoted literal at offset $Start"
            }
            continue
        }

        $Index++
    }

    return (-join $Chars)
}

function Get-FunctionExtents([string]$Masked) {
    $Results = [System.Collections.Generic.List[object]]::new()

    foreach ($Match in [regex]::Matches($Masked, $FunctionPattern, $RegexOptions)) {
        $Name = $Match.Groups[1].Value
        if ($ControlNames.Contains($Name)) {
            continue
        }

        $OpenParen = $Masked.IndexOf('(', $Match.Index)
        if ($OpenParen -lt 0) {
            continue
        }

        $ParenDepth = 0
        $CloseParen = -1
        for ($Index = $OpenParen; $Index -lt $Masked.Length; $Index++) {
            if ($Masked[$Index] -eq '(') {
                $ParenDepth++
            }
            elseif ($Masked[$Index] -eq ')') {
                $ParenDepth--
                if ($ParenDepth -eq 0) {
                    $CloseParen = $Index
                    break
                }
            }
        }
        if ($CloseParen -lt 0) {
            continue
        }

        $Probe = $CloseParen + 1
        while ($Probe -lt $Masked.Length -and [char]::IsWhiteSpace($Masked[$Probe])) {
            $Probe++
        }
        if ($Probe -ge $Masked.Length -or $Masked[$Probe] -ne '{') {
            continue
        }

        $BraceDepth = 1
        $CloseBrace = -1
        for ($Index = $Probe + 1; $Index -lt $Masked.Length; $Index++) {
            if ($Masked[$Index] -eq '{') {
                $BraceDepth++
            }
            elseif ($Masked[$Index] -eq '}') {
                $BraceDepth--
                if ($BraceDepth -eq 0) {
                    $CloseBrace = $Index
                    break
                }
            }
        }
        if ($CloseBrace -lt 0) {
            throw "unterminated function body: $Name offset=$($Match.Index)"
        }

        $Results.Add([pscustomobject]@{
            Name = $Name
            NameOffset = $Match.Groups[1].Index
            OpenBrace = $Probe
            CloseBrace = $CloseBrace
        })
    }

    return @($Results)
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
$Discovery = (Resolve-Path -LiteralPath $DiscoveryPath -ErrorAction Stop).Path
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

$DiscoveryLines = [System.IO.File]::ReadAllLines($Discovery)
foreach ($RequiredLine in @(
    'TEMPLEOSTS 1.10 COMPILER DISCOVERY',
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

$ExpandedPath = [System.IO.Path]::GetFullPath($Expanded)
$ExpandedPrefix = $ExpandedPath.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
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
        throw "compiler candidate file missing: $($Parts[0])"
    }

    $Item = Get-Item -LiteralPath $FullPath
    if ($Item.Length -ne $ExpectedBytes) {
        throw "compiler candidate byte count mismatch: $($Parts[0])"
    }

    $ExpectedHash = $Parts[2].ToUpperInvariant()
    $ActualHash = (Get-FileHash -LiteralPath $FullPath -Algorithm SHA256).Hash
    if ($ActualHash -cne $ExpectedHash) {
        throw "compiler candidate SHA256 mismatch: $($Parts[0])"
    }

    $CompilerRows.Add([pscustomobject]@{
        RelativePath = $Parts[0]
        FullPath = $FullPath
        Bytes = $ExpectedBytes
        SHA256 = $ActualHash
    })
}

if ($CompilerRows.Count -eq 0) {
    throw 'expanded manifest contains no Compiler/ files'
}

foreach ($RequiredPath in @(
    'Compiler/CmpMain.CPP',
    'Compiler/OptPass6.CPP'
)) {
    if (-not @($CompilerRows | Where-Object { $_.RelativePath -ceq $RequiredPath }).Count) {
        throw "observed compiler candidate missing from manifest: $RequiredPath"
    }
}

$CompilerSetLines = @(
    foreach ($Row in ($CompilerRows | Sort-Object RelativePath)) {
        "$($Row.RelativePath)`t$($Row.Bytes)`t$($Row.SHA256)"
    }
)
$CompilerSetHash = Get-Sha256Hex $Latin1.GetBytes(($CompilerSetLines -join "`n") + "`n")
$DiscoveryHash = (Get-FileHash -LiteralPath $Discovery -Algorithm SHA256).Hash

$PassDefinitions = [System.Collections.Generic.List[object]]::new()
$PipelineCandidates = [System.Collections.Generic.List[object]]::new()
$FunctionsOfInterest = [System.Collections.Generic.List[object]]::new()

foreach ($Row in $CompilerRows) {
    if ($Row.Bytes -gt 16MB) {
        continue
    }

    $FileBytes = [System.IO.File]::ReadAllBytes($Row.FullPath)
    $Text = $Latin1.GetString($FileBytes)
    $Masked = Mask-NonCode $Text

    foreach ($Function in (Get-FunctionExtents $Masked)) {
        $Length = $Function.CloseBrace - $Function.NameOffset + 1
        $FunctionText = $Text.Substring($Function.NameOffset, $Length)
        $FunctionMasked = $Masked.Substring($Function.NameOffset, $Length)
        $FunctionHash = Get-Sha256Hex $Latin1.GetBytes($FunctionText)
        $StartLine = Get-LineNumber $Text $Function.NameOffset
        $EndLine = Get-LineNumber $Text $Function.CloseBrace
        $IcCount = Count-Ordinal $FunctionMasked 'CIntermediateCode'

        $PassCalls = [System.Collections.Generic.List[object]]::new()
        foreach ($Match in [regex]::Matches($FunctionMasked, $PassPattern, $RegexOptions)) {
            $AbsoluteOffset = $Function.NameOffset + $Match.Groups[1].Index
            $PassCalls.Add([pscustomobject]@{
                Name = $Match.Groups[1].Value
                Offset = $AbsoluteOffset
                Line = Get-LineNumber $Text $AbsoluteOffset
            })
        }

        if ($Function.Name.StartsWith('OptPass', [System.StringComparison]::Ordinal)) {
            $PassDefinitions.Add([pscustomobject]@{
                Path = $Row.RelativePath
                Name = $Function.Name
                StartLine = $StartLine
                EndLine = $EndLine
                SHA256 = $FunctionHash
            })
        }

        if ($PassCalls.Count -eq 0 -and $IcCount -eq 0) {
            continue
        }

        $CallText = @(
            foreach ($Call in $PassCalls) {
                "$($Call.Name)@$($Call.Line)"
            }
        ) -join ','

        $FunctionsOfInterest.Add([pscustomobject]@{
            Path = $Row.RelativePath
            Name = $Function.Name
            StartLine = $StartLine
            EndLine = $EndLine
            SHA256 = $FunctionHash
            PassCallCount = $PassCalls.Count
            IcCount = $IcCount
            Calls = $CallText
        })

        if ($PassCalls.Count -ge 2) {
            $UniqueCalls = @($PassCalls | Select-Object -ExpandProperty Name -Unique).Count
            $Score = $PassCalls.Count * 100 + $UniqueCalls * 20 + [Math]::Min($IcCount, 50)
            if ($Row.RelativePath -ceq 'Compiler/CmpMain.CPP') {
                $Score += 50
            }

            $PipelineCandidates.Add([pscustomobject]@{
                Score = $Score
                Path = $Row.RelativePath
                Name = $Function.Name
                StartLine = $StartLine
                EndLine = $EndLine
                SHA256 = $FunctionHash
                PassCallCount = $PassCalls.Count
                UniquePassCount = $UniqueCalls
                IcCount = $IcCount
                Calls = $CallText
            })
        }
    }
}

$OrderedDefinitions = @(
    $PassDefinitions |
        Sort-Object `
            @{ Expression = 'Name'; Descending = $false },
            @{ Expression = 'Path'; Descending = $false },
            @{ Expression = 'StartLine'; Descending = $false }
)
$OrderedFunctions = @(
    $FunctionsOfInterest |
        Sort-Object `
            @{ Expression = 'PassCallCount'; Descending = $true },
            @{ Expression = 'IcCount'; Descending = $true },
            @{ Expression = 'Path'; Descending = $false },
            @{ Expression = 'StartLine'; Descending = $false }
)
$OrderedPipelines = @(
    $PipelineCandidates |
        Sort-Object `
            @{ Expression = 'Score'; Descending = $true },
            @{ Expression = 'Path'; Descending = $false },
            @{ Expression = 'StartLine'; Descending = $false }
)

$Report = [System.Collections.Generic.List[string]]::new()
foreach ($Line in @(
    'DBYTE-HOLYC-OPT',
    'TEMPLEOSTS 1.10 COMPILER PIPELINE ADJUDICATION',
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
    '',
    'PASS DEFINITIONS',
    "path`tfunction`tstart_line`tend_line`tfunction_SHA256"
)) {
    $Report.Add($Line)
}

foreach ($Definition in $OrderedDefinitions) {
    $Report.Add(
        "$($Definition.Path)`t$($Definition.Name)`t$($Definition.StartLine)`t" +
        "$($Definition.EndLine)`t$($Definition.SHA256)"
    )
}

foreach ($Line in @(
    '',
    'PIPELINE CANDIDATES',
    "score`tpath`tfunction`tstart_line`tend_line`tfunction_SHA256`tpass_calls`tunique_passes`tIC_refs`tordered_calls"
)) {
    $Report.Add($Line)
}

foreach ($Candidate in $OrderedPipelines) {
    $Report.Add(
        "$($Candidate.Score)`t$($Candidate.Path)`t$($Candidate.Name)`t" +
        "$($Candidate.StartLine)`t$($Candidate.EndLine)`t$($Candidate.SHA256)`t" +
        "$($Candidate.PassCallCount)`t$($Candidate.UniquePassCount)`t" +
        "$($Candidate.IcCount)`t$($Candidate.Calls)"
    )
}

foreach ($Line in @(
    '',
    'FUNCTIONS OF INTEREST',
    "path`tfunction`tstart_line`tend_line`tfunction_SHA256`tpass_calls`tIC_refs`tordered_calls"
)) {
    $Report.Add($Line)
}

foreach ($Function in $OrderedFunctions) {
    $Report.Add(
        "$($Function.Path)`t$($Function.Name)`t$($Function.StartLine)`t" +
        "$($Function.EndLine)`t$($Function.SHA256)`t$($Function.PassCallCount)`t" +
        "$($Function.IcCount)`t$($Function.Calls)"
    )
}

foreach ($Line in @(
    '',
    'BOUNDARY',
    'Compiler/ is an exact candidate file set sealed from the expanded manifest.',
    'Pass definitions and ordered calls are lexical observations from masked bytes.',
    'Pipeline scores are navigation aids and do not identify semantic ownership.',
    'No insertion seam is selected or authorized by this report.',
    'No source, archive, manifest, or discovery file is modified.',
    '',
    "COMPILER SET STATUS`tEXACT-CANDIDATE",
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
Write-Host "COMPILER FILES:      $($CompilerRows.Count)/$($CompilerRows.Count)"
Write-Host "COMPILER SET SHA256: $CompilerSetHash"
Write-Host "PASS DEFINITIONS:    $($OrderedDefinitions.Count)"
Write-Host "FUNCTIONS:           $($OrderedFunctions.Count)"
Write-Host "PIPELINE CANDIDATES: $($OrderedPipelines.Count)"
foreach ($Candidate in @($OrderedPipelines | Select-Object -First 10)) {
    Write-Host (
        "PIPELINE {0}: {1}::{2} lines {3}-{4} calls {5}" -f
        $Candidate.Score,
        $Candidate.Path,
        $Candidate.Name,
        $Candidate.StartLine,
        $Candidate.EndLine,
        $Candidate.Calls
    )
}
Write-Host "REPORT:              $Output"
Write-Host "REPORT SHA256:       $ReportHash"
Write-Host 'COMPILER SET:        EXACT-CANDIDATE'
Write-Host 'PIPELINE:            CANDIDATE-ONLY'
Write-Host 'SEAM:                UNRESOLVED'
Write-Host 'PATCH STATUS:        NOT AUTHORIZED'
Write-Host 'VERDICT:             ADJUDICATION COMPLETE'
