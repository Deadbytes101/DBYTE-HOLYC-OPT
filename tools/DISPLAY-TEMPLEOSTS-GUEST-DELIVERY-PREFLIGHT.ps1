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
$ExpectedCandidateHash =
    'DB1C75A5EE71B07ADAEC32E984146602E73D9A0D606E2B76B8CCCC624E0CDCB8'
$ExpectedCandidateBytes = 10527L
$ExpectedGuardFiles = 11
$ExpectedManifestRows = 10
$ExpectedIsoHash =
    'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'

function Get-Prefix {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/') +
        [System.IO.Path]::DirectorySeparatorChar
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
        Label = $Label
        Arguments = $Arguments
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

function Add-Lines {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[string]]$Target,
        [AllowEmptyCollection()]
        [string[]]$Lines
    )

    foreach ($Line in $Lines) {
        $Target.Add([string]$Line)
    }
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
$Output = [System.IO.Path]::GetFullPath($OutPath)

if (-not (Test-Path -LiteralPath $script:VBox -PathType Leaf)) {
    throw "VBoxManage is not a file: $script:VBox"
}
if (-not (Test-Path -LiteralPath $Guard -PathType Container)) {
    throw "guard root is not a directory: $Guard"
}
if (Test-Path -LiteralPath $Output) {
    throw "output already exists: $Output"
}

$GuardPrefix = Get-Prefix -Path $Guard
if (
    $Output.StartsWith(
        $GuardPrefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )
) {
    throw "output path is inside immutable guard root: $Output"
}

$GuardManifest = Join-Path $Guard 'GUARD-MANIFEST.TXT'
$Candidate = Join-Path $Guard 'candidate-expanded\Compiler\ICLCC.CPP'

$GuardManifestHash = (
    Get-FileHash -LiteralPath $GuardManifest -Algorithm SHA256
).Hash
$GuardReportHash = (
    Get-FileHash -LiteralPath $GuardReport -Algorithm SHA256
).Hash

if ($GuardManifestHash -cne $ExpectedGuardManifestHash) {
    throw "guard manifest hash mismatch: $GuardManifestHash"
}
if ($GuardReportHash -cne $ExpectedGuardReportHash) {
    throw "guard report hash mismatch: $GuardReportHash"
}
Assert-ExactFile `
    -Path $Candidate `
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
                Source = $Matches.source
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

$Version = Invoke-VBoxReadOnly `
    -Arguments @('--version') `
    -Label 'VBoxManage version'
$Registered = Invoke-VBoxReadOnly `
    -Arguments @('list', 'vms') `
    -Label 'registered VM inventory'
$Running = Invoke-VBoxReadOnly `
    -Arguments @('list', 'runningvms') `
    -Label 'running VM inventory'

$RegisteredRows = [System.Collections.Generic.List[object]]::new()
foreach ($Line in $Registered.Lines) {
    if ($Line -match '^"(?<name>.*)" \{(?<uuid>[0-9A-Fa-f-]+)\}$') {
        $RegisteredRows.Add(
            [pscustomobject]@{
                Name = $Matches.name
                UUID = $Matches.uuid
            }
        )
    }
}

$RunningNames = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
foreach ($Line in $Running.Lines) {
    if ($Line -match '^"(?<name>.*)" \{(?<uuid>[0-9A-Fa-f-]+)\}$') {
        [void]$RunningNames.Add($Matches.name)
    }
}

$Candidates = @(
    $RegisteredRows |
        Where-Object { $CandidateNames -contains $_.Name } |
        Sort-Object Name
)

$Report = [System.Collections.Generic.List[string]]::new()
$Report.Add('DBYTE-HOLYC-OPT')
$Report.Add('TEMPLEOSTS 1.10 GUEST DELIVERY PREFLIGHT DISPLAY')
$Report.Add('')
$Report.Add("guard_manifest_sha256`t$GuardManifestHash")
$Report.Add("guard_report_sha256`t$GuardReportHash")
$Report.Add("candidate_iclcc_sha256`t$ExpectedCandidateHash")
$Report.Add("guard_files`t$($GuardFiles.Count)")
$Report.Add("vboxmanage_path`t$script:VBox")
$Report.Add("vboxmanage_version`t$($Version.Lines -join ' ')")
$Report.Add("registered_vms`t$($RegisteredRows.Count)")
$Report.Add("running_vms`t$($RunningNames.Count)")
$Report.Add("known_candidates`t$($Candidates.Count)")
$Report.Add("candidate_names`t$($CandidateNames -join ',')")
$Report.Add('')
$Report.Add('REGISTERED VM INVENTORY RAW')
$Report.Add('---------------------------')
Add-Lines -Target $Report -Lines $Registered.Lines
$Report.Add('')
$Report.Add('RUNNING VM INVENTORY RAW')
$Report.Add('------------------------')
Add-Lines -Target $Report -Lines $Running.Lines

