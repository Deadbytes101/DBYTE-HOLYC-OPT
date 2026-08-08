[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$VBox='D:\Portable-VirtualBox7\app64\VBoxManage.exe'
$Root='D:\TECHNICAL\DBYTE-HOLYC-OPT-ISOBOOT-FRESH-R1'
$Uuid='9c98691e-27cd-4487-a306-587969c2c78c'
$Name='Temple1.10'
$VersionExpected='7.0.12r159484'
$IsoHash='DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$R4ReportHash='D7C511A1F62731A51B39DB4C56E72451245D472666146376E090C39443078F03'
$R4PngHash='CF7A075A0AC2266745DF95769170D723BB8047B87FABF86E68B9097DDA43F53C'
$Machine=Join-Path $Root 'Machine'
$VBoxHome=Join-Path $Root 'VBoxUserHome'
$VboxFile=Join-Path $Machine 'Temple1.10.vbox'
$Vdi=Join-Path $Machine 'Temple1.10.vdi'
$Iso=Join-Path $Machine 'TempleOSTS.iso'
$R4Report=Join-Path $Root 'GUEST-COMPRESSED-COMPILER-VDI-R4.txt'
$R4Source=Join-Path $Root 'GUEST-COMPRESSED-SOURCE-R4.png'
$R4Project=Join-Path $Root 'GUEST-COMPRESSED-PROJECT-R4.png'
$PrePng=Join-Path $Root 'GUEST-R5-PRE.png'
$MarkerPng=Join-Path $Root 'GUEST-R5-MARKER.png'
$SourcePng=Join-Path $Root 'GUEST-R5-SOURCE.png'
$ProjectPng=Join-Path $Root 'GUEST-R5-PROJECT.png'
$Report=Join-Path $Root 'GUEST-COMPRESSED-PATHS-R5.txt'

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
function HashIs([string]$Path,[string]$Expected,[string]$Label){
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "missing: $Path"}
    $Actual=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if($Actual-cne$Expected){throw "$Label hash mismatch actual=$Actual expected=$Expected"}
}
function State{
    $R=Native $VBox @('showvminfo',$Uuid,'--machinereadable') 'state';Ok $R;$M=MR $R.Rows
    if(-not$M.ContainsKey('VMState')){throw 'VMState missing'}
    [string]$M['VMState']
}
function Quote{$R=Native $VBox @('controlvm',$Uuid,'keyboardputscancode','2a','28','a8','aa') 'quote';Ok $R}
function Text([string]$Value,[string]$Label){$R=Native $VBox @('controlvm',$Uuid,'keyboardputstring',$Value) $Label;Ok $R}
function Enter{$R=Native $VBox @('controlvm',$Uuid,'keyboardputscancode','1c','9c') 'enter';Ok $R}
function Marker{Quote;Text 'DBYTE_R5_INPUT_LIVE' 'marker';Quote;Text ';' 'marker suffix';Enter;Start-Sleep -Seconds 2}
function SendDir([string]$Path,[string]$Label){Text 'Dir(' "$Label prefix";Quote;Text $Path "$Label path";Quote;Text ');' "$Label suffix";Enter;Start-Sleep -Seconds 3}
function Shot([string]$Path,[string]$Label){
    $R=Native $VBox @('controlvm',$Uuid,'screenshotpng',$Path) $Label;Ok $R
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "$Label PNG missing"}
    $Bytes=[IO.File]::ReadAllBytes($Path);if($Bytes.Length-lt 8){throw "$Label PNG too small"}
    $Sig=@(137,80,78,71,13,10,26,10);for($I=0;$I-lt 8;$I++){if($Bytes[$I]-ne$Sig[$I]){throw "$Label PNG signature mismatch"}}
    [pscustomobject]@{Bytes=$Bytes.Length;SHA256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
}
function Different($A,$B,[string]$Label){if($A.SHA256-ceq$B.SHA256){throw "$Label produced no screenshot delta: $($A.SHA256)"}}

foreach($P in @($VBox,$VboxFile,$Vdi,$Iso,$R4Report,$R4Source,$R4Project)){if(-not(Test-Path -LiteralPath $P -PathType Leaf)){throw "missing: $P"}}
foreach($P in @($PrePng,$MarkerPng,$SourcePng,$ProjectPng,$Report)){if(Test-Path -LiteralPath $P){throw "output exists: $P"}}
HashIs $Iso $IsoHash 'ISO'
HashIs $R4Report $R4ReportHash 'R4 report'
HashIs $R4Source $R4PngHash 'R4 source PNG'
HashIs $R4Project $R4PngHash 'R4 project PNG'

