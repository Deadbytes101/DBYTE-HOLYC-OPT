[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VBoxManagePath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PreparedRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PreparedVerificationReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedRoot =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r3'
$ExpectedVerificationReport =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r3-prepared-verification.txt'
$ExpectedVerificationHash =
    '26DC5258CF4692FD55EC95D81E48E3CFE05B4667BC20CDAC0CFFD58DC8433EF7'
$ExpectedOut =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r3-boot-authorization-adjudication.txt'

$ExpectedVBoxVersion = '7.0.12r159484'
$ExpectedMachineName = 'Temple1.10'
$ExpectedMachineUuid = '9c98691e-27cd-4487-a306-587969c2c78c'
$ExpectedVdiUuid = '55c1f29d-a681-402e-b90d-bfbb6b09f207'

$ExpectedCurrentVBoxHash =
    '8EADB39D54CABE5E7B791E5D7E05BCF4CBBF32D4AB6B58291BEC0B2FAD607C0C'
$ExpectedPreviousVBoxHash =
    'C93D128227EE80B647DB63FE64277CEF1BDC61C224110472C73CBFFEC63877A7'
$ExpectedVdiHash =
    '90D453A94F075760A11E0772862E60C4B031ED874F28AA396EAE638F7EB8B31B'
$ExpectedIsoHash =
    'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'

$ExpectedCurrentVBoxId = '0X000000000000000000050000000609A1'
$ExpectedPreviousVBoxId = '0X000000000000000000040000000609A7'
$ExpectedVdiId = '0X000000000000000000010000000609A2'
$ExpectedIsoId = '0X000000000000000000010000000609A3'

function Get-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath(
        [Environment]::ExpandEnvironmentVariables($Path)
    ).TrimEnd('\', '/')
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

function Get-FileId {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Captured = @(
        & fsutil file queryfileid $Path 2>&1 |
            ForEach-Object { [string]$_ }
    )
    if ($LASTEXITCODE -ne 0) {
        throw "${Label} file-ID query failed`n$($Captured -join "`n")"
    }

    $Ids = @(
        foreach ($Line in $Captured) {
            foreach ($Match in [regex]::Matches($Line, '0x[0-9A-Fa-f]+')) {
                $Match.Value.ToUpperInvariant()
            }
        }
    )
    if ($Ids.Count -ne 1) {
        throw "${Label} file-ID parse mismatch: count=$($Ids.Count)"
    }
    return $Ids[0]
}

function Assert-FileState {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$SHA256,
        [Parameter(Mandatory = $true)][string]$FileId,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "${Label} missing: $Path"
    }
    $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($Hash -cne $SHA256) {
        throw "${Label} SHA256 mismatch: observed=$Hash expected=$SHA256"
    }
    $ObservedId = Get-FileId -Path $Path -Label $Label
    if ($ObservedId -cne $FileId) {
        throw "${Label} file-ID mismatch: observed=$ObservedId expected=$FileId"
    }
}

function Invoke-VBoxRead {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $OldEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $Captured = @(
            & $script:VBox @Arguments 2>&1 |
                ForEach-Object { [string]$_ }
        )
        $ExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $OldEap
    }

    if ($ExitCode -ne 0) {
        throw "${Label} failed exit=$ExitCode`n$($Captured -join "`n")"
    }
    return $Captured
}

function Convert-MachineReadable {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Map = [ordered]@{}
    foreach ($Line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($Line)) {
            continue
        }
        $Match = [regex]::Match($Line, '^([^=]+)=(.*)$')
        if (-not $Match.Success) {
            throw "${Label} non-machine-readable row: $Line"
        }
        $Key = $Match.Groups[1].Value
        $Raw = $Match.Groups[2].Value
        if ($Map.Contains($Key)) {
            throw "${Label} duplicate key: $Key"
        }
        $Value = $Raw
        if ($Raw.Length -ge 2 -and $Raw[0] -eq '"' -and $Raw[$Raw.Length - 1] -eq '"') {
            $Value = $Raw.Substring(1, $Raw.Length - 2).Replace('\"', '"').Replace('\\', '\')
        }
        $Map[$Key] = [string]$Value
    }
    return $Map
}

function Get-RequiredMachineValue {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Info,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not $Info.Contains($Key)) {
        throw "${Label} missing key: $Key"
    }
    return [string]$Info[$Key]
}

function Assert-MachineValue {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Info,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Observed = Get-RequiredMachineValue -Info $Info -Key $Key -Label $Label
    if ($Observed -cne $Expected) {
        throw "${Label} mismatch: key=$Key observed=$Observed expected=$Expected"
    }
}

function ConvertTo-NormalizedUuid {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Normalized = $Value.Trim().Trim('{', '}').ToLowerInvariant()
    $Parsed = [Guid]::Empty
    if (-not [Guid]::TryParse($Normalized, [ref]$Parsed)) {
        throw "${Label} is not a UUID: $Value"
    }
    return $Parsed.ToString('D').ToLowerInvariant()
}

function Get-ColonValue {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Key
    )

    $Matches = @(
        foreach ($Line in $Lines) {
            $Match = [regex]::Match($Line, '^\s*' + [regex]::Escape($Key) + '\s*:\s*(.*?)\s*$')
            if ($Match.Success) {
                $Match.Groups[1].Value
            }
        }
    )
    if ($Matches.Count -ne 1) {
        throw "colon field cardinality mismatch: key=$Key count=$($Matches.Count)"
    }
    return $Matches[0]
}

