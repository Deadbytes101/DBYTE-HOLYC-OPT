[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$VBoxManagePath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$PortableVirtualBoxRoot,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$PreparedRoot,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$MutationReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$FailedBootAttemptReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$PreparedVerificationReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$BootAuthorizationReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$StorageProbeReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedSourceBlob = '9d2cce9702aed0b955a779a07d3b61f78097933b'
$SourceRelative = 'tools/VERIFY-PORTABLE-VIRTUALBOX7-VBOXSUP-HOST-READY-R3.ps1'
$ExpectedStorageProbeReport = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-portable-vbox-r3-storage-surface-probe.txt'
$ExpectedStorageProbeHash = '4520FE5ECFA74E21395A84C0BDA0BAA7606C505259043C50BF9A8CD3B5FE34F8'

function Get-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath(
        [Environment]::ExpandEnvironmentVariables($Path)
    ).TrimEnd([char]92, [char]47)
}

function Assert-PathEquals {
    param(
        [Parameter(Mandatory = $true)][string]$Observed,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not [string]::Equals(
        (Get-FullPath -Path $Observed),
        (Get-FullPath -Path $Expected),
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "${Label} mismatch: observed=$Observed expected=$Expected"
    }
}

function Get-OccurrenceCount {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Needle
    )
    if ($Needle.Length -eq 0) {
        throw 'empty occurrence needle'
    }
    $Count = 0
    $Offset = 0
    while ($true) {
        $Found = $Text.IndexOf(
            $Needle,
            $Offset,
            [System.StringComparison]::Ordinal
        )
        if ($Found -lt 0) {
            break
        }
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

$TreeRows = @(
    & git -C $RepoRoot rev-parse "HEAD:$SourceRelative" 2>&1 |
        ForEach-Object { [string]$_ }
)
if ($LASTEXITCODE -ne 0 -or $TreeRows.Count -ne 1) {
    throw "tree blob query failed: $($TreeRows -join ' | ')"
}
$TreeBlob = $TreeRows[0].Trim()

$LocalRows = @(
    & git -C $RepoRoot hash-object -- $SourceRelative 2>&1 |
        ForEach-Object { [string]$_ }
)
if ($LASTEXITCODE -ne 0 -or $LocalRows.Count -ne 1) {
    throw "local blob query failed: $($LocalRows -join ' | ')"
}
$LocalBlob = $LocalRows[0].Trim()

if ($TreeBlob -cne $ExpectedSourceBlob -or $LocalBlob -cne $ExpectedSourceBlob) {
    throw (
        "bound verifier blob mismatch expected=$ExpectedSourceBlob " +
        "tree=$TreeBlob local=$LocalBlob"
    )
}

$StorageProbeReport = (
    Resolve-Path -LiteralPath $StorageProbeReportPath -ErrorAction Stop
).Path
Assert-PathEquals `
    -Observed $StorageProbeReport `
    -Expected $ExpectedStorageProbeReport `
    -Label 'storage probe report'

$StorageProbeHash = (
    Get-FileHash -LiteralPath $StorageProbeReport -Algorithm SHA256
).Hash
if ($StorageProbeHash -cne $ExpectedStorageProbeHash) {
    throw (
        "storage probe report SHA256 mismatch " +
        "observed=$StorageProbeHash expected=$ExpectedStorageProbeHash"
    )
}

$Source = [System.IO.File]::ReadAllText($SourcePath)

$OldKey = '        $Key = $Matches[1]'
$NewKey = @'
        $Key = [string]$Matches[1]
        if (
            $Key.Length -ge 2 -and
            $Key[0] -eq [char]34 -and
            $Key[$Key.Length - 1] -eq [char]34
        ) {
            $Key = $Key.Substring(1, $Key.Length - 2)
        }
'@

$OldNetwork = 'Write-Host "NETWORK DISABLED:       $([bool](($NicKeys | Where-Object { [string]$Map[$_] -cne ''none'' }).Count -eq 0))"'
$NewNetwork = @'
$EnabledNicKeysForConsole = @(
    $NicKeys | Where-Object { [string]$Map[$_] -cne 'none' }
)
$NetworkDisabledForConsole = ($EnabledNicKeysForConsole.Count -eq 0)
Write-Host "NETWORK DISABLED:       $NetworkDisabledForConsole"
'@

$OldKeyBefore = Get-OccurrenceCount -Text $Source -Needle $OldKey
$NewKeyBefore = Get-OccurrenceCount -Text $Source -Needle $NewKey
$OldNetworkBefore = Get-OccurrenceCount -Text $Source -Needle $OldNetwork
$NewNetworkBefore = Get-OccurrenceCount -Text $Source -Needle $NewNetwork

if (
    $OldKeyBefore -ne 1 -or
    $NewKeyBefore -ne 0 -or
    $OldNetworkBefore -ne 1 -or
    $NewNetworkBefore -ne 0
) {
    throw (
        'patch precondition mismatch ' +
        "old_key=$OldKeyBefore new_key=$NewKeyBefore " +
        "old_network=$OldNetworkBefore new_network=$NewNetworkBefore"
    )
}

$PatchedSource = $Source.Replace($OldKey, $NewKey)
$PatchedSource = $PatchedSource.Replace($OldNetwork, $NewNetwork)

$OldKeyAfter = Get-OccurrenceCount -Text $PatchedSource -Needle $OldKey
$NewKeyAfter = Get-OccurrenceCount -Text $PatchedSource -Needle $NewKey
$OldNetworkAfter = Get-OccurrenceCount -Text $PatchedSource -Needle $OldNetwork
$NewNetworkAfter = Get-OccurrenceCount -Text $PatchedSource -Needle $NewNetwork

if (
    $OldKeyAfter -ne 0 -or
    $NewKeyAfter -ne 1 -or
    $OldNetworkAfter -ne 0 -or
    $NewNetworkAfter -ne 1
) {
    throw (
        'patch postcondition mismatch ' +
        "old_key=$OldKeyAfter new_key=$NewKeyAfter " +
        "old_network=$OldNetworkAfter new_network=$NewNetworkAfter"
    )
}

$Tokens = $null
$ParseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput(
    $PatchedSource,
    [ref]$Tokens,
    [ref]$ParseErrors
)
if ($ParseErrors.Count -ne 0) {
    throw (
        'patched verifier parse failed: ' +
        (($ParseErrors | ForEach-Object { $_.Message }) -join ' | ')
    )
}

$PatchedBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($PatchedSource)
$Sha = [System.Security.Cryptography.SHA256]::Create()
try {
    $PatchedHash = -join (
        $Sha.ComputeHash($PatchedBytes) |
            ForEach-Object { $_.ToString('X2') }
    )
}
finally {
    $Sha.Dispose()
}

Write-Host "BOUND VERIFIER BASE:    $ExpectedSourceBlob"
Write-Host "BOUND STORAGE PROBE:    $StorageProbeHash"
Write-Host 'CORRECTION 1:           STRIP SURROUNDING QUOTES FROM MR KEYS'
Write-Host 'CORRECTION 2:           FINAL NIC COUNT MATERIALIZED WITH @()'
Write-Host 'REPLACEMENTS:           EXACT SOURCE CARDINALITY 1 -> 1 / 1 -> 1'
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
