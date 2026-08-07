[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$VBoxManagePath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$PortableVirtualBoxRoot,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$PreparedRoot,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$MutationReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$FailedBootAttemptReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$PreparedVerificationReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$BootAuthorizationReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedVBoxManage = 'D:\Portable-VirtualBox7\app64\VBoxManage.exe'
$ExpectedPortableRoot = 'D:\Portable-VirtualBox7'
$ExpectedPreparedRoot = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r3'
$ExpectedMutationReport = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-portable-vbox-vboxsup-surgical-install-start.txt'
$ExpectedMutationHash = '3C24420D77868E8D15F58A6412AF53635EEAFFF00337CCEB01E17C31183666F3'
$ExpectedFailedBootReport = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r3-single-controlled-boot-attempt.txt'
$ExpectedFailedBootHash = 'AC22D9A63234B8BC16FFFAE21BDAAE78704BDE6635A4072093EECCD070EE80D4'
$ExpectedPreparedVerification = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r3-prepared-verification.txt'
$ExpectedPreparedVerificationHash = '26DC5258CF4692FD55EC95D81E48E3CFE05B4667BC20CDAC0CFFD58DC8433EF7'
$ExpectedBootAuthorization = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r3-boot-authorization-adjudication.txt'
$ExpectedBootAuthorizationHash = 'F8596A2CDECB75BE1FEC02377E9B6A428F15A3F4FC2C81D33F27A0CD962C3482'
$ExpectedOut = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-portable-vbox-vboxsup-host-ready-r3-verification.txt'

$ExpectedDriverHash = '3344E2909580A9965E38B26AB9E9958842315DDEA1B0D0E274DA314DDCAB97F4'
$ExpectedDriverVersion = '7.0.12.159484'
$ExpectedInfHash = 'B34D56477E8273C6C2B177B38A7F5CBE1DD4708A1C2BAF7A2D2170302ECAC7F6'
$ExpectedCatHash = '09DFDCD84B7CE8970B32AF5BB18000738155C04444C6276B5353C98CB1CA6999'

$ExpectedCurrentVBoxHash = '8EADB39D54CABE5E7B791E5D7E05BCF4CBBF32D4AB6B58291BEC0B2FAD607C0C'
$ExpectedPreviousVBoxHash = 'C93D128227EE80B647DB63FE64277CEF1BDC61C224110472C73CBFFEC63877A7'
$ExpectedVdiHash = '90D453A94F075760A11E0772862E60C4B031ED874F28AA396EAE638F7EB8B31B'
$ExpectedIsoHash = 'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$ExpectedCurrentVBoxFileId = '0X000000000000000000050000000609A1'
$ExpectedPreviousVBoxFileId = '0X000000000000000000040000000609A7'
$ExpectedVdiFileId = '0X000000000000000000010000000609A2'
$ExpectedIsoFileId = '0X000000000000000000010000000609A3'
$ExpectedRegistryHash = '99DB185525D245B1AAFF6937B459518089435882373A55CD2159D03FC82FDCBF'

$TargetName = 'Temple1.10'
$TargetUuid = '9c98691e-27cd-4487-a306-587969c2c78c'
$ExpectedVdiUuid = '55c1f29d-a681-402e-b90d-bfbb6b09f207'
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

function Invoke-NativeRead {
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
        $Exit = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $OldEap
    }
    return [pscustomobject]@{
        Label = $Label
        ExitCode = [int]$Exit
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
    $Result = Invoke-NativeRead -FilePath $FsutilPath -Arguments @('file', 'queryfileid', $Path) -Label "fsutil queryfileid $Path"
    Require-NativeSuccess -Result $Result
    $Text = $Result.Output -join "`n"
    $Match = [regex]::Match($Text, '(?i)0x[0-9a-f]+')
    if (-not $Match.Success) {
        throw "file ID missing from fsutil output: $Path"
    }
    return $Match.Value.ToUpperInvariant()
}

function Normalize-DriverImagePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $Value = $Path.Trim().Trim([char]34)
    if ($Value.StartsWith('\??\', [System.StringComparison]::Ordinal)) {
        $Value = $Value.Substring(4)
    }
    return Get-FullPath -Path $Value
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
        $Key = $Matches[1]
        $Value = $Matches[2]
        if ($Value.Length -ge 2 -and $Value[0] -eq [char]34 -and $Value[$Value.Length - 1] -eq [char]34) {
            $Value = $Value.Substring(1, $Value.Length - 2)
            $Value = $Value.Replace($EscapedQuote, [string][char]34)
            $Value = $Value.Replace($DoubleSlash, $Slash)
        }
        $Map[$Key] = $Value
    }
    return $Map
}

