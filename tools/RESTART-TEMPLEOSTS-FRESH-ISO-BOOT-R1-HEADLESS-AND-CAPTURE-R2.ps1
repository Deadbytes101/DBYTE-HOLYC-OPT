[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$VBox='D:\Portable-VirtualBox7\app64\VBoxManage.exe'
$Root='D:\TECHNICAL\DBYTE-HOLYC-OPT-ISOBOOT-FRESH-R1'
$Uuid='9c98691e-27cd-4487-a306-587969c2c78c'
$Name='Temple1.10'
$VersionExpected='7.0.12r159484'
$StartHash='23E802ADF0EF790F51D6D4DECA66EE0D10C755AE6C818CAA1C3934100BE43D76'
$RuntimeHash='0C4D594761ED669BBDD096B8B73BECD05685A8D1CE0568DAFC4849235E5EBC8A'
$CauseHash='78420DA53E37ACA5DCA0C000E6DBDD606704BB2FBF80F8DC9264D52757F89ADA'
$VBoxHash='BB6058E7FF513B8261A1FC0B4D51C6A2ACC44DDE9CA0B2E9007B7A90DAC3CC76'
$RegistryHash='48B39A11E3E6E5FF1F2713143915E15A6F0CAE562357D92575D5DCDF569A968C'
$IsoHash='DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$DriverHash='3344E2909580A9965E38B26AB9E9958842315DDEA1B0D0E274DA314DDCAB97F4'
$Driver='D:\Portable-VirtualBox7\app64\drivers\vboxsup\VBoxSup.sys'
$Sc=Join-Path $env:SystemRoot 'System32\sc.exe'
$Machine=Join-Path $Root 'Machine'
$VBoxHome=Join-Path $Root 'VBoxUserHome'
$VboxFile=Join-Path $Machine 'Temple1.10.vbox'
$Vdi=Join-Path $Machine 'Temple1.10.vdi'
$Iso=Join-Path $Machine 'TempleOSTS.iso'
$Registry=Join-Path $VBoxHome 'VirtualBox.xml'
$Start=Join-Path $Root 'START.txt'
$Runtime=Join-Path $Root 'RUNTIME-STATE-R1.txt'
$Cause=Join-Path $Root 'POWEROFF-CAUSE-R1.txt'
$Png=Join-Path $Root 'VISUAL-HEADLESS-R1.png'
$Report=Join-Path $Root 'HEADLESS-CAPTURE-R1.txt'

function Native([string]$FilePath,[string[]]$ArgumentList,[string]$Label){
    $Old=$ErrorActionPreference
    try{$ErrorActionPreference='Continue';$Rows=@(& $FilePath @ArgumentList 2>&1|ForEach-Object{[string]$_});$Code=$LASTEXITCODE}
    finally{$ErrorActionPreference=$Old}
    [pscustomobject]@{Label=$Label;Code=[int]$Code;Rows=[string[]]$Rows}
}
function Ok($R){if($R.Code-ne 0){throw "$($R.Label) failed exit=$($R.Code) output=$($R.Rows -join ' | ')"}}
function MR([string[]]$Rows){
    $Map=@{};$S=[string][char]92;$SS=$S+$S;$EQ=$S+[string][char]34
    foreach($Row in $Rows){
        if($Row-notmatch'^([^=]+)=(.*)$'){continue}
        $K=[string]$Matches[1];$V=[string]$Matches[2]
        if($K.Length-ge 2-and$K[0]-eq[char]34-and$K[$K.Length-1]-eq[char]34){$K=$K.Substring(1,$K.Length-2).Replace($EQ,[string][char]34).Replace($SS,$S)}
        if($V.Length-ge 2-and$V[0]-eq[char]34-and$V[$V.Length-1]-eq[char]34){$V=$V.Substring(1,$V.Length-2).Replace($EQ,[string][char]34).Replace($SS,$S)}
        if([string]::IsNullOrWhiteSpace($K)-or$Map.ContainsKey($K)){throw "bad key: $K"}
        $Map[$K]=$V
    }
    $Map
}
function Need($Map,[string]$Key,[string]$Expected){
    if(-not$Map.ContainsKey($Key)){throw "missing key: $Key"}
    if(-not[string]::Equals([string]$Map[$Key],$Expected,[System.StringComparison]::OrdinalIgnoreCase)){throw "$Key mismatch observed=$($Map[$Key]) expected=$Expected"}
}
function State{
    $R=Native $VBox @('showvminfo',$Uuid,'--machinereadable') 'showvminfo';Ok $R;$M=MR $R.Rows
    if(-not$M.ContainsKey('VMState')){throw 'VMState missing'}
    [string]$M['VMState']
}
function HashIs([string]$Path,[string]$Expected,[string]$Label){
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "missing: $Path"}
    $Actual=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if($Actual-cne$Expected){throw "$Label hash mismatch actual=$Actual expected=$Expected"}
}

