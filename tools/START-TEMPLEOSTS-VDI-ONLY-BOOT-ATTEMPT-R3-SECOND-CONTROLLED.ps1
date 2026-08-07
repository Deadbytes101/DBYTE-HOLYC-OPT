[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$VBoxManagePath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$PreparedRoot,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HostReadyReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$FirstAttemptReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedVBoxManage = 'D:\Portable-VirtualBox7\app64\VBoxManage.exe'
$ExpectedRoot = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r3'
$ExpectedHostReadyReport = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-portable-vbox-vboxsup-host-ready-r3-verification.txt'
$ExpectedHostReadyHash = '2F674C33658CE25661DA07C7EBC4336858D5A442F58ADCA7B8C3E6FC7F97BC9C'
$ExpectedFirstAttemptReport = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r3-single-controlled-boot-attempt.txt'
$ExpectedFirstAttemptHash = 'AC22D9A63234B8BC16FFFAE21BDAAE78704BDE6635A4072093EECCD070EE80D4'
$ExpectedOut = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r3-second-controlled-boot-attempt.txt'

$ExpectedVBoxVersion = '7.0.12r159484'
$ExpectedMachineName = 'Temple1.10'
$ExpectedMachineUuid = '9c98691e-27cd-4487-a306-587969c2c78c'
$ExpectedVdiUuid = '55c1f29d-a681-402e-b90d-bfbb6b09f207'

$ExpectedCurrentVBoxHash = '8EADB39D54CABE5E7B791E5D7E05BCF4CBBF32D4AB6B58291BEC0B2FAD607C0C'
$ExpectedPreviousVBoxHash = 'C93D128227EE80B647DB63FE64277CEF1BDC61C224110472C73CBFFEC63877A7'
$ExpectedVdiHash = '90D453A94F075760A11E0772862E60C4B031ED874F28AA396EAE638F7EB8B31B'
$ExpectedIsoHash = 'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$ExpectedCurrentVBoxId = '0X000000000000000000050000000609A1'
$ExpectedPreviousVBoxId = '0X000000000000000000040000000609A7'
$ExpectedVdiId = '0X000000000000000000010000000609A2'
$ExpectedIsoId = '0X000000000000000000010000000609A3'
$ExpectedRegistryHash = '99DB185525D245B1AAFF6937B459518089435882373A55CD2159D03FC82FDCBF'

$ExpectedDriverPath = 'D:\Portable-VirtualBox7\app64\drivers\vboxsup\VBoxSup.sys'
$ExpectedDriverHash = '3344E2909580A9965E38B26AB9E9958842315DDEA1B0D0E274DA314DDCAB97F4'
$ExpectedDriverVersion = '7.0.12.159484'
$ServiceName = 'VBoxSup'
$ExpectedDisplayName = 'PortableVBoxSUP'
$ServiceRegistryPath = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\VBoxSup'
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

function Assert-Hash {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "${Label} missing: $Path"
    }
    $Observed = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($Observed -cne $Expected) {
        throw "${Label} SHA256 mismatch: observed=$Observed expected=$Expected"
    }
    return $Observed
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

function Get-FileId {
    param([Parameter(Mandatory = $true)][string]$Path)
    $Result = Invoke-Native -FilePath $FsutilPath -Arguments @('file', 'queryfileid', $Path) -Label "fsutil queryfileid $Path"
    Require-NativeSuccess -Result $Result
    $Match = [regex]::Match(($Result.Output -join "`n"), '(?i)0x[0-9a-f]+')
    if (-not $Match.Success) {
        throw "file ID missing: $Path"
    }
    return $Match.Value.ToUpperInvariant()
}

function Assert-FileState {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Hash,
        [Parameter(Mandatory = $true)][string]$FileId,
        [Parameter(Mandatory = $true)][string]$Label
    )
    [void](Assert-Hash -Path $Path -Expected $Hash -Label $Label)
    $ObservedId = Get-FileId -Path $Path
    if ($ObservedId -cne $FileId) {
        throw "${Label} file ID mismatch: observed=$ObservedId expected=$FileId"
    }
}