function Get-SnapshotRows {
    param([Parameter(Mandatory = $true)][string]$VBoxManage, [Parameter(Mandatory = $true)][string]$Uuid)
    $Result = Invoke-NativeRead -FilePath $VBoxManage -Arguments @('snapshot', $Uuid, 'list', '--machinereadable') -Label 'VBoxManage snapshot list'
    if ($Result.ExitCode -eq 0) {
        return [string[]]@($Result.Output | Where-Object { $_.Trim().Length -gt 0 })
    }
    $Text = $Result.Output -join "`n"
    if ($Text -match '(?i)does not have any snapshots') {
        return [string[]]@()
    }
    throw "snapshot list failed exit=$($Result.ExitCode) output=$($Result.Output -join ' | ')"
}

foreach ($RequiredExe in @($VBoxManagePath, $ScPath, $FsutilPath)) {
    if (-not (Test-Path -LiteralPath $RequiredExe -PathType Leaf)) {
        throw "required executable missing: $RequiredExe"
    }
}

$VBoxManage = (Resolve-Path -LiteralPath $VBoxManagePath -ErrorAction Stop).Path
$PortableRoot = (Resolve-Path -LiteralPath $PortableVirtualBoxRoot -ErrorAction Stop).Path
$R3Root = (Resolve-Path -LiteralPath $PreparedRoot -ErrorAction Stop).Path
$MutationReport = (Resolve-Path -LiteralPath $MutationReportPath -ErrorAction Stop).Path
$FailedBootReport = (Resolve-Path -LiteralPath $FailedBootAttemptReportPath -ErrorAction Stop).Path
$PreparedVerification = (Resolve-Path -LiteralPath $PreparedVerificationReportPath -ErrorAction Stop).Path
$BootAuthorization = (Resolve-Path -LiteralPath $BootAuthorizationReportPath -ErrorAction Stop).Path
$Output = Get-FullPath -Path $OutPath

Assert-PathEquals -Observed $VBoxManage -Expected $ExpectedVBoxManage -Label 'VBoxManage path'
Assert-PathEquals -Observed $PortableRoot -Expected $ExpectedPortableRoot -Label 'portable root'
Assert-PathEquals -Observed $R3Root -Expected $ExpectedPreparedRoot -Label 'R3 root'
Assert-PathEquals -Observed $MutationReport -Expected $ExpectedMutationReport -Label 'mutation report'
Assert-PathEquals -Observed $FailedBootReport -Expected $ExpectedFailedBootReport -Label 'failed boot report'
Assert-PathEquals -Observed $PreparedVerification -Expected $ExpectedPreparedVerification -Label 'prepared verification report'
Assert-PathEquals -Observed $BootAuthorization -Expected $ExpectedBootAuthorization -Label 'boot authorization report'
Assert-PathEquals -Observed $Output -Expected $ExpectedOut -Label 'verification report'

if (Test-Path -LiteralPath $Output) {
    throw "host-ready verification report already exists: $Output"
}
$OutputParent = Split-Path -Parent $Output
if (-not (Test-Path -LiteralPath $OutputParent -PathType Container)) {
    throw "verification report parent missing: $OutputParent"
}

$MutationHash = (Get-FileHash -LiteralPath $MutationReport -Algorithm SHA256).Hash
$FailedBootHash = (Get-FileHash -LiteralPath $FailedBootReport -Algorithm SHA256).Hash
$PreparedVerificationHash = (Get-FileHash -LiteralPath $PreparedVerification -Algorithm SHA256).Hash
$BootAuthorizationHash = (Get-FileHash -LiteralPath $BootAuthorization -Algorithm SHA256).Hash
if ($MutationHash -cne $ExpectedMutationHash) { throw "mutation report SHA256 mismatch: $MutationHash" }
if ($FailedBootHash -cne $ExpectedFailedBootHash) { throw "failed boot report SHA256 mismatch: $FailedBootHash" }
if ($PreparedVerificationHash -cne $ExpectedPreparedVerificationHash) { throw "prepared verification SHA256 mismatch: $PreparedVerificationHash" }
if ($BootAuthorizationHash -cne $ExpectedBootAuthorizationHash) { throw "boot authorization SHA256 mismatch: $BootAuthorizationHash" }

