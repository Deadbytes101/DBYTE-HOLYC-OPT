[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$VBox = 'D:\Portable-VirtualBox7\app64\VBoxManage.exe'
$Root = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-ISOBOOT-FRESH-R1'
$Uuid = '9c98691e-27cd-4487-a306-587969c2c78c'
$Name = 'Temple1.10'
$ExpectedVersion = '7.0.12r159484'
$ExpectedStartHash = '23E802ADF0EF790F51D6D4DECA66EE0D10C755AE6C818CAA1C3934100BE43D76'
$ExpectedIsoHash = 'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$Driver = 'D:\Portable-VirtualBox7\app64\drivers\vboxsup\VBoxSup.sys'
$ExpectedDriverHash = '3344E2909580A9965E38B26AB9E9958842315DDEA1B0D0E274DA314DDCAB97F4'
$Sc = Join-Path $env:SystemRoot 'System32\sc.exe'
$Machine = Join-Path $Root 'Machine'
$VBoxHome = Join-Path $Root 'VBoxUserHome'
$VboxFile = Join-Path $Machine 'Temple1.10.vbox'
$Vdi = Join-Path $Machine 'Temple1.10.vdi'
$Iso = Join-Path $Machine 'TempleOSTS.iso'
$Start = Join-Path $Root 'START.txt'
$Png = Join-Path $Root 'VISUAL.png'
$Report = Join-Path $Root 'VISUAL.txt'

function Native([string]$File,[string[]]$Args) {
    $Old = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $Rows = @(& $File @Args 2>&1 | ForEach-Object { [string]$_ })
        $Code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $Old }
    [pscustomobject]@{ Code = [int]$Code; Rows = [string[]]$Rows }
}

function Ok($R,[string]$Label) {
    if ($R.Code -ne 0) {
        throw "$Label failed exit=$($R.Code) output=$($R.Rows -join ' | ')"
    }
}

function MR([string[]]$Rows) {
    $Map = @{}
    $S = [string][char]92
    $SS = $S + $S
    $EQ = $S + [string][char]34
    foreach ($Row in $Rows) {
        if ($Row -notmatch '^([^=]+)=(.*)$') { continue }
        $K = [string]$Matches[1]
        $V = [string]$Matches[2]
        if ($K.Length -ge 2 -and $K[0] -eq [char]34 -and $K[$K.Length - 1] -eq [char]34) {
            $K = $K.Substring(1,$K.Length - 2).Replace($EQ,[string][char]34).Replace($SS,$S)
        }
        if ($V.Length -ge 2 -and $V[0] -eq [char]34 -and $V[$V.Length - 1] -eq [char]34) {
            $V = $V.Substring(1,$V.Length - 2).Replace($EQ,[string][char]34).Replace($SS,$S)
        }
        if ($Map.ContainsKey($K)) { throw "duplicate key: $K" }
        $Map[$K] = $V
    }
    $Map
}