function Normalize-DriverImagePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $Value = $Path.Trim().Trim([char]34)
    if ($Value.StartsWith('\??\', [System.StringComparison]::Ordinal)) {
        $Value = $Value.Substring(4)
    }
    return Get-FullPath -Path $Value
}

function Require-VBoxSupRunning {
    param([Parameter(Mandatory = $true)][string]$Label)
    $Result = Invoke-Native -FilePath $ScPath -Arguments @('query', $ServiceName) -Label $Label
    Require-NativeSuccess -Result $Result
    if (($Result.Output -join "`n") -notmatch '(?im)^\s*STATE\s*:\s*4\b') {
        throw "VBoxSup numeric STATE 4 not observed: $Label"
    }
    return $Result
}

function Convert-MachineReadable {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Rows)
    $Map = @{}
    $Slash = [string][char]92
    $DoubleSlash = $Slash + $Slash
    $EscapedQuote = $Slash + [string][char]34
    foreach ($Row in $Rows) {
        if ($Row -notmatch '^([^=]+)=(.*)$') {
            continue
        }
        $Key = [string]$Matches[1]
        $Value = [string]$Matches[2]
        if (
            $Key.Length -ge 2 -and
            $Key[0] -eq [char]34 -and
            $Key[$Key.Length - 1] -eq [char]34
        ) {
            $Key = $Key.Substring(1, $Key.Length - 2)
            $Key = $Key.Replace($EscapedQuote, [string][char]34)
            $Key = $Key.Replace($DoubleSlash, $Slash)
        }
        if (
            $Value.Length -ge 2 -and
            $Value[0] -eq [char]34 -and
            $Value[$Value.Length - 1] -eq [char]34
        ) {
            $Value = $Value.Substring(1, $Value.Length - 2)
            $Value = $Value.Replace($EscapedQuote, [string][char]34)
            $Value = $Value.Replace($DoubleSlash, $Slash)
        }
        if ([string]::IsNullOrWhiteSpace($Key)) {
            throw 'machine-readable key normalized empty'
        }
        if ($Map.ContainsKey($Key)) {
            throw "duplicate machine-readable key: $Key"
        }
        $Map[$Key] = $Value
    }
    return $Map
}

function Require-MapValue {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Map,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not $Map.ContainsKey($Key)) {
        throw "${Label} missing key: $Key"
    }
    $Observed = [string]$Map[$Key]
    if (-not [string]::Equals($Observed, $Expected, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "${Label} mismatch: $Key=$Observed expected=$Expected"
    }
}

function Get-SnapshotRows {
    param([Parameter(Mandatory = $true)][string]$VBox, [Parameter(Mandatory = $true)][string]$Uuid)
    $Result = Invoke-Native -FilePath $VBox -Arguments @('snapshot', $Uuid, 'list', '--machinereadable') -Label 'VBoxManage snapshot list'
    if ($Result.ExitCode -eq 0) {
        return [string[]]@($Result.Output | Where-Object { $_.Trim().Length -gt 0 })
    }
    if (($Result.Output -join "`n") -match '(?i)does not have any snapshots') {
        return [string[]]@()
    }
    throw "snapshot list failed exit=$($Result.ExitCode) output=$($Result.Output -join ' | ')"
}

function Get-HardeningEvidence {
    param([Parameter(Mandatory = $true)][string]$MachineDir)
    $Path = Join-Path (Join-Path $MachineDir 'Logs') 'VBoxHardening.log'
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ Path = $Path; Hash = ''; Tail = @() }
    }
    $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    $Tail = @(Get-Content -LiteralPath $Path -Tail 80 -ErrorAction Stop)
    return [pscustomobject]@{ Path = $Path; Hash = $Hash; Tail = [string[]]$Tail }
}

