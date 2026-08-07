[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$IncompleteRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PreservedR1Root,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PreparationReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedInspectorBlob = 'efaecd9ca56042e927a457596da487484ceefb77'
$InspectorRelative = 'tools/INSPECT-TEMPLEOSTS-VDI-ONLY-BOOT-INCOMPLETE-R2.ps1'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$InspectorPath = Join-Path $RepoRoot (
    $InspectorRelative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
)

function Invoke-GitRead {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Captured = @(
        & git -C $RepoRoot @Arguments 2>&1 |
            ForEach-Object { [string]$_ }
    )
    if ($LASTEXITCODE -ne 0) {
        throw "${Label} failed`n$($Captured -join "`n")"
    }
    return $Captured
}

function Get-ParsedAst {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Tokens = $null
    $Errors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseInput(
        $Text,
        [ref]$Tokens,
        [ref]$Errors
    )
    $ParseErrors = @($Errors)
    if ($ParseErrors.Count -ne 0) {
        throw (
            "${Label} PowerShell parse failed: " +
            (($ParseErrors | ForEach-Object { $_.Message }) -join ' | ')
        )
    }
    return $Ast
}

function Get-ExactNewLine {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $CrLfCount = [regex]::Matches($Text, "`r`n").Count
    $BareLfCount = [regex]::Matches($Text, "(?<!`r)`n").Count
    if (
        ($CrLfCount -gt 0 -and $BareLfCount -gt 0) -or
        ($CrLfCount -eq 0 -and $BareLfCount -eq 0)
    ) {
        throw (
            "${Label} newline style is mixed or absent: " +
            "crlf=$CrLfCount bare_lf=$BareLfCount"
        )
    }
    if ($CrLfCount -gt 0) {
        return "`r`n"
    }
    return "`n"
}

function Convert-ToNewLine {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$NewLine,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Normalized = $Text.Replace("`r`n", "`n")
    if ($Normalized.Contains("`r")) {
        throw "${Label} contains unsupported standalone carriage return"
    }
    if ($NewLine -ceq "`n") {
        return $Normalized
    }
    if ($NewLine -ceq "`r`n") {
        return $Normalized.Replace("`n", "`r`n")
    }
    throw "${Label} requested unsupported newline representation"
}

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Text)

    $Bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Text)
    $Sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return (
            [System.BitConverter]::ToString($Sha.ComputeHash($Bytes))
        ).Replace('-', '')
    }
    finally {
        $Sha.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $InspectorPath -PathType Leaf)) {
    throw "failed inspector missing: $InspectorPath"
}

$TreeBlob = @(
    Invoke-GitRead `
        -Arguments @('rev-parse', "HEAD`:$InspectorRelative") `
        -Label 'failed inspector tree blob'
)
$LocalBlob = @(
    Invoke-GitRead `
        -Arguments @('hash-object', '--', $InspectorRelative) `
        -Label 'failed inspector local blob'
)
if (
    $TreeBlob.Count -ne 1 -or
    $LocalBlob.Count -ne 1 -or
    $TreeBlob[0] -cne $ExpectedInspectorBlob -or
    $LocalBlob[0] -cne $ExpectedInspectorBlob
) {
    throw (
        'failed inspector blob mismatch: ' +
        "tree=$($TreeBlob -join '|') local=$($LocalBlob -join '|')"
    )
}

$Source = [System.IO.File]::ReadAllText($InspectorPath)
$NewLine = Get-ExactNewLine -Text $Source -Label 'failed inspector source'
$InitialAst = Get-ParsedAst -Text $Source -Label 'bound failed inspector'

$Functions = @(
    $InitialAst.FindAll(
        {
            param($Node)
            $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $Node.Name -ceq 'Add-NodeAttributes'
        },
        $true
    )
)
if ($Functions.Count -ne 1) {
    throw "Add-NodeAttributes function count mismatch: $($Functions.Count)"
}

$Function = $Functions[0]
$FunctionStart = [int]$Function.Extent.StartOffset
$FunctionEnd = [int]$Function.Extent.EndOffset
if (
    $FunctionStart -lt 0 -or
    $FunctionEnd -le $FunctionStart -or
    $FunctionEnd -gt $Source.Length
) {
    throw (
        'Add-NodeAttributes extent invalid: ' +
        "start=$FunctionStart end=$FunctionEnd length=$($Source.Length)"
    )
}

$FunctionText = $Source.Substring(
    $FunctionStart,
    $FunctionEnd - $FunctionStart
)
$OldSignature = '[Parameter(Mandatory = $true)][System.Collections.Generic.List[string]]$Lines,'
$NewSignature = '[Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowEmptyString()][System.Collections.Generic.List[string]]$Lines,'
$OldSignatureCount = [regex]::Matches(
    $FunctionText,
    [regex]::Escape($OldSignature),
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
).Count
$NewSignatureCountBefore = [regex]::Matches(
    $FunctionText,
    [regex]::Escape($NewSignature),
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
).Count
if ($OldSignatureCount -ne 1 -or $NewSignatureCountBefore -ne 0) {
    throw (
        'Add-NodeAttributes Lines signature cardinality mismatch: ' +
        "old=$OldSignatureCount new_before=$NewSignatureCountBefore"
    )
}

$CorrectedFunction = $FunctionText.Replace(
    $OldSignature,
    $NewSignature
)
$Patched = (
    $Source.Substring(0, $FunctionStart) +
    $CorrectedFunction +
    $Source.Substring($FunctionEnd)
)

