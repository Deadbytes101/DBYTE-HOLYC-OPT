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
$ExpectedRuntimeHash = '0C4D594761ED669BBDD096B8B73BECD05685A8D1CE0568DAFC4849235E5EBC8A'
$ExpectedCauseHash = '78420DA53E37ACA5DCA0C000E6DBDD606704BB2FBF80F8DC9264D52757F89ADA'
$ExpectedVBoxHash = 'BB6058E7FF513B8261A1FC0B4D51C6A2ACC44DDE9CA0B2E9007B7A90DAC3CC76'
$ExpectedRegistryHash = '48B39A11E3E6E5FF1F2713143915E15A6F0CAE562357D92575D5DCDF569A968C'
$ExpectedIsoHash = 'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$Driver = 'D:\Portable-VirtualBox7\app64\drivers\vboxsup\VBoxSup.sys'
$ExpectedDriverHash = '3344E2909580A9965E38B26AB9E9958842315DDEA1B0D0E274DA314DDCAB97F4'
$Sc = Join-Path $env:SystemRoot 'System32\sc.exe'
$Machine = Join-Path $Root 'Machine'
$VBoxHome = Join-Path $Root 'VBoxUserHome'
$VboxFile = Join-Path $Machine 'Temple1.10.vbox'
$Vdi = Join-Path $Machine 'Temple1.10.vdi'
$Iso = Join-Path $Machine 'TempleOSTS.iso'
$Registry = Join-Path $VBoxHome 'VirtualBox.xml'
$StartReport = Join-Path $Root 'START.txt'
$RuntimeReport = Join-Path $Root 'RUNTIME-STATE-R1.txt'
$CauseReport = Join-Path $Root 'POWEROFF-CAUSE-R1.txt'
$Png = Join-Path $Root 'VISUAL-HEADLESS-R1.png'
$Report = Join-Path $Root 'HEADLESS-CAPTURE-R1.txt'

function Invoke-NativeCommand {
    param([string]$FilePath,[string[]]$ArgumentList,[string]$Label)
    $OldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $Rows = @(& $FilePath @ArgumentList 2>&1 | ForEach-Object { [string]$_ })
        $ExitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $OldPreference }
    [pscustomobject]@{ Label = $Label; ExitCode = [int]$ExitCode; Rows = [string[]]$Rows }
}

function Require-Success {
    param($Result)
    if ($Result.ExitCode -ne 0) { throw "$($Result.Label) failed exit=$($Result.ExitCode) output=$($Result.Rows -join ' | ')" }
}

function Convert-MachineReadable {
    param([string[]]$Rows)
    $Map = @{}
    $Slash = [string][char]92
    $DoubleSlash = $Slash + $Slash
    $EscapedQuote = $Slash + [string][char]34
    foreach ($Row in $Rows) {
        if ($Row -notmatch '^([^=]+)=(.*)$') { continue }
        $Key = [string]$Matches[1]
        $Value = [string]$Matches[2]
        if ($Key.Length -ge 2 -and $Key[0] -eq [char]34 -and $Key[$Key.Length - 1] -eq [char]34) {
            $Key = $Key.Substring(1,$Key.Length - 2).Replace($EscapedQuote,[string][char]34).Replace($DoubleSlash,$Slash)
        }
        if ($Value.Length -ge 2 -and $Value[0] -eq [char]34 -and $Value[$Value.Length - 1] -eq [char]34) {
            $Value = $Value.Substring(1,$Value.Length - 2).Replace($EscapedQuote,[string][char]34).Replace($DoubleSlash,$Slash)
        }
        if ([string]::IsNullOrWhiteSpace($Key)) { throw 'machine-readable key empty' }
        if ($Map.ContainsKey($Key)) { throw "duplicate machine-readable key: $Key" }
        $Map[$Key] = $Value
    }
    $Map
}

