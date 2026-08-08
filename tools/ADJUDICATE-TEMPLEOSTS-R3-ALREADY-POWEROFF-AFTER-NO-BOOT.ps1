[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$VBoxManagePath,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$PreparedRoot,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$SecondAttemptReportPath,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$ExpectedVBoxManage='D:\Portable-VirtualBox7\app64\VBoxManage.exe'
$ExpectedRoot='D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r3'
$ExpectedSecondAttemptReport='D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r3-second-controlled-boot-attempt.txt'
$ExpectedSecondAttemptHash='E6780E727989B974727402F782CA16B1B870FBF05591FACA6D131F6244F71430'
$ExpectedOut='D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r3-already-poweroff-after-no-boot-adjudication.txt'
$ExpectedVBoxVersion='7.0.12r159484'
$ExpectedMachineName='Temple1.10'
$ExpectedMachineUuid='9c98691e-27cd-4487-a306-587969c2c78c'
$ExpectedVdiUuid='55c1f29d-a681-402e-b90d-bfbb6b09f207'
$ExpectedDriverPath='D:\Portable-VirtualBox7\app64\drivers\vboxsup\VBoxSup.sys'
$ExpectedDriverHash='3344E2909580A9965E38B26AB9E9958842315DDEA1B0D0E274DA314DDCAB97F4'
$ScPath=Join-Path $env:SystemRoot 'System32\sc.exe'

function Get-FullPath { param([Parameter(Mandatory=$true)][string]$Path); return [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path)).TrimEnd([char]92,[char]47) }
function Assert-PathEquals {
    param([string]$Observed,[string]$Expected,[string]$Label)
    if(-not [string]::Equals((Get-FullPath $Observed),(Get-FullPath $Expected),[System.StringComparison]::OrdinalIgnoreCase)){throw "${Label} mismatch observed=$Observed expected=$Expected"}
}
function Invoke-Native {
    param([string]$FilePath,[AllowEmptyCollection()][string[]]$Arguments,[string]$Label)
    $Old=$ErrorActionPreference
    try{$ErrorActionPreference='Continue';$Rows=@(& $FilePath @Arguments 2>&1|ForEach-Object{[string]$_});$Exit=$LASTEXITCODE}finally{$ErrorActionPreference=$Old}
    return [pscustomobject]@{Label=$Label;ExitCode=[int]$Exit;Output=[string[]]$Rows}
}
function Require-Success { param([object]$Result); if($Result.ExitCode -ne 0){throw "$($Result.Label) failed exit=$($Result.ExitCode) output=$($Result.Output -join ' | ')"} }
function Convert-MachineReadable {
    param([AllowEmptyCollection()][string[]]$Rows)
    $Map=@{};$Slash=[string][char]92;$DoubleSlash=$Slash+$Slash;$EscapedQuote=$Slash+[string][char]34
    foreach($Row in $Rows){
        if($Row -notmatch '^([^=]+)=(.*)$'){continue}
        $Key=[string]$Matches[1];$Value=[string]$Matches[2]
        if($Key.Length -ge 2 -and $Key[0] -eq [char]34 -and $Key[$Key.Length-1] -eq [char]34){$Key=$Key.Substring(1,$Key.Length-2).Replace($EscapedQuote,[string][char]34).Replace($DoubleSlash,$Slash)}
        if($Value.Length -ge 2 -and $Value[0] -eq [char]34 -and $Value[$Value.Length-1] -eq [char]34){$Value=$Value.Substring(1,$Value.Length-2).Replace($EscapedQuote,[string][char]34).Replace($DoubleSlash,$Slash)}
        if([string]::IsNullOrWhiteSpace($Key)){throw 'machine-readable key normalized empty'}
        if($Map.ContainsKey($Key)){throw "duplicate machine-readable key: $Key"}
        $Map[$Key]=$Value
    }
    return $Map
}
function Require-MapValue {
    param([hashtable]$Map,[string]$Key,[string]$Expected,[string]$Label)
    if(-not $Map.ContainsKey($Key)){throw "${Label} missing key: $Key"}
    $Observed=[string]$Map[$Key]
    if(-not [string]::Equals($Observed,$Expected,[System.StringComparison]::OrdinalIgnoreCase)){throw "${Label} mismatch $Key=$Observed expected=$Expected"}
}
function Require-VBoxSupRunning {
    $Result=Invoke-Native $ScPath @('query','VBoxSup') 'sc query VBoxSup';Require-Success $Result
    if(($Result.Output -join "`n") -notmatch '(?im)^\s*STATE\s*:\s*4\b'){throw 'VBoxSup STATE 4 not observed'}
}
function Get-SnapshotRows {
    param([string]$VBox,[string]$Uuid)
    $Result=Invoke-Native $VBox @('snapshot',$Uuid,'list','--machinereadable') 'snapshot list'
    if($Result.ExitCode -eq 0){return [string[]]@($Result.Output|Where-Object{$_ -match '^Snapshot(Name|UUID|Node)'})}
    if(($Result.Output -join "`n") -match '(?i)does not have any snapshots'){return [string[]]@()}
    throw "snapshot list failed exit=$($Result.ExitCode) output=$($Result.Output -join ' | ')"
}
function Wait-VBoxSVCExit {
    param([int]$Seconds=30)
    $Deadline=[DateTime]::UtcNow.AddSeconds($Seconds)
    while([DateTime]::UtcNow -lt $Deadline){if(@(Get-Process -Name 'VBoxSVC' -ErrorAction SilentlyContinue).Count -eq 0){return};Start-Sleep -Milliseconds 250}
    $Pids=@(Get-Process -Name 'VBoxSVC' -ErrorAction SilentlyContinue).Id
    throw "VBoxSVC did not exit after read-only adjudication: $($Pids -join ',')"
}