function Need($Map,[string]$Key,[string]$Expected) {
    if (-not $Map.ContainsKey($Key)) { throw "missing key: $Key" }
    if (-not [string]::Equals([string]$Map[$Key],$Expected,[System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Key mismatch observed=$($Map[$Key]) expected=$Expected"
    }
}

foreach ($Path in @($VBox,$Sc,$Driver,$VboxFile,$Vdi,$Iso,$Start)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "missing: $Path" }
}
if (Test-Path -LiteralPath $Png) { throw "visual PNG exists: $Png" }
if (Test-Path -LiteralPath $Report) { throw "visual report exists: $Report" }
if ((Get-FileHash -LiteralPath $Start -Algorithm SHA256).Hash -cne $ExpectedStartHash) { throw 'START.txt hash mismatch' }
if ((Get-FileHash -LiteralPath $Driver -Algorithm SHA256).Hash -cne $ExpectedDriverHash) { throw 'VBoxSup.sys hash mismatch' }
if ((Get-FileHash -LiteralPath $Iso -Algorithm SHA256).Hash -cne $ExpectedIsoHash) { throw 'ISO hash mismatch' }

$Svc = Native $Sc @('query','VBoxSup')
Ok $Svc 'sc query VBoxSup'
if (($Svc.Rows -join "`n") -notmatch '(?im)^\s*STATE\s*:\s*4\b') { throw 'VBoxSup not running' }

$OldHome = [Environment]::GetEnvironmentVariable('VBOX_USER_HOME',[EnvironmentVariableTarget]::Process)
if (-not [string]::IsNullOrEmpty($OldHome)) { throw "VBOX_USER_HOME must be unset: $OldHome" }

[Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$VBoxHome,[EnvironmentVariableTarget]::Process)
try {
    $Ver = Native $VBox @('--version')
    Ok $Ver 'version'
    if ($Ver.Rows.Count -ne 1 -or $Ver.Rows[0].Trim() -cne $ExpectedVersion) { throw 'VirtualBox version mismatch' }

    $Run = Native $VBox @('list','runningvms')
    Ok $Run 'runningvms'
    $Rows = @($Run.Rows | Where-Object { $_.Trim().Length -gt 0 })
    $Q = [string][char]34
    $Expected = $Q + $Name + $Q + ' {' + $Uuid + '}'
    if ($Rows.Count -ne 1 -or $Rows[0].Trim() -cne $Expected) { throw "running inventory mismatch: $($Rows -join ' | ')" }

    $InfoR = Native $VBox @('showvminfo',$Uuid,'--machinereadable')
    Ok $InfoR 'showvminfo'
    $Info = MR $InfoR.Rows
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
    foreach ($I in 1..8) {
        $K = "nic$I"
        if ($Info.ContainsKey($K)) { Need $Info $K 'none' }
    }

    $Shot = Native $VBox @('controlvm',$Uuid,'screenshotpng',$Png)
    Ok $Shot 'screenshotpng'
}
finally {
    [Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$OldHome,[EnvironmentVariableTarget]::Process)
}

if (-not (Test-Path -LiteralPath $Png -PathType Leaf)) { throw 'visual PNG not created' }
$Bytes = [System.IO.File]::ReadAllBytes($Png)
if ($Bytes.Length -lt 8) { throw 'visual PNG too small' }
$Sig = @(137,80,78,71,13,10,26,10)
for ($I = 0; $I -lt 8; $I++) {
    if ($Bytes[$I] -ne $Sig[$I]) { throw 'visual PNG signature mismatch' }
}

$Hash = (Get-FileHash -LiteralPath $Png -Algorithm SHA256).Hash
$Lines = @(
    'DBYTE-HOLYC-OPT',
    'TEMPLEOSTS 1.10 / FRESH ISO BOOT R1 / VISUAL CAPTURE',
    '',
    "start_report_sha256`t$ExpectedStartHash",
    "visual_png`t$Png",
    "visual_png_bytes`t$($Bytes.Length)",
    "visual_png_sha256`t$Hash",
    "machine_uuid`t$Uuid",
    "machine_state_before_capture`trunning",
    "CONTROLVM`tSCREENSHOTPNG-ONLY",
    "VM START/STOP`tNOT-EXECUTED",
    "STORAGE MUTATION`tNOT-EXECUTED",
    "COMPILER BUILD`tNOT-EXECUTED",
    "STATUS`tVISUAL-CAPTURE-ACQUIRED-CONTENT-PENDING-ADJUDICATION",
    '',
    'REPORTS ARE CLAIMS, NOT EVIDENCE.'
)
[System.IO.File]::WriteAllText($Report,(($Lines -join "`n") + "`n"),[System.Text.UTF8Encoding]::new($false))
Write-Host "VISUAL PNG: $Png"
Write-Host "PNG SHA256: $Hash"
Write-Host "PNG BYTES: $($Bytes.Length)"
Write-Host "REPORT: $Report"
Write-Host 'VERDICT: VISUAL CAPTURE ACQUIRED / CONTENT ADJUDICATION PENDING'
