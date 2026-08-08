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
$R2PostHash='0CD00EB81A4902E30FF1236AD79D6F7B1EEB72C94F6DD8A241185FE6805320D5'
$R2ReportHash='B1E197C412B5E01B44A5AAAB69EE11B2DBAD6096AFCDD26E8FCA9E9B4CF1B3C3'
$Machine=Join-Path $Root 'Machine'
$VBoxHome=Join-Path $Root 'VBoxUserHome'
$VboxFile=Join-Path $Machine 'Temple1.10.vbox'
$Vdi=Join-Path $Machine 'Temple1.10.vdi'
$Iso=Join-Path $Machine 'TempleOSTS.iso'
$R2Post=Join-Path $Root 'GUEST-QUOTE-SCANCODE-R2-POST.png'
$R2Report=Join-Path $Root 'GUEST-QUOTE-SCANCODE-R2.txt'
$TPng=Join-Path $Root 'GUEST-T-PATH-R3.png'
$AtaPng=Join-Path $Root 'GUEST-ATA-R3.png'
$Report=Join-Path $Root 'GUEST-T-PATH-ATA-R3.txt'

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
function Quote{
    $R=Native $VBox @('controlvm',$Uuid,'keyboardputscancode','2a','28','a8','aa') 'quote';Ok $R
}
function Text([string]$Value,[string]$Label){
    $R=Native $VBox @('controlvm',$Uuid,'keyboardputstring',$Value) $Label;Ok $R
}
function Enter{
    $R=Native $VBox @('controlvm',$Uuid,'keyboardputscancode','1c','9c') 'enter';Ok $R
}
function Shot([string]$Path,[string]$Label){
    $R=Native $VBox @('controlvm',$Uuid,'screenshotpng',$Path) $Label;Ok $R
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "$Label PNG missing"}
    $Bytes=[IO.File]::ReadAllBytes($Path);if($Bytes.Length-lt 8){throw "$Label PNG too small"}
    $Sig=@(137,80,78,71,13,10,26,10);for($I=0;$I-lt 8;$I++){if($Bytes[$I]-ne$Sig[$I]){throw "$Label PNG signature mismatch"}}
    [pscustomobject]@{Bytes=$Bytes.Length;SHA256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
}

foreach($P in @($VBox,$VboxFile,$Vdi,$Iso,$R2Post,$R2Report)){if(-not(Test-Path -LiteralPath $P -PathType Leaf)){throw "missing: $P"}}
foreach($P in @($TPng,$AtaPng,$Report)){if(Test-Path -LiteralPath $P){throw "output exists: $P"}}
HashIs $Iso $IsoHash 'ISO'
HashIs $R2Post $R2PostHash 'R2 post PNG'
HashIs $R2Report $R2ReportHash 'R2 report'

