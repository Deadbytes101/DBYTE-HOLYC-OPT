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
    [string]$VerificationReportPath,

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
$ExpectedVerificationReportHash =
    '887D93D1869CA321A8A4A11816A7ABA6A74366BBA64D4138E1D7DF223F7A9CEC'
$ExpectedManifestHash =
    '3E7C4285920A981BF72AFCD179C467B2DEC35AB1828D21EB4767A1DEB3619F45'
$ExpectedTargetName = 'Temple1.10'
$ExpectedTargetUuid = '9c98691e-27cd-4487-a306-587969c2c78c'
$ExpectedVdiUuid = '55c1f29d-a681-402e-b90d-bfbb6b09f207'
$ExpectedIsoUuid = 'ab97b3a5-1331-494d-a917-e85b6e728c45'
$ExpectedVBoxVersion = '7.0.12r159484'
$ExpectedRecoveryRoot =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-RECOVERY\templeosts-1.10-config-exact-r2'
$ExpectedLiveVBoxPath = 'D:\VirtualBox VMs\Temple1.10\Temple1.10.vbox'
$ExpectedLiveVdiPath = 'D:\VirtualBox VMs\Temple1.10\Temple1.10.vdi'
$ExpectedLiveIsoPath = 'D:\TempleOSTS.iso'
$ExpectedLiveVBoxHash =
    'E537469A1B1A88DE13D18704B5D6299F3AF202DA518FB266F045485A8FC4F1E6'
$ExpectedVdiBytes = 2097152L
$ExpectedVdiHash =
    '90D453A94F075760A11E0772862E60C4B031ED874F28AA396EAE638F7EB8B31B'
$ExpectedIsoBytes = 30558208L
$ExpectedIsoHash =
    'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$ExpectedBundleVBoxFileId = '0X00000000000000000003000000060062'
$ExpectedBundleVdiFileId = '0X0000000000000000000100000006007B'
$ExpectedLiveVdiFileId = '0X00000000000000000004000000040293'
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
        throw "$Label SHA256 mismatch: observed=$Hash expected=$SHA256 path=$Path"
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
        throw "field mismatch: $Key observed=$Observed expected=$Expected"
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
    if ($Difference.Count -ne 0 -or $ObservedSorted.Count -ne $ExpectedSorted.Count) {
        throw "$Label name-set mismatch: $($Difference | Out-String)"
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
    if (
        $Captured.Count -eq 1 -and
        $Captured[0].Trim() -ceq 'This machine does not have any snapshots'
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
        throw "live machine field mismatch: $Key=$Observed expected=$Expected"
    }
}

function ConvertTo-NormalizedUuid {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Value,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Trimmed = $Value.Trim().Trim('{', '}')
    $Parsed = [guid]::Empty
    if (-not [guid]::TryParse($Trimmed, [ref]$Parsed)) {
        throw "$Label is not a UUID: $Value"
    }
    return $Parsed.ToString().ToLowerInvariant()
}

function Get-RequiredAttribute {
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Node,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Attribute = $Node.Attributes[$Name]
    if ($null -eq $Attribute -or [string]::IsNullOrWhiteSpace($Attribute.Value)) {
        throw "$Label attribute missing: $Name"
    }
    return $Attribute.Value
}

function Resolve-VBoxLocation {
    param(
        [Parameter(Mandatory = $true)][string]$VBoxDirectory,
        [Parameter(Mandatory = $true)][string]$Location
    )

    $Native = $Location.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    if ([System.IO.Path]::IsPathRooted($Native)) {
        return Get-FullPath -Path $Native
    }
    return Get-FullPath -Path (Join-Path $VBoxDirectory $Native)
}

function Get-ColonValue {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Key
    )

    $Pattern = '^\s*' + [regex]::Escape($Key) + ':\s*(?<value>.+?)\s*$'
    $Matches = @($Lines | Where-Object { $_ -match $Pattern })
    if ($Matches.Count -ne 1) {
        throw "medium field count mismatch: $Key count=$($Matches.Count)"
    }
    return [regex]::Match($Matches[0], $Pattern).Groups['value'].Value
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

