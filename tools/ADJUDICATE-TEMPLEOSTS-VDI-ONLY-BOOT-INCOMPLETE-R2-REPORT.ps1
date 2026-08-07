[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$InspectionReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedInspectionReport =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r2-incomplete-inspection.txt'
$ExpectedInspectionHash =
    '9C2F6A2C2838CF00412F37BA2753DBB1718605FBE165B6D9D2A9FFBFC5E2D42A'
$ExpectedOut =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r2-incomplete-adjudication.txt'

$ExpectedR2Root =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r2'
$ExpectedR1Root =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r1'
$ExpectedMachineUuid = '9c98691e-27cd-4487-a306-587969c2c78c'
$ExpectedCurrentVBoxHash =
    '8EADB39D54CABE5E7B791E5D7E05BCF4CBBF32D4AB6B58291BEC0B2FAD607C0C'
$ExpectedCurrentVBoxFileId = '0X00000000000000000005000000060670'
$ExpectedPreRegistrationVBoxHash =
    '69224A832694CA0C657CA2135ED370F6B7E667B84F93C08D921AED4A6D21F39B'
$ExpectedVdiHash =
    '90D453A94F075760A11E0772862E60C4B031ED874F28AA396EAE638F7EB8B31B'
$ExpectedIsoHash =
    'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$ExpectedVdiFileId = '0X00000000000000000001000000060671'
$ExpectedIsoFileId = '0X00000000000000000001000000060672'

function Get-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath(
        [Environment]::ExpandEnvironmentVariables($Path)
    ).TrimEnd('\', '/')
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
        throw "${Label} mismatch: observed=$Observed expected=$Expected"
    }
}

function Get-ExactField {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Key
    )

    $Prefix = $Key + "`t"
    $Matches = @(
        $Lines | Where-Object {
            $_.StartsWith($Prefix, [System.StringComparison]::Ordinal)
        }
    )
    if ($Matches.Count -ne 1) {
        throw "field cardinality mismatch: key=$Key count=$($Matches.Count)"
    }
    return $Matches[0].Substring($Prefix.Length)
}

function Get-ExactRows {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Key
    )

    $Prefix = $Key + "`t"
    return @(
        $Lines | Where-Object {
            $_.StartsWith($Prefix, [System.StringComparison]::Ordinal)
        }
    )
}

function Assert-Value {
    param(
        [Parameter(Mandatory = $true)][string]$Observed,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ($Observed -cne $Expected) {
        throw "${Label} mismatch: observed=$Observed expected=$Expected"
    }
}

function Convert-VBoxLikeRow {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Line
    )

    $Parts = @($Line.Split("`t"))
    if ($Parts.Count -ne 5 -or $Parts[0] -cne 'vbox_like_file') {
        throw "vbox_like_file row shape mismatch: $Line"
    }
    $Bytes = 0L
    if (-not [long]::TryParse($Parts[2], [ref]$Bytes)) {
        throw "vbox_like_file bytes parse failed: $Line"
    }
    if ($Parts[3] -notmatch '^[0-9A-F]{64}$') {
        throw "vbox_like_file SHA256 shape mismatch: $Line"
    }
    if ($Parts[4] -notmatch '^0X[0-9A-F]+$') {
        throw "vbox_like_file file-ID shape mismatch: $Line"
    }
    return [pscustomobject]@{
        Relative = $Parts[1]
        Bytes = $Bytes
        SHA256 = $Parts[3]
        FileId = $Parts[4]
        Raw = $Line
    }
}

$Report = (Resolve-Path -LiteralPath $InspectionReportPath -ErrorAction Stop).Path
$Output = Get-FullPath -Path $OutPath
Assert-PathEquals -Observed $Report -Expected $ExpectedInspectionReport -Label 'inspection report path'
Assert-PathEquals -Observed $Output -Expected $ExpectedOut -Label 'adjudication report path'