function Require-MapValue {
    param([hashtable]$Map,[string]$Key,[string]$Expected)
    if (-not $Map.ContainsKey($Key)) { throw "missing key: $Key" }
    if (-not [string]::Equals([string]$Map[$Key],$Expected,[System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Key mismatch observed=$($Map[$Key]) expected=$Expected"
    }
}

function Get-State {
    $Result = Invoke-NativeCommand -FilePath $VBox -ArgumentList @('showvminfo',$Uuid,'--machinereadable') -Label 'showvminfo'
    Require-Success $Result
    $Info = Convert-MachineReadable $Result.Rows
    if (-not $Info.ContainsKey('VMState')) { throw 'VMState missing' }
    [string]$Info['VMState']
}

foreach ($Path in @($VBox,$Sc,$Driver,$VboxFile,$Vdi,$Iso,$Registry,$StartReport,$RuntimeReport,$CauseReport)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "missing: $Path" }
}
if (Test-Path -LiteralPath $Png) { throw "PNG exists: $Png" }
if (Test-Path -LiteralPath $Report) { throw "report exists: $Report" }
if ((Get-FileHash -LiteralPath $StartReport -Algorithm SHA256).Hash -cne $ExpectedStartHash) { throw 'START.txt hash mismatch' }
if ((Get-FileHash -LiteralPath $RuntimeReport -Algorithm SHA256).Hash -cne $ExpectedRuntimeHash) { throw 'runtime report hash mismatch' }
if ((Get-FileHash -LiteralPath $CauseReport -Algorithm SHA256).Hash -cne $ExpectedCauseHash) { throw 'cause report hash mismatch' }
if ((Get-FileHash -LiteralPath $VboxFile -Algorithm SHA256).Hash -cne $ExpectedVBoxHash) { throw 'VBOX hash mismatch' }
if ((Get-FileHash -LiteralPath $Registry -Algorithm SHA256).Hash -cne $ExpectedRegistryHash) { throw 'registry hash mismatch' }
if ((Get-FileHash -LiteralPath $Iso -Algorithm SHA256).Hash -cne $ExpectedIsoHash) { throw 'ISO hash mismatch' }
if ((Get-FileHash -LiteralPath $Driver -Algorithm SHA256).Hash -cne $ExpectedDriverHash) { throw 'VBoxSup.sys hash mismatch' }

$Service = Invoke-NativeCommand -FilePath $Sc -ArgumentList @('query','VBoxSup') -Label 'sc query VBoxSup'
Require-Success $Service
if (($Service.Rows -join "`n") -notmatch '(?im)^\s*STATE\s*:\s*4\b') { throw 'VBoxSup not running' }

$Processes = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '(?i)^(VBoxSVC|VirtualBoxVM|VBoxHeadless|VirtualBox)$' })
if ($Processes.Count -ne 0) { throw "VirtualBox runtime already present: $($Processes.ProcessName -join ',')" }

$OriginalVBoxHome = [Environment]::GetEnvironmentVariable('VBOX_USER_HOME',[EnvironmentVariableTarget]::Process)
if (-not [string]::IsNullOrEmpty($OriginalVBoxHome)) { throw "VBOX_USER_HOME must be unset: $OriginalVBoxHome" }

$StartIssued = $false
$StartExit = -1
$StartRows = @()
$CaptureExit = -1
$CaptureRows = @()
$PostState = ''
$PostRunningCount = -1

[Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$VBoxHome,[EnvironmentVariableTarget]::Process)
try {
    $Version = Invoke-NativeCommand -FilePath $VBox -ArgumentList @('--version') -Label 'VBoxManage --version'
    Require-Success $Version
    if ($Version.Rows.Count -ne 1 -or $Version.Rows[0].Trim() -cne $ExpectedVersion) { throw 'VirtualBox version mismatch' }

    $List = Invoke-NativeCommand -FilePath $VBox -ArgumentList @('list','vms') -Label 'list vms'
    Require-Success $List
    $VmRows = @($List.Rows | Where-Object { $_.Trim().Length -gt 0 })
    $Quote = [string][char]34
    $ExpectedRow = $Quote + $Name + $Quote + ' {' + $Uuid + '}'
    if ($VmRows.Count -ne 1 -or $VmRows[0].Trim() -cne $ExpectedRow) { throw "registered inventory mismatch: $($VmRows -join ' | ')" }

    $Running = Invoke-NativeCommand -FilePath $VBox -ArgumentList @('list','runningvms') -Label 'list runningvms'
    Require-Success $Running
    if (@($Running.Rows | Where-Object { $_.Trim().Length -gt 0 }).Count -ne 0) { throw 'VM already running' }

    $InfoResult = Invoke-NativeCommand -FilePath $VBox -ArgumentList @('showvminfo',$Uuid,'--machinereadable') -Label 'pre-start showvminfo'
    Require-Success $InfoResult
    $Info = Convert-MachineReadable $InfoResult.Rows
    Require-MapValue $Info 'name' $Name
    Require-MapValue $Info 'UUID' $Uuid
    Require-MapValue $Info 'VMState' 'poweroff'
    Require-MapValue $Info 'CfgFile' $VboxFile
    Require-MapValue $Info 'IDE-1-0' $Vdi
    Require-MapValue $Info 'IDE-0-1' $Iso
    Require-MapValue $Info 'boot1' 'dvd'
    Require-MapValue $Info 'boot2' 'disk'
    Require-MapValue $Info 'boot3' 'none'
    Require-MapValue $Info 'boot4' 'none'
    foreach ($Index in 1..8) {
        $Key = "nic$Index"
        if ($Info.ContainsKey($Key)) { Require-MapValue $Info $Key 'none' }
    }

    Write-Host 'HEADLESS START BOUNDARY: ALL GATES PASSED'
    $StartIssued = $true
    $Start = Invoke-NativeCommand -FilePath $VBox -ArgumentList @('startvm',$Uuid,'--type','headless') -Label 'headless start'
    $StartExit = $Start.ExitCode
    $StartRows = @($Start.Rows)
    Require-Success $Start

    $Deadline = [DateTime]::UtcNow.AddSeconds(20)
    do {
        $State = Get-State
        if ($State -eq 'running') { break }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $Deadline)
    if ($State -ne 'running') { throw "VM did not reach running: $State" }

    Start-Sleep -Seconds 12
    if ((Get-State) -ne 'running') { throw 'VM left running state before capture' }

    $Capture = Invoke-NativeCommand -FilePath $VBox -ArgumentList @('controlvm',$Uuid,'screenshotpng',$Png) -Label 'screenshotpng'
    $CaptureExit = $Capture.ExitCode
    $CaptureRows = @($Capture.Rows)
    Require-Success $Capture

    if (-not (Test-Path -LiteralPath $Png -PathType Leaf)) { throw 'PNG not created' }
    $Bytes = [System.IO.File]::ReadAllBytes($Png)
    if ($Bytes.Length -lt 8) { throw 'PNG too small' }
    $Signature = @(137,80,78,71,13,10,26,10)
    for ($Index = 0; $Index -lt 8; $Index++) {
        if ($Bytes[$Index] -ne $Signature[$Index]) { throw 'PNG signature mismatch' }
    }
    $PngHash = (Get-FileHash -LiteralPath $Png -Algorithm SHA256).Hash

    $PostState = Get-State
    $PostRunning = Invoke-NativeCommand -FilePath $VBox -ArgumentList @('list','runningvms') -Label 'post-capture running inventory'
    Require-Success $PostRunning
    $PostRows = @($PostRunning.Rows | Where-Object { $_.Trim().Length -gt 0 })
    $PostRunningCount = $PostRows.Count
    if ($PostState -ne 'running') { throw "post-capture state mismatch: $PostState" }
    if ($PostRows.Count -ne 1 -or $PostRows[0].Trim() -cne $ExpectedRow) { throw "post-capture running inventory mismatch: $($PostRows -join ' | ')" }

    $Lines = @(
        'DBYTE-HOLYC-OPT',
        'TEMPLEOSTS 1.10 / FRESH ISO BOOT R1 / HEADLESS VISUAL CAPTURE',
        '',
        "prior_start_sha256`t$ExpectedStartHash",
        "runtime_report_sha256`t$ExpectedRuntimeHash",
        "poweroff_cause_sha256`t$ExpectedCauseHash",
        "start_mode`theadless",
        "start_exit`t$StartExit",
        "capture_exit`t$CaptureExit",
        "png_path`t$Png",
        "png_bytes`t$($Bytes.Length)",
        "png_sha256`t$PngHash",
        "post_capture_vm_state`t$PostState",
        "post_capture_running_rows`t$PostRunningCount",
        'CONTROLVM`tSCREENSHOTPNG-ONLY',
        'VM START`tHEADLESS-ONCE',
        'VM STOP/RESET`tNOT-EXECUTED',
        'STORAGE MUTATION`tNOT-EXECUTED',
        'SERVICE MUTATION`tNOT-EXECUTED',
        'COMPILER BUILD`tNOT-EXECUTED',
        'STATUS`tHEADLESS-START-AND-VISUAL-CAPTURE-PASS',
        '',
        'REPORTS ARE CLAIMS, NOT EVIDENCE.'
    )
    [System.IO.File]::WriteAllText($Report,(($Lines -join "`n") + "`n"),[System.Text.UTF8Encoding]::new($false))
    $ReportHash = (Get-FileHash -LiteralPath $Report -Algorithm SHA256).Hash

    Write-Host "START EXIT: $StartExit"
    Write-Host "CAPTURE EXIT: $CaptureExit"
    Write-Host "PNG: $Png"
    Write-Host "PNG SHA256: $PngHash"
    Write-Host "PNG BYTES: $($Bytes.Length)"
    Write-Host "POST STATE: $PostState"
    Write-Host "RUNNING ROWS: $PostRunningCount"
    Write-Host "REPORT: $Report"
    Write-Host "REPORT SHA256: $ReportHash"
    Write-Host 'VERDICT: HEADLESS START + VISUAL CAPTURE PASS'
}
catch {
    if ($StartIssued -and -not (Test-Path -LiteralPath $Report)) {
        $Failure = @(
            'DBYTE-HOLYC-OPT',
            'TEMPLEOSTS 1.10 / FRESH ISO BOOT R1 / HEADLESS VISUAL CAPTURE FAILURE',
            '',
            "start_exit`t$StartExit",
            "capture_exit`t$CaptureExit",
            "post_state`t$PostState",
            "post_running_rows`t$PostRunningCount",
            "error`t$($_.Exception.Message)",
            'AUTOMATIC ROLLBACK`tNOT-EXECUTED',
            'COMPILER BUILD`tNOT-EXECUTED',
            'STATUS`tHEADLESS-START-ISSUED-CAPTURE-PATH-FAILED',
            '',
            'REPORTS ARE CLAIMS, NOT EVIDENCE.'
        )
        try { [System.IO.File]::WriteAllText($Report,(($Failure -join "`n") + "`n"),[System.Text.UTF8Encoding]::new($false)) } catch { }
    }
    throw
}
finally {
    [Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$OriginalVBoxHome,[EnvironmentVariableTarget]::Process)
}
