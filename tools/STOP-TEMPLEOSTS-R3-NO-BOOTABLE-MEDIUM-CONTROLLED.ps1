[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$VBoxManagePath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$PreparedRoot,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$SecondAttemptReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedVBoxManage = 'D:\Portable-VirtualBox7\app64\VBoxManage.exe'
$ExpectedRoot = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r3'
$ExpectedSecondAttemptReport = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r3-second-controlled-boot-attempt.txt'
$ExpectedSecondAttemptHash = 'E6780E727989B974727402F782CA16B1B870FBF05591FACA6D131F6244F71430'
$ExpectedOut = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r3-controlled-stop-after-no-boot.txt'
$ExpectedVBoxVersion = '7.0.12r159484'
$ExpectedMachineName = 'Temple1.10'
$ExpectedMachineUuid = '9c98691e-27cd-4487-a306-587969c2c78c'
$ExpectedDriverPath = 'D:\Portable-VirtualBox7\app64\drivers\vboxsup\VBoxSup.sys'
$ExpectedDriverHash = '3344E2909580A9965E38B26AB9E9958842315DDEA1B0D0E274DA314DDCAB97F4'
$ServiceName = 'VBoxSup'
$ScPath = Join-Path $env:SystemRoot 'System32\sc.exe'
$FsutilPath = Join-Path $env:SystemRoot 'System32\fsutil.exe'

function Get-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath(
        [Environment]::ExpandEnvironmentVariables($Path)
    ).TrimEnd([char]92, [char]47)
}

function Assert-PathEquals {
    param(
        [Parameter(Mandatory = $true)][string]$Observed,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not [string]::Equals(
        (Get-FullPath -Path $Observed),
        (Get-FullPath -Path $Expected),
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "${Label} mismatch: observed=$Observed expected=$Expected"
    }
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $OldEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $Rows = @(
            & $FilePath @Arguments 2>&1 |
                ForEach-Object { [string]$_ }
        )
        $ExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $OldEap
    }
    return [pscustomobject]@{
        Label = $Label
        ExitCode = [int]$ExitCode
        Output = [string[]]$Rows
    }
}

function Require-NativeSuccess {
    param([Parameter(Mandatory = $true)][object]$Result)
    if ($Result.ExitCode -ne 0) {
        throw (
            "$($Result.Label) failed exit=$($Result.ExitCode) output=" +
            ($Result.Output -join ' | ')
        )
    }
}

function Get-HashOrMissing {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '<missing>' }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-FileIdOrMissing {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '<missing>' }
    $Result = Invoke-Native -FilePath $FsutilPath -Arguments @('file', 'queryfileid', $Path) -Label "fsutil queryfileid $Path"
    if ($Result.ExitCode -ne 0) { return "<query-failed:$($Result.ExitCode)>" }
    $Match = [regex]::Match(($Result.Output -join "`n"), '(?i)0x[0-9a-f]+')
    if (-not $Match.Success) { return '<parse-missing>' }
    return $Match.Value.ToUpperInvariant()
}

function Require-VBoxSupRunning {
    param([Parameter(Mandatory = $true)][string]$Label)
    $Result = Invoke-Native -FilePath $ScPath -Arguments @('query', $ServiceName) -Label $Label
    Require-NativeSuccess -Result $Result
    if (($Result.Output -join "`n") -notmatch '(?im)^\s*STATE\s*:\s*4\b') {
        throw "VBoxSup numeric STATE 4 not observed: $Label"
    }
}

function Convert-MachineReadable {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Rows)
    $Map = @{}
    $Slash = [string][char]92
    $DoubleSlash = $Slash + $Slash
    $EscapedQuote = $Slash + [string][char]34
    foreach ($Row in $Rows) {
        if ($Row -notmatch '^([^=]+)=(.*)$') { continue }
        $Key = [string]$Matches[1]
        $Value = [string]$Matches[2]
        if ($Key.Length -ge 2 -and $Key[0] -eq [char]34 -and $Key[$Key.Length - 1] -eq [char]34) {
            $Key = $Key.Substring(1, $Key.Length - 2)
            $Key = $Key.Replace($EscapedQuote, [string][char]34).Replace($DoubleSlash, $Slash)
        }
        if ($Value.Length -ge 2 -and $Value[0] -eq [char]34 -and $Value[$Value.Length - 1] -eq [char]34) {
            $Value = $Value.Substring(1, $Value.Length - 2)
            $Value = $Value.Replace($EscapedQuote, [string][char]34).Replace($DoubleSlash, $Slash)
        }
        if ([string]::IsNullOrWhiteSpace($Key)) { throw 'machine-readable key normalized empty' }
        if ($Map.ContainsKey($Key)) { throw "duplicate machine-readable key: $Key" }
        $Map[$Key] = $Value
    }
    return $Map
}

