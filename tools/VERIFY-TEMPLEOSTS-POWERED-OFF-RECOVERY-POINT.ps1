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
    [string]$TargetReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$InspectorReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedResourceCommit =
    '37b0457e8735ab8cc34a23f2717fcfb808e6a7a8'
$ExpectedInspectorBlob =
    '33491cd33706e1c3a310949bd5fafb30aef9a805'
$ExpectedTargetReportHash =
    '0CDEAEF0B877CB4ED4D56860D5160EB28DDF838AE45360133A8CCAE7CF61EC62'
$ExpectedTargetName = 'Temple1.10'
$ExpectedTargetUuid = '9c98691e-27cd-4487-a306-587969c2c78c'
$ExpectedVdiPath = 'D:\VirtualBox VMs\Temple1.10\Temple1.10.vdi'
$ExpectedVdiBytes = 2097152L
$ExpectedVdiHash =
    '90D453A94F075760A11E0772862E60C4B031ED874F28AA396EAE638F7EB8B31B'
$ExpectedIsoPath = 'D:\TempleOSTS.iso'
$ExpectedIsoBytes = 30558208L
$ExpectedIsoHash =
    'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$ExpectedBaselineManifestBytes = 2662L
$ExpectedBaselineManifestHash =
    '1B4DC2EEDC573DFABD8314E304671F868A6924858CDB736FBD244D257499D37C'
$ExpectedVBoxBytes = 2503L
$ExpectedVBoxHash =
    'E7A884AD2590BAD05AF4465A22FD857A75F64AB9F91042E4638256E8B21AEB46'
$ExpectedVBoxPrevBytes = 2923L
$ExpectedVBoxPrevHash =
    'C127289608695718B6AF58E9522B525EA9E45EFF26CD39BCB3E9773FB35294A0'
$InspectorRelativePath =
    'scripts/inspect-templeos-ts-110-adopted-current-registry.ps1'
$BaselineRelativePath =
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
    $Prefix = Get-Prefix -Path $Root
    if ($Full.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label is inside read-only resource root: $Full"
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

function Assert-NonEmptyFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label missing: $Path"
    }
    $Item = Get-Item -LiteralPath $Path
    if ($Item.Length -le 0) {
        throw "$Label is empty: $Path"
    }
    return [pscustomobject]@{
        Path = $Item.FullName
        Bytes = $Item.Length
        SHA256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }
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

