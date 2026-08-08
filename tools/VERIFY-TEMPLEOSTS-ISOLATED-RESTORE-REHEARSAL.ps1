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
    [string]$PreparationReportPath,

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
$ExpectedBundleVerificationHash =
    '887D93D1869CA321A8A4A11816A7ABA6A74366BBA64D4138E1D7DF223F7A9CEC'
$ExpectedRouteReportHash =
    '8AD50F9DB56C228B1D1CF1366D2A34D9F3413DA8B2CD043B6971FB9004ED9AC4'
$ExpectedPreparationReportHash =
    '7E8BABD61E456403AAD8F56FE326C7062A39C7937ABA02B331E0F90F95B39165'
$ExpectedRecoveryManifestHash =
    '3E7C4285920A981BF72AFCD179C467B2DEC35AB1828D21EB4767A1DEB3619F45'
$ExpectedRehearsalManifestHash =
    'AC2609C9C6EFC87316835BB6A4174AF5C28FEEE8DCEBD37E0E9D3DADB14D383F'
$ExpectedTargetName = 'Temple1.10'
$ExpectedTargetUuid = '9c98691e-27cd-4487-a306-587969c2c78c'
$ExpectedVdiUuid = '55c1f29d-a681-402e-b90d-bfbb6b09f207'
$ExpectedIsoUuid = 'ab97b3a5-1331-494d-a917-e85b6e728c45'
$ExpectedVBoxVersion = '7.0.12r159484'
$ExpectedRecoveryRoot =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-RECOVERY\templeosts-1.10-config-exact-r2'
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
$ExpectedBundleVBoxFileId = '0X00000000000000000003000000060062'
$ExpectedBundleVdiFileId = '0X0000000000000000000100000006007B'
$ExpectedLiveVdiFileId = '0X00000000000000000004000000040293'
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
        throw (
            "$Label SHA256 mismatch: observed=$Hash " +
            "expected=$SHA256 path=$($Item.FullName)"
        )
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
            "$Label byte-count mismatch: observed=$($Identity.Bytes) " +
            "expected=$Bytes path=$($Identity.Path)"
        )
    }
    return $Identity
}