function Get-RequiredValue {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Map,
        [Parameter(Mandatory = $true)][string]$Key
    )
    if (-not $Map.ContainsKey($Key)) { throw "machine-readable key missing: $Key" }
    return [string]$Map[$Key]
}

function Get-ShowInfo {
    param([Parameter(Mandatory = $true)][string]$VBox)
    $Result = Invoke-Native -FilePath $VBox -Arguments @('showvminfo', $ExpectedMachineUuid, '--machinereadable') -Label 'VBoxManage showvminfo'
    Require-NativeSuccess -Result $Result
    return Convert-MachineReadable -Rows $Result.Output
}

function Write-Report {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$PoweroffArguments,
        [Parameter(Mandatory = $true)][int]$PoweroffExitCode,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowEmptyString()][string[]]$PoweroffOutput,
        [AllowEmptyString()][string]$ErrorText = ''
    )
    if (Test-Path -LiteralPath $Path) { throw "stop report already exists: $Path" }

    $MachineDir = Join-Path $script:R3Root 'Machine'
    $Home = Join-Path $script:R3Root 'VBoxUserHome'
    $CurrentVBox = Join-Path $MachineDir 'Temple1.10.vbox'
    $PreviousVBox = Join-Path $MachineDir 'Temple1.10.vbox-prev'
    $Vdi = Join-Path $MachineDir 'Temple1.10.vdi'
    $Iso = Join-Path $MachineDir 'TempleOSTS.iso'
    $Registry = Join-Path $Home 'VirtualBox.xml'

    $Lines = [System.Collections.Generic.List[string]]::new()
    $Lines.Add('DBYTE-HOLYC-OPT')
    $Lines.Add('TEMPLEOSTS 1.10 / R3 CONTROLLED STOP AFTER NO-BOOTABLE-MEDIUM')
    $Lines.Add('')
    $Lines.Add("second_attempt_report_sha256`t$ExpectedSecondAttemptHash")
    $Lines.Add("machine_uuid`t$ExpectedMachineUuid")
    $Lines.Add("poweroff_arguments`t$PoweroffArguments")
    $Lines.Add("poweroff_exit_code`t$PoweroffExitCode")
    foreach ($Row in $PoweroffOutput) { $Lines.Add("poweroff_output`t$Row") }
    $Lines.Add("post_stop_current_vbox_sha256`t$(Get-HashOrMissing -Path $CurrentVBox)")
    $Lines.Add("post_stop_current_vbox_file_id`t$(Get-FileIdOrMissing -Path $CurrentVBox)")
    $Lines.Add("post_stop_previous_vbox_sha256`t$(Get-HashOrMissing -Path $PreviousVBox)")
    $Lines.Add("post_stop_previous_vbox_file_id`t$(Get-FileIdOrMissing -Path $PreviousVBox)")
    $Lines.Add("post_stop_vdi_sha256`t$(Get-HashOrMissing -Path $Vdi)")
    $Lines.Add("post_stop_vdi_file_id`t$(Get-FileIdOrMissing -Path $Vdi)")
    $Lines.Add("post_stop_iso_sha256`t$(Get-HashOrMissing -Path $Iso)")
    $Lines.Add("post_stop_iso_file_id`t$(Get-FileIdOrMissing -Path $Iso)")
    $Lines.Add("post_stop_registry_sha256`t$(Get-HashOrMissing -Path $Registry)")
    $Lines.Add("post_stop_vboxsup_sys_sha256`t$(Get-HashOrMissing -Path $ExpectedDriverPath)")
    if (-not [string]::IsNullOrWhiteSpace($ErrorText)) { $Lines.Add("error`t$ErrorText") }
    $Lines.Add('')
    $Lines.Add("CONTROLVM`tPOWEROFF-ONCE")
    $Lines.Add("AUTOMATIC RETRY`tNOT-EXECUTED")
    $Lines.Add("ISO ATTACH`tNOT-EXECUTED")
    $Lines.Add("STORAGE MUTATION`tNOT-EXECUTED")
    $Lines.Add("SERVICE MUTATION`tNOT-EXECUTED")
    $Lines.Add("COMPILER BUILD`tNOT-EXECUTED")
    $Lines.Add("STATUS`t$Status")
    $Lines.Add('')
    $Lines.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')

    [System.IO.File]::WriteAllText(
        $Path,
        (($Lines.ToArray() -join "`n") + "`n"),
        [System.Text.UTF8Encoding]::new($false)
    )
}

