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
$R1PngHash='04B80A576F5D4FBC161D763247DEE47F6321A4BE46EF680E207E459AFA4B3DD5'
$R1ReportHash='83A2B2A73D4684C4FDA6B89A64ED6809AE72E14884B39CBF98995286657D0BF3'
$Machine=Join-Path $Root 'Machine'
$VBoxHome=Join-Path $Root 'VBoxUserHome'
$VboxFile=Join-Path $Machine 'Temple1.10.vbox'
$Vdi=Join-Path $Machine 'Temple1.10.vdi'
$Iso=Join-Path $Machine 'TempleOSTS.iso'
$R1Png=Join-Path $Root 'GUEST-SHELL-PROBE-R1.png'
$R1Report=Join-Path $Root 'GUEST-SHELL-PROBE-R1.txt'
$PrePng=Join-Path $Root 'GUEST-QUOTE-SCANCODE-R2-PRE.png'
$PostPng=Join-Path $Root 'GUEST-QUOTE-SCANCODE-R2-POST.png'
$Report=Join-Path $Root 'GUEST-QUOTE-SCANCODE-R2.txt'

function Native([string]$FilePath,[string[]]$ArgumentList,[string]$Label){
    $Old=$ErrorActionPreference
    try{
        $ErrorActionPreference='Continue'
        $Rows=@(& $FilePath @ArgumentList 2>&1 | ForEach-Object { [string]$_ })
        $Code=$LASTEXITCODE
    }
    finally{$ErrorActionPreference=$Old}
    [pscustomobject]@{Label=$Label;Code=[int]$Code;Rows=[string[]]$Rows}
}
function Ok($R){
    if($R.Code-ne 0){throw "$($R.Label) failed exit=$($R.Code) output=$($R.Rows -join ' | ')"}
}
function MR([string[]]$Rows){
    $Map=@{}
    $S=[string][char]92
    $SS=$S+$S
    $EQ=$S+[string][char]34
    foreach($Row in $Rows){
        if($Row-notmatch'^([^=]+)=(.*)$'){continue}
        $K=[string]$Matches[1]
        $V=[string]$Matches[2]
        if($K.Length-ge 2-and$K[0]-eq[char]34-and$K[$K.Length-1]-eq[char]34){
            $K=$K.Substring(1,$K.Length-2).Replace($EQ,[string][char]34).Replace($SS,$S)
        }
        if($V.Length-ge 2-and$V[0]-eq[char]34-and$V[$V.Length-1]-eq[char]34){
            $V=$V.Substring(1,$V.Length-2).Replace($EQ,[string][char]34).Replace($SS,$S)
        }
        if([string]::IsNullOrWhiteSpace($K)-or$Map.ContainsKey($K)){throw "bad key: $K"}
        $Map[$K]=$V
    }
    $Map
}
function Need($Map,[string]$Key,[string]$Expected){
    if(-not$Map.ContainsKey($Key)){throw "missing key: $Key"}
    if(-not[string]::Equals([string]$Map[$Key],$Expected,[System.StringComparison]::OrdinalIgnoreCase)){
        throw "$Key mismatch observed=$($Map[$Key]) expected=$Expected"
    }
}
function State{
    $R=Native $VBox @('showvminfo',$Uuid,'--machinereadable') 'showvminfo'
    Ok $R
    $M=MR $R.Rows
    if(-not$M.ContainsKey('VMState')){throw 'VMState missing'}
    [string]$M['VMState']
}
function HashIs([string]$Path,[string]$Expected,[string]$Label){
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "missing: $Path"}
    $Actual=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if($Actual-cne$Expected){throw "$Label hash mismatch actual=$Actual expected=$Expected"}
}
function Capture([string]$Path,[string]$Label){
    $R=Native $VBox @('controlvm',$Uuid,'screenshotpng',$Path) $Label
    Ok $R
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "$Label PNG missing"}
    $Bytes=[System.IO.File]::ReadAllBytes($Path)
    if($Bytes.Length-lt 8){throw "$Label PNG too small"}
    $Sig=@(137,80,78,71,13,10,26,10)
    for($I=0;$I-lt 8;$I++){if($Bytes[$I]-ne$Sig[$I]){throw "$Label PNG signature mismatch"}}
    [pscustomobject]@{
        Bytes=$Bytes.Length
        SHA256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }
}
function SendQuote{
    # Set-1 US keyboard: LSHIFT down, quote/apostrophe key down/up, LSHIFT up.
    $R=Native $VBox @('controlvm',$Uuid,'keyboardputscancode','2a','28','a8','aa') 'quote scancode'
    Ok $R
}
function SendText([string]$Text,[string]$Label){
    $R=Native $VBox @('controlvm',$Uuid,'keyboardputstring',$Text) $Label
    Ok $R
}
function SendEnter{
    $R=Native $VBox @('controlvm',$Uuid,'keyboardputscancode','1c','9c') 'enter scancode'
    Ok $R
}

