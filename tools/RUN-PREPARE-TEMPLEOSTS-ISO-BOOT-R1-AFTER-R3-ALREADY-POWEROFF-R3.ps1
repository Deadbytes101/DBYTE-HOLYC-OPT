[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$VBoxManagePath,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$R3Root,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$R3PoweroffAdjudicationReportPath,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$SealedRehearsalRoot,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$RehearsalVerificationReportPath,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$BootReadinessReportPath,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$IsoBootRoot,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$ExpectedBaseBlob='bd1ec076b0a34cf32792ffab39c7ced7697f5254'
$BaseRelative='tools/PREPARE-TEMPLEOSTS-ISO-BOOT-R1-AFTER-R3-STOP.ps1'
$RepoRoot=Split-Path -Parent $PSScriptRoot
$BasePath=Join-Path $RepoRoot ($BaseRelative.Replace('/',[System.IO.Path]::DirectorySeparatorChar))

function Get-Count {
    param([string]$Text,[string]$Needle)
    if($Needle.Length -eq 0){throw 'empty needle'}
    $Count=0;$Offset=0
    while($true){$At=$Text.IndexOf($Needle,$Offset,[System.StringComparison]::Ordinal);if($At -lt 0){break};$Count++;$Offset=$At+$Needle.Length}
    return $Count
}
function Apply-Patch {
    param([string]$Text,[string]$Old,[string]$New,[string]$Label)
    $OldBefore=Get-Count $Text $Old;$NewBefore=Get-Count $Text $New
    if($OldBefore -ne 1 -or $NewBefore -ne 0){throw "R3 precondition mismatch $Label old=$OldBefore new=$NewBefore"}
    $Patched=$Text.Replace($Old,$New)
    $OldAfter=Get-Count $Patched $Old;$NewAfter=Get-Count $Patched $New
    if($OldAfter -ne 0 -or $NewAfter -ne 1){throw "R3 postcondition mismatch $Label old=$OldAfter new=$NewAfter"}
    return $Patched
}

if(-not(Test-Path -LiteralPath $BasePath -PathType Leaf)){throw "base ISO preparer missing: $BasePath"}
$Tree=@(& git -C $RepoRoot rev-parse "HEAD:$BaseRelative" 2>&1|ForEach-Object{[string]$_});if($LASTEXITCODE -ne 0 -or $Tree.Count -ne 1){throw 'base tree blob query failed'}
$Local=@(& git -C $RepoRoot hash-object -- $BaseRelative 2>&1|ForEach-Object{[string]$_});if($LASTEXITCODE -ne 0 -or $Local.Count -ne 1){throw 'base local blob query failed'}
if($Tree[0].Trim() -cne $ExpectedBaseBlob -or $Local[0].Trim() -cne $ExpectedBaseBlob){throw "base preparer blob mismatch expected=$ExpectedBaseBlob tree=$($Tree[0]) local=$($Local[0])"}

$Source=[System.IO.File]::ReadAllText($BasePath)

$OldExpected=@'
$ExpectedR3StopReport = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r3-controlled-stop-after-no-boot.txt'
'@
$NewExpected=@'
$ExpectedR3StopReport = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r3-already-poweroff-after-no-boot-adjudication.txt'
'@
$Source=Apply-Patch $Source $OldExpected $NewExpected 'truthful-poweroff-report-path'

$OldStopGate=@'
$StopLines = [System.IO.File]::ReadAllLines($StopReport)
if ((Get-TabValue -Lines $StopLines -Key 'second_attempt_report_sha256') -cne $ExpectedSecondAttemptHash) { throw 'R3 stop report second-attempt binding mismatch' }
if ((Get-TabValue -Lines $StopLines -Key 'poweroff_exit_code') -cne '0') { throw 'R3 stop report poweroff exit is not zero' }
if ((Get-TabValue -Lines $StopLines -Key 'CONTROLVM') -cne 'POWEROFF-ONCE') { throw 'R3 stop report controlvm field mismatch' }
if ((Get-TabValue -Lines $StopLines -Key 'STATUS') -cne 'R3-POWERED-OFF-PRESERVED') { throw 'R3 stop report status mismatch' }
$StopReportHash = (Get-FileHash -LiteralPath $StopReport -Algorithm SHA256).Hash
'@
$NewStopGate=@'
$StopLines = [System.IO.File]::ReadAllLines($StopReport)
if ((Get-TabValue -Lines $StopLines -Key 'second_attempt_report_sha256') -cne $ExpectedSecondAttemptHash) { throw 'R3 poweroff adjudication second-attempt binding mismatch' }
if ((Get-TabValue -Lines $StopLines -Key 'running_vm_rows') -cne '0') { throw 'R3 poweroff adjudication running row count mismatch' }
if ((Get-TabValue -Lines $StopLines -Key 'machine_state') -cne 'poweroff') { throw 'R3 poweroff adjudication VMState mismatch' }
if ((Get-TabValue -Lines $StopLines -Key 'CONTROLVM') -cne 'NOT-EXECUTED') { throw 'R3 poweroff adjudication controlvm field mismatch' }
if ((Get-TabValue -Lines $StopLines -Key 'STATUS') -cne 'R3-ALREADY-POWEROFF-PRESERVED') { throw 'R3 poweroff adjudication status mismatch' }
$StopReportHash = (Get-FileHash -LiteralPath $StopReport -Algorithm SHA256).Hash
'@
$Source=Apply-Patch $Source $OldStopGate $NewStopGate 'truthful-poweroff-report-contract'

$OldSnapshot=@'
    if ($Result.ExitCode -eq 0) { return [string[]]@($Result.Output | Where-Object { $_.Trim().Length -gt 0 }) }
'@
$NewSnapshot=@'
    if ($Result.ExitCode -eq 0) {
        return [string[]]@(
            $Result.Output |
                Where-Object { $_ -match '^Snapshot(Name|UUID|Node)' }
        )
    }
'@
$Source=Apply-Patch $Source $OldSnapshot $NewSnapshot 'snapshot-filter'

$OldRuntime=@'
Wait-VBoxSVCExit

$MachineRoot = Join-Path $NewRoot 'Machine'
'@
$NewRuntime=@'
Wait-VBoxSVCExit
$RuntimeProcesses = @(
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProcessName -match '(?i)^(VBoxSVC|VirtualBoxVM|VBoxHeadless|VirtualBox)$'
        }
)
if ($RuntimeProcesses.Count -ne 0) {
    throw (
        'VirtualBox runtime process remains before fresh ISO preparation: ' +
        (($RuntimeProcesses | ForEach-Object { "$($_.ProcessName):$($_.Id)" }) -join ', ')
    )
}