$DriverPath = Join-Path $PortableRoot 'app64\drivers\vboxsup\VBoxSup.sys'
$InfPath = Join-Path $PortableRoot 'app64\drivers\vboxsup\VBoxSup.inf'
$CatPath = Join-Path $PortableRoot 'app64\drivers\vboxsup\VBoxSup.cat'
foreach ($Path in @($DriverPath, $InfPath, $CatPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "VBoxSup payload missing: $Path" }
}
$DriverItem = Get-Item -LiteralPath $DriverPath -Force -ErrorAction Stop
$DriverHashBefore = (Get-FileHash -LiteralPath $DriverPath -Algorithm SHA256).Hash
$InfHashBefore = (Get-FileHash -LiteralPath $InfPath -Algorithm SHA256).Hash
$CatHashBefore = (Get-FileHash -LiteralPath $CatPath -Algorithm SHA256).Hash
if ($DriverHashBefore -cne $ExpectedDriverHash) { throw 'VBoxSup.sys SHA256 mismatch' }
if ($DriverItem.VersionInfo.FileVersion -cne $ExpectedDriverVersion) { throw 'VBoxSup.sys version mismatch' }
if ($InfHashBefore -cne $ExpectedInfHash) { throw 'VBoxSup.inf SHA256 mismatch' }
if ($CatHashBefore -cne $ExpectedCatHash) { throw 'VBoxSup.cat SHA256 mismatch' }
$Signature = Get-AuthenticodeSignature -LiteralPath $DriverPath
if ($Signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) { throw "VBoxSup.sys signature is not Valid: $($Signature.Status)" }

if (-not (Test-Path -LiteralPath $ServiceRegistryPath)) { throw 'VBoxSup service registry key missing' }
$Service = Get-ItemProperty -LiteralPath $ServiceRegistryPath -ErrorAction Stop
$ServiceImageRaw = [string]$Service.ImagePath
$ServiceImage = Normalize-DriverImagePath -Path $ServiceImageRaw
$ServiceType = [int]$Service.Type
$ServiceStart = [int]$Service.Start
$ServiceError = [int]$Service.ErrorControl
$ServiceDisplay = [string]$Service.DisplayName
Assert-PathEquals -Observed $ServiceImage -Expected $DriverPath -Label 'VBoxSup ImagePath'
if ($ServiceType -ne 1) { throw "VBoxSup Type mismatch: $ServiceType" }
if ($ServiceStart -ne 2) { throw "VBoxSup Start mismatch: $ServiceStart" }
if ($ServiceError -ne 1) { throw "VBoxSup ErrorControl mismatch: $ServiceError" }
if ($ServiceDisplay -cne $ExpectedDisplayName) { throw "VBoxSup DisplayName mismatch: $ServiceDisplay" }

$ScQueryBefore = Invoke-NativeRead -FilePath $ScPath -Arguments @('query', $ServiceName) -Label 'sc query VBoxSup before'
Require-NativeSuccess -Result $ScQueryBefore
if (($ScQueryBefore.Output -join "`n") -notmatch '(?im)^\s*STATE\s*:\s*4\b') { throw 'VBoxSup numeric STATE 4 not observed before VBoxManage reads' }
$ScQc = Invoke-NativeRead -FilePath $ScPath -Arguments @('qc', $ServiceName) -Label 'sc qc VBoxSup'
Require-NativeSuccess -Result $ScQc

$CimRows = @(
    Get-CimInstance -ClassName Win32_SystemDriver -ErrorAction Stop |
        Where-Object { $_.Name -ieq $ServiceName }
)
if ($CimRows.Count -ne 1) { throw "Win32_SystemDriver VBoxSup cardinality mismatch: $($CimRows.Count)" }
if ([string]$CimRows[0].State -ine 'Running') { throw "Win32_SystemDriver VBoxSup state mismatch: $($CimRows[0].State)" }

