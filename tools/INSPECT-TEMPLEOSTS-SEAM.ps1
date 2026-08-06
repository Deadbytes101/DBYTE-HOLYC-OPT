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
        $Hash = $Hasher.ComputeHash($Bytes)
    }
    finally {
        $Hasher.Dispose()
    }

    return ([System.Convert]::ToHexString($Hash))
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

function Find-FunctionExtent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [int]$NameOffset
    )

    $State = 0
    $Escaped = $false
    $OpenOffset = -1

    :FindOpen for ($Index = $NameOffset; $Index -lt $Text.Length; $Index++) {
        $Ch = $Text[$Index]
        $Next = if ($Index + 1 -lt $Text.Length) { $Text[$Index + 1] } else { [char]0 }

        switch ($State) {
            0 {
                if ($Ch -eq '/' -and $Next -eq '/') {
                    $State = 1
                    $Index++
                }
                elseif ($Ch -eq '/' -and $Next -eq '*') {
                    $State = 2
                    $Index++
                }
                elseif ($Ch -eq '"') {
                    $State = 3
                    $Escaped = $false
                }
                elseif ($Ch -eq "'") {
                    $State = 4
                    $Escaped = $false
                }
                elseif ($Ch -eq ';') {
                    return $null
                }
                elseif ($Ch -eq '{') {
                    $OpenOffset = $Index
                    break FindOpen
                }
            }
            1 {
                if ($Ch -eq "`r" -or $Ch -eq "`n") {
                    $State = 0
                }
            }
            2 {
                if ($Ch -eq '*' -and $Next -eq '/') {
                    $State = 0
                    $Index++
                }
            }
            3 {
                if ($Escaped) {
                    $Escaped = $false
                }
                elseif ($Ch -eq '\') {
                    $Escaped = $true
                }
                elseif ($Ch -eq '"') {
                    $State = 0
                }
            }
            4 {
                if ($Escaped) {
                    $Escaped = $false
                }
                elseif ($Ch -eq '\') {
                    $Escaped = $true
                }
                elseif ($Ch -eq "'") {
                    $State = 0
                }
            }
        }
    }

    if ($OpenOffset -lt 0) {
        return $null
    }

    $Depth = 1
    $State = 0
    $Escaped = $false

    for ($Index = $OpenOffset + 1; $Index -lt $Text.Length; $Index++) {
        $Ch = $Text[$Index]
        $Next = if ($Index + 1 -lt $Text.Length) { $Text[$Index + 1] } else { [char]0 }

        switch ($State) {
            0 {
                if ($Ch -eq '/' -and $Next -eq '/') {
                    $State = 1
                    $Index++
                }
                elseif ($Ch -eq '/' -and $Next -eq '*') {
                    $State = 2
                    $Index++
                }
                elseif ($Ch -eq '"') {
                    $State = 3
                    $Escaped = $false
                }
                elseif ($Ch -eq "'") {
                    $State = 4
                    $Escaped = $false
                }
                elseif ($Ch -eq '{') {
                    $Depth++
                }
                elseif ($Ch -eq '}') {
                    $Depth--
                    if ($Depth -eq 0) {
                        return [pscustomobject]@{
                            NameOffset = $NameOffset
                            OpenOffset = $OpenOffset
                            CloseOffset = $Index
                        }
                    }
                }
            }
            1 {
                if ($Ch -eq "`r" -or $Ch -eq "`n") {
                    $State = 0
                }
            }
            2 {
                if ($Ch -eq '*' -and $Next -eq '/') {
                    $State = 0
                    $Index++
                }
            }
            3 {
                if ($Escaped) {
                    $Escaped = $false
                }
                elseif ($Ch -eq '\') {
                    $Escaped = $true
                }
                elseif ($Ch -eq '"') {
                    $State = 0
                }
            }
            4 {
                if ($Escaped) {
                    $Escaped = $false
                }
                elseif ($Ch -eq '\') {
                    $Escaped = $true
                }
                elseif ($Ch -eq "'") {
                    $State = 0
                }
            }
        }
    }

    return $null
}