foreach($P in @($VBox,$VboxFile,$Vdi,$Iso,$R1Png,$R1Report)){
    if(-not(Test-Path -LiteralPath $P -PathType Leaf)){throw "missing: $P"}
}
foreach($P in @($PrePng,$PostPng,$Report)){
    if(Test-Path -LiteralPath $P){throw "output exists: $P"}
}
HashIs $Iso $IsoHash 'ISO'
HashIs $R1Png $R1PngHash 'R1 probe PNG'
HashIs $R1Report $R1ReportHash 'R1 probe report'

$OldHome=[Environment]::GetEnvironmentVariable('VBOX_USER_HOME',[EnvironmentVariableTarget]::Process)
if(-not[string]::IsNullOrEmpty($OldHome)){throw "VBOX_USER_HOME must be unset: $OldHome"}

$PoweroffIssued=$false
$StartIssued=$false
$InputIssued=$false
$PoweroffExit=-1
$StartExit=-1
$Pre=$null
$Post=$null
$PostState=''
$PostRows=-1

[Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$VBoxHome,[EnvironmentVariableTarget]::Process)
try{
    $R=Native $VBox @('--version') 'version'
    Ok $R
    if($R.Rows.Count-ne 1-or$R.Rows[0].Trim()-cne$VersionExpected){throw 'VirtualBox version mismatch'}

    $R=Native $VBox @('list','vms') 'list vms'
    Ok $R
    $Rows=@($R.Rows|Where-Object{$_.Trim().Length-gt 0})
    $Q=[string][char]34
    $Expected=$Q+$Name+$Q+' {'+$Uuid+'}'
    if($Rows.Count-ne 1-or$Rows[0].Trim()-cne$Expected){throw "registered inventory mismatch: $($Rows -join ' | ')"}

    $R=Native $VBox @('list','runningvms') 'pre-restart runningvms'
    Ok $R
    $Rows=@($R.Rows|Where-Object{$_.Trim().Length-gt 0})
    if($Rows.Count-ne 1-or$Rows[0].Trim()-cne$Expected){throw "pre-restart running inventory mismatch: $($Rows -join ' | ')"}

    $R=Native $VBox @('showvminfo',$Uuid,'--machinereadable') 'pre-restart showvminfo'
    Ok $R
    $Info=MR $R.Rows
    Need $Info 'name' $Name
    Need $Info 'UUID' $Uuid
    Need $Info 'VMState' 'running'
    Need $Info 'CfgFile' $VboxFile
    Need $Info 'IDE-1-0' $Vdi
    Need $Info 'IDE-0-1' $Iso
    Need $Info 'boot1' 'dvd'
    Need $Info 'boot2' 'disk'
    Need $Info 'boot3' 'none'
    Need $Info 'boot4' 'none'
    foreach($I in 1..8){$K="nic$I";if($Info.ContainsKey($K)){Need $Info $K 'none'}}

    Write-Host 'R2 RESTART BOUNDARY: R1 FAILURE EVIDENCE + RUNNING VM GATES PASSED'
    $PoweroffIssued=$true
    $R=Native $VBox @('controlvm',$Uuid,'poweroff') 'controlled poweroff'
    $PoweroffExit=$R.Code
    Ok $R

    $Deadline=[DateTime]::UtcNow.AddSeconds(20)
    do{
        $Current=State
        if($Current-eq'poweroff'){break}
        Start-Sleep -Milliseconds 250
    }while([DateTime]::UtcNow-lt$Deadline)
    if($Current-ne'poweroff'){throw "VM did not reach poweroff: $Current"}

    $R=Native $VBox @('list','runningvms') 'post-poweroff runningvms'
    Ok $R
    if(@($R.Rows|Where-Object{$_.Trim().Length-gt 0}).Count-ne 0){throw 'running VM remained after poweroff'}

    Write-Host 'R2 HEADLESS START BOUNDARY: POWEROFF VERIFIED'
    $StartIssued=$true
    $R=Native $VBox @('startvm',$Uuid,'--type','headless') 'headless start'
    $StartExit=$R.Code
    Ok $R

    $Deadline=[DateTime]::UtcNow.AddSeconds(20)
    do{
        $Current=State
        if($Current-eq'running'){break}
        Start-Sleep -Milliseconds 250
    }while([DateTime]::UtcNow-lt$Deadline)
    if($Current-ne'running'){throw "VM did not reach running: $Current"}

    Start-Sleep -Seconds 12
    if((State)-ne'running'){throw 'VM left running state before R2 pre-capture'}

    $Pre=Capture $PrePng 'R2 pre-input screenshot'

    # Exactly one guest command is sent. Quotes are emitted as raw Set-1 scancodes,
    # not as embedded characters inside keyboardputstring.
    $InputIssued=$true
    SendQuote
    SendText 'DBYTE_QUOTE_SCANCODE_R2' 'marker text'
    SendQuote
    SendText ';' 'marker semicolon'
    SendEnter
    Start-Sleep -Seconds 2

    $Post=Capture $PostPng 'R2 post-input screenshot'

    $PostState=State
    $R=Native $VBox @('list','runningvms') 'post-input runningvms'
    Ok $R
    $Rows=@($R.Rows|Where-Object{$_.Trim().Length-gt 0})
    $PostRows=$Rows.Count
    if($PostState-ne'running'){throw "post-input state mismatch: $PostState"}
    if($Rows.Count-ne 1-or$Rows[0].Trim()-cne$Expected){throw "post-input running inventory mismatch: $($Rows -join ' | ')"}

    $Lines=@(
        'DBYTE-HOLYC-OPT',
        'TEMPLEOSTS 1.10 / QUOTE SCANCODE TRANSPORT PROBE R2',
        '',
        "r1_probe_png_sha256`t$R1PngHash",
        "r1_probe_report_sha256`t$R1ReportHash",
        "poweroff_exit`t$PoweroffExit",
        "start_exit`t$StartExit",
        "pre_png`t$PrePng",
        "pre_png_bytes`t$($Pre.Bytes)",
        "pre_png_sha256`t$($Pre.SHA256)",
        "command`tquoted DBYTE_QUOTE_SCANCODE_R2 marker only",
        "quote_transport`tLSHIFT 2a + QUOTE 28/a8 + LSHIFT-UP aa",
        "post_png`t$PostPng",
        "post_png_bytes`t$($Post.Bytes)",
        "post_png_sha256`t$($Post.SHA256)",
        "post_vm_state`t$PostState",
        "post_running_rows`t$PostRows",
        'DEBUGGER COMMAND G/Fix/Exit`tNOT-EXECUTED',
        'PATH PROBE`tNOT-EXECUTED',
        'TARGET COMPILER FILE WRITE`tNOT-EXECUTED',
        'COMPILER BUILD`tNOT-EXECUTED',
        'STORAGE ATTACH/MODIFY`tNOT-EXECUTED',
        'NETWORK ENABLEMENT`tNOT-EXECUTED',
        'INTERACTIVE TEMP PATH`tMAY-BE-WRITTEN-BY-GUEST-COMMAND-LINE',
        'STATUS`tQUOTE-SCANCODE-R2-CAPTURED-VISUAL-ADJUDICATION-PENDING',
        '',
        'REPORTS ARE CLAIMS, NOT EVIDENCE.'
    )
    [System.IO.File]::WriteAllText($Report,(($Lines-join"`n")+"`n"),[System.Text.UTF8Encoding]::new($false))
    $ReportHash=(Get-FileHash -LiteralPath $Report -Algorithm SHA256).Hash

    Write-Host "POWEROFF EXIT: $PoweroffExit"
    Write-Host "START EXIT: $StartExit"
    Write-Host "PRE PNG: $PrePng"
    Write-Host "PRE PNG SHA256: $($Pre.SHA256)"
    Write-Host "POST PNG: $PostPng"
    Write-Host "POST PNG SHA256: $($Post.SHA256)"
    Write-Host "POST STATE: $PostState"
    Write-Host "RUNNING ROWS: $PostRows"
    Write-Host "REPORT: $Report"
    Write-Host "REPORT SHA256: $ReportHash"
    Write-Host 'VERDICT: QUOTE SCANCODE R2 CAPTURED / VISUAL ADJUDICATION PENDING'
}
catch{
    if(($PoweroffIssued-or$StartIssued-or$InputIssued)-and-not(Test-Path -LiteralPath $Report)){
        $Lines=@(
            'DBYTE-HOLYC-OPT',
            'TEMPLEOSTS 1.10 / QUOTE SCANCODE TRANSPORT PROBE R2 FAILURE',
            '',
            "poweroff_issued`t$PoweroffIssued",
            "poweroff_exit`t$PoweroffExit",
            "start_issued`t$StartIssued",
            "start_exit`t$StartExit",
            "input_issued`t$InputIssued",
            "post_state`t$PostState",
            "post_running_rows`t$PostRows",
            "error`t$($_.Exception.Message)",
            'AUTOMATIC EXTRA VM MUTATION`tNOT-EXECUTED',
            'TARGET COMPILER FILE WRITE`tNOT-EXECUTED-BY-SCRIPT-CONTENT',
            'COMPILER BUILD`tNOT-EXECUTED',
            'STATUS`tR2-FAILED-AFTER-BOUNDARY',
            '',
            'REPORTS ARE CLAIMS, NOT EVIDENCE.'
        )
        try{[System.IO.File]::WriteAllText($Report,(($Lines-join"`n")+"`n"),[System.Text.UTF8Encoding]::new($false))}catch{}
    }
    throw
}
finally{
    [Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$OldHome,[EnvironmentVariableTarget]::Process)
}