$MachineDir = Join-Path $R3Root 'Machine'
$CurrentVBox = Join-Path $MachineDir 'Temple1.10.vbox'
$PreviousVBox = Join-Path $MachineDir 'Temple1.10.vbox-prev'
$VdiPath = Join-Path $MachineDir 'Temple1.10.vdi'
$IsoPath = Join-Path $MachineDir 'TempleOSTS.iso'
$VBoxUserHome = Join-Path $R3Root 'VBoxUserHome'
$RegistryPath = Join-Path $VBoxUserHome 'VirtualBox.xml'
foreach ($Path in @($CurrentVBox, $PreviousVBox, $VdiPath, $IsoPath, $RegistryPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "required R3 artifact missing: $Path" }
}

$CurrentVBoxHashBefore = (Get-FileHash -LiteralPath $CurrentVBox -Algorithm SHA256).Hash
$PreviousVBoxHashBefore = (Get-FileHash -LiteralPath $PreviousVBox -Algorithm SHA256).Hash
$VdiHashBefore = (Get-FileHash -LiteralPath $VdiPath -Algorithm SHA256).Hash
$IsoHashBefore = (Get-FileHash -LiteralPath $IsoPath -Algorithm SHA256).Hash
$RegistryHashBefore = (Get-FileHash -LiteralPath $RegistryPath -Algorithm SHA256).Hash
$CurrentVBoxIdBefore = Get-FileId -Path $CurrentVBox
$PreviousVBoxIdBefore = Get-FileId -Path $PreviousVBox
$VdiIdBefore = Get-FileId -Path $VdiPath
$IsoIdBefore = Get-FileId -Path $IsoPath

if ($CurrentVBoxHashBefore -cne $ExpectedCurrentVBoxHash -or $CurrentVBoxIdBefore -cne $ExpectedCurrentVBoxFileId) { throw 'current R3 VBOX identity mismatch' }
if ($PreviousVBoxHashBefore -cne $ExpectedPreviousVBoxHash -or $PreviousVBoxIdBefore -cne $ExpectedPreviousVBoxFileId) { throw 'previous R3 VBOX identity mismatch' }
if ($VdiHashBefore -cne $ExpectedVdiHash -or $VdiIdBefore -cne $ExpectedVdiFileId) { throw 'R3 VDI identity mismatch' }
if ($IsoHashBefore -cne $ExpectedIsoHash -or $IsoIdBefore -cne $ExpectedIsoFileId) { throw 'R3 ISO identity mismatch' }
if ($RegistryHashBefore -cne $ExpectedRegistryHash) { throw "isolated registry SHA256 mismatch before reads: $RegistryHashBefore" }

