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
    [string]$DiffReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RecoveryRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedResourceCommit =
    '37b0457e8735ab8cc34a23f2717fcfb808e6a7a8'
$ExpectedDiffReportHash =
    'C7253681589771FF0E36A56DDFA7627C6FCA48398A1AEE1465645470DC8B3A11'
$ExpectedTargetName = 'Temple1.10'
$ExpectedTargetUuid = '9c98691e-27cd-4487-a306-587969c2c78c'
$ExpectedLiveVBoxPath = 'D:\VirtualBox VMs\Temple1.10\Temple1.10.vbox'
$ExpectedLiveVBoxHash =
    'E537469A1B1A88DE13D18704B5D6299F3AF202DA518FB266F045485A8FC4F1E6'
$ExpectedLiveVdiPath = 'D:\VirtualBox VMs\Temple1.10\Temple1.10.vdi'
$ExpectedVdiBytes = 2097152L
$ExpectedVdiHash =
    '90D453A94F075760A11E0772862E60C4B031ED874F28AA396EAE638F7EB8B31B'
$ExpectedLiveIsoPath = 'D:\TempleOSTS.iso'
$ExpectedIsoBytes = 30558208L
$ExpectedIsoHash =
    'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$BaselineRelative =
    'vm-output/virtualbox/Temple1.10-adopted-baseline/baseline1'

function Get-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path)
}

function Get-Prefix {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FullPath -Path $Path).TrimEnd('\', '/') +
        [System.IO.Path]::DirectorySeparatorChar
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

function Assert-ExactFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][long]$Bytes,
        [Parameter(Mandatory = $true)][string]$SHA256,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label missing: $Path"
    }

    $Item = Get-Item -LiteralPath $Path
    $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($Item.Length -ne $Bytes -or $Hash -cne $SHA256) {
        throw (
            "$Label identity mismatch: bytes=$($Item.Length) " +
            "SHA256=$Hash path=$Path"
        )
    }

    return [pscustomobject]@{
        Path = $Item.FullName
        Bytes = $Item.Length
        SHA256 = $Hash
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
        throw "$Label SHA256 mismatch: SHA256=$Hash path=$Path"
    }

    return [pscustomobject]@{
        Path = $Item.FullName
        Bytes = $Item.Length
        SHA256 = $Hash
    }
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