$Root = (Resolve-Path -LiteralPath $PreparedRoot -ErrorAction Stop).Path
$VerificationReport = (
    Resolve-Path -LiteralPath $PreparedVerificationReportPath -ErrorAction Stop
).Path
$Output = Get-FullPath -Path $OutPath
$script:VBox = (Resolve-Path -LiteralPath $VBoxManagePath -ErrorAction Stop).Path

Assert-PathEquals -Observed $Root -Expected $ExpectedRoot -Label 'prepared r3 root'
Assert-PathEquals -Observed $VerificationReport -Expected $ExpectedVerificationReport -Label 'prepared verification report'
Assert-PathEquals -Observed $Output -Expected $ExpectedOut -Label 'boot authorization report'

if (Test-Path -LiteralPath $Output) {
    throw "boot authorization report already exists: $Output"
}
$OutputParent = Split-Path -Parent $Output
if (-not (Test-Path -LiteralPath $OutputParent -PathType Container)) {
    throw "boot authorization report parent missing: $OutputParent"
}

$VerificationHash = (
    Get-FileHash -LiteralPath $VerificationReport -Algorithm SHA256
).Hash
if ($VerificationHash -cne $ExpectedVerificationHash) {
    throw "prepared verification SHA256 mismatch: observed=$VerificationHash expected=$ExpectedVerificationHash"
}

$MachineRoot = Join-Path $Root 'Machine'
$HomeRoot = Join-Path $Root 'VBoxUserHome'
$CurrentVBox = Join-Path $MachineRoot 'Temple1.10.vbox'
$PreviousVBox = Join-Path $MachineRoot 'Temple1.10.vbox-prev'
$Vdi = Join-Path $MachineRoot 'Temple1.10.vdi'
$Iso = Join-Path $MachineRoot 'TempleOSTS.iso'
$Registry = Join-Path $HomeRoot 'VirtualBox.xml'

foreach ($RequiredDirectory in @($MachineRoot, $HomeRoot)) {
    if (-not (Test-Path -LiteralPath $RequiredDirectory -PathType Container)) {
        throw "required directory missing: $RequiredDirectory"
    }
}
if (-not (Test-Path -LiteralPath $Registry -PathType Leaf)) {
    throw "isolated registry missing: $Registry"
}