$OldHome=[Environment]::GetEnvironmentVariable('VBOX_USER_HOME',[EnvironmentVariableTarget]::Process)
if(-not[string]::IsNullOrEmpty($OldHome)){throw "VBOX_USER_HOME must be unset: $OldHome"}
[Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$VBoxHome,[EnvironmentVariableTarget]::Process)
try{
    $R=Native $VBox @('--version') 'version';Ok $R
    if($R.Rows.Count-ne 1-or$R.Rows[0].Trim()-cne$VersionExpected){throw 'VirtualBox version mismatch'}
    $R=Native $VBox @('list','runningvms') 'runningvms';Ok $R
    $Rows=@($R.Rows|Where-Object{$_.Trim().Length-gt 0});$Q=[string][char]34;$Expected=$Q+$Name+$Q+' {'+$Uuid+'}'
    if($Rows.Count-ne 1-or$Rows[0].Trim()-cne$Expected){throw "running inventory mismatch: $($Rows -join ' | ')"}
    $R=Native $VBox @('showvminfo',$Uuid,'--machinereadable') 'showvminfo';Ok $R;$Info=MR $R.Rows
    Need $Info 'VMState' 'running';Need $Info 'CfgFile' $VboxFile;Need $Info 'IDE-1-0' $Vdi;Need $Info 'IDE-0-1' $Iso;Need $Info 'boot1' 'dvd';Need $Info 'boot2' 'disk'
    foreach($I in 1..8){$K="nic$I";if($Info.ContainsKey($K)){Need $Info $K 'none'}}

    Write-Host 'R3 T-PATH BOUNDARY: QUOTE TRANSPORT + RUNNING VM GATES PASSED'
    Text 'Dir(' 'Dir prefix';Quote;Text 'T:/Compiler/ICLCC.CPP' 'T path';Quote;Text ');' 'Dir suffix';Enter
    Start-Sleep -Seconds 2
    $T=Shot $TPng 'T path screenshot'
    if((Native $VBox @('showvminfo',$Uuid,'--machinereadable') 'post T state').Rows -join"`n" -notmatch '(?m)^VMState="?running"?$'){throw 'VM not running after T probe'}

    Write-Host 'R3 ATA BOUNDARY: T-PATH CAPTURED'
    Text 'ATARep(FALSE,TRUE);' 'ATARep';Enter
    Start-Sleep -Seconds 2
    $Ata=Shot $AtaPng 'ATA screenshot'

    $R=Native $VBox @('showvminfo',$Uuid,'--machinereadable') 'post showvminfo';Ok $R;$Post=MR $R.Rows;Need $Post 'VMState' 'running'
    $R=Native $VBox @('list','runningvms') 'post runningvms';Ok $R;$PostRows=@($R.Rows|Where-Object{$_.Trim().Length-gt 0})
    if($PostRows.Count-ne 1-or$PostRows[0].Trim()-cne$Expected){throw 'post-probe running inventory mismatch'}

    $Lines=@('DBYTE-HOLYC-OPT','TEMPLEOSTS 1.10 / GUEST T-PATH + ATA PROBE R3','',"r2_post_png_sha256`t$R2PostHash","r2_report_sha256`t$R2ReportHash","t_command`tDir(quote T:/Compiler/ICLCC.CPP quote);","t_png`t$TPng","t_png_bytes`t$($T.Bytes)","t_png_sha256`t$($T.SHA256)","ata_command`tATARep(FALSE,TRUE);","ata_png`t$AtaPng","ata_png_bytes`t$($Ata.Bytes)","ata_png_sha256`t$($Ata.SHA256)","post_vm_state`trunning","post_running_rows`t$($PostRows.Count)",'C DRIVE PROBE`tNOT-EXECUTED','TARGET COMPILER FILE WRITE`tNOT-EXECUTED','COMPILER BUILD`tNOT-EXECUTED','INSTALL`tNOT-EXECUTED','VM START/STOP/RESET`tNOT-EXECUTED','STORAGE ATTACH/MODIFY`tNOT-EXECUTED','NETWORK ENABLEMENT`tNOT-EXECUTED','INTERACTIVE TEMP PATH`tMAY-BE-WRITTEN-BY-GUEST-COMMAND-LINE','STATUS`tR3-CAPTURED-VISUAL-ADJUDICATION-PENDING','','REPORTS ARE CLAIMS, NOT EVIDENCE.')
    [IO.File]::WriteAllText($Report,(($Lines-join"`n")+"`n"),[Text.UTF8Encoding]::new($false))
    $ReportHash=(Get-FileHash -LiteralPath $Report -Algorithm SHA256).Hash
    Write-Host "T PNG: $TPng";Write-Host "T PNG SHA256: $($T.SHA256)";Write-Host "ATA PNG: $AtaPng";Write-Host "ATA PNG SHA256: $($Ata.SHA256)";Write-Host 'POST STATE: running';Write-Host "RUNNING ROWS: $($PostRows.Count)";Write-Host "REPORT: $Report";Write-Host "REPORT SHA256: $ReportHash";Write-Host 'VERDICT: R3 T-PATH + ATA CAPTURED / VISUAL ADJUDICATION PENDING'
}
finally{[Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$OldHome,[EnvironmentVariableTarget]::Process)}
