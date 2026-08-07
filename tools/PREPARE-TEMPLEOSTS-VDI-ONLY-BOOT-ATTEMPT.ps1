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
    [string]$BootReadinessReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SealedRehearsalRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$BootAttemptRoot,

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
$ExpectedReadinessReportHash =
    'C96EA11818CCEF207D914F165CD6B5822ADFC71B4712E7025371E085D3627461'
$ExpectedRehearsalManifestHash =
    'AC2609C9C6EFC87316835BB6A4174AF5C28FEEE8DCEBD37E0E9D3DADB14D383F'
$ExpectedTargetName = 'Temple1.10'
$ExpectedTargetUuid = '9c98691e-27cd-4487-a306-587969c2c78c'
$ExpectedVdiUuid = '55c1f29d-a681-402e-b90d-bfbb6b09f207'
$ExpectedIsoUuid = 'ab97b3a5-1331-494d-a917-e85b6e728c45'
$ExpectedVBoxVersion = '7.0.12r159484'
$ExpectedSealedRoot =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-REHEARSAL\templeosts-1.10-isolated-r1'
$ExpectedBootRoot =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r1'
$ExpectedLiveVBoxPath = 'D:\VirtualBox VMs\Temple1.10\Temple1.10.vbox'
$ExpectedLiveVdiPath = 'D:\VirtualBox VMs\Temple1.10\Temple1.10.vdi'
$ExpectedLiveIsoPath = 'D:\TempleOSTS.iso'
$ExpectedLiveVBoxHash =
    'E537469A1B1A88DE13D18704B5D6299F3AF202DA518FB266F045485A8FC4F1E6'
$ExpectedSealedVBoxHash =
    '69224A832694CA0C657CA2135ED370F6B7E667B84F93C08D921AED4A6D21F39B'
$ExpectedVdiBytes = 2097152L
$ExpectedVdiHash =
    '90D453A94F075760A11E0772862E60C4B031ED874F28AA396EAE638F7EB8B31B'
$ExpectedIsoBytes = 30558208L
$ExpectedIsoHash =
    'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$ExpectedSealedVBoxFileId = '0X0000000000000000000100000006010A'
$ExpectedSealedVdiFileId = '0X0000000000000000000100000006010B'
$ExpectedSealedIsoFileId = '0X0000000000000000000100000006010C'
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
        throw "${Label} path mismatch: observed=$Observed expected=$Expected"
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
        throw "${Label} is inside forbidden root: path=$Full root=$RootFull"
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
        throw "${Label} missing: $Path"
    }
    $Item = Get-Item -LiteralPath $Path
    $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($Hash -cne $SHA256) {
        throw "${Label} SHA256 mismatch: observed=$Hash expected=$SHA256"
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
        throw (
            "${Label} byte-count mismatch: observed=$($Identity.Bytes) " +
            "expected=$Bytes"
        )
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
        throw "${Label} file-id query failed`n$($Captured -join "`n")"
    }
    $Ids = @(
        foreach ($Line in $Captured) {
            foreach ($Match in [regex]::Matches($Line, '0x[0-9A-Fa-f]+')) {
                $Match.Value.ToUpperInvariant()
            }
        }
    )
    if ($Ids.Count -ne 1) {
        throw "${Label} file-id parse mismatch: count=$($Ids.Count)"
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
        throw "${Label} file ID mismatch: observed=$Observed expected=$Expected"
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
        throw "${Label} failed`n$($Captured -join "`n")"
    }
    return $Captured
}