function Find-CodeDefinitions {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $Results = [System.Collections.Generic.List[object]]::new()
    $State = 0
    $Escaped = $false

    for ($Index = 0; $Index -lt $Text.Length; $Index++) {
        $Ch = $Text[$Index]
        $Next = if ($Index + 1 -lt $Text.Length) { $Text[$Index + 1] } else { [char]0 }

        switch ($State) {
            0 {
                if ($Ch -eq '/' -and $Next -eq '/') {
                    $State = 1
                    $Index++
                    continue
                }
                if ($Ch -eq '/' -and $Next -eq '*') {
                    $State = 2
                    $Index++
                    continue
                }
                if ($Ch -eq '"') {
                    $State = 3
                    $Escaped = $false
                    continue
                }
                if ($Ch -eq "'") {
                    $State = 4
                    $Escaped = $false
                    continue
                }

                if ($Ch -eq '_' -or [char]::IsLetter($Ch)) {
                    $Start = $Index
                    while (
                        $Index + 1 -lt $Text.Length -and
                        ($Text[$Index + 1] -eq '_' -or [char]::IsLetterOrDigit($Text[$Index + 1]))
                    ) {
                        $Index++
                    }

                    $Identifier = $Text.Substring($Start, $Index - $Start + 1)
                    if ($Identifier -cne $Name) {
                        continue
                    }

                    $Look = $Index + 1
                    while ($Look -lt $Text.Length -and [char]::IsWhiteSpace($Text[$Look])) {
                        $Look++
                    }
                    if ($Look -ge $Text.Length -or $Text[$Look] -ne '(') {
                        continue
                    }

                    $Extent = Find-FunctionExtent -Text $Text -NameOffset $Start
                    if ($null -ne $Extent) {
                        $Results.Add($Extent)
                        $Index = $Extent.CloseOffset
                    }
                }
            }
            1 {
                if ($Ch -eq "`r" -or $Ch -eq "`n") {
                    $State = 0
                }
            }
            2 {
                if ($Ch -eq '*' -and $Next -eq '/') {
                    $State = 0
                    $Index++
                }
            }
            3 {
                if ($Escaped) {
                    $Escaped = $false
                }
                elseif ($Ch -eq '\') {
                    $Escaped = $true
                }
                elseif ($Ch -eq '"') {
                    $State = 0
                }
            }
            4 {
                if ($Escaped) {
                    $Escaped = $false
                }
                elseif ($Ch -eq '\') {
                    $Escaped = $true
                }
                elseif ($Ch -eq "'") {
                    $State = 0
                }
            }
        }
    }

    return @($Results)
}

function Find-CodeCalls {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [int]$StartOffset,

        [Parameter(Mandatory = $true)]
        [int]$EndOffset,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $Offsets = [System.Collections.Generic.List[int]]::new()
    $State = 0
    $Escaped = $false

    for ($Index = $StartOffset; $Index -le $EndOffset; $Index++) {
        $Ch = $Text[$Index]
        $Next = if ($Index + 1 -le $EndOffset) { $Text[$Index + 1] } else { [char]0 }

        switch ($State) {
            0 {
                if ($Ch -eq '/' -and $Next -eq '/') {
                    $State = 1
                    $Index++
                    continue
                }
                if ($Ch -eq '/' -and $Next -eq '*') {
                    $State = 2
                    $Index++
                    continue
                }
                if ($Ch -eq '"') {
                    $State = 3
                    $Escaped = $false
                    continue
                }
                if ($Ch -eq "'") {
                    $State = 4
                    $Escaped = $false
                    continue
                }

                if ($Ch -eq '_' -or [char]::IsLetter($Ch)) {
                    $IdentifierStart = $Index
                    while (
                        $Index + 1 -le $EndOffset -and
                        ($Text[$Index + 1] -eq '_' -or [char]::IsLetterOrDigit($Text[$Index + 1]))
                    ) {
                        $Index++
                    }

                    $Identifier = $Text.Substring(
                        $IdentifierStart,
                        $Index - $IdentifierStart + 1
                    )
                    if ($Identifier -cne $Name) {
                        continue
                    }

                    $Look = $Index + 1
                    while ($Look -le $EndOffset -and [char]::IsWhiteSpace($Text[$Look])) {
                        $Look++
                    }
                    if ($Look -le $EndOffset -and $Text[$Look] -eq '(') {
                        $Offsets.Add($IdentifierStart)
                    }
                }
            }
            1 {
                if ($Ch -eq "`r" -or $Ch -eq "`n") {
                    $State = 0
                }
            }
            2 {
                if ($Ch -eq '*' -and $Next -eq '/') {
                    $State = 0
                    $Index++
                }
            }
            3 {
                if ($Escaped) {
                    $Escaped = $false
                }
                elseif ($Ch -eq '\') {
                    $Escaped = $true
                }
                elseif ($Ch -eq '"') {
                    $State = 0
                }
            }
            4 {
                if ($Escaped) {
                    $Escaped = $false
                }
                elseif ($Ch -eq '\') {
                    $Escaped = $true
                }
                elseif ($Ch -eq "'") {
                    $State = 0
                }
            }
        }
    }

    return @($Offsets)
}

