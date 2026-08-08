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
$Machine = Join-Path $Root 'Machine'
$VBoxHome = Join-Path $Root 'VBoxUserHome'
$VboxFile = Join-Path $Machine 'Temple1.10.vbox'
$Vdi = Join-Path $Machine 'Temple1.10.vdi'
$Iso = Join-Path $Machine 'TempleOSTS.iso'
$Start = Join-Path $Root 'START.txt'
$Registry = Join-Path $VBoxHome 'VirtualBox.xml'
$VBoxLog = Join-Path (Join-Path $Machine 'Logs') 'VBox.log'
$HardeningLog = Join-Path (Join-Path $Machine 'Logs') 'VBoxHardening.log'
$Report = Join-Path $Root 'RUNTIME-STATE-R1.txt'
$Sc = Join-Path $env:SystemRoot 'System32\sc.exe'

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
    if ($Result.ExitCode -ne 0) {
        throw "$($Result.Label) failed exit=$($Result.ExitCode) output=$($Result.Rows -join ' | ')"
    }
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

function Get-TabValue {
    param([string[]]$Lines,[string]$Key)
    $Prefix = $Key + "`t"
    $Rows = @($Lines | Where-Object { $_.StartsWith($Prefix,[System.StringComparison]::Ordinal) })
    if ($Rows.Count -ne 1) { throw "report field count mismatch key=$Key count=$($Rows.Count)" }
    $Rows[0].Substring($Prefix.Length)
}

function Add-FileEvidence {
    param([System.Collections.Generic.List[string]]$Lines,[string]$Prefix,[string]$Path,[int]$TailCount)
    $Exists = Test-Path -LiteralPath $Path -PathType Leaf
    [void]$Lines.Add("${Prefix}_path`t$Path")
    [void]$Lines.Add("${Prefix}_present`t$Exists")
    if (-not $Exists) { return }
    $Item = Get-Item -LiteralPath $Path -Force
    $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    [void]$Lines.Add("${Prefix}_bytes`t$($Item.Length)")
    [void]$Lines.Add("${Prefix}_sha256`t$Hash")
    foreach ($Row in @(Get-Content -LiteralPath $Path -Tail $TailCount -ErrorAction Stop)) {
        [void]$Lines.Add("${Prefix}_tail`t$([string]$Row)")
    }
}

foreach ($Path in @($VBox,$Sc,$VboxFile,$Vdi,$Iso,$Start,$Registry)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "missing: $Path" }
}
if (Test-Path -LiteralPath $Report) { throw "runtime report exists: $Report" }
if ((Get-FileHash -LiteralPath $Start -Algorithm SHA256).Hash -cne $ExpectedStartHash) { throw 'START.txt hash mismatch' }

$StartLines = [System.IO.File]::ReadAllLines($Start)
if ((Get-TabValue $StartLines 'STATUS') -cne 'FRESH-ISO-START-ACCEPTED-HOST-RUNNING-VISUAL-PROOF-PENDING') {
    throw 'START.txt status mismatch'
}

$OriginalVBoxHome = [Environment]::GetEnvironmentVariable('VBOX_USER_HOME',[EnvironmentVariableTarget]::Process)
if (-not [string]::IsNullOrEmpty($OriginalVBoxHome)) { throw "VBOX_USER_HOME must be unset: $OriginalVBoxHome" }

$Service = Invoke-NativeCommand -FilePath $Sc -ArgumentList @('query','VBoxSup') -Label 'sc query VBoxSup'
$ServiceState = if ($Service.ExitCode -eq 0 -and ($Service.Rows -join "`n") -match '(?im)^\s*STATE\s*:\s*(\d+)\b') { [string]$Matches[1] } else { '<unresolved>' }

