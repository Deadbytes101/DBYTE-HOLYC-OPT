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
    [string]$RouteReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RecoveryRoot,

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
    '887D93D1869CA321A8A4A11816A7ABA6A74366BBA64D4138E1D7DF223F7A9CEC'
$ExpectedRouteReportHash =
    '8AD50F9DB56C228B1D1CF1366D2A34D9F3413DA8B2CD043B6971FB9004ED9AC4'
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

function Assert-DisjointRoots {
    param(
        [Parameter(Mandatory = $true)][string]$Left,
        [Parameter(Mandatory = $true)][string]$Right,
        [Parameter(Mandatory = $true)][string]$Label
    )

    Assert-OutsideRoot -Path $Left -Root $Right -Label $Label
    Assert-OutsideRoot -Path $Right -Root $Left -Label $Label
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

function Invoke-VBox {
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
        throw "machine field missing: $Key"
    }
    $Observed = [string]$Info[$Key]
    if (-not [string]::Equals(
        $Observed,
        $Expected,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "machine field mismatch: $Key=$Observed expected=$Expected"
    }
}

function ConvertTo-NormalizedUuid {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
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
    throw "$Label: VBoxSVC did not exit; PIDs=$($Remaining.Id -join ',')"
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
        [Parameter(Mandatory = $true)][string[]]$Show,
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
    $RunningPattern = '^"' + [regex]::Escape($ExpectedTargetName) + '" '
    if (@($NonEmptyRunning | Where-Object { $_ -match $RunningPattern }).Count -ne 0) {
        throw "$Label target is listed as running"
    }
    if ($NonEmptyRunning.Count -ne 0) {
        throw "$Label registry contains an unexpected running VM"
    }

    $Info = ConvertFrom-VBoxMachineReadable -Lines $Show
    Assert-MachineValue -Info $Info -Key 'name' -Expected $ExpectedTargetName
    Assert-MachineValue -Info $Info -Key 'UUID' -Expected $ExpectedTargetUuid
    Assert-MachineValue -Info $Info -Key 'VMState' -Expected 'poweroff'
    Assert-MachineValue -Info $Info -Key 'CfgFile' -Expected $ExpectedConfig
    Assert-MachineValue -Info $Info -Key 'IDE-1-0' -Expected $ExpectedVdi
    Assert-MachineValue -Info $Info -Key 'IDE-0-1' -Expected $ExpectedIso

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

function Get-VBoxXmlContract {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedVdiPath,
        [Parameter(Mandatory = $true)][string]$ExpectedIsoPath,
        [switch]$RewriteIsoToLocal
    )

    $Document = [System.Xml.XmlDocument]::new()
    $Document.PreserveWhitespace = $true
    $Document.Load($Path)

    $MachineNodes = @($Document.SelectNodes("//*[local-name()='Machine']"))
    if ($MachineNodes.Count -ne 1) {
        throw "VBOX machine-node count mismatch: $($MachineNodes.Count)"
    }
    $Machine = $MachineNodes[0]
    $MachineName = Get-RequiredAttribute -Node $Machine -Name 'name' -Label 'Machine'
    $MachineUuid = ConvertTo-NormalizedUuid `
        -Value (Get-RequiredAttribute -Node $Machine -Name 'uuid' -Label 'Machine') `
        -Label 'machine UUID'
    if ($MachineName -cne $ExpectedTargetName -or $MachineUuid -cne $ExpectedTargetUuid) {
        throw "VBOX machine identity mismatch: name=$MachineName UUID=$MachineUuid"
    }

    $HardDisks = @(
        $Document.SelectNodes(
            "//*[local-name()='MediaRegistry']/*[local-name()='HardDisks']//*[local-name()='HardDisk']"
        ) | Where-Object {
            (ConvertTo-NormalizedUuid `
                -Value (Get-RequiredAttribute -Node $_ -Name 'uuid' -Label 'HardDisk') `
                -Label 'hard-disk UUID') -ceq $ExpectedVdiUuid
        }
    )
    if ($HardDisks.Count -ne 1) {
        throw "VBOX expected hard-disk row count mismatch: $($HardDisks.Count)"
    }
    $VdiLocationRaw = Get-RequiredAttribute `
        -Node $HardDisks[0] `
        -Name 'location' `
        -Label 'HardDisk'
    $VdiResolved = Resolve-VBoxLocation `
        -VBoxDirectory (Split-Path -Parent $Path) `
        -Location $VdiLocationRaw
    Assert-PathEquals -Observed $VdiResolved -Expected $ExpectedVdiPath -Label 'VBOX VDI location'

    $DvdImages = @(
        $Document.SelectNodes(
            "//*[local-name()='MediaRegistry']/*[local-name()='DVDImages']/*[local-name()='Image']"
        ) | Where-Object {
            (ConvertTo-NormalizedUuid `
                -Value (Get-RequiredAttribute -Node $_ -Name 'uuid' -Label 'DVD Image') `
                -Label 'DVD-image UUID') -ceq $ExpectedIsoUuid
        }
    )
    if ($DvdImages.Count -ne 1) {
        throw "VBOX expected DVD-image row count mismatch: $($DvdImages.Count)"
    }
    $IsoAttribute = $DvdImages[0].Attributes['location']
    if ($null -eq $IsoAttribute -or [string]::IsNullOrWhiteSpace($IsoAttribute.Value)) {
        throw 'VBOX DVD Image location is missing'
    }
    $IsoLocationBefore = $IsoAttribute.Value
    $IsoResolvedBefore = Resolve-VBoxLocation `
        -VBoxDirectory (Split-Path -Parent $Path) `
        -Location $IsoLocationBefore

    if ($RewriteIsoToLocal) {
        Assert-PathEquals `
            -Observed $IsoResolvedBefore `
            -Expected $ExpectedLiveIsoPath `
            -Label 'pre-rewrite VBOX ISO location'
        $IsoAttribute.Value = [System.IO.Path]::GetFileName($ExpectedIsoPath)
        $WriterSettings = [System.Xml.XmlWriterSettings]::new()
        $WriterSettings.Encoding = [System.Text.UTF8Encoding]::new($false)
        $WriterSettings.Indent = $false
        $WriterSettings.NewLineHandling = [System.Xml.NewLineHandling]::None
        $Writer = [System.Xml.XmlWriter]::Create($Path, $WriterSettings)
        try {
            $Document.Save($Writer)
        }
        finally {
            $Writer.Dispose()
        }
        return Get-VBoxXmlContract `
            -Path $Path `
            -ExpectedVdiPath $ExpectedVdiPath `
            -ExpectedIsoPath $ExpectedIsoPath
    }

    Assert-PathEquals `
        -Observed $IsoResolvedBefore `
        -Expected $ExpectedIsoPath `
        -Label 'VBOX ISO location'

    $Attachments = @($Document.SelectNodes("//*[local-name()='AttachedDevice']"))
    $HardDiskAttachments = @(
        foreach ($Device in $Attachments) {
            if ((Get-RequiredAttribute -Node $Device -Name 'type' -Label 'AttachedDevice') -cne 'HardDisk') {
                continue
            }
            $Images = @($Device.SelectNodes("./*[local-name()='Image']"))
            if ($Images.Count -ne 1) {
                throw "hard-disk attachment image count mismatch: $($Images.Count)"
            }
            [pscustomobject]@{
                Port = Get-RequiredAttribute -Node $Device -Name 'port' -Label 'HardDisk attachment'
                Device = Get-RequiredAttribute -Node $Device -Name 'device' -Label 'HardDisk attachment'
                UUID = ConvertTo-NormalizedUuid `
                    -Value (Get-RequiredAttribute -Node $Images[0] -Name 'uuid' -Label 'HardDisk Image') `
                    -Label 'hard-disk attachment UUID'
            }
        }
    )
    $DvdAttachments = @(
        foreach ($Device in $Attachments) {
            if ((Get-RequiredAttribute -Node $Device -Name 'type' -Label 'AttachedDevice') -cne 'DVD') {
                continue
            }
            $Images = @($Device.SelectNodes("./*[local-name()='Image']"))
            if ($Images.Count -ne 1) {
                throw "DVD attachment image count mismatch: $($Images.Count)"
            }
            [pscustomobject]@{
                Port = Get-RequiredAttribute -Node $Device -Name 'port' -Label 'DVD attachment'
                Device = Get-RequiredAttribute -Node $Device -Name 'device' -Label 'DVD attachment'
                UUID = ConvertTo-NormalizedUuid `
                    -Value (Get-RequiredAttribute -Node $Images[0] -Name 'uuid' -Label 'DVD Image') `
                    -Label 'DVD attachment UUID'
            }
        }
    )
    if (
        $HardDiskAttachments.Count -ne 1 -or
        $HardDiskAttachments[0].Port -cne '1' -or
        $HardDiskAttachments[0].Device -cne '0' -or
        $HardDiskAttachments[0].UUID -cne $ExpectedVdiUuid
    ) {
        throw 'VBOX hard-disk attachment contract mismatch'
    }
    if (
        $DvdAttachments.Count -ne 1 -or
        $DvdAttachments[0].Port -cne '0' -or
        $DvdAttachments[0].Device -cne '1' -or
        $DvdAttachments[0].UUID -cne $ExpectedIsoUuid
    ) {
        throw 'VBOX DVD attachment contract mismatch'
    }

    return [pscustomobject]@{
        MachineName = $MachineName
        MachineUUID = $MachineUuid
        VdiUUID = $ExpectedVdiUuid
        IsoUUID = $ExpectedIsoUuid
        VdiPath = $VdiResolved
        IsoPath = $IsoResolvedBefore
    }
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
$RouteReport = (
    Resolve-Path -LiteralPath $RouteReportPath -ErrorAction Stop
).Path
$Bundle = (
    Resolve-Path -LiteralPath $RecoveryRoot -ErrorAction Stop
).Path
$Rehearsal = Get-FullPath -Path $RehearsalRoot
$Output = Get-FullPath -Path $OutPath
$LiveVmRoot = Split-Path -Parent $ExpectedLiveVBoxPath

if (-not (Test-Path -LiteralPath $script:Resource -PathType Container)) {
    throw "resource root is not a directory: $script:Resource"
}
if (-not (Test-Path -LiteralPath $script:VBox -PathType Leaf)) {
    throw "VBoxManage is not a file: $script:VBox"
}
if (-not (Test-Path -LiteralPath $Bundle -PathType Container)) {
    throw "bundle root is not a directory: $Bundle"
}
Assert-PathEquals -Observed $Bundle -Expected $ExpectedRecoveryRoot -Label 'bundle root'
foreach ($Protected in @($script:Resource, $Bundle, $LiveVmRoot)) {
    Assert-DisjointRoots -Left $Rehearsal -Right $Protected -Label 'rehearsal root'
    Assert-OutsideRoot -Path $Output -Root $Protected -Label 'preparation report'
}
Assert-OutsideRoot -Path $Output -Root $Rehearsal -Label 'preparation report'
if (Test-Path -LiteralPath $Rehearsal) {
    throw "rehearsal root already exists: $Rehearsal"
}
if (Test-Path -LiteralPath $Output) {
    throw "preparation report already exists: $Output"
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
    -Label 'bundle verification report'
$RouteIdentity = Assert-ExactHashFile `
    -Path $RouteReport `
    -SHA256 $ExpectedRouteReportHash `
    -Label 'restore route report'
$RouteLines = [System.IO.File]::ReadAllLines($RouteReport)
Assert-UniqueLine -Lines $RouteLines -Expected 'TEMPLEOSTS 1.10 RESTORE ROUTE ADJUDICATION'
foreach ($Field in @(
    @('verification_report_sha256', $ExpectedVerificationReportHash),
    @('resource_commit', $ExpectedResourceCommit),
    @('target_uuid', $ExpectedTargetUuid),
    @('target_state', 'poweroff'),
    @('current_registry_machine_uuid_collision', 'True'),
    @('current_registry_disk_uuid_collision', 'True'),
    @('bundle_iso_location_class', 'LIVE-ABSOLUTE'),
    @('isolated_rehearsal_iso_rewrite', 'DISPOSABLE-COPY-PATH-REWRITE-REQUIRED'),
    @('CURRENT REGISTRY SIDE-BY-SIDE', 'DENIED-IDENTITY-COLLISION'),
    @('SEALED BUNDLE DIRECT USE', 'DENIED-IMMUTABLE-EVIDENCE'),
    @('IN-PLACE COLD RESTORE', 'DEFINED-NOT-AUTHORIZED'),
    @('ISOLATED DISPOSABLE REHEARSAL', 'CANDIDATE-NOT-PREPARED'),
    @('BUILD EXECUTION', 'NOT-AUTHORIZED')
)) {
    Assert-FieldEquals -Lines $RouteLines -Key $Field[0] -Expected $Field[1]
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
if ((Get-FileId -Path $BundleVBox.Path -Label 'bundle VBOX') -cne $ExpectedBundleVBoxFileId) {
    throw 'bundle VBOX file ID mismatch'
}
if ((Get-FileId -Path $BundleVdi.Path -Label 'bundle VDI') -cne $ExpectedBundleVdiFileId) {
    throw 'bundle VDI file ID mismatch'
}

Wait-VBoxServiceExit -Label 'preflight default registry service isolation'
$VersionBefore = @(Invoke-VBox -Arguments @('--version') -Label 'default VirtualBox version')
if ($VersionBefore.Count -ne 1 -or $VersionBefore[0] -cne $ExpectedVBoxVersion) {
    throw "VirtualBox version mismatch: $($VersionBefore -join ' | ')"
}
$RegisteredBefore = @(Invoke-VBox -Arguments @('list', 'vms') -Label 'default registered inventory')
$RunningBefore = @(Invoke-VBox -Arguments @('list', 'runningvms') -Label 'default running inventory')
$ShowBefore = @(
    Invoke-VBox `
        -Arguments @('showvminfo', $ExpectedTargetUuid, '--machinereadable') `
        -Label 'default target showvminfo'
)
[void](Assert-TargetState `
    -Registered $RegisteredBefore `
    -Running $RunningBefore `
    -Show $ShowBefore `
    -ExpectedConfig $ExpectedLiveVBoxPath `
    -ExpectedVdi $ExpectedLiveVdiPath `
    -ExpectedIso $ExpectedLiveIsoPath `
    -Label 'default registry before rehearsal')
$SnapshotsBefore = @(
    Invoke-VBoxSnapshotInventory `
        -Uuid $ExpectedTargetUuid `
        -Label 'default target snapshot inventory'
)
if (@($SnapshotsBefore | Where-Object { $_ -match '^Snapshot(Name|UUID|Node)' }).Count -ne 0) {
    throw 'default target snapshot rows are not zero before rehearsal'
}
$LiveVBoxBefore = Assert-ExactHashFile `
    -Path $ExpectedLiveVBoxPath `
    -SHA256 $ExpectedLiveVBoxHash `
    -Label 'live VBOX before rehearsal'
$LiveVdiBefore = Assert-ExactFile `
    -Path $ExpectedLiveVdiPath `
    -Bytes $ExpectedVdiBytes `
    -SHA256 $ExpectedVdiHash `
    -Label 'live VDI before rehearsal'
$LiveIsoBefore = Assert-ExactFile `
    -Path $ExpectedLiveIsoPath `
    -Bytes $ExpectedIsoBytes `
    -SHA256 $ExpectedIsoHash `
    -Label 'live ISO before rehearsal'
if ((Get-FileId -Path $LiveVdiBefore.Path -Label 'live VDI') -cne $ExpectedLiveVdiFileId) {
    throw 'live VDI file ID mismatch before rehearsal'
}
Wait-VBoxServiceExit -Label 'default registry service shutdown before isolated home'

$RootParent = Split-Path -Parent $Rehearsal
if ($RootParent) {
    [void][System.IO.Directory]::CreateDirectory($RootParent)
}
$OutputParent = Split-Path -Parent $Output
if ($OutputParent) {
    [void][System.IO.Directory]::CreateDirectory($OutputParent)
}

try {
    [void][System.IO.Directory]::CreateDirectory($Rehearsal)
    $MachineRoot = Join-Path $Rehearsal 'Machine'
    $IsolatedHome = Join-Path $Rehearsal 'VBoxUserHome'
    [void][System.IO.Directory]::CreateDirectory($MachineRoot)
    [void][System.IO.Directory]::CreateDirectory($IsolatedHome)

    $DisposableVBox = Join-Path $MachineRoot 'Temple1.10.vbox'
    $DisposableVdi = Join-Path $MachineRoot 'Temple1.10.vdi'
    $DisposableIso = Join-Path $MachineRoot 'TempleOSTS.iso'
    $CopiedVerification = Join-Path $Rehearsal 'source-bundle-verification.txt'
    $CopiedRoute = Join-Path $Rehearsal 'source-restore-route-adjudication.txt'
    $CopiedManifest = Join-Path $Rehearsal 'source-bundle-manifest.txt'

    [System.IO.File]::Copy($BundleVBox.Path, $DisposableVBox, $false)
    [System.IO.File]::Copy($BundleVdi.Path, $DisposableVdi, $false)
    [System.IO.File]::Copy($BundleIso.Path, $DisposableIso, $false)
    [System.IO.File]::Copy($VerificationIdentity.Path, $CopiedVerification, $false)
    [System.IO.File]::Copy($RouteIdentity.Path, $CopiedRoute, $false)
    [System.IO.File]::Copy($BundleManifest.Path, $CopiedManifest, $false)

    [void](Assert-ExactHashFile `
        -Path $DisposableVBox `
        -SHA256 $ExpectedLiveVBoxHash `
        -Label 'disposable VBOX before rewrite')
    [void](Assert-ExactFile `
        -Path $DisposableVdi `
        -Bytes $ExpectedVdiBytes `
        -SHA256 $ExpectedVdiHash `
        -Label 'disposable VDI')
    [void](Assert-ExactFile `
        -Path $DisposableIso `
        -Bytes $ExpectedIsoBytes `
        -SHA256 $ExpectedIsoHash `
        -Label 'disposable ISO')
    [void](Assert-ExactHashFile `
        -Path $CopiedVerification `
        -SHA256 $ExpectedVerificationReportHash `
        -Label 'copied verification report')
    [void](Assert-ExactHashFile `
        -Path $CopiedRoute `
        -SHA256 $ExpectedRouteReportHash `
        -Label 'copied route report')
    [void](Assert-ExactHashFile `
        -Path $CopiedManifest `
        -SHA256 $ExpectedManifestHash `
        -Label 'copied bundle manifest')

    $DisposableVdiFileId = Get-FileId -Path $DisposableVdi -Label 'disposable VDI'
    $DisposableIsoFileId = Get-FileId -Path $DisposableIso -Label 'disposable ISO'
    $BundleIsoFileId = Get-FileId -Path $BundleIso.Path -Label 'bundle ISO'
    if (
        $DisposableVdiFileId -ceq $ExpectedBundleVdiFileId -or
        $DisposableVdiFileId -ceq $ExpectedLiveVdiFileId
    ) {
        throw 'disposable VDI is not a distinct NTFS file object'
    }
    if ($DisposableIsoFileId -ceq $BundleIsoFileId) {
        throw 'disposable ISO is not a distinct NTFS file object'
    }

    $ContractBeforeRewrite = Get-VBoxXmlContract `
        -Path $DisposableVBox `
        -ExpectedVdiPath $DisposableVdi `
        -ExpectedIsoPath $ExpectedLiveIsoPath
    $DisposableVBoxPreRewriteHash = (
        Get-FileHash -LiteralPath $DisposableVBox -Algorithm SHA256
    ).Hash
    $ContractAfterRewrite = Get-VBoxXmlContract `
        -Path $DisposableVBox `
        -ExpectedVdiPath $DisposableVdi `
        -ExpectedIsoPath $DisposableIso `
        -RewriteIsoToLocal
    $DisposableVBoxPostRewriteHash = (
        Get-FileHash -LiteralPath $DisposableVBox -Algorithm SHA256
    ).Hash
    if ($DisposableVBoxPostRewriteHash -ceq $DisposableVBoxPreRewriteHash) {
        throw 'disposable VBOX ISO rewrite produced no byte change'
    }

    $HomePreItems = @(Get-ChildItem -LiteralPath $IsolatedHome -Force)
    if ($HomePreItems.Count -ne 0) {
        throw "isolated VBOX_USER_HOME is not empty: $($HomePreItems.Count)"
    }

    [Environment]::SetEnvironmentVariable(
        'VBOX_USER_HOME',
        $IsolatedHome,
        [EnvironmentVariableTarget]::Process
    )
    try {
        $IsolatedVersion = @(Invoke-VBox -Arguments @('--version') -Label 'isolated VirtualBox version')
        if ($IsolatedVersion.Count -ne 1 -or $IsolatedVersion[0] -cne $ExpectedVBoxVersion) {
            throw "isolated VirtualBox version mismatch: $($IsolatedVersion -join ' | ')"
        }
        $IsolatedBefore = @(Invoke-VBox -Arguments @('list', 'vms') -Label 'isolated registry pre-registration')
        $IsolatedBeforeNonEmpty = @($IsolatedBefore | Where-Object { $_ -cne '' })
        if ($IsolatedBeforeNonEmpty.Count -ne 0) {
            throw "isolated registry is not empty: $($IsolatedBeforeNonEmpty -join ' | ')"
        }

        [void](Invoke-VBox `
            -Arguments @('registervm', $DisposableVBox) `
            -Label 'isolated disposable VM registration')

        $IsolatedRegistered = @(Invoke-VBox -Arguments @('list', 'vms') -Label 'isolated registered inventory')
        $IsolatedRunning = @(Invoke-VBox -Arguments @('list', 'runningvms') -Label 'isolated running inventory')
        $IsolatedShow = @(
            Invoke-VBox `
                -Arguments @('showvminfo', $ExpectedTargetUuid, '--machinereadable') `
                -Label 'isolated target showvminfo'
        )
        [void](Assert-TargetState `
            -Registered $IsolatedRegistered `
            -Running $IsolatedRunning `
            -Show $IsolatedShow `
            -ExpectedConfig $DisposableVBox `
            -ExpectedVdi $DisposableVdi `
            -ExpectedIso $DisposableIso `
            -Label 'isolated registry after registration')
        $IsolatedSnapshots = @(
            Invoke-VBoxSnapshotInventory `
                -Uuid $ExpectedTargetUuid `
                -Label 'isolated target snapshot inventory'
        )
        if (@($IsolatedSnapshots | Where-Object { $_ -match '^Snapshot(Name|UUID|Node)' }).Count -ne 0) {
            throw 'isolated target snapshot rows are not zero'
        }

        $IsolatedVdiMedium = @(
            Invoke-VBox `
                -Arguments @('showmediuminfo', 'disk', $DisposableVdi) `
                -Label 'isolated VDI medium info'
        )
        $IsolatedIsoMedium = @(
            Invoke-VBox `
                -Arguments @('showmediuminfo', 'dvd', $DisposableIso) `
                -Label 'isolated ISO medium info'
        )
        $ObservedVdiUuid = ConvertTo-NormalizedUuid `
            -Value (Get-ColonValue -Lines $IsolatedVdiMedium -Key 'UUID') `
            -Label 'isolated VDI UUID'
        $ObservedIsoUuid = ConvertTo-NormalizedUuid `
            -Value (Get-ColonValue -Lines $IsolatedIsoMedium -Key 'UUID') `
            -Label 'isolated ISO UUID'
        if ($ObservedVdiUuid -cne $ExpectedVdiUuid) {
            throw "isolated VDI UUID mismatch: $ObservedVdiUuid"
        }
        if ($ObservedIsoUuid -cne $ExpectedIsoUuid) {
            throw "isolated ISO UUID mismatch: $ObservedIsoUuid"
        }
    }
    finally {
        try {
            Wait-VBoxServiceExit -Label 'isolated registry service shutdown'
        }
        finally {
            [Environment]::SetEnvironmentVariable(
                'VBOX_USER_HOME',
                $OriginalVBoxUserHome,
                [EnvironmentVariableTarget]::Process
            )
        }
    }

    $RegisteredAfter = @(Invoke-VBox -Arguments @('list', 'vms') -Label 'default registered inventory after rehearsal')
    $RunningAfter = @(Invoke-VBox -Arguments @('list', 'runningvms') -Label 'default running inventory after rehearsal')
    $ShowAfter = @(
        Invoke-VBox `
            -Arguments @('showvminfo', $ExpectedTargetUuid, '--machinereadable') `
            -Label 'default target showvminfo after rehearsal'
    )
    [void](Assert-TargetState `
        -Registered $RegisteredAfter `
        -Running $RunningAfter `
        -Show $ShowAfter `
        -ExpectedConfig $ExpectedLiveVBoxPath `
        -ExpectedVdi $ExpectedLiveVdiPath `
        -ExpectedIso $ExpectedLiveIsoPath `
        -Label 'default registry after rehearsal')
    $SnapshotsAfter = @(
        Invoke-VBoxSnapshotInventory `
            -Uuid $ExpectedTargetUuid `
            -Label 'default target snapshot inventory after rehearsal'
    )
    if (@($SnapshotsAfter | Where-Object { $_ -match '^Snapshot(Name|UUID|Node)' }).Count -ne 0) {
        throw 'default target snapshot rows are not zero after rehearsal'
    }
    [void](Assert-ExactHashFile `
        -Path $ExpectedLiveVBoxPath `
        -SHA256 $ExpectedLiveVBoxHash `
        -Label 'live VBOX after rehearsal')
    [void](Assert-ExactFile `
        -Path $ExpectedLiveVdiPath `
        -Bytes $ExpectedVdiBytes `
        -SHA256 $ExpectedVdiHash `
        -Label 'live VDI after rehearsal')
    [void](Assert-ExactFile `
        -Path $ExpectedLiveIsoPath `
        -Bytes $ExpectedIsoBytes `
        -SHA256 $ExpectedIsoHash `
        -Label 'live ISO after rehearsal')
    Wait-VBoxServiceExit -Label 'default registry service shutdown after revalidation'

    $DisposableVBoxPostRegistrationHash = (
        Get-FileHash -LiteralPath $DisposableVBox -Algorithm SHA256
    ).Hash
    $PostRegistrationContract = Get-VBoxXmlContract `
        -Path $DisposableVBox `
        -ExpectedVdiPath $DisposableVdi `
        -ExpectedIsoPath $DisposableIso

    $InventoryRows = [System.Collections.Generic.List[string]]::new()
    $InventoryFiles = @(
        Get-ChildItem -LiteralPath $Rehearsal -Recurse -Force -File |
            Sort-Object FullName
    )
    foreach ($File in $InventoryFiles) {
        $Relative = $File.FullName.Substring($Rehearsal.Length).TrimStart('\', '/')
        $Hash = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash
        $InventoryRows.Add("file`t$Relative`t$($File.Length)`t$Hash")
    }

    $ManifestPath = Join-Path $Rehearsal 'ISOLATED-REHEARSAL-MANIFEST.txt'
    $Manifest = [System.Collections.Generic.List[string]]::new()
    $Manifest.Add('DBYTE-HOLYC-OPT')
    $Manifest.Add('TEMPLEOSTS 1.10 ISOLATED DISPOSABLE RESTORE REHEARSAL')
    $Manifest.Add('')
    $Manifest.Add("created_utc`t$([DateTime]::UtcNow.ToString('o'))")
    $Manifest.Add("resource_commit`t$ExpectedResourceCommit")
    $Manifest.Add("verification_report_sha256`t$ExpectedVerificationReportHash")
    $Manifest.Add("route_report_sha256`t$ExpectedRouteReportHash")
    $Manifest.Add("bundle_manifest_sha256`t$ExpectedManifestHash")
    $Manifest.Add('')
    $Manifest.Add("rehearsal_root`t$Rehearsal")
    $Manifest.Add("isolated_vbox_user_home`t$IsolatedHome")
    $Manifest.Add("machine_name`t$($PostRegistrationContract.MachineName)")
    $Manifest.Add("machine_uuid`t$($PostRegistrationContract.MachineUUID)")
    $Manifest.Add("machine_state`tpoweroff")
    $Manifest.Add("running_rows`t0")
    $Manifest.Add("snapshot_rows`t0")
    $Manifest.Add("shared_folder_rows`t0")
    $Manifest.Add('')
    $Manifest.Add("disposable_vbox_pre_rewrite_sha256`t$DisposableVBoxPreRewriteHash")
    $Manifest.Add("disposable_vbox_post_rewrite_sha256`t$DisposableVBoxPostRewriteHash")
    $Manifest.Add("disposable_vbox_post_registration_sha256`t$DisposableVBoxPostRegistrationHash")
    $Manifest.Add("disposable_vdi_sha256`t$ExpectedVdiHash")
    $Manifest.Add("disposable_vdi_file_id`t$DisposableVdiFileId")
    $Manifest.Add("disposable_vdi_uuid`t$ExpectedVdiUuid")
    $Manifest.Add("disposable_iso_sha256`t$ExpectedIsoHash")
    $Manifest.Add("disposable_iso_file_id`t$DisposableIsoFileId")
    $Manifest.Add("disposable_iso_uuid`t$ExpectedIsoUuid")
    $Manifest.Add("disposable_iso_path`t$DisposableIso")
    $Manifest.Add('')
    foreach ($Row in $InventoryRows) {
        $Manifest.Add($Row)
    }
    $Manifest.Add('')
    $Manifest.Add("ISOLATED REGISTRY`tPREPARED")
    $Manifest.Add("DISPOSABLE VM REGISTRATION`tOBSERVED")
    $Manifest.Add("VM START`tNOT-AUTHORIZED")
    $Manifest.Add("RESTORE BOOT`tNOT-OBSERVED")
    $Manifest.Add("POWERED-OFF RECOVERY POINT`tNOT-SEALED")
    $Manifest.Add("BUILD EXECUTION`tNOT-AUTHORIZED")
    $Manifest.Add('')
    $Manifest.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')
    Write-Utf8Lines -Path $ManifestPath -Lines $Manifest.ToArray()
    $ManifestHash = (Get-FileHash -LiteralPath $ManifestPath -Algorithm SHA256).Hash

    $Report = [System.Collections.Generic.List[string]]::new()
    $Report.Add('DBYTE-HOLYC-OPT')
    $Report.Add('TEMPLEOSTS 1.10 ISOLATED DISPOSABLE RESTORE REHEARSAL PREPARATION')
    $Report.Add('')
    $Report.Add("verification_report_sha256`t$ExpectedVerificationReportHash")
    $Report.Add("route_report_sha256`t$ExpectedRouteReportHash")
    $Report.Add("rehearsal_manifest_sha256`t$ManifestHash")
    $Report.Add("virtualbox_version`t$ExpectedVBoxVersion")
    $Report.Add('')
    $Report.Add("rehearsal_root`t$Rehearsal")
    $Report.Add("isolated_vbox_user_home`t$IsolatedHome")
    $Report.Add("machine_name`t$ExpectedTargetName")
    $Report.Add("machine_uuid`t$ExpectedTargetUuid")
    $Report.Add("machine_state`tpoweroff")
    $Report.Add("running_rows`t0")
    $Report.Add("snapshot_rows`t0")
    $Report.Add("shared_folder_rows`t0")
    $Report.Add('')
    $Report.Add("disposable_vbox_pre_rewrite_sha256`t$DisposableVBoxPreRewriteHash")
    $Report.Add("disposable_vbox_post_rewrite_sha256`t$DisposableVBoxPostRewriteHash")
    $Report.Add("disposable_vbox_post_registration_sha256`t$DisposableVBoxPostRegistrationHash")
    $Report.Add("disposable_vdi_sha256`t$ExpectedVdiHash")
    $Report.Add("disposable_vdi_file_id`t$DisposableVdiFileId")
    $Report.Add("disposable_vdi_uuid`t$ExpectedVdiUuid")
    $Report.Add("disposable_iso_sha256`t$ExpectedIsoHash")
    $Report.Add("disposable_iso_file_id`t$DisposableIsoFileId")
    $Report.Add("disposable_iso_uuid`t$ExpectedIsoUuid")
    $Report.Add("disposable_iso_path`t$DisposableIso")
    $Report.Add('')
    $Report.Add('The sealed bundle remained unchanged and was never registered.')
    $Report.Add('Only disposable copies were rewritten and registered.')
    $Report.Add('The isolated registry was empty before registration and contained exactly one powered-off VM after registration.')
    $Report.Add('The current default registry and live VBOX, VDI and ISO identities were revalidated after isolated registration.')
    $Report.Add('No VM was started and no restore boot, guest delivery or compiler execution occurred.')
    $Report.Add('')
    $Report.Add("ISOLATED REHEARSAL`tPREPARED")
    $Report.Add("ISOLATED REGISTRY`tSEALED-FOR-POWERED-OFF-BOOT-PROOF")
    $Report.Add("DISPOSABLE VM REGISTRATION`tOBSERVED")
    $Report.Add("VM START`tNOT-AUTHORIZED")
    $Report.Add("RESTORE BOOT`tNOT-OBSERVED")
    $Report.Add("POWERED-OFF RECOVERY POINT`tNOT-SEALED")
    $Report.Add("GUEST DELIVERY ROUTE`tUNRESOLVED")
    $Report.Add("BUILD EXECUTION`tNOT-AUTHORIZED")
    $Report.Add('')
    $Report.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')
    Write-Utf8Lines -Path $Output -Lines $Report.ToArray()
    $OutputHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

    Write-Host "ROUTE REPORT:         $ExpectedRouteReportHash"
    Write-Host "REHEARSAL ROOT:       $Rehearsal"
    Write-Host "VBOX USER HOME:       $IsolatedHome"
    Write-Host "MACHINE UUID:         $ExpectedTargetUuid"
    Write-Host "VDI UUID:             $ExpectedVdiUuid"
    Write-Host "ISO UUID:             $ExpectedIsoUuid"
    Write-Host "VBOX PRE-REWRITE:     $DisposableVBoxPreRewriteHash"
    Write-Host "VBOX POST-REWRITE:    $DisposableVBoxPostRewriteHash"
    Write-Host "VBOX POST-REGISTER:   $DisposableVBoxPostRegistrationHash"
    Write-Host "VDI FILE ID:          $DisposableVdiFileId"
    Write-Host "ISO FILE ID:          $DisposableIsoFileId"
    Write-Host "REHEARSAL MANIFEST:   $ManifestHash"
    Write-Host "REPORT:               $Output"
    Write-Host "REPORT SHA256:        $OutputHash"
    Write-Host 'ISOLATED REHEARSAL:   PREPARED'
    Write-Host 'ISOLATED REGISTRY:    SEALED FOR POWERED-OFF BOOT PROOF'
    Write-Host 'DISPOSABLE REGISTER:  OBSERVED'
    Write-Host 'VM START:             NOT-AUTHORIZED'
    Write-Host 'RESTORE BOOT:         NOT-OBSERVED'
    Write-Host 'RECOVERY POINT:       NOT-SEALED'
    Write-Host 'BUILD:                NOT-AUTHORIZED'
    Write-Host 'VERDICT:              ISOLATED DISPOSABLE REHEARSAL PREPARATION COMPLETE'
}
catch {
    if (Test-Path -LiteralPath $Rehearsal -PathType Container) {
        $FailureMarker = Join-Path $Rehearsal 'REHEARSAL-INCOMPLETE.txt'
        if (-not (Test-Path -LiteralPath $FailureMarker)) {
            $FailureLines = @(
                'DBYTE-HOLYC-OPT',
                'TEMPLEOSTS 1.10 ISOLATED REHEARSAL INCOMPLETE',
                '',
                "failed_utc`t$([DateTime]::UtcNow.ToString('o'))",
                "error_type`t$($_.Exception.GetType().FullName)",
                "error_message`t$($_.Exception.Message)",
                '',
                'PRESERVE THIS ROOT FOR REVIEW.',
                'DO NOT TREAT IT AS A RECOVERY POINT.',
                'BUILD EXECUTION REMAINS NOT AUTHORIZED.'
            )
            Write-Utf8Lines -Path $FailureMarker -Lines $FailureLines
        }
        Write-Host "INCOMPLETE REHEARSAL: $Rehearsal"
        Write-Host 'INCOMPLETE REHEARSAL ROOT WAS PRESERVED FOR REVIEW.'
    }
    throw
}
finally {
    [Environment]::SetEnvironmentVariable(
        'VBOX_USER_HOME',
        $OriginalVBoxUserHome,
        [EnvironmentVariableTarget]::Process
    )
}
