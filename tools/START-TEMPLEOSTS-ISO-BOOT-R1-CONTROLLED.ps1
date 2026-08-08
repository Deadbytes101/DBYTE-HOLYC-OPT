[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$VBoxManagePath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$IsoBootRoot,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$PreparationReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedVBoxManage = 'D:\Portable-VirtualBox7\app64\VBoxManage.exe'
$ExpectedRoot = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-iso-boot-r1'
$ExpectedPrepReport = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-iso-boot-r1-preparation.txt'
$ExpectedOut = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-iso-boot-r1-controlled-start.txt'
$ExpectedMachineName = 'Temple1.10'
$ExpectedMachineUuid = '9c98691e-27cd-4487-a306-587969c2c78c'
$ExpectedVdiUuid = '55c1f29d-a681-402e-b90d-bfbb6b09f207'
$ExpectedIsoUuid = 'ab97b3a5-1331-494d-a917-e85b6e728c45'
$ExpectedVdiHash = '90D453A94F075760A11E0772862E60C4B031ED874F28AA396EAE638F7EB8B31B'
$ExpectedIsoHash = 'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$ExpectedDriverPath = 'D:\Portable-VirtualBox7\app64\drivers\vboxsup\VBoxSup.sys'
$ExpectedDriverHash = '3344E2909580A9965E38B26AB9E9958842315DDEA1B0D0E274DA314DDCAB97F4'
$ExpectedVBoxVersion = '7.0.12r159484'
$ScPath = Join-Path $env:SystemRoot 'System32\sc.exe'
$FsutilPath = Join-Path $env:SystemRoot 'System32\fsutil.exe'

function Get-FullPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    return [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path)).TrimEnd([char]92,[char]47)
}
function Assert-PathEquals {
    param([string]$Observed,[string]$Expected,[string]$Label)
    if (-not [string]::Equals((Get-FullPath $Observed),(Get-FullPath $Expected),[System.StringComparison]::OrdinalIgnoreCase)) {
        throw "${Label} mismatch: observed=$Observed expected=$Expected"
    }
}
function Invoke-Native {
    param([string]$FilePath,[AllowEmptyCollection()][string[]]$Arguments,[string]$Label)
    $Old=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        $Rows=@(& $FilePath @Arguments 2>&1 | ForEach-Object {[string]$_})
        $Exit=$LASTEXITCODE
    }
    finally { $ErrorActionPreference=$Old }
    return [pscustomobject]@{Label=$Label;ExitCode=[int]$Exit;Output=[string[]]$Rows}
}
function Require-Success { param([object]$Result); if ($Result.ExitCode -ne 0) { throw "$($Result.Label) failed exit=$($Result.ExitCode) output=$($Result.Output -join ' | ')" } }
function Get-TabValue {
    param([string[]]$Lines,[string]$Key)
    $Prefix=$Key+"`t"
    $Rows=@($Lines | Where-Object {$_.StartsWith($Prefix,[System.StringComparison]::Ordinal)})
    if ($Rows.Count -ne 1) { throw "report field count mismatch: $Key count=$($Rows.Count)" }
    return $Rows[0].Substring($Prefix.Length)
}
function Get-FileId {
    param([string]$Path,[string]$Label)
    $Result=Invoke-Native -FilePath $FsutilPath -Arguments @('file','queryfileid',$Path) -Label "fsutil $Label"
    Require-Success $Result
    $Ids=@([regex]::Matches(($Result.Output -join "`n"),'(?i)0x[0-9a-f]+') | ForEach-Object {$_.Value.ToUpperInvariant()})
    if ($Ids.Count -ne 1) { throw "${Label} file ID count mismatch: $($Ids.Count)" }
    return $Ids[0]
}
function Require-Hash {
    param([string]$Path,[string]$Expected,[string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "${Label} missing: $Path" }
    $Hash=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($Hash -cne $Expected) { throw "${Label} SHA256 mismatch: $Hash expected=$Expected" }
    return $Hash
}
function Require-VBoxSupRunning {
    $Result=Invoke-Native -FilePath $ScPath -Arguments @('query','VBoxSup') -Label 'sc query VBoxSup'
    Require-Success $Result
    if (($Result.Output -join "`n") -notmatch '(?im)^\s*STATE\s*:\s*4\b') { throw 'VBoxSup STATE 4 not observed' }
}
function Convert-MachineReadable {
    param([AllowEmptyCollection()][string[]]$Rows)
    $Map=@{}
    $Slash=[string][char]92; $DoubleSlash=$Slash+$Slash; $EscapedQuote=$Slash+[string][char]34
    foreach ($Row in $Rows) {
        if ($Row -notmatch '^([^=]+)=(.*)$') { continue }
        $Key=[string]$Matches[1]; $Value=[string]$Matches[2]
        if ($Key.Length -ge 2 -and $Key[0] -eq [char]34 -and $Key[$Key.Length-1] -eq [char]34) { $Key=$Key.Substring(1,$Key.Length-2).Replace($EscapedQuote,[string][char]34).Replace($DoubleSlash,$Slash) }
        if ($Value.Length -ge 2 -and $Value[0] -eq [char]34 -and $Value[$Value.Length-1] -eq [char]34) { $Value=$Value.Substring(1,$Value.Length-2).Replace($EscapedQuote,[string][char]34).Replace($DoubleSlash,$Slash) }
        if ([string]::IsNullOrWhiteSpace($Key)) { throw 'machine-readable key normalized empty' }
        if ($Map.ContainsKey($Key)) { throw "duplicate machine-readable key: $Key" }
        $Map[$Key]=$Value
    }
    return $Map
}
function Require-MapValue {
    param([hashtable]$Map,[string]$Key,[string]$Expected,[string]$Label)
    if (-not $Map.ContainsKey($Key)) { throw "${Label} missing key: $Key" }
    $Observed=[string]$Map[$Key]
    if (-not [string]::Equals($Observed,$Expected,[System.StringComparison]::OrdinalIgnoreCase)) { throw "${Label} mismatch: $Key=$Observed expected=$Expected" }
}
function Get-SnapshotRows {
    param([string]$VBox,[string]$Uuid)
    $Result=Invoke-Native -FilePath $VBox -Arguments @('snapshot',$Uuid,'list','--machinereadable') -Label 'snapshot list'
    if ($Result.ExitCode -eq 0) { return [string[]]@($Result.Output | Where-Object {$_ -match '^Snapshot(Name|UUID|Node)'}) }
    if (($Result.Output -join "`n") -match '(?i)does not have any snapshots') { return [string[]]@() }
    throw "snapshot list failed exit=$($Result.ExitCode) output=$($Result.Output -join ' | ')"
}
function Get-HardeningEvidence {
    param([string]$MachineDir)
    $Path=Join-Path (Join-Path $MachineDir 'Logs') 'VBoxHardening.log'
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return [pscustomobject]@{Path=$Path;Hash='';Tail=@();Error=''} }
    try {
        return [pscustomobject]@{Path=$Path;Hash=(Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash;Tail=[string[]]@(Get-Content -LiteralPath $Path -Tail 80 -ErrorAction Stop);Error=''}
    }
    catch { return [pscustomobject]@{Path=$Path;Hash='';Tail=@();Error=$_.Exception.Message} }
}
function Write-Report {
    param([string]$Path,[string]$Status,[string]$PrepHash,[string]$ManifestHash,[string]$StartArgs,[int]$StartExit,[AllowEmptyCollection()][AllowEmptyString()][string[]]$StartOutput,[string]$PostState,[string]$PostRunning,[string]$PostVBoxSup,[AllowEmptyString()][string]$ErrorText='')
    if (Test-Path -LiteralPath $Path) { throw "start report already exists: $Path" }
    $Hardening=Get-HardeningEvidence -MachineDir $script:MachineDir
    $Lines=[System.Collections.Generic.List[string]]::new()
    $Lines.Add('DBYTE-HOLYC-OPT')
    $Lines.Add('TEMPLEOSTS 1.10 / FRESH EXACT ISO BOOT R1 / CONTROLLED START')
    $Lines.Add('')
    $Lines.Add("preparation_report_sha256`t$PrepHash")
    $Lines.Add("iso_boot_manifest_sha256`t$ManifestHash")
    $Lines.Add("machine_uuid`t$ExpectedMachineUuid")
    $Lines.Add("start_arguments`t$StartArgs")
    $Lines.Add("start_exit_code`t$StartExit")
    foreach ($Row in $StartOutput) {$Lines.Add("start_output`t$Row")}
    $Lines.Add("post_start_vm_state`t$PostState")
    $Lines.Add("post_start_running_vm_rows`t$PostRunning")
    $Lines.Add("post_start_vboxsup_state`t$PostVBoxSup")
    if (-not [string]::IsNullOrWhiteSpace($ErrorText)) {$Lines.Add("error`t$ErrorText")}
    $Lines.Add("hardening_log_path`t$($Hardening.Path)")
    $Lines.Add("hardening_log_sha256`t$($Hardening.Hash)")
    $Lines.Add("hardening_log_capture_error`t$($Hardening.Error)")
    foreach ($Row in $Hardening.Tail) {$Lines.Add("hardening_tail`t$Row")}
    $Lines.Add('')
    $Lines.Add("VBOXMANAGE`tSTARTVM-ONCE-PLUS-READ-ONLY-OBSERVATION")
    $Lines.Add("CONTROLVM`tNOT-EXECUTED")
    $Lines.Add("STORAGEATTACH`tNOT-EXECUTED")
    $Lines.Add("SERVICE MUTATION`tNOT-EXECUTED")
    $Lines.Add("COMPILER BUILD`tNOT-EXECUTED")
    $Lines.Add("GUEST VISUAL BOOT`tNOT-OBSERVED-BY-HOST-SCRIPT")
    $Lines.Add("STATUS`t$Status")
    $Lines.Add('')
    $Lines.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')
    [System.IO.File]::WriteAllText($Path,(($Lines.ToArray()-join "`n")+"`n"),[System.Text.UTF8Encoding]::new($false))
}

foreach ($Exe in @($VBoxManagePath,$ScPath,$FsutilPath,$ExpectedDriverPath)) { if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) { throw "required file missing: $Exe" } }
$VBox=(Resolve-Path -LiteralPath $VBoxManagePath -ErrorAction Stop).Path
$Root=(Resolve-Path -LiteralPath $IsoBootRoot -ErrorAction Stop).Path
$Prep=(Resolve-Path -LiteralPath $PreparationReportPath -ErrorAction Stop).Path
$Output=Get-FullPath $OutPath
Assert-PathEquals $VBox $ExpectedVBoxManage 'VBoxManage'
Assert-PathEquals $Root $ExpectedRoot 'ISO boot root'
Assert-PathEquals $Prep $ExpectedPrepReport 'preparation report'
Assert-PathEquals $Output $ExpectedOut 'start report'
if (Test-Path -LiteralPath $Output) { throw "ISO start report already exists: $Output" }
if (Test-Path -LiteralPath (Join-Path $Root 'ISO-BOOT-R1-INCOMPLETE.txt')) { throw 'ISO boot root retains INCOMPLETE marker' }