Assert-FileState -Path $CurrentVBox -SHA256 $ExpectedCurrentVBoxHash -FileId $ExpectedCurrentVBoxId -Label 'r3 current VBOX before runtime adjudication'
Assert-FileState -Path $PreviousVBox -SHA256 $ExpectedPreviousVBoxHash -FileId $ExpectedPreviousVBoxId -Label 'r3 previous VBOX before runtime adjudication'
Assert-FileState -Path $Vdi -SHA256 $ExpectedVdiHash -FileId $ExpectedVdiId -Label 'r3 VDI before runtime adjudication'
Assert-FileState -Path $Iso -SHA256 $ExpectedIsoHash -FileId $ExpectedIsoId -Label 'r3 ISO before runtime adjudication'
$RegistryHashBefore = (Get-FileHash -LiteralPath $Registry -Algorithm SHA256).Hash

$OriginalVBoxUserHome = [Environment]::GetEnvironmentVariable(
    'VBOX_USER_HOME',
    [EnvironmentVariableTarget]::Process
)
if (-not [string]::IsNullOrEmpty($OriginalVBoxUserHome)) {
    throw "process VBOX_USER_HOME must be unset: $OriginalVBoxUserHome"
}

$Version = $null
$Registered = @()
$Running = @()
$ShowLines = @()
$SnapshotLines = @()
$VdiMediumLines = @()
try {
    [Environment]::SetEnvironmentVariable(
        'VBOX_USER_HOME',
        $HomeRoot,
        [EnvironmentVariableTarget]::Process
    )

    $Version = @(Invoke-VBoxRead -Arguments @('--version') -Label 'isolated VirtualBox version')
    $Registered = @(Invoke-VBoxRead -Arguments @('list', 'vms') -Label 'isolated registered inventory')
    $Running = @(Invoke-VBoxRead -Arguments @('list', 'runningvms') -Label 'isolated running inventory')
    $ShowLines = @(
        Invoke-VBoxRead `
            -Arguments @('showvminfo', $ExpectedMachineUuid, '--machinereadable') `
            -Label 'isolated target showvminfo'
    )
    $SnapshotLines = @(
        Invoke-VBoxRead `
            -Arguments @('snapshot', $ExpectedMachineUuid, 'list', '--machinereadable') `
            -Label 'isolated target snapshot inventory'
    )
    $VdiMediumLines = @(
        Invoke-VBoxRead `
            -Arguments @('showmediuminfo', 'disk', $Vdi) `
            -Label 'isolated VDI medium info'
    )
}
finally {
    [Environment]::SetEnvironmentVariable(
        'VBOX_USER_HOME',
        $OriginalVBoxUserHome,
        [EnvironmentVariableTarget]::Process
    )
}

if ($Version.Count -ne 1 -or $Version[0] -cne $ExpectedVBoxVersion) {
    throw "isolated VirtualBox version mismatch: $($Version -join '|')"
}

