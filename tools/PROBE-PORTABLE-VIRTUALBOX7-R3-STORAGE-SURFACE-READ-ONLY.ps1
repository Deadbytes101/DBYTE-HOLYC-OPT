[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$VBoxManagePath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$PreparedRoot,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$MutationReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedVBoxManage = 'D:\Portable-VirtualBox7\app64\VBoxManage.exe'
$ExpectedPreparedRoot = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r3'
$ExpectedMutationReport = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-portable-vbox-vboxsup-surgical-install-start.txt'
$ExpectedMutationHash = '3C24420D77868E8D15F58A6412AF53635EEAFFF00337CCEB01E17C31183666F3'
$ExpectedFailedVerifierOut = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-portable-vbox-vboxsup-host-ready-r3-verification.txt'
$ExpectedOut = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-portable-vbox-r3-storage-surface-probe.txt'

$ExpectedCurrentVBoxHash = '8EADB39D54CABE5E7B791E5D7E05BCF4CBBF32D4AB6B58291BEC0B2FAD607C0C'
$ExpectedPreviousVBoxHash = 'C93D128227EE80B647DB63FE64277CEF1BDC61C224110472C73CBFFEC63877A7'
$ExpectedVdiHash = '90D453A94F075760A11E0772862E60C4B031ED874F28AA396EAE638F7EB8B31B'
$ExpectedIsoHash = 'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$ExpectedCurrentVBoxFileId = '0X000000000000000000050000000609A1'
$ExpectedPreviousVBoxFileId = '0X000000000000000000040000000609A7'
$ExpectedVdiFileId = '0X000000000000000000010000000609A2'
$ExpectedIsoFileId = '0X000000000000000000010000000609A3'
$ExpectedRegistryHash = '99DB185525D245B1AAFF6937B459518089435882373A55CD2159D03FC82FDCBF'
$ExpectedDriverHash = '3344E2909580A9965E38B26AB9E9958842315DDEA1B0D0E274DA314DDCAB97F4'

$TargetUuid = '9c98691e-27cd-4487-a306-587969c2c78c'
$ExpectedVdiUuid = '55c1f29d-a681-402e-b90d-bfbb6b09f207'
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
        throw "$($Result.Label) failed exit=$($Result.ExitCode) output=$($Result.Output -join ' | ')"
    }
}

function Get-FileId {
    param([Parameter(Mandatory = $true)][string]$Path)
    $Result = Invoke-NativeRead -FilePath $FsutilPath -Arguments @('file', 'queryfileid', $Path) -Label "fsutil queryfileid $Path"
    Require-NativeSuccess -Result $Result
    $Match = [regex]::Match(($Result.Output -join "`n"), '(?i)0x[0-9a-f]+')
    if (-not $Match.Success) {
        throw "file ID missing from fsutil output: $Path"
    }
    return $Match.Value.ToUpperInvariant()
}

function Require-ServiceState4 {
    param([Parameter(Mandatory = $true)][string]$Label)
    $Result = Invoke-NativeRead -FilePath $ScPath -Arguments @('query', $ServiceName) -Label $Label
    Require-NativeSuccess -Result $Result
    if (($Result.Output -join "`n") -notmatch '(?im)^\s*STATE\s*:\s*4\b') {
        throw "VBoxSup numeric STATE 4 not observed: $Label"
    }
    return $Result
}

foreach ($Exe in @($VBoxManagePath, $ScPath, $FsutilPath)) {
    if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) {
        throw "required executable missing: $Exe"
    }
}

$VBoxManage = (Resolve-Path -LiteralPath $VBoxManagePath -ErrorAction Stop).Path
$R3Root = (Resolve-Path -LiteralPath $PreparedRoot -ErrorAction Stop).Path
$MutationReport = (Resolve-Path -LiteralPath $MutationReportPath -ErrorAction Stop).Path
$Output = Get-FullPath -Path $OutPath