$ProcessRows = @(
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -match '(?i)^(VBoxSVC|VirtualBoxVM|VBoxHeadless|VirtualBox)$' } |
        Sort-Object ProcessName,Id |
        ForEach-Object { "$($_.ProcessName) | pid=$($_.Id)" }
)

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
    $RunningRows = @($Running.Rows | Where-Object { $_.Trim().Length -gt 0 })

    $InfoResult = Invoke-NativeCommand -FilePath $VBox -ArgumentList @('showvminfo',$Uuid,'--machinereadable') -Label 'showvminfo'
    Require-Success $InfoResult
    $Info = Convert-MachineReadable $InfoResult.Rows
    Require-MapValue $Info 'name' $Name
    Require-MapValue $Info 'UUID' $Uuid
    Require-MapValue $Info 'CfgFile' $VboxFile
    Require-MapValue $Info 'IDE-1-0' $Vdi
    Require-MapValue $Info 'IDE-0-1' $Iso
    $VmState = if ($Info.ContainsKey('VMState')) { [string]$Info['VMState'] } else { '<missing>' }
    $LastStateChange = if ($Info.ContainsKey('VMStateChangeTime')) { [string]$Info['VMStateChangeTime'] } else { '<missing>' }
}
finally {
    [Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$OriginalVBoxHome,[EnvironmentVariableTarget]::Process)
}

$Lines = [System.Collections.Generic.List[string]]::new()
[void]$Lines.Add('DBYTE-HOLYC-OPT')
[void]$Lines.Add('TEMPLEOSTS 1.10 / FRESH ISO BOOT R1 / RUNTIME STATE READ-ONLY')
[void]$Lines.Add('')
[void]$Lines.Add("start_report_sha256`t$ExpectedStartHash")
[void]$Lines.Add("machine_uuid`t$Uuid")
[void]$Lines.Add("vm_state`t$VmState")
[void]$Lines.Add("vm_state_change_time`t$LastStateChange")
[void]$Lines.Add("registered_vm_rows`t$($VmRows.Count)")
[void]$Lines.Add("running_vm_rows`t$($RunningRows.Count)")
foreach ($Row in $RunningRows) { [void]$Lines.Add("running_vm`t$Row") }
[void]$Lines.Add("vboxsup_query_exit`t$($Service.ExitCode)")
[void]$Lines.Add("vboxsup_state`t$ServiceState")
foreach ($Row in $Service.Rows) { [void]$Lines.Add("vboxsup_query`t$Row") }
[void]$Lines.Add("virtualbox_process_rows`t$($ProcessRows.Count)")
foreach ($Row in $ProcessRows) { [void]$Lines.Add("virtualbox_process`t$Row") }
Add-FileEvidence -Lines $Lines -Prefix 'vbox_log' -Path $VBoxLog -TailCount 120
Add-FileEvidence -Lines $Lines -Prefix 'hardening_log' -Path $HardeningLog -TailCount 80
[void]$Lines.Add('')
[void]$Lines.Add('VBOXMANAGE`tREAD-ONLY-ONLY')
[void]$Lines.Add('CONTROLVM`tNOT-EXECUTED')
[void]$Lines.Add('VM START/STOP/RESET`tNOT-EXECUTED')
[void]$Lines.Add('STORAGE MUTATION`tNOT-EXECUTED')
[void]$Lines.Add('SERVICE MUTATION`tNOT-EXECUTED')
[void]$Lines.Add('COMPILER BUILD`tNOT-EXECUTED')
[void]$Lines.Add('STATUS`tFRESH-ISO-RUNTIME-STATE-ADJUDICATED-READ-ONLY')
[void]$Lines.Add('')
[void]$Lines.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')

[System.IO.File]::WriteAllText($Report,(($Lines.ToArray() -join "`n") + "`n"),[System.Text.UTF8Encoding]::new($false))
$ReportHash = (Get-FileHash -LiteralPath $Report -Algorithm SHA256).Hash

Write-Host "VM STATE: $VmState"
Write-Host "STATE CHANGE: $LastStateChange"
Write-Host "RUNNING ROWS: $($RunningRows.Count)"
Write-Host "VBOXSUP STATE: $ServiceState"
Write-Host "VBOX PROCESSES: $($ProcessRows.Count)"
Write-Host "VBOX.LOG: $(Test-Path -LiteralPath $VBoxLog -PathType Leaf)"
Write-Host "HARDENING LOG: $(Test-Path -LiteralPath $HardeningLog -PathType Leaf)"
Write-Host "REPORT: $Report"
Write-Host "REPORT SHA256: $ReportHash"
Write-Host 'VERDICT: RUNTIME STATE ADJUDICATED READ-ONLY'