function Write-AttemptReport {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$StartArguments,
        [Parameter(Mandatory = $true)][int]$StartExitCode,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowEmptyString()][string[]]$StartOutput,
        [AllowEmptyString()][string]$PostState = '',
        [AllowEmptyString()][string]$PostRunningCount = '',
        [AllowEmptyString()][string]$PostServiceState = '',
        [AllowEmptyString()][string]$ErrorText = ''
    )
    if (Test-Path -LiteralPath $Path) {
        throw "second boot-attempt report already exists: $Path"
    }
    $Hardening = Get-HardeningEvidence -MachineDir $script:MachineDir
    $Lines = [System.Collections.Generic.List[string]]::new()
    $Lines.Add('DBYTE-HOLYC-OPT')
    $Lines.Add('TEMPLEOSTS 1.10 VDI-ONLY R3 SECOND SINGLE CONTROLLED BOOT ATTEMPT')
    $Lines.Add('')
    $Lines.Add("prepared_root`t$script:R3Root")
    $Lines.Add("host_ready_report_sha256`t$ExpectedHostReadyHash")
    $Lines.Add("first_attempt_report_sha256`t$ExpectedFirstAttemptHash")
    $Lines.Add("vboxsup_sys_sha256`t$ExpectedDriverHash")
    $Lines.Add("machine_uuid`t$ExpectedMachineUuid")
    $Lines.Add("pre_start_current_vbox_sha256`t$ExpectedCurrentVBoxHash")
    $Lines.Add("pre_start_previous_vbox_sha256`t$ExpectedPreviousVBoxHash")
    $Lines.Add("pre_start_vdi_sha256`t$ExpectedVdiHash")
    $Lines.Add("pre_start_iso_sha256`t$ExpectedIsoHash")
    $Lines.Add("pre_start_registry_sha256`t$ExpectedRegistryHash")
    $Lines.Add('')
    $Lines.Add("start_arguments`t$StartArguments")
    $Lines.Add("start_exit_code`t$StartExitCode")
    foreach ($Row in $StartOutput) {
        $Lines.Add("start_output`t$Row")
    }
    $Lines.Add("post_start_vm_state`t$PostState")
    $Lines.Add("post_start_running_vm_rows`t$PostRunningCount")
    $Lines.Add("post_start_vboxsup_state`t$PostServiceState")
    if (-not [string]::IsNullOrWhiteSpace($ErrorText)) {
        $Lines.Add("error`t$ErrorText")
    }
    $Lines.Add("hardening_log_path`t$($Hardening.Path)")
    $Lines.Add("hardening_log_sha256`t$($Hardening.Hash)")
    foreach ($Row in $Hardening.Tail) {
        $Lines.Add("hardening_tail`t$Row")
    }
    $Lines.Add('')
    $Lines.Add("VBOXMANAGE`tSTARTVM-ONCE-PLUS-READ-ONLY-OBSERVATION")
    $Lines.Add("EXPLICIT CONFIGURATION COMMAND`tNOT-EXECUTED")
    $Lines.Add("EXPLICIT STORAGEATTACH COMMAND`tNOT-EXECUTED")
    $Lines.Add("SNAPSHOT MUTATION`tNOT-EXECUTED")
    $Lines.Add("CONTROLVM`tNOT-EXECUTED")
    $Lines.Add("GUESTCONTROL`tNOT-EXECUTED")
    $Lines.Add("SERVICE MUTATION`tNOT-EXECUTED")
    $Lines.Add("GUEST DISK WRITES AFTER START`tPOSSIBLE / NOT BLOCKED / NOT ADJUDICATED HERE")
    $Lines.Add("COMPILER BUILD`tNOT-EXECUTED")
    $Lines.Add("GUEST VISUAL BOOT`tNOT-OBSERVED-BY-HOST-SCRIPT")
    $Lines.Add("BOOT ATTEMPT STATUS`t$Status")
    $Lines.Add('')
    $Lines.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')
    [System.IO.File]::WriteAllText(
        $Path,
        (($Lines.ToArray() -join "`n") + "`n"),
        [System.Text.UTF8Encoding]::new($false)
    )
}

foreach ($Exe in @($VBoxManagePath, $ScPath, $FsutilPath)) {
    if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) {
        throw "required executable missing: $Exe"
    }
}

