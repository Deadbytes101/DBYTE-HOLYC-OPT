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

function Get-Sha256Hex {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes
    )

    $Hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [System.Convert]::ToHexString($Hasher.ComputeHash($Bytes))
    }
    finally {
        $Hasher.Dispose()
    }
}

function Get-LineNumber {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [int]$Offset
    )

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

function Get-CodeTokens {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $Tokens = [System.Collections.Generic.List[object]]::new()
    $Symbols = '(){};'
    $Index = 0

    while ($Index -lt $Text.Length) {
        $Ch = $Text[$Index]
        $Next = if ($Index + 1 -lt $Text.Length) { $Text[$Index + 1] } else { [char]0 }

        if ([char]::IsWhiteSpace($Ch)) {
            $Index++
            continue
        }

        if ($Ch -eq '/' -and $Next -eq '/') {
            $Index += 2
            while (
                $Index -lt $Text.Length -and
                $Text[$Index] -ne "`r" -and
                $Text[$Index] -ne "`n"
            ) {
                $Index++
            }
            continue
        }

        if ($Ch -eq '/' -and $Next -eq '*') {
            $CommentOffset = $Index
            $Index += 2
            $Closed = $false
            while ($Index + 1 -lt $Text.Length) {
                if ($Text[$Index] -eq '*' -and $Text[$Index + 1] -eq '/') {
                    $Index += 2
                    $Closed = $true
                    break
                }
                $Index++
            }
            if (-not $Closed) {
                throw "unterminated block comment at offset $CommentOffset"
            }
            continue
        }

        if ($Ch -eq '"' -or $Ch -eq "'") {
            $Quote = $Ch
            $QuoteOffset = $Index
            $Escaped = $false
            $Closed = $false
            $Index++

            while ($Index -lt $Text.Length) {
                $Current = $Text[$Index]
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
                throw "unterminated quoted literal at offset $QuoteOffset"
            }
            continue
        }

        if ($Ch -eq '_' -or [char]::IsLetter($Ch)) {
            $Start = $Index
            $Index++
            while (
                $Index -lt $Text.Length -and
                ($Text[$Index] -eq '_' -or [char]::IsLetterOrDigit($Text[$Index]))
            ) {
                $Index++
            }

            $Tokens.Add([pscustomobject]@{
                Kind = 'ident'
                Text = $Text.Substring($Start, $Index - $Start)
                Offset = $Start
            })
            continue
        }

        if ($Symbols.IndexOf($Ch) -ge 0) {
            $Tokens.Add([pscustomobject]@{
                Kind = 'symbol'
                Text = $Ch.ToString()
                Offset = $Index
            })
        }

        $Index++
    }

    return $Tokens.ToArray()
}

function Find-FunctionDefinitions {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Tokens,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $Definitions = [System.Collections.Generic.List[object]]::new()

    for ($Index = 0; $Index + 1 -lt $Tokens.Count; $Index++) {
        if (
            $Tokens[$Index].Kind -cne 'ident' -or
            $Tokens[$Index].Text -cne $Name -or
            $Tokens[$Index + 1].Text -cne '('
        ) {
            continue
        }

        $OpenIndex = -1
        for ($Probe = $Index + 2; $Probe -lt $Tokens.Count; $Probe++) {
            if ($Tokens[$Probe].Text -ceq ';') {
                break
            }
            if ($Tokens[$Probe].Text -ceq '{') {
                $OpenIndex = $Probe
                break
            }
        }

        if ($OpenIndex -lt 0) {
            continue
        }

        $Depth = 1
        $CloseIndex = -1
        for ($Probe = $OpenIndex + 1; $Probe -lt $Tokens.Count; $Probe++) {
            if ($Tokens[$Probe].Text -ceq '{') {
                $Depth++
            }
            elseif ($Tokens[$Probe].Text -ceq '}') {
                $Depth--
                if ($Depth -eq 0) {
                    $CloseIndex = $Probe
                    break
                }
            }
        }

        if ($CloseIndex -lt 0) {
            throw "unterminated function body for $Name at offset $($Tokens[$Index].Offset)"
        }

        $Definitions.Add([pscustomobject]@{
            NameTokenIndex = $Index
            OpenTokenIndex = $OpenIndex
            CloseTokenIndex = $CloseIndex
        })
        $Index = $CloseIndex
    }

    return $Definitions.ToArray()
}