Assert-PathEquals -Observed $VBoxManage -Expected $ExpectedVBoxManage -Label 'VBoxManage path'
Assert-PathEquals -Observed $R3Root -Expected $ExpectedPreparedRoot -Label 'R3 root'
Assert-PathEquals -Observed $MutationReport -Expected $ExpectedMutationReport -Label 'mutation report'
Assert-PathEquals -Observed $Output -Expected $ExpectedOut -Label 'probe report'

if (Test-Path -LiteralPath $ExpectedFailedVerifierOut) {
    throw "failed verifier unexpectedly produced final report; preserve and inspect first: $ExpectedFailedVerifierOut"
}
if (Test-Path -LiteralPath $Output) {
    throw "storage-surface probe report already exists: $Output"
}
$OutputParent = Split-Path -Parent $Output
if (-not (Test-Path -LiteralPath $OutputParent -PathType Container)) {
    throw "probe report parent missing: $OutputParent"
}

$MutationHash = (Get-FileHash -LiteralPath $MutationReport -Algorithm SHA256).Hash
if ($MutationHash -cne $ExpectedMutationHash) {
    throw "mutation report SHA256 mismatch: observed=$MutationHash expected=$ExpectedMutationHash"
}

$MachineDir = Join-Path $R3Root 'Machine'
$CurrentVBox = Join-Path $MachineDir 'Temple1.10.vbox'
$PreviousVBox = Join-Path $MachineDir 'Temple1.10.vbox-prev'
$VdiPath = Join-Path $MachineDir 'Temple1.10.vdi'
$IsoPath = Join-Path $MachineDir 'TempleOSTS.iso'
$VBoxUserHome = Join-Path $R3Root 'VBoxUserHome'
$RegistryPath = Join-Path $VBoxUserHome 'VirtualBox.xml'
$DriverPath = 'D:\Portable-VirtualBox7\app64\drivers\vboxsup\VBoxSup.sys'

foreach ($Path in @($CurrentVBox, $PreviousVBox, $VdiPath, $IsoPath, $RegistryPath, $DriverPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "required evidence artifact missing: $Path"
    }
}

$CurrentVBoxHashBefore = (Get-FileHash -LiteralPath $CurrentVBox -Algorithm SHA256).Hash
$PreviousVBoxHashBefore = (Get-FileHash -LiteralPath $PreviousVBox -Algorithm SHA256).Hash
$VdiHashBefore = (Get-FileHash -LiteralPath $VdiPath -Algorithm SHA256).Hash
$IsoHashBefore = (Get-FileHash -LiteralPath $IsoPath -Algorithm SHA256).Hash
$RegistryHashBefore = (Get-FileHash -LiteralPath $RegistryPath -Algorithm SHA256).Hash
$DriverHashBefore = (Get-FileHash -LiteralPath $DriverPath -Algorithm SHA256).Hash
$CurrentVBoxIdBefore = Get-FileId -Path $CurrentVBox
$PreviousVBoxIdBefore = Get-FileId -Path $PreviousVBox
$VdiIdBefore = Get-FileId -Path $VdiPath
$IsoIdBefore = Get-FileId -Path $IsoPath

if ($CurrentVBoxHashBefore -cne $ExpectedCurrentVBoxHash -or $CurrentVBoxIdBefore -cne $ExpectedCurrentVBoxFileId) { throw 'current R3 VBOX identity mismatch before probe' }
if ($PreviousVBoxHashBefore -cne $ExpectedPreviousVBoxHash -or $PreviousVBoxIdBefore -cne $ExpectedPreviousVBoxFileId) { throw 'previous R3 VBOX identity mismatch before probe' }
if ($VdiHashBefore -cne $ExpectedVdiHash -or $VdiIdBefore -cne $ExpectedVdiFileId) { throw 'R3 VDI identity mismatch before probe' }
if ($IsoHashBefore -cne $ExpectedIsoHash -or $IsoIdBefore -cne $ExpectedIsoFileId) { throw 'R3 ISO identity mismatch before probe' }
if ($RegistryHashBefore -cne $ExpectedRegistryHash) { throw 'isolated VirtualBox.xml identity mismatch before probe' }
if ($DriverHashBefore -cne $ExpectedDriverHash) { throw 'VBoxSup.sys identity mismatch before probe' }

