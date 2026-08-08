[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$VBoxManagePath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$PreparedRoot,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$SecondAttemptReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedBaseBlob = '06f7270ab7b8d97fc9a3fce06f3e86ed65375398'
$BaseRelative = 'tools/STOP-TEMPLEOSTS-R3-NO-BOOTABLE-MEDIUM-CONTROLLED.ps1'
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
    throw "base stop object missing: $BasePath"
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
        "base stop blob mismatch expected=$ExpectedBaseBlob " +
        "tree=$($Tree -join '|') local=$($Local -join '|')"
    )
}

$Source = [System.IO.File]::ReadAllText($BasePath)
$BaseAst = Parse-Source -Text $Source -Label 'base stop object'

$OldToken = '$Home'
$NewToken = '$IsolatedVBoxHome'
$OldTextBefore = Get-OrdinalCount -Text $Source -Needle $OldToken
$NewTextBefore = Get-OrdinalCount -Text $Source -Needle $NewToken
$OldAstBefore = Get-VariableCount -Ast $BaseAst -Name 'Home'
$NewAstBefore = Get-VariableCount -Ast $BaseAst -Name 'IsolatedVBoxHome'

if (
    $OldTextBefore -ne 4 -or
    $NewTextBefore -ne 0 -or
    $OldAstBefore -ne 4 -or
    $NewAstBefore -ne 0
) {
    throw (
        'HOME hotfix precondition mismatch ' +
        "text_old=$OldTextBefore text_new=$NewTextBefore " +
        "ast_old=$OldAstBefore ast_new=$NewAstBefore"
    )
}

$PoweroffNeedle = "@('controlvm', `$ExpectedMachineUuid, 'poweroff')"
$PoweroffBefore = Get-OrdinalCount -Text $Source -Needle $PoweroffNeedle
$StartVmBefore = Get-OrdinalCount -Text $Source -Needle "'startvm'"
$StorageAttachBefore = Get-OrdinalCount -Text $Source -Needle "'storageattach'"
if ($PoweroffBefore -ne 1 -or $StartVmBefore -ne 0 -or $StorageAttachBefore -ne 0) {
    throw (
        'base mutation-surface mismatch ' +
        "poweroff=$PoweroffBefore startvm=$StartVmBefore storageattach=$StorageAttachBefore"
    )
}

$Patched = $Source.Replace($OldToken, $NewToken)
$PatchedAst = Parse-Source -Text $Patched -Label 'patched stop object'

$OldTextAfter = Get-OrdinalCount -Text $Patched -Needle $OldToken
$NewTextAfter = Get-OrdinalCount -Text $Patched -Needle $NewToken
$OldAstAfter = Get-VariableCount -Ast $PatchedAst -Name 'Home'
$NewAstAfter = Get-VariableCount -Ast $PatchedAst -Name 'IsolatedVBoxHome'

if (
    $OldTextAfter -ne 0 -or
    $NewTextAfter -ne 4 -or
    $OldAstAfter -ne 0 -or
    $NewAstAfter -ne 4
) {
    throw (
        'HOME hotfix postcondition mismatch ' +
        "text_old=$OldTextAfter text_new=$NewTextAfter " +
        "ast_old=$OldAstAfter ast_new=$NewAstAfter"
    )
}

$PoweroffAfter = Get-OrdinalCount -Text $Patched -Needle $PoweroffNeedle
$StartVmAfter = Get-OrdinalCount -Text $Patched -Needle "'startvm'"
$StorageAttachAfter = Get-OrdinalCount -Text $Patched -Needle "'storageattach'"
if (
    $PoweroffAfter -ne 1 -or
    $StartVmAfter -ne 0 -or
    $StorageAttachAfter -ne 0
) {
    throw (
        'patched mutation-surface mismatch ' +
        "poweroff=$PoweroffAfter startvm=$StartVmAfter storageattach=$StorageAttachAfter"
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

Write-Host "BOUND STOP BASE:        $ExpectedBaseBlob"
Write-Host 'ROOT CAUSE:             POWERSHELL HOME IS READ-ONLY / CASE-INSENSITIVE COLLISION'
Write-Host 'CORRECTION:             Home -> IsolatedVBoxHome'
Write-Host 'VARIABLE CARDINALITY:   AST 4 -> 0 / NEW 0 -> 4'
Write-Host 'TEXT CARDINALITY:       4 -> 0 / NEW 0 -> 4'
Write-Host 'CONTROLVM POWEROFF:     EXACTLY ONE / UNCHANGED'
Write-Host 'STARTVM:                NONE'
Write-Host 'STORAGEATTACH:          NONE'
Write-Host "PATCHED STOP SHA256:    $PatchedHash"

$DynamicStop = [scriptblock]::Create($Patched)
& $DynamicStop `
    -VBoxManagePath $VBoxManagePath `
    -PreparedRoot $PreparedRoot `
    -SecondAttemptReportPath $SecondAttemptReportPath `
    -OutPath $OutPath
