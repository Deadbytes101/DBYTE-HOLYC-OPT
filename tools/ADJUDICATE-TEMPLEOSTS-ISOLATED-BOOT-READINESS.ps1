[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VBoxManagePath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RehearsalVerificationReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RehearsalRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedResourceCommit =
    '37b0457e8735ab8cc34a23f2717fcfb808e6a7a8'
$ExpectedVerificationReportHash =
    'F16F263F1A9217022F24FC318DC0CB4A9BEAFA295723AFB889C043EF428E51E8'
$ExpectedRehearsalManifestHash =
    'AC2609C9C6EFC87316835BB6A4174AF5C28FEEE8DCEBD37E0E9D3DADB14D383F'
$ExpectedTargetName = 'Temple1.10'
$ExpectedTargetUuid = '9c98691e-27cd-4487-a306-587969c2c78c'
$ExpectedVdiUuid = '55c1f29d-a681-402e-b90d-bfbb6b09f207'
$ExpectedIsoUuid = 'ab97b3a5-1331-494d-a917-e85b6e728c45'
$ExpectedVBoxVersion = '7.0.12r159484'
$ExpectedRehearsalRoot =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-REHEARSAL\templeosts-1.10-isolated-r1'
$ExpectedLiveVBoxPath = 'D:\VirtualBox VMs\Temple1.10\Temple1.10.vbox'
$ExpectedLiveVdiPath = 'D:\VirtualBox VMs\Temple1.10\Temple1.10.vdi'
$ExpectedLiveIsoPath = 'D:\TempleOSTS.iso'
$ExpectedLiveVBoxHash =
    'E537469A1B1A88DE13D18704B5D6299F3AF202DA518FB266F045485A8FC4F1E6'
$ExpectedDisposableVBoxHash =
    '69224A832694CA0C657CA2135ED370F6B7E667B84F93C08D921AED4A6D21F39B'
$ExpectedVdiBytes = 2097152L
$ExpectedVdiHash =
    '90D453A94F075760A11E0772862E60C4B031ED874F28AA396EAE638F7EB8B31B'
$ExpectedIsoBytes = 30558208L
$ExpectedIsoHash =
    'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$ExpectedDisposableVBoxFileId = '0X0000000000000000000100000006010A'
$ExpectedDisposableVdiFileId = '0X0000000000000000000100000006010B'
$ExpectedDisposableIsoFileId = '0X0000000000000000000100000006010C'

function Get-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path)
}

function Get-Prefix {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FullPath -Path $Path).TrimEnd('\', '/') +
        [System.IO.Path]::DirectorySeparatorChar
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
        throw "$Label path mismatch: observed=$Observed expected=$Expected"
    }
}

function Assert-OutsideRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Full = Get-FullPath -Path $Path
    $RootFull = Get-FullPath -Path $Root
    if (
        [string]::Equals(
            $Full,
            $RootFull,
            [System.StringComparison]::OrdinalIgnoreCase
        ) -or
        $Full.StartsWith(
            (Get-Prefix -Path $Root),
            [System.StringComparison]::OrdinalIgnoreCase
        )
    ) {
        throw "$Label is inside forbidden root: path=$Full root=$RootFull"
    }
}

function Assert-ExactHashFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$SHA256,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label missing: $Path"
    }
    $Item = Get-Item -LiteralPath $Path
    $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($Hash -cne $SHA256) {
        throw "$Label SHA256 mismatch: observed=$Hash expected=$SHA256"
    }
    return [pscustomobject]@{
        Path = $Item.FullName
        Bytes = $Item.Length
        SHA256 = $Hash
    }
}

function Assert-ExactFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][long]$Bytes,
        [Parameter(Mandatory = $true)][string]$SHA256,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Identity = Assert-ExactHashFile -Path $Path -SHA256 $SHA256 -Label $Label
    if ($Identity.Bytes -ne $Bytes) {
        throw "$Label byte-count mismatch: observed=$($Identity.Bytes) expected=$Bytes"
    }
    return $Identity
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
        throw "$Label file-id query failed`n$($Captured -join "`n")"
    }
    $Ids = @(
        foreach ($Line in $Captured) {
            foreach ($Match in [regex]::Matches($Line, '0x[0-9A-Fa-f]+')) {
                $Match.Value.ToUpperInvariant()
            }
        }
    )
    if ($Ids.Count -ne 1) {
        throw "$Label file-id parse mismatch: count=$($Ids.Count)"
    }
    return $Ids[0]
}

function Assert-FileId {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Observed = Get-FileId -Path $Path -Label $Label
    if ($Observed -cne $Expected) {
        throw "$Label file ID mismatch: observed=$Observed expected=$Expected"
    }
    return $Observed
}

function Invoke-GitRead {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Captured = @(
        & git -C $script:Resource @Arguments 2>&1 |
            ForEach-Object { [string]$_ }
    )
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed`n$($Captured -join "`n")"
    }
    return $Captured
}