$ScBefore = Require-ServiceState4 -Label 'sc query VBoxSup before storage probe'

[xml]$VBoxXml = [System.IO.File]::ReadAllText($CurrentVBox)
$ControllerNodes = @($VBoxXml.SelectNodes('//*[local-name()="StorageController"]'))
$XmlRows = [System.Collections.Generic.List[string]]::new()
foreach ($Controller in $ControllerNodes) {
    $Name = [string]$Controller.GetAttribute('name')
    if ([string]::IsNullOrEmpty($Name)) { $Name = [string]$Controller.GetAttribute('Name') }
    $Bus = [string]$Controller.GetAttribute('bus')
    if ([string]::IsNullOrEmpty($Bus)) { $Bus = [string]$Controller.GetAttribute('Bus') }
    $PortCount = [string]$Controller.GetAttribute('PortCount')
    $XmlRows.Add("controller`t$Name`t$Bus`t$PortCount")
    $Devices = @($Controller.SelectNodes('./*[local-name()="AttachedDevice"]'))
    foreach ($Device in $Devices) {
        $Type = [string]$Device.GetAttribute('type')
        if ([string]::IsNullOrEmpty($Type)) { $Type = [string]$Device.GetAttribute('Type') }
        $Port = [string]$Device.GetAttribute('port')
        $DeviceNo = [string]$Device.GetAttribute('device')
        $Hotplug = [string]$Device.GetAttribute('hotpluggable')
        $ImageNodes = @($Device.SelectNodes('./*[local-name()="Image"]'))
        $ImageUuid = if ($ImageNodes.Count -eq 1) { [string]$ImageNodes[0].GetAttribute('uuid') } else { '' }
        $XmlRows.Add("attached`t$Name`t$Type`t$Port`t$DeviceNo`t$Hotplug`t$ImageUuid")
    }
}

$OldVBoxUserHomeExists = Test-Path Env:VBOX_USER_HOME
$OldVBoxUserHome = if ($OldVBoxUserHomeExists) { [string]$env:VBOX_USER_HOME } else { $null }
try {
    $env:VBOX_USER_HOME = $VBoxUserHome

    $Version = Invoke-NativeRead -FilePath $VBoxManage -Arguments @('--version') -Label 'VBoxManage --version'
    Require-NativeSuccess -Result $Version
    if ($Version.Output.Count -ne 1 -or $Version.Output[0].Trim() -cne '7.0.12r159484') {
        throw "VirtualBox version mismatch: $($Version.Output -join ' | ')"
    }

    $Running = Invoke-NativeRead -FilePath $VBoxManage -Arguments @('list', 'runningvms') -Label 'VBoxManage list runningvms'
    Require-NativeSuccess -Result $Running
    $RunningRows = @($Running.Output | Where-Object { $_.Trim().Length -gt 0 })
    if ($RunningRows.Count -ne 0) {
        throw "running VM count mismatch before storage probe: $($RunningRows.Count)"
    }

    $MachineReadable = Invoke-NativeRead -FilePath $VBoxManage -Arguments @('showvminfo', $TargetUuid, '--machinereadable') -Label 'VBoxManage showvminfo --machinereadable'
    Require-NativeSuccess -Result $MachineReadable

    $Human = Invoke-NativeRead -FilePath $VBoxManage -Arguments @('showvminfo', $TargetUuid) -Label 'VBoxManage showvminfo'
    Require-NativeSuccess -Result $Human

    $Medium = Invoke-NativeRead -FilePath $VBoxManage -Arguments @('showmediuminfo', 'disk', $VdiPath) -Label 'VBoxManage showmediuminfo disk'
    Require-NativeSuccess -Result $Medium
    if (($Medium.Output -join "`n") -notmatch '(?im)^UUID:\s*55c1f29d-a681-402e-b90d-bfbb6b09f207\s*$') {
        throw 'VDI UUID not observed in showmediuminfo output'
    }
}
finally {
    if ($OldVBoxUserHomeExists) {
        $env:VBOX_USER_HOME = $OldVBoxUserHome
    }
    else {
        Remove-Item Env:VBOX_USER_HOME -ErrorAction SilentlyContinue
    }
}