$AfterLinesAst = Get-ParsedAst `
    -Text $Patched `
    -Label 'inspector after Lines binding correction'

$AssignmentNames = @('HomeFiles', 'HomeDirectories')
$Assignments = [System.Collections.Generic.List[object]]::new()
foreach ($Name in $AssignmentNames) {
    $Matches = @(
        $AfterLinesAst.FindAll(
            {
                param($Node)
                $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $Node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $Node.Left.VariablePath.UserPath -ceq $Name
            },
            $true
        )
    )
    if ($Matches.Count -ne 1) {
        throw "${Name} assignment count mismatch: $($Matches.Count)"
    }
    $Assignments.Add([pscustomobject]@{
        Name = $Name
        Node = $Matches[0]
    })
}

$HomeFilesReplacement = @'
$HomeFiles = @(
    if (Test-Path -LiteralPath $VBoxUserHome -PathType Container) {
        Get-ChildItem -LiteralPath $VBoxUserHome -Recurse -Force -File |
            Sort-Object FullName
    }
)
'@
$HomeDirectoriesReplacement = @'
$HomeDirectories = @(
    if (Test-Path -LiteralPath $VBoxUserHome -PathType Container) {
        Get-ChildItem -LiteralPath $VBoxUserHome -Recurse -Force -Directory |
            Sort-Object FullName
    }
)
'@
$ReplacementByName = @{
    HomeFiles = Convert-ToNewLine `
        -Text $HomeFilesReplacement.TrimEnd("`r", "`n") `
        -NewLine $NewLine `
        -Label 'HomeFiles replacement'
    HomeDirectories = Convert-ToNewLine `
        -Text $HomeDirectoriesReplacement.TrimEnd("`r", "`n") `
        -NewLine $NewLine `
        -Label 'HomeDirectories replacement'
}

$OrderedAssignments = @(
    $Assignments |
        Sort-Object { [int]$_.Node.Extent.StartOffset } -Descending
)
foreach ($Entry in $OrderedAssignments) {
    $Start = [int]$Entry.Node.Extent.StartOffset
    $End = [int]$Entry.Node.Extent.EndOffset
    if ($Start -lt 0 -or $End -le $Start -or $End -gt $Patched.Length) {
        throw (
            "$($Entry.Name) assignment extent invalid: " +
            "start=$Start end=$End length=$($Patched.Length)"
        )
    }

    $Observed = $Patched.Substring($Start, $End - $Start)
    $ExpectedPrefix = '$' + $Entry.Name + ' = if ('
    if (-not $Observed.StartsWith(
        $ExpectedPrefix,
        [System.StringComparison]::Ordinal
    )) {
        throw (
            "$($Entry.Name) assignment extent text mismatch: " +
            "expected_prefix=$ExpectedPrefix"
        )
    }

    $Patched = (
        $Patched.Substring(0, $Start) +
        [string]$ReplacementByName[$Entry.Name] +
        $Patched.Substring($End)
    )
}

$FinalAst = Get-ParsedAst `
    -Text $Patched `
    -Label 'final materialized r2 inspector'

$FinalFunctions = @(
    $FinalAst.FindAll(
        {
            param($Node)
            $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $Node.Name -ceq 'Add-NodeAttributes'
        },
        $true
    )
)
if ($FinalFunctions.Count -ne 1) {
    throw "final Add-NodeAttributes function count mismatch: $($FinalFunctions.Count)"
}
if (
    [regex]::Matches(
        $FinalFunctions[0].Extent.Text,
        [regex]::Escape($NewSignature),
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    ).Count -ne 1
) {
    throw 'final Lines binding correction proof failed'
}

foreach ($Name in $AssignmentNames) {
    $Matches = @(
        $FinalAst.FindAll(
            {
                param($Node)
                $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $Node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $Node.Left.VariablePath.UserPath -ceq $Name
            },
            $true
        )
    )
    if ($Matches.Count -ne 1) {
        throw "final ${Name} assignment count mismatch: $($Matches.Count)"
    }
    $ExpectedFinalPrefix = '$' + $Name + ' = @('
    if (-not $Matches[0].Extent.Text.StartsWith(
        $ExpectedFinalPrefix,
        [System.StringComparison]::Ordinal
    )) {
        throw "final ${Name} materialization proof failed"
    }
}

$PatchedHash = Get-TextSha256 -Text $Patched
$Inspector = [scriptblock]::Create($Patched)
$InvokeArguments = @{
    IncompleteRoot = $IncompleteRoot
    PreservedR1Root = $PreservedR1Root
    PreparationReportPath = $PreparationReportPath
    OutPath = $OutPath
}

Write-Host "BOUND FAILED INSPECTOR: $ExpectedInspectorBlob"
Write-Host 'LINES CORRECTION:       ALLOW EMPTY COLLECTION + EMPTY STRING'
Write-Host 'COLLECTION CORRECTION:  HOMEFILES + HOMEDIRECTORIES OUTER ARRAY'
Write-Host 'ASSIGNMENT CLASSIFIER:  POWERSHELL AST / EXACT VARIABLE NAME'
Write-Host 'ASSIGNMENT REPLACEMENT: DESCENDING AST OFFSET SPLICE'
Write-Host 'INSPECTION LOGIC:       OTHERWISE UNCHANGED'
Write-Host 'VBOXMANAGE SURFACE:     NONE'
Write-Host "PATCHED INSPECTOR SHA:  $PatchedHash"
& $Inspector @InvokeArguments