function Find-StatementEnd {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [int]$CallOffset,

        [Parameter(Mandatory = $true)]
        [int]$EndOffset
    )

    $State = 0
    $Escaped = $false
    $ParenDepth = 0
    $SawOpenParen = $false

    for ($Index = $CallOffset; $Index -le $EndOffset; $Index++) {
        $Ch = $Text[$Index]
        $Next = if ($Index + 1 -le $EndOffset) { $Text[$Index + 1] } else { [char]0 }

        switch ($State) {
            0 {
                if ($Ch -eq '/' -and $Next -eq '/') {
                    $State = 1
                    $Index++
                }
                elseif ($Ch -eq '/' -and $Next -eq '*') {
                    $State = 2
                    $Index++
                }
                elseif ($Ch -eq '"') {
                    $State = 3
                    $Escaped = $false
                }
                elseif ($Ch -eq "'") {
                    $State = 4
                    $Escaped = $false
                }
                elseif ($Ch -eq '(') {
                    $ParenDepth++
                    $SawOpenParen = $true
                }
                elseif ($Ch -eq ')') {
                    $ParenDepth--
                    if ($ParenDepth -lt 0) {
                        return -1
                    }
                }
                elseif ($Ch -eq ';' -and $SawOpenParen -and $ParenDepth -eq 0) {
                    return $Index
                }
            }
            1 {
                if ($Ch -eq "`r" -or $Ch -eq "`n") {
                    $State = 0
                }
            }
            2 {
                if ($Ch -eq '*' -and $Next -eq '/') {
                    $State = 0
                    $Index++
                }
            }
            3 {
                if ($Escaped) {
                    $Escaped = $false
                }
                elseif ($Ch -eq '\') {
                    $Escaped = $true
                }
                elseif ($Ch -eq '"') {
                    $State = 0
                }
            }
            4 {
                if ($Escaped) {
                    $Escaped = $false
                }
                elseif ($Ch -eq '\') {
                    $Escaped = $true
                }
                elseif ($Ch -eq "'") {
                    $State = 0
                }
            }
        }
    }

    return -1
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
    'EXTRACTION_LAYER`texpanded',
    'PATCH_AUTHORITY`texpanded historical bytes only'
)) {
    if (-not ($ManifestLines -ccontains $RequiredLine)) {
        throw "compiler manifest missing exact line: $RequiredLine"
    }
}