$RegisteredRows = @($Registered | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($RegisteredRows.Count -ne 1) {
    throw "isolated registered VM count mismatch: $($RegisteredRows.Count)"
}
$ExpectedRegistered = '"' + $ExpectedMachineName + '" {' + $ExpectedMachineUuid + '}'
if ($RegisteredRows[0] -cne $ExpectedRegistered) {
    throw "isolated registered VM row mismatch: $($RegisteredRows[0])"
}

$RunningRows = @($Running | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($RunningRows.Count -ne 0) {
    throw "isolated running VM count is not zero: $($RunningRows.Count)"
}

$Info = Convert-MachineReadable -Lines $ShowLines -Label 'isolated target showvminfo'
Assert-MachineValue -Info $Info -Key 'name' -Expected $ExpectedMachineName -Label 'isolated target'
$ObservedUuid = ConvertTo-NormalizedUuid `
    -Value (Get-RequiredMachineValue -Info $Info -Key 'UUID' -Label 'isolated target') `
    -Label 'isolated target UUID'
if ($ObservedUuid -cne $ExpectedMachineUuid) {
    throw "isolated target UUID mismatch: $ObservedUuid"
}
Assert-MachineValue -Info $Info -Key 'VMState' -Expected 'poweroff' -Label 'isolated target'
Assert-MachineValue -Info $Info -Key 'CfgFile' -Expected $CurrentVBox -Label 'isolated target'
Assert-MachineValue -Info $Info -Key 'IDE-1-0' -Expected $Vdi -Label 'isolated target'
Assert-MachineValue -Info $Info -Key 'boot1' -Expected 'disk' -Label 'isolated target'
Assert-MachineValue -Info $Info -Key 'boot2' -Expected 'none' -Label 'isolated target'
Assert-MachineValue -Info $Info -Key 'boot3' -Expected 'none' -Label 'isolated target'
Assert-MachineValue -Info $Info -Key 'boot4' -Expected 'none' -Label 'isolated target'
Assert-MachineValue -Info $Info -Key 'clipboard' -Expected 'disabled' -Label 'isolated target'
Assert-MachineValue -Info $Info -Key 'draganddrop' -Expected 'disabled' -Label 'isolated target'
Assert-MachineValue -Info $Info -Key 'graphicscontroller' -Expected 'vboxvga' -Label 'isolated target'
Assert-MachineValue -Info $Info -Key 'vram' -Expected '9' -Label 'isolated target'

$NicKeys = @($Info.Keys | Where-Object { $_ -match '^nic[1-8]$' })
if ($NicKeys.Count -le 0) {
    throw 'isolated target contains no NIC fields'
}
foreach ($NicKey in $NicKeys) {
    Assert-MachineValue -Info $Info -Key $NicKey -Expected 'none' -Label 'isolated target'
}

$IsoSlotValue = if ($Info.Contains('IDE-0-1')) {
    [string]$Info['IDE-0-1']
}
else {
    '<missing>'
}
if ($IsoSlotValue -cne 'none' -and $IsoSlotValue -cne '<missing>') {
    throw "isolated target ISO slot remains attached: $IsoSlotValue"
}

$SnapshotRows = @(
    $SnapshotLines | Where-Object {
        $_ -match '^Snapshot(Name|UUID|Node)'
    }
)
if ($SnapshotRows.Count -ne 0) {
    throw "isolated target snapshot rows are not zero: $($SnapshotRows.Count)"
}

$ObservedVdiUuid = ConvertTo-NormalizedUuid `
    -Value (Get-ColonValue -Lines $VdiMediumLines -Key 'UUID') `
    -Label 'isolated VDI UUID'
if ($ObservedVdiUuid -cne $ExpectedVdiUuid) {
    throw "isolated VDI UUID mismatch: $ObservedVdiUuid"
}

Assert-FileState -Path $CurrentVBox -SHA256 $ExpectedCurrentVBoxHash -FileId $ExpectedCurrentVBoxId -Label 'r3 current VBOX after runtime adjudication'
Assert-FileState -Path $PreviousVBox -SHA256 $ExpectedPreviousVBoxHash -FileId $ExpectedPreviousVBoxId -Label 'r3 previous VBOX after runtime adjudication'
Assert-FileState -Path $Vdi -SHA256 $ExpectedVdiHash -FileId $ExpectedVdiId -Label 'r3 VDI after runtime adjudication'
Assert-FileState -Path $Iso -SHA256 $ExpectedIsoHash -FileId $ExpectedIsoId -Label 'r3 ISO after runtime adjudication'
$RegistryHashAfter = (Get-FileHash -LiteralPath $Registry -Algorithm SHA256).Hash
if ($RegistryHashAfter -cne $RegistryHashBefore) {
    throw "isolated VirtualBox.xml changed during read-only adjudication: before=$RegistryHashBefore after=$RegistryHashAfter"
}

$Lines = [System.Collections.Generic.List[string]]::new()
$Lines.Add('DBYTE-HOLYC-OPT')
$Lines.Add('TEMPLEOSTS 1.10 VDI-ONLY BOOT ATTEMPT R3 BOOT AUTHORIZATION ADJUDICATION')
$Lines.Add('')
$Lines.Add("prepared_verification_report_sha256`t$VerificationHash")
$Lines.Add("prepared_root`t$Root")
$Lines.Add("virtualbox_version`t$($Version[0])")
$Lines.Add("machine_name`t$ExpectedMachineName")
$Lines.Add("machine_uuid`t$ObservedUuid")
$Lines.Add("machine_state`tpoweroff")
$Lines.Add("cfg_file`t$CurrentVBox")
$Lines.Add("vdi_attachment`t$Vdi")
$Lines.Add("vdi_uuid`t$ObservedVdiUuid")
$Lines.Add("iso_slot_value`t$IsoSlotValue")
$Lines.Add("boot1`tdisk")
$Lines.Add("boot2`tnone")
$Lines.Add("boot3`tnone")
$Lines.Add("boot4`tnone")
$Lines.Add("network_disabled`tTrue")
$Lines.Add("clipboard_disabled`tTrue")
$Lines.Add("drag_and_drop_disabled`tTrue")
$Lines.Add("graphicscontroller`tvboxvga")
$Lines.Add("vram_mb`t9")
$Lines.Add("snapshot_rows`t$($SnapshotRows.Count)")
$Lines.Add("registered_vm_rows`t$($RegisteredRows.Count)")
$Lines.Add("running_vm_rows`t$($RunningRows.Count)")
$Lines.Add("registry_sha256_before`t$RegistryHashBefore")
$Lines.Add("registry_sha256_after`t$RegistryHashAfter")
$Lines.Add('')
$Lines.Add("VBOXMANAGE`tREAD-ONLY-ONLY")
$Lines.Add("VIRTUALBOX MUTATION`tNOT-EXECUTED")
$Lines.Add("VM START`tNOT-EXECUTED")
$Lines.Add("BOOT AUTHORIZATION`tREADY-FOR-SEPARATE-EXPLICIT-DECISION")
$Lines.Add('')
$Lines.Add('THIS ADJUDICATION DOES NOT START THE VM.')
$Lines.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')

[System.IO.File]::WriteAllText(
    $Output,
    (($Lines.ToArray() -join "`n") + "`n"),
    [System.Text.UTF8Encoding]::new($false)
)
$OutputHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

Write-Host "PREPARED R3 ROOT:      $Root"
Write-Host "BOUND VERIFICATION:    $VerificationHash"
Write-Host "VIRTUALBOX VERSION:    $($Version[0])"
Write-Host "REGISTERED VMS:        $($RegisteredRows.Count)"
Write-Host "RUNNING VMS:           $($RunningRows.Count)"
Write-Host "MACHINE UUID:          $ObservedUuid"
Write-Host 'MACHINE STATE:         poweroff'
Write-Host "CFG FILE:              $CurrentVBox"
Write-Host "VDI ATTACHMENT:        $Vdi"
Write-Host "VDI UUID:              $ObservedVdiUuid"
Write-Host "ISO SLOT:              $IsoSlotValue"
Write-Host 'BOOT1:                 disk'
Write-Host 'BOOT2:                 none'
Write-Host 'BOOT3:                 none'
Write-Host 'BOOT4:                 none'
Write-Host 'NETWORK DISABLED:      True'
Write-Host 'CLIPBOARD DISABLED:    True'
Write-Host 'DRAGDROP DISABLED:     True'
Write-Host 'GRAPHICS:              vboxvga / 9 MB'
Write-Host "SNAPSHOT ROWS:         $($SnapshotRows.Count)"
Write-Host "REGISTRY SHA BEFORE:   $RegistryHashBefore"
Write-Host "REGISTRY SHA AFTER:    $RegistryHashAfter"
Write-Host "REPORT:                $Output"
Write-Host "REPORT SHA256:         $OutputHash"
Write-Host 'VBOXMANAGE:            READ-ONLY-ONLY'
Write-Host 'VIRTUALBOX MUTATION:   NOT-EXECUTED'
Write-Host 'VM START:              NOT-EXECUTED'
Write-Host 'BOOT AUTHORIZATION:    READY-FOR-SEPARATE-EXPLICIT-DECISION'
Write-Host 'VERDICT:               R3 BOOT AUTHORIZATION ADJUDICATION COMPLETE'