function Invoke-VBoxRead {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Captured = @(
        & $script:VBox @Arguments 2>&1 |
            ForEach-Object { [string]$_ }
    )
    if ($LASTEXITCODE -ne 0) {
        throw "${Label} failed`n$($Captured -join "`n")"
    }
    return $Captured
}

function Invoke-VBoxMutation {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Captured = @(
        & $script:VBox @Arguments 2>&1 |
            ForEach-Object { [string]$_ }
    )
    if ($LASTEXITCODE -ne 0) {
        throw "${Label} failed`n$($Captured -join "`n")"
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
    throw "${Label} failed`n$($Captured -join "`n")"
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
        throw "${Label} field missing: $Key"
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
        throw "${Label} field mismatch: $Key=$Observed expected=$Expected"
    }
}

function Assert-ExactRegisteredTarget {
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
        [Parameter(Mandatory = $true)][string]$Label
    )

    $NonEmptyRegistered = @($Registered | Where-Object { $_ -cne '' })
    $NonEmptyRunning = @($Running | Where-Object { $_ -cne '' })
    $TargetPattern = (
        '^"' + [regex]::Escape($ExpectedTargetName) + '" \{' +
        [regex]::Escape($ExpectedTargetUuid) + '\}$'
    )
    if (
        $NonEmptyRegistered.Count -ne 1 -or
        @($NonEmptyRegistered | Where-Object { $_ -match $TargetPattern }).Count -ne 1
    ) {
        throw "${Label} registered inventory mismatch"
    }
    if ($NonEmptyRunning.Count -ne 0) {
        throw "${Label} contains running VM rows: $($NonEmptyRunning.Count)"
    }

    $Info = ConvertFrom-VBoxMachineReadable -Lines $Show
    Assert-MachineValue -Info $Info -Key 'name' -Expected $ExpectedTargetName -Label $Label
    Assert-MachineValue -Info $Info -Key 'UUID' -Expected $ExpectedTargetUuid -Label $Label
    Assert-MachineValue -Info $Info -Key 'VMState' -Expected 'poweroff' -Label $Label
    Assert-MachineValue -Info $Info -Key 'CfgFile' -Expected $ExpectedConfig -Label $Label
    Assert-MachineValue -Info $Info -Key 'IDE-1-0' -Expected $ExpectedVdi -Label $Label

    $SharedKeys = @(
        $Info.Keys | Where-Object {
            $_ -like 'SharedFolderNameMachineMapping*' -or
            $_ -like 'SharedFolderPathMachineMapping*'
        }
    )
    if ($SharedKeys.Count -ne 0) {
        throw "${Label} shared-folder keys are not zero: $($SharedKeys.Count)"
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

function ConvertTo-NormalizedUuid {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Trimmed = $Value.Trim().Trim('{', '}')
    $Parsed = [guid]::Empty
    if (-not [guid]::TryParse($Trimmed, [ref]$Parsed)) {
        throw "${Label} is not a UUID: $Value"
    }
    return $Parsed.ToString().ToLowerInvariant()
}

function Get-ColonValue {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Key
    )

    $Pattern = '^\s*' + [regex]::Escape($Key) + ':\s*(?<value>.+?)\s*$'
    $Found = @($Lines | Where-Object { $_ -match $Pattern })
    if ($Found.Count -ne 1) {
        throw "medium field count mismatch: $Key count=$($Found.Count)"
    }
    return [regex]::Match($Found[0], $Pattern).Groups['value'].Value
}

function Invoke-ExactTextReplacement {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Old,
        [Parameter(Mandatory = $true)][string]$New,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $OldCount = [regex]::Matches(
        $Source,
        [regex]::Escape($Old),
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    ).Count
    $NewCountBefore = [regex]::Matches(
        $Source,
        [regex]::Escape($New),
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    ).Count
    if ($OldCount -ne 1 -or $NewCountBefore -ne 0) {
        throw (
            "${Label} source cardinality mismatch: " +
            "old=$OldCount new_before=$NewCountBefore"
        )
    }
    $Patched = $Source.Replace($Old, $New)
    $OldCountAfter = [regex]::Matches(
        $Patched,
        [regex]::Escape($Old),
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    ).Count
    $NewCountAfter = [regex]::Matches(
        $Patched,
        [regex]::Escape($New),
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    ).Count
    if ($OldCountAfter -ne 0 -or $NewCountAfter -ne 1) {
        throw (
            "${Label} replacement mismatch: " +
            "old_after=$OldCountAfter new_after=$NewCountAfter"
        )
    }
    return $Patched
}

function Write-Utf8Text {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )

    [System.IO.File]::WriteAllText(
        $Path,
        $Text,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Write-Utf8Lines {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    Write-Utf8Text -Path $Path -Text (($Lines -join "`n") + "`n")
}

function Get-DvdControllerName {
    param([Parameter(Mandatory = $true)][string]$VBoxPath)

    [xml]$Document = [System.IO.File]::ReadAllText($VBoxPath)
    $Matches = [System.Collections.Generic.List[string]]::new()
    $Controllers = @(
        $Document.SelectNodes("//*[local-name()='StorageController']")
    )
    foreach ($Controller in $Controllers) {
        $Devices = @(
            $Controller.SelectNodes("./*[local-name()='AttachedDevice']")
        )
        foreach ($Device in $Devices) {
            if (
                $Device.GetAttribute('type') -ceq 'DVD' -and
                $Device.GetAttribute('port') -ceq '0' -and
                $Device.GetAttribute('device') -ceq '1'
            ) {
                $Name = $Controller.GetAttribute('name')
                if ([string]::IsNullOrWhiteSpace($Name)) {
                    throw 'DVD storage controller name is empty'
                }
                $Matches.Add($Name)
            }
        }
    }
    if ($Matches.Count -ne 1) {
        throw "DVD storage-controller match count mismatch: $($Matches.Count)"
    }
    return $Matches[0]
}

function Assert-BootVBoxXml {
    param(
        [Parameter(Mandatory = $true)][string]$VBoxPath,
        [Parameter(Mandatory = $true)][string]$ExpectedVdiPath,
        [Parameter(Mandatory = $true)][string]$ExpectedIsoRegistryPath
    )

    [xml]$Document = [System.IO.File]::ReadAllText($VBoxPath)
    $HardDisks = @(
        $Document.SelectNodes("//*[local-name()='MediaRegistry']/*[local-name()='HardDisks']/*[local-name()='HardDisk']")
    )
    $MatchingDisks = @(
        $HardDisks | Where-Object {
            [string]::Equals(
                $_.GetAttribute('location'),
                $ExpectedVdiPath,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        }
    )
    if ($HardDisks.Count -ne 1 -or $MatchingDisks.Count -ne 1) {
        throw 'boot-attempt VBOX VDI media-registry path mismatch'
    }

    $IsoImages = @(
        $Document.SelectNodes("//*[local-name()='MediaRegistry']/*[local-name()='DVDImages']/*[local-name()='Image']")
    )
    $MatchingIsoImages = @(
        $IsoImages | Where-Object {
            [string]::Equals(
                $_.GetAttribute('location'),
                $ExpectedIsoRegistryPath,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        }
    )
    if ($IsoImages.Count -ne 1 -or $MatchingIsoImages.Count -ne 1) {
        throw 'boot-attempt VBOX ISO media-registry path mismatch'
    }

    $AttachedIsoNodes = @(
        $Document.SelectNodes("//*[local-name()='AttachedDevice']/*[local-name()='Image']") |
            Where-Object {
                (ConvertTo-NormalizedUuid `
                    -Value $_.GetAttribute('uuid') `
                    -Label 'attached-image UUID') -ceq $ExpectedIsoUuid
            }
    )
    if ($AttachedIsoNodes.Count -ne 0) {
        throw 'boot-attempt VBOX still attaches the ISO UUID'
    }
}

function Test-IsVolatileLogPath {
    param([Parameter(Mandatory = $true)][string]$Relative)

    $Normalized = $Relative.Replace('/', '\')
    return $Normalized -cmatch '^VBoxUserHome\\VBoxSVC\.log(?:\.[1-9][0-9]*)?$'
}

function Get-BootAttemptInventory {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [string[]]$ExcludedNames = @()
    )

    $Rows = [System.Collections.Generic.List[object]]::new()
    $Files = @(
        Get-ChildItem -LiteralPath $Root -Recurse -Force -File |
            Sort-Object FullName
    )
    foreach ($File in $Files) {
        $Relative = $File.FullName.Substring($Root.Length).TrimStart('\', '/')
        if ($ExcludedNames -contains $Relative) {
            continue
        }
        if (
            [string]::IsNullOrWhiteSpace($Relative) -or
            [System.IO.Path]::IsPathRooted($Relative) -or
            $Relative -match '(^|[\\/])\.\.([\\/]|$)'
        ) {
            throw "invalid boot-attempt inventory path: $Relative"
        }
        $Rows.Add([pscustomobject]@{
            Relative = $Relative
            Path = $File.FullName
            Bytes = $File.Length
            SHA256 = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash
            Volatile = (Test-IsVolatileLogPath -Relative $Relative)
        })
    }
    return $Rows.ToArray()
}

function Get-ModifyVmSwitches {
    $Help = @(
        Invoke-VBoxRead -Arguments @('modifyvm', '--help') -Label 'modifyvm help'
    )
    $Text = $Help -join "`n"
    $ClipboardSwitch = if ($Text -match '(?m)--clipboard-mode(?:\s|=)') {
        '--clipboard-mode'
    }
    elseif ($Text -match '(?m)--clipboard(?:\s|=)') {
        '--clipboard'
    }
    else {
        throw 'no supported clipboard modifyvm switch found'
    }
    $DragDropSwitch = if ($Text -match '(?m)--drag-and-drop(?:\s|=)') {
        '--drag-and-drop'
    }
    elseif ($Text -match '(?m)--draganddrop(?:\s|=)') {
        '--draganddrop'
    }
    else {
        throw 'no supported drag-and-drop modifyvm switch found'
    }
    return [pscustomobject]@{
        Clipboard = $ClipboardSwitch
        DragDrop = $DragDropSwitch
    }
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
$ReadinessReport = (
    Resolve-Path -LiteralPath $BootReadinessReportPath -ErrorAction Stop
).Path
$SealedRoot = (
    Resolve-Path -LiteralPath $SealedRehearsalRoot -ErrorAction Stop
).Path
$BootRoot = Get-FullPath -Path $BootAttemptRoot
$Output = Get-FullPath -Path $OutPath
$LiveVmRoot = Split-Path -Parent $ExpectedLiveVBoxPath

Assert-PathEquals -Observed $SealedRoot -Expected $ExpectedSealedRoot -Label 'sealed rehearsal root'
Assert-PathEquals -Observed $BootRoot -Expected $ExpectedBootRoot -Label 'boot-attempt root'
Assert-DisjointRoots -Left $SealedRoot -Right $BootRoot -Label 'sealed/boot roots'
foreach ($ForbiddenRoot in @($script:Resource, $SealedRoot, $BootRoot, $LiveVmRoot)) {
    Assert-OutsideRoot -Path $Output -Root $ForbiddenRoot -Label 'preparation report'
}
if (Test-Path -LiteralPath $BootRoot) {
    throw "boot-attempt root already exists: $BootRoot"
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
    -Label 'rehearsal verification report'
$ReadinessIdentity = Assert-ExactHashFile `
    -Path $ReadinessReport `
    -SHA256 $ExpectedReadinessReportHash `
    -Label 'boot-readiness report'
$VerificationLines = [System.IO.File]::ReadAllLines($VerificationIdentity.Path)
$ReadinessLines = [System.IO.File]::ReadAllLines($ReadinessIdentity.Path)
foreach ($Field in @(
    @('rehearsal_manifest_sha256', $ExpectedRehearsalManifestHash),
    @('rehearsal_root', $ExpectedSealedRoot),
    @('machine_uuid', $ExpectedTargetUuid),
    @('machine_state', 'poweroff'),
    @('ISOLATED REHEARSAL', 'VERIFIED'),
    @('POWERED-OFF REHEARSAL ENVIRONMENT', 'SEALED'),
    @('VM START', 'NOT-AUTHORIZED'),
    @('RESTORE BOOT', 'NOT-OBSERVED'),
    @('BUILD EXECUTION', 'NOT-AUTHORIZED')
)) {
    Assert-FieldEquals -Lines $VerificationLines -Key $Field[0] -Expected $Field[1]
}
foreach ($Field in @(
    @('rehearsal_verification_report_sha256', $ExpectedVerificationReportHash),
    @('rehearsal_root', $ExpectedSealedRoot),
    @('machine_uuid', $ExpectedTargetUuid),
    @('boot1', 'floppy'),
    @('boot2', 'dvd'),
    @('boot3', 'disk'),
    @('boot4', 'none'),
    @('vdi_first_boot', 'False'),
    @('iso_attached', 'True'),
    @('network_disabled', 'False'),
    @('SEALED REHEARSAL DIRECT START', 'DENIED'),
    @('BOOT ATTEMPT COPY', 'REQUIRED-NOT-PREPARED'),
    @('VM START', 'NOT-AUTHORIZED'),
    @('RESTORE BOOT', 'NOT-OBSERVED'),
    @('BUILD EXECUTION', 'NOT-AUTHORIZED')
)) {
    Assert-FieldEquals -Lines $ReadinessLines -Key $Field[0] -Expected $Field[1]
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

$SealedManifest = Assert-ExactHashFile `
    -Path (Join-Path $SealedRoot 'ISOLATED-REHEARSAL-MANIFEST.txt') `
    -SHA256 $ExpectedRehearsalManifestHash `
    -Label 'sealed rehearsal manifest'
$SealedMachine = Join-Path $SealedRoot 'Machine'
$SealedVBox = Assert-ExactHashFile `
    -Path (Join-Path $SealedMachine 'Temple1.10.vbox') `
    -SHA256 $ExpectedSealedVBoxHash `
    -Label 'sealed rehearsal VBOX'
$SealedVdi = Assert-ExactFile `
    -Path (Join-Path $SealedMachine 'Temple1.10.vdi') `
    -Bytes $ExpectedVdiBytes `
    -SHA256 $ExpectedVdiHash `
    -Label 'sealed rehearsal VDI'
$SealedIso = Assert-ExactFile `
    -Path (Join-Path $SealedMachine 'TempleOSTS.iso') `
    -Bytes $ExpectedIsoBytes `
    -SHA256 $ExpectedIsoHash `
    -Label 'sealed rehearsal ISO'
$SealedVBoxFileId = Assert-FileId `
    -Path $SealedVBox.Path `
    -Expected $ExpectedSealedVBoxFileId `
    -Label 'sealed rehearsal VBOX'
$SealedVdiFileId = Assert-FileId `
    -Path $SealedVdi.Path `
    -Expected $ExpectedSealedVdiFileId `
    -Label 'sealed rehearsal VDI'
$SealedIsoFileId = Assert-FileId `
    -Path $SealedIso.Path `
    -Expected $ExpectedSealedIsoFileId `
    -Label 'sealed rehearsal ISO'

$Switches = Get-ModifyVmSwitches
Wait-VBoxServiceExit -Label 'default registry isolation before boot-copy preparation'
$DefaultVersion = @(Invoke-VBoxRead -Arguments @('--version') -Label 'default VirtualBox version')
if ($DefaultVersion.Count -ne 1 -or $DefaultVersion[0] -cne $ExpectedVBoxVersion) {
    throw "VirtualBox version mismatch: $($DefaultVersion -join ' | ')"
}
$DefaultRegisteredBefore = @(Invoke-VBoxRead -Arguments @('list', 'vms') -Label 'default registered inventory before boot-copy preparation')
$DefaultRunningBefore = @(Invoke-VBoxRead -Arguments @('list', 'runningvms') -Label 'default running inventory before boot-copy preparation')
$DefaultShowBefore = @(
    Invoke-VBoxRead `
        -Arguments @('showvminfo', $ExpectedTargetUuid, '--machinereadable') `
        -Label 'default target before boot-copy preparation'
)
[void](Assert-ExactRegisteredTarget `
    -Registered $DefaultRegisteredBefore `
    -Running $DefaultRunningBefore `
    -Show $DefaultShowBefore `
    -ExpectedConfig $ExpectedLiveVBoxPath `
    -ExpectedVdi $ExpectedLiveVdiPath `
    -Label 'default registry before boot-copy preparation')
$DefaultSnapshotsBefore = @(
    Invoke-VBoxSnapshotInventory `
        -Uuid $ExpectedTargetUuid `
        -Label 'default snapshot inventory before boot-copy preparation'
)
if (@($DefaultSnapshotsBefore | Where-Object { $_ -match '^Snapshot(Name|UUID|Node)' }).Count -ne 0) {
    throw 'default target snapshot rows are not zero before boot-copy preparation'
}
[void](Assert-ExactHashFile -Path $ExpectedLiveVBoxPath -SHA256 $ExpectedLiveVBoxHash -Label 'live VBOX before boot-copy preparation')
[void](Assert-ExactFile -Path $ExpectedLiveVdiPath -Bytes $ExpectedVdiBytes -SHA256 $ExpectedVdiHash -Label 'live VDI before boot-copy preparation')
[void](Assert-ExactFile -Path $ExpectedLiveIsoPath -Bytes $ExpectedIsoBytes -SHA256 $ExpectedIsoHash -Label 'live ISO before boot-copy preparation')
[void](Assert-FileId -Path $ExpectedLiveVdiPath -Expected $ExpectedLiveVdiFileId -Label 'live VDI before boot-copy preparation')
Wait-VBoxServiceExit -Label 'default registry shutdown before boot-copy preparation'

$MachineRoot = Join-Path $BootRoot 'Machine'
$IsolatedHome = Join-Path $BootRoot 'VBoxUserHome'
$BootVBox = Join-Path $MachineRoot 'Temple1.10.vbox'
$BootVdi = Join-Path $MachineRoot 'Temple1.10.vdi'
$BootIso = Join-Path $MachineRoot 'TempleOSTS.iso'
$ManifestPath = Join-Path $BootRoot 'BOOT-ATTEMPT-MANIFEST.txt'
$IncompletePath = Join-Path $BootRoot 'BOOT-ATTEMPT-INCOMPLETE.txt'
$RootCreated = $false
$Registered = $false
$MutationSteps = [System.Collections.Generic.List[string]]::new()

try {
    [void][System.IO.Directory]::CreateDirectory($MachineRoot)
    [void][System.IO.Directory]::CreateDirectory($IsolatedHome)
    $RootCreated = $true
    Write-Utf8Lines `
        -Path $IncompletePath `
        -Lines @(
            'DBYTE-HOLYC-OPT',
            'TEMPLEOSTS 1.10 VDI-ONLY BOOT ATTEMPT PREPARATION INCOMPLETE',
            '',
            ('created_utc' + "`t" + [DateTimeOffset]::UtcNow.ToString('o')),
            ('process_id' + "`t" + $PID),
            '',
            'PRESERVE THIS ROOT IF PREPARATION FAILS.'
        )

    Copy-Item -LiteralPath $SealedVBox.Path -Destination $BootVBox -ErrorAction Stop
    Copy-Item -LiteralPath $SealedVdi.Path -Destination $BootVdi -ErrorAction Stop
    Copy-Item -LiteralPath $SealedIso.Path -Destination $BootIso -ErrorAction Stop
    $MutationSteps.Add('COPY-SEALED-MACHINE-FILES')

    $BootVBoxBeforeRewrite = Assert-ExactHashFile `
        -Path $BootVBox `
        -SHA256 $ExpectedSealedVBoxHash `
        -Label 'boot-copy VBOX before path rewrite'
    $BootVdiBefore = Assert-ExactFile `
        -Path $BootVdi `
        -Bytes $ExpectedVdiBytes `
        -SHA256 $ExpectedVdiHash `
        -Label 'boot-copy VDI before registration'
    $BootIsoBefore = Assert-ExactFile `
        -Path $BootIso `
        -Bytes $ExpectedIsoBytes `
        -SHA256 $ExpectedIsoHash `
        -Label 'boot-copy ISO before registration'

    $BootVBoxFileId = Get-FileId -Path $BootVBox -Label 'boot-copy VBOX'
    $BootVdiFileId = Get-FileId -Path $BootVdi -Label 'boot-copy VDI'
    $BootIsoFileId = Get-FileId -Path $BootIso -Label 'boot-copy ISO'
    if ($BootVBoxFileId -ceq $SealedVBoxFileId) {
        throw 'boot-copy VBOX is not a distinct NTFS file object'
    }
    if (
        $BootVdiFileId -ceq $SealedVdiFileId -or
        $BootVdiFileId -ceq $ExpectedLiveVdiFileId
    ) {
        throw 'boot-copy VDI is not distinct from sealed and live VDI objects'
    }
    if ($BootIsoFileId -ceq $SealedIsoFileId) {
        throw 'boot-copy ISO is not a distinct NTFS file object'
    }

    $VBoxText = [System.IO.File]::ReadAllText($BootVBox)
    $VBoxText = Invoke-ExactTextReplacement `
        -Source $VBoxText `
        -Old $SealedVdi.Path `
        -New $BootVdi `
        -Label 'boot-copy VDI path rewrite'
    $VBoxText = Invoke-ExactTextReplacement `
        -Source $VBoxText `
        -Old $SealedIso.Path `
        -New $BootIso `
        -Label 'boot-copy ISO path rewrite'
    Write-Utf8Text -Path $BootVBox -Text $VBoxText
    $MutationSteps.Add('REWRITE-COPIED-VBOX-MEDIA-PATHS')
    $BootVBoxAfterRewriteHash = (
        Get-FileHash -LiteralPath $BootVBox -Algorithm SHA256
    ).Hash
    $DvdController = Get-DvdControllerName -VBoxPath $BootVBox

    [Environment]::SetEnvironmentVariable(
        'VBOX_USER_HOME',
        $IsolatedHome,
        [EnvironmentVariableTarget]::Process
    )
    try {
        $IsolatedVersion = @(Invoke-VBoxRead -Arguments @('--version') -Label 'boot-copy isolated VirtualBox version')
        if ($IsolatedVersion.Count -ne 1 -or $IsolatedVersion[0] -cne $ExpectedVBoxVersion) {
            throw "boot-copy VirtualBox version mismatch: $($IsolatedVersion -join ' | ')"
        }
        $EmptyRegistered = @(Invoke-VBoxRead -Arguments @('list', 'vms') -Label 'empty boot-copy registry inventory')
        $EmptyRunning = @(Invoke-VBoxRead -Arguments @('list', 'runningvms') -Label 'empty boot-copy running inventory')
        if (@($EmptyRegistered | Where-Object { $_ -cne '' }).Count -ne 0) {
            throw 'boot-copy isolated registry is not empty before registration'
        }
        if (@($EmptyRunning | Where-Object { $_ -cne '' }).Count -ne 0) {
            throw 'boot-copy isolated registry has running rows before registration'
        }

        [void](Invoke-VBoxMutation `
            -Arguments @('registervm', $BootVBox) `
            -Label 'register boot-copy VM')
        $Registered = $true
        $MutationSteps.Add('REGISTER-COPY-IN-EMPTY-ISOLATED-REGISTRY')

        $RegisteredRows = @(Invoke-VBoxRead -Arguments @('list', 'vms') -Label 'boot-copy registered inventory before correction')
        $RunningRows = @(Invoke-VBoxRead -Arguments @('list', 'runningvms') -Label 'boot-copy running inventory before correction')
        $ShowBeforeCorrection = @(
            Invoke-VBoxRead `
                -Arguments @('showvminfo', $ExpectedTargetUuid, '--machinereadable') `
                -Label 'boot-copy showvminfo before correction'
        )
        [void](Assert-ExactRegisteredTarget `
            -Registered $RegisteredRows `
            -Running $RunningRows `
            -Show $ShowBeforeCorrection `
            -ExpectedConfig $BootVBox `
            -ExpectedVdi $BootVdi `
            -Label 'boot-copy registry before correction')

        [void](Invoke-VBoxMutation `
            -Arguments @(
                'modifyvm', $ExpectedTargetUuid,
                '--boot1', 'disk',
                '--boot2', 'none',
                '--boot3', 'none',
                '--boot4', 'none'
            ) `
            -Label 'set boot-copy disk-only boot order')
        $MutationSteps.Add('SET-BOOT1-DISK-BOOT2-4-NONE')

        for ($Index = 1; $Index -le 8; $Index++) {
            [void](Invoke-VBoxMutation `
                -Arguments @('modifyvm', $ExpectedTargetUuid, "--nic$Index", 'none') `
                -Label "disable boot-copy NIC $Index")
        }
        $MutationSteps.Add('DISABLE-NIC1-THROUGH-NIC8')

        [void](Invoke-VBoxMutation `
            -Arguments @('modifyvm', $ExpectedTargetUuid, $Switches.Clipboard, 'disabled') `
            -Label 'disable boot-copy clipboard')
        $MutationSteps.Add("DISABLE-CLIPBOARD-VIA-$($Switches.Clipboard)")

        [void](Invoke-VBoxMutation `
            -Arguments @('modifyvm', $ExpectedTargetUuid, $Switches.DragDrop, 'disabled') `
            -Label 'disable boot-copy drag-and-drop')
        $MutationSteps.Add("DISABLE-DRAGDROP-VIA-$($Switches.DragDrop)")

        [void](Invoke-VBoxMutation `
            -Arguments @(
                'storageattach', $ExpectedTargetUuid,
                '--storagectl', $DvdController,
                '--port', '0',
                '--device', '1',
                '--type', 'dvddrive',
                '--medium', 'none'
            ) `
            -Label 'detach boot-copy ISO medium')
        $MutationSteps.Add('DETACH-ISO-FROM-DVD-SLOT')

        $PostRegistered = @(Invoke-VBoxRead -Arguments @('list', 'vms') -Label 'boot-copy registered inventory after correction')
        $PostRunning = @(Invoke-VBoxRead -Arguments @('list', 'runningvms') -Label 'boot-copy running inventory after correction')
        $PostShow = @(
            Invoke-VBoxRead `
                -Arguments @('showvminfo', $ExpectedTargetUuid, '--machinereadable') `
                -Label 'boot-copy showvminfo after correction'
        )
        $PostInfo = Assert-ExactRegisteredTarget `
            -Registered $PostRegistered `
            -Running $PostRunning `
            -Show $PostShow `
            -ExpectedConfig $BootVBox `
            -ExpectedVdi $BootVdi `
            -Label 'boot-copy registry after correction'

        Assert-MachineValue -Info $PostInfo -Key 'boot1' -Expected 'disk' -Label 'boot-copy corrected state'
        Assert-MachineValue -Info $PostInfo -Key 'boot2' -Expected 'none' -Label 'boot-copy corrected state'
        Assert-MachineValue -Info $PostInfo -Key 'boot3' -Expected 'none' -Label 'boot-copy corrected state'
        Assert-MachineValue -Info $PostInfo -Key 'boot4' -Expected 'none' -Label 'boot-copy corrected state'
        Assert-MachineValue -Info $PostInfo -Key 'clipboard' -Expected 'disabled' -Label 'boot-copy corrected state'
        Assert-MachineValue -Info $PostInfo -Key 'draganddrop' -Expected 'disabled' -Label 'boot-copy corrected state'
        for ($Index = 1; $Index -le 8; $Index++) {
            $NicKey = "nic$Index"
            if ($PostInfo.ContainsKey($NicKey)) {
                Assert-MachineValue `
                    -Info $PostInfo `
                    -Key $NicKey `
                    -Expected 'none' `
                    -Label 'boot-copy corrected state'
            }
        }

        $IsoSlotValue = Get-RequiredMachineValue `
            -Info $PostInfo `
            -Key 'IDE-0-1' `
            -Label 'boot-copy corrected state'
        if (
            [string]::Equals(
                $IsoSlotValue,
                $BootIso,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        ) {
            throw 'boot-copy ISO remains attached in IDE-0-1'
        }
        $PathValueMatches = @(
            $PostInfo.Values | Where-Object {
                [string]::Equals(
                    [string]$_,
                    $BootIso,
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            }
        )
        if ($PathValueMatches.Count -ne 0) {
            throw 'boot-copy showvminfo still contains the ISO attachment path'
        }

        $Snapshots = @(
            Invoke-VBoxSnapshotInventory `
                -Uuid $ExpectedTargetUuid `
                -Label 'boot-copy snapshot inventory after correction'
        )
        if (@($Snapshots | Where-Object { $_ -match '^Snapshot(Name|UUID|Node)' }).Count -ne 0) {
            throw 'boot-copy snapshot rows are not zero'
        }

        $VdiMedium = @(
            Invoke-VBoxRead `
                -Arguments @('showmediuminfo', 'disk', $BootVdi) `
                -Label 'boot-copy VDI medium info'
        )
        $IsoMedium = @(
            Invoke-VBoxRead `
                -Arguments @('showmediuminfo', 'dvd', $BootIso) `
                -Label 'boot-copy ISO medium info'
        )
        $ObservedVdiUuid = ConvertTo-NormalizedUuid `
            -Value (Get-ColonValue -Lines $VdiMedium -Key 'UUID') `
            -Label 'boot-copy VDI UUID'
        $ObservedIsoUuid = ConvertTo-NormalizedUuid `
            -Value (Get-ColonValue -Lines $IsoMedium -Key 'UUID') `
            -Label 'boot-copy ISO UUID'
        if ($ObservedVdiUuid -cne $ExpectedVdiUuid) {
            throw "boot-copy VDI UUID mismatch: $ObservedVdiUuid"
        }
        if ($ObservedIsoUuid -cne $ExpectedIsoUuid) {
            throw "boot-copy ISO UUID mismatch: $ObservedIsoUuid"
        }
    }
    finally {
        try {
            Wait-VBoxServiceExit -Label 'boot-copy isolated registry shutdown after correction'
        }
        finally {
            [Environment]::SetEnvironmentVariable(
                'VBOX_USER_HOME',
                $OriginalVBoxUserHome,
                [EnvironmentVariableTarget]::Process
            )
        }
    }

    $DefaultRegisteredAfter = @(Invoke-VBoxRead -Arguments @('list', 'vms') -Label 'default registered inventory after boot-copy preparation')
    $DefaultRunningAfter = @(Invoke-VBoxRead -Arguments @('list', 'runningvms') -Label 'default running inventory after boot-copy preparation')
    $DefaultShowAfter = @(
        Invoke-VBoxRead `
            -Arguments @('showvminfo', $ExpectedTargetUuid, '--machinereadable') `
            -Label 'default target after boot-copy preparation'
    )
    [void](Assert-ExactRegisteredTarget `
        -Registered $DefaultRegisteredAfter `
        -Running $DefaultRunningAfter `
        -Show $DefaultShowAfter `
        -ExpectedConfig $ExpectedLiveVBoxPath `
        -ExpectedVdi $ExpectedLiveVdiPath `
        -Label 'default registry after boot-copy preparation')
    $DefaultSnapshotsAfter = @(
        Invoke-VBoxSnapshotInventory `
            -Uuid $ExpectedTargetUuid `
            -Label 'default snapshot inventory after boot-copy preparation'
    )
    if (@($DefaultSnapshotsAfter | Where-Object { $_ -match '^Snapshot(Name|UUID|Node)' }).Count -ne 0) {
        throw 'default target snapshot rows changed during boot-copy preparation'
    }
    [void](Assert-ExactHashFile -Path $ExpectedLiveVBoxPath -SHA256 $ExpectedLiveVBoxHash -Label 'live VBOX after boot-copy preparation')
    [void](Assert-ExactFile -Path $ExpectedLiveVdiPath -Bytes $ExpectedVdiBytes -SHA256 $ExpectedVdiHash -Label 'live VDI after boot-copy preparation')
    [void](Assert-ExactFile -Path $ExpectedLiveIsoPath -Bytes $ExpectedIsoBytes -SHA256 $ExpectedIsoHash -Label 'live ISO after boot-copy preparation')
    [void](Assert-FileId -Path $ExpectedLiveVdiPath -Expected $ExpectedLiveVdiFileId -Label 'live VDI after boot-copy preparation')
    Wait-VBoxServiceExit -Label 'default registry shutdown after boot-copy preparation'

    [void](Assert-ExactHashFile -Path $VerificationReport -SHA256 $ExpectedVerificationReportHash -Label 'verification report after boot-copy preparation')
    [void](Assert-ExactHashFile -Path $ReadinessReport -SHA256 $ExpectedReadinessReportHash -Label 'readiness report after boot-copy preparation')
    [void](Assert-ExactHashFile -Path $SealedManifest.Path -SHA256 $ExpectedRehearsalManifestHash -Label 'sealed manifest after boot-copy preparation')
    [void](Assert-ExactHashFile -Path $SealedVBox.Path -SHA256 $ExpectedSealedVBoxHash -Label 'sealed VBOX after boot-copy preparation')
    [void](Assert-ExactFile -Path $SealedVdi.Path -Bytes $ExpectedVdiBytes -SHA256 $ExpectedVdiHash -Label 'sealed VDI after boot-copy preparation')
    [void](Assert-ExactFile -Path $SealedIso.Path -Bytes $ExpectedIsoBytes -SHA256 $ExpectedIsoHash -Label 'sealed ISO after boot-copy preparation')
    [void](Assert-FileId -Path $SealedVBox.Path -Expected $ExpectedSealedVBoxFileId -Label 'sealed VBOX after boot-copy preparation')
    [void](Assert-FileId -Path $SealedVdi.Path -Expected $ExpectedSealedVdiFileId -Label 'sealed VDI after boot-copy preparation')
    [void](Assert-FileId -Path $SealedIso.Path -Expected $ExpectedSealedIsoFileId -Label 'sealed ISO after boot-copy preparation')

    $BootVBoxAfter = Assert-ExactHashFile `
        -Path $BootVBox `
        -SHA256 (Get-FileHash -LiteralPath $BootVBox -Algorithm SHA256).Hash `
        -Label 'boot-copy VBOX after correction'
    $BootVdiAfter = Assert-ExactFile `
        -Path $BootVdi `
        -Bytes $ExpectedVdiBytes `
        -SHA256 $ExpectedVdiHash `
        -Label 'boot-copy VDI after correction'
    $BootIsoAfter = Assert-ExactFile `
        -Path $BootIso `
        -Bytes $ExpectedIsoBytes `
        -SHA256 $ExpectedIsoHash `
        -Label 'boot-copy ISO after correction'
    if ((Get-FileId -Path $BootVBox -Label 'boot-copy VBOX after correction') -cne $BootVBoxFileId) {
        throw 'boot-copy VBOX file ID changed during correction'
    }
    if ((Get-FileId -Path $BootVdi -Label 'boot-copy VDI after correction') -cne $BootVdiFileId) {
        throw 'boot-copy VDI file ID changed during correction'
    }
    if ((Get-FileId -Path $BootIso -Label 'boot-copy ISO after correction') -cne $BootIsoFileId) {
        throw 'boot-copy ISO file ID changed during correction'
    }
    Assert-BootVBoxXml `
        -VBoxPath $BootVBox `
        -ExpectedVdiPath $BootVdi `
        -ExpectedIsoRegistryPath $BootIso

    $NvramFiles = @(
        Get-ChildItem -LiteralPath $BootRoot -Recurse -Force -File |
            Where-Object { $_.Extension -ieq '.nvram' }
    )
    if ($NvramFiles.Count -ne 0) {
        throw "boot-copy NVRAM file count is not zero: $($NvramFiles.Count)"
    }

    $Excluded = @(
        'BOOT-ATTEMPT-MANIFEST.txt',
        'BOOT-ATTEMPT-INCOMPLETE.txt'
    )
    $Inventory = @(Get-BootAttemptInventory -Root $BootRoot -ExcludedNames $Excluded)
    $ImmutableRows = @($Inventory | Where-Object { -not $_.Volatile })
    $VolatileRows = @($Inventory | Where-Object { $_.Volatile })
    if ($ImmutableRows.Count -le 0) {
        throw 'boot-copy immutable inventory is empty'
    }
    if (@($Inventory | Group-Object Relative | Where-Object { $_.Count -ne 1 }).Count -ne 0) {
        throw 'boot-copy inventory contains duplicate relative paths'
    }

    $Manifest = [System.Collections.Generic.List[string]]::new()
    $Manifest.Add('DBYTE-HOLYC-OPT')
    $Manifest.Add('TEMPLEOSTS 1.10 VDI-ONLY OFFLINE BOOT ATTEMPT COPY')
    $Manifest.Add('')
    $Manifest.Add("created_utc`t$([DateTimeOffset]::UtcNow.ToString('o'))")
    $Manifest.Add("resource_commit`t$ExpectedResourceCommit")
    $Manifest.Add("rehearsal_verification_report_sha256`t$ExpectedVerificationReportHash")
    $Manifest.Add("boot_readiness_report_sha256`t$ExpectedReadinessReportHash")
    $Manifest.Add("sealed_rehearsal_manifest_sha256`t$ExpectedRehearsalManifestHash")
    $Manifest.Add("sealed_rehearsal_root`t$SealedRoot")
    $Manifest.Add("boot_attempt_root`t$BootRoot")
    $Manifest.Add("isolated_vbox_user_home`t$IsolatedHome")
    $Manifest.Add("virtualbox_version`t$ExpectedVBoxVersion")
    $Manifest.Add('')
    $Manifest.Add("machine_name`t$ExpectedTargetName")
    $Manifest.Add("machine_uuid`t$ExpectedTargetUuid")
    $Manifest.Add("machine_state`tpoweroff")
    $Manifest.Add("vdi_uuid`t$ExpectedVdiUuid")
    $Manifest.Add("iso_uuid`t$ExpectedIsoUuid")
    $Manifest.Add("dvd_controller`t$DvdController")
    $Manifest.Add("iso_slot_value_after_detach`t$IsoSlotValue")
    $Manifest.Add('')
    $Manifest.Add("boot1`tdisk")
    $Manifest.Add("boot2`tnone")
    $Manifest.Add("boot3`tnone")
    $Manifest.Add("boot4`tnone")
    $Manifest.Add("network_disabled`tTrue")
    $Manifest.Add("clipboard_disabled`tTrue")
    $Manifest.Add("drag_and_drop_disabled`tTrue")
    $Manifest.Add("iso_attached`tFalse")
    $Manifest.Add('')
    $Manifest.Add("boot_vbox_pre_rewrite_sha256`t$($BootVBoxBeforeRewrite.SHA256)")
    $Manifest.Add("boot_vbox_post_rewrite_sha256`t$BootVBoxAfterRewriteHash")
    $Manifest.Add("boot_vbox_post_correction_sha256`t$($BootVBoxAfter.SHA256)")
    $Manifest.Add("boot_vbox_file_id`t$BootVBoxFileId")
    $Manifest.Add("boot_vdi_sha256`t$($BootVdiAfter.SHA256)")
    $Manifest.Add("boot_vdi_file_id`t$BootVdiFileId")
    $Manifest.Add("boot_iso_sha256`t$($BootIsoAfter.SHA256)")
    $Manifest.Add("boot_iso_file_id`t$BootIsoFileId")
    $Manifest.Add('')
    $Manifest.Add("immutable_inventory_files`t$($ImmutableRows.Count)")
    $Manifest.Add("volatile_log_files`t$($VolatileRows.Count)")
    foreach ($Step in $MutationSteps) {
        $Manifest.Add("preparation_step`t$Step")
    }
    $Manifest.Add('')
    foreach ($Row in $ImmutableRows | Sort-Object Relative) {
        $Manifest.Add("file`t$($Row.Relative)`t$($Row.Bytes)`t$($Row.SHA256)")
    }
    foreach ($Row in $VolatileRows | Sort-Object Relative) {
        $Manifest.Add("volatile_log`t$($Row.Relative)`t$($Row.Bytes)`t$($Row.SHA256)")
    }
    $Manifest.Add('')
    $Manifest.Add("BOOT ATTEMPT COPY`tPREPARED")
    $Manifest.Add("POWERED-OFF CORRECTED CONFIGURATION`tOBSERVED")
    $Manifest.Add("VM START`tNOT-AUTHORIZED")
    $Manifest.Add("RESTORE BOOT`tNOT-OBSERVED")
    $Manifest.Add("POWERED-OFF RECOVERY POINT`tNOT-SEALED")
    $Manifest.Add("BUILD EXECUTION`tNOT-AUTHORIZED")
    $Manifest.Add('')
    $Manifest.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')
    Write-Utf8Lines -Path $ManifestPath -Lines $Manifest.ToArray()
    $ManifestHash = (Get-FileHash -LiteralPath $ManifestPath -Algorithm SHA256).Hash

    Remove-Item -LiteralPath $IncompletePath -Force -ErrorAction Stop

    $OutputParent = Split-Path -Parent $Output
    if ($OutputParent) {
        [void][System.IO.Directory]::CreateDirectory($OutputParent)
    }
    $Report = [System.Collections.Generic.List[string]]::new()
    $Report.Add('DBYTE-HOLYC-OPT')
    $Report.Add('TEMPLEOSTS 1.10 VDI-ONLY BOOT ATTEMPT COPY PREPARATION')
    $Report.Add('')
    $Report.Add("rehearsal_verification_report_sha256`t$ExpectedVerificationReportHash")
    $Report.Add("boot_readiness_report_sha256`t$ExpectedReadinessReportHash")
    $Report.Add("boot_attempt_manifest_sha256`t$ManifestHash")
    $Report.Add("boot_attempt_root`t$BootRoot")
    $Report.Add("isolated_vbox_user_home`t$IsolatedHome")
    $Report.Add("virtualbox_version`t$ExpectedVBoxVersion")
    $Report.Add('')
    $Report.Add("machine_name`t$ExpectedTargetName")
    $Report.Add("machine_uuid`t$ExpectedTargetUuid")
    $Report.Add("machine_state`tpoweroff")
    $Report.Add("vdi_uuid`t$ExpectedVdiUuid")
    $Report.Add("iso_uuid`t$ExpectedIsoUuid")
    $Report.Add("dvd_controller`t$DvdController")
    $Report.Add("iso_slot_value_after_detach`t$IsoSlotValue")
    $Report.Add('')
    $Report.Add("boot1`tdisk")
    $Report.Add("boot2`tnone")
    $Report.Add("boot3`tnone")
    $Report.Add("boot4`tnone")
    $Report.Add("network_disabled`tTrue")
    $Report.Add("clipboard_disabled`tTrue")
    $Report.Add("drag_and_drop_disabled`tTrue")
    $Report.Add("iso_attached`tFalse")
    $Report.Add('')
    $Report.Add("boot_vbox_sha256`t$($BootVBoxAfter.SHA256)")
    $Report.Add("boot_vbox_file_id`t$BootVBoxFileId")
    $Report.Add("boot_vdi_sha256`t$($BootVdiAfter.SHA256)")
    $Report.Add("boot_vdi_file_id`t$BootVdiFileId")
    $Report.Add("boot_iso_sha256`t$($BootIsoAfter.SHA256)")
    $Report.Add("boot_iso_file_id`t$BootIsoFileId")
    $Report.Add("immutable_inventory_files`t$($ImmutableRows.Count)")
    $Report.Add("volatile_log_files`t$($VolatileRows.Count)")
    $Report.Add('')
    $Report.Add('The boot-attempt copy is registered only in its own isolated VBOX_USER_HOME.')
    $Report.Add('The copied VDI is first and only boot device; the copied ISO remains a file but is not attached.')
    $Report.Add('All exposed NICs, clipboard and drag-and-drop were disabled on the copied machine only.')
    $Report.Add('The machine remained powered off and no guest execution occurred.')
    $Report.Add('The sealed rehearsal, default registry and live artifacts were revalidated after preparation.')
    $Report.Add('')
    $Report.Add("BOOT ATTEMPT COPY`tPREPARED")
    $Report.Add("POWERED-OFF CORRECTED CONFIGURATION`tOBSERVED")
    $Report.Add("VM START`tNOT-AUTHORIZED")
    $Report.Add("RESTORE BOOT`tNOT-OBSERVED")
    $Report.Add("POWERED-OFF RECOVERY POINT`tNOT-SEALED")
    $Report.Add("BUILD EXECUTION`tNOT-AUTHORIZED")
    $Report.Add('')
    $Report.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')
    Write-Utf8Lines -Path $Output -Lines $Report.ToArray()
    $OutputHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

    Write-Host "READINESS REPORT:     $ExpectedReadinessReportHash"
    Write-Host "BOOT ATTEMPT ROOT:    $BootRoot"
    Write-Host "VBOX USER HOME:       $IsolatedHome"
    Write-Host "MACHINE UUID:         $ExpectedTargetUuid"
    Write-Host "VDI UUID:             $ExpectedVdiUuid"
    Write-Host "ISO UUID:             $ExpectedIsoUuid"
    Write-Host "DVD CONTROLLER:       $DvdController"
    Write-Host "ISO SLOT AFTER:       $IsoSlotValue"
    Write-Host "BOOT1:                disk"
    Write-Host "BOOT2:                none"
    Write-Host "BOOT3:                none"
    Write-Host "BOOT4:                none"
    Write-Host "NETWORK DISABLED:     True"
    Write-Host "CLIPBOARD DISABLED:   True"
    Write-Host "DRAGDROP DISABLED:    True"
    Write-Host "ISO ATTACHED:         False"
    Write-Host "VBOX SHA256:          $($BootVBoxAfter.SHA256)"
    Write-Host "VBOX FILE ID:         $BootVBoxFileId"
    Write-Host "VDI FILE ID:          $BootVdiFileId"
    Write-Host "ISO FILE ID:          $BootIsoFileId"
    Write-Host "BOOT MANIFEST:        $ManifestHash"
    Write-Host "REPORT:               $Output"
    Write-Host "REPORT SHA256:        $OutputHash"
    Write-Host 'BOOT ATTEMPT COPY:    PREPARED'
    Write-Host 'POWERED-OFF CONFIG:   OBSERVED'
    Write-Host 'VM START:             NOT-AUTHORIZED'
    Write-Host 'RESTORE BOOT:         NOT-OBSERVED'
    Write-Host 'RECOVERY POINT:       NOT-SEALED'
    Write-Host 'BUILD:                NOT-AUTHORIZED'
    Write-Host 'VERDICT:              VDI-ONLY BOOT ATTEMPT COPY PREPARATION COMPLETE'
}
catch {
    if ($RootCreated -and (Test-Path -LiteralPath $BootRoot -PathType Container)) {
        $FailureLines = @(
            'DBYTE-HOLYC-OPT',
            'TEMPLEOSTS 1.10 VDI-ONLY BOOT ATTEMPT PREPARATION FAILED',
            '',
            ('failed_utc' + "`t" + [DateTimeOffset]::UtcNow.ToString('o')),
            ('registered_before_failure' + "`t" + $Registered),
            ('error' + "`t" + $_.Exception.Message),
            '',
            'PRESERVE THIS ROOT FOR REVIEW.',
            'DO NOT DELETE OR REUSE IT.'
        )
        try {
            Write-Utf8Lines -Path $IncompletePath -Lines $FailureLines
        }
        catch {
        }
        Write-Host "INCOMPLETE BOOT ROOT: $BootRoot"
        Write-Host 'INCOMPLETE BOOT ROOT WAS PRESERVED FOR REVIEW.'
    }
    throw
}