function Assert-UniqueLine {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
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

function Assert-ExactNameSet {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Observed,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Expected,
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
    if (
        $Difference.Count -ne 0 -or
        $ObservedSorted.Count -ne $ExpectedSorted.Count
    ) {
        throw "$Label mismatch: $($Difference | Out-String)"
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

function Assert-MachineValue {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Info,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not $Info.ContainsKey($Key)) {
        throw "$Label field missing: $Key"
    }
    $Observed = [string]$Info[$Key]
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

    $RunningPattern = '^"' + [regex]::Escape($ExpectedTargetName) + '" '
    if (@($NonEmptyRunning | Where-Object { $_ -match $RunningPattern }).Count -ne 0) {
        throw "$Label target is listed as running"
    }
    if ($NonEmptyRunning.Count -ne 0) {
        throw "$Label registry contains unexpected running rows: $($NonEmptyRunning.Count)"
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

function Get-ColonValue {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
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

function Get-RehearsalInventory {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [switch]$ExcludeManifest
    )

    $ManifestPath = Join-Path $Root 'ISOLATED-REHEARSAL-MANIFEST.txt'
    $Rows = [System.Collections.Generic.List[object]]::new()
    $Files = @(
        Get-ChildItem -LiteralPath $Root -Recurse -Force -File |
            Sort-Object FullName
    )
    foreach ($File in $Files) {
        if (
            $ExcludeManifest -and
            [string]::Equals(
                $File.FullName,
                $ManifestPath,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        ) {
            continue
        }
        if (-not $File.FullName.StartsWith(
            (Get-Prefix -Path $Root),
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            throw "rehearsal inventory escaped root: $($File.FullName)"
        }
        $Relative = $File.FullName.Substring($Root.Length).TrimStart('\', '/')
        if (
            [string]::IsNullOrWhiteSpace($Relative) -or
            [System.IO.Path]::IsPathRooted($Relative) -or
            $Relative -match '(^|[\\/])\.\.([\\/]|$)'
        ) {
            throw "invalid rehearsal relative path: $Relative"
        }
        $Rows.Add([pscustomobject]@{
            Relative = $Relative
            Path = $File.FullName
            Bytes = $File.Length
            SHA256 = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash
        })
    }
    return $Rows.ToArray()
}

function Read-ManifestInventory {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $Rows = [System.Collections.Generic.List[object]]::new()
    foreach ($Line in $Lines) {
        $Match = [regex]::Match(
            $Line,
            '^file\t([^\t]+)\t([0-9]+)\t([0-9A-F]{64})$'
        )
        if (-not $Match.Success) {
            continue
        }
        $Relative = $Match.Groups[1].Value
        if (
            [string]::IsNullOrWhiteSpace($Relative) -or
            [System.IO.Path]::IsPathRooted($Relative) -or
            $Relative -match '(^|[\\/])\.\.([\\/]|$)'
        ) {
            throw "manifest inventory relative path is invalid: $Relative"
        }
        $Resolved = Get-FullPath -Path (Join-Path $Root $Relative)
        if (-not $Resolved.StartsWith(
            (Get-Prefix -Path $Root),
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            throw "manifest inventory escaped rehearsal root: $Relative"
        }
        $Rows.Add([pscustomobject]@{
            Relative = $Relative
            Path = $Resolved
            Bytes = [long]$Match.Groups[2].Value
            SHA256 = $Match.Groups[3].Value
        })
    }
    $Names = @($Rows | ForEach-Object { $_.Relative })
    if (@($Names | Select-Object -Unique).Count -ne $Names.Count) {
        throw 'manifest inventory contains duplicate relative paths'
    }
    return $Rows.ToArray()
}

function Assert-InventoryMatches {
    param(
        [Parameter(Mandatory = $true)][object[]]$Expected,
        [Parameter(Mandatory = $true)][object[]]$Observed,
        [Parameter(Mandatory = $true)][string]$Label
    )

    Assert-ExactNameSet `
        -Observed @($Observed | ForEach-Object { $_.Relative }) `
        -Expected @($Expected | ForEach-Object { $_.Relative }) `
        -Label "$Label file set"

    $ObservedByName = @{}
    foreach ($Row in $Observed) {
        $ObservedByName[$Row.Relative] = $Row
    }
    foreach ($ExpectedRow in $Expected) {
        $ObservedRow = $ObservedByName[$ExpectedRow.Relative]
        if ($null -eq $ObservedRow) {
            throw "$Label file missing: $($ExpectedRow.Relative)"
        }
        if ($ObservedRow.Bytes -ne $ExpectedRow.Bytes) {
            throw (
                "$Label byte-count mismatch: $($ExpectedRow.Relative) " +
                "observed=$($ObservedRow.Bytes) expected=$($ExpectedRow.Bytes)"
            )
        }
        if ($ObservedRow.SHA256 -cne $ExpectedRow.SHA256) {
            throw (
                "$Label SHA256 mismatch: $($ExpectedRow.Relative) " +
                "observed=$($ObservedRow.SHA256) expected=$($ExpectedRow.SHA256)"
            )
        }
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
$BundleVerificationReport = (
    Resolve-Path -LiteralPath $VerificationReportPath -ErrorAction Stop
).Path
$RouteReport = (
    Resolve-Path -LiteralPath $RouteReportPath -ErrorAction Stop
).Path
$PreparationReport = (
    Resolve-Path -LiteralPath $PreparationReportPath -ErrorAction Stop
).Path
$Bundle = (
    Resolve-Path -LiteralPath $RecoveryRoot -ErrorAction Stop
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
if (-not (Test-Path -LiteralPath $Bundle -PathType Container)) {
    throw "recovery bundle is not a directory: $Bundle"
}
if (-not (Test-Path -LiteralPath $Rehearsal -PathType Container)) {
    throw "rehearsal root is not a directory: $Rehearsal"
}
Assert-PathEquals -Observed $Bundle -Expected $ExpectedRecoveryRoot -Label 'recovery root'
Assert-PathEquals -Observed $Rehearsal -Expected $ExpectedRehearsalRoot -Label 'rehearsal root'
foreach ($ForbiddenRoot in @($script:Resource, $Bundle, $Rehearsal, $LiveVmRoot)) {
    Assert-OutsideRoot -Path $Output -Root $ForbiddenRoot -Label 'verification report'
}
if (Test-Path -LiteralPath $Output) {
    throw "verification report already exists: $Output"
}
if (Test-Path -LiteralPath (Join-Path $Rehearsal 'REHEARSAL-INCOMPLETE.txt')) {
    throw 'rehearsal root contains an incomplete marker'
}

$OriginalVBoxUserHome = [Environment]::GetEnvironmentVariable(
    'VBOX_USER_HOME',
    [EnvironmentVariableTarget]::Process
)
if (-not [string]::IsNullOrEmpty($OriginalVBoxUserHome)) {
    throw "process VBOX_USER_HOME must be unset: $OriginalVBoxUserHome"
}

$BundleVerificationIdentity = Assert-ExactHashFile `
    -Path $BundleVerificationReport `
    -SHA256 $ExpectedBundleVerificationHash `
    -Label 'bundle verification report'
$RouteIdentity = Assert-ExactHashFile `
    -Path $RouteReport `
    -SHA256 $ExpectedRouteReportHash `
    -Label 'restore route report'
$PreparationIdentity = Assert-ExactHashFile `
    -Path $PreparationReport `
    -SHA256 $ExpectedPreparationReportHash `
    -Label 'rehearsal preparation report'

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
    -SHA256 $ExpectedRecoveryManifestHash `
    -Label 'recovery-bundle manifest'
$BundleVBox = Assert-ExactHashFile `
    -Path (Join-Path $Bundle 'Temple1.10.vbox') `
    -SHA256 $ExpectedLiveVBoxHash `
    -Label 'recovery-bundle VBOX'
$BundleVdi = Assert-ExactFile `
    -Path (Join-Path $Bundle 'Temple1.10.vdi') `
    -Bytes $ExpectedVdiBytes `
    -SHA256 $ExpectedVdiHash `
    -Label 'recovery-bundle VDI'
$BundleIso = Assert-ExactFile `
    -Path (Join-Path $Bundle 'TempleOSTS.iso') `
    -Bytes $ExpectedIsoBytes `
    -SHA256 $ExpectedIsoHash `
    -Label 'recovery-bundle ISO'
$BundleVBoxFileId = Assert-FileId `
    -Path $BundleVBox.Path `
    -Expected $ExpectedBundleVBoxFileId `
    -Label 'recovery-bundle VBOX'
$BundleVdiFileId = Assert-FileId `
    -Path $BundleVdi.Path `
    -Expected $ExpectedBundleVdiFileId `
    -Label 'recovery-bundle VDI'
$BundleIsoFileId = Get-FileId -Path $BundleIso.Path -Label 'recovery-bundle ISO'

$ManifestPath = Join-Path $Rehearsal 'ISOLATED-REHEARSAL-MANIFEST.txt'
$RehearsalManifest = Assert-ExactHashFile `
    -Path $ManifestPath `
    -SHA256 $ExpectedRehearsalManifestHash `
    -Label 'rehearsal manifest'
$ManifestLines = [System.IO.File]::ReadAllLines($RehearsalManifest.Path)
Assert-UniqueLine `
    -Lines $ManifestLines `
    -Expected 'TEMPLEOSTS 1.10 ISOLATED DISPOSABLE RESTORE REHEARSAL'
foreach ($Field in @(
    @('resource_commit', $ExpectedResourceCommit),
    @('verification_report_sha256', $ExpectedBundleVerificationHash),
    @('route_report_sha256', $ExpectedRouteReportHash),
    @('bundle_manifest_sha256', $ExpectedRecoveryManifestHash),
    @('rehearsal_root', $ExpectedRehearsalRoot),
    @('isolated_vbox_user_home', (Join-Path $ExpectedRehearsalRoot 'VBoxUserHome')),
    @('machine_name', $ExpectedTargetName),
    @('machine_uuid', $ExpectedTargetUuid),
    @('machine_state', 'poweroff'),
    @('running_rows', '0'),
    @('snapshot_rows', '0'),
    @('shared_folder_rows', '0'),
    @('disposable_vbox_pre_rewrite_sha256', $ExpectedLiveVBoxHash),
    @('disposable_vbox_post_rewrite_sha256', $ExpectedDisposableVBoxHash),
    @('disposable_vbox_post_registration_sha256', $ExpectedDisposableVBoxHash),
    @('disposable_vbox_pre_rewrite_file_id', $ExpectedDisposableVBoxFileId),
    @('disposable_vbox_post_registration_file_id', $ExpectedDisposableVBoxFileId),
    @('disposable_vdi_sha256', $ExpectedVdiHash),
    @('disposable_vdi_file_id', $ExpectedDisposableVdiFileId),
    @('disposable_vdi_uuid', $ExpectedVdiUuid),
    @('disposable_iso_sha256', $ExpectedIsoHash),
    @('disposable_iso_file_id', $ExpectedDisposableIsoFileId),
    @('disposable_iso_uuid', $ExpectedIsoUuid),
    @('disposable_iso_path', (Join-Path $ExpectedRehearsalRoot 'Machine\TempleOSTS.iso')),
    @('ISOLATED REGISTRY', 'PREPARED'),
    @('DISPOSABLE VM REGISTRATION', 'OBSERVED'),
    @('VM START', 'NOT-AUTHORIZED'),
    @('RESTORE BOOT', 'NOT-OBSERVED'),
    @('POWERED-OFF RECOVERY POINT', 'NOT-SEALED'),
    @('BUILD EXECUTION', 'NOT-AUTHORIZED')
)) {
    Assert-FieldEquals -Lines $ManifestLines -Key $Field[0] -Expected $Field[1]
}
$CreatedUtcText = Get-UniqueTabValue -Lines $ManifestLines -Key 'created_utc'
$CreatedUtc = [DateTimeOffset]::MinValue
if (-not [DateTimeOffset]::TryParse($CreatedUtcText, [ref]$CreatedUtc)) {
    throw "rehearsal manifest created_utc is not parseable: $CreatedUtcText"
}
if ($CreatedUtc.Offset -ne [TimeSpan]::Zero) {
    throw "rehearsal manifest created_utc is not UTC: $CreatedUtcText"
}

$PreparationLines = [System.IO.File]::ReadAllLines($PreparationIdentity.Path)
Assert-UniqueLine `
    -Lines $PreparationLines `
    -Expected 'TEMPLEOSTS 1.10 ISOLATED DISPOSABLE RESTORE REHEARSAL PREPARATION'
foreach ($Field in @(
    @('verification_report_sha256', $ExpectedBundleVerificationHash),
    @('route_report_sha256', $ExpectedRouteReportHash),
    @('rehearsal_manifest_sha256', $ExpectedRehearsalManifestHash),
    @('virtualbox_version', $ExpectedVBoxVersion),
    @('rehearsal_root', $ExpectedRehearsalRoot),
    @('isolated_vbox_user_home', (Join-Path $ExpectedRehearsalRoot 'VBoxUserHome')),
    @('machine_name', $ExpectedTargetName),
    @('machine_uuid', $ExpectedTargetUuid),
    @('machine_state', 'poweroff'),
    @('running_rows', '0'),
    @('snapshot_rows', '0'),
    @('shared_folder_rows', '0'),
    @('disposable_vbox_pre_rewrite_sha256', $ExpectedLiveVBoxHash),
    @('disposable_vbox_post_rewrite_sha256', $ExpectedDisposableVBoxHash),
    @('disposable_vbox_post_registration_sha256', $ExpectedDisposableVBoxHash),
    @('disposable_vbox_pre_rewrite_file_id', $ExpectedDisposableVBoxFileId),
    @('disposable_vbox_post_registration_file_id', $ExpectedDisposableVBoxFileId),
    @('disposable_vdi_sha256', $ExpectedVdiHash),
    @('disposable_vdi_file_id', $ExpectedDisposableVdiFileId),
    @('disposable_vdi_uuid', $ExpectedVdiUuid),
    @('disposable_iso_sha256', $ExpectedIsoHash),
    @('disposable_iso_file_id', $ExpectedDisposableIsoFileId),
    @('disposable_iso_uuid', $ExpectedIsoUuid),
    @('disposable_iso_path', (Join-Path $ExpectedRehearsalRoot 'Machine\TempleOSTS.iso')),
    @('ISOLATED REHEARSAL', 'PREPARED'),
    @('ISOLATED REGISTRY', 'SEALED-FOR-POWERED-OFF-BOOT-PROOF'),
    @('DISPOSABLE VM REGISTRATION', 'OBSERVED'),
    @('VM START', 'NOT-AUTHORIZED'),
    @('RESTORE BOOT', 'NOT-OBSERVED'),
    @('POWERED-OFF RECOVERY POINT', 'NOT-SEALED'),
    @('GUEST DELIVERY ROUTE', 'UNRESOLVED'),
    @('BUILD EXECUTION', 'NOT-AUTHORIZED')
)) {
    Assert-FieldEquals -Lines $PreparationLines -Key $Field[0] -Expected $Field[1]
}

$ManifestInventory = @(Read-ManifestInventory -Lines $ManifestLines -Root $Rehearsal)
if ($ManifestInventory.Count -le 0) {
    throw 'rehearsal manifest inventory is empty'
}
$ObservedInventoryBefore = @(
    Get-RehearsalInventory -Root $Rehearsal -ExcludeManifest
)
Assert-InventoryMatches `
    -Expected $ManifestInventory `
    -Observed $ObservedInventoryBefore `
    -Label 'rehearsal inventory before registry verification'
$AllFilesBefore = @(Get-RehearsalInventory -Root $Rehearsal)
if ($AllFilesBefore.Count -ne ($ManifestInventory.Count + 1)) {
    throw (
        "rehearsal total file count mismatch: observed=$($AllFilesBefore.Count) " +
        "expected=$($ManifestInventory.Count + 1)"
    )
}

$MachineRoot = Join-Path $Rehearsal 'Machine'
$IsolatedHome = Join-Path $Rehearsal 'VBoxUserHome'
$DisposableVBox = Join-Path $MachineRoot 'Temple1.10.vbox'
$DisposableVdi = Join-Path $MachineRoot 'Temple1.10.vdi'
$DisposableIso = Join-Path $MachineRoot 'TempleOSTS.iso'
if (-not (Test-Path -LiteralPath $MachineRoot -PathType Container)) {
    throw "machine root missing: $MachineRoot"
}
if (-not (Test-Path -LiteralPath $IsolatedHome -PathType Container)) {
    throw "isolated VBOX_USER_HOME missing: $IsolatedHome"
}
$DisposableVBoxIdentity = Assert-ExactHashFile `
    -Path $DisposableVBox `
    -SHA256 $ExpectedDisposableVBoxHash `
    -Label 'disposable VBOX'
$DisposableVdiIdentity = Assert-ExactFile `
    -Path $DisposableVdi `
    -Bytes $ExpectedVdiBytes `
    -SHA256 $ExpectedVdiHash `
    -Label 'disposable VDI'
$DisposableIsoIdentity = Assert-ExactFile `
    -Path $DisposableIso `
    -Bytes $ExpectedIsoBytes `
    -SHA256 $ExpectedIsoHash `
    -Label 'disposable ISO'
$DisposableVBoxFileId = Assert-FileId `
    -Path $DisposableVBoxIdentity.Path `
    -Expected $ExpectedDisposableVBoxFileId `
    -Label 'disposable VBOX'
$DisposableVdiFileId = Assert-FileId `
    -Path $DisposableVdiIdentity.Path `
    -Expected $ExpectedDisposableVdiFileId `
    -Label 'disposable VDI'
$DisposableIsoFileId = Assert-FileId `
    -Path $DisposableIsoIdentity.Path `
    -Expected $ExpectedDisposableIsoFileId `
    -Label 'disposable ISO'
if ($DisposableVBoxFileId -ceq $BundleVBoxFileId) {
    throw 'disposable and recovery-bundle VBOX share one NTFS file ID'
}
if (
    $DisposableVdiFileId -ceq $BundleVdiFileId -or
    $DisposableVdiFileId -ceq $ExpectedLiveVdiFileId
) {
    throw 'disposable VDI is not distinct from recovery-bundle and live VDI objects'
}
if ($DisposableIsoFileId -ceq $BundleIsoFileId) {
    throw 'disposable and recovery-bundle ISO share one NTFS file ID'
}

Wait-VBoxServiceExit -Label 'default registry service isolation before verification'
$DefaultVersionBefore = @(
    Invoke-VBoxReadOnly -Arguments @('--version') -Label 'default VirtualBox version before verification'
)
if (
    $DefaultVersionBefore.Count -ne 1 -or
    $DefaultVersionBefore[0] -cne $ExpectedVBoxVersion
) {
    throw "VirtualBox version mismatch: $($DefaultVersionBefore -join ' | ')"
}
$DefaultRegisteredBefore = @(
    Invoke-VBoxReadOnly -Arguments @('list', 'vms') -Label 'default registered inventory before verification'
)
$DefaultRunningBefore = @(
    Invoke-VBoxReadOnly -Arguments @('list', 'runningvms') -Label 'default running inventory before verification'
)
$DefaultShowBefore = @(
    Invoke-VBoxReadOnly `
        -Arguments @('showvminfo', $ExpectedTargetUuid, '--machinereadable') `
        -Label 'default target showvminfo before verification'
)
[void](Assert-TargetState `
    -Registered $DefaultRegisteredBefore `
    -Running $DefaultRunningBefore `
    -Show $DefaultShowBefore `
    -ExpectedConfig $ExpectedLiveVBoxPath `
    -ExpectedVdi $ExpectedLiveVdiPath `
    -ExpectedIso $ExpectedLiveIsoPath `
    -Label 'default registry before isolated verification')
$DefaultSnapshotsBefore = @(
    Invoke-VBoxSnapshotInventory `
        -Uuid $ExpectedTargetUuid `
        -Label 'default target snapshot inventory before verification'
)
if (@($DefaultSnapshotsBefore | Where-Object { $_ -match '^Snapshot(Name|UUID|Node)' }).Count -ne 0) {
    throw 'default target snapshot rows are not zero before isolated verification'
}
$LiveVBoxBefore = Assert-ExactHashFile `
    -Path $ExpectedLiveVBoxPath `
    -SHA256 $ExpectedLiveVBoxHash `
    -Label 'live VBOX before isolated verification'
$LiveVdiBefore = Assert-ExactFile `
    -Path $ExpectedLiveVdiPath `
    -Bytes $ExpectedVdiBytes `
    -SHA256 $ExpectedVdiHash `
    -Label 'live VDI before isolated verification'
$LiveIsoBefore = Assert-ExactFile `
    -Path $ExpectedLiveIsoPath `
    -Bytes $ExpectedIsoBytes `
    -SHA256 $ExpectedIsoHash `
    -Label 'live ISO before isolated verification'
$LiveVdiFileId = Assert-FileId `
    -Path $LiveVdiBefore.Path `
    -Expected $ExpectedLiveVdiFileId `
    -Label 'live VDI before isolated verification'
Wait-VBoxServiceExit -Label 'default registry service shutdown before isolated verification'

[Environment]::SetEnvironmentVariable(
    'VBOX_USER_HOME',
    $IsolatedHome,
    [EnvironmentVariableTarget]::Process
)
try {
    $IsolatedVersion = @(
        Invoke-VBoxReadOnly -Arguments @('--version') -Label 'isolated VirtualBox version'
    )
    if (
        $IsolatedVersion.Count -ne 1 -or
        $IsolatedVersion[0] -cne $ExpectedVBoxVersion
    ) {
        throw "isolated VirtualBox version mismatch: $($IsolatedVersion -join ' | ')"
    }
    $IsolatedRegistered = @(
        Invoke-VBoxReadOnly -Arguments @('list', 'vms') -Label 'isolated registered inventory'
    )
    $IsolatedRunning = @(
        Invoke-VBoxReadOnly -Arguments @('list', 'runningvms') -Label 'isolated running inventory'
    )
    $IsolatedShow = @(
        Invoke-VBoxReadOnly `
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
        -Label 'isolated rehearsal registry')
    $IsolatedSnapshots = @(
        Invoke-VBoxSnapshotInventory `
            -Uuid $ExpectedTargetUuid `
            -Label 'isolated target snapshot inventory'
    )
    if (@($IsolatedSnapshots | Where-Object { $_ -match '^Snapshot(Name|UUID|Node)' }).Count -ne 0) {
        throw 'isolated target snapshot rows are not zero'
    }

    $IsolatedVdiMedium = @(
        Invoke-VBoxReadOnly `
            -Arguments @('showmediuminfo', 'disk', $DisposableVdi) `
            -Label 'isolated VDI medium info'
    )
    $IsolatedIsoMedium = @(
        Invoke-VBoxReadOnly `
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
        Wait-VBoxServiceExit -Label 'isolated registry service shutdown after verification'
    }
    finally {
        [Environment]::SetEnvironmentVariable(
            'VBOX_USER_HOME',
            $OriginalVBoxUserHome,
            [EnvironmentVariableTarget]::Process
        )
    }
}

$DefaultRegisteredAfter = @(
    Invoke-VBoxReadOnly -Arguments @('list', 'vms') -Label 'default registered inventory after verification'
)
$DefaultRunningAfter = @(
    Invoke-VBoxReadOnly -Arguments @('list', 'runningvms') -Label 'default running inventory after verification'
)
$DefaultShowAfter = @(
    Invoke-VBoxReadOnly `
        -Arguments @('showvminfo', $ExpectedTargetUuid, '--machinereadable') `
        -Label 'default target showvminfo after verification'
)
[void](Assert-TargetState `
    -Registered $DefaultRegisteredAfter `
    -Running $DefaultRunningAfter `
    -Show $DefaultShowAfter `
    -ExpectedConfig $ExpectedLiveVBoxPath `
    -ExpectedVdi $ExpectedLiveVdiPath `
    -ExpectedIso $ExpectedLiveIsoPath `
    -Label 'default registry after isolated verification')
$DefaultSnapshotsAfter = @(
    Invoke-VBoxSnapshotInventory `
        -Uuid $ExpectedTargetUuid `
        -Label 'default target snapshot inventory after verification'
)
if (@($DefaultSnapshotsAfter | Where-Object { $_ -match '^Snapshot(Name|UUID|Node)' }).Count -ne 0) {
    throw 'default target snapshot rows are not zero after isolated verification'
}
[void](Assert-ExactHashFile `
    -Path $ExpectedLiveVBoxPath `
    -SHA256 $ExpectedLiveVBoxHash `
    -Label 'live VBOX after isolated verification')
[void](Assert-ExactFile `
    -Path $ExpectedLiveVdiPath `
    -Bytes $ExpectedVdiBytes `
    -SHA256 $ExpectedVdiHash `
    -Label 'live VDI after isolated verification')
[void](Assert-ExactFile `
    -Path $ExpectedLiveIsoPath `
    -Bytes $ExpectedIsoBytes `
    -SHA256 $ExpectedIsoHash `
    -Label 'live ISO after isolated verification')
[void](Assert-FileId `
    -Path $ExpectedLiveVdiPath `
    -Expected $ExpectedLiveVdiFileId `
    -Label 'live VDI after isolated verification')
Wait-VBoxServiceExit -Label 'default registry service shutdown after verification'

[void](Assert-ExactHashFile `
    -Path $BundleVerificationReport `
    -SHA256 $ExpectedBundleVerificationHash `
    -Label 'bundle verification report after isolated verification')
[void](Assert-ExactHashFile `
    -Path $RouteReport `
    -SHA256 $ExpectedRouteReportHash `
    -Label 'restore route report after isolated verification')
[void](Assert-ExactHashFile `
    -Path $PreparationReport `
    -SHA256 $ExpectedPreparationReportHash `
    -Label 'rehearsal preparation report after isolated verification')
[void](Assert-ExactHashFile `
    -Path $BundleManifest.Path `
    -SHA256 $ExpectedRecoveryManifestHash `
    -Label 'recovery-bundle manifest after isolated verification')
[void](Assert-ExactHashFile `
    -Path $BundleVBox.Path `
    -SHA256 $ExpectedLiveVBoxHash `
    -Label 'recovery-bundle VBOX after isolated verification')
[void](Assert-ExactFile `
    -Path $BundleVdi.Path `
    -Bytes $ExpectedVdiBytes `
    -SHA256 $ExpectedVdiHash `
    -Label 'recovery-bundle VDI after isolated verification')
[void](Assert-ExactFile `
    -Path $BundleIso.Path `
    -Bytes $ExpectedIsoBytes `
    -SHA256 $ExpectedIsoHash `
    -Label 'recovery-bundle ISO after isolated verification')
[void](Assert-FileId `
    -Path $BundleVBox.Path `
    -Expected $ExpectedBundleVBoxFileId `
    -Label 'recovery-bundle VBOX after isolated verification')
[void](Assert-FileId `
    -Path $BundleVdi.Path `
    -Expected $ExpectedBundleVdiFileId `
    -Label 'recovery-bundle VDI after isolated verification')
if ((Get-FileId -Path $BundleIso.Path -Label 'recovery-bundle ISO after isolated verification') -cne $BundleIsoFileId) {
    throw 'recovery-bundle ISO file ID changed during isolated verification'
}

[void](Assert-ExactHashFile `
    -Path $RehearsalManifest.Path `
    -SHA256 $ExpectedRehearsalManifestHash `
    -Label 'rehearsal manifest after isolated registry verification')
[void](Assert-ExactHashFile `
    -Path $DisposableVBox `
    -SHA256 $ExpectedDisposableVBoxHash `
    -Label 'disposable VBOX after isolated registry verification')
[void](Assert-ExactFile `
    -Path $DisposableVdi `
    -Bytes $ExpectedVdiBytes `
    -SHA256 $ExpectedVdiHash `
    -Label 'disposable VDI after isolated registry verification')
[void](Assert-ExactFile `
    -Path $DisposableIso `
    -Bytes $ExpectedIsoBytes `
    -SHA256 $ExpectedIsoHash `
    -Label 'disposable ISO after isolated registry verification')
[void](Assert-FileId `
    -Path $DisposableVBox `
    -Expected $ExpectedDisposableVBoxFileId `
    -Label 'disposable VBOX after isolated registry verification')
[void](Assert-FileId `
    -Path $DisposableVdi `
    -Expected $ExpectedDisposableVdiFileId `
    -Label 'disposable VDI after isolated registry verification')
[void](Assert-FileId `
    -Path $DisposableIso `
    -Expected $ExpectedDisposableIsoFileId `
    -Label 'disposable ISO after isolated registry verification')

$ObservedInventoryAfter = @(
    Get-RehearsalInventory -Root $Rehearsal -ExcludeManifest
)
Assert-InventoryMatches `
    -Expected $ManifestInventory `
    -Observed $ObservedInventoryAfter `
    -Label 'rehearsal inventory after registry verification'
$AllFilesAfter = @(Get-RehearsalInventory -Root $Rehearsal)
if ($AllFilesAfter.Count -ne ($ManifestInventory.Count + 1)) {
    throw (
        "rehearsal total file count changed: observed=$($AllFilesAfter.Count) " +
        "expected=$($ManifestInventory.Count + 1)"
    )
}

$OutputParent = Split-Path -Parent $Output
if ($OutputParent) {
    [void][System.IO.Directory]::CreateDirectory($OutputParent)
}
$Report = [System.Collections.Generic.List[string]]::new()
$Report.Add('DBYTE-HOLYC-OPT')
$Report.Add('TEMPLEOSTS 1.10 ISOLATED RESTORE REHEARSAL VERIFICATION')
$Report.Add('')
$Report.Add("resource_commit`t$ExpectedResourceCommit")
$Report.Add("bundle_verification_report_sha256`t$($BundleVerificationIdentity.SHA256)")
$Report.Add("route_report_sha256`t$($RouteIdentity.SHA256)")
$Report.Add("preparation_report_sha256`t$($PreparationIdentity.SHA256)")
$Report.Add("rehearsal_manifest_sha256`t$($RehearsalManifest.SHA256)")
$Report.Add("manifest_created_utc`t$CreatedUtcText")
$Report.Add("virtualbox_version`t$ExpectedVBoxVersion")
$Report.Add('')
$Report.Add("rehearsal_root`t$Rehearsal")
$Report.Add("isolated_vbox_user_home`t$IsolatedHome")
$Report.Add("manifest_inventory_files`t$($ManifestInventory.Count)")
$Report.Add("rehearsal_total_files`t$($AllFilesAfter.Count)")
$Report.Add('')
$Report.Add("machine_name`t$ExpectedTargetName")
$Report.Add("machine_uuid`t$ExpectedTargetUuid")
$Report.Add("machine_state`tpoweroff")
$Report.Add("running_rows`t0")
$Report.Add("snapshot_rows`t0")
$Report.Add("shared_folder_rows`t0")
$Report.Add('')
$Report.Add("disposable_vbox_sha256`t$($DisposableVBoxIdentity.SHA256)")
$Report.Add("disposable_vbox_file_id`t$DisposableVBoxFileId")
$Report.Add("disposable_vdi_sha256`t$($DisposableVdiIdentity.SHA256)")
$Report.Add("disposable_vdi_file_id`t$DisposableVdiFileId")
$Report.Add("disposable_vdi_uuid`t$ExpectedVdiUuid")
$Report.Add("disposable_iso_sha256`t$($DisposableIsoIdentity.SHA256)")
$Report.Add("disposable_iso_file_id`t$DisposableIsoFileId")
$Report.Add("disposable_iso_uuid`t$ExpectedIsoUuid")
$Report.Add('')
$Report.Add("recovery_bundle_vbox_file_id`t$BundleVBoxFileId")
$Report.Add("recovery_bundle_vdi_file_id`t$BundleVdiFileId")
$Report.Add("live_vdi_file_id`t$LiveVdiFileId")
$Report.Add('')
$Report.Add('Every manifest inventory row was reopened and rehashed before isolated registry access.')
$Report.Add('The isolated registry contained exactly one powered-off disposable VM with exact local attachments.')
$Report.Add('The isolated VDI and ISO UUIDs matched the sealed route identities.')
$Report.Add('After VBoxSVC shutdown, every manifest inventory row was reopened and matched again.')
$Report.Add('The default registry, live artifacts, sealed reports and recovery bundle were revalidated after isolation.')
$Report.Add('No VM start, restore boot, snapshot mutation, guest delivery or compiler execution occurred.')
$Report.Add('')
$Report.Add("ISOLATED REHEARSAL`tVERIFIED")
$Report.Add("POWERED-OFF REHEARSAL ENVIRONMENT`tSEALED")
$Report.Add("VM START`tNOT-AUTHORIZED")
$Report.Add("RESTORE BOOT`tNOT-OBSERVED")
$Report.Add("POWERED-OFF RECOVERY POINT`tNOT-SEALED")
$Report.Add("GUEST DELIVERY ROUTE`tUNRESOLVED")
$Report.Add("BUILD EXECUTION`tNOT-AUTHORIZED")
$Report.Add('')
$Report.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')
Write-Utf8Lines -Path $Output -Lines $Report.ToArray()
$OutputHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

Write-Host "PREPARATION REPORT:   $($PreparationIdentity.SHA256)"
Write-Host "REHEARSAL MANIFEST:   $($RehearsalManifest.SHA256)"
Write-Host "MANIFEST FILES:       $($ManifestInventory.Count)"
Write-Host "TOTAL FILES:          $($AllFilesAfter.Count)"
Write-Host "MACHINE UUID:         $ExpectedTargetUuid"
Write-Host "VDI UUID:             $ExpectedVdiUuid"
Write-Host "ISO UUID:             $ExpectedIsoUuid"
Write-Host "VBOX SHA256:          $($DisposableVBoxIdentity.SHA256)"
Write-Host "VBOX FILE ID:         $DisposableVBoxFileId"
Write-Host "VDI FILE ID:          $DisposableVdiFileId"
Write-Host "ISO FILE ID:          $DisposableIsoFileId"
Write-Host "REPORT:               $Output"
Write-Host "REPORT SHA256:        $OutputHash"
Write-Host 'ISOLATED REHEARSAL:   VERIFIED'
Write-Host 'POWERED-OFF ENV:      SEALED'
Write-Host 'VM START:             NOT-AUTHORIZED'
Write-Host 'RESTORE BOOT:         NOT-OBSERVED'
Write-Host 'RECOVERY POINT:       NOT-SEALED'
Write-Host 'BUILD:                NOT-AUTHORIZED'
Write-Host 'VERDICT:              ISOLATED POWERED-OFF REHEARSAL VERIFICATION COMPLETE'