function Find-Calls {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Tokens,

        [Parameter(Mandatory = $true)]
        [int]$StartIndex,

        [Parameter(Mandatory = $true)]
        [int]$EndIndex,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $Calls = [System.Collections.Generic.List[int]]::new()
    for ($Index = $StartIndex; $Index + 1 -le $EndIndex; $Index++) {
        if (
            $Tokens[$Index].Kind -ceq 'ident' -and
            $Tokens[$Index].Text -ceq $Name -and
            $Tokens[$Index + 1].Text -ceq '('
        ) {
            $Calls.Add($Index)
        }
    }

    return $Calls.ToArray()
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
foreach ($Row in $Rows) {
    $FileBytes = [System.IO.File]::ReadAllBytes($Row.FullPath)
    $Text = [System.Text.Encoding]::Latin1.GetString($FileBytes)
    $Tokens = @(Get-CodeTokens -Text $Text)

    foreach ($Definition in (Find-FunctionDefinitions -Tokens $Tokens -Name 'COCCompile')) {
        $Definitions.Add([pscustomobject]@{
            Row = $Row
            FileBytes = $FileBytes
            Text = $Text
            Tokens = $Tokens
            Definition = $Definition
        })
    }
}

if ($Definitions.Count -ne 1) {
    throw "expected one COCCompile definition in rare compiler corpus; found=$($Definitions.Count)"
}

$Match = $Definitions[0]
$Tokens = $Match.Tokens
$Definition = $Match.Definition
$FunctionStartIndex = $Definition.NameTokenIndex
$FunctionOpenIndex = $Definition.OpenTokenIndex
$FunctionCloseIndex = $Definition.CloseTokenIndex

$Pass6Calls = @(
    Find-Calls `
        -Tokens $Tokens `
        -StartIndex ($FunctionOpenIndex + 1) `
        -EndIndex ($FunctionCloseIndex - 1) `
        -Name 'OptPass6'
)
$Pass789Calls = @(
    Find-Calls `
        -Tokens $Tokens `
        -StartIndex ($FunctionOpenIndex + 1) `
        -EndIndex ($FunctionCloseIndex - 1) `
        -Name 'OptPass789A'
)

if ($Pass6Calls.Count -ne 1) {
    throw "expected one OptPass6 call in COCCompile; found=$($Pass6Calls.Count)"
}
if ($Pass789Calls.Count -eq 0) {
    throw 'OptPass789A call not found in COCCompile'
}

$Pass6TokenIndex = [int]$Pass6Calls[0]
$FirstPass789TokenIndex = [int]($Pass789Calls | Sort-Object | Select-Object -First 1)
if ($Pass6TokenIndex -ge $FirstPass789TokenIndex) {
    throw 'compiler pass order mismatch: OptPass6 is not before OptPass789A'
}

$ParenDepth = 0
$SawOpenParen = $false
$Pass6EndTokenIndex = -1
for ($Index = $Pass6TokenIndex + 1; $Index -lt $FirstPass789TokenIndex; $Index++) {
    switch ($Tokens[$Index].Text) {
        '(' {
            $ParenDepth++
            $SawOpenParen = $true
        }
        ')' {
            $ParenDepth--
            if ($ParenDepth -lt 0) {
                throw 'OptPass6 call has invalid parenthesis depth'
            }
        }
        ';' {
            if ($SawOpenParen -and $ParenDepth -eq 0) {
                $Pass6EndTokenIndex = $Index
                break
            }
        }
    }
    if ($Pass6EndTokenIndex -ge 0) {
        break
    }
}
if ($Pass6EndTokenIndex -lt 0) {
    throw 'unable to find OptPass6 statement end before OptPass789A'
}

$FunctionStartOffset = [int]$Tokens[$FunctionStartIndex].Offset
$FunctionCloseOffset = [int]$Tokens[$FunctionCloseIndex].Offset
$Pass6Offset = [int]$Tokens[$Pass6TokenIndex].Offset
$Pass6EndOffset = [int]$Tokens[$Pass6EndTokenIndex].Offset
$Pass789Offset = [int]$Tokens[$FirstPass789TokenIndex].Offset

$FunctionLength = $FunctionCloseOffset - $FunctionStartOffset + 1
$FunctionText = $Match.Text.Substring($FunctionStartOffset, $FunctionLength)
$FunctionHash = Get-Sha256Hex -Bytes ([System.Text.Encoding]::Latin1.GetBytes($FunctionText))

$FunctionStartLine = Get-LineNumber -Text $Match.Text -Offset $FunctionStartOffset
$FunctionEndLine = Get-LineNumber -Text $Match.Text -Offset $FunctionCloseOffset
$Pass6Line = Get-LineNumber -Text $Match.Text -Offset $Pass6Offset
$Pass789Line = Get-LineNumber -Text $Match.Text -Offset $Pass789Offset
$SeamLine = Get-LineNumber -Text $Match.Text -Offset ($Pass6EndOffset + 1)

$SourceLines = [System.Text.RegularExpressions.Regex]::Split(
    $Match.Text,
    "\r\n|\n|\r"
)
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
    "path`t$($Match.Row.RelativePath)",
    "bytes`t$($Match.Row.Bytes)",
    "sha256`t$($Match.Row.SHA256)",
    "function`tCOCCompile",
    "function_start_line`t$FunctionStartLine",
    "function_end_line`t$FunctionEndLine",
    "function_sha256`t$FunctionHash",
    '',
    'ORDER',
    "OptPass6_line`t$Pass6Line",
    "OptPass6_offset`t$Pass6Offset",
    "OptPass6_statement_end`t$Pass6EndOffset",
    "OptPass789A_first_line`t$Pass789Line",
    "OptPass789A_first_offset`t$Pass789Offset",
    "OptPass789A_call_count`t$($Pass789Calls.Count)",
    "order_verdict`tPASS6-BEFORE-789A",
    '',
    'CANDIDATE SEAM',
    "after_OptPass6_statement_offset`t$($Pass6EndOffset + 1)",
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
Write-Host "SOURCE:         $($Match.Row.RelativePath)"
Write-Host "SOURCE SHA256:  $($Match.Row.SHA256)"
Write-Host "FUNCTION SHA256 $FunctionHash"
Write-Host "REPORT:         $Output"
Write-Host "REPORT SHA256:  $ReportHash"
Write-Host 'PATCH STATUS:   NOT AUTHORIZED'
Write-Host 'VERDICT:        PASS'