function Invoke-VBoxReadOnly {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Captured = @(
        & $script:VBox @Arguments 2>&1 |
            ForEach-Object { [string]$_ }
    )
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed`n$($Captured -join "`n")"
    }
    return $Captured
}

function Invoke-VBoxSnapshotInventory {
    param(
        [Parameter(Mandatory = $true)][string]$Uuid,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Captured = @(
        & $script:VBox 'snapshot' $Uuid 'list' '--machinereadable' 2>&1 |
            ForEach-Object { [string]$_ }
    )
    $ExitCode = $LASTEXITCODE
    if ($ExitCode -eq 0) {
        return $Captured
    }
    if (
        $Captured.Count -eq 1 -and
        $Captured[0].Trim() -ceq 'This machine does not have any snapshots'
    ) {
        return @()
    }
    throw "$Label failed`n$($Captured -join "`n")"
}

function Wait-VBoxServiceExit {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [int]$TimeoutSeconds = 30
    )

    $Deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $Deadline) {
        $Processes = @(Get-Process -Name 'VBoxSVC' -ErrorAction SilentlyContinue)
        if ($Processes.Count -eq 0) {
            return
        }
        Start-Sleep -Milliseconds 250
    }
    $Remaining = @(Get-Process -Name 'VBoxSVC' -ErrorAction SilentlyContinue)
    throw "${Label}: VBoxSVC did not exit; PIDs=$($Remaining.Id -join ',')"
}

function ConvertFrom-VBoxMachineReadable {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    $Result = @{}
    foreach ($Line in $Lines) {
        $Equals = $Line.IndexOf('=')
        if ($Equals -le 0) {
            continue
        }
        $Key = $Line.Substring(0, $Equals)
        $Value = $Line.Substring($Equals + 1)
        if (
            $Key.Length -ge 2 -and
            $Key[0] -eq '"' -and
            $Key[$Key.Length - 1] -eq '"'
        ) {
            $Key = $Key.Substring(1, $Key.Length - 2)
            $Key = $Key.Replace('\"', '"').Replace('\\', '\')
        }
        if (
            $Value.Length -ge 2 -and
            $Value[0] -eq '"' -and
            $Value[$Value.Length - 1] -eq '"'
        ) {
            $Value = $Value.Substring(1, $Value.Length - 2)
            $Value = $Value.Replace('\"', '"').Replace('\\', '\')
        }
        if ([string]::IsNullOrWhiteSpace($Key)) {
            throw 'machine-readable key normalized to empty text'
        }
        if ($Result.ContainsKey($Key)) {
            throw "duplicate machine-readable key after normalization: $Key"
        }
        $Result[$Key] = $Value
    }
    return $Result
}

function Get-RequiredMachineValue {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Info,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not $Info.ContainsKey($Key)) {
        throw "$Label field missing: $Key"
    }
    return [string]$Info[$Key]
}

function Assert-MachineValue {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Info,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Observed = Get-RequiredMachineValue -Info $Info -Key $Key -Label $Label
    if (-not [string]::Equals(
        $Observed,
        $Expected,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "$Label field mismatch: $Key=$Observed expected=$Expected"
    }
}

function Assert-TargetState {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Registered,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Running,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Show,
        [Parameter(Mandatory = $true)][string]$ExpectedConfig,
        [Parameter(Mandatory = $true)][string]$ExpectedVdi,
        [Parameter(Mandatory = $true)][string]$ExpectedIso,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $NonEmptyRegistered = @($Registered | Where-Object { $_ -cne '' })
    $NonEmptyRunning = @($Running | Where-Object { $_ -cne '' })
    $WhitespaceRegistered = @(
        $Registered | Where-Object {
            $_ -cne '' -and [string]::IsNullOrWhiteSpace($_)
        }
    )
    $WhitespaceRunning = @(
        $Running | Where-Object {
            $_ -cne '' -and [string]::IsNullOrWhiteSpace($_)
        }
    )
    if ($WhitespaceRegistered.Count -ne 0 -or $WhitespaceRunning.Count -ne 0) {
        throw "$Label inventory contains nonempty whitespace-only rows"
    }

    $TargetPattern = (
        '^"' + [regex]::Escape($ExpectedTargetName) + '" \{' +
        [regex]::Escape($ExpectedTargetUuid) + '\}$'
    )
    if (@($NonEmptyRegistered | Where-Object { $_ -match $TargetPattern }).Count -ne 1) {
        throw "$Label registered target identity mismatch"
    }
    if ($NonEmptyRegistered.Count -ne 1) {
        throw "$Label registry contains unexpected VM rows: $($NonEmptyRegistered.Count)"
    }
    if ($NonEmptyRunning.Count -ne 0) {
        throw "$Label contains running VM rows: $($NonEmptyRunning.Count)"
    }

    $Info = ConvertFrom-VBoxMachineReadable -Lines $Show
    Assert-MachineValue -Info $Info -Key 'name' -Expected $ExpectedTargetName -Label $Label
    Assert-MachineValue -Info $Info -Key 'UUID' -Expected $ExpectedTargetUuid -Label $Label
    Assert-MachineValue -Info $Info -Key 'VMState' -Expected 'poweroff' -Label $Label
    Assert-MachineValue -Info $Info -Key 'CfgFile' -Expected $ExpectedConfig -Label $Label
    Assert-MachineValue -Info $Info -Key 'IDE-1-0' -Expected $ExpectedVdi -Label $Label
    Assert-MachineValue -Info $Info -Key 'IDE-0-1' -Expected $ExpectedIso -Label $Label

    $SharedKeys = @(
        $Info.Keys | Where-Object {
            $_ -like 'SharedFolderNameMachineMapping*' -or
            $_ -like 'SharedFolderPathMachineMapping*'
        }
    )
    if ($SharedKeys.Count -ne 0) {
        throw "$Label shared-folder keys are not zero: $($SharedKeys.Count)"
    }
    return $Info
}

function Get-UniqueTabValue {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Key
    )

    $Prefix = "$Key`t"
    $Found = @($Lines | Where-Object { $_.StartsWith($Prefix) })
    if ($Found.Count -ne 1) {
        throw "report field count mismatch: $Key count=$($Found.Count)"
    }
    return $Found[0].Substring($Prefix.Length)
}

function Assert-FieldEquals {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Expected
    )

    $Observed = Get-UniqueTabValue -Lines $Lines -Key $Key
    if ($Observed -cne $Expected) {
        throw "field mismatch: $Key observed=$Observed expected=$Expected"
    }
}