foreach($P in @($VBox,$Sc,$Driver,$VboxFile,$Vdi,$Iso,$Registry,$Start,$Runtime,$Cause)){if(-not(Test-Path -LiteralPath $P -PathType Leaf)){throw "missing: $P"}}
if(Test-Path -LiteralPath $Png){throw "PNG exists: $Png"}
if(Test-Path -LiteralPath $Report){throw "report exists: $Report"}
HashIs $Start $StartHash 'START'
HashIs $Runtime $RuntimeHash 'runtime'
HashIs $Cause $CauseHash 'cause'
HashIs $VboxFile $VBoxHash 'VBOX'
HashIs $Registry $RegistryHash 'registry'
HashIs $Iso $IsoHash 'ISO'
HashIs $Driver $DriverHash 'VBoxSup.sys'

$Svc=Native $Sc @('query','VBoxSup') 'sc query VBoxSup';Ok $Svc
if(($Svc.Rows-join"`n")-notmatch'(?im)^\s*STATE\s*:\s*4\b'){throw 'VBoxSup not running'}
$Processes=@(Get-Process -ErrorAction SilentlyContinue|Where-Object{$_.ProcessName-match'(?i)^(VBoxSVC|VirtualBoxVM|VBoxHeadless|VirtualBox)$'})
if($Processes.Count-ne 0){throw "VirtualBox runtime already present: $($Processes.ProcessName -join ',')"}
$OldHome=[Environment]::GetEnvironmentVariable('VBOX_USER_HOME',[EnvironmentVariableTarget]::Process)
if(-not[string]::IsNullOrEmpty($OldHome)){throw "VBOX_USER_HOME must be unset: $OldHome"}

