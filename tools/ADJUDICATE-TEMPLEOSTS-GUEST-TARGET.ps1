[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VBoxManagePath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$GuardRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$GuardReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PreflightReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath,

    [string[]]$CandidateNames = @(
        'Temple1.10',
        'TempleOSTS-1.10-DBYTE-TEST'
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedGuardManifestHash =
    '792ED470CF151582C81B20C95C588067B2CD41ED74893AB926079DC5D2C76FCA'
$ExpectedGuardReportHash =
    '53FC38AC8F84C16AA4657A9EF4CB7BBA94B958217B8C489D481ADEF4137AA297'
$ExpectedPreflightReportHash =
    '8F851B21087B470126E343ECBD8258F2A439D2AF3FAE8801451F4FBB63610461'
$ExpectedCandidateHash =
    'DB1C75A5EE71B07ADAEC32E984146602E73D9A0D606E2B76B8CCCC624E0CDCB8'
$ExpectedCandidateBytes = 10527L
$ExpectedGuardFiles = 11
$ExpectedManifestRows = 10
$ExpectedIsoHash =
    'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'

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
            "SHA256=$Hash"
        )
    }
}

function Invoke-VBoxReadOnly {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label,
        [switch]$AllowFailure
    )

    $Captured = @(
        & $script:VBox @Arguments 2>&1 |
            ForEach-Object { [string]$_ }
    )
    $Code = $LASTEXITCODE

    if ($Code -ne 0 -and -not $AllowFailure) {
        throw (
            "$Label failed with exit code $Code`n" +
            ($Captured -join "`n")
        )
    }

    return [pscustomobject]@{
        ExitCode = $Code
        Lines = $Captured
    }
}