$PrepLines=[System.IO.File]::ReadAllLines($Prep)
if ((Get-TabValue $PrepLines 'iso_boot_root') -cne $ExpectedRoot) { throw 'preparation root field mismatch' }
if ((Get-TabValue $PrepLines 'machine_state') -cne 'poweroff') { throw 'preparation machine state mismatch' }
if ((Get-TabValue $PrepLines 'boot1') -cne 'dvd' -or (Get-TabValue $PrepLines 'boot2') -cne 'disk' -or (Get-TabValue $PrepLines 'boot3') -cne 'none' -or (Get-TabValue $PrepLines 'boot4') -cne 'none') { throw 'preparation boot order mismatch' }
if ((Get-TabValue $PrepLines 'iso_attached') -cne 'True') { throw 'preparation ISO attachment mismatch' }
if ((Get-TabValue $PrepLines 'vdi_sha256') -cne $ExpectedVdiHash -or (Get-TabValue $PrepLines 'iso_sha256') -cne $ExpectedIsoHash) { throw 'preparation media hash fields mismatch' }
if ((Get-TabValue $PrepLines 'STATUS') -cne 'ISO-BOOT-R1-PREPARED') { throw 'preparation status mismatch' }
$PrepHash=(Get-FileHash -LiteralPath $Prep -Algorithm SHA256).Hash
$ManifestHash=Get-TabValue $PrepLines 'iso_boot_manifest_sha256'
$Manifest=Join-Path $Root 'ISO-BOOT-R1-MANIFEST.txt'
[void](Require-Hash $Manifest $ManifestHash 'ISO boot manifest')