$VBox = (Resolve-Path -LiteralPath $VBoxManagePath -ErrorAction Stop).Path
$script:R3Root = (Resolve-Path -LiteralPath $PreparedRoot -ErrorAction Stop).Path
$HostReady = (Resolve-Path -LiteralPath $HostReadyReportPath -ErrorAction Stop).Path
$FirstAttempt = (Resolve-Path -LiteralPath $FirstAttemptReportPath -ErrorAction Stop).Path
$Output = Get-FullPath -Path $OutPath

Assert-PathEquals -Observed $VBox -Expected $ExpectedVBoxManage -Label 'VBoxManage path'
Assert-PathEquals -Observed $script:R3Root -Expected $ExpectedRoot -Label 'R3 root'
Assert-PathEquals -Observed $HostReady -Expected $ExpectedHostReadyReport -Label 'host-ready report'
Assert-PathEquals -Observed $FirstAttempt -Expected $ExpectedFirstAttemptReport -Label 'first-attempt report'
Assert-PathEquals -Observed $Output -Expected $ExpectedOut -Label 'second-attempt report'
if (Test-Path -LiteralPath $Output) {
    throw "second boot-attempt report already exists: $Output"
}
$OutputParent = Split-Path -Parent $Output
if (-not (Test-Path -LiteralPath $OutputParent -PathType Container)) {
    throw "second-attempt report parent missing: $OutputParent"
}

[void](Assert-Hash -Path $HostReady -Expected $ExpectedHostReadyHash -Label 'host-ready report')
[void](Assert-Hash -Path $FirstAttempt -Expected $ExpectedFirstAttemptHash -Label 'first-attempt report')

$DriverPath = (Resolve-Path -LiteralPath $ExpectedDriverPath -ErrorAction Stop).Path
[void](Assert-Hash -Path $DriverPath -Expected $ExpectedDriverHash -Label 'VBoxSup.sys')
$DriverItem = Get-Item -LiteralPath $DriverPath -Force -ErrorAction Stop
if ($DriverItem.VersionInfo.FileVersion -cne $ExpectedDriverVersion) {
    throw "VBoxSup.sys version mismatch: $($DriverItem.VersionInfo.FileVersion)"
}
$Signature = Get-AuthenticodeSignature -LiteralPath $DriverPath
if ($Signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
    throw "VBoxSup.sys signature not Valid: $($Signature.Status)"
}

if (-not (Test-Path -LiteralPath $ServiceRegistryPath)) {
    throw 'VBoxSup service registry key missing'
}
$Service = Get-ItemProperty -LiteralPath $ServiceRegistryPath -ErrorAction Stop
$ServiceImage = Normalize-DriverImagePath -Path ([string]$Service.ImagePath)
Assert-PathEquals -Observed $ServiceImage -Expected $DriverPath -Label 'VBoxSup ImagePath'
if ([int]$Service.Type -ne 1) { throw "VBoxSup Type mismatch: $($Service.Type)" }
if ([int]$Service.Start -ne 2) { throw "VBoxSup Start mismatch: $($Service.Start)" }
if ([int]$Service.ErrorControl -ne 1) { throw "VBoxSup ErrorControl mismatch: $($Service.ErrorControl)" }
if ([string]$Service.DisplayName -cne $ExpectedDisplayName) { throw "VBoxSup DisplayName mismatch: $($Service.DisplayName)" }
[void](Require-VBoxSupRunning -Label 'sc query VBoxSup initial')

$script:MachineDir = Join-Path $script:R3Root 'Machine'
$VBoxUserHome = Join-Path $script:R3Root 'VBoxUserHome'
$CurrentVBox = Join-Path $script:MachineDir 'Temple1.10.vbox'
$PreviousVBox = Join-Path $script:MachineDir 'Temple1.10.vbox-prev'
$Vdi = Join-Path $script:MachineDir 'Temple1.10.vdi'
$Iso = Join-Path $script:MachineDir 'TempleOSTS.iso'
$Registry = Join-Path $VBoxUserHome 'VirtualBox.xml'