$OldHome=[Environment]::GetEnvironmentVariable('VBOX_USER_HOME',[EnvironmentVariableTarget]::Process)
if(-not[string]::IsNullOrEmpty($OldHome)){throw "VBOX_USER_HOME must be unset: $OldHome"}
[Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$VBoxHome,[EnvironmentVariableTarget]::Process)
try{
    $R=Native $VBox @('--version') 'version';Ok $R
    if($R.Rows.Count-ne 1-or$R.Rows[0].Trim()-cne$VersionExpected){throw 'VirtualBox version mismatch'}
    $R=Native $VBox @('list','runningvms') 'pre runningvms';Ok $R
    $Rows=@($R.Rows|Where-Object{$_.Trim().Length-gt 0});$Q=[string][char]34;$Expected=$Q+$Name+$Q+' {'+$Uuid+'}'
    if($Rows.Count-ne 1-or$Rows[0].Trim()-cne$Expected){throw "pre running inventory mismatch: $($Rows -join ' | ')"}
    $R=Native $VBox @('showvminfo',$Uuid,'--machinereadable') 'pre showvminfo';Ok $R;$Info=MR $R.Rows
    Need $Info 'VMState' 'running';Need $Info 'CfgFile' $VboxFile;Need $Info 'IDE-1-0' $Vdi;Need $Info 'IDE-0-1' $Iso
    Need $Info 'boot1' 'dvd';Need $Info 'boot2' 'disk';Need $Info 'boot3' 'none';Need $Info 'boot4' 'none'
    foreach($I in 1..8){$K="nic$I";if($Info.ContainsKey($K)){Need $Info $K 'none'}}

    Write-Host 'R5 RESTART BOUNDARY: R4 NO-VISUAL-DELTA + RUNNING VM GATES PASSED'
    $R=Native $VBox @('controlvm',$Uuid,'poweroff') 'poweroff';Ok $R
    $Deadline=[DateTime]::UtcNow.AddSeconds(20)
    do{$Current=State;if($Current-eq'poweroff'){break};Start-Sleep -Milliseconds 250}while([DateTime]::UtcNow-lt$Deadline)
    if($Current-ne'poweroff'){throw "VM did not reach poweroff: $Current"}

    Write-Host 'R5 START BOUNDARY: POWEROFF VERIFIED'
    $R=Native $VBox @('startvm',$Uuid,'--type','headless') 'start';Ok $R
    $Deadline=[DateTime]::UtcNow.AddSeconds(20)
    do{$Current=State;if($Current-eq'running'){break};Start-Sleep -Milliseconds 250}while([DateTime]::UtcNow-lt$Deadline)
    if($Current-ne'running'){throw "VM did not reach running: $Current"}
    Start-Sleep -Seconds 12
    if((State)-ne'running'){throw 'VM left running before pre-capture'}

    $Pre=Shot $PrePng 'pre screenshot'
    Marker
    $Mark=Shot $MarkerPng 'marker screenshot'
    Different $Pre $Mark 'marker'

    Write-Host 'R5 INPUT LIVE: MARKER SCREEN DELTA OBSERVED'
    SendDir 'T:/Compiler/ICLCC.CPP.Z' 'source'
    $Source=Shot $SourcePng 'source screenshot'
    Different $Mark $Source 'source probe'

    Write-Host 'R5 SOURCE DELTA: OBSERVED'
    SendDir 'T:/Compiler/Compiler.PRJ.Z' 'project'
    $Project=Shot $ProjectPng 'project screenshot'
    Different $Source $Project 'project probe'

    $R=Native $VBox @('showvminfo',$Uuid,'--machinereadable') 'post showvminfo';Ok $R;$Post=MR $R.Rows;Need $Post 'VMState' 'running'
    $R=Native $VBox @('list','runningvms') 'post runningvms';Ok $R;$PostRows=@($R.Rows|Where-Object{$_.Trim().Length-gt 0})
    if($PostRows.Count-ne 1-or$PostRows[0].Trim()-cne$Expected){throw 'post running inventory mismatch'}

    $Lines=@('DBYTE-HOLYC-OPT','TEMPLEOSTS 1.10 / COMPRESSED PATHS R5','',"r4_report_sha256`t$R4ReportHash","r4_visual_hash`t$R4PngHash","pre_png_sha256`t$($Pre.SHA256)","marker_png_sha256`t$($Mark.SHA256)","source_png_sha256`t$($Source.SHA256)","project_png_sha256`t$($Project.SHA256)",'marker_delta`tPASS','source_delta`tPASS','project_delta`tPASS',"post_vm_state`trunning","post_running_rows`t$($PostRows.Count)",'INSTALL`tNOT-EXECUTED','TARGET COMPILER FILE WRITE`tNOT-EXECUTED','COMPILER BUILD`tNOT-EXECUTED','STORAGE ATTACH/MODIFY`tNOT-EXECUTED','NETWORK ENABLEMENT`tNOT-EXECUTED','STATUS`tR5-CAPTURED-VISUAL-ADJUDICATION-PENDING','','REPORTS ARE CLAIMS, NOT EVIDENCE.')
    [IO.File]::WriteAllText($Report,(($Lines-join"`n")+"`n"),[Text.UTF8Encoding]::new($false))
    $ReportHash=(Get-FileHash -LiteralPath $Report -Algorithm SHA256).Hash
    Write-Host "PRE PNG SHA256: $($Pre.SHA256)"
    Write-Host "MARKER PNG SHA256: $($Mark.SHA256)"
    Write-Host "SOURCE PNG SHA256: $($Source.SHA256)"
    Write-Host "PROJECT PNG SHA256: $($Project.SHA256)"
    Write-Host 'POST STATE: running'
    Write-Host "RUNNING ROWS: $($PostRows.Count)"
    Write-Host "REPORT: $Report"
    Write-Host "REPORT SHA256: $ReportHash"
    Write-Host 'VERDICT: R5 INPUT LIVE + COMPRESSED PATH SCREEN DELTAS PASS / VISUAL ADJUDICATION PENDING'
}
finally{[Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$OldHome,[EnvironmentVariableTarget]::Process)}