$OldVBoxUserHomeExists = Test-Path Env:VBOX_USER_HOME
$OldVBoxUserHome = if ($OldVBoxUserHomeExists) { [string]$env:VBOX_USER_HOME } else { $null }
try {
    $env:VBOX_USER_HOME = $VBoxUserHome

    $Version = Invoke-NativeRead -FilePath $VBoxManage -Arguments @('--version') -Label 'VBoxManage --version'
    Require-NativeSuccess -Result $Version
    if ($Version.Output.Count -ne 1 -or $Version.Output[0].Trim() -cne '7.0.12r159484') { throw "VirtualBox version mismatch: $($Version.Output -join ' | ')" }

    $ListVms = Invoke-NativeRead -FilePath $VBoxManage -Arguments @('list', 'vms') -Label 'VBoxManage list vms'
    Require-NativeSuccess -Result $ListVms
    $RegisteredRows = @($ListVms.Output | Where-Object { $_.Trim().Length -gt 0 })
    if ($RegisteredRows.Count -ne 1) { throw "registered VM count mismatch: $($RegisteredRows.Count)" }
    if ($RegisteredRows[0] -notmatch '^"Temple1\.10"\s+\{9c98691e-27cd-4487-a306-587969c2c78c\}$') { throw "registered VM row mismatch: $($RegisteredRows[0])" }

    $Running = Invoke-NativeRead -FilePath $VBoxManage -Arguments @('list', 'runningvms') -Label 'VBoxManage list runningvms'
    Require-NativeSuccess -Result $Running
    $RunningRows = @($Running.Output | Where-Object { $_.Trim().Length -gt 0 })
    if ($RunningRows.Count -ne 0) { throw "running VM count mismatch: $($RunningRows.Count)" }

    $Info = Invoke-NativeRead -FilePath $VBoxManage -Arguments @('showvminfo', $TargetUuid, '--machinereadable') -Label 'VBoxManage showvminfo'
    Require-NativeSuccess -Result $Info
    $Map = Convert-MachineReadable -Rows $Info.Output
    foreach ($RequiredKey in @('VMState', 'CfgFile', 'IDE-1-0', 'boot1', 'boot2', 'boot3', 'boot4', 'clipboard', 'draganddrop', 'graphicscontroller', 'vram')) {
        if (-not $Map.ContainsKey($RequiredKey)) { throw "showvminfo missing key: $RequiredKey" }
    }
    if ([string]$Map['VMState'] -cne 'poweroff') { throw "VMState mismatch: $($Map['VMState'])" }
    Assert-PathEquals -Observed ([string]$Map['CfgFile']) -Expected $CurrentVBox -Label 'showvminfo CfgFile'
    Assert-PathEquals -Observed ([string]$Map['IDE-1-0']) -Expected $VdiPath -Label 'showvminfo VDI attachment'
    if ($Map.ContainsKey('IDE-0-1') -and [string]$Map['IDE-0-1'] -cne 'none') { throw "ISO slot is not detached: $($Map['IDE-0-1'])" }
    if ([string]$Map['boot1'] -cne 'disk' -or [string]$Map['boot2'] -cne 'none' -or [string]$Map['boot3'] -cne 'none' -or [string]$Map['boot4'] -cne 'none') { throw 'boot order mismatch' }
    if ([string]$Map['clipboard'] -cne 'disabled') { throw "clipboard mismatch: $($Map['clipboard'])" }
    if ([string]$Map['draganddrop'] -cne 'disabled') { throw "draganddrop mismatch: $($Map['draganddrop'])" }
    if ([string]$Map['graphicscontroller'] -cne 'vboxvga') { throw "graphicscontroller mismatch: $($Map['graphicscontroller'])" }
    if ([string]$Map['vram'] -cne '9') { throw "vram mismatch: $($Map['vram'])" }
    $NicKeys = @($Map.Keys | Where-Object { $_ -match '^nic\d+$' })
    if ($NicKeys.Count -eq 0) { throw 'showvminfo exposed no NIC keys' }
    foreach ($Key in $NicKeys) {
        if ([string]$Map[$Key] -cne 'none') { throw "network adapter not disabled: $Key=$($Map[$Key])" }
    }

    $Snapshots = @(Get-SnapshotRows -VBoxManage $VBoxManage -Uuid $TargetUuid)
    if ($Snapshots.Count -ne 0) { throw "snapshot inventory is not empty: $($Snapshots.Count)" }

    $Medium = Invoke-NativeRead -FilePath $VBoxManage -Arguments @('showmediuminfo', 'disk', $VdiPath) -Label 'VBoxManage showmediuminfo disk'
    Require-NativeSuccess -Result $Medium
    $MediumText = $Medium.Output -join "`n"
    if ($MediumText -notmatch '(?im)^UUID:\s*55c1f29d-a681-402e-b90d-bfbb6b09f207\s*$') { throw 'VDI UUID not observed in showmediuminfo output' }
}
finally {
    if ($OldVBoxUserHomeExists) { $env:VBOX_USER_HOME = $OldVBoxUserHome } else { Remove-Item Env:VBOX_USER_HOME -ErrorAction SilentlyContinue }
}

$ScQueryAfter = Invoke-NativeRead -FilePath $ScPath -Arguments @('query', $ServiceName) -Label 'sc query VBoxSup after'
Require-NativeSuccess -Result $ScQueryAfter
if (($ScQueryAfter.Output -join "`n") -notmatch '(?im)^\s*STATE\s*:\s*4\b') { throw 'VBoxSup numeric STATE 4 not observed after VBoxManage reads' }