$Issued=$false;$StartExit=-1;$CaptureExit=-1;$PostState='';$PostRows=-1
[Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$VBoxHome,[EnvironmentVariableTarget]::Process)
try{
    $R=Native $VBox @('--version') 'version';Ok $R
    if($R.Rows.Count-ne 1-or$R.Rows[0].Trim()-cne$VersionExpected){throw 'VirtualBox version mismatch'}

    $R=Native $VBox @('list','vms') 'list vms';Ok $R
    $Rows=@($R.Rows|Where-Object{$_.Trim().Length-gt 0});$Q=[string][char]34;$Expected=$Q+$Name+$Q+' {'+$Uuid+'}'
    if($Rows.Count-ne 1-or$Rows[0].Trim()-cne$Expected){throw "registered inventory mismatch: $($Rows -join ' | ')"}

    $R=Native $VBox @('list','runningvms') 'list runningvms';Ok $R
    if(@($R.Rows|Where-Object{$_.Trim().Length-gt 0}).Count-ne 0){throw 'VM already running'}

    $R=Native $VBox @('showvminfo',$Uuid,'--machinereadable') 'pre-start showvminfo';Ok $R;$Info=MR $R.Rows
    Need $Info 'name' $Name;Need $Info 'UUID' $Uuid;Need $Info 'VMState' 'poweroff';Need $Info 'CfgFile' $VboxFile
    Need $Info 'IDE-1-0' $Vdi;Need $Info 'IDE-0-1' $Iso;Need $Info 'boot1' 'dvd';Need $Info 'boot2' 'disk';Need $Info 'boot3' 'none';Need $Info 'boot4' 'none'
    foreach($I in 1..8){$K="nic$I";if($Info.ContainsKey($K)){Need $Info $K 'none'}}

    Write-Host 'HEADLESS START BOUNDARY: ALL GATES PASSED'
    $Issued=$true;$R=Native $VBox @('startvm',$Uuid,'--type','headless') 'headless start';$StartExit=$R.Code;Ok $R

    $Deadline=[DateTime]::UtcNow.AddSeconds(20)
    do{$Current=State;if($Current-eq'running'){break};Start-Sleep -Milliseconds 250}while([DateTime]::UtcNow-lt$Deadline)
    if($Current-ne'running'){throw "VM did not reach running: $Current"}

    Start-Sleep -Seconds 12
    if((State)-ne'running'){throw 'VM left running state before capture'}

    $R=Native $VBox @('controlvm',$Uuid,'screenshotpng',$Png) 'screenshotpng';$CaptureExit=$R.Code;Ok $R
    if(-not(Test-Path -LiteralPath $Png -PathType Leaf)){throw 'PNG not created'}
    $Bytes=[System.IO.File]::ReadAllBytes($Png);if($Bytes.Length-lt 8){throw 'PNG too small'}
    $Sig=@(137,80,78,71,13,10,26,10);for($I=0;$I-lt 8;$I++){if($Bytes[$I]-ne$Sig[$I]){throw 'PNG signature mismatch'}}
    $PngHash=(Get-FileHash -LiteralPath $Png -Algorithm SHA256).Hash

    $PostState=State;$R=Native $VBox @('list','runningvms') 'post-capture runningvms';Ok $R;$Rows=@($R.Rows|Where-Object{$_.Trim().Length-gt 0});$PostRows=$Rows.Count
    if($PostState-ne'running'){throw "post-capture state mismatch: $PostState"}
    if($Rows.Count-ne 1-or$Rows[0].Trim()-cne$Expected){throw "post-capture inventory mismatch: $($Rows -join ' | ')"}

    $Lines=@('DBYTE-HOLYC-OPT','TEMPLEOSTS 1.10 / FRESH ISO BOOT R1 / HEADLESS VISUAL CAPTURE','',"prior_start_sha256`t$StartHash","runtime_report_sha256`t$RuntimeHash","poweroff_cause_sha256`t$CauseHash","start_mode`theadless","start_exit`t$StartExit","capture_exit`t$CaptureExit","png_path`t$Png","png_bytes`t$($Bytes.Length)","png_sha256`t$PngHash","post_capture_vm_state`t$PostState","post_capture_running_rows`t$PostRows","CONTROLVM`tSCREENSHOTPNG-ONLY","VM START`tHEADLESS-ONCE","VM STOP/RESET`tNOT-EXECUTED","STORAGE MUTATION`tNOT-EXECUTED","SERVICE MUTATION`tNOT-EXECUTED","COMPILER BUILD`tNOT-EXECUTED","STATUS`tHEADLESS-START-AND-VISUAL-CAPTURE-PASS",'','REPORTS ARE CLAIMS, NOT EVIDENCE.')
    [System.IO.File]::WriteAllText($Report,(($Lines-join"`n")+"`n"),[System.Text.UTF8Encoding]::new($false))
    $ReportHash=(Get-FileHash -LiteralPath $Report -Algorithm SHA256).Hash
    Write-Host "START EXIT: $StartExit";Write-Host "CAPTURE EXIT: $CaptureExit";Write-Host "PNG: $Png";Write-Host "PNG SHA256: $PngHash";Write-Host "PNG BYTES: $($Bytes.Length)";Write-Host "POST STATE: $PostState";Write-Host "RUNNING ROWS: $PostRows";Write-Host "REPORT: $Report";Write-Host "REPORT SHA256: $ReportHash";Write-Host 'VERDICT: HEADLESS START + VISUAL CAPTURE PASS'
}
catch{
    if($Issued-and-not(Test-Path -LiteralPath $Report)){
        $Lines=@('DBYTE-HOLYC-OPT','TEMPLEOSTS 1.10 / FRESH ISO BOOT R1 / HEADLESS VISUAL CAPTURE FAILURE','',"start_exit`t$StartExit","capture_exit`t$CaptureExit","post_state`t$PostState","post_running_rows`t$PostRows","error`t$($_.Exception.Message)","AUTOMATIC ROLLBACK`tNOT-EXECUTED","COMPILER BUILD`tNOT-EXECUTED","STATUS`tHEADLESS-START-ISSUED-CAPTURE-PATH-FAILED",'','REPORTS ARE CLAIMS, NOT EVIDENCE.')
        try{[System.IO.File]::WriteAllText($Report,(($Lines-join"`n")+"`n"),[System.Text.UTF8Encoding]::new($false))}catch{}
    }
    throw
}
finally{[Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$OldHome,[EnvironmentVariableTarget]::Process)}