if (Test-Path -LiteralPath $Output) {
    throw "adjudication report already exists: $Output"
}
$OutputParent = Split-Path -Parent $Output
if (-not (Test-Path -LiteralPath $OutputParent -PathType Container)) {
    throw "adjudication report parent missing: $OutputParent"
}

$ReportHash = (Get-FileHash -LiteralPath $Report -Algorithm SHA256).Hash
if ($ReportHash -cne $ExpectedInspectionHash) {
    throw "inspection report SHA256 mismatch: observed=$ReportHash expected=$ExpectedInspectionHash"
}

$Lines = @([System.IO.File]::ReadAllLines($Report))

$ExpectedFields = [ordered]@{
    incomplete_root = $ExpectedR2Root
    preserved_r1_root = $ExpectedR1Root
    preparation_report_absent = 'True'
    incomplete_marker_present = 'True'
    final_manifest_absent = 'True'
    machine_uuid = $ExpectedMachineUuid
    vbox_sha256 = $ExpectedCurrentVBoxHash
    vbox_file_id = $ExpectedCurrentVBoxFileId
    vbox_matches_pre_registration_hash = 'False'
    vdi_sha256 = $ExpectedVdiHash
    vdi_file_id = $ExpectedVdiFileId
    iso_sha256 = $ExpectedIsoHash
    iso_file_id = $ExpectedIsoFileId
    target_vdi_registry_rows = '1'
    target_vdi_location = 'Temple1.10.vdi'
    target_vdi_location_matches_expected = 'True'
    target_iso_registry_rows = '1'
    target_iso_location = 'TempleOSTS.iso'
    target_iso_location_matches_expected = 'True'
    attached_target_iso_count = '0'
    vbox_like_file_count = '2'
    boot_order_node_count = '4'
    network_adapter_node_count = '1'
    clipboard_drag_node_count = '1'
    graphics_node_count = '0'
    vbox_user_home_file_count = '2'
    isolated_registry_target_entry_count = '1'
    vboxmanage_invocation = 'NOT-EXECUTED'
    virtualbox_mutation = 'NOT-EXECUTED'
    vm_start = 'NOT-AUTHORIZED'
    INSPECTION = 'COMPLETE'
    'R1 ROOT' = 'PRESERVED'
    'R2 ROOT' = 'PRESERVED'
}

