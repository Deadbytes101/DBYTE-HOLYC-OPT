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
$RegexOptions = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant

function Get-Sha256Hex([byte[]]$Bytes) {
    $Hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [System.Convert]::ToHexString($Hasher.ComputeHash($Bytes))
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
    'TEMPLEOSTS 1.10 INTERNAL COMPILER CORPUS',
    "TOOLS_COMMIT`t$ExpectedToolsCommit",
    "ISO_SHA256`t$ExpectedIsoHash",
    "EXTRACTION_LAYER`texpanded",
    "PATCH_AUTHORITY`texpanded historical bytes only"
)) {
    if (-not ($ManifestLines -ccontains $RequiredLine)) {
        throw "compiler manifest missing exact line: $RequiredLine"
    }
}

$SectionIndex = -1
for ($Index = 0; $Index -lt $ManifestLines.Length; $Index++) {
    if ($ManifestLines[$Index] -ceq 'COMPILER FILES') {
        $SectionIndex = $Index
        break
    }
}
if ($SectionIndex -lt 0 -or $SectionIndex + 1 -ge $ManifestLines.Length) {
    throw 'compiler manifest has no COMPILER FILES section'
}
if ($ManifestLines[$SectionIndex + 1] -cne "path`tbytes`tSHA256") {
    throw 'compiler manifest file header mismatch'
}

$Rows = [System.Collections.Generic.List[object]]::new()
$SeenPaths = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
$ExpandedPath = [System.IO.Path]::GetFullPath($Expanded)
$ExpandedPrefix = $ExpandedPath.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar

for ($Index = $SectionIndex + 2; $Index -lt $ManifestLines.Length; $Index++) {
    $Line = $ManifestLines[$Index]
    if ([string]::IsNullOrWhiteSpace($Line) -or $Line -ceq 'BOUNDARY') {
        break
    }

    $Parts = $Line -split "`t", 3
    if ($Parts.Count -ne 3) {
        throw "malformed compiler manifest row: $Line"
    }

    $ExpectedBytes = 0L
    if (-not [long]::TryParse($Parts[1], [ref]$ExpectedBytes)) {
        throw "invalid compiler byte count: $Line"
    }
    if ($Parts[2] -notmatch '^[0-9A-Fa-f]{64}$') {
        throw "invalid compiler SHA256: $Line"
    }
    if (-not $SeenPaths.Add($Parts[0])) {
        throw "duplicate compiler path in manifest: $($Parts[0])"
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
    if ($Item.Length -ne $ExpectedBytes) {
        throw (
            "compiler byte count mismatch: path=$($Parts[0]) " +
            "expected=$ExpectedBytes actual=$($Item.Length)"
        )
    }

    $ExpectedHash = $Parts[2].ToUpperInvariant()
    $ActualHash = (Get-FileHash -LiteralPath $FullPath -Algorithm SHA256).Hash
    if ($ActualHash -cne $ExpectedHash) {
        throw (
            "compiler SHA256 mismatch: path=$($Parts[0]) " +
            "expected=$ExpectedHash actual=$ActualHash"
        )
    }

    $Rows.Add([pscustomobject]@{
        RelativePath = $Parts[0]
        FullPath = $FullPath
        Bytes = $ExpectedBytes
        SHA256 = $ActualHash
    })
}

if ($Rows.Count -eq 0) {
    throw 'compiler manifest contains no files'
}

$Definitions = [System.Collections.Generic.List[object]]::new()
$NamePattern = '(?<![A-Za-z0-9_])COCCompile\s*\('

foreach ($Row in $Rows) {
    $FileBytes = [System.IO.File]::ReadAllBytes($Row.FullPath)
    $Text = [System.Text.Encoding]::Latin1.GetString($FileBytes)
    $Masked = Mask-NonCode $Text

    foreach ($NameMatch in [regex]::Matches($Masked, $NamePattern, $RegexOptions)) {
        $Probe = $NameMatch.Index + $NameMatch.Length
        while ($Probe -lt $Masked.Length -and $Masked[$Probe] -ne '{' -and $Masked[$Probe] -ne ';') {
            $Probe++
        }
        if ($Probe -ge $Masked.Length -or $Masked[$Probe] -eq ';') {
            continue
        }

        $Depth = 1
        $Close = -1
        for ($Cursor = $Probe + 1; $Cursor -lt $Masked.Length; $Cursor++) {
            if ($Masked[$Cursor] -eq '{') {
                $Depth++
            }
            elseif ($Masked[$Cursor] -eq '}') {
                $Depth--
                if ($Depth -eq 0) {
                    $Close = $Cursor
                    break
                }
            }
        }
        if ($Close -lt 0) {
            throw "unterminated COCCompile body in $($Row.RelativePath)"
        }

        $Definitions.Add([pscustomobject]@{
            Row = $Row
            Text = $Text
            Masked = $Masked
            NameOffset = $NameMatch.Index
            OpenOffset = $Probe
            CloseOffset = $Close
        })
    }
}

if ($Definitions.Count -ne 1) {
    throw "expected one COCCompile definition in rare compiler corpus; found=$($Definitions.Count)"
}

$Definition = $Definitions[0]
$BodyLength = $Definition.CloseOffset - $Definition.OpenOffset + 1
$BodyMasked = $Definition.Masked.Substring($Definition.OpenOffset, $BodyLength)
$Pass6Matches = [regex]::Matches(
    $BodyMasked,
    '(?<![A-Za-z0-9_])OptPass6\s*\(',
    $RegexOptions
)
$Pass789Matches = [regex]::Matches(
    $BodyMasked,
    '(?<![A-Za-z0-9_])OptPass789A\s*\(',
    $RegexOptions
)

if ($Pass6Matches.Count -ne 1) {
    throw "expected one OptPass6 call in COCCompile; found=$($Pass6Matches.Count)"
}
if ($Pass789Matches.Count -eq 0) {
    throw 'OptPass789A call not found in COCCompile'
}

$Pass6Offset = $Definition.OpenOffset + $Pass6Matches[0].Index
$Pass789Offset = $Definition.OpenOffset + $Pass789Matches[0].Index
if ($Pass6Offset -ge $Pass789Offset) {
    throw 'compiler pass order mismatch: OptPass6 is not before OptPass789A'
}

$OpenParen = $Definition.Masked.IndexOf('(', $Pass6Offset)
$ParenDepth = 0
$CloseParen = -1
for ($Index = $OpenParen; $Index -lt $Pass789Offset; $Index++) {
    if ($Definition.Masked[$Index] -eq '(') {
        $ParenDepth++
    }
    elseif ($Definition.Masked[$Index] -eq ')') {
        $ParenDepth--
        if ($ParenDepth -eq 0) {
            $CloseParen = $Index
            break
        }
    }
}
if ($OpenParen -lt 0 -or $CloseParen -lt 0) {
    throw 'unable to close OptPass6 call before OptPass789A'
}

$Pass6End = $CloseParen + 1
while ($Pass6End -lt $Pass789Offset -and [char]::IsWhiteSpace($Definition.Masked[$Pass6End])) {
    $Pass6End++
}
if ($Pass6End -ge $Pass789Offset -or $Definition.Masked[$Pass6End] -ne ';') {
    throw 'OptPass6 call is not followed by a semicolon before OptPass789A'
}

$FunctionLength = $Definition.CloseOffset - $Definition.NameOffset + 1
$FunctionText = $Definition.Text.Substring($Definition.NameOffset, $FunctionLength)
$FunctionHash = Get-Sha256Hex ([System.Text.Encoding]::Latin1.GetBytes($FunctionText))

$FunctionStartLine = Get-LineNumber $Definition.Text $Definition.NameOffset
$FunctionEndLine = Get-LineNumber $Definition.Text $Definition.CloseOffset
$Pass6Line = Get-LineNumber $Definition.Text $Pass6Offset
$Pass789Line = Get-LineNumber $Definition.Text $Pass789Offset
$SeamLine = Get-LineNumber $Definition.Text ($Pass6End + 1)

$SourceLines = [regex]::Split($Definition.Text, "\r\n|\n|\r")
$ContextStart = [Math]::Max(1, $Pass6Line - 3)
$ContextEnd = [Math]::Min($SourceLines.Length, $Pass789Line + 3)

$Report = [System.Collections.Generic.List[string]]::new()
foreach ($Line in @(
    'DBYTE-HOLYC-OPT',
    'TEMPLEOSTS 1.10 INTERNAL COMPILER SEAM',
    '',
    'CORPUS',
    "tools_commit`t$ExpectedToolsCommit",
    "iso_sha256`t$ExpectedIsoHash",
    "expanded_root`t$ExpandedPath",
    "compiler_manifest`t$Manifest",
    "compiler_files_verified`t$($Rows.Count)",
    '',
    'SOURCE',
    "path`t$($Definition.Row.RelativePath)",
    "bytes`t$($Definition.Row.Bytes)",
    "sha256`t$($Definition.Row.SHA256)",
    "function`tCOCCompile",
    "function_start_line`t$FunctionStartLine",
    "function_end_line`t$FunctionEndLine",
    "function_sha256`t$FunctionHash",
    '',
    'ORDER',
    "OptPass6_line`t$Pass6Line",
    "OptPass6_offset`t$Pass6Offset",
    "OptPass6_statement_end`t$Pass6End",
    "OptPass789A_first_line`t$Pass789Line",
    "OptPass789A_first_offset`t$Pass789Offset",
    "OptPass789A_call_count`t$($Pass789Matches.Count)",
    "order_verdict`tPASS6-BEFORE-789A",
    '',
    'CANDIDATE SEAM',
    "after_OptPass6_statement_offset`t$($Pass6End + 1)",
    "after_OptPass6_statement_line`t$SeamLine",
    "before_first_OptPass789A_offset`t$Pass789Offset",
    "authorization`tNOT-AUTHORIZED",
    '',
    'CONTEXT DISPLAY ONLY'
)) {
    $Report.Add($Line)
}

for ($LineNumber = $ContextStart; $LineNumber -le $ContextEnd; $LineNumber++) {
    $DisplayLine = $SourceLines[$LineNumber - 1].Replace("`t", '<TAB>')
    $Report.Add(("{0:D6}`t{1}" -f $LineNumber, $DisplayLine))
}

foreach ($Line in @(
    '',
    'BOUNDARY',
    'This report proves exact compiler-file identity, one COCCompile definition,',
    'and the observed ordering of OptPass6 before OptPass789A in that function.',
    'It does not authorize a source patch or claim semantic compatibility.',
    'No source or archive file is modified by this inspector.',
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
Write-Host "COMPILER FILES: $($Rows.Count)/$($Rows.Count)"
Write-Host 'COCCOMPILE:     UNIQUE'
Write-Host 'PASS ORDER:     PASS6-BEFORE-789A'
Write-Host "SOURCE:         $($Definition.Row.RelativePath)"
Write-Host "SOURCE SHA256:  $($Definition.Row.SHA256)"
Write-Host "FUNCTION SHA256 $FunctionHash"
Write-Host "REPORT:         $Output"
Write-Host "REPORT SHA256:  $ReportHash"
Write-Host 'PATCH STATUS:   NOT AUTHORIZED'
Write-Host 'VERDICT:        PASS'