Assert-FileState -Path $CurrentVBox -Hash $ExpectedCurrentVBoxHash -FileId $ExpectedCurrentVBoxId -Label 'R3 current VBOX initial'
Assert-FileState -Path $PreviousVBox -Hash $ExpectedPreviousVBoxHash -FileId $ExpectedPreviousVBoxId -Label 'R3 previous VBOX initial'
Assert-FileState -Path $Vdi -Hash $ExpectedVdiHash -FileId $ExpectedVdiId -Label 'R3 VDI initial'
Assert-FileState -Path $Iso -Hash $ExpectedIsoHash -FileId $ExpectedIsoId -Label 'R3 ISO initial'
[void](Assert-Hash -Path $Registry -Expected $ExpectedRegistryHash -Label 'R3 isolated registry initial')

$OriginalVBoxUserHome = [Environment]::GetEnvironmentVariable('VBOX_USER_HOME', [EnvironmentVariableTarget]::Process)
if (-not [string]::IsNullOrEmpty($OriginalVBoxUserHome)) {
    throw "process VBOX_USER_HOME must be unset: $OriginalVBoxUserHome"
}
$ForbiddenProcesses = @(
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -match '^(?i)(VBoxSVC|VirtualBoxVM|VBoxHeadless|VirtualBox)$' }
)
if ($ForbiddenProcesses.Count -ne 0) {
    throw 'VirtualBox runtime process already present: ' + (($ForbiddenProcesses | ForEach-Object { "$($_.ProcessName):$($_.Id)" }) -join ', ')
}

$StartIssued = $false
$StartArguments = 'NOT-ISSUED'
$StartExitCode = -1
$StartOutput = @()
$PostState = ''
$PostRunningCount = ''
$PostServiceState = ''