foreach($Required in @($VBoxManagePath,$ScPath,$ExpectedDriverPath)){if(-not(Test-Path -LiteralPath $Required -PathType Leaf)){throw "required file missing: $Required"}}
$VBox=(Resolve-Path -LiteralPath $VBoxManagePath).Path
$Root=(Resolve-Path -LiteralPath $PreparedRoot).Path
$Second=(Resolve-Path -LiteralPath $SecondAttemptReportPath).Path
$Output=Get-FullPath $OutPath
Assert-PathEquals $VBox $ExpectedVBoxManage 'VBoxManage'
Assert-PathEquals $Root $ExpectedRoot 'R3 root'
Assert-PathEquals $Second $ExpectedSecondAttemptReport 'second attempt report'
Assert-PathEquals $Output $ExpectedOut 'adjudication report'
if(Test-Path -LiteralPath $Output){throw "adjudication report already exists: $Output"}
if((Get-FileHash -LiteralPath $Second -Algorithm SHA256).Hash -cne $ExpectedSecondAttemptHash){throw 'second attempt report hash mismatch'}
if((Get-FileHash -LiteralPath $ExpectedDriverPath -Algorithm SHA256).Hash -cne $ExpectedDriverHash){throw 'VBoxSup.sys hash mismatch'}
Require-VBoxSupRunning

$MachineDir=Join-Path $Root 'Machine'
$R3VBoxHome=Join-Path $Root 'VBoxUserHome'
$CurrentVBox=Join-Path $MachineDir 'Temple1.10.vbox'
$Vdi=Join-Path $MachineDir 'Temple1.10.vdi'
$Iso=Join-Path $MachineDir 'TempleOSTS.iso'
$Registry=Join-Path $R3VBoxHome 'VirtualBox.xml'
foreach($Required in @($CurrentVBox,$Vdi,$Iso,$Registry)){if(-not(Test-Path -LiteralPath $Required -PathType Leaf)){throw "R3 artifact missing: $Required"}}
$RegistryHashBefore=(Get-FileHash -LiteralPath $Registry -Algorithm SHA256).Hash
$VBoxHash=(Get-FileHash -LiteralPath $CurrentVBox -Algorithm SHA256).Hash
$VdiHash=(Get-FileHash -LiteralPath $Vdi -Algorithm SHA256).Hash
$IsoHash=(Get-FileHash -LiteralPath $Iso -Algorithm SHA256).Hash