foreach ($Key in $ExpectedFields.Keys) {
    Assert-Value `
        -Observed (Get-ExactField -Lines $Lines -Key $Key) `
        -Expected ([string]$ExpectedFields[$Key]) `
        -Label "inspection field $Key"
}

$VBoxLikeRows = @(Get-ExactRows -Lines $Lines -Key 'vbox_like_file')
if ($VBoxLikeRows.Count -ne 2) {
    throw "vbox_like_file row count mismatch: $($VBoxLikeRows.Count)"
}
$VBoxLike = @($VBoxLikeRows | ForEach-Object { Convert-VBoxLikeRow -Line $_ })

$CurrentMatches = @(
    $VBoxLike | Where-Object {
        $_.Relative -ceq 'Machine\Temple1.10.vbox'
    }
)
if ($CurrentMatches.Count -ne 1) {
    throw "current VBOX-like row count mismatch: $($CurrentMatches.Count)"
}
$Current = $CurrentMatches[0]
Assert-Value -Observed $Current.SHA256 -Expected $ExpectedCurrentVBoxHash -Label 'current VBOX-like SHA256'
Assert-Value -Observed $Current.FileId -Expected $ExpectedCurrentVBoxFileId -Label 'current VBOX-like file ID'

$Companions = @(
    $VBoxLike | Where-Object {
        $_.Relative -cne 'Machine\Temple1.10.vbox'
    }
)
if ($Companions.Count -ne 1) {
    throw "companion VBOX-like row count mismatch: $($Companions.Count)"
}
$Companion = $Companions[0]
$CompanionMatchesPreRegistration =
    $Companion.SHA256 -ceq $ExpectedPreRegistrationVBoxHash

$ReplayRows = @(
    $Lines | Where-Object {
        $_ -match '^(?:machine_file|vbox_like_file|boot_order_[^\t]*|network_adapter_[^\t]*|clipboard_drag_[^\t]*|graphics_[^\t]*|storage_device_[^\t]*|vbox_user_home_file|isolated_registry_[^\t]*|registry_machine_entry_[^\t]*)\t'
    }
)
if ($ReplayRows.Count -le 0) {
    throw 'selected structural replay rows are empty'
}

$OutLines = [System.Collections.Generic.List[string]]::new()
$OutLines.Add('DBYTE-HOLYC-OPT')
$OutLines.Add('TEMPLEOSTS 1.10 VDI-ONLY BOOT INCOMPLETE R2 REPORT ADJUDICATION')
$OutLines.Add('')
$OutLines.Add("inspection_report_sha256`t$ExpectedInspectionHash")
$OutLines.Add("current_vbox_sha256`t$($Current.SHA256)")
$OutLines.Add("current_vbox_file_id`t$($Current.FileId)")
$OutLines.Add("companion_relative`t$($Companion.Relative)")
$OutLines.Add("companion_bytes`t$($Companion.Bytes)")
$OutLines.Add("companion_sha256`t$($Companion.SHA256)")
$OutLines.Add("companion_file_id`t$($Companion.FileId)")
$OutLines.Add("companion_matches_pre_registration_vbox`t$CompanionMatchesPreRegistration")
$OutLines.Add('')
$OutLines.Add('selected_report_rows_begin')
foreach ($Line in $ReplayRows) {
    $OutLines.Add($Line)
}
$OutLines.Add('selected_report_rows_end')
$OutLines.Add('')
$OutLines.Add("VBOXMANAGE`tNOT-EXECUTED")
$OutLines.Add("VIRTUALBOX MUTATION`tNOT-EXECUTED")
$OutLines.Add("VM START`tNOT-AUTHORIZED")
$OutLines.Add("R1 ROOT`tPRESERVED")
$OutLines.Add("R2 ROOT`tPRESERVED")
$OutLines.Add("R3 PREPARATION`tNOT-AUTHORIZED")
$OutLines.Add('')
$OutLines.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')

[System.IO.File]::WriteAllText(
    $Output,
    (($OutLines.ToArray() -join "`n") + "`n"),
    [System.Text.UTF8Encoding]::new($false)
)
$AdjudicationHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

Write-Host "BOUND INSPECTION:      $ExpectedInspectionHash"
Write-Host "CURRENT VBOX SHA256:   $($Current.SHA256)"
Write-Host "CURRENT VBOX FILE ID:  $($Current.FileId)"
Write-Host "COMPANION RELATIVE:    $($Companion.Relative)"
Write-Host "COMPANION SHA256:      $($Companion.SHA256)"
Write-Host "COMPANION FILE ID:     $($Companion.FileId)"
Write-Host "COMPANION IS PRECOPY:  $CompanionMatchesPreRegistration"
Write-Host "STRUCTURAL ROWS:       $($ReplayRows.Count)"
Write-Host "REPORT:                 $Output"
Write-Host "REPORT SHA256:          $AdjudicationHash"
Write-Host 'VBOXMANAGE:             NOT-EXECUTED'
Write-Host 'VIRTUALBOX MUTATION:    NOT-EXECUTED'
Write-Host 'VM START:               NOT-AUTHORIZED'
Write-Host 'R3 PREPARATION:         NOT-AUTHORIZED'
Write-Host 'VERDICT:                R2 REPORT ADJUDICATION COMPLETE'
Write-Host ''
Write-Host 'SELECTED REPORT ROWS:'
foreach ($Line in $ReplayRows) {
    Write-Host $Line
}
