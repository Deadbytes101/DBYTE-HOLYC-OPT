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
    [string]$PreparationReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RecoveryRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PreservedIncompleteRoot,

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
$ExpectedPreparationReportHash =
    'C4182656FC6DFE7CD3173126564415C37745B756B5416557BBCFE7EDA6D948D8'
$ExpectedManifestHash =
    '3E7C4285920A981BF72AFCD179C467B2DEC35AB1828D21EB4767A1DEB3619F45'
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
$ExpectedRecoveryRoot =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-RECOVERY\templeosts-1.10-config-exact-r2'
$ExpectedIncompleteRoot =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-RECOVERY\templeosts-1.10-config-exact-r2.incomplete-20260806T231912Z-p11460'
$ExpectedPreparationReportPath =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-config-exact-recovery-preparation.txt'
$ExpectedBaselineVdiFileId = '0X0000000000000000001500000003CF10'
$ExpectedLiveVdiFileId = '0X00000000000000000004000000040293'
$ExpectedBundleVBoxFileId = '0X00000000000000000003000000060062'
$ExpectedBundleVdiFileId = '0X0000000000000000000100000006007B'
$BaselineRelative =
    'vm-output/virtualbox/Temple1.10-adopted-baseline/baseline1'

$ExpectedBundleNames = @(
    'RECOVERY-BUNDLE-MANIFEST.txt',
    'registered-vms.txt',
    'running-vms.txt',
    'Temple1.10-showvminfo-machinereadable.txt',
    'Temple1.10-snapshot-list-machinereadable.txt',
    'Temple1.10-vdi-showmediuminfo.txt',
    'Temple1.10.vbox',
    'Temple1.10.vdi',
    'TempleOSTS.iso',
    'templeosts-vbox-normalized-diff.txt'
)
$ExpectedEvidenceNames = @(
    'registered-vms.txt',
    'running-vms.txt',
    'Temple1.10-showvminfo-machinereadable.txt',
    'Temple1.10-snapshot-list-machinereadable.txt',
    'Temple1.10-vdi-showmediuminfo.txt'
)
$ExpectedIncompleteNames = @(
    'registered-vms.txt',
    'running-vms.txt',
    'Temple1.10-showvminfo-machinereadable.txt',
    'Temple1.10-snapshot-list-machinereadable.txt',
    'Temple1.10-vdi-showmediuminfo.txt',
    'Temple1.10.vbox',
    'Temple1.10.vdi',
    'TempleOSTS.iso',
    'templeosts-vbox-normalized-diff.txt'
)

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
        throw "$Label SHA256 mismatch: SHA256=$Hash path=$Path"
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

    $Identity = Assert-ExactHashFile `
        -Path $Path `
        -SHA256 $SHA256 `
        -Label $Label
    if ($Identity.Bytes -ne $Bytes) {
        throw (
            "$Label byte-count mismatch: bytes=$($Identity.Bytes) " +
            "expected=$Bytes path=$($Identity.Path)"
        )
    }
    return $Identity
}

function Assert-UniqueLine {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Expected
    )

    $Count = @($Lines | Where-Object { $_ -ceq $Expected }).Count
    if ($Count -ne 1) {
        throw "required line count mismatch: $Expected count=$Count"
    }
}

function Get-UniqueTabValue {
    param(
        [Parameter(Mandatory = $true)]
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
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Expected
    )

    $Observed = Get-UniqueTabValue -Lines $Lines -Key $Key
    if ($Observed -cne $Expected) {
        throw "field mismatch: $Key expected=$Expected observed=$Observed"
    }
}

function Assert-ExactNameSet {
    param(
        [Parameter(Mandatory = $true)][string[]]$Observed,
        [Parameter(Mandatory = $true)][string[]]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $ObservedSorted = @($Observed | Sort-Object)
    $ExpectedSorted = @($Expected | Sort-Object)
    $Difference = @(
        Compare-Object `
            -ReferenceObject $ExpectedSorted `
            -DifferenceObject $ObservedSorted `
            -CaseSensitive
    )
    if ($Difference.Count -ne 0) {
        throw "$Label name-set mismatch: $($Difference | Out-String)"
    }
    if ($ObservedSorted.Count -ne $ExpectedSorted.Count) {
        throw (
            "$Label count mismatch: observed=$($ObservedSorted.Count) " +
            "expected=$($ExpectedSorted.Count)"
        )
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

function Invoke-VBoxSnapshotInventory {
    param(
        [Parameter(Mandatory = $true)][string]$Uuid,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Captured = @(
        & $script:VBox `
            'snapshot' `
            $Uuid `
            'list' `
            '--machinereadable' 2>&1 |
            ForEach-Object { [string]$_ }
    )
    $ExitCode = $LASTEXITCODE
    if ($ExitCode -eq 0) {
        return $Captured
    }

    $NoSnapshotSentinel = 'This machine does not have any snapshots'
    if (
        $Captured.Count -eq 1 -and
        $Captured[0].Trim() -ceq $NoSnapshotSentinel
    ) {
        return @()
    }

    throw "$Label failed`n$($Captured -join "`n")"
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

function Assert-LiveTarget {
    param(
        [Parameter(Mandatory = $true)][string[]]$Registered,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Running,
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

$script:Resource = (
    Resolve-Path -LiteralPath $ResourceRoot -ErrorAction Stop
).Path
$script:VBox = (
    Resolve-Path -LiteralPath $VBoxManagePath -ErrorAction Stop
).Path
$DiffReport = (
    Resolve-Path -LiteralPath $DiffReportPath -ErrorAction Stop
).Path
$PreparationReport = (
    Resolve-Path -LiteralPath $PreparationReportPath -ErrorAction Stop
).Path
$Bundle = (
    Resolve-Path -LiteralPath $RecoveryRoot -ErrorAction Stop
).Path
$Incomplete = (
    Resolve-Path -LiteralPath $PreservedIncompleteRoot -ErrorAction Stop
).Path
$Output = Get-FullPath -Path $OutPath
$LiveVmRoot = Split-Path -Parent $ExpectedLiveVBoxPath

if (-not (Test-Path -LiteralPath $script:Resource -PathType Container)) {
    throw "resource root is not a directory: $script:Resource"
}
if (-not (Test-Path -LiteralPath $script:VBox -PathType Leaf)) {
    throw "VBoxManage is not a file: $script:VBox"
}
if (-not (Test-Path -LiteralPath $Bundle -PathType Container)) {
    throw "recovery root is not a directory: $Bundle"
}
if (-not (Test-Path -LiteralPath $Incomplete -PathType Container)) {
    throw "preserved incomplete root is not a directory: $Incomplete"
}
Assert-PathEquals -Observed $Bundle -Expected $ExpectedRecoveryRoot -Label 'recovery root'
Assert-PathEquals -Observed $Incomplete -Expected $ExpectedIncompleteRoot -Label 'incomplete root'
Assert-PathEquals `
    -Observed $PreparationReport `
    -Expected $ExpectedPreparationReportPath `
    -Label 'preparation report'
foreach ($ForbiddenRoot in @(
    $script:Resource,
    $Bundle,
    $Incomplete,
    $LiveVmRoot
)) {
    Assert-OutsideRoot -Path $Output -Root $ForbiddenRoot -Label 'verification report'
}
if (Test-Path -LiteralPath $Output) {
    throw "verification report already exists: $Output"
}

$DiffIdentity = Assert-ExactHashFile `
    -Path $DiffReport `
    -SHA256 $ExpectedDiffReportHash `
    -Label 'sealed normalized-difference report'
$PreparationIdentity = Assert-ExactHashFile `
    -Path $PreparationReport `
    -SHA256 $ExpectedPreparationReportHash `
    -Label 'bundle preparation report'

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
$BaselineVdiFileId = Assert-FileId `
    -Path $BaselineVdi.Path `
    -Expected $ExpectedBaselineVdiFileId `
    -Label 'adopted baseline VDI'

$PreparationLines = [System.IO.File]::ReadAllLines($PreparationReport)
Assert-UniqueLine `
    -Lines $PreparationLines `
    -Expected 'TEMPLEOSTS 1.10 CONFIGURATION-EXACT RECOVERY BUNDLE PREPARATION'
Assert-FieldEquals `
    -Lines $PreparationLines `
    -Key 'resource_commit' `
    -Expected $ExpectedResourceCommit
Assert-FieldEquals `
    -Lines $PreparationLines `
    -Key 'diff_report_sha256' `
    -Expected $ExpectedDiffReportHash
Assert-FieldEquals `
    -Lines $PreparationLines `
    -Key 'target_name' `
    -Expected $ExpectedTargetName
Assert-FieldEquals `
    -Lines $PreparationLines `
    -Key 'target_uuid' `
    -Expected $ExpectedTargetUuid
Assert-FieldEquals -Lines $PreparationLines -Key 'vm_state' -Expected 'poweroff'
Assert-FieldEquals `
    -Lines $PreparationLines `
    -Key 'recovery_root' `
    -Expected $ExpectedRecoveryRoot
Assert-FieldEquals `
    -Lines $PreparationLines `
    -Key 'manifest_sha256' `
    -Expected $ExpectedManifestHash
Assert-FieldEquals `
    -Lines $PreparationLines `
    -Key 'bundle_vbox_sha256' `
    -Expected $ExpectedLiveVBoxHash
Assert-FieldEquals `
    -Lines $PreparationLines `
    -Key 'bundle_vbox_file_id' `
    -Expected $ExpectedBundleVBoxFileId
Assert-FieldEquals `
    -Lines $PreparationLines `
    -Key 'bundle_vdi_sha256' `
    -Expected $ExpectedVdiHash
Assert-FieldEquals `
    -Lines $PreparationLines `
    -Key 'bundle_vdi_file_id' `
    -Expected $ExpectedBundleVdiFileId
Assert-FieldEquals `
    -Lines $PreparationLines `
    -Key 'bundle_iso_sha256' `
    -Expected $ExpectedIsoHash
Assert-FieldEquals `
    -Lines $PreparationLines `
    -Key 'BUNDLE PREPARATION' `
    -Expected 'COMPLETE'
Assert-FieldEquals `
    -Lines $PreparationLines `
    -Key 'POWERED-OFF RECOVERY POINT' `
    -Expected 'PREPARED-NOT-SEALED'
Assert-FieldEquals `
    -Lines $PreparationLines `
    -Key 'RESTORE EXECUTION' `
    -Expected 'NOT-OBSERVED'
Assert-FieldEquals `
    -Lines $PreparationLines `
    -Key 'GUEST DELIVERY ROUTE' `
    -Expected 'UNRESOLVED'
Assert-FieldEquals `
    -Lines $PreparationLines `
    -Key 'BUILD EXECUTION' `
    -Expected 'NOT-AUTHORIZED'

$BundleItems = @(Get-ChildItem -LiteralPath $Bundle -Force)
$BundleDirectories = @($BundleItems | Where-Object { $_.PSIsContainer })
$BundleFiles = @($BundleItems | Where-Object { -not $_.PSIsContainer })
if ($BundleDirectories.Count -ne 0) {
    throw "bundle contains directories: $($BundleDirectories.FullName -join ' | ')"
}
Assert-ExactNameSet `
    -Observed @($BundleFiles.Name) `
    -Expected $ExpectedBundleNames `
    -Label 'bundle file set'

$BundleManifest = Assert-ExactHashFile `
    -Path (Join-Path $Bundle 'RECOVERY-BUNDLE-MANIFEST.txt') `
    -SHA256 $ExpectedManifestHash `
    -Label 'bundle manifest'
$BundleVBox = Assert-ExactHashFile `
    -Path (Join-Path $Bundle 'Temple1.10.vbox') `
    -SHA256 $ExpectedLiveVBoxHash `
    -Label 'bundle VBOX'
$BundleVdi = Assert-ExactFile `
    -Path (Join-Path $Bundle 'Temple1.10.vdi') `
    -Bytes $ExpectedVdiBytes `
    -SHA256 $ExpectedVdiHash `
    -Label 'bundle VDI'
$BundleIso = Assert-ExactFile `
    -Path (Join-Path $Bundle 'TempleOSTS.iso') `
    -Bytes $ExpectedIsoBytes `
    -SHA256 $ExpectedIsoHash `
    -Label 'bundle ISO'
$BundleDiff = Assert-ExactHashFile `
    -Path (Join-Path $Bundle 'templeosts-vbox-normalized-diff.txt') `
    -SHA256 $ExpectedDiffReportHash `
    -Label 'bundle normalized-difference report'

$BundleVBoxFileId = Assert-FileId `
    -Path $BundleVBox.Path `
    -Expected $ExpectedBundleVBoxFileId `
    -Label 'bundle VBOX'
$BundleVdiFileId = Assert-FileId `
    -Path $BundleVdi.Path `
    -Expected $ExpectedBundleVdiFileId `
    -Label 'bundle VDI'

$ManifestLines = [System.IO.File]::ReadAllLines($BundleManifest.Path)
Assert-UniqueLine `
    -Lines $ManifestLines `
    -Expected 'TEMPLEOSTS 1.10 CONFIGURATION-EXACT RECOVERY BUNDLE'
Assert-FieldEquals `
    -Lines $ManifestLines `
    -Key 'resource_commit' `
    -Expected $ExpectedResourceCommit
Assert-FieldEquals `
    -Lines $ManifestLines `
    -Key 'diff_report_sha256' `
    -Expected $ExpectedDiffReportHash
Assert-FieldEquals `
    -Lines $ManifestLines `
    -Key 'target_name' `
    -Expected $ExpectedTargetName
Assert-FieldEquals `
    -Lines $ManifestLines `
    -Key 'target_uuid' `
    -Expected $ExpectedTargetUuid
Assert-FieldEquals `
    -Lines $ManifestLines `
    -Key 'vm_state_at_capture' `
    -Expected 'poweroff'
Assert-FieldEquals `
    -Lines $ManifestLines `
    -Key 'snapshot_rows_at_capture' `
    -Expected '0'
Assert-FieldEquals `
    -Lines $ManifestLines `
    -Key 'shared_folder_rows_at_capture' `
    -Expected '0'
Assert-FieldEquals `
    -Lines $ManifestLines `
    -Key 'nvram_at_capture' `
    -Expected 'ABSENT'
Assert-FieldEquals `
    -Lines $ManifestLines `
    -Key 'live_vbox_source' `
    -Expected $ExpectedLiveVBoxPath
Assert-FieldEquals `
    -Lines $ManifestLines `
    -Key 'live_vbox_bytes' `
    -Expected ([string]$BundleVBox.Bytes)
Assert-FieldEquals `
    -Lines $ManifestLines `
    -Key 'live_vbox_sha256' `
    -Expected $ExpectedLiveVBoxHash
Assert-FieldEquals `
    -Lines $ManifestLines `
    -Key 'bundle_vbox_sha256' `
    -Expected $ExpectedLiveVBoxHash
Assert-FieldEquals `
    -Lines $ManifestLines `
    -Key 'bundle_vbox_file_id' `
    -Expected $ExpectedBundleVBoxFileId
Assert-FieldEquals `
    -Lines $ManifestLines `
    -Key 'live_vdi_source' `
    -Expected $ExpectedLiveVdiPath
Assert-FieldEquals `
    -Lines $ManifestLines `
    -Key 'live_vdi_sha256' `
    -Expected $ExpectedVdiHash
Assert-FieldEquals `
    -Lines $ManifestLines `
    -Key 'live_vdi_file_id' `
    -Expected $ExpectedLiveVdiFileId
Assert-FieldEquals `
    -Lines $ManifestLines `
    -Key 'baseline_vdi_source' `
    -Expected $BaselineVdi.Path
Assert-FieldEquals `
    -Lines $ManifestLines `
    -Key 'baseline_vdi_sha256' `
    -Expected $ExpectedVdiHash
Assert-FieldEquals `
    -Lines $ManifestLines `
    -Key 'baseline_vdi_file_id' `
    -Expected $ExpectedBaselineVdiFileId
Assert-FieldEquals `
    -Lines $ManifestLines `
    -Key 'bundle_vdi_sha256' `
    -Expected $ExpectedVdiHash
Assert-FieldEquals `
    -Lines $ManifestLines `
    -Key 'bundle_vdi_file_id' `
    -Expected $ExpectedBundleVdiFileId
Assert-FieldEquals `
    -Lines $ManifestLines `
    -Key 'bundle_iso_sha256' `
    -Expected $ExpectedIsoHash
Assert-FieldEquals `
    -Lines $ManifestLines `
    -Key 'BUNDLE PREPARATION' `
    -Expected 'COMPLETE'
Assert-FieldEquals `
    -Lines $ManifestLines `
    -Key 'POWERED-OFF RECOVERY POINT' `
    -Expected 'PREPARED-NOT-SEALED'
Assert-FieldEquals `
    -Lines $ManifestLines `
    -Key 'RESTORE EXECUTION' `
    -Expected 'NOT-OBSERVED'
Assert-FieldEquals `
    -Lines $ManifestLines `
    -Key 'BUILD EXECUTION' `
    -Expected 'NOT-AUTHORIZED'

$CreatedUtcText = Get-UniqueTabValue -Lines $ManifestLines -Key 'created_utc'
$CreatedUtc = [DateTimeOffset]::MinValue
if (-not [DateTimeOffset]::TryParse($CreatedUtcText, [ref]$CreatedUtc)) {
    throw "manifest created_utc is not parseable: $CreatedUtcText"
}
if ($CreatedUtc.Offset -ne [TimeSpan]::Zero) {
    throw "manifest created_utc is not UTC: $CreatedUtcText"
}

$EvidenceRows = @(
    foreach ($Line in $ManifestLines) {
        $Match = [regex]::Match(
            $Line,
            '^evidence\t([^\t]+)\t([0-9]+)\t([0-9A-F]{64})$'
        )
        if ($Match.Success) {
            [pscustomobject]@{
                Name = $Match.Groups[1].Value
                Bytes = [long]$Match.Groups[2].Value
                SHA256 = $Match.Groups[3].Value
            }
        }
    }
)
if ($EvidenceRows.Count -ne $ExpectedEvidenceNames.Count) {
    throw "manifest evidence row count mismatch: $($EvidenceRows.Count)"
}
Assert-ExactNameSet `
    -Observed @($EvidenceRows.Name) `
    -Expected $ExpectedEvidenceNames `
    -Label 'manifest evidence set'
foreach ($Evidence in $EvidenceRows) {
    [void](Assert-ExactFile `
        -Path (Join-Path $Bundle $Evidence.Name) `
        -Bytes $Evidence.Bytes `
        -SHA256 $Evidence.SHA256 `
        -Label "bundle evidence $($Evidence.Name)")
}

$CapturedRegistered = [System.IO.File]::ReadAllLines(
    (Join-Path $Bundle 'registered-vms.txt')
)
$CapturedRunning = [System.IO.File]::ReadAllLines(
    (Join-Path $Bundle 'running-vms.txt')
)
$CapturedShow = [System.IO.File]::ReadAllLines(
    (Join-Path $Bundle 'Temple1.10-showvminfo-machinereadable.txt')
)
$CapturedSnapshots = [System.IO.File]::ReadAllLines(
    (Join-Path $Bundle 'Temple1.10-snapshot-list-machinereadable.txt')
)
[void](Assert-LiveTarget `
    -Registered $CapturedRegistered `
    -Running $CapturedRunning `
    -Show $CapturedShow)
$CapturedSnapshotRows = @(
    $CapturedSnapshots | Where-Object {
        $_ -match '^Snapshot(Name|UUID|Node)'
    }
)
if ($CapturedSnapshotRows.Count -ne 0) {
    throw "captured snapshot rows are not zero: $($CapturedSnapshotRows.Count)"
}

$IncompleteItems = @(Get-ChildItem -LiteralPath $Incomplete -Force)
$IncompleteDirectories = @($IncompleteItems | Where-Object { $_.PSIsContainer })
$IncompleteFiles = @($IncompleteItems | Where-Object { -not $_.PSIsContainer })
if ($IncompleteDirectories.Count -ne 0) {
    throw "incomplete root contains directories: $($IncompleteDirectories.FullName -join ' | ')"
}
Assert-ExactNameSet `
    -Observed @($IncompleteFiles.Name) `
    -Expected $ExpectedIncompleteNames `
    -Label 'preserved incomplete file set'
if (Test-Path -LiteralPath (Join-Path $Incomplete 'RECOVERY-BUNDLE-MANIFEST.txt')) {
    throw 'preserved incomplete root unexpectedly contains a manifest'
}
[void](Assert-ExactHashFile `
    -Path (Join-Path $Incomplete 'Temple1.10.vbox') `
    -SHA256 $ExpectedLiveVBoxHash `
    -Label 'incomplete VBOX')
[void](Assert-ExactFile `
    -Path (Join-Path $Incomplete 'Temple1.10.vdi') `
    -Bytes $ExpectedVdiBytes `
    -SHA256 $ExpectedVdiHash `
    -Label 'incomplete VDI')
[void](Assert-ExactFile `
    -Path (Join-Path $Incomplete 'TempleOSTS.iso') `
    -Bytes $ExpectedIsoBytes `
    -SHA256 $ExpectedIsoHash `
    -Label 'incomplete ISO')
[void](Assert-ExactHashFile `
    -Path (Join-Path $Incomplete 'templeosts-vbox-normalized-diff.txt') `
    -SHA256 $ExpectedDiffReportHash `
    -Label 'incomplete normalized-difference report')

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
    Invoke-VBoxSnapshotInventory `
        -Uuid $ExpectedTargetUuid `
        -Label 'target snapshot inventory'
)
$SnapshotRows = @(
    $Snapshots | Where-Object {
        $_ -match '^Snapshot(Name|UUID|Node)'
    }
)
if ($SnapshotRows.Count -ne 0) {
    throw "live target snapshot rows are not zero: $($SnapshotRows.Count)"
}
[void](Invoke-VBoxReadOnly `
    -Arguments @('showmediuminfo', 'disk', $ExpectedLiveVdiPath) `
    -Label 'live VDI showmediuminfo')

$LiveVBox = Assert-ExactHashFile `
    -Path $ExpectedLiveVBoxPath `
    -SHA256 $ExpectedLiveVBoxHash `
    -Label 'live VBOX'
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

$LiveVdiFileId = Assert-FileId `
    -Path $LiveVdi.Path `
    -Expected $ExpectedLiveVdiFileId `
    -Label 'live VDI'
$LiveVBoxFileId = Get-FileId -Path $LiveVBox.Path -Label 'live VBOX'
Assert-FieldEquals `
    -Lines $ManifestLines `
    -Key 'live_vbox_file_id' `
    -Expected $LiveVBoxFileId
if ($BundleVBoxFileId -ceq $LiveVBoxFileId) {
    throw "bundle and live VBOX share one NTFS file ID: $LiveVBoxFileId"
}

$VdiFileIds = @(
    $BaselineVdiFileId,
    $LiveVdiFileId,
    $BundleVdiFileId
)
if (@($VdiFileIds | Select-Object -Unique).Count -ne 3) {
    throw "VDI file IDs are not pairwise distinct: $($VdiFileIds -join ' | ')"
}

$OutputParent = Split-Path -Parent $Output
if ($OutputParent) {
    [void][System.IO.Directory]::CreateDirectory($OutputParent)
}

$Report = [System.Collections.Generic.List[string]]::new()
$Report.Add('DBYTE-HOLYC-OPT')
$Report.Add('TEMPLEOSTS 1.10 CONFIGURATION-EXACT RECOVERY BUNDLE VERIFICATION')
$Report.Add('')
$Report.Add("resource_commit`t$ExpectedResourceCommit")
$Report.Add("diff_report_sha256`t$($DiffIdentity.SHA256)")
$Report.Add("preparation_report_sha256`t$($PreparationIdentity.SHA256)")
$Report.Add("manifest_sha256`t$($BundleManifest.SHA256)")
$Report.Add("manifest_created_utc`t$CreatedUtcText")
$Report.Add('')
$Report.Add("target_name`t$ExpectedTargetName")
$Report.Add("target_uuid`t$ExpectedTargetUuid")
$Report.Add("vm_state`tpoweroff")
$Report.Add("running_target_rows`t0")
$Report.Add("snapshot_rows`t0")
$Report.Add("shared_folder_rows`t0")
$Report.Add("live_nvram`tABSENT")
$Report.Add('')
$Report.Add("bundle_root`t$Bundle")
$Report.Add("bundle_file_count`t$($BundleFiles.Count)")
$Report.Add("bundle_vbox_bytes`t$($BundleVBox.Bytes)")
$Report.Add("bundle_vbox_sha256`t$($BundleVBox.SHA256)")
$Report.Add("bundle_vbox_file_id`t$BundleVBoxFileId")
$Report.Add("bundle_vdi_bytes`t$($BundleVdi.Bytes)")
$Report.Add("bundle_vdi_sha256`t$($BundleVdi.SHA256)")
$Report.Add("bundle_vdi_file_id`t$BundleVdiFileId")
$Report.Add("bundle_iso_bytes`t$($BundleIso.Bytes)")
$Report.Add("bundle_iso_sha256`t$($BundleIso.SHA256)")
$Report.Add("bundle_diff_sha256`t$($BundleDiff.SHA256)")
$Report.Add("bundle_evidence_files`t$($EvidenceRows.Count)")
$Report.Add('')
$Report.Add("live_vbox_sha256`t$($LiveVBox.SHA256)")
$Report.Add("live_vbox_file_id`t$LiveVBoxFileId")
$Report.Add("live_vdi_sha256`t$($LiveVdi.SHA256)")
$Report.Add("live_vdi_file_id`t$LiveVdiFileId")
$Report.Add("baseline_vdi_sha256`t$($BaselineVdi.SHA256)")
$Report.Add("baseline_vdi_file_id`t$BaselineVdiFileId")
$Report.Add('')
$Report.Add("preserved_incomplete_root`t$Incomplete")
$Report.Add("preserved_incomplete_file_count`t$($IncompleteFiles.Count)")
$Report.Add("preserved_incomplete_manifest`tABSENT")
$Report.Add('')
$Report.Add('The exact ten-file bundle set was reopened and verified.')
$Report.Add('All bundle payload identities and all five manifest evidence rows were revalidated.')
$Report.Add('The bundle, live and adopted-baseline VDI are exact and pairwise distinct NTFS files.')
$Report.Add('The bundle VBOX is exact and distinct from the live VBOX file object.')
$Report.Add('The live target remained powered off with zero running rows, snapshots and shared folders.')
$Report.Add('The preserved failed staging root remained present without a manifest and was not promoted.')
$Report.Add('No restore, VM mutation, attachment change, guest delivery or compiler execution occurred.')
$Report.Add('')
$Report.Add("CONFIGURATION-EXACT BUNDLE`tVERIFIED")
$Report.Add("BUNDLE IDENTITY`tSEALED")
$Report.Add("POWERED-OFF RECOVERY POINT`tNOT-SEALED")
$Report.Add("RESTORE ROUTE`tUNRESOLVED")
$Report.Add("RESTORE EXECUTION`tNOT-OBSERVED")
$Report.Add("GUEST DELIVERY ROUTE`tUNRESOLVED")
$Report.Add("BUILD EXECUTION`tNOT-AUTHORIZED")
$Report.Add('')
$Report.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')

[System.IO.File]::WriteAllText(
    $Output,
    (($Report -join "`n") + "`n"),
    [System.Text.UTF8Encoding]::new($false)
)
$OutputHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

Write-Host "PREPARATION REPORT:   $($PreparationIdentity.SHA256)"
Write-Host "BUNDLE MANIFEST:      $($BundleManifest.SHA256)"
Write-Host "BUNDLE FILES:         $($BundleFiles.Count)"
Write-Host "BUNDLE VBOX:          $($BundleVBox.SHA256)"
Write-Host "BUNDLE VBOX ID:       $BundleVBoxFileId"
Write-Host "BUNDLE VDI:           $($BundleVdi.SHA256)"
Write-Host "BUNDLE VDI ID:        $BundleVdiFileId"
Write-Host "LIVE VDI ID:          $LiveVdiFileId"
Write-Host "BASELINE VDI ID:      $BaselineVdiFileId"
Write-Host "INCOMPLETE FILES:     $($IncompleteFiles.Count)"
Write-Host "REPORT:               $Output"
Write-Host "REPORT SHA256:        $OutputHash"
Write-Host 'BUNDLE:               VERIFIED'
Write-Host 'BUNDLE IDENTITY:      SEALED'
Write-Host 'RECOVERY POINT:       NOT-SEALED'
Write-Host 'RESTORE ROUTE:        UNRESOLVED'
Write-Host 'RESTORE EXECUTION:    NOT-OBSERVED'
Write-Host 'BUILD:                NOT-AUTHORIZED'
Write-Host 'VERDICT:              CONFIGURATION-EXACT RECOVERY BUNDLE VERIFICATION COMPLETE'