$ScAfter = Require-ServiceState4 -Label 'sc query VBoxSup after storage probe'

$CurrentVBoxHashAfter = (Get-FileHash -LiteralPath $CurrentVBox -Algorithm SHA256).Hash
$PreviousVBoxHashAfter = (Get-FileHash -LiteralPath $PreviousVBox -Algorithm SHA256).Hash
$VdiHashAfter = (Get-FileHash -LiteralPath $VdiPath -Algorithm SHA256).Hash
$IsoHashAfter = (Get-FileHash -LiteralPath $IsoPath -Algorithm SHA256).Hash
$RegistryHashAfter = (Get-FileHash -LiteralPath $RegistryPath -Algorithm SHA256).Hash
$DriverHashAfter = (Get-FileHash -LiteralPath $DriverPath -Algorithm SHA256).Hash
$CurrentVBoxIdAfter = Get-FileId -Path $CurrentVBox
$PreviousVBoxIdAfter = Get-FileId -Path $PreviousVBox
$VdiIdAfter = Get-FileId -Path $VdiPath
$IsoIdAfter = Get-FileId -Path $IsoPath

if ($CurrentVBoxHashAfter -cne $CurrentVBoxHashBefore -or $CurrentVBoxIdAfter -cne $CurrentVBoxIdBefore) { throw 'current R3 VBOX drifted during storage probe' }
if ($PreviousVBoxHashAfter -cne $PreviousVBoxHashBefore -or $PreviousVBoxIdAfter -cne $PreviousVBoxIdBefore) { throw 'previous R3 VBOX drifted during storage probe' }
if ($VdiHashAfter -cne $VdiHashBefore -or $VdiIdAfter -cne $VdiIdBefore) { throw 'R3 VDI drifted during storage probe' }
if ($IsoHashAfter -cne $IsoHashBefore -or $IsoIdAfter -cne $IsoIdBefore) { throw 'R3 ISO drifted during storage probe' }
if ($RegistryHashAfter -cne $RegistryHashBefore) { throw 'isolated VirtualBox.xml drifted during storage probe' }
if ($DriverHashAfter -cne $DriverHashBefore) { throw 'VBoxSup.sys drifted during storage probe' }

$ParsedKeyRows = [System.Collections.Generic.List[string]]::new()
foreach ($Row in @($MachineReadable.Output)) {
    if ($Row -match '^([^=]+)=(.*)$') {
        $RawKey = [string]$Matches[1]
        $NormalizedKey = $RawKey.Trim()
        if ($NormalizedKey.Length -ge 2 -and $NormalizedKey[0] -eq [char]34 -and $NormalizedKey[$NormalizedKey.Length - 1] -eq [char]34) {
            $NormalizedKey = $NormalizedKey.Substring(1, $NormalizedKey.Length - 2)
        }
        $ParsedKeyRows.Add("key`t$RawKey`t$NormalizedKey")
    }
}

$StorageMachineRows = @(
    $MachineReadable.Output | Where-Object {
        $_ -match '(?i)(IDE|SATA|SCSI|NVMe|Floppy|DVD|Optical|Storage|Controller|\.vdi|\.iso)'
    }
)
$StorageHumanRows = @(
    $Human.Output | Where-Object {
        $_ -match '(?i)(IDE|SATA|SCSI|NVMe|Floppy|DVD|Optical|Storage|Controller|\.vdi|\.iso)'
    }
)