$PoweredOffCandidates = 0
$CandidateWithVdi = 0
$CandidateWithHashedVdi = 0
$CandidateWithExactIso = 0
$CandidateWithSnapshots = 0
$CandidateWithSharedFolders = 0

foreach ($Vm in $Candidates) {
    $Show = Invoke-VBoxReadOnly `
        -Arguments @('showvminfo', $Vm.Name, '--machinereadable') `
        -Label "showvminfo $($Vm.Name)"
    $Info = ConvertFrom-VBoxMachineReadable -Lines $Show.Lines
    $Snapshot = Invoke-VBoxReadOnly `
        -Arguments @('snapshot', $Vm.Name, 'list', '--machinereadable') `
        -Label "snapshot list $($Vm.Name)" `
        -AllowFailure

    $State = if ($Info.ContainsKey('VMState')) {
        [string]$Info['VMState']
    }
    else {
        '<missing>'
    }
    $ListedRunning = $RunningNames.Contains($Vm.Name)
    $SafeToHashVdi = $State -ceq 'poweroff' -and -not $ListedRunning
    if ($SafeToHashVdi) {
        $PoweredOffCandidates++
    }

    $Storage = [System.Collections.Generic.List[object]]::new()
    foreach ($Key in ($Info.Keys | Sort-Object)) {
        $Value = [string]$Info[$Key]
        if ($Value -notmatch '(?i)\.(vdi|iso)$') {
            continue
        }

        $Kind = if ($Value -match '(?i)\.vdi$') { 'VDI' } else { 'ISO' }
        $Exists = Test-Path -LiteralPath $Value -PathType Leaf
        $Bytes = $null
        $Hash = $null
        $HashState = 'MISSING'
        if ($Exists) {
            $Item = Get-Item -LiteralPath $Value
            $Bytes = $Item.Length
            if ($Kind -ceq 'VDI' -and -not $SafeToHashVdi) {
                $HashState = 'NOT-HASHED-VM-NOT-POWEROFF'
            }
            else {
                $Hash = (Get-FileHash -LiteralPath $Value -Algorithm SHA256).Hash
                $HashState = 'HASHED'
            }
        }

        $Storage.Add(
            [pscustomobject]@{
                Key = $Key
                Kind = $Kind
                Path = $Value
                Exists = $Exists
                Bytes = $Bytes
                SHA256 = $Hash
                HashState = $HashState
            }
        )
    }

    $VdiObjects = @($Storage | Where-Object { $_.Kind -ceq 'VDI' })
    if ($VdiObjects.Count -gt 0) {
        $CandidateWithVdi++
    }
    if (@($VdiObjects | Where-Object { $_.HashState -ceq 'HASHED' }).Count -gt 0) {
        $CandidateWithHashedVdi++
    }
    if (
        @(
            $Storage |
                Where-Object {
                    $_.Kind -ceq 'ISO' -and
                    $_.SHA256 -ceq $ExpectedIsoHash
                }
        ).Count -gt 0
    ) {
        $CandidateWithExactIso++
    }

    $SnapshotCount = @(
        $Snapshot.Lines |
            Where-Object { $_ -match '^SnapshotUUID' }
    ).Count
    if ($SnapshotCount -gt 0) {
        $CandidateWithSnapshots++
    }

    $SharedFolderKeys = @(
        $Info.Keys |
            Where-Object {
                $_ -match '^SharedFolder(Name|Path)(Machine|Transient)Mapping'
            }
    )
    if ($SharedFolderKeys.Count -gt 0) {
        $CandidateWithSharedFolders++
    }

    $Report.Add('')
    $Report.Add("CANDIDATE`t$($Vm.Name)")
    $Report.Add("uuid`t$($Vm.UUID)")
    $Report.Add("vm_state`t$State")
    $Report.Add("listed_running`t$ListedRunning")
    $Report.Add("safe_to_hash_vdi`t$SafeToHashVdi")
    $Report.Add("storage_objects`t$($Storage.Count)")
    $Report.Add("snapshot_uuid_rows`t$SnapshotCount")
    $Report.Add("shared_folder_keys`t$($SharedFolderKeys.Count)")
    $Report.Add('')
    $Report.Add('SHOWVMINFO RAW')
    $Report.Add('--------------')
    Add-Lines -Target $Report -Lines $Show.Lines
    $Report.Add('')
    $Report.Add('STORAGE IDENTITIES')
    $Report.Add('------------------')
    $Report.Add('key kind path exists bytes hash_state SHA256')
    foreach ($Object in $Storage) {
        $Report.Add(
            "$($Object.Key)`t$($Object.Kind)`t$($Object.Path)`t" +
            "$($Object.Exists)`t$($Object.Bytes)`t" +
            "$($Object.HashState)`t$($Object.SHA256)"
        )
    }
    $Report.Add('')
    $Report.Add('SNAPSHOT LIST RAW')
    $Report.Add('-----------------')
    $Report.Add("exit_code`t$($Snapshot.ExitCode)")
    Add-Lines -Target $Report -Lines $Snapshot.Lines
}