$MachineRoot = Join-Path $NewRoot 'Machine'
'@
$Source=Apply-Patch $Source $OldRuntime $NewRuntime 'runtime-process-gate'

$OldEarlyRemove=@'
    Remove-Item -LiteralPath $IncompletePath -Force -ErrorAction Stop

    $Report = [System.Collections.Generic.List[string]]::new()
'@
$NewEarlyRemove=@'
    $Steps.Add('MANIFEST-WRITTEN-INCOMPLETE-MARKER-RETAINED')

    $Report = [System.Collections.Generic.List[string]]::new()
'@
$Source=Apply-Patch $Source $OldEarlyRemove $NewEarlyRemove 'retain-incomplete-marker'

$OldReportHash=@'
    $OutputHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

    Write-Host "R3 STOP REPORT SHA256:  $StopReportHash"
'@
$NewReportHash=@'
    $OutputHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash
    Remove-Item -LiteralPath $IncompletePath -Force -ErrorAction Stop

    Write-Host "R3 POWEROFF EVIDENCE:   $StopReportHash"
'@
$Source=Apply-Patch $Source $OldReportHash $NewReportHash 'remove-marker-after-report-hash'

$Tokens=$null;$ParseErrors=$null
[void][System.Management.Automation.Language.Parser]::ParseInput($Source,[ref]$Tokens,[ref]$ParseErrors)
if(@($ParseErrors).Count -ne 0){throw 'patched ISO preparer parse failed: '+((@($ParseErrors)|ForEach-Object{$_.Message}) -join ' | ')}
if((Get-Count $Source "'startvm'") -ne 0){throw 'patched preparer unexpectedly contains startvm'}

$Bytes=[System.Text.UTF8Encoding]::new($false).GetBytes($Source);$Sha=[System.Security.Cryptography.SHA256]::Create()
try{$PatchedHash=-join($Sha.ComputeHash($Bytes)|ForEach-Object{$_.ToString('X2')})}finally{$Sha.Dispose()}

Write-Host "BOUND ISO PREPARER:     $ExpectedBaseBlob"
Write-Host 'POWER STATE CONTRACT:   ALREADY POWEROFF / CONTROLVM NOT EXECUTED'
Write-Host 'CORRECTION 1:           TRUTHFUL POWEROFF ADJUDICATION REPORT BINDING'
Write-Host 'CORRECTION 2:           SNAPSHOT ROWS FILTERED TO ACTUAL SNAPSHOT KEYS'
Write-Host 'CORRECTION 3:           NO VBOX RUNTIME PROCESS BEFORE NEW ISOLATED HOME'
Write-Host 'CORRECTION 4:           INCOMPLETE MARKER RETAINED UNTIL REPORT HASHED'
Write-Host 'VM START:               NONE'
Write-Host "PATCHED PREPARER SHA:   $PatchedHash"

$Runner=[scriptblock]::Create($Source)
& $Runner `
    -VBoxManagePath $VBoxManagePath `
    -R3Root $R3Root `
    -R3StopReportPath $R3PoweroffAdjudicationReportPath `
    -SealedRehearsalRoot $SealedRehearsalRoot `
    -RehearsalVerificationReportPath $RehearsalVerificationReportPath `
    -BootReadinessReportPath $BootReadinessReportPath `
    -IsoBootRoot $IsoBootRoot `
    -OutPath $OutPath