function Write-Utf8Lines {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    [System.IO.File]::WriteAllText(
        $Path,
        (($Lines -join "`n") + "`n"),
        [System.Text.UTF8Encoding]::new($false)
    )
}

$script:Resource = (
    Resolve-Path -LiteralPath $ResourceRoot -ErrorAction Stop
).Path
$script:VBox = (
    Resolve-Path -LiteralPath $VBoxManagePath -ErrorAction Stop
).Path
$VerificationReport = (
    Resolve-Path -LiteralPath $RehearsalVerificationReportPath -ErrorAction Stop
).Path
$Rehearsal = (
    Resolve-Path -LiteralPath $RehearsalRoot -ErrorAction Stop
).Path
$Output = Get-FullPath -Path $OutPath
$LiveVmRoot = Split-Path -Parent $ExpectedLiveVBoxPath

if (-not (Test-Path -LiteralPath $script:Resource -PathType Container)) {
    throw "resource root is not a directory: $script:Resource"
}
if (-not (Test-Path -LiteralPath $script:VBox -PathType Leaf)) {
    throw "VBoxManage is not a file: $script:VBox"
}
if (-not (Test-Path -LiteralPath $Rehearsal -PathType Container)) {
    throw "rehearsal root is not a directory: $Rehearsal"
}
Assert-PathEquals -Observed $Rehearsal -Expected $ExpectedRehearsalRoot -Label 'rehearsal root'
foreach ($ForbiddenRoot in @($script:Resource, $Rehearsal, $LiveVmRoot)) {
    Assert-OutsideRoot -Path $Output -Root $ForbiddenRoot -Label 'boot-readiness report'
}
if (Test-Path -LiteralPath $Output) {
    throw "boot-readiness report already exists: $Output"
}