$SectionIndex = [Array]::IndexOf($ManifestLines, 'COMPILER FILES')
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

    $RelativePath = $Parts[0]
    $ExpectedBytes = 0L
    if (-not [long]::TryParse($Parts[1], [ref]$ExpectedBytes)) {
        throw "invalid compiler byte count: $Line"
    }
    if ($Parts[2] -notmatch '^[0-9A-Fa-f]{64}$') {
        throw "invalid compiler SHA256: $Line"
    }
    if (-not $SeenPaths.Add($RelativePath)) {
        throw "duplicate compiler path in manifest: $RelativePath"
    }

    $NativeRelative = $RelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $FullPath = [System.IO.Path]::GetFullPath((Join-Path $ExpandedPath $NativeRelative))
    if (-not $FullPath.StartsWith($ExpandedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "compiler path escapes expanded corpus: $RelativePath"
    }
    if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) {
        throw "compiler file missing: $RelativePath"
    }

    $Item = Get-Item -LiteralPath $FullPath
    if ($Item.Length -ne $ExpectedBytes) {
        throw (
            "compiler byte count mismatch: path=$RelativePath " +
            "expected=$ExpectedBytes actual=$($Item.Length)"
        )
    }

    $ActualHash = (Get-FileHash -LiteralPath $FullPath -Algorithm SHA256).Hash
    if ($ActualHash -cne $Parts[2].ToUpperInvariant()) {
        throw (
            "compiler SHA256 mismatch: path=$RelativePath " +
            "expected=$($Parts[2]) actual=$ActualHash"
        )
    }

    $Rows.Add([pscustomobject]@{
        RelativePath = $RelativePath
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
    foreach ($Extent in (Find-CodeDefinitions -Text $Text -Name 'COCCompile')) {
        $Definitions.Add([pscustomobject]@{
            Row = $Row
            Bytes = $FileBytes
            Text = $Text
            Extent = $Extent
        })
    }
}

if ($Definitions.Count -ne 1) {
    throw "expected one COCCompile definition in rare compiler corpus; found=$($Definitions.Count)"
}

$Definition = $Definitions[0]
$Text = $Definition.Text
$Extent = $Definition.Extent
$FunctionStart = $Extent.NameOffset
$FunctionEnd = $Extent.CloseOffset

$Pass6Calls = @(
    Find-CodeCalls `
        -Text $Text `
        -StartOffset $Extent.OpenOffset `
        -EndOffset $FunctionEnd `
        -Name 'OptPass6'
)
$Pass789Calls = @(
    Find-CodeCalls `
        -Text $Text `
        -StartOffset $Extent.OpenOffset `
        -EndOffset $FunctionEnd `
        -Name 'OptPass789A'
)

if ($Pass6Calls.Count -ne 1) {
    throw "expected one OptPass6 call in COCCompile; found=$($Pass6Calls.Count)"
}
if ($Pass789Calls.Count -eq 0) {
    throw 'OptPass789A call not found in COCCompile'
}

$Pass6Offset = [int]$Pass6Calls[0]
$FirstPass789Offset = [int]($Pass789Calls | Sort-Object | Select-Object -First 1)
if ($Pass6Offset -ge $FirstPass789Offset) {
    throw (
        "compiler pass order mismatch: OptPass6=$Pass6Offset " +
        "first-OptPass789A=$FirstPass789Offset"
    )
}

$Pass6StatementEnd = Find-StatementEnd `
    -Text $Text `
    -CallOffset $Pass6Offset `
    -EndOffset $FunctionEnd
if ($Pass6StatementEnd -lt 0 -or $Pass6StatementEnd -ge $FirstPass789Offset) {
    throw 'unable to seal end of OptPass6 statement before OptPass789A'
}

$FunctionLength = $FunctionEnd - $FunctionStart + 1
$FunctionText = $Text.Substring($FunctionStart, $FunctionLength)
$FunctionBytes = [System.Text.Encoding]::Latin1.GetBytes($FunctionText)
$FunctionHash = Get-Sha256Hex -Bytes $FunctionBytes

$FunctionStartLine = Get-LineNumber -Text $Text -Offset $FunctionStart
$FunctionEndLine = Get-LineNumber -Text $Text -Offset $FunctionEnd
$Pass6Line = Get-LineNumber -Text $Text -Offset $Pass6Offset
$Pass789Line = Get-LineNumber -Text $Text -Offset $FirstPass789Offset
$SeamAfterLine = Get-LineNumber -Text $Text -Offset ($Pass6StatementEnd + 1)

$SourceLines = [System.Text.RegularExpressions.Regex]::Split($Text, "\r\n|\n|\r")
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
    "OptPass6_statement_end`t$Pass6StatementEnd",
    "OptPass789A_first_line`t$Pass789Line",
    "OptPass789A_first_offset`t$FirstPass789Offset",
    "OptPass789A_call_count`t$($Pass789Calls.Count)",
    "order_verdict`tPASS6-BEFORE-789A",
    '',
    'CANDIDATE SEAM',
    "after_OptPass6_statement_offset`t$($Pass6StatementEnd + 1)",
    "after_OptPass6_statement_line`t$SeamAfterLine",
    "before_first_OptPass789A_offset`t$FirstPass789Offset",
    "authorization`tNOT-AUTHORIZED",
    '',
    'CONTEXT DISPLAY ONLY'
)) {
    $Report.Add($Line)
}

for ($LineNumber = $ContextStart; $LineNumber -le $ContextEnd; $LineNumber++) {
    $DisplayLine = $SourceLines[$LineNumber - 1].Replace("`t", '<TAB>')
    $Report.Add(('{0:D6}`t{1}' -f $LineNumber, $DisplayLine))
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
Write-Host "COCCOMPILE:     UNIQUE"
Write-Host "PASS ORDER:     PASS6-BEFORE-789A"
Write-Host "SOURCE:         $($Definition.Row.RelativePath)"
Write-Host "SOURCE SHA256:  $($Definition.Row.SHA256)"
Write-Host "FUNCTION SHA256 $FunctionHash"
Write-Host "REPORT:         $Output"
Write-Host "REPORT SHA256:  $ReportHash"
Write-Host "PATCH STATUS:   NOT AUTHORIZED"
Write-Host "VERDICT:        PASS"
