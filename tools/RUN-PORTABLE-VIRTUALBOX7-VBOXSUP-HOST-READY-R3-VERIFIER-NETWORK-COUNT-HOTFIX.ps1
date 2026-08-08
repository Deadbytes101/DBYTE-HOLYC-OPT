[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$VBoxManagePath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$PortableVirtualBoxRoot,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$PreparedRoot,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$MutationReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$FailedBootAttemptReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$PreparedVerificationReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$BootAuthorizationReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedSourceBlob = '9d2cce9702aed0b955a779a07d3b61f78097933b'
$SourceRelative = 'tools/VERIFY-PORTABLE-VIRTUALBOX7-VBOXSUP-HOST-READY-R3.ps1'

function Get-OccurrenceCount {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Needle
    )
    if ($Needle.Length -eq 0) { throw 'empty occurrence needle' }
    $Count = 0
    $Offset = 0
    while ($true) {
        $Found = $Text.IndexOf($Needle, $Offset, [System.StringComparison]::Ordinal)
        if ($Found -lt 0) { break }
        $Count++
        $Offset = $Found + $Needle.Length
    }
    return $Count
}

$RepoRoot = Split-Path -Parent $PSScriptRoot
$SourcePath = Join-Path $RepoRoot $SourceRelative
if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    throw "bound verifier missing: $SourcePath"
}

$TreeRows = @(& git -C $RepoRoot rev-parse "HEAD:$SourceRelative" 2>&1 | ForEach-Object { [string]$_ })
if ($LASTEXITCODE -ne 0 -or $TreeRows.Count -ne 1) {
    throw "tree blob query failed: $($TreeRows -join ' | ')"
}
$TreeBlob = $TreeRows[0].Trim()

$LocalRows = @(& git -C $RepoRoot hash-object -- $SourceRelative 2>&1 | ForEach-Object { [string]$_ })
if ($LASTEXITCODE -ne 0 -or $LocalRows.Count -ne 1) {
    throw "local blob query failed: $($LocalRows -join ' | ')"
}
$LocalBlob = $LocalRows[0].Trim()

if ($TreeBlob -cne $ExpectedSourceBlob -or $LocalBlob -cne $ExpectedSourceBlob) {
    throw "bound verifier blob mismatch expected=$ExpectedSourceBlob tree=$TreeBlob local=$LocalBlob"
}

$Source = [System.IO.File]::ReadAllText($SourcePath)
$Old = 'Write-Host "NETWORK DISABLED:       $([bool](($NicKeys | Where-Object { [string]$Map[$_] -cne ''none'' }).Count -eq 0))"'
$New = @'
$EnabledNicKeysForConsole = @(
    $NicKeys | Where-Object { [string]$Map[$_] -cne 'none' }
)
$NetworkDisabledForConsole = ($EnabledNicKeysForConsole.Count -eq 0)
Write-Host "NETWORK DISABLED:       $NetworkDisabledForConsole"
'@

$OldBefore = Get-OccurrenceCount -Text $Source -Needle $Old
$NewBefore = Get-OccurrenceCount -Text $Source -Needle $New
if ($OldBefore -ne 1 -or $NewBefore -ne 0) {
    throw "network-count patch precondition mismatch: old=$OldBefore new=$NewBefore"
}

$PatchedSource = $Source.Replace($Old, $New)
$OldAfter = Get-OccurrenceCount -Text $PatchedSource -Needle $Old
$NewAfter = Get-OccurrenceCount -Text $PatchedSource -Needle $New
if ($OldAfter -ne 0 -or $NewAfter -ne 1) {
    throw "network-count patch postcondition mismatch: old=$OldAfter new=$NewAfter"
}

$Tokens = $null
$ParseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput(
    $PatchedSource,
    [ref]$Tokens,
    [ref]$ParseErrors
)
if ($ParseErrors.Count -ne 0) {
    throw 'patched verifier parse failed: ' + (($ParseErrors | ForEach-Object { $_.Message }) -join ' | ')
}

$PatchedBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($PatchedSource)
$Sha = [System.Security.Cryptography.SHA256]::Create()
try {
    $PatchedHash = -join ($Sha.ComputeHash($PatchedBytes) | ForEach-Object { $_.ToString('X2') })
}
finally {
    $Sha.Dispose()
}

Write-Host "BOUND VERIFIER BASE:    $ExpectedSourceBlob"
Write-Host 'CORRECTION:             FINAL NIC COUNT MATERIALIZED WITH @()'
Write-Host 'REPLACEMENT:            EXACT SOURCE CARDINALITY 1 -> 1'
Write-Host 'CORE VERIFICATION:      OTHERWISE UNCHANGED'
Write-Host 'SC MUTATION:            NONE'
Write-Host 'VM START:               NONE'
Write-Host "PATCHED VERIFIER SHA:   $PatchedHash"

$Verifier = [scriptblock]::Create($PatchedSource)
& $Verifier `
    -VBoxManagePath $VBoxManagePath `
    -PortableVirtualBoxRoot $PortableVirtualBoxRoot `
    -PreparedRoot $PreparedRoot `
    -MutationReportPath $MutationReportPath `
    -FailedBootAttemptReportPath $FailedBootAttemptReportPath `
    -PreparedVerificationReportPath $PreparedVerificationReportPath `
    -BootAuthorizationReportPath $BootAuthorizationReportPath `
    -OutPath $OutPath