function ConvertFrom-VBoxMachineReadable {
    param([Parameter(Mandatory = $true)][string[]]$Lines)

    $Result = @{}
    foreach ($Line in $Lines) {
        $Equals = $Line.IndexOf('=')
        if ($Equals -le 0) {
            continue
        }

        $Key = $Line.Substring(0, $Equals)
        $Value = $Line.Substring($Equals + 1)
        if (
            $Value.Length -ge 2 -and
            $Value[0] -eq '"' -and
            $Value[$Value.Length - 1] -eq '"'
        ) {
            $Value = $Value.Substring(1, $Value.Length - 2)
            $Value = $Value.Replace('\"', '"').Replace('\\', '\')
        }
        $Result[$Key] = $Value
    }
    return $Result
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
        throw "required report line count mismatch: $Expected count=$Count"
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

$CandidateNames = @(
    $CandidateNames |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique
)
if ($CandidateNames.Count -eq 0) {
    throw 'at least one candidate VM name is required'
}

$script:VBox = (Resolve-Path -LiteralPath $VBoxManagePath -ErrorAction Stop).Path
$Guard = (Resolve-Path -LiteralPath $GuardRoot -ErrorAction Stop).Path
$GuardReport = (
    Resolve-Path -LiteralPath $GuardReportPath -ErrorAction Stop
).Path
$PreflightReport = (
    Resolve-Path -LiteralPath $PreflightReportPath -ErrorAction Stop
).Path
$Output = [System.IO.Path]::GetFullPath($OutPath)

if (-not (Test-Path -LiteralPath $script:VBox -PathType Leaf)) {
    throw "VBoxManage is not a file: $script:VBox"
}
if (Test-Path -LiteralPath $Output) {
    throw "output already exists: $Output"
}

$GuardPrefix = [System.IO.Path]::GetFullPath($Guard).TrimEnd('\', '/') +
    [System.IO.Path]::DirectorySeparatorChar
if (
    $Output.StartsWith(
        $GuardPrefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )
) {
    throw "output path is inside immutable guard root: $Output"
}

$GuardManifest = Join-Path $Guard 'GUARD-MANIFEST.TXT'
$CandidateSource = Join-Path $Guard 'candidate-expanded\Compiler\ICLCC.CPP'

$GuardManifestHash = (
    Get-FileHash -LiteralPath $GuardManifest -Algorithm SHA256
).Hash
$GuardReportHash = (
    Get-FileHash -LiteralPath $GuardReport -Algorithm SHA256
).Hash
$PreflightHash = (
    Get-FileHash -LiteralPath $PreflightReport -Algorithm SHA256
).Hash

if ($GuardManifestHash -cne $ExpectedGuardManifestHash) {
    throw "guard manifest hash mismatch: $GuardManifestHash"
}
if ($GuardReportHash -cne $ExpectedGuardReportHash) {
    throw "guard report hash mismatch: $GuardReportHash"
}
if ($PreflightHash -cne $ExpectedPreflightReportHash) {
    throw "preflight report hash mismatch: $PreflightHash"
}
Assert-ExactFile `
    -Path $CandidateSource `
    -Bytes $ExpectedCandidateBytes `
    -SHA256 $ExpectedCandidateHash `
    -Label 'candidate ICLCC'

$GuardFiles = @(Get-ChildItem -LiteralPath $Guard -Recurse -File)
if ($GuardFiles.Count -ne $ExpectedGuardFiles) {
    throw (
        "guard file count mismatch: expected=$ExpectedGuardFiles " +
        "actual=$($GuardFiles.Count)"
    )
}

$ManifestRows = [System.Collections.Generic.List[object]]::new()
foreach ($Line in [System.IO.File]::ReadAllLines($GuardManifest)) {
    if (
        $Line -match
        '^(?<path>[^\t]+)\t(?<bytes>[0-9]+)\t(?<hash>[0-9A-F]{64})\t(?<source>[^\t]+)$'
    ) {
        $Relative = $Matches.path
        $Components = @($Relative -split '[\\/]')
        if (
            [System.IO.Path]::IsPathRooted($Relative) -or
            $Components -contains '..'
        ) {
            throw "unsafe guard manifest path: $Relative"
        }

        $ManifestRows.Add(
            [pscustomobject]@{
                Path = $Relative
                Bytes = [long]$Matches.bytes
                SHA256 = $Matches.hash
            }
        )
    }
}
if ($ManifestRows.Count -ne $ExpectedManifestRows) {
    throw (
        "guard manifest row count mismatch: expected=$ExpectedManifestRows " +
        "actual=$($ManifestRows.Count)"
    )
}
foreach ($Row in $ManifestRows) {
    $Native = $Row.Path.Replace(
        '/',
        [System.IO.Path]::DirectorySeparatorChar
    )
    Assert-ExactFile `
        -Path (Join-Path $Guard $Native) `
        -Bytes $Row.Bytes `
        -SHA256 $Row.SHA256 `
        -Label "guard manifest row $($Row.Path)"
}

$Lines = [System.IO.File]::ReadAllLines($PreflightReport)
Assert-UniqueLine -Lines $Lines -Expected 'DBYTE-HOLYC-OPT'
Assert-UniqueLine `
    -Lines $Lines `
    -Expected 'TEMPLEOSTS 1.10 GUEST DELIVERY PREFLIGHT DISPLAY'
Assert-UniqueLine `
    -Lines $Lines `
    -Expected "guard_manifest_sha256`t$ExpectedGuardManifestHash"
Assert-UniqueLine `
    -Lines $Lines `
    -Expected "guard_report_sha256`t$ExpectedGuardReportHash"
Assert-UniqueLine `
    -Lines $Lines `
    -Expected "candidate_iclcc_sha256`t$ExpectedCandidateHash"
Assert-UniqueLine -Lines $Lines -Expected "guard_files`t11"
Assert-UniqueLine -Lines $Lines -Expected "registered_vms`t1"
Assert-UniqueLine -Lines $Lines -Expected "running_vms`t0"
Assert-UniqueLine -Lines $Lines -Expected "known_candidates`t1"
Assert-UniqueLine `
    -Lines $Lines `
    -Expected "selection_class`tONE-CANDIDATE-OBSERVED"
Assert-UniqueLine -Lines $Lines -Expected "powered_off_candidates`t1"
Assert-UniqueLine -Lines $Lines -Expected "candidates_with_vdi`t1"
Assert-UniqueLine -Lines $Lines -Expected "candidates_with_hashed_vdi`t1"
Assert-UniqueLine -Lines $Lines -Expected "candidates_with_exact_iso`t1"
Assert-UniqueLine -Lines $Lines -Expected "candidates_with_snapshots`t0"
Assert-UniqueLine -Lines $Lines -Expected "candidates_with_shared_folders`t0"
Assert-UniqueLine -Lines $Lines -Expected "target_selection`tUNRESOLVED"
Assert-UniqueLine `
    -Lines $Lines `
    -Expected "powered_off_recovery_point`tUNRESOLVED"
Assert-UniqueLine -Lines $Lines -Expected "guest_delivery_route`tUNRESOLVED"
Assert-UniqueLine -Lines $Lines -Expected "build_execution`tNOT-AUTHORIZED"
Assert-UniqueLine -Lines $Lines -Expected "build_status`tNOT-OBSERVED"

$CandidateIndexes = @()
for ($Index = 0; $Index -lt $Lines.Length; $Index++) {
    if ($Lines[$Index].StartsWith("CANDIDATE`t")) {
        $CandidateIndexes += $Index
    }
}
if ($CandidateIndexes.Count -ne 1) {
    throw "candidate block count mismatch: $($CandidateIndexes.Count)"
}

$CandidateStart = $CandidateIndexes[0]
$SummaryIndex = [Array]::IndexOf($Lines, 'SUMMARY')
if ($SummaryIndex -le $CandidateStart) {
    throw 'summary boundary is missing or precedes candidate block'
}
$CandidateBlock = @($Lines[$CandidateStart..($SummaryIndex - 1)])

$TargetName = Get-UniqueTabValue -Lines $CandidateBlock -Key 'CANDIDATE'
$TargetUuid = Get-UniqueTabValue -Lines $CandidateBlock -Key 'uuid'
$TargetState = Get-UniqueTabValue -Lines $CandidateBlock -Key 'vm_state'
$ListedRunning = Get-UniqueTabValue -Lines $CandidateBlock -Key 'listed_running'
$SafeToHashVdi = Get-UniqueTabValue -Lines $CandidateBlock -Key 'safe_to_hash_vdi'
$SnapshotRows = Get-UniqueTabValue -Lines $CandidateBlock -Key 'snapshot_uuid_rows'
$SharedFolderKeys = Get-UniqueTabValue -Lines $CandidateBlock -Key 'shared_folder_keys'

if ($CandidateNames -notcontains $TargetName) {
    throw "candidate name is outside allowed set: $TargetName"
}
if ($TargetUuid -notmatch '^[0-9A-Fa-f-]{36}$') {
    throw "candidate UUID is invalid: $TargetUuid"
}
if ($TargetState -cne 'poweroff') {
    throw "candidate report state is not poweroff: $TargetState"
}
if ($ListedRunning -cne 'False') {
    throw "candidate report says listed running: $ListedRunning"
}
if ($SafeToHashVdi -cne 'True') {
    throw "candidate report did not authorize VDI hashing: $SafeToHashVdi"
}
if ($SnapshotRows -cne '0') {
    throw "candidate report contains snapshot UUID rows: $SnapshotRows"
}
if ($SharedFolderKeys -cne '0') {
    throw "candidate report contains shared-folder keys: $SharedFolderKeys"
}

$StorageHeader = [Array]::IndexOf(
    $CandidateBlock,
    'key kind path exists bytes hash_state SHA256'
)
$SnapshotHeader = [Array]::IndexOf($CandidateBlock, 'SNAPSHOT LIST RAW')
if ($StorageHeader -lt 0 -or $SnapshotHeader -le $StorageHeader) {
    throw 'candidate storage section boundaries are invalid'
}

$StorageRows = [System.Collections.Generic.List[object]]::new()
for ($Index = $StorageHeader + 1; $Index -lt $SnapshotHeader; $Index++) {
    $Line = $CandidateBlock[$Index]
    if ([string]::IsNullOrWhiteSpace($Line)) {
        continue
    }
    $Fields = @($Line -split "`t", 7)
    if ($Fields.Count -ne 7) {
        throw "invalid storage row field count: $Line"
    }
    $StorageRows.Add(
        [pscustomobject]@{
            Key = $Fields[0]
            Kind = $Fields[1]
            Path = $Fields[2]
            Exists = $Fields[3]
            Bytes = $Fields[4]
            HashState = $Fields[5]
            SHA256 = $Fields[6]
        }
    )
}

$VdiRows = @($StorageRows | Where-Object { $_.Kind -ceq 'VDI' })
$IsoRows = @($StorageRows | Where-Object { $_.Kind -ceq 'ISO' })
if ($VdiRows.Count -ne 1) {
    throw "candidate VDI row count mismatch: $($VdiRows.Count)"
}
if ($IsoRows.Count -ne 1) {
    throw "candidate ISO row count mismatch: $($IsoRows.Count)"
}

$Vdi = $VdiRows[0]
$Iso = $IsoRows[0]
if (
    $Vdi.Exists -cne 'True' -or
    $Vdi.HashState -cne 'HASHED' -or
    $Vdi.Bytes -notmatch '^[0-9]+$' -or
    $Vdi.SHA256 -notmatch '^[0-9A-F]{64}$'
) {
    throw 'candidate VDI report identity is incomplete'
}
if (
    $Iso.Exists -cne 'True' -or
    $Iso.HashState -cne 'HASHED' -or
    $Iso.Bytes -notmatch '^[0-9]+$' -or
    $Iso.SHA256 -cne $ExpectedIsoHash
) {
    throw 'candidate ISO report identity is not the exact TempleOSTS ISO'
}

$Registered = Invoke-VBoxReadOnly `
    -Arguments @('list', 'vms') `
    -Label 'registered VM inventory'
$Running = Invoke-VBoxReadOnly `
    -Arguments @('list', 'runningvms') `
    -Label 'running VM inventory'

$RegisteredPattern = (
    '^"' + [regex]::Escape($TargetName) + '" \{' +
    [regex]::Escape($TargetUuid) + '\}$'
)
$RegisteredMatch = @(
    $Registered.Lines |
        Where-Object { $_ -match $RegisteredPattern }
)
if ($RegisteredMatch.Count -ne 1) {
    throw "live registered target identity mismatch: count=$($RegisteredMatch.Count)"
}
$RunningPattern = '^"' + [regex]::Escape($TargetName) + '" '
if (@($Running.Lines | Where-Object { $_ -match $RunningPattern }).Count -ne 0) {
    throw "target is currently listed as running: $TargetName"
}

$Show = Invoke-VBoxReadOnly `
    -Arguments @('showvminfo', $TargetName, '--machinereadable') `
    -Label "showvminfo $TargetName"
$Info = ConvertFrom-VBoxMachineReadable -Lines $Show.Lines

if (-not $Info.ContainsKey('VMState') -or [string]$Info['VMState'] -cne 'poweroff') {
    throw 'live target state is not poweroff'
}
if (
    -not $Info.ContainsKey('UUID') -or
    -not [string]::Equals(
        [string]$Info['UUID'],
        $TargetUuid,
        [System.StringComparison]::OrdinalIgnoreCase
    )
) {
    throw 'live target UUID does not match preflight report'
}

$CurrentVdiKeys = @(
    $Info.Keys |
        Where-Object {
            [string]::Equals(
                [string]$Info[$_],
                $Vdi.Path,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        }
)
$CurrentIsoKeys = @(
    $Info.Keys |
        Where-Object {
            [string]::Equals(
                [string]$Info[$_],
                $Iso.Path,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        }
)
if ($CurrentVdiKeys.Count -ne 1) {
    throw "live VDI attachment count mismatch: $($CurrentVdiKeys.Count)"
}
if ($CurrentIsoKeys.Count -ne 1) {
    throw "live ISO attachment count mismatch: $($CurrentIsoKeys.Count)"
}

Assert-ExactFile `
    -Path $Vdi.Path `
    -Bytes ([long]$Vdi.Bytes) `
    -SHA256 $Vdi.SHA256 `
    -Label 'selected powered-off VDI'
Assert-ExactFile `
    -Path $Iso.Path `
    -Bytes ([long]$Iso.Bytes) `
    -SHA256 $ExpectedIsoHash `
    -Label 'selected TempleOSTS ISO'

$Snapshot = Invoke-VBoxReadOnly `
    -Arguments @('snapshot', $TargetName, 'list', '--machinereadable') `
    -Label "snapshot list $TargetName" `
    -AllowFailure
$LiveSnapshotRows = @(
    $Snapshot.Lines |
        Where-Object { $_ -match '^SnapshotUUID' }
)
if ($LiveSnapshotRows.Count -ne 0) {
    throw "live target acquired a snapshot chain: $($LiveSnapshotRows.Count)"
}

$LiveSharedFolderKeys = @(
    $Info.Keys |
        Where-Object {
            $_ -match '^SharedFolder(Name|Path)(Machine|Transient)Mapping'
        }
)
if ($LiveSharedFolderKeys.Count -ne 0) {
    throw "live target acquired shared-folder mappings: $($LiveSharedFolderKeys.Count)"
}

$Report = @(
    'DBYTE-HOLYC-OPT',
    'TEMPLEOSTS 1.10 GUEST TARGET ADJUDICATION',
    '',
    "guard_manifest_sha256`t$GuardManifestHash",
    "guard_report_sha256`t$GuardReportHash",
    "preflight_report_sha256`t$PreflightHash",
    "candidate_iclcc_sha256`t$ExpectedCandidateHash",
    '',
    "target_name`t$TargetName",
    "target_uuid`t$TargetUuid",
    "vm_state`t$($Info['VMState'])",
    "listed_running`tFalse",
    "vdi_attachment_key`t$($CurrentVdiKeys[0])",
    "vdi_path`t$($Vdi.Path)",
    "vdi_bytes`t$($Vdi.Bytes)",
    "vdi_sha256`t$($Vdi.SHA256)",
    "iso_attachment_key`t$($CurrentIsoKeys[0])",
    "iso_path`t$($Iso.Path)",
    "iso_bytes`t$($Iso.Bytes)",
    "iso_sha256`t$($Iso.SHA256)",
    "snapshot_command_exit`t$($Snapshot.ExitCode)",
    "snapshot_uuid_rows`t$($LiveSnapshotRows.Count)",
    "shared_folder_keys`t$($LiveSharedFolderKeys.Count)",
    '',
    'The preflight report and live read-only VirtualBox inventory agree on one exact target.',
    'The selected VDI was hashed only after the target was proved powered off and absent from runningvms.',
    'No snapshot, VDI copy, attachment change, guest delivery, or compiler execution occurred.',
    '',
    "TARGET SELECTION`tSEALED",
    "POWERED-OFF RECOVERY POINT`tNOT-PREPARED",
    "GUEST DELIVERY ROUTE`tUNRESOLVED",
    "GUEST FILE BACKUP RESTORE`tUNRESOLVED",
    "BUILD EXECUTION`tNOT-AUTHORIZED",
    "BUILD STATUS`tNOT-OBSERVED",
    '',
    'REPORTS ARE CLAIMS, NOT EVIDENCE.'
)

$OutDirectory = Split-Path -Parent $Output
if ($OutDirectory) {
    New-Item -ItemType Directory -Path $OutDirectory -Force | Out-Null
}
[System.IO.File]::WriteAllText(
    $Output,
    (($Report -join "`n") + "`n"),
    [System.Text.UTF8Encoding]::new($false)
)

$ReportHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash
Write-Host "PREFLIGHT REPORT:     $PreflightHash"
Write-Host "TARGET NAME:          $TargetName"
Write-Host "TARGET UUID:          $TargetUuid"
Write-Host "VM STATE:             $($Info['VMState'])"
Write-Host "VDI PATH:             $($Vdi.Path)"
Write-Host "VDI BYTES:            $($Vdi.Bytes)"
Write-Host "VDI SHA256:           $($Vdi.SHA256)"
Write-Host "ISO PATH:             $($Iso.Path)"
Write-Host "ISO SHA256:           $($Iso.SHA256)"
Write-Host "SNAPSHOT UUID ROWS:   $($LiveSnapshotRows.Count)"
Write-Host "SHARED FOLDERS:       $($LiveSharedFolderKeys.Count)"
Write-Host "REPORT:               $Output"
Write-Host "REPORT SHA256:        $ReportHash"
Write-Host 'TARGET SELECTION:     SEALED'
Write-Host 'RECOVERY POINT:       NOT-PREPARED'
Write-Host 'DELIVERY ROUTE:       UNRESOLVED'
Write-Host 'BUILD:                NOT-AUTHORIZED'
Write-Host 'VERDICT:              GUEST TARGET SELECTION COMPLETE'