$OriginalHome=[Environment]::GetEnvironmentVariable('VBOX_USER_HOME',[EnvironmentVariableTarget]::Process)
if(-not [string]::IsNullOrEmpty($OriginalHome)){throw "process VBOX_USER_HOME must be unset: $OriginalHome"}
[Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$R3VBoxHome,[EnvironmentVariableTarget]::Process)
try{
    $Version=Invoke-Native $VBox @('--version') 'VBoxManage --version';Require-Success $Version
    if($Version.Output.Count -ne 1 -or $Version.Output[0].Trim() -cne $ExpectedVBoxVersion){throw 'VirtualBox version mismatch'}
    $List=Invoke-Native $VBox @('list','vms') 'registered inventory';Require-Success $List
    $Rows=@($List.Output|Where-Object{$_.Trim().Length -gt 0});$Quote=[string][char]34;$ExpectedRow=$Quote+$ExpectedMachineName+$Quote+' {'+$ExpectedMachineUuid+'}'
    if($Rows.Count -ne 1 -or $Rows[0].Trim() -cne $ExpectedRow){throw "registered inventory mismatch: $($Rows -join ' | ')"}
    $Running=Invoke-Native $VBox @('list','runningvms') 'running inventory';Require-Success $Running
    $RunningRows=@($Running.Output|Where-Object{$_.Trim().Length -gt 0})
    if($RunningRows.Count -ne 0){throw "R3 still running: $($RunningRows -join ' | ')"}
    $InfoResult=Invoke-Native $VBox @('showvminfo',$ExpectedMachineUuid,'--machinereadable') 'showvminfo';Require-Success $InfoResult
    $Info=Convert-MachineReadable $InfoResult.Output
    Require-MapValue $Info 'name' $ExpectedMachineName 'R3'
    Require-MapValue $Info 'UUID' $ExpectedMachineUuid 'R3'
    Require-MapValue $Info 'VMState' 'poweroff' 'R3'
    Require-MapValue $Info 'CfgFile' $CurrentVBox 'R3'
    Require-MapValue $Info 'IDE-1-0' $Vdi 'R3'
    Require-MapValue $Info 'IDE-ImageUUID-1-0' $ExpectedVdiUuid 'R3'
    Require-MapValue $Info 'boot1' 'disk' 'R3'
    Require-MapValue $Info 'boot2' 'none' 'R3'
    Require-MapValue $Info 'boot3' 'none' 'R3'
    Require-MapValue $Info 'boot4' 'none' 'R3'
    if($Info.ContainsKey('IDE-0-1') -and -not [string]::Equals([string]$Info['IDE-0-1'],'none',[System.StringComparison]::OrdinalIgnoreCase)){throw "R3 ISO slot unexpectedly attached: $($Info['IDE-0-1'])"}
    if(@(Get-SnapshotRows $VBox $ExpectedMachineUuid).Count -ne 0){throw 'R3 snapshot inventory not zero'}
    $VdiInfo=Invoke-Native $VBox @('showmediuminfo','disk',$Vdi) 'VDI medium info';Require-Success $VdiInfo
    if(($VdiInfo.Output -join "`n") -notmatch '(?im)^UUID:\s*55c1f29d-a681-402e-b90d-bfbb6b09f207\s*$'){throw 'R3 VDI UUID mismatch'}
}finally{[Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$OriginalHome,[EnvironmentVariableTarget]::Process)}
Wait-VBoxSVCExit
Require-VBoxSupRunning
$RegistryHashAfter=(Get-FileHash -LiteralPath $Registry -Algorithm SHA256).Hash
if($RegistryHashAfter -cne $RegistryHashBefore){throw "R3 registry changed during read-only adjudication before=$RegistryHashBefore after=$RegistryHashAfter"}

$Lines=[System.Collections.Generic.List[string]]::new()
$Lines.Add('DBYTE-HOLYC-OPT')
$Lines.Add('TEMPLEOSTS 1.10 / R3 ALREADY POWEROFF AFTER NO-BOOT / READ-ONLY ADJUDICATION')
$Lines.Add('')
$Lines.Add("second_attempt_report_sha256`t$ExpectedSecondAttemptHash")
$Lines.Add("machine_uuid`t$ExpectedMachineUuid")
$Lines.Add("running_vm_rows`t0")
$Lines.Add("machine_state`tpoweroff")
$Lines.Add("current_vbox_sha256`t$VBoxHash")
$Lines.Add("vdi_sha256`t$VdiHash")
$Lines.Add("iso_sha256`t$IsoHash")
$Lines.Add("registry_sha_before`t$RegistryHashBefore")
$Lines.Add("registry_sha_after`t$RegistryHashAfter")
$Lines.Add('')
$Lines.Add("CONTROLVM`tNOT-EXECUTED")
$Lines.Add("VM START`tNOT-EXECUTED")
$Lines.Add("STORAGE MUTATION`tNOT-EXECUTED")
$Lines.Add("SERVICE MUTATION`tNOT-EXECUTED")
$Lines.Add("COMPILER BUILD`tNOT-EXECUTED")
$Lines.Add("STATUS`tR3-ALREADY-POWEROFF-PRESERVED")
$Lines.Add('')
$Lines.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')
[System.IO.File]::WriteAllText($Output,(($Lines.ToArray()-join "`n")+"`n"),[System.Text.UTF8Encoding]::new($false))
$ReportHash=(Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash
Write-Host 'R3 RUNNING VMS:         0'
Write-Host 'R3 MACHINE STATE:       poweroff'
Write-Host 'CONTROLVM:              NOT-EXECUTED'
Write-Host 'VBOXSUP STATE:          4 / RUNNING'
Write-Host "REPORT:                 $Output"
Write-Host "REPORT SHA256:          $ReportHash"
Write-Host 'VERDICT:                R3 ALREADY POWEROFF / PRESERVED READ-ONLY'