$OriginalVBoxUserHome = [Environment]::GetEnvironmentVariable(
    'VBOX_USER_HOME',
    [EnvironmentVariableTarget]::Process
)
if (-not [string]::IsNullOrEmpty($OriginalVBoxUserHome)) {
    throw "process VBOX_USER_HOME must be unset: $OriginalVBoxUserHome"
}

$VerificationIdentity = Assert-ExactHashFile `
    -Path $VerificationReport `
    -SHA256 $ExpectedVerificationReportHash `
    -Label 'isolated rehearsal verification report'
$VerificationLines = [System.IO.File]::ReadAllLines($VerificationIdentity.Path)
foreach ($Field in @(
    @('rehearsal_manifest_sha256', $ExpectedRehearsalManifestHash),
    @('rehearsal_root', $ExpectedRehearsalRoot),
    @('machine_uuid', $ExpectedTargetUuid),
    @('machine_state', 'poweroff'),
    @('running_rows', '0'),
    @('snapshot_rows', '0'),
    @('shared_folder_rows', '0'),
    @('disposable_vbox_sha256', $ExpectedDisposableVBoxHash),
    @('disposable_vbox_file_id', $ExpectedDisposableVBoxFileId),
    @('disposable_vdi_sha256', $ExpectedVdiHash),
    @('disposable_vdi_file_id', $ExpectedDisposableVdiFileId),
    @('disposable_vdi_uuid', $ExpectedVdiUuid),
    @('disposable_iso_sha256', $ExpectedIsoHash),
    @('disposable_iso_file_id', $ExpectedDisposableIsoFileId),
    @('disposable_iso_uuid', $ExpectedIsoUuid),
    @('ISOLATED REHEARSAL', 'VERIFIED'),
    @('POWERED-OFF REHEARSAL ENVIRONMENT', 'SEALED'),
    @('VM START', 'NOT-AUTHORIZED'),
    @('RESTORE BOOT', 'NOT-OBSERVED'),
    @('POWERED-OFF RECOVERY POINT', 'NOT-SEALED'),
    @('BUILD EXECUTION', 'NOT-AUTHORIZED')
)) {
    Assert-FieldEquals -Lines $VerificationLines -Key $Field[0] -Expected $Field[1]
}

$Head = @(Invoke-GitRead -Arguments @('rev-parse', 'HEAD') -Label 'resource HEAD')
if ($Head.Count -ne 1 -or $Head[0] -cne $ExpectedResourceCommit) {
    throw "resource HEAD mismatch: $($Head -join ' | ')"
}
[void](Invoke-GitRead -Arguments @('diff', '--check') -Label 'resource diff check')
$Worktree = @(Invoke-GitRead -Arguments @('diff', '--name-only') -Label 'resource worktree diff')
$Index = @(Invoke-GitRead -Arguments @('diff', '--cached', '--name-only') -Label 'resource index diff')
if ($Worktree.Count -ne 0 -or $Index.Count -ne 0) {
    throw 'resource tracked tree is not clean'
}

$Manifest = Assert-ExactHashFile `
    -Path (Join-Path $Rehearsal 'ISOLATED-REHEARSAL-MANIFEST.txt') `
    -SHA256 $ExpectedRehearsalManifestHash `
    -Label 'rehearsal manifest'
$MachineRoot = Join-Path $Rehearsal 'Machine'
$IsolatedHome = Join-Path $Rehearsal 'VBoxUserHome'
$DisposableVBox = Join-Path $MachineRoot 'Temple1.10.vbox'
$DisposableVdi = Join-Path $MachineRoot 'Temple1.10.vdi'
$DisposableIso = Join-Path $MachineRoot 'TempleOSTS.iso'
if (-not (Test-Path -LiteralPath $IsolatedHome -PathType Container)) {
    throw "isolated VBOX_USER_HOME missing: $IsolatedHome"
}
$VBoxBefore = Assert-ExactHashFile `
    -Path $DisposableVBox `
    -SHA256 $ExpectedDisposableVBoxHash `
    -Label 'disposable VBOX before readiness query'
$VdiBefore = Assert-ExactFile `
    -Path $DisposableVdi `
    -Bytes $ExpectedVdiBytes `
    -SHA256 $ExpectedVdiHash `
    -Label 'disposable VDI before readiness query'
$IsoBefore = Assert-ExactFile `
    -Path $DisposableIso `
    -Bytes $ExpectedIsoBytes `
    -SHA256 $ExpectedIsoHash `
    -Label 'disposable ISO before readiness query'
$VBoxFileId = Assert-FileId `
    -Path $VBoxBefore.Path `
    -Expected $ExpectedDisposableVBoxFileId `
    -Label 'disposable VBOX before readiness query'