$DriverHashAfter = (Get-FileHash -LiteralPath $DriverPath -Algorithm SHA256).Hash
$InfHashAfter = (Get-FileHash -LiteralPath $InfPath -Algorithm SHA256).Hash
$CatHashAfter = (Get-FileHash -LiteralPath $CatPath -Algorithm SHA256).Hash
$CurrentVBoxHashAfter = (Get-FileHash -LiteralPath $CurrentVBox -Algorithm SHA256).Hash
$PreviousVBoxHashAfter = (Get-FileHash -LiteralPath $PreviousVBox -Algorithm SHA256).Hash
$VdiHashAfter = (Get-FileHash -LiteralPath $VdiPath -Algorithm SHA256).Hash
$IsoHashAfter = (Get-FileHash -LiteralPath $IsoPath -Algorithm SHA256).Hash
$RegistryHashAfter = (Get-FileHash -LiteralPath $RegistryPath -Algorithm SHA256).Hash
$CurrentVBoxIdAfter = Get-FileId -Path $CurrentVBox
$PreviousVBoxIdAfter = Get-FileId -Path $PreviousVBox
$VdiIdAfter = Get-FileId -Path $VdiPath
$IsoIdAfter = Get-FileId -Path $IsoPath

if ($DriverHashAfter -cne $DriverHashBefore -or $InfHashAfter -cne $InfHashBefore -or $CatHashAfter -cne $CatHashBefore) { throw 'VBoxSup payload drifted during read-only verification' }
if ($CurrentVBoxHashAfter -cne $CurrentVBoxHashBefore -or $CurrentVBoxIdAfter -cne $CurrentVBoxIdBefore) { throw 'current VBOX drifted during read-only verification' }
if ($PreviousVBoxHashAfter -cne $PreviousVBoxHashBefore -or $PreviousVBoxIdAfter -cne $PreviousVBoxIdBefore) { throw 'previous VBOX drifted during read-only verification' }
if ($VdiHashAfter -cne $VdiHashBefore -or $VdiIdAfter -cne $VdiIdBefore) { throw 'VDI drifted during read-only verification' }
if ($IsoHashAfter -cne $IsoHashBefore -or $IsoIdAfter -cne $IsoIdBefore) { throw 'ISO drifted during read-only verification' }
if ($RegistryHashAfter -cne $RegistryHashBefore) { throw 'isolated VirtualBox.xml drifted during read-only verification' }

$Lines = [System.Collections.Generic.List[string]]::new()
$Lines.Add('DBYTE-HOLYC-OPT')
$Lines.Add('PORTABLE VIRTUALBOX7 VBOXSUP HOST-READY + R3 READ-ONLY VERIFICATION')
$Lines.Add('')
$Lines.Add("portable_root`t$PortableRoot")
$Lines.Add("prepared_r3_root`t$R3Root")
$Lines.Add("bound_mutation_report_sha256`t$MutationHash")
$Lines.Add("bound_failed_boot_report_sha256`t$FailedBootHash")
$Lines.Add("bound_prepared_verification_sha256`t$PreparedVerificationHash")
$Lines.Add("bound_boot_authorization_sha256`t$BootAuthorizationHash")
$Lines.Add('')
$Lines.Add("vboxsup_sys_sha256`t$DriverHashAfter")
$Lines.Add("vboxsup_sys_version`t$($DriverItem.VersionInfo.FileVersion)")
$Lines.Add("vboxsup_signature_status`t$($Signature.Status)")
$Lines.Add("vboxsup_service_image_path`t$ServiceImage")
$Lines.Add("vboxsup_service_type`t$ServiceType")
$Lines.Add("vboxsup_service_start`t$ServiceStart")
$Lines.Add("vboxsup_service_error_control`t$ServiceError")
$Lines.Add("vboxsup_service_display_name`t$ServiceDisplay")
$Lines.Add("sc_state_before`t4")
$Lines.Add("sc_state_after`t4")
$Lines.Add("cim_vboxsup_count`t$($CimRows.Count)")
$Lines.Add("cim_vboxsup_state`t$([string]$CimRows[0].State)")
$Lines.Add("cim_vboxsup_start_mode`t$([string]$CimRows[0].StartMode)")
$Lines.Add("cim_vboxsup_path`t$([string]$CimRows[0].PathName)")
$Lines.Add('')
$Lines.Add("virtualbox_version`t$($Version.Output[0].Trim())")
$Lines.Add("registered_vms`t$($RegisteredRows.Count)")
$Lines.Add("running_vms`t$($RunningRows.Count)")
$Lines.Add("machine_uuid`t$TargetUuid")
$Lines.Add("machine_state`t$($Map['VMState'])")
$Lines.Add("cfg_file`t$($Map['CfgFile'])")
$Lines.Add("vdi_attachment`t$($Map['IDE-1-0'])")
$Lines.Add("boot1`t$($Map['boot1'])")
$Lines.Add("boot2`t$($Map['boot2'])")
$Lines.Add("boot3`t$($Map['boot3'])")
$Lines.Add("boot4`t$($Map['boot4'])")
$Lines.Add("network_adapter_keys`t$($NicKeys.Count)")
$Lines.Add("clipboard`t$($Map['clipboard'])")
$Lines.Add("draganddrop`t$($Map['draganddrop'])")
$Lines.Add("graphicscontroller`t$($Map['graphicscontroller'])")
$Lines.Add("vram`t$($Map['vram'])")
$Lines.Add("snapshot_rows`t$($Snapshots.Count)")
$Lines.Add("vdi_uuid`t$ExpectedVdiUuid")
$Lines.Add('')
$Lines.Add("current_vbox_sha256`t$CurrentVBoxHashAfter")
$Lines.Add("current_vbox_file_id`t$CurrentVBoxIdAfter")
$Lines.Add("previous_vbox_sha256`t$PreviousVBoxHashAfter")
$Lines.Add("previous_vbox_file_id`t$PreviousVBoxIdAfter")
$Lines.Add("vdi_sha256`t$VdiHashAfter")
$Lines.Add("vdi_file_id`t$VdiIdAfter")
$Lines.Add("iso_sha256`t$IsoHashAfter")
$Lines.Add("iso_file_id`t$IsoIdAfter")
$Lines.Add("registry_sha_before`t$RegistryHashBefore")
$Lines.Add("registry_sha_after`t$RegistryHashAfter")
$Lines.Add('')
$Lines.Add("SC MUTATION`tNOT-EXECUTED")
$Lines.Add("DRIVER INSTALL/START`tNOT-EXECUTED")
$Lines.Add("VBOXMANAGE`tREAD-ONLY-ONLY")
$Lines.Add("VM START`tNOT-EXECUTED")
$Lines.Add("VM RETRY AUTHORIZATION`tREADY-FOR-SEPARATE-EXPLICIT-DECISION")
$Lines.Add("VERDICT`tVBOXSUP HOST READY + R3 STATE VERIFIED READ-ONLY")
$Lines.Add('')
$Lines.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')