$Lines = [System.Collections.Generic.List[string]]::new()
$Lines.Add('DBYTE-HOLYC-OPT')
$Lines.Add('PORTABLE VIRTUALBOX7 R3 STORAGE SURFACE READ-ONLY PROBE')
$Lines.Add('')
$Lines.Add("prepared_r3_root`t$R3Root")
$Lines.Add("bound_mutation_report_sha256`t$MutationHash")
$Lines.Add("virtualbox_version`t$($Version.Output[0].Trim())")
$Lines.Add("running_vms`t$($RunningRows.Count)")
$Lines.Add("vboxsup_state_before`t4")
$Lines.Add("vboxsup_state_after`t4")
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
$Lines.Add("vboxsup_sys_sha256`t$DriverHashAfter")
$Lines.Add("expected_vdi_uuid`t$ExpectedVdiUuid")
$Lines.Add('')
$Lines.Add("xml_storage_controller_count`t$($ControllerNodes.Count)")
foreach ($Row in $XmlRows) { $Lines.Add("xml_storage`t$Row") }
$Lines.Add('')
$Lines.Add("machinereadable_row_count`t$($MachineReadable.Output.Count)")
foreach ($Row in @($MachineReadable.Output)) { $Lines.Add("machinereadable_raw`t$Row") }
$Lines.Add('')
$Lines.Add("parsed_key_count`t$($ParsedKeyRows.Count)")
foreach ($Row in $ParsedKeyRows) { $Lines.Add("machinereadable_$Row") }
$Lines.Add('')
$Lines.Add("storage_machinereadable_row_count`t$($StorageMachineRows.Count)")
foreach ($Row in $StorageMachineRows) { $Lines.Add("storage_machinereadable`t$Row") }
$Lines.Add('')
$Lines.Add("storage_human_row_count`t$($StorageHumanRows.Count)")
foreach ($Row in $StorageHumanRows) { $Lines.Add("storage_human`t$Row") }
$Lines.Add('')
$Lines.Add("medium_row_count`t$($Medium.Output.Count)")
foreach ($Row in @($Medium.Output)) { $Lines.Add("medium_raw`t$Row") }
$Lines.Add('')
$Lines.Add("SC MUTATION`tNOT-EXECUTED")
$Lines.Add("DRIVER INSTALL/START`tNOT-EXECUTED")
$Lines.Add("VBOXMANAGE`tREAD-ONLY-ONLY")
$Lines.Add("VM START`tNOT-EXECUTED")
$Lines.Add("STORAGE INTERPRETATION`tPENDING / RAW SURFACE CAPTURED")
$Lines.Add("VERDICT`tR3 STORAGE SURFACE PROBED READ-ONLY")
$Lines.Add('')
$Lines.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')

[System.IO.File]::WriteAllText(
    $Output,
    (($Lines.ToArray() -join "`n") + "`n"),
    [System.Text.UTF8Encoding]::new($false)
)
$ReportHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

Write-Host "PREPARED R3 ROOT:       $R3Root"
Write-Host "BOUND MUTATION REPORT:  $MutationHash"
Write-Host "VIRTUALBOX VERSION:     $($Version.Output[0].Trim())"
Write-Host "RUNNING VMS:            $($RunningRows.Count)"
Write-Host 'VBOXSUP STATE:          4 BEFORE / 4 AFTER'
Write-Host "XML CONTROLLERS:        $($ControllerNodes.Count)"
Write-Host "MACHINEREADABLE ROWS:   $($MachineReadable.Output.Count)"
Write-Host "PARSED KEYS:            $($ParsedKeyRows.Count)"
Write-Host "STORAGE MR ROWS:        $($StorageMachineRows.Count)"
Write-Host "STORAGE HUMAN ROWS:     $($StorageHumanRows.Count)"
Write-Host "REGISTRY SHA BEFORE:    $RegistryHashBefore"
Write-Host "REGISTRY SHA AFTER:     $RegistryHashAfter"
Write-Host "REPORT:                 $Output"
Write-Host "REPORT SHA256:          $ReportHash"
Write-Host 'SC MUTATION:            NOT-EXECUTED'
Write-Host 'DRIVER INSTALL/START:   NOT-EXECUTED'
Write-Host 'VBOXMANAGE:             READ-ONLY-ONLY'
Write-Host 'VM START:               NOT-EXECUTED'
Write-Host 'VERDICT:                R3 STORAGE SURFACE PROBED READ-ONLY'