$VdiFileId = Assert-FileId `
    -Path $VdiBefore.Path `
    -Expected $ExpectedDisposableVdiFileId `
    -Label 'disposable VDI before readiness query'
$IsoFileId = Assert-FileId `
    -Path $IsoBefore.Path `
    -Expected $ExpectedDisposableIsoFileId `
    -Label 'disposable ISO before readiness query'

Wait-VBoxServiceExit -Label 'default registry isolation before readiness query'
$DefaultVersionBefore = @(Invoke-VBoxReadOnly -Arguments @('--version') -Label 'default VirtualBox version')
if ($DefaultVersionBefore.Count -ne 1 -or $DefaultVersionBefore[0] -cne $ExpectedVBoxVersion) {
    throw "VirtualBox version mismatch: $($DefaultVersionBefore -join ' | ')"
}
$DefaultRegisteredBefore = @(Invoke-VBoxReadOnly -Arguments @('list', 'vms') -Label 'default registered inventory')
$DefaultRunningBefore = @(Invoke-VBoxReadOnly -Arguments @('list', 'runningvms') -Label 'default running inventory')
$DefaultShowBefore = @(
    Invoke-VBoxReadOnly `
        -Arguments @('showvminfo', $ExpectedTargetUuid, '--machinereadable') `
        -Label 'default target showvminfo'
)
[void](Assert-TargetState `
    -Registered $DefaultRegisteredBefore `
    -Running $DefaultRunningBefore `
    -Show $DefaultShowBefore `
    -ExpectedConfig $ExpectedLiveVBoxPath `
    -ExpectedVdi $ExpectedLiveVdiPath `
    -ExpectedIso $ExpectedLiveIsoPath `
    -Label 'default registry before readiness query')
$DefaultSnapshotsBefore = @(
    Invoke-VBoxSnapshotInventory `
        -Uuid $ExpectedTargetUuid `
        -Label 'default target snapshot inventory'
)
if (@($DefaultSnapshotsBefore | Where-Object { $_ -match '^Snapshot(Name|UUID|Node)' }).Count -ne 0) {
    throw 'default target snapshot rows are not zero'
}
[void](Assert-ExactHashFile -Path $ExpectedLiveVBoxPath -SHA256 $ExpectedLiveVBoxHash -Label 'live VBOX before readiness query')
[void](Assert-ExactFile -Path $ExpectedLiveVdiPath -Bytes $ExpectedVdiBytes -SHA256 $ExpectedVdiHash -Label 'live VDI before readiness query')
[void](Assert-ExactFile -Path $ExpectedLiveIsoPath -Bytes $ExpectedIsoBytes -SHA256 $ExpectedIsoHash -Label 'live ISO before readiness query')
Wait-VBoxServiceExit -Label 'default registry shutdown before isolated readiness query'

[Environment]::SetEnvironmentVariable(
    'VBOX_USER_HOME',
    $IsolatedHome,
    [EnvironmentVariableTarget]::Process
)
try {
    $IsolatedVersion = @(Invoke-VBoxReadOnly -Arguments @('--version') -Label 'isolated VirtualBox version')
    if ($IsolatedVersion.Count -ne 1 -or $IsolatedVersion[0] -cne $ExpectedVBoxVersion) {
        throw "isolated VirtualBox version mismatch: $($IsolatedVersion -join ' | ')"
    }
    $IsolatedRegistered = @(Invoke-VBoxReadOnly -Arguments @('list', 'vms') -Label 'isolated registered inventory')
    $IsolatedRunning = @(Invoke-VBoxReadOnly -Arguments @('list', 'runningvms') -Label 'isolated running inventory')
    $IsolatedShow = @(
        Invoke-VBoxReadOnly `
            -Arguments @('showvminfo', $ExpectedTargetUuid, '--machinereadable') `
            -Label 'isolated target showvminfo'
    )
    $IsolatedInfo = Assert-TargetState `
        -Registered $IsolatedRegistered `
        -Running $IsolatedRunning `
        -Show $IsolatedShow `
        -ExpectedConfig $DisposableVBox `
        -ExpectedVdi $DisposableVdi `
        -ExpectedIso $DisposableIso `
        -Label 'isolated registry readiness query'
    $IsolatedSnapshots = @(
        Invoke-VBoxSnapshotInventory `
            -Uuid $ExpectedTargetUuid `
            -Label 'isolated target snapshot inventory'
    )
    if (@($IsolatedSnapshots | Where-Object { $_ -match '^Snapshot(Name|UUID|Node)' }).Count -ne 0) {
        throw 'isolated target snapshot rows are not zero'
    }

    $Boot1 = Get-RequiredMachineValue -Info $IsolatedInfo -Key 'boot1' -Label 'isolated target'
    $Boot2 = Get-RequiredMachineValue -Info $IsolatedInfo -Key 'boot2' -Label 'isolated target'
    $Boot3 = Get-RequiredMachineValue -Info $IsolatedInfo -Key 'boot3' -Label 'isolated target'
    $Boot4 = Get-RequiredMachineValue -Info $IsolatedInfo -Key 'boot4' -Label 'isolated target'
    $GraphicsController = Get-RequiredMachineValue -Info $IsolatedInfo -Key 'graphicscontroller' -Label 'isolated target'
    $Vram = Get-RequiredMachineValue -Info $IsolatedInfo -Key 'vram' -Label 'isolated target'
    $Clipboard = Get-RequiredMachineValue -Info $IsolatedInfo -Key 'clipboard' -Label 'isolated target'
    $DragAndDrop = Get-RequiredMachineValue -Info $IsolatedInfo -Key 'draganddrop' -Label 'isolated target'

    $NicRows = [System.Collections.Generic.List[object]]::new()
    for ($Index = 1; $Index -le 8; $Index++) {
        $NicKey = "nic$Index"
        if (-not $IsolatedInfo.ContainsKey($NicKey)) {
            continue
        }
        $Mode = [string]$IsolatedInfo[$NicKey]
        $CableKey = "cableconnected$Index"
        $Cable = if ($IsolatedInfo.ContainsKey($CableKey)) {
            [string]$IsolatedInfo[$CableKey]
        }
        else {
            '<missing>'
        }
        $NicRows.Add([pscustomobject]@{
            Index = $Index
            Mode = $Mode
            Cable = $Cable
        })
    }
    if ($NicRows.Count -le 0) {
        throw 'isolated target has no NIC fields in machine-readable output'
    }

    $VdiFirstBoot = @('disk', 'harddisk') -contains $Boot1.ToLowerInvariant()
    $IsoAttached = -not [string]::IsNullOrWhiteSpace(
        Get-RequiredMachineValue -Info $IsolatedInfo -Key 'IDE-0-1' -Label 'isolated target'
    )
    $NetworkDisabled = @(
        $NicRows | Where-Object { $_.Mode.ToLowerInvariant() -ne 'none' }
    ).Count -eq 0
    $ClipboardDisabled = $Clipboard.ToLowerInvariant() -eq 'disabled'
    $DragAndDropDisabled = $DragAndDrop.ToLowerInvariant() -eq 'disabled'
}
finally {
    try {
        Wait-VBoxServiceExit -Label 'isolated registry shutdown after readiness query'
    }
    finally {
        [Environment]::SetEnvironmentVariable(
            'VBOX_USER_HOME',
            $OriginalVBoxUserHome,
            [EnvironmentVariableTarget]::Process
        )
    }
}