[System.IO.File]::WriteAllText(
    $Output,
    (($Lines.ToArray() -join "`n") + "`n"),
    [System.Text.UTF8Encoding]::new($false)
)
$ReportHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

Write-Host "PORTABLE ROOT:          $PortableRoot"
Write-Host "BOUND MUTATION REPORT:  $MutationHash"
Write-Host "VBOXSUP.SYS SHA256:     $DriverHashAfter"
Write-Host "VBOXSUP SERVICE:        TYPE=$ServiceType START=$ServiceStart STATE=4"
Write-Host "CIM VBOXSUP:            $($CimRows.Count) / $([string]$CimRows[0].State)"
Write-Host "VIRTUALBOX VERSION:     $($Version.Output[0].Trim())"
Write-Host "REGISTERED VMS:         $($RegisteredRows.Count)"
Write-Host "RUNNING VMS:            $($RunningRows.Count)"
Write-Host "MACHINE STATE:          $($Map['VMState'])"
Write-Host "BOOT ORDER:             $($Map['boot1']) / $($Map['boot2']) / $($Map['boot3']) / $($Map['boot4'])"
Write-Host "NETWORK DISABLED:       $([bool](($NicKeys | Where-Object { [string]$Map[$_] -cne 'none' }).Count -eq 0))"
Write-Host "SNAPSHOT ROWS:          $($Snapshots.Count)"
Write-Host "REGISTRY SHA BEFORE:    $RegistryHashBefore"
Write-Host "REGISTRY SHA AFTER:     $RegistryHashAfter"
Write-Host "REPORT:                 $Output"
Write-Host "REPORT SHA256:          $ReportHash"
Write-Host 'SC MUTATION:            NOT-EXECUTED'
Write-Host 'DRIVER INSTALL/START:   NOT-EXECUTED'
Write-Host 'VBOXMANAGE:             READ-ONLY-ONLY'
Write-Host 'VM START:               NOT-EXECUTED'
Write-Host 'VM RETRY AUTHORIZATION: READY-FOR-SEPARATE-EXPLICIT-DECISION'
Write-Host 'VERDICT:                VBOXSUP HOST READY + R3 STATE VERIFIED READ-ONLY'
