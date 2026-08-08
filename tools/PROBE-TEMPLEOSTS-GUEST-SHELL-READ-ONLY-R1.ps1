[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$VBox='D:\Portable-VirtualBox7\app64\VBoxManage.exe'
$Root='D:\TECHNICAL\DBYTE-HOLYC-OPT-ISOBOOT-FRESH-R1'
$Uuid='9c98691e-27cd-4487-a306-587969c2c78c'
$Name='Temple1.10'
$VersionExpected='7.0.12r159484'
$CaptureHash='15AA06C62838EE226284630E5E42BCC9303B5C51433253A15D0E8D4B45E353AF'
$VisualHash='B051E8B85D8E1D6B32A8DC4D82BB8F35AC62894AF13F61995A7DA96E3AABD879'
$IsoHash='DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$Machine=Join-Path $Root 'Machine'
$VBoxHome=Join-Path $Root 'VBoxUserHome'
$Iso=Join-Path $Machine 'TempleOSTS.iso'
$Capture=Join-Path $Root 'HEADLESS-CAPTURE-R1.txt'
$Visual=Join-Path $Root 'VISUAL-HEADLESS-R1.png'
$Png=Join-Path $Root 'GUEST-SHELL-PROBE-R1.png'
$Report=Join-Path $Root 'GUEST-SHELL-PROBE-R1.txt'

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
function Send([string]$Text){
    $R=Native $VBox @('controlvm',$Uuid,'keyboardputstring',$Text) 'keyboardputstring';Ok $R
    $R=Native $VBox @('controlvm',$Uuid,'keyboardputscancode','1c','9c') 'keyboard enter';Ok $R
    Start-Sleep -Milliseconds 700
}

foreach($P in @($VBox,$Iso,$Capture,$Visual)){if(-not(Test-Path -LiteralPath $P -PathType Leaf)){throw "missing: $P"}}
if(Test-Path -LiteralPath $Png){throw "PNG exists: $Png"}
if(Test-Path -LiteralPath $Report){throw "report exists: $Report"}
HashIs $Capture $CaptureHash 'capture report'
HashIs $Visual $VisualHash 'visual PNG'
HashIs $Iso $IsoHash 'ISO'

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
    Need $Info 'VMState' 'running';Need $Info 'IDE-0-1' $Iso;Need $Info 'boot1' 'dvd';Need $Info 'boot2' 'disk'
    foreach($I in 1..8){$K="nic$I";if($Info.ContainsKey($K)){Need $Info $K 'none'}}

    Send '"DBYTE_GUEST_SHELL_R1\n";'
    Send 'Dir("C:/Compiler/ICLCC.CPP");'
    Send 'Dir("T:/Compiler/ICLCC.CPP");'

    $R=Native $VBox @('controlvm',$Uuid,'screenshotpng',$Png) 'screenshotpng';Ok $R
    if(-not(Test-Path -LiteralPath $Png -PathType Leaf)){throw 'probe PNG not created'}
    $Bytes=[System.IO.File]::ReadAllBytes($Png);if($Bytes.Length-lt 8){throw 'probe PNG too small'}
    $Sig=@(137,80,78,71,13,10,26,10);for($I=0;$I-lt 8;$I++){if($Bytes[$I]-ne$Sig[$I]){throw 'probe PNG signature mismatch'}}
    $PngHash=(Get-FileHash -LiteralPath $Png -Algorithm SHA256).Hash

    $R=Native $VBox @('showvminfo',$Uuid,'--machinereadable') 'post showvminfo';Ok $R;$Post=MR $R.Rows;Need $Post 'VMState' 'running'
    $R=Native $VBox @('list','runningvms') 'post runningvms';Ok $R;$PostRows=@($R.Rows|Where-Object{$_.Trim().Length-gt 0})
    if($PostRows.Count-ne 1-or$PostRows[0].Trim()-cne$Expected){throw 'post-probe running inventory mismatch'}

    $Lines=@('DBYTE-HOLYC-OPT','TEMPLEOSTS 1.10 / GUEST SHELL READ-ONLY PROBE R1','',"capture_report_sha256`t$CaptureHash","prior_visual_sha256`t$VisualHash","probe_png`t$Png","probe_png_bytes`t$($Bytes.Length)","probe_png_sha256`t$PngHash","commands`tDBYTE marker | Dir C:/Compiler/ICLCC.CPP | Dir T:/Compiler/ICLCC.CPP","post_vm_state`trunning","post_running_rows`t$($PostRows.Count)","GUEST FILE WRITE`tNOT-EXECUTED","COMPILER BUILD`tNOT-EXECUTED","VM START/STOP/RESET`tNOT-EXECUTED","CONTROLVM`tKEYBOARD-INPUT-PLUS-SCREENSHOT-ONLY","STATUS`tGUEST-SHELL-PROBE-R1-CAPTURED",'','REPORTS ARE CLAIMS, NOT EVIDENCE.')
    [System.IO.File]::WriteAllText($Report,(($Lines-join"`n")+"`n"),[System.Text.UTF8Encoding]::new($false))
    $ReportHash=(Get-FileHash -LiteralPath $Report -Algorithm SHA256).Hash
    Write-Host "PNG: $Png";Write-Host "PNG SHA256: $PngHash";Write-Host "REPORT: $Report";Write-Host "REPORT SHA256: $ReportHash";Write-Host 'VERDICT: GUEST SHELL PROBE CAPTURED / VISUAL ADJUDICATION PENDING'
}
finally{[Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$OldHome,[EnvironmentVariableTarget]::Process)}