$script:MachineDir=Join-Path $Root 'Machine'
$Home=Join-Path $Root 'VBoxUserHome'
$CurrentVBox=Join-Path $script:MachineDir 'Temple1.10.vbox'
$PreviousVBox=Join-Path $script:MachineDir 'Temple1.10.vbox-prev'
$Vdi=Join-Path $script:MachineDir 'Temple1.10.vdi'
$Iso=Join-Path $script:MachineDir 'TempleOSTS.iso'
$Registry=Join-Path $Home 'VirtualBox.xml'
$ExpectedVBoxHash=Get-TabValue $PrepLines 'current_vbox_sha256'
$ExpectedVBoxId=Get-TabValue $PrepLines 'current_vbox_file_id'
$ExpectedPrevHash=Get-TabValue $PrepLines 'previous_vbox_sha256'
$ExpectedPrevId=Get-TabValue $PrepLines 'previous_vbox_file_id'
$ExpectedVdiId=Get-TabValue $PrepLines 'vdi_file_id'
$ExpectedIsoId=Get-TabValue $PrepLines 'iso_file_id'
$ExpectedRegistryHash=Get-TabValue $PrepLines 'registry_sha256'

[void](Require-Hash $CurrentVBox $ExpectedVBoxHash 'current VBOX')
if ((Get-FileId $CurrentVBox 'current VBOX') -cne $ExpectedVBoxId) { throw 'current VBOX file ID mismatch' }
if ($ExpectedPrevHash -ceq '<missing>') {
    if (Test-Path -LiteralPath $PreviousVBox -PathType Leaf) { throw 'unexpected VBOX-prev appeared after preparation' }
} else {
    [void](Require-Hash $PreviousVBox $ExpectedPrevHash 'previous VBOX')
    if ((Get-FileId $PreviousVBox 'previous VBOX') -cne $ExpectedPrevId) { throw 'previous VBOX file ID mismatch' }
}
[void](Require-Hash $Vdi $ExpectedVdiHash 'VDI')
[void](Require-Hash $Iso $ExpectedIsoHash 'ISO')
[void](Require-Hash $Registry $ExpectedRegistryHash 'isolated registry')
if ((Get-FileId $Vdi 'VDI') -cne $ExpectedVdiId) { throw 'VDI file ID mismatch' }
if ((Get-FileId $Iso 'ISO') -cne $ExpectedIsoId) { throw 'ISO file ID mismatch' }
[void](Require-Hash $ExpectedDriverPath $ExpectedDriverHash 'VBoxSup.sys')
Require-VBoxSupRunning