$DefaultRegisteredAfter = @(Invoke-VBoxReadOnly -Arguments @('list', 'vms') -Label 'default registered inventory after readiness query')
$DefaultRunningAfter = @(Invoke-VBoxReadOnly -Arguments @('list', 'runningvms') -Label 'default running inventory after readiness query')
$DefaultShowAfter = @(
    Invoke-VBoxReadOnly `
        -Arguments @('showvminfo', $ExpectedTargetUuid, '--machinereadable') `
        -Label 'default target showvminfo after readiness query'
)
[void](Assert-TargetState `
    -Registered $DefaultRegisteredAfter `
    -Running $DefaultRunningAfter `
    -Show $DefaultShowAfter `
    -ExpectedConfig $ExpectedLiveVBoxPath `
    -ExpectedVdi $ExpectedLiveVdiPath `
    -ExpectedIso $ExpectedLiveIsoPath `
    -Label 'default registry after readiness query')
$DefaultSnapshotsAfter = @(
    Invoke-VBoxSnapshotInventory `
        -Uuid $ExpectedTargetUuid `
        -Label 'default target snapshot inventory after readiness query'
)
if (@($DefaultSnapshotsAfter | Where-Object { $_ -match '^Snapshot(Name|UUID|Node)' }).Count -ne 0) {
    throw 'default target snapshot rows changed during readiness query'
}
[void](Assert-ExactHashFile -Path $ExpectedLiveVBoxPath -SHA256 $ExpectedLiveVBoxHash -Label 'live VBOX after readiness query')
[void](Assert-ExactFile -Path $ExpectedLiveVdiPath -Bytes $ExpectedVdiBytes -SHA256 $ExpectedVdiHash -Label 'live VDI after readiness query')
[void](Assert-ExactFile -Path $ExpectedLiveIsoPath -Bytes $ExpectedIsoBytes -SHA256 $ExpectedIsoHash -Label 'live ISO after readiness query')
Wait-VBoxServiceExit -Label 'default registry shutdown after readiness query'

[void](Assert-ExactHashFile -Path $VerificationReport -SHA256 $ExpectedVerificationReportHash -Label 'verification report after readiness query')
[void](Assert-ExactHashFile -Path $Manifest.Path -SHA256 $ExpectedRehearsalManifestHash -Label 'rehearsal manifest after readiness query')
[void](Assert-ExactHashFile -Path $DisposableVBox -SHA256 $ExpectedDisposableVBoxHash -Label 'disposable VBOX after readiness query')
[void](Assert-ExactFile -Path $DisposableVdi -Bytes $ExpectedVdiBytes -SHA256 $ExpectedVdiHash -Label 'disposable VDI after readiness query')
[void](Assert-ExactFile -Path $DisposableIso -Bytes $ExpectedIsoBytes -SHA256 $ExpectedIsoHash -Label 'disposable ISO after readiness query')
[void](Assert-FileId -Path $DisposableVBox -Expected $ExpectedDisposableVBoxFileId -Label 'disposable VBOX after readiness query')
[void](Assert-FileId -Path $DisposableVdi -Expected $ExpectedDisposableVdiFileId -Label 'disposable VDI after readiness query')
[void](Assert-FileId -Path $DisposableIso -Expected $ExpectedDisposableIsoFileId -Label 'disposable ISO after readiness query')

$CorrectionRows = [System.Collections.Generic.List[string]]::new()
$CorrectionRows.Add('COPY-SEALED-REHEARSAL-MACHINE-FILES')
if (-not $VdiFirstBoot) {
    $CorrectionRows.Add('SET-BOOT1-DISK-ON-BOOT-COPY')
}
if ($IsoAttached) {
    $CorrectionRows.Add('DETACH-ISO-FROM-BOOT-COPY')
}
if (-not $NetworkDisabled) {
    $CorrectionRows.Add('DISABLE-ALL-NICS-ON-BOOT-COPY')
}
if (-not $ClipboardDisabled) {
    $CorrectionRows.Add('DISABLE-CLIPBOARD-ON-BOOT-COPY')
}
if (-not $DragAndDropDisabled) {
    $CorrectionRows.Add('DISABLE-DRAG-AND-DROP-ON-BOOT-COPY')
}
$CorrectionRows.Add('REGISTER-COPY-IN-NEW-EMPTY-VBOX_USER_HOME')
$CorrectionRows.Add('CAPTURE-BOUNDED-SCREENSHOTS')
$CorrectionRows.Add('POWER-OFF-DISPOSABLE-BOOT-COPY')
$CorrectionRows.Add('REVALIDATE-SEALED-REHEARSAL-AND-DEFAULT-REGISTRY')

$OutputParent = Split-Path -Parent $Output
if ($OutputParent) {
    [void][System.IO.Directory]::CreateDirectory($OutputParent)
}
$Report = [System.Collections.Generic.List[string]]::new()
$Report.Add('DBYTE-HOLYC-OPT')
$Report.Add('TEMPLEOSTS 1.10 ISOLATED RESTORE BOOT READINESS ADJUDICATION')
$Report.Add('')
$Report.Add("resource_commit`t$ExpectedResourceCommit")
$Report.Add("rehearsal_verification_report_sha256`t$ExpectedVerificationReportHash")
$Report.Add("rehearsal_manifest_sha256`t$ExpectedRehearsalManifestHash")
$Report.Add("virtualbox_version`t$ExpectedVBoxVersion")
$Report.Add('')
$Report.Add("rehearsal_root`t$Rehearsal")
$Report.Add("isolated_vbox_user_home`t$IsolatedHome")
$Report.Add("machine_name`t$ExpectedTargetName")
$Report.Add("machine_uuid`t$ExpectedTargetUuid")
$Report.Add("machine_state`tpoweroff")
$Report.Add("vdi_uuid`t$ExpectedVdiUuid")
$Report.Add("iso_uuid`t$ExpectedIsoUuid")
$Report.Add('')
$Report.Add("boot1`t$Boot1")
$Report.Add("boot2`t$Boot2")
$Report.Add("boot3`t$Boot3")
$Report.Add("boot4`t$Boot4")
$Report.Add("vdi_first_boot`t$VdiFirstBoot")
$Report.Add("iso_attached`t$IsoAttached")
$Report.Add("graphics_controller`t$GraphicsController")
$Report.Add("vram_mb`t$Vram")
$Report.Add("clipboard_mode`t$Clipboard")
$Report.Add("drag_and_drop_mode`t$DragAndDrop")
$Report.Add("network_disabled`t$NetworkDisabled")
$Report.Add('')
foreach ($Nic in $NicRows) {
    $Report.Add("nic$($Nic.Index)_mode`t$($Nic.Mode)")
    $Report.Add("nic$($Nic.Index)_cable`t$($Nic.Cable)")
}
$Report.Add('')
$Report.Add("disposable_vbox_sha256`t$($VBoxBefore.SHA256)")
$Report.Add("disposable_vbox_file_id`t$VBoxFileId")
$Report.Add("disposable_vdi_sha256`t$($VdiBefore.SHA256)")
$Report.Add("disposable_vdi_file_id`t$VdiFileId")
$Report.Add("disposable_iso_sha256`t$($IsoBefore.SHA256)")
$Report.Add("disposable_iso_file_id`t$IsoFileId")
$Report.Add('')
foreach ($Correction in $CorrectionRows) {
    $Report.Add("boot_copy_requirement`t$Correction")
}
$Report.Add('')
$Report.Add('The sealed powered-off rehearsal was queried but not started or modified.')
$Report.Add('VBoxSVC may rotate its explicitly bounded service logs during read-only registry access.')
$Report.Add('The boot attempt must use a second disposable copy and must prove VDI-only offline boot.')
$Report.Add('Visual evidence must be reviewed before a restore-boot claim.')
$Report.Add('')
$Report.Add("SEALED REHEARSAL DIRECT START`tDENIED")
$Report.Add("BOOT ATTEMPT COPY`tREQUIRED-NOT-PREPARED")
$Report.Add("VDI-ONLY OFFLINE CORRECTION`tDEFINED-NOT-EXECUTED")
$Report.Add("VM START`tNOT-AUTHORIZED")
$Report.Add("RESTORE BOOT`tNOT-OBSERVED")
$Report.Add("POWERED-OFF RECOVERY POINT`tNOT-SEALED")
$Report.Add("BUILD EXECUTION`tNOT-AUTHORIZED")
$Report.Add('')
$Report.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')
Write-Utf8Lines -Path $Output -Lines $Report.ToArray()
$OutputHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

Write-Host "VERIFICATION REPORT:  $ExpectedVerificationReportHash"
Write-Host "BOOT1:                $Boot1"
Write-Host "BOOT2:                $Boot2"
Write-Host "BOOT3:                $Boot3"
Write-Host "BOOT4:                $Boot4"
Write-Host "VDI FIRST BOOT:       $VdiFirstBoot"
Write-Host "ISO ATTACHED:         $IsoAttached"
Write-Host "NETWORK DISABLED:     $NetworkDisabled"
Write-Host "CLIPBOARD DISABLED:   $ClipboardDisabled"
Write-Host "DRAGDROP DISABLED:    $DragAndDropDisabled"
Write-Host "GRAPHICS CONTROLLER:  $GraphicsController"
Write-Host "VRAM MB:              $Vram"
Write-Host "REPORT:               $Output"
Write-Host "REPORT SHA256:        $OutputHash"
Write-Host 'SEALED REHEARSAL:     DIRECT START DENIED'
Write-Host 'BOOT ATTEMPT COPY:    REQUIRED / NOT-PREPARED'
Write-Host 'VM START:             NOT-AUTHORIZED'
Write-Host 'RESTORE BOOT:         NOT-OBSERVED'
Write-Host 'RECOVERY POINT:       NOT-SEALED'
Write-Host 'BUILD:                NOT-AUTHORIZED'
Write-Host 'VERDICT:              ISOLATED RESTORE BOOT READINESS ADJUDICATION COMPLETE'