function Invoke-GitRead {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Captured = @(
        & git -C $script:Resource @Arguments 2>&1 |
            ForEach-Object { [string]$_ }
    )
    $Code = $LASTEXITCODE
    if ($Code -ne 0) {
        throw "$Label failed with exit code $Code`n$($Captured -join "`n")"
    }
    return $Captured
}

function Invoke-Inspector {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$VBox,
        [Parameter(Mandatory = $true)][string]$Report
    )

    $Captured = [System.Collections.Generic.List[string]]::new()
    & $Path `
        -VBoxManagePath $VBox `
        -Phase PREFLIGHT `
        -ReportPath $Report *>&1 |
        ForEach-Object {
            $Text = [string]$_
            $Captured.Add($Text)
            Write-Host $Text
        }
    return $Captured.ToArray()
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
    $Code = $LASTEXITCODE
    if ($Code -ne 0) {
        throw "$Label file-id query failed with exit code $Code`n$($Captured -join "`n")"
    }
    $Matches = @(
        $Captured |
            ForEach-Object {
                [regex]::Matches($_, '0x[0-9A-Fa-f]+') |
                    ForEach-Object { $_.Value.ToUpperInvariant() }
            }
    )
    if ($Matches.Count -ne 1) {
        throw "$Label file-id parse mismatch: count=$($Matches.Count)"
    }
    return $Matches[0]
}

$script:Resource = (Resolve-Path -LiteralPath $ResourceRoot -ErrorAction Stop).Path
$VBox = (Resolve-Path -LiteralPath $VBoxManagePath -ErrorAction Stop).Path
$TargetReport = (
    Resolve-Path -LiteralPath $TargetReportPath -ErrorAction Stop
).Path
$InspectorReport = Get-FullPath -Path $InspectorReportPath
$Output = Get-FullPath -Path $OutPath

if (-not (Test-Path -LiteralPath $script:Resource -PathType Container)) {
    throw "resource root is not a directory: $script:Resource"
}
if (-not (Test-Path -LiteralPath $VBox -PathType Leaf)) {
    throw "VBoxManage is not a file: $VBox"
}
if ([string]::Equals(
    $InspectorReport,
    $Output,
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    throw 'inspector report and final report paths must be different'
}
foreach ($Path in @($InspectorReport, $Output)) {
    Assert-OutsideRoot -Path $Path -Root $script:Resource -Label 'output'
    if (Test-Path -LiteralPath $Path) {
        throw "output already exists: $Path"
    }
}

$TargetReportIdentity = Assert-ExactFile `
    -Path $TargetReport `
    -Bytes (Get-Item -LiteralPath $TargetReport).Length `
    -SHA256 $ExpectedTargetReportHash `
    -Label 'sealed target report'
$TargetLines = [System.IO.File]::ReadAllLines($TargetReport)
foreach ($Expected in @(
    "target_name`t$ExpectedTargetName",
    "target_uuid`t$ExpectedTargetUuid",
    'vm_state`tpoweroff',
    'listed_running`tFalse',
    "vdi_path`t$ExpectedVdiPath",
    "vdi_bytes`t$ExpectedVdiBytes",
    "vdi_sha256`t$ExpectedVdiHash",
    "iso_path`t$ExpectedIsoPath",
    "iso_bytes`t$ExpectedIsoBytes",
    "iso_sha256`t$ExpectedIsoHash",
    'snapshot_uuid_rows`t0',
    'shared_folder_keys`t0',
    'TARGET SELECTION`tSEALED',
    'POWERED-OFF RECOVERY POINT`tNOT-PREPARED',
    'GUEST DELIVERY ROUTE`tUNRESOLVED',
    'BUILD EXECUTION`tNOT-AUTHORIZED'
)) {
    Assert-UniqueLine -Lines $TargetLines -Expected $Expected
}

$Head = @(Invoke-GitRead -Arguments @('rev-parse', 'HEAD') -Label 'resource HEAD')
if ($Head.Count -ne 1 -or $Head[0] -cne $ExpectedResourceCommit) {
    throw "resource HEAD mismatch: $($Head -join ' | ')"
}
[void](Invoke-GitRead -Arguments @('diff', '--check') -Label 'resource diff check')
$TrackedWorktree = @(
    Invoke-GitRead -Arguments @('diff', '--name-only') -Label 'resource worktree diff'
)
$TrackedIndex = @(
    Invoke-GitRead -Arguments @('diff', '--cached', '--name-only') -Label 'resource index diff'
)
if ($TrackedWorktree.Count -ne 0 -or $TrackedIndex.Count -ne 0) {
    throw 'resource tracked tree is not clean'
}

$InspectorPath = Join-Path $script:Resource (
    $InspectorRelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
)
if (-not (Test-Path -LiteralPath $InspectorPath -PathType Leaf)) {
    throw "pinned inspector missing: $InspectorPath"
}
$TreeObject = @(
    Invoke-GitRead `
        -Arguments @('rev-parse', "$ExpectedResourceCommit`:$InspectorRelativePath") `
        -Label 'pinned inspector blob'
)
$LocalObject = @(
    Invoke-GitRead `
        -Arguments @('hash-object', '--', $InspectorRelativePath) `
        -Label 'local inspector blob'
)
if (
    $TreeObject.Count -ne 1 -or
    $LocalObject.Count -ne 1 -or
    $TreeObject[0] -cne $ExpectedInspectorBlob -or
    $LocalObject[0] -cne $ExpectedInspectorBlob
) {
    throw (
        "inspector blob mismatch: tree=$($TreeObject -join '|') " +
        "local=$($LocalObject -join '|')"
    )
}

$BaselineRoot = Join-Path $script:Resource (
    $BaselineRelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
)
$BaselineManifest = Join-Path $BaselineRoot 'ADOPTED-BASELINE-MANIFEST.txt'
$BaselineVBox = Join-Path $BaselineRoot 'Temple1.10.vbox'
$BaselineVBoxPrev = Join-Path $BaselineRoot 'Temple1.10.vbox-prev'
$BaselineVdi = Join-Path $BaselineRoot 'Temple1.10.vdi'
$BaselineIso = Join-Path $BaselineRoot 'TempleOSTS.iso'
$BaselineEvidencePaths = @(
    (Join-Path $BaselineRoot 'registered-vms.txt'),
    (Join-Path $BaselineRoot 'running-vms.txt'),
    (Join-Path $BaselineRoot 'Temple1.10-showvminfo-machinereadable.txt'),
    (Join-Path $BaselineRoot 'Temple1.10-vdi-showmediuminfo.txt')
)

$ManifestIdentity = Assert-ExactFile `
    -Path $BaselineManifest `
    -Bytes $ExpectedBaselineManifestBytes `
    -SHA256 $ExpectedBaselineManifestHash `
    -Label 'adopted baseline manifest'
$BaselineVBoxIdentity = Assert-ExactFile `
    -Path $BaselineVBox `
    -Bytes $ExpectedVBoxBytes `
    -SHA256 $ExpectedVBoxHash `
    -Label 'adopted baseline VBOX'
$BaselineVBoxPrevIdentity = Assert-ExactFile `
    -Path $BaselineVBoxPrev `
    -Bytes $ExpectedVBoxPrevBytes `
    -SHA256 $ExpectedVBoxPrevHash `
    -Label 'adopted baseline VBOX-PREV'
$BaselineVdiIdentity = Assert-ExactFile `
    -Path $BaselineVdi `
    -Bytes $ExpectedVdiBytes `
    -SHA256 $ExpectedVdiHash `
    -Label 'adopted baseline VDI'
$BaselineIsoIdentity = Assert-ExactFile `
    -Path $BaselineIso `
    -Bytes $ExpectedIsoBytes `
    -SHA256 $ExpectedIsoHash `
    -Label 'adopted baseline ISO'
$BaselineEvidence = @(
    foreach ($Path in $BaselineEvidencePaths) {
        Assert-NonEmptyFile -Path $Path -Label 'adopted baseline evidence'
    }
)
if (Test-Path -LiteralPath (Join-Path $BaselineRoot 'Temple1.10.nvram')) {
    throw 'adopted baseline NVRAM must remain absent'
}
if ([string]::Equals(
    (Get-FullPath -Path $BaselineVdi),
    (Get-FullPath -Path $ExpectedVdiPath),
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    throw 'baseline VDI path equals live VDI path'
}

$BaselineVdiId = Get-FileId -Path $BaselineVdi -Label 'baseline VDI'
$LiveVdiId = Get-FileId -Path $ExpectedVdiPath -Label 'live VDI'
if ($BaselineVdiId -ceq $LiveVdiId) {
    throw "baseline VDI and live VDI share one file ID: $LiveVdiId"
}

$InspectorParent = Split-Path -Parent $InspectorReport
$OutputParent = Split-Path -Parent $Output
foreach ($Parent in @($InspectorParent, $OutputParent)) {
    if ($Parent) {
        [void][System.IO.Directory]::CreateDirectory($Parent)
    }
}

$InspectorOutput = @(
    Invoke-Inspector `
        -Path $InspectorPath `
        -VBox $VBox `
        -Report $InspectorReport
)
foreach ($Required in @(
    'phase PREFLIGHT',
    'classification REGISTERED-EXACT',
    'target row count 1',
    'running target count 0',
    'target VM state poweroff',
    'VBOX state EXACT',
    'VDI state EXACT',
    'ISO destination state EXACT',
    'adopted baseline state EXACT',
    'tracked diff none',
    'inspect-templeos-ts-110-adopted-current-registry: ok'
)) {
    Assert-UniqueLine -Lines $InspectorOutput -Expected $Required
}
if (-not (Test-Path -LiteralPath $InspectorReport -PathType Leaf)) {
    throw "nested inspector report missing: $InspectorReport"
}
$InspectorReportIdentity = [pscustomobject]@{
    Path = $InspectorReport
    Bytes = (Get-Item -LiteralPath $InspectorReport).Length
    SHA256 = (Get-FileHash -LiteralPath $InspectorReport -Algorithm SHA256).Hash
}

$Report = [System.Collections.Generic.List[string]]::new()
$Report.Add('DBYTE-HOLYC-OPT')
$Report.Add('TEMPLEOSTS 1.10 POWERED-OFF RECOVERY POINT')
$Report.Add('')
$Report.Add("target_report_sha256`t$($TargetReportIdentity.SHA256)")
$Report.Add("resource_commit`t$ExpectedResourceCommit")
$Report.Add("inspector_blob`t$ExpectedInspectorBlob")
$Report.Add("inspector_report_sha256`t$($InspectorReportIdentity.SHA256)")
$Report.Add('')
$Report.Add("target_name`t$ExpectedTargetName")
$Report.Add("target_uuid`t$ExpectedTargetUuid")
$Report.Add('vm_state`tpoweroff')
$Report.Add("live_vdi_path`t$ExpectedVdiPath")
$Report.Add("live_vdi_bytes`t$ExpectedVdiBytes")
$Report.Add("live_vdi_sha256`t$ExpectedVdiHash")
$Report.Add("live_vdi_file_id`t$LiveVdiId")
$Report.Add("live_iso_path`t$ExpectedIsoPath")
$Report.Add("live_iso_sha256`t$ExpectedIsoHash")
$Report.Add('')
$Report.Add("baseline_root`t$BaselineRoot")
$Report.Add("baseline_manifest_sha256`t$($ManifestIdentity.SHA256)")
$Report.Add("baseline_vbox_sha256`t$($BaselineVBoxIdentity.SHA256)")
$Report.Add("baseline_vbox_prev_sha256`t$($BaselineVBoxPrevIdentity.SHA256)")
$Report.Add("baseline_vdi_path`t$($BaselineVdiIdentity.Path)")
$Report.Add("baseline_vdi_bytes`t$($BaselineVdiIdentity.Bytes)")
$Report.Add("baseline_vdi_sha256`t$($BaselineVdiIdentity.SHA256)")
$Report.Add("baseline_vdi_file_id`t$BaselineVdiId")
$Report.Add("baseline_iso_sha256`t$($BaselineIsoIdentity.SHA256)")
$Report.Add("baseline_evidence_files`t$($BaselineEvidence.Count)")
$Report.Add('baseline_nvram`tABSENT')
$Report.Add('')
$Report.Add('The baseline and live VDI have equal bytes and SHA256 but distinct NTFS file IDs.')
$Report.Add('The pinned adopted inspector revalidated the live target as REGISTERED-EXACT and poweroff.')
$Report.Add('No VM, snapshot, attachment, VDI, ISO, guest file or compiler output was modified.')
$Report.Add('')
$Report.Add('TARGET SELECTION`tSEALED')
$Report.Add('POWERED-OFF RECOVERY POINT`tSEALED')
$Report.Add('RESTORE EXECUTION`tNOT-OBSERVED')
$Report.Add('GUEST DELIVERY ROUTE`tUNRESOLVED')
$Report.Add('GUEST FILE BACKUP RESTORE`tUNRESOLVED')
$Report.Add('BUILD EXECUTION`tNOT-AUTHORIZED')
$Report.Add('BUILD STATUS`tNOT-OBSERVED')
$Report.Add('')
$Report.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')

[System.IO.File]::WriteAllText(
    $Output,
    (($Report -join "`n") + "`n"),
    [System.Text.UTF8Encoding]::new($false)
)
$OutputHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

Write-Host "TARGET REPORT:        $($TargetReportIdentity.SHA256)"
Write-Host "RESOURCE COMMIT:      $ExpectedResourceCommit"
Write-Host "INSPECTOR BLOB:       $ExpectedInspectorBlob"
Write-Host "BASELINE MANIFEST:    $($ManifestIdentity.SHA256)"
Write-Host "BASELINE VDI:         $($BaselineVdiIdentity.SHA256)"
Write-Host "BASELINE VDI FILE ID: $BaselineVdiId"
Write-Host "LIVE VDI:             $ExpectedVdiHash"
Write-Host "LIVE VDI FILE ID:     $LiveVdiId"
Write-Host "NESTED REPORT:        $($InspectorReportIdentity.SHA256)"
Write-Host "REPORT:               $Output"
Write-Host "REPORT SHA256:        $OutputHash"
Write-Host 'TARGET SELECTION:     SEALED'
Write-Host 'RECOVERY POINT:       SEALED'
Write-Host 'RESTORE EXECUTION:    NOT-OBSERVED'
Write-Host 'DELIVERY ROUTE:       UNRESOLVED'
Write-Host 'BUILD:                NOT-AUTHORIZED'
Write-Host 'VERDICT:              POWERED-OFF RECOVERY POINT COMPLETE'
