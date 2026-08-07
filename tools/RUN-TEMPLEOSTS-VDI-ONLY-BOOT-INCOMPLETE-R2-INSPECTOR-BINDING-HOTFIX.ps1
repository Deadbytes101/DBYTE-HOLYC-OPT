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
$Ast = Get-ParsedAst -Text $Source -Label 'bound failed inspector'
$Functions = @(
    $Ast.FindAll(
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
$Start = [int]$Function.Extent.StartOffset
$End = [int]$Function.Extent.EndOffset
if ($Start -lt 0 -or $End -le $Start -or $End -gt $Source.Length) {
    throw "Add-NodeAttributes extent invalid: start=$Start end=$End length=$($Source.Length)"
}

$FunctionText = $Source.Substring($Start, $End - $Start)
$OldSignature = '[Parameter(Mandatory = $true)][System.Collections.Generic.List[string]]$Lines,'
$NewSignature = '[Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowEmptyString()][System.Collections.Generic.List[string]]$Lines,'
$OldCount = [regex]::Matches(
    $FunctionText,
    [regex]::Escape($OldSignature),
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
).Count
$NewCountBefore = [regex]::Matches(
    $FunctionText,
    [regex]::Escape($NewSignature),
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
).Count
if ($OldCount -ne 1 -or $NewCountBefore -ne 0) {
    throw (
        'Add-NodeAttributes Lines signature cardinality mismatch: ' +
        "old=$OldCount new_before=$NewCountBefore"
    )
}

$CorrectedFunction = $FunctionText.Replace($OldSignature, $NewSignature)
$OldAfter = [regex]::Matches(
    $CorrectedFunction,
    [regex]::Escape($OldSignature),
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
).Count
$NewAfter = [regex]::Matches(
    $CorrectedFunction,
    [regex]::Escape($NewSignature),
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
).Count
if ($OldAfter -ne 0 -or $NewAfter -ne 1) {
    throw (
        'Add-NodeAttributes Lines signature replacement mismatch: ' +
        "old_after=$OldAfter new_after=$NewAfter"
    )
}

$Patched = (
    $Source.Substring(0, $Start) +
    $CorrectedFunction +
    $Source.Substring($End)
)
$FinalAst = Get-ParsedAst -Text $Patched -Label 'corrected r2 inspector'
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
    throw "corrected Add-NodeAttributes function count mismatch: $($FinalFunctions.Count)"
}
$FinalFunctionText = $FinalFunctions[0].Extent.Text
if (
    [regex]::Matches(
        $FinalFunctionText,
        [regex]::Escape($NewSignature),
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    ).Count -ne 1
) {
    throw 'corrected Lines binding attribute proof failed'
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
Write-Host 'CORRECTION:             Add-NodeAttributes Lines allows blank separator rows'
Write-Host 'FUNCTION CLASSIFIER:    POWERSHELL AST / EXACT NAME'
Write-Host 'FUNCTION REPLACEMENT:   AST STARTOFFSET/ENDOFFSET SPLICE'
Write-Host 'LINES CONTRACT:         ALLOW EMPTY COLLECTION + EMPTY STRING'
Write-Host 'INSPECTION LOGIC:       UNCHANGED'
Write-Host 'VBOXMANAGE SURFACE:     NONE'
Write-Host "PATCHED INSPECTOR SHA:  $PatchedHash"
& $Inspector @InvokeArguments