[Environment]::SetEnvironmentVariable('VBOX_USER_HOME', $VBoxUserHome, [EnvironmentVariableTarget]::Process)
try {
    $Version = Invoke-Native -FilePath $VBox -Arguments @('--version') -Label 'pre-start VBoxManage --version'
    Require-NativeSuccess -Result $Version
    if ($Version.Output.Count -ne 1 -or $Version.Output[0].Trim() -cne $ExpectedVBoxVersion) {
        throw "VirtualBox version mismatch: $($Version.Output -join ' | ')"
    }

    $Registered = Invoke-Native -FilePath $VBox -Arguments @('list', 'vms') -Label 'pre-start VBoxManage list vms'
    Require-NativeSuccess -Result $Registered
    $RegisteredRows = @($Registered.Output | Where-Object { $_.Trim().Length -gt 0 })
    $TargetRow = '^"Temple1\.10"\s+\{9c98691e-27cd-4487-a306-587969c2c78c\}$'
    if ($RegisteredRows.Count -ne 1 -or $RegisteredRows[0] -notmatch $TargetRow) {
        throw "registered VM inventory mismatch: $($RegisteredRows -join ' | ')"
    }

    $Running = Invoke-Native -FilePath $VBox -Arguments @('list', 'runningvms') -Label 'pre-start VBoxManage list runningvms'
    Require-NativeSuccess -Result $Running
    $RunningRows = @($Running.Output | Where-Object { $_.Trim().Length -gt 0 })
    if ($RunningRows.Count -ne 0) {
        throw "running VM inventory not empty: $($RunningRows -join ' | ')"
    }

    $InfoResult = Invoke-Native -FilePath $VBox -Arguments @('showvminfo', $ExpectedMachineUuid, '--machinereadable') -Label 'pre-start VBoxManage showvminfo'
    Require-NativeSuccess -Result $InfoResult
    $Info = Convert-MachineReadable -Rows $InfoResult.Output
    Require-MapValue -Map $Info -Key 'name' -Expected $ExpectedMachineName -Label 'pre-start VM'
    Require-MapValue -Map $Info -Key 'UUID' -Expected $ExpectedMachineUuid -Label 'pre-start VM'
    Require-MapValue -Map $Info -Key 'VMState' -Expected 'poweroff' -Label 'pre-start VM'
    Require-MapValue -Map $Info -Key 'CfgFile' -Expected $CurrentVBox -Label 'pre-start VM'
    Require-MapValue -Map $Info -Key 'IDE-1-0' -Expected $Vdi -Label 'pre-start VM'
    Require-MapValue -Map $Info -Key 'IDE-ImageUUID-1-0' -Expected $ExpectedVdiUuid -Label 'pre-start VM'
    Require-MapValue -Map $Info -Key 'boot1' -Expected 'disk' -Label 'pre-start VM'
    Require-MapValue -Map $Info -Key 'boot2' -Expected 'none' -Label 'pre-start VM'
    Require-MapValue -Map $Info -Key 'boot3' -Expected 'none' -Label 'pre-start VM'
    Require-MapValue -Map $Info -Key 'boot4' -Expected 'none' -Label 'pre-start VM'
    Require-MapValue -Map $Info -Key 'clipboard' -Expected 'disabled' -Label 'pre-start VM'
    Require-MapValue -Map $Info -Key 'draganddrop' -Expected 'disabled' -Label 'pre-start VM'
    Require-MapValue -Map $Info -Key 'graphicscontroller' -Expected 'vboxvga' -Label 'pre-start VM'
    Require-MapValue -Map $Info -Key 'vram' -Expected '9' -Label 'pre-start VM'

    $NicKeys = @($Info.Keys | Where-Object { $_ -match '^nic\d+$' })
    if ($NicKeys.Count -eq 0) { throw 'pre-start VM exposes no NIC keys' }
    foreach ($Key in $NicKeys) {
        Require-MapValue -Map $Info -Key $Key -Expected 'none' -Label 'pre-start VM'
    }
    $SharedKeys = @($Info.Keys | Where-Object { $_ -like 'SharedFolderNameMachineMapping*' -or $_ -like 'SharedFolderPathMachineMapping*' })
    if ($SharedKeys.Count -ne 0) { throw "shared-folder mapping key count mismatch: $($SharedKeys.Count)" }
    if ($Info.ContainsKey('IDE-0-1')) {
        Require-MapValue -Map $Info -Key 'IDE-0-1' -Expected 'none' -Label 'pre-start VM'
    }

    $Snapshots = @(Get-SnapshotRows -VBox $VBox -Uuid $ExpectedMachineUuid)
    if ($Snapshots.Count -ne 0) { throw "snapshot inventory not empty: $($Snapshots.Count)" }

    $Medium = Invoke-Native -FilePath $VBox -Arguments @('showmediuminfo', 'disk', $Vdi) -Label 'pre-start VBoxManage showmediuminfo disk'
    Require-NativeSuccess -Result $Medium
    if (($Medium.Output -join "`n") -notmatch '(?im)^UUID:\s*55c1f29d-a681-402e-b90d-bfbb6b09f207\s*$') {
        throw 'pre-start VDI UUID mismatch in showmediuminfo'
    }

    [void](Require-VBoxSupRunning -Label 'sc query VBoxSup at start boundary')
    [void](Assert-Hash -Path $DriverPath -Expected $ExpectedDriverHash -Label 'VBoxSup.sys at start boundary')
    Assert-FileState -Path $CurrentVBox -Hash $ExpectedCurrentVBoxHash -FileId $ExpectedCurrentVBoxId -Label 'R3 current VBOX at start boundary'
    Assert-FileState -Path $PreviousVBox -Hash $ExpectedPreviousVBoxHash -FileId $ExpectedPreviousVBoxId -Label 'R3 previous VBOX at start boundary'
    Assert-FileState -Path $Vdi -Hash $ExpectedVdiHash -FileId $ExpectedVdiId -Label 'R3 VDI at start boundary'
    Assert-FileState -Path $Iso -Hash $ExpectedIsoHash -FileId $ExpectedIsoId -Label 'R3 ISO at start boundary'
    [void](Assert-Hash -Path $Registry -Expected $ExpectedRegistryHash -Label 'R3 isolated registry at start boundary')

    Write-Host 'SECOND START BOUNDARY:  ALL PRE-START GATES PASSED'
    Write-Host 'VBOXSUP STATE:          4 / RUNNING'
    Write-Host 'AUTHORIZED MUTATION:    startvm TARGET --type gui / ONCE'
    Write-Host 'AUTOMATIC ROLLBACK:     NONE'

    $StartArgs = @('startvm', $ExpectedMachineUuid, '--type', 'gui')
    $StartArguments = $StartArgs -join ' '
    $Start = Invoke-Native -FilePath $VBox -Arguments $StartArgs -Label 'second controlled VBoxManage startvm'
    $StartIssued = $true
    $StartExitCode = [int]$Start.ExitCode
    $StartOutput = @($Start.Output)
    if ($StartExitCode -ne 0) {
        throw "second startvm failed exit=$StartExitCode output=$($StartOutput -join ' | ')"
    }

    $PostInfoResult = Invoke-Native -FilePath $VBox -Arguments @('showvminfo', $ExpectedMachineUuid, '--machinereadable') -Label 'post-start VBoxManage showvminfo'
    Require-NativeSuccess -Result $PostInfoResult
    $PostInfo = Convert-MachineReadable -Rows $PostInfoResult.Output
    if (-not $PostInfo.ContainsKey('VMState')) { throw 'post-start VMState key missing' }
    $PostState = [string]$PostInfo['VMState']

    $PostRunning = Invoke-Native -FilePath $VBox -Arguments @('list', 'runningvms') -Label 'post-start VBoxManage list runningvms'
    Require-NativeSuccess -Result $PostRunning
    $PostRunningRows = @($PostRunning.Output | Where-Object { $_.Trim().Length -gt 0 })
    $PostRunningCount = [string]$PostRunningRows.Count

    $PostSc = Require-VBoxSupRunning -Label 'sc query VBoxSup after start'
    $PostServiceState = '4'

    if ($PostState -ine 'running') {
        throw "post-start VMState not running: $PostState"
    }
    if ($PostRunningRows.Count -ne 1 -or $PostRunningRows[0] -notmatch $TargetRow) {
        throw "post-start running VM inventory mismatch: $($PostRunningRows -join ' | ')"
    }

    Write-AttemptReport -Path $Output -Status 'SECOND-START-ACCEPTED-HOST-RUNNING' -StartArguments $StartArguments -StartExitCode $StartExitCode -StartOutput $StartOutput -PostState $PostState -PostRunningCount $PostRunningCount -PostServiceState $PostServiceState
    $ReportHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

    Write-Host "START COMMAND:          $StartArguments"
    Write-Host "START EXIT CODE:        $StartExitCode"
    Write-Host "POST-START VM STATE:    $PostState"
    Write-Host "POST-START RUNNING VMS: $PostRunningCount"
    Write-Host "POST-START VBOXSUP:     $PostServiceState"
    Write-Host "REPORT:                 $Output"
    Write-Host "REPORT SHA256:          $ReportHash"
    Write-Host 'GUEST VISUAL BOOT:      NOT-OBSERVED-BY-HOST-SCRIPT'
    Write-Host 'CONTROLVM:              NOT-EXECUTED'
    Write-Host 'COMPILER BUILD:         NOT-EXECUTED'
    Write-Host 'VERDICT:                SECOND START ACCEPTED / HOST RUNNING / VISUAL PROOF PENDING'
}
catch {
    $ErrorText = $_.Exception.Message
    if ($StartIssued -and -not (Test-Path -LiteralPath $Output)) {
        try {
            Write-AttemptReport -Path $Output -Status 'SECOND-START-ISSUED-FAILED-OR-POST-OBSERVATION-FAILED' -StartArguments $StartArguments -StartExitCode $StartExitCode -StartOutput $StartOutput -PostState $PostState -PostRunningCount $PostRunningCount -PostServiceState $PostServiceState -ErrorText $ErrorText
            $FailureHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash
            Write-Host "SECOND BOOT FAILURE REPORT: $Output"
            Write-Host "FAILURE REPORT SHA256:      $FailureHash"
            Write-Host 'AUTOMATIC ROLLBACK:         NOT-EXECUTED'
        }
        catch {
        }
    }
    throw
}
finally {
    [Environment]::SetEnvironmentVariable('VBOX_USER_HOME', $OriginalVBoxUserHome, [EnvironmentVariableTarget]::Process)
}
