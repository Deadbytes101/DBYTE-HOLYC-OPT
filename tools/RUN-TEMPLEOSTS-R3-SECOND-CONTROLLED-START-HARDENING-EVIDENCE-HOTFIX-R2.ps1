[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$VBoxManagePath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$PreparedRoot,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HostReadyReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$FirstAttemptReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedSourceBlob = 'f7a2d82b0e20739cc763fc93b395fa33f7701f27'
$SourceRelative = 'tools/START-TEMPLEOSTS-VDI-ONLY-BOOT-ATTEMPT-R3-SECOND-CONTROLLED.ps1'

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
    throw "bound second-start launcher missing: $SourcePath"
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
        "bound launcher blob mismatch expected=$ExpectedSourceBlob " +
        "tree=$TreeBlob local=$LocalBlob"
    )
}

$Source = [System.IO.File]::ReadAllText($SourcePath)

$OldHardening = @'
function Get-HardeningEvidence {
    param([Parameter(Mandatory = $true)][string]$MachineDir)
    $Path = Join-Path (Join-Path $MachineDir 'Logs') 'VBoxHardening.log'
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ Path = $Path; Hash = ''; Tail = @() }
    }
    $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    $Tail = @(Get-Content -LiteralPath $Path -Tail 80 -ErrorAction Stop)
    return [pscustomobject]@{ Path = $Path; Hash = $Hash; Tail = [string[]]$Tail }
}
'@

$NewHardening = @'
function Get-HardeningEvidence {
    param([Parameter(Mandatory = $true)][string]$MachineDir)
    $Path = Join-Path (Join-Path $MachineDir 'Logs') 'VBoxHardening.log'
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ Path = $Path; Hash = ''; Tail = @(); Error = '' }
    }
    try {
        $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
        $Tail = @(Get-Content -LiteralPath $Path -Tail 80 -ErrorAction Stop)
        return [pscustomobject]@{ Path = $Path; Hash = $Hash; Tail = [string[]]$Tail; Error = '' }
    }
    catch {
        return [pscustomobject]@{
            Path = $Path
            Hash = ''
            Tail = @()
            Error = $_.Exception.Message
        }
    }
}
'@

$OldHardeningReport = @'
    $Lines.Add("hardening_log_sha256`t$($Hardening.Hash)")
    foreach ($Row in $Hardening.Tail) {
'@

$NewHardeningReport = @'
    $Lines.Add("hardening_log_sha256`t$($Hardening.Hash)")
    $Lines.Add("hardening_log_capture_error`t$($Hardening.Error)")
    foreach ($Row in $Hardening.Tail) {
'@

$OldStartBoundary = @'
    $Start = Invoke-Native -FilePath $VBox -Arguments $StartArgs -Label 'second controlled VBoxManage startvm'
    $StartIssued = $true
'@

$NewStartBoundary = @'
    $StartIssued = $true
    $Start = Invoke-Native -FilePath $VBox -Arguments $StartArgs -Label 'second controlled VBoxManage startvm'
'@

$StartCommandNeedle = "$StartArgs = @('startvm', $ExpectedMachineUuid, '--type', 'gui')"

$OldHardeningBefore = Get-OccurrenceCount -Text $Source -Needle $OldHardening
$NewHardeningBefore = Get-OccurrenceCount -Text $Source -Needle $NewHardening
$OldReportBefore = Get-OccurrenceCount -Text $Source -Needle $OldHardeningReport
$NewReportBefore = Get-OccurrenceCount -Text $Source -Needle $NewHardeningReport
$OldStartBefore = Get-OccurrenceCount -Text $Source -Needle $OldStartBoundary
$NewStartBefore = Get-OccurrenceCount -Text $Source -Needle $NewStartBoundary
$StartCommandBefore = Get-OccurrenceCount -Text $Source -Needle $StartCommandNeedle

if (
    $OldHardeningBefore -ne 1 -or $NewHardeningBefore -ne 0 -or
    $OldReportBefore -ne 1 -or $NewReportBefore -ne 0 -or
    $OldStartBefore -ne 1 -or $NewStartBefore -ne 0 -or
    $StartCommandBefore -ne 1
) {
    throw (
        'R2 hotfix precondition mismatch ' +
        "hardening_old=$OldHardeningBefore hardening_new=$NewHardeningBefore " +
        "report_old=$OldReportBefore report_new=$NewReportBefore " +
        "start_old=$OldStartBefore start_new=$NewStartBefore " +
        "start_command=$StartCommandBefore"
    )
}

$PatchedSource = $Source.Replace($OldHardening, $NewHardening)
$PatchedSource = $PatchedSource.Replace($OldHardeningReport, $NewHardeningReport)
$PatchedSource = $PatchedSource.Replace($OldStartBoundary, $NewStartBoundary)

$OldHardeningAfter = Get-OccurrenceCount -Text $PatchedSource -Needle $OldHardening
$NewHardeningAfter = Get-OccurrenceCount -Text $PatchedSource -Needle $NewHardening
$OldReportAfter = Get-OccurrenceCount -Text $PatchedSource -Needle $OldHardeningReport
$NewReportAfter = Get-OccurrenceCount -Text $PatchedSource -Needle $NewHardeningReport
$OldStartAfter = Get-OccurrenceCount -Text $PatchedSource -Needle $OldStartBoundary
$NewStartAfter = Get-OccurrenceCount -Text $PatchedSource -Needle $NewStartBoundary
$StartCommandAfter = Get-OccurrenceCount -Text $PatchedSource -Needle $StartCommandNeedle

if (
    $OldHardeningAfter -ne 0 -or $NewHardeningAfter -ne 1 -or
    $OldReportAfter -ne 0 -or $NewReportAfter -ne 1 -or
    $OldStartAfter -ne 0 -or $NewStartAfter -ne 1 -or
    $StartCommandAfter -ne 1
) {
    throw (
        'R2 hotfix postcondition mismatch ' +
        "hardening_old=$OldHardeningAfter hardening_new=$NewHardeningAfter " +
        "report_old=$OldReportAfter report_new=$NewReportAfter " +
        "start_old=$OldStartAfter start_new=$NewStartAfter " +
        "start_command=$StartCommandAfter"
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
        'patched launcher parse failed: ' +
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

Write-Host "BOUND SECOND LAUNCHER:  $ExpectedSourceBlob"
Write-Host 'CORRECTION 1:           HARDENING LOG CAPTURE BEST-EFFORT'
Write-Host 'CORRECTION 2:           REPORT PATCH USES MULTILINE BOUNDARY'
Write-Host 'CORRECTION 3:           START-ISSUED SET BEFORE STARTVM INVOCATION'
Write-Host 'REPLACEMENTS:           EXACT CARDINALITY 1 -> 1 / 1 -> 1 / 1 -> 1'
Write-Host 'START COMMAND COUNT:    1 -> 1'
Write-Host 'CORE START LOGIC:       OTHERWISE UNCHANGED'
Write-Host 'AUTOMATIC ROLLBACK:     NONE'
Write-Host "PATCHED LAUNCHER SHA:   $PatchedHash"

$Launcher = [scriptblock]::Create($PatchedSource)
& $Launcher `
    -VBoxManagePath $VBoxManagePath `
    -PreparedRoot $PreparedRoot `
    -HostReadyReportPath $HostReadyReportPath `
    -FirstAttemptReportPath $FirstAttemptReportPath `
    -OutPath $OutPath