$OriginalHome=[Environment]::GetEnvironmentVariable('VBOX_USER_HOME',[EnvironmentVariableTarget]::Process)
if (-not [string]::IsNullOrEmpty($OriginalHome)) { throw "process VBOX_USER_HOME must be unset: $OriginalHome" }
$Processes=@(Get-Process -ErrorAction SilentlyContinue | Where-Object {$_.ProcessName -match '(?i)^(VBoxSVC|VirtualBoxVM|VBoxHeadless|VirtualBox)$'})
if ($Processes.Count -ne 0) { throw 'VirtualBox runtime process already present: '+(($Processes|ForEach-Object{"$($_.ProcessName):$($_.Id)"}) -join ', ') }

$StartIssued=$false; $StartArgsText='NOT-ISSUED'; $StartExit=-1; $StartOutput=@(); $PostState=''; $PostRunning=''; $PostVBoxSup=''
[Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$Home,[EnvironmentVariableTarget]::Process)
try {
    $Version=Invoke-Native $VBox @('--version') 'VBoxManage --version'; Require-Success $Version
    if ($Version.Output.Count -ne 1 -or $Version.Output[0].Trim() -cne $ExpectedVBoxVersion) { throw 'VirtualBox version mismatch' }
    $List=Invoke-Native $VBox @('list','vms') 'registered inventory'; Require-Success $List
    $Rows=@($List.Output|Where-Object{$_.Trim().Length -gt 0}); $Quote=[string][char]34; $ExpectedRow=$Quote+$ExpectedMachineName+$Quote+' {'+$ExpectedMachineUuid+'}'
    if ($Rows.Count -ne 1 -or $Rows[0].Trim() -cne $ExpectedRow) { throw 'registered inventory mismatch' }
    $Running=Invoke-Native $VBox @('list','runningvms') 'running inventory'; Require-Success $Running
    if (@($Running.Output|Where-Object{$_.Trim().Length -gt 0}).Count -ne 0) { throw 'running inventory not zero' }
    $InfoResult=Invoke-Native $VBox @('showvminfo',$ExpectedMachineUuid,'--machinereadable') 'showvminfo'; Require-Success $InfoResult
    $Info=Convert-MachineReadable $InfoResult.Output
    Require-MapValue $Info 'name' $ExpectedMachineName 'ISO boot start gate'
    Require-MapValue $Info 'UUID' $ExpectedMachineUuid 'ISO boot start gate'
    Require-MapValue $Info 'VMState' 'poweroff' 'ISO boot start gate'
    Require-MapValue $Info 'CfgFile' $CurrentVBox 'ISO boot start gate'
    Require-MapValue $Info 'IDE-1-0' $Vdi 'ISO boot start gate'
    Require-MapValue $Info 'IDE-ImageUUID-1-0' $ExpectedVdiUuid 'ISO boot start gate'
    Require-MapValue $Info 'IDE-0-1' $Iso 'ISO boot start gate'
    Require-MapValue $Info 'IDE-ImageUUID-0-1' $ExpectedIsoUuid 'ISO boot start gate'
    Require-MapValue $Info 'boot1' 'dvd' 'ISO boot start gate'; Require-MapValue $Info 'boot2' 'disk' 'ISO boot start gate'; Require-MapValue $Info 'boot3' 'none' 'ISO boot start gate'; Require-MapValue $Info 'boot4' 'none' 'ISO boot start gate'
    Require-MapValue $Info 'clipboard' 'disabled' 'ISO boot start gate'; Require-MapValue $Info 'draganddrop' 'disabled' 'ISO boot start gate'; Require-MapValue $Info 'graphicscontroller' 'vboxvga' 'ISO boot start gate'; Require-MapValue $Info 'vram' '9' 'ISO boot start gate'
    $NicKeys=@($Info.Keys|Where-Object{$_ -match '^nic[1-8]$'}); if ($NicKeys.Count -eq 0) {throw 'no NIC keys'}; foreach($Key in $NicKeys){Require-MapValue $Info $Key 'none' 'ISO boot start gate'}
    $Shared=@($Info.Keys|Where-Object{$_ -like 'SharedFolderNameMachineMapping*' -or $_ -like 'SharedFolderPathMachineMapping*'}); if($Shared.Count -ne 0){throw 'shared-folder keys not zero'}
    if (@(Get-SnapshotRows $VBox $ExpectedMachineUuid).Count -ne 0) { throw 'snapshot rows not zero' }
    Require-VBoxSupRunning
    [void](Require-Hash $CurrentVBox $ExpectedVBoxHash 'current VBOX at start boundary'); if((Get-FileId $CurrentVBox 'current VBOX at start boundary') -cne $ExpectedVBoxId){throw 'current VBOX ID drift'}
    [void](Require-Hash $Vdi $ExpectedVdiHash 'VDI at start boundary'); if((Get-FileId $Vdi 'VDI at start boundary') -cne $ExpectedVdiId){throw 'VDI ID drift'}
    [void](Require-Hash $Iso $ExpectedIsoHash 'ISO at start boundary'); if((Get-FileId $Iso 'ISO at start boundary') -cne $ExpectedIsoId){throw 'ISO ID drift'}
    [void](Require-Hash $Registry $ExpectedRegistryHash 'registry at start boundary')

    Write-Host 'ISO START BOUNDARY:     ALL PRE-START GATES PASSED'
    Write-Host 'BOOT ROUTE:             DVD -> DISK -> NONE -> NONE'
    Write-Host 'ISO ATTACHED:           TRUE / EXACT TEMPLEOSTS ISO'
    Write-Host 'VBOXSUP STATE:          4 / RUNNING'
    Write-Host 'AUTHORIZED MUTATION:    startvm TARGET --type gui / ONCE'
    Write-Host 'AUTOMATIC ROLLBACK:     NONE'

    $Args=@('startvm',$ExpectedMachineUuid,'--type','gui'); $StartArgsText=$Args -join ' '; $StartIssued=$true
    $Start=Invoke-Native $VBox $Args 'ISO controlled start'; $StartExit=[int]$Start.ExitCode; $StartOutput=@($Start.Output)
    Require-Success $Start
    $PostInfoResult=Invoke-Native $VBox @('showvminfo',$ExpectedMachineUuid,'--machinereadable') 'post-start showvminfo'; Require-Success $PostInfoResult
    $PostInfo=Convert-MachineReadable $PostInfoResult.Output; if(-not $PostInfo.ContainsKey('VMState')){throw 'post-start VMState missing'}; $PostState=[string]$PostInfo['VMState']
    $PostList=Invoke-Native $VBox @('list','runningvms') 'post-start running inventory'; Require-Success $PostList
    $PostRows=@($PostList.Output|Where-Object{$_.Trim().Length -gt 0}); $PostRunning=[string]$PostRows.Count
    Require-VBoxSupRunning; $PostVBoxSup='4'
    if($PostState -ine 'running'){throw "post-start state not running: $PostState"}; if($PostRows.Count -ne 1 -or $PostRows[0].Trim() -cne $ExpectedRow){throw 'post-start running inventory mismatch'}
    Write-Report $Output 'ISO-START-ACCEPTED-HOST-RUNNING' $PrepHash $ManifestHash $StartArgsText $StartExit $StartOutput $PostState $PostRunning $PostVBoxSup
    $ReportHash=(Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash
    Write-Host "START COMMAND:          $StartArgsText"
    Write-Host "START EXIT CODE:        $StartExit"
    Write-Host "POST-START VM STATE:    $PostState"
    Write-Host "POST-START RUNNING VMS: $PostRunning"
    Write-Host "POST-START VBOXSUP:     $PostVBoxSup"
    Write-Host "REPORT:                 $Output"
    Write-Host "REPORT SHA256:          $ReportHash"
    Write-Host 'GUEST VISUAL BOOT:      NOT-OBSERVED-BY-HOST-SCRIPT'
    Write-Host 'COMPILER BUILD:         NOT-EXECUTED'
    Write-Host 'VERDICT:                ISO START ACCEPTED / HOST RUNNING / VISUAL PROOF PENDING'
}
catch {
    $ErrorText=$_.Exception.Message
    if($StartIssued -and -not(Test-Path -LiteralPath $Output)){
        try{Write-Report $Output 'ISO-START-ISSUED-FAILED-OR-POST-OBSERVATION-FAILED' $PrepHash $ManifestHash $StartArgsText $StartExit $StartOutput $PostState $PostRunning $PostVBoxSup $ErrorText; Write-Host "ISO START FAILURE REPORT: $Output"; Write-Host "FAILURE REPORT SHA256:    $((Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash)"; Write-Host 'AUTOMATIC ROLLBACK:       NOT-EXECUTED'}catch{}
    }
    throw
}
finally { [Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$OriginalHome,[EnvironmentVariableTarget]::Process) }