$script:Resource = (
    Resolve-Path -LiteralPath $ResourceRoot -ErrorAction Stop
).Path
$script:VBox = (
    Resolve-Path -LiteralPath $VBoxManagePath -ErrorAction Stop
).Path
$VerificationReport = (
    Resolve-Path -LiteralPath $VerificationReportPath -ErrorAction Stop
).Path
$Bundle = (
    Resolve-Path -LiteralPath $RecoveryRoot -ErrorAction Stop
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
Assert-PathEquals -Observed $Bundle -Expected $ExpectedRecoveryRoot -Label 'recovery root'
foreach ($ForbiddenRoot in @($script:Resource, $Bundle, $LiveVmRoot)) {
    Assert-OutsideRoot -Path $Output -Root $ForbiddenRoot -Label 'route report'
}
if (Test-Path -LiteralPath $Output) {
    throw "route report already exists: $Output"
}

$VerificationIdentity = Assert-ExactHashFile `
    -Path $VerificationReport `
    -SHA256 $ExpectedVerificationReportHash `
    -Label 'sealed bundle verification report'
$VerificationLines = [System.IO.File]::ReadAllLines($VerificationReport)
Assert-UniqueLine `
    -Lines $VerificationLines `
    -Expected 'TEMPLEOSTS 1.10 CONFIGURATION-EXACT RECOVERY BUNDLE VERIFICATION'
foreach ($Field in @(
    @('resource_commit', $ExpectedResourceCommit),
    @('manifest_sha256', $ExpectedManifestHash),
    @('target_name', $ExpectedTargetName),
    @('target_uuid', $ExpectedTargetUuid),
    @('vm_state', 'poweroff'),
    @('running_target_rows', '0'),
    @('snapshot_rows', '0'),
    @('shared_folder_rows', '0'),
    @('bundle_root', $ExpectedRecoveryRoot),
    @('bundle_file_count', '10'),
    @('bundle_vbox_sha256', $ExpectedLiveVBoxHash),
    @('bundle_vbox_file_id', $ExpectedBundleVBoxFileId),
    @('bundle_vdi_sha256', $ExpectedVdiHash),
    @('bundle_vdi_file_id', $ExpectedBundleVdiFileId),
    @('CONFIGURATION-EXACT BUNDLE', 'VERIFIED'),
    @('BUNDLE IDENTITY', 'SEALED'),
    @('POWERED-OFF RECOVERY POINT', 'NOT-SEALED'),
    @('RESTORE ROUTE', 'UNRESOLVED'),
    @('RESTORE EXECUTION', 'NOT-OBSERVED'),
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
$BundleVBoxFileId = Get-FileId -Path $BundleVBox.Path -Label 'bundle VBOX'
$BundleVdiFileId = Get-FileId -Path $BundleVdi.Path -Label 'bundle VDI'
if ($BundleVBoxFileId -cne $ExpectedBundleVBoxFileId) {
    throw "bundle VBOX file ID mismatch: $BundleVBoxFileId"
}
if ($BundleVdiFileId -cne $ExpectedBundleVdiFileId) {
    throw "bundle VDI file ID mismatch: $BundleVdiFileId"
}

$Document = [System.Xml.XmlDocument]::new()
$Document.PreserveWhitespace = $true
$Document.Load($BundleVBox.Path)
$MachineNodes = @($Document.SelectNodes("//*[local-name()='Machine']"))
if ($MachineNodes.Count -ne 1) {
    throw "bundle VBOX machine-node count mismatch: $($MachineNodes.Count)"
}
$MachineNode = $MachineNodes[0]
$BundleMachineName = Get-RequiredAttribute -Node $MachineNode -Name 'name' -Label 'Machine'
$BundleMachineUuid = ConvertTo-NormalizedUuid `
    -Value (Get-RequiredAttribute -Node $MachineNode -Name 'uuid' -Label 'Machine') `
    -Label 'bundle machine UUID'
if ($BundleMachineName -cne $ExpectedTargetName -or $BundleMachineUuid -cne $ExpectedTargetUuid) {
    throw "bundle machine identity mismatch: name=$BundleMachineName UUID=$BundleMachineUuid"
}

$HardDiskNodes = @(
    $Document.SelectNodes(
        "//*[local-name()='MediaRegistry']/*[local-name()='HardDisks']//*[local-name()='HardDisk']"
    )
)
$MatchingHardDisks = @(
    $HardDiskNodes | Where-Object {
        (ConvertTo-NormalizedUuid `
            -Value (Get-RequiredAttribute -Node $_ -Name 'uuid' -Label 'HardDisk') `
            -Label 'hard-disk UUID') -ceq $ExpectedVdiUuid
    }
)
if ($MatchingHardDisks.Count -ne 1) {
    throw "bundle VBOX expected hard-disk row count mismatch: $($MatchingHardDisks.Count)"
}
$HardDiskLocationRaw = Get-RequiredAttribute `
    -Node $MatchingHardDisks[0] `
    -Name 'location' `
    -Label 'HardDisk'
$HardDiskLocationResolved = Resolve-VBoxLocation `
    -VBoxDirectory $Bundle `
    -Location $HardDiskLocationRaw
Assert-PathEquals `
    -Observed $HardDiskLocationResolved `
    -Expected $BundleVdi.Path `
    -Label 'bundle VDI XML location'

$DvdImageNodes = @(
    $Document.SelectNodes(
        "//*[local-name()='MediaRegistry']/*[local-name()='DVDImages']/*[local-name()='Image']"
    )
)
$MatchingDvdImages = @(
    $DvdImageNodes | Where-Object {
        (ConvertTo-NormalizedUuid `
            -Value (Get-RequiredAttribute -Node $_ -Name 'uuid' -Label 'DVD Image') `
            -Label 'DVD-image UUID') -ceq $ExpectedIsoUuid
    }
)
if ($MatchingDvdImages.Count -ne 1) {
    throw "bundle VBOX expected DVD-image row count mismatch: $($MatchingDvdImages.Count)"
}
$IsoLocationRaw = Get-RequiredAttribute `
    -Node $MatchingDvdImages[0] `
    -Name 'location' `
    -Label 'DVD Image'
$IsoLocationResolved = Resolve-VBoxLocation `
    -VBoxDirectory $Bundle `
    -Location $IsoLocationRaw
$IsoLocationClass = 'OTHER'
if ([string]::Equals(
    $IsoLocationResolved,
    (Get-FullPath -Path $ExpectedLiveIsoPath),
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    $IsoLocationClass = 'LIVE-ABSOLUTE'
}
elseif ([string]::Equals(
    $IsoLocationResolved,
    (Get-FullPath -Path $BundleIso.Path),
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    $IsoLocationClass = 'BUNDLE-LOCAL'
}

$AttachedDevices = @($Document.SelectNodes("//*[local-name()='AttachedDevice']"))
$HardDiskAttachments = @(
    foreach ($Device in $AttachedDevices) {
        if ((Get-RequiredAttribute -Node $Device -Name 'type' -Label 'AttachedDevice') -cne 'HardDisk') {
            continue
        }
        $Images = @($Device.SelectNodes("./*[local-name()='Image']"))
        if ($Images.Count -ne 1) {
            throw "hard-disk attachment image count mismatch: $($Images.Count)"
        }
        [pscustomobject]@{
            Port = Get-RequiredAttribute -Node $Device -Name 'port' -Label 'HardDisk AttachedDevice'
            Device = Get-RequiredAttribute -Node $Device -Name 'device' -Label 'HardDisk AttachedDevice'
            UUID = ConvertTo-NormalizedUuid `
                -Value (Get-RequiredAttribute -Node $Images[0] -Name 'uuid' -Label 'HardDisk Image') `
                -Label 'hard-disk attachment UUID'
        }
    }
)
$DvdAttachments = @(
    foreach ($Device in $AttachedDevices) {
        if ((Get-RequiredAttribute -Node $Device -Name 'type' -Label 'AttachedDevice') -cne 'DVD') {
            continue
        }
        $Images = @($Device.SelectNodes("./*[local-name()='Image']"))
        if ($Images.Count -ne 1) {
            throw "DVD attachment image count mismatch: $($Images.Count)"
        }
        [pscustomobject]@{
            Port = Get-RequiredAttribute -Node $Device -Name 'port' -Label 'DVD AttachedDevice'
            Device = Get-RequiredAttribute -Node $Device -Name 'device' -Label 'DVD AttachedDevice'
            UUID = ConvertTo-NormalizedUuid `
                -Value (Get-RequiredAttribute -Node $Images[0] -Name 'uuid' -Label 'DVD Image') `
                -Label 'DVD attachment UUID'
        }
    }
)
$ExpectedHardDiskAttachments = @(
    $HardDiskAttachments | Where-Object {
        $_.Port -ceq '1' -and $_.Device -ceq '0' -and $_.UUID -ceq $ExpectedVdiUuid
    }
)
$ExpectedDvdAttachments = @(
    $DvdAttachments | Where-Object {
        $_.Port -ceq '0' -and $_.Device -ceq '1' -and $_.UUID -ceq $ExpectedIsoUuid
    }
)
if ($ExpectedHardDiskAttachments.Count -ne 1 -or $HardDiskAttachments.Count -ne 1) {
    throw "bundle hard-disk attachment contract mismatch: expected=$($ExpectedHardDiskAttachments.Count) total=$($HardDiskAttachments.Count)"
}
if ($ExpectedDvdAttachments.Count -ne 1 -or $DvdAttachments.Count -ne 1) {
    throw "bundle DVD attachment contract mismatch: expected=$($ExpectedDvdAttachments.Count) total=$($DvdAttachments.Count)"
}

$Version = @(Invoke-VBoxReadOnly -Arguments @('--version') -Label 'VirtualBox version')
if ($Version.Count -ne 1 -or $Version[0] -cne $ExpectedVBoxVersion) {
    throw "VirtualBox version mismatch: observed=$($Version -join ' | ') expected=$ExpectedVBoxVersion"
}
$Registered = @(Invoke-VBoxReadOnly -Arguments @('list', 'vms') -Label 'registered VM inventory')
$Running = @(Invoke-VBoxReadOnly -Arguments @('list', 'runningvms') -Label 'running VM inventory')
$TargetPattern = (
    '^"' + [regex]::Escape($ExpectedTargetName) + '" \{' +
    [regex]::Escape($ExpectedTargetUuid) + '\}$'
)
if (@($Registered | Where-Object { $_ -match $TargetPattern }).Count -ne 1) {
    throw 'live registered target identity mismatch'
}
$RunningTargetPattern = '^"' + [regex]::Escape($ExpectedTargetName) + '" '
if (@($Running | Where-Object { $_ -match $RunningTargetPattern }).Count -ne 0) {
    throw 'live target is currently listed as running'
}
$Show = @(
    Invoke-VBoxReadOnly `
        -Arguments @('showvminfo', $ExpectedTargetUuid, '--machinereadable') `
        -Label 'live target showvminfo'
)
$LiveInfo = ConvertFrom-VBoxMachineReadable -Lines $Show
Assert-MachineValue -Info $LiveInfo -Key 'name' -Expected $ExpectedTargetName
Assert-MachineValue -Info $LiveInfo -Key 'UUID' -Expected $ExpectedTargetUuid
Assert-MachineValue -Info $LiveInfo -Key 'VMState' -Expected 'poweroff'
Assert-MachineValue -Info $LiveInfo -Key 'CfgFile' -Expected $ExpectedLiveVBoxPath
Assert-MachineValue -Info $LiveInfo -Key 'IDE-1-0' -Expected $ExpectedLiveVdiPath
Assert-MachineValue -Info $LiveInfo -Key 'IDE-0-1' -Expected $ExpectedLiveIsoPath
$SharedKeys = @(
    $LiveInfo.Keys | Where-Object {
        $_ -like 'SharedFolderNameMachineMapping*' -or
        $_ -like 'SharedFolderPathMachineMapping*'
    }
)
if ($SharedKeys.Count -ne 0) {
    throw "live target shared-folder keys are not zero: $($SharedKeys.Count)"
}
$Snapshots = @(
    Invoke-VBoxSnapshotInventory `
        -Uuid $ExpectedTargetUuid `
        -Label 'live target snapshot inventory'
)
$SnapshotRows = @(
    $Snapshots | Where-Object { $_ -match '^Snapshot(Name|UUID|Node)' }
)
if ($SnapshotRows.Count -ne 0) {
    throw "live target snapshot rows are not zero: $($SnapshotRows.Count)"
}

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
$LiveVdiFileId = Get-FileId -Path $LiveVdi.Path -Label 'live VDI'
if ($LiveVdiFileId -cne $ExpectedLiveVdiFileId) {
    throw "live VDI file ID mismatch: $LiveVdiFileId"
}
if ($BundleVdiFileId -ceq $LiveVdiFileId) {
    throw 'bundle and live VDI unexpectedly share one NTFS file ID'
}

$LiveVdiMedium = @(
    Invoke-VBoxReadOnly `
        -Arguments @('showmediuminfo', 'disk', $ExpectedLiveVdiPath) `
        -Label 'live VDI medium info'
)
$LiveIsoMedium = @(
    Invoke-VBoxReadOnly `
        -Arguments @('showmediuminfo', 'dvd', $ExpectedLiveIsoPath) `
        -Label 'live ISO medium info'
)
$LiveVdiUuid = ConvertTo-NormalizedUuid `
    -Value (Get-ColonValue -Lines $LiveVdiMedium -Key 'UUID') `
    -Label 'live VDI medium UUID'
$LiveIsoUuid = ConvertTo-NormalizedUuid `
    -Value (Get-ColonValue -Lines $LiveIsoMedium -Key 'UUID') `
    -Label 'live ISO medium UUID'
if ($LiveVdiUuid -cne $ExpectedVdiUuid) {
    throw "live VDI UUID mismatch: $LiveVdiUuid"
}
if ($LiveIsoUuid -cne $ExpectedIsoUuid) {
    throw "live ISO UUID mismatch: $LiveIsoUuid"
}

$CurrentRegistryMachineCollision = $BundleMachineUuid -ceq $ExpectedTargetUuid
$CurrentRegistryDiskCollision = $ExpectedVdiUuid -ceq $LiveVdiUuid
$CurrentRegistryIsoIdentityReuse = $ExpectedIsoUuid -ceq $LiveIsoUuid
if (-not $CurrentRegistryMachineCollision -or -not $CurrentRegistryDiskCollision) {
    throw 'expected current-registry identity collisions were not proven'
}

$IsoRewriteRequirement = 'UNRESOLVED'
if ($IsoLocationClass -ceq 'LIVE-ABSOLUTE') {
    $IsoRewriteRequirement = 'DISPOSABLE-COPY-PATH-REWRITE-REQUIRED'
}
elseif ($IsoLocationClass -ceq 'BUNDLE-LOCAL') {
    $IsoRewriteRequirement = 'NOT-REQUIRED'
}
else {
    $IsoRewriteRequirement = 'UNRECOGNIZED-LOCATION-DENIED'
}

$OutputParent = Split-Path -Parent $Output
if ($OutputParent) {
    [void][System.IO.Directory]::CreateDirectory($OutputParent)
}

$Report = [System.Collections.Generic.List[string]]::new()
$Report.Add('DBYTE-HOLYC-OPT')
$Report.Add('TEMPLEOSTS 1.10 RESTORE ROUTE ADJUDICATION')
$Report.Add('')
$Report.Add("verification_report_sha256`t$($VerificationIdentity.SHA256)")
$Report.Add("resource_commit`t$ExpectedResourceCommit")
$Report.Add("virtualbox_version`t$ExpectedVBoxVersion")
$Report.Add('')
$Report.Add("target_name`t$ExpectedTargetName")
$Report.Add("target_uuid`t$ExpectedTargetUuid")
$Report.Add("target_state`tpoweroff")
$Report.Add("running_target_rows`t0")
$Report.Add("snapshot_rows`t0")
$Report.Add("shared_folder_rows`t0")
$Report.Add('')
$Report.Add("bundle_root`t$Bundle")
$Report.Add("bundle_manifest_sha256`t$($BundleManifest.SHA256)")
$Report.Add("bundle_vbox_sha256`t$($BundleVBox.SHA256)")
$Report.Add("bundle_vbox_file_id`t$BundleVBoxFileId")
$Report.Add("bundle_vdi_sha256`t$($BundleVdi.SHA256)")
$Report.Add("bundle_vdi_file_id`t$BundleVdiFileId")
$Report.Add("bundle_iso_sha256`t$($BundleIso.SHA256)")
$Report.Add('')
$Report.Add("bundle_machine_name`t$BundleMachineName")
$Report.Add("bundle_machine_uuid`t$BundleMachineUuid")
$Report.Add("bundle_vdi_uuid`t$ExpectedVdiUuid")
$Report.Add("bundle_vdi_location_raw`t$HardDiskLocationRaw")
$Report.Add("bundle_vdi_location_resolved`t$HardDiskLocationResolved")
$Report.Add("bundle_iso_uuid`t$ExpectedIsoUuid")
$Report.Add("bundle_iso_location_raw`t$IsoLocationRaw")
$Report.Add("bundle_iso_location_resolved`t$IsoLocationResolved")
$Report.Add("bundle_iso_location_class`t$IsoLocationClass")
$Report.Add("isolated_rehearsal_iso_rewrite`t$IsoRewriteRequirement")
$Report.Add('')
$Report.Add("live_vbox_sha256`t$($LiveVBox.SHA256)")
$Report.Add("live_vdi_sha256`t$($LiveVdi.SHA256)")
$Report.Add("live_vdi_file_id`t$LiveVdiFileId")
$Report.Add("live_vdi_uuid`t$LiveVdiUuid")
$Report.Add("live_iso_sha256`t$($LiveIso.SHA256)")
$Report.Add("live_iso_uuid`t$LiveIsoUuid")
$Report.Add('')
$Report.Add("current_registry_machine_uuid_collision`t$CurrentRegistryMachineCollision")
$Report.Add("current_registry_disk_uuid_collision`t$CurrentRegistryDiskCollision")
$Report.Add("current_registry_iso_identity_reuse`t$CurrentRegistryIsoIdentityReuse")
$Report.Add('')
$Report.Add('Current-registry side-by-side registration would collide with the registered machine UUID and VDI UUID.')
$Report.Add('The sealed bundle VBOX must not be registered directly because sealed evidence files must remain immutable.')
$Report.Add('An in-place cold restore route is structurally defined by the exact original machine, medium UUIDs and paths, but it is destructive and is not authorized.')
$Report.Add('The only authorized next proof route is an isolated VBOX_USER_HOME rehearsal using disposable copies of the sealed bundle.')
$Report.Add('The disposable rehearsal must never register, rewrite or boot the sealed source files directly.')
$Report.Add('No registration, unregistration, medium operation, VM start, snapshot mutation, attachment change or restore occurred.')
$Report.Add('')
$Report.Add("CURRENT REGISTRY SIDE-BY-SIDE`tDENIED-IDENTITY-COLLISION")
$Report.Add("SEALED BUNDLE DIRECT USE`tDENIED-IMMUTABLE-EVIDENCE")
$Report.Add("IN-PLACE COLD RESTORE`tDEFINED-NOT-AUTHORIZED")
$Report.Add("ISOLATED DISPOSABLE REHEARSAL`tCANDIDATE-NOT-PREPARED")
$Report.Add("RESTORE ROUTE`tADJUDICATED")
$Report.Add("RESTORE EXECUTION`tNOT-OBSERVED")
$Report.Add("POWERED-OFF RECOVERY POINT`tNOT-SEALED")
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

Write-Host "VERIFICATION REPORT:  $($VerificationIdentity.SHA256)"
Write-Host "BUNDLE MACHINE UUID:  $BundleMachineUuid"
Write-Host "BUNDLE VDI UUID:      $ExpectedVdiUuid"
Write-Host "BUNDLE VDI LOCATION:  $HardDiskLocationResolved"
Write-Host "BUNDLE ISO UUID:      $ExpectedIsoUuid"
Write-Host "BUNDLE ISO LOCATION:  $IsoLocationResolved"
Write-Host "ISO LOCATION CLASS:   $IsoLocationClass"
Write-Host "ISO REWRITE:          $IsoRewriteRequirement"
Write-Host "MACHINE COLLISION:    $CurrentRegistryMachineCollision"
Write-Host "DISK UUID COLLISION:  $CurrentRegistryDiskCollision"
Write-Host "ISO IDENTITY REUSE:   $CurrentRegistryIsoIdentityReuse"
Write-Host "REPORT:               $Output"
Write-Host "REPORT SHA256:        $OutputHash"
Write-Host 'CURRENT REGISTRY:     SIDE-BY-SIDE DENIED'
Write-Host 'SEALED BUNDLE:        DIRECT USE DENIED'
Write-Host 'IN-PLACE RESTORE:     DEFINED / NOT-AUTHORIZED'
Write-Host 'ISOLATED REHEARSAL:   CANDIDATE / NOT-PREPARED'
Write-Host 'RESTORE EXECUTION:    NOT-OBSERVED'
Write-Host 'RECOVERY POINT:       NOT-SEALED'
Write-Host 'BUILD:                NOT-AUTHORIZED'
Write-Host 'VERDICT:              RESTORE ROUTE ADJUDICATION COMPLETE'