function ConvertFrom-VBoxMachineReadable {
    param(
        [Parameter(Mandatory = $true)]
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

function Assert-MachineValue {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Info,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Expected
    )

    if (-not $Info.ContainsKey($Key)) {
        throw "live machine field missing: $Key"
    }
    $Observed = [string]$Info[$Key]
    if (-not [string]::Equals(
        $Observed,
        $Expected,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "live machine field mismatch: $Key=$Observed"
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

function Write-Utf8Lines {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Lines
    )

    [System.IO.File]::WriteAllText(
        $Path,
        (($Lines -join "`n") + "`n"),
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Assert-LiveTarget {
    param(
        [Parameter(Mandatory = $true)][string[]]$Registered,
        [Parameter(Mandatory = $true)][string[]]$Running,
        [Parameter(Mandatory = $true)][string[]]$Show
    )

    $RegisteredPattern = (
        '^"' + [regex]::Escape($ExpectedTargetName) + '" \{' +
        [regex]::Escape($ExpectedTargetUuid) + '\}$'
    )
    if (@($Registered | Where-Object { $_ -match $RegisteredPattern }).Count -ne 1) {
        throw 'live registered target identity mismatch'
    }

    $RunningPattern = '^"' + [regex]::Escape($ExpectedTargetName) + '" '
    if (@($Running | Where-Object { $_ -match $RunningPattern }).Count -ne 0) {
        throw 'target is currently listed as running'
    }

    $Info = ConvertFrom-VBoxMachineReadable -Lines $Show
    Assert-MachineValue -Info $Info -Key 'name' -Expected $ExpectedTargetName
    Assert-MachineValue -Info $Info -Key 'UUID' -Expected $ExpectedTargetUuid
    Assert-MachineValue -Info $Info -Key 'VMState' -Expected 'poweroff'
    Assert-MachineValue -Info $Info -Key 'CfgFile' -Expected $ExpectedLiveVBoxPath
    Assert-MachineValue -Info $Info -Key 'IDE-1-0' -Expected $ExpectedLiveVdiPath
    Assert-MachineValue -Info $Info -Key 'IDE-0-1' -Expected $ExpectedLiveIsoPath

    $SharedNameKeys = @(
        $Info.Keys | Where-Object {
            $_ -like 'SharedFolderNameMachineMapping*'
        }
    )
    $SharedPathKeys = @(
        $Info.Keys | Where-Object {
            $_ -like 'SharedFolderPathMachineMapping*'
        }
    )
    if ($SharedNameKeys.Count -ne 0 -or $SharedPathKeys.Count -ne 0) {
        throw (
            'live machine has shared-folder mappings: ' +
            "names=$($SharedNameKeys.Count) paths=$($SharedPathKeys.Count)"
        )
    }

    return $Info
}

$script:Resource = (
    Resolve-Path -LiteralPath $ResourceRoot -ErrorAction Stop
).Path
$script:VBox = (
    Resolve-Path -LiteralPath $VBoxManagePath -ErrorAction Stop
).Path
$DiffReport = (
    Resolve-Path -LiteralPath $DiffReportPath -ErrorAction Stop
).Path
$FinalRoot = Get-FullPath -Path $RecoveryRoot
$Output = Get-FullPath -Path $OutPath
$LiveVmRoot = Split-Path -Parent $ExpectedLiveVBoxPath

if (-not (Test-Path -LiteralPath $script:Resource -PathType Container)) {
    throw "resource root is not a directory: $script:Resource"
}
if (-not (Test-Path -LiteralPath $script:VBox -PathType Leaf)) {
    throw "VBoxManage is not a file: $script:VBox"
}
foreach ($ForbiddenRoot in @($script:Resource, $LiveVmRoot)) {
    Assert-OutsideRoot `
        -Path $FinalRoot `
        -Root $ForbiddenRoot `
        -Label 'recovery root'
    Assert-OutsideRoot `
        -Path $Output `
        -Root $ForbiddenRoot `
        -Label 'preparation report'
}
Assert-OutsideRoot `
    -Path $Output `
    -Root $FinalRoot `
    -Label 'preparation report'
if (Test-Path -LiteralPath $FinalRoot) {
    throw "recovery root already exists: $FinalRoot"
}
if (Test-Path -LiteralPath $Output) {
    throw "preparation report already exists: $Output"
}

$DiffIdentity = Assert-ExactHashFile `
    -Path $DiffReport `
    -SHA256 $ExpectedDiffReportHash `
    -Label 'sealed normalized difference report'

$Head = @(Invoke-GitRead -Arguments @('rev-parse', 'HEAD') -Label 'resource HEAD')
if ($Head.Count -ne 1 -or $Head[0] -cne $ExpectedResourceCommit) {
    throw "resource HEAD mismatch: $($Head -join ' | ')"
}
[void](Invoke-GitRead -Arguments @('diff', '--check') -Label 'resource diff check')
$Worktree = @(
    Invoke-GitRead -Arguments @('diff', '--name-only') -Label 'resource worktree diff'
)
$Index = @(
    Invoke-GitRead -Arguments @('diff', '--cached', '--name-only') -Label 'resource index diff'
)
if ($Worktree.Count -ne 0 -or $Index.Count -ne 0) {
    throw 'resource tracked tree is not clean'
}

$BaselineRoot = Join-Path $script:Resource (
    $BaselineRelative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
)
$BaselineVdi = Assert-ExactFile `
    -Path (Join-Path $BaselineRoot 'Temple1.10.vdi') `
    -Bytes $ExpectedVdiBytes `
    -SHA256 $ExpectedVdiHash `
    -Label 'adopted baseline VDI'
$BaselineIso = Assert-ExactFile `
    -Path (Join-Path $BaselineRoot 'TempleOSTS.iso') `
    -Bytes $ExpectedIsoBytes `
    -SHA256 $ExpectedIsoHash `
    -Label 'adopted baseline ISO'

$Registered = @(
    Invoke-VBoxReadOnly -Arguments @('list', 'vms') -Label 'registered VM inventory'
)
$Running = @(
    Invoke-VBoxReadOnly -Arguments @('list', 'runningvms') -Label 'running VM inventory'
)
$Show = @(
    Invoke-VBoxReadOnly `
        -Arguments @('showvminfo', $ExpectedTargetUuid, '--machinereadable') `
        -Label 'target showvminfo'
)
[void](Assert-LiveTarget -Registered $Registered -Running $Running -Show $Show)

$Snapshots = @(
    Invoke-VBoxReadOnly `
        -Arguments @('snapshot', $ExpectedTargetUuid, 'list', '--machinereadable') `
        -Label 'target snapshot inventory'
)
$SnapshotRows = @(
    $Snapshots | Where-Object {
        $_ -match '^Snapshot(Name|UUID|Node)'
    }
)
if ($SnapshotRows.Count -ne 0) {
    throw "target snapshot rows are not zero: $($SnapshotRows.Count)"
}

$MediumInfo = @(
    Invoke-VBoxReadOnly `
        -Arguments @('showmediuminfo', 'disk', $ExpectedLiveVdiPath) `
        -Label 'live VDI showmediuminfo'
)

$LiveVBox = Assert-ExactHashFile `
    -Path $ExpectedLiveVBoxPath `
    -SHA256 $ExpectedLiveVBoxHash `
    -Label 'live current VBOX'
$LiveVdi = Assert-ExactFile `
    -Path $ExpectedLiveVdiPath `
    -Bytes $ExpectedVdiBytes `
    -SHA256 $ExpectedVdiHash `
    -Label 'live VDI'
$LiveIso = Assert-ExactFile `
    -Path $ExpectedLiveIsoPath `
    -Bytes $ExpectedIsoBytes `
    -SHA256 $ExpectedIsoHash `
    -Label 'live ISO'
if (Test-Path -LiteralPath (Join-Path $LiveVmRoot 'Temple1.10.nvram')) {
    throw 'live target NVRAM must remain absent'
}

$LiveVdiFileId = Get-FileId -Path $LiveVdi.Path -Label 'live VDI'
$BaselineVdiFileId = Get-FileId -Path $BaselineVdi.Path -Label 'baseline VDI'
if ($LiveVdiFileId -ceq $BaselineVdiFileId) {
    throw "live and baseline VDI share one NTFS file ID: $LiveVdiFileId"
}

$Stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$StageRoot = "$FinalRoot.incomplete-$Stamp-p$PID"
if (Test-Path -LiteralPath $StageRoot) {
    throw "staging root already exists: $StageRoot"
}
Assert-OutsideRoot `
    -Path $StageRoot `
    -Root $script:Resource `
    -Label 'staging root'
Assert-OutsideRoot `
    -Path $StageRoot `
    -Root $LiveVmRoot `
    -Label 'staging root'

$StageParent = Split-Path -Parent $StageRoot
if ($StageParent) {
    [void][System.IO.Directory]::CreateDirectory($StageParent)
}
$OutputParent = Split-Path -Parent $Output
if ($OutputParent) {
    [void][System.IO.Directory]::CreateDirectory($OutputParent)
}

try {
    [void][System.IO.Directory]::CreateDirectory($StageRoot)

    $StageVBox = Join-Path $StageRoot 'Temple1.10.vbox'
    $StageVdi = Join-Path $StageRoot 'Temple1.10.vdi'
    $StageIso = Join-Path $StageRoot 'TempleOSTS.iso'
    $StageDiff = Join-Path $StageRoot 'templeosts-vbox-normalized-diff.txt'
    [System.IO.File]::Copy($LiveVBox.Path, $StageVBox, $false)
    [System.IO.File]::Copy($BaselineVdi.Path, $StageVdi, $false)
    [System.IO.File]::Copy($BaselineIso.Path, $StageIso, $false)
    [System.IO.File]::Copy($DiffIdentity.Path, $StageDiff, $false)

    Write-Utf8Lines `
        -Path (Join-Path $StageRoot 'registered-vms.txt') `
        -Lines $Registered
    Write-Utf8Lines `
        -Path (Join-Path $StageRoot 'running-vms.txt') `
        -Lines $Running
    Write-Utf8Lines `
        -Path (Join-Path $StageRoot 'Temple1.10-showvminfo-machinereadable.txt') `
        -Lines $Show
    Write-Utf8Lines `
        -Path (Join-Path $StageRoot 'Temple1.10-snapshot-list-machinereadable.txt') `
        -Lines $Snapshots
    Write-Utf8Lines `
        -Path (Join-Path $StageRoot 'Temple1.10-vdi-showmediuminfo.txt') `
        -Lines $MediumInfo

    $CopiedVBox = Assert-ExactHashFile `
        -Path $StageVBox `
        -SHA256 $ExpectedLiveVBoxHash `
        -Label 'copied current VBOX'
    $CopiedVdi = Assert-ExactFile `
        -Path $StageVdi `
        -Bytes $ExpectedVdiBytes `
        -SHA256 $ExpectedVdiHash `
        -Label 'copied recovery VDI'
    $CopiedIso = Assert-ExactFile `
        -Path $StageIso `
        -Bytes $ExpectedIsoBytes `
        -SHA256 $ExpectedIsoHash `
        -Label 'copied recovery ISO'
    [void](Assert-ExactHashFile `
        -Path $StageDiff `
        -SHA256 $ExpectedDiffReportHash `
        -Label 'copied normalized difference report')

    $CopiedVBoxFileId = Get-FileId -Path $CopiedVBox.Path -Label 'copied VBOX'
    $LiveVBoxFileId = Get-FileId -Path $LiveVBox.Path -Label 'live VBOX'
    if ($CopiedVBoxFileId -ceq $LiveVBoxFileId) {
        throw "copied and live VBOX share one NTFS file ID: $LiveVBoxFileId"
    }

    $CopiedVdiFileId = Get-FileId -Path $CopiedVdi.Path -Label 'copied recovery VDI'
    if (
        $CopiedVdiFileId -ceq $LiveVdiFileId -or
        $CopiedVdiFileId -ceq $BaselineVdiFileId
    ) {
        throw (
            'copied recovery VDI is not a distinct NTFS file: ' +
            "copied=$CopiedVdiFileId live=$LiveVdiFileId " +
            "baseline=$BaselineVdiFileId"
        )
    }

    $EvidenceNames = @(
        'registered-vms.txt',
        'running-vms.txt',
        'Temple1.10-showvminfo-machinereadable.txt',
        'Temple1.10-snapshot-list-machinereadable.txt',
        'Temple1.10-vdi-showmediuminfo.txt'
    )
    $EvidenceLines = [System.Collections.Generic.List[string]]::new()
    foreach ($Name in $EvidenceNames) {
        $Path = Join-Path $StageRoot $Name
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "recovery evidence file missing: $Path"
        }
        $Item = Get-Item -LiteralPath $Path
        $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
        $EvidenceLines.Add("evidence`t$Name`t$($Item.Length)`t$Hash")
    }

    $ManifestPath = Join-Path $StageRoot 'RECOVERY-BUNDLE-MANIFEST.txt'
    $Manifest = [System.Collections.Generic.List[string]]::new()
    $Manifest.Add('DBYTE-HOLYC-OPT')
    $Manifest.Add('TEMPLEOSTS 1.10 CONFIGURATION-EXACT RECOVERY BUNDLE')
    $Manifest.Add('')
    $Manifest.Add("created_utc`t$([DateTime]::UtcNow.ToString('o'))")
    $Manifest.Add("resource_commit`t$ExpectedResourceCommit")
    $Manifest.Add("diff_report_sha256`t$ExpectedDiffReportHash")
    $Manifest.Add('')
    $Manifest.Add("target_name`t$ExpectedTargetName")
    $Manifest.Add("target_uuid`t$ExpectedTargetUuid")
    $Manifest.Add("vm_state_at_capture`tpoweroff")
    $Manifest.Add("snapshot_rows_at_capture`t0")
    $Manifest.Add("shared_folder_rows_at_capture`t0")
    $Manifest.Add("nvram_at_capture`tABSENT")
    $Manifest.Add('')
    $Manifest.Add("live_vbox_source`t$($LiveVBox.Path)")
    $Manifest.Add("live_vbox_bytes`t$($LiveVBox.Bytes)")
    $Manifest.Add("live_vbox_sha256`t$($LiveVBox.SHA256)")
    $Manifest.Add("live_vbox_file_id`t$LiveVBoxFileId")
    $Manifest.Add("bundle_vbox_sha256`t$($CopiedVBox.SHA256)")
    $Manifest.Add("bundle_vbox_file_id`t$CopiedVBoxFileId")
    $Manifest.Add('')
    $Manifest.Add("live_vdi_source`t$($LiveVdi.Path)")
    $Manifest.Add("live_vdi_sha256`t$($LiveVdi.SHA256)")
    $Manifest.Add("live_vdi_file_id`t$LiveVdiFileId")
    $Manifest.Add("baseline_vdi_source`t$($BaselineVdi.Path)")
    $Manifest.Add("baseline_vdi_sha256`t$($BaselineVdi.SHA256)")
    $Manifest.Add("baseline_vdi_file_id`t$BaselineVdiFileId")
    $Manifest.Add("bundle_vdi_sha256`t$($CopiedVdi.SHA256)")
    $Manifest.Add("bundle_vdi_file_id`t$CopiedVdiFileId")
    $Manifest.Add('')
    $Manifest.Add("bundle_iso_sha256`t$($CopiedIso.SHA256)")
    foreach ($Line in $EvidenceLines) {
        $Manifest.Add($Line)
    }
    $Manifest.Add('')
    $Manifest.Add("BUNDLE PREPARATION`tCOMPLETE")
    $Manifest.Add("POWERED-OFF RECOVERY POINT`tPREPARED-NOT-SEALED")
    $Manifest.Add("RESTORE EXECUTION`tNOT-OBSERVED")
    $Manifest.Add("BUILD EXECUTION`tNOT-AUTHORIZED")
    $Manifest.Add('')
    $Manifest.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')
    Write-Utf8Lines -Path $ManifestPath -Lines $Manifest.ToArray()
    $ManifestHash = (Get-FileHash -LiteralPath $ManifestPath -Algorithm SHA256).Hash

    $RegisteredFinal = @(
        Invoke-VBoxReadOnly -Arguments @('list', 'vms') -Label 'final registered VM inventory'
    )
    $RunningFinal = @(
        Invoke-VBoxReadOnly -Arguments @('list', 'runningvms') -Label 'final running VM inventory'
    )
    $ShowFinal = @(
        Invoke-VBoxReadOnly `
            -Arguments @('showvminfo', $ExpectedTargetUuid, '--machinereadable') `
            -Label 'final target showvminfo'
    )
    [void](Assert-LiveTarget `
        -Registered $RegisteredFinal `
        -Running $RunningFinal `
        -Show $ShowFinal)
    [void](Assert-ExactHashFile `
        -Path $ExpectedLiveVBoxPath `
        -SHA256 $ExpectedLiveVBoxHash `
        -Label 'final live VBOX')
    [void](Assert-ExactFile `
        -Path $ExpectedLiveVdiPath `
        -Bytes $ExpectedVdiBytes `
        -SHA256 $ExpectedVdiHash `
        -Label 'final live VDI')
    [void](Assert-ExactFile `
        -Path $ExpectedLiveIsoPath `
        -Bytes $ExpectedIsoBytes `
        -SHA256 $ExpectedIsoHash `
        -Label 'final live ISO')

    [System.IO.Directory]::Move($StageRoot, $FinalRoot)

    $FinalManifest = Join-Path $FinalRoot 'RECOVERY-BUNDLE-MANIFEST.txt'
    $FinalManifestHash = (
        Get-FileHash -LiteralPath $FinalManifest -Algorithm SHA256
    ).Hash
    if ($FinalManifestHash -cne $ManifestHash) {
        throw (
            'manifest hash changed after final directory move: ' +
            "before=$ManifestHash after=$FinalManifestHash"
        )
    }

    $Report = [System.Collections.Generic.List[string]]::new()
    $Report.Add('DBYTE-HOLYC-OPT')
    $Report.Add('TEMPLEOSTS 1.10 CONFIGURATION-EXACT RECOVERY BUNDLE PREPARATION')
    $Report.Add('')
    $Report.Add("resource_commit`t$ExpectedResourceCommit")
    $Report.Add("diff_report_sha256`t$ExpectedDiffReportHash")
    $Report.Add("target_name`t$ExpectedTargetName")
    $Report.Add("target_uuid`t$ExpectedTargetUuid")
    $Report.Add("vm_state`tpoweroff")
    $Report.Add('')
    $Report.Add("recovery_root`t$FinalRoot")
    $Report.Add("manifest_sha256`t$FinalManifestHash")
    $Report.Add("bundle_vbox_sha256`t$($CopiedVBox.SHA256)")
    $Report.Add("bundle_vbox_file_id`t$CopiedVBoxFileId")
    $Report.Add("bundle_vdi_sha256`t$($CopiedVdi.SHA256)")
    $Report.Add("bundle_vdi_file_id`t$CopiedVdiFileId")
    $Report.Add("bundle_iso_sha256`t$($CopiedIso.SHA256)")
    $Report.Add('')
    $Report.Add('The bundle VBOX is an exact distinct-file copy of the current powered-off VM configuration.')
    $Report.Add('The bundle VDI is an exact third-file copy sourced from the adopted baseline VDI.')
    $Report.Add('The bundle VDI, adopted baseline VDI and live VDI have equal bytes and SHA256 but distinct NTFS file IDs.')
    $Report.Add('No VM, snapshot, attachment, live VBOX, live VDI, live ISO, guest file or compiler output was modified.')
    $Report.Add('')
    $Report.Add("BUNDLE PREPARATION`tCOMPLETE")
    $Report.Add("POWERED-OFF RECOVERY POINT`tPREPARED-NOT-SEALED")
    $Report.Add("RESTORE EXECUTION`tNOT-OBSERVED")
    $Report.Add("GUEST DELIVERY ROUTE`tUNRESOLVED")
    $Report.Add("BUILD EXECUTION`tNOT-AUTHORIZED")
    $Report.Add('')
    $Report.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')
    Write-Utf8Lines -Path $Output -Lines $Report.ToArray()
    $OutputHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

    Write-Host "DIFF REPORT:          $ExpectedDiffReportHash"
    Write-Host "TARGET NAME:          $ExpectedTargetName"
    Write-Host "TARGET UUID:          $ExpectedTargetUuid"
    Write-Host 'VM STATE:             poweroff'
    Write-Host "LIVE VBOX:            $ExpectedLiveVBoxHash"
    Write-Host "LIVE VDI:             $ExpectedVdiHash"
    Write-Host "BASELINE VDI ID:      $BaselineVdiFileId"
    Write-Host "LIVE VDI ID:          $LiveVdiFileId"
    Write-Host "BUNDLE ROOT:          $FinalRoot"
    Write-Host "BUNDLE MANIFEST:      $FinalManifestHash"
    Write-Host "BUNDLE VBOX ID:       $CopiedVBoxFileId"
    Write-Host "BUNDLE VDI ID:        $CopiedVdiFileId"
    Write-Host "REPORT:               $Output"
    Write-Host "REPORT SHA256:        $OutputHash"
    Write-Host 'BUNDLE:               PREPARED'
    Write-Host 'RECOVERY POINT:       NOT-SEALED'
    Write-Host 'RESTORE EXECUTION:    NOT-OBSERVED'
    Write-Host 'BUILD:                NOT-AUTHORIZED'
    Write-Host 'VERDICT:              CONFIGURATION-EXACT RECOVERY BUNDLE PREPARATION COMPLETE'
}
catch {
    if (Test-Path -LiteralPath $StageRoot) {
        Write-Host "INCOMPLETE ROOT:      $StageRoot"
        Write-Host 'INCOMPLETE ROOT WAS PRESERVED FOR REVIEW.'
    }
    throw
}