foreach ($Required in @($VBoxManagePath, $ScPath, $FsutilPath, $ExpectedDriverPath)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) { throw "required file missing: $Required" }
}

$VBox = (Resolve-Path -LiteralPath $VBoxManagePath -ErrorAction Stop).Path
$script:R3Root = (Resolve-Path -LiteralPath $PreparedRoot -ErrorAction Stop).Path
$SecondAttempt = (Resolve-Path -LiteralPath $SecondAttemptReportPath -ErrorAction Stop).Path
$Output = Get-FullPath -Path $OutPath

Assert-PathEquals -Observed $VBox -Expected $ExpectedVBoxManage -Label 'VBoxManage path'
Assert-PathEquals -Observed $script:R3Root -Expected $ExpectedRoot -Label 'R3 root'
Assert-PathEquals -Observed $SecondAttempt -Expected $ExpectedSecondAttemptReport -Label 'second attempt report'
Assert-PathEquals -Observed $Output -Expected $ExpectedOut -Label 'controlled stop report'
if (Test-Path -LiteralPath $Output) { throw "controlled stop report already exists: $Output" }
if (-not (Test-Path -LiteralPath (Split-Path -Parent $Output) -PathType Container)) { throw 'controlled stop report parent missing' }

$SecondHash = (Get-FileHash -LiteralPath $SecondAttempt -Algorithm SHA256).Hash
if ($SecondHash -cne $ExpectedSecondAttemptHash) { throw "second attempt report hash mismatch: $SecondHash" }
$DriverHash = (Get-FileHash -LiteralPath $ExpectedDriverPath -Algorithm SHA256).Hash
if ($DriverHash -cne $ExpectedDriverHash) { throw "VBoxSup.sys hash mismatch: $DriverHash" }
Require-VBoxSupRunning -Label 'sc query VBoxSup before stop'

$OriginalHome = [Environment]::GetEnvironmentVariable('VBOX_USER_HOME', [EnvironmentVariableTarget]::Process)
if (-not [string]::IsNullOrEmpty($OriginalHome)) { throw "process VBOX_USER_HOME must be unset: $OriginalHome" }
$Home = Join-Path $script:R3Root 'VBoxUserHome'

$PoweroffIssued = $false
$PoweroffArguments = 'NOT-ISSUED'
$PoweroffExitCode = -1
$PoweroffOutput = @()

