[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$VBoxManagePath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$IsoBootRoot,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$PreparationReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedBaseBlob = '4133358b3e38bee6911fde5e8cf01f408a1d0a85'
$BaseRelative = 'tools/START-TEMPLEOSTS-ISO-BOOT-R1-CONTROLLED.ps1'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$BasePath = Join-Path $RepoRoot ($BaseRelative.Replace('/', [System.IO.Path]::DirectorySeparatorChar))

function Invoke-GitRead {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $Rows = @(
        & git -C $RepoRoot @Arguments 2>&1 |
            ForEach-Object { [string]$_ }
    )
    if ($LASTEXITCODE -ne 0) {
        throw "${Label} failed: $($Rows -join ' | ')"
    }
    return [string[]]$Rows
}

function Get-OrdinalCount {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Needle
    )
    if ($Needle.Length -eq 0) { throw 'empty count needle' }
    $Count = 0
    $Offset = 0
    while ($true) {
        $At = $Text.IndexOf($Needle, $Offset, [System.StringComparison]::Ordinal)
        if ($At -lt 0) { break }
        $Count++
        $Offset = $At + $Needle.Length
    }
    return $Count
}

function Parse-Source {
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
    if (@($Errors).Count -ne 0) {
        throw "${Label} parse failed: $((@($Errors) | ForEach-Object { $_.Message }) -join ' | ')"
    }
    return $Ast
}

function Get-VariableCount {
    param(
        [Parameter(Mandatory = $true)][System.Management.Automation.Language.Ast]$Ast,
        [Parameter(Mandatory = $true)][string]$Name
    )
    return @(
        $Ast.FindAll(
            {
                param($Node)
                $Node -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $Node.VariablePath.UserPath -ceq $Name
            },
            $true
        )
    ).Count
}

if (-not (Test-Path -LiteralPath $BasePath -PathType Leaf)) {
    throw "base ISO start object missing: $BasePath"
}

$Tree = @(Invoke-GitRead -Arguments @('rev-parse', "HEAD`:$BaseRelative") -Label 'base tree blob')
$Local = @(Invoke-GitRead -Arguments @('hash-object', '--', $BaseRelative) -Label 'base local blob')
if (
    $Tree.Count -ne 1 -or
    $Local.Count -ne 1 -or
    $Tree[0].Trim() -cne $ExpectedBaseBlob -or
    $Local[0].Trim() -cne $ExpectedBaseBlob
) {
    throw (
        "base ISO start blob mismatch expected=$ExpectedBaseBlob " +
        "tree=$($Tree -join '|') local=$($Local -join '|')"
    )
}

$Source = [System.IO.File]::ReadAllText($BasePath)
$BaseAst = Parse-Source -Text $Source -Label 'base ISO start object'

$OldToken = '$Home'
$NewToken = '$IsolatedVBoxHome'
$OldTextBefore = Get-OrdinalCount -Text $Source -Needle $OldToken
$NewTextBefore = Get-OrdinalCount -Text $Source -Needle $NewToken
$OldAstBefore = Get-VariableCount -Ast $BaseAst -Name 'Home'
$NewAstBefore = Get-VariableCount -Ast $BaseAst -Name 'IsolatedVBoxHome'
if (
    $OldTextBefore -ne 3 -or
    $NewTextBefore -ne 0 -or
    $OldAstBefore -ne 3 -or
    $NewAstBefore -ne 0
) {
    throw (
        'ISO start HOME hotfix precondition mismatch ' +
        "text_old=$OldTextBefore text_new=$NewTextBefore " +
        "ast_old=$OldAstBefore ast_new=$NewAstBefore"
    )
}

$StartNeedle = "@('startvm',`$ExpectedMachineUuid,'--type','gui')"
$StartBefore = Get-OrdinalCount -Text $Source -Needle $StartNeedle
$ControlVmBefore = Get-OrdinalCount -Text $Source -Needle "'controlvm'"
$StorageAttachBefore = Get-OrdinalCount -Text $Source -Needle "'storageattach'"
if ($StartBefore -ne 1 -or $ControlVmBefore -ne 0 -or $StorageAttachBefore -ne 0) {
    throw (
        'base ISO start mutation-surface mismatch ' +
        "startvm=$StartBefore controlvm=$ControlVmBefore storageattach=$StorageAttachBefore"
    )
}

$Patched = $Source.Replace($OldToken, $NewToken)
$PatchedAst = Parse-Source -Text $Patched -Label 'patched ISO start object'

$OldTextAfter = Get-OrdinalCount -Text $Patched -Needle $OldToken
$NewTextAfter = Get-OrdinalCount -Text $Patched -Needle $NewToken
$OldAstAfter = Get-VariableCount -Ast $PatchedAst -Name 'Home'
$NewAstAfter = Get-VariableCount -Ast $PatchedAst -Name 'IsolatedVBoxHome'
if (
    $OldTextAfter -ne 0 -or
    $NewTextAfter -ne 3 -or
    $OldAstAfter -ne 0 -or
    $NewAstAfter -ne 3
) {
    throw (
        'ISO start HOME hotfix postcondition mismatch ' +
        "text_old=$OldTextAfter text_new=$NewTextAfter " +
        "ast_old=$OldAstAfter ast_new=$NewAstAfter"
    )
}

$StartAfter = Get-OrdinalCount -Text $Patched -Needle $StartNeedle
$ControlVmAfter = Get-OrdinalCount -Text $Patched -Needle "'controlvm'"
$StorageAttachAfter = Get-OrdinalCount -Text $Patched -Needle "'storageattach'"
if ($StartAfter -ne 1 -or $ControlVmAfter -ne 0 -or $StorageAttachAfter -ne 0) {
    throw (
        'patched ISO start mutation-surface mismatch ' +
        "startvm=$StartAfter controlvm=$ControlVmAfter storageattach=$StorageAttachAfter"
    )
}

$Bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Patched)
$Sha = [System.Security.Cryptography.SHA256]::Create()
try {
    $PatchedHash = -join (
        $Sha.ComputeHash($Bytes) |
            ForEach-Object { $_.ToString('X2') }
    )
}
finally {
    $Sha.Dispose()
}

Write-Host "BOUND ISO START BASE:   $ExpectedBaseBlob"
Write-Host 'ROOT CAUSE PREEMPTED:   POWERSHELL HOME IS READ-ONLY / CASE-INSENSITIVE COLLISION'
Write-Host 'CORRECTION:             Home -> IsolatedVBoxHome'
Write-Host 'VARIABLE CARDINALITY:   AST 3 -> 0 / NEW 0 -> 3'
Write-Host 'TEXT CARDINALITY:       3 -> 0 / NEW 0 -> 3'
Write-Host 'STARTVM:                EXACTLY ONE / UNCHANGED'
Write-Host 'CONTROLVM:              NONE'
Write-Host 'STORAGEATTACH:          NONE'
Write-Host "PATCHED START SHA256:   $PatchedHash"

$DynamicStart = [scriptblock]::Create($Patched)
& $DynamicStart `
    -VBoxManagePath $VBoxManagePath `
    -IsoBootRoot $IsoBootRoot `
    -PreparationReportPath $PreparationReportPath `
    -OutPath $OutPath