$SelectionClass = if ($Candidates.Count -eq 0) {
    'NO-KNOWN-CANDIDATE'
}
elseif ($Candidates.Count -eq 1) {
    'ONE-CANDIDATE-OBSERVED'
}
else {
    'MULTIPLE-CANDIDATES-OBSERVED'
}

$Report.Add('')
$Report.Add('SUMMARY')
$Report.Add('-------')
$Report.Add("selection_class`t$SelectionClass")
$Report.Add("powered_off_candidates`t$PoweredOffCandidates")
$Report.Add("candidates_with_vdi`t$CandidateWithVdi")
$Report.Add("candidates_with_hashed_vdi`t$CandidateWithHashedVdi")
$Report.Add("candidates_with_exact_iso`t$CandidateWithExactIso")
$Report.Add("candidates_with_snapshots`t$CandidateWithSnapshots")
$Report.Add("candidates_with_shared_folders`t$CandidateWithSharedFolders")
$Report.Add('target_selection`tUNRESOLVED')
$Report.Add('powered_off_recovery_point`tUNRESOLVED')
$Report.Add('guest_delivery_route`tUNRESOLVED')
$Report.Add('guest_file_backup_restore`tUNRESOLVED')
$Report.Add('build_execution`tNOT-AUTHORIZED')
$Report.Add('build_status`tNOT-OBSERVED')
$Report.Add('')
$Report.Add('This tool performed VBoxManage read operations and host file hashing only.')
$Report.Add('VDI bytes were hashed only when both VM state sources proved poweroff.')
$Report.Add('It did not start, stop, snapshot, attach, detach, mount, or modify a VM or disk.')
$Report.Add('A configured shared-folder mapping would not by itself prove TempleOS guest support.')
$Report.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')

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
Write-Host "GUARD FILES:          $($GuardFiles.Count)/$ExpectedGuardFiles"
Write-Host "GUARD MANIFEST:       $GuardManifestHash"
Write-Host "GUARD REPORT:         $GuardReportHash"
Write-Host "REGISTERED VMS:       $($RegisteredRows.Count)"
Write-Host "KNOWN CANDIDATES:     $($Candidates.Count)"
Write-Host "POWERED OFF:          $PoweredOffCandidates"
Write-Host "CANDIDATES WITH VDI:  $CandidateWithVdi"
Write-Host "HASHED VDI:           $CandidateWithHashedVdi"
Write-Host "EXACT ISO ATTACHED:   $CandidateWithExactIso"
Write-Host "SNAPSHOT CHAINS:      $CandidateWithSnapshots"
Write-Host "SHARED FOLDERS:       $CandidateWithSharedFolders"
Write-Host "REPORT:               $Output"
Write-Host "REPORT SHA256:        $ReportHash"
Write-Host "TARGET SELECTION:     UNRESOLVED"
Write-Host "DELIVERY ROUTE:       UNRESOLVED"
Write-Host "BUILD:                NOT-AUTHORIZED"
Write-Host "VERDICT:              GUEST DELIVERY PREFLIGHT CONTEXT COMPLETE"