[Environment]::SetEnvironmentVariable('VBOX_USER_HOME', $Home, [EnvironmentVariableTarget]::Process)
try {
    $Version = Invoke-Native -FilePath $VBox -Arguments @('--version') -Label 'VBoxManage --version'
    Require-NativeSuccess -Result $Version
    if ($Version.Output.Count -ne 1 -or $Version.Output[0].Trim() -cne $ExpectedVBoxVersion) { throw "VirtualBox version mismatch: $($Version.Output -join '|')" }

    $Running = Invoke-Native -FilePath $VBox -Arguments @('list', 'runningvms') -Label 'pre-stop running inventory'
    Require-NativeSuccess -Result $Running
    $RunningRows = @($Running.Output | Where-Object { $_.Trim().Length -gt 0 })
    $ExpectedRunningRow = '"' + $ExpectedMachineName + '" {' + $ExpectedMachineUuid + '}'
    if ($RunningRows.Count -ne 1 -or $RunningRows[0].Trim() -cne $ExpectedRunningRow) { throw "pre-stop running inventory mismatch: $($RunningRows -join ' | ')" }

    $Info = Get-ShowInfo -VBox $VBox
    if ((Get-RequiredValue -Map $Info -Key 'VMState') -ine 'running') { throw "pre-stop VMState is not running: $(Get-RequiredValue -Map $Info -Key 'VMState')" }

    Require-VBoxSupRunning -Label 'sc query VBoxSup at stop boundary'

    Write-Host 'STOP BOUNDARY:          R3 RUNNING / NO-BOOT EVIDENCE SEALED'
    Write-Host 'AUTHORIZED MUTATION:    controlvm TARGET poweroff / ONCE'
    Write-Host 'AUTOMATIC RETRY:        NONE'

    $PoweroffArgs = @('controlvm', $ExpectedMachineUuid, 'poweroff')
    $PoweroffArguments = $PoweroffArgs -join ' '
    $PoweroffIssued = $true
    $Poweroff = Invoke-Native -FilePath $VBox -Arguments $PoweroffArgs -Label 'controlled poweroff'
    $PoweroffExitCode = [int]$Poweroff.ExitCode
    $PoweroffOutput = @($Poweroff.Output)
    Require-NativeSuccess -Result $Poweroff

    $PostState = ''
    for ($Attempt = 0; $Attempt -lt 20; $Attempt++) {
        Start-Sleep -Milliseconds 250
        $PostInfo = Get-ShowInfo -VBox $VBox
        $PostState = Get-RequiredValue -Map $PostInfo -Key 'VMState'
        if ($PostState -ieq 'poweroff') { break }
    }
    if ($PostState -ine 'poweroff') { throw "post-stop VMState did not reach poweroff: $PostState" }

    $PostRunning = Invoke-Native -FilePath $VBox -Arguments @('list', 'runningvms') -Label 'post-stop running inventory'
    Require-NativeSuccess -Result $PostRunning
    $PostRunningRows = @($PostRunning.Output | Where-Object { $_.Trim().Length -gt 0 })
    if ($PostRunningRows.Count -ne 0) { throw "post-stop running inventory not zero: $($PostRunningRows -join ' | ')" }

    Require-VBoxSupRunning -Label 'sc query VBoxSup after stop'

    Write-Report -Path $Output -Status 'R3-POWERED-OFF-PRESERVED' -PoweroffArguments $PoweroffArguments -PoweroffExitCode $PoweroffExitCode -PoweroffOutput $PoweroffOutput
    $ReportHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

    Write-Host "POWEROFF COMMAND:       $PoweroffArguments"
    Write-Host "POWEROFF EXIT CODE:     $PoweroffExitCode"
    Write-Host 'POST-STOP VM STATE:     poweroff'
    Write-Host 'POST-STOP RUNNING VMS:  0'
    Write-Host 'POST-STOP VBOXSUP:      4 / RUNNING'
    Write-Host "REPORT:                 $Output"
    Write-Host "REPORT SHA256:          $ReportHash"
    Write-Host 'VERDICT:                R3 POWERED OFF / NO-BOOT EVIDENCE PRESERVED'
}
catch {
    $ErrorText = $_.Exception.Message
    if ($PoweroffIssued -and -not (Test-Path -LiteralPath $Output)) {
        try {
            Write-Report -Path $Output -Status 'POWEROFF-ISSUED-POST-OBSERVATION-FAILED' -PoweroffArguments $PoweroffArguments -PoweroffExitCode $PoweroffExitCode -PoweroffOutput $PoweroffOutput -ErrorText $ErrorText
            $FailureHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash
            Write-Host "STOP FAILURE REPORT:    $Output"
            Write-Host "FAILURE REPORT SHA256:  $FailureHash"
        }
        catch { }
    }
    throw
}
finally {
    [Environment]::SetEnvironmentVariable('VBOX_USER_HOME', $OriginalHome, [EnvironmentVariableTarget]::Process)
}
