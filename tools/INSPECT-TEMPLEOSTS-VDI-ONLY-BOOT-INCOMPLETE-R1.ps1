[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$IncompleteRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PreparationReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedRoot =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r1'
$ExpectedPreparationReport =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-boot-attempt-preparation.txt'
$ExpectedOutput =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r1-incomplete-inspection.txt'
$ExpectedSealedRoot =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-REHEARSAL\templeosts-1.10-isolated-r1'
$ExpectedSealedVBoxHash =
    '69224A832694CA0C657CA2135ED370F6B7E667B84F93C08D921AED4A6D21F39B'
$ExpectedVdiBytes = 2097152L
$ExpectedVdiHash =
    '90D453A94F075760A11E0772862E60C4B031ED874F28AA396EAE638F7EB8B31B'
$ExpectedIsoBytes = 30558208L
$ExpectedIsoHash =
    'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$ExpectedVdiUuid = '55c1f29d-a681-402e-b90d-bfbb6b09f207'
$ExpectedIsoUuid = 'ab97b3a5-1331-494d-a917-e85b6e728c45'
$ExpectedSealedVBoxFileId = '0X0000000000000000000100000006010A'
$ExpectedSealedVdiFileId = '0X0000000000000000000100000006010B'
$ExpectedSealedIsoFileId = '0X0000000000000000000100000006010C'
$ExpectedLiveVdiFileId = '0X00000000000000000004000000040293'

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

function Assert-ExactHashFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$SHA256,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "${Label} missing: $Path"
    }
    $Item = Get-Item -LiteralPath $Path -ErrorAction Stop
    $Hash = (Get-FileHash -LiteralPath $Item.FullName -Algorithm SHA256).Hash
    if ($Hash -cne $SHA256) {
        throw "${Label} SHA256 mismatch: observed=$Hash expected=$SHA256"
    }
    return [pscustomobject]@{
        Path = $Item.FullName
        Bytes = [int64]$Item.Length
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

function Get-OrdinalCount {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Needle
    )

    if ($Needle.Length -eq 0) {
        throw 'empty occurrence-count needle is not allowed'
    }
    $Count = 0
    $Offset = 0
    while ($Offset -le $Text.Length - $Needle.Length) {
        $Index = $Text.IndexOf(
            $Needle,
            $Offset,
            [System.StringComparison]::OrdinalIgnoreCase
        )
        if ($Index -lt 0) {
            break
        }
        $Count++
        $Offset = $Index + $Needle.Length
    }
    return $Count
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

$Root = Get-FullPath -Path $IncompleteRoot
$PreparationReport = Get-FullPath -Path $PreparationReportPath
$Output = Get-FullPath -Path $OutPath

Assert-PathEquals -Observed $Root -Expected $ExpectedRoot -Label 'incomplete root'
Assert-PathEquals `
    -Observed $PreparationReport `
    -Expected $ExpectedPreparationReport `
    -Label 'preparation report'
Assert-PathEquals -Observed $Output -Expected $ExpectedOutput -Label 'inspection report'

if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    throw "incomplete root missing: $Root"
}
if (Test-Path -LiteralPath $PreparationReport) {
    throw "preparation report unexpectedly exists: $PreparationReport"
}
if (Test-Path -LiteralPath $Output) {
    throw "inspection report already exists: $Output"
}
$OutputParent = Split-Path -Parent $Output
if (-not (Test-Path -LiteralPath $OutputParent -PathType Container)) {
    throw "inspection report parent directory missing: $OutputParent"
}

$OriginalVBoxUserHome = [Environment]::GetEnvironmentVariable(
    'VBOX_USER_HOME',
    [EnvironmentVariableTarget]::Process
)
if (-not [string]::IsNullOrEmpty($OriginalVBoxUserHome)) {
    throw "process VBOX_USER_HOME must be unset: $OriginalVBoxUserHome"
}

$MachineRoot = Join-Path $Root 'Machine'
$VBoxUserHome = Join-Path $Root 'VBoxUserHome'
$VBoxPath = Join-Path $MachineRoot 'Temple1.10.vbox'
$VdiPath = Join-Path $MachineRoot 'Temple1.10.vdi'
$IsoPath = Join-Path $MachineRoot 'TempleOSTS.iso'
$IncompletePath = Join-Path $Root 'BOOT-ATTEMPT-INCOMPLETE.txt'
$ManifestPath = Join-Path $Root 'BOOT-ATTEMPT-MANIFEST.txt'

if (-not (Test-Path -LiteralPath $MachineRoot -PathType Container)) {
    throw "Machine directory missing: $MachineRoot"
}
if (-not (Test-Path -LiteralPath $VBoxUserHome -PathType Container)) {
    throw "VBoxUserHome directory missing: $VBoxUserHome"
}
if (-not (Test-Path -LiteralPath $IncompletePath -PathType Leaf)) {
    throw "incomplete marker missing: $IncompletePath"
}
if (Test-Path -LiteralPath $ManifestPath) {
    throw "final boot-attempt manifest unexpectedly exists: $ManifestPath"
}

$VBox = Assert-ExactHashFile `
    -Path $VBoxPath `
    -SHA256 $ExpectedSealedVBoxHash `
    -Label 'incomplete copied VBOX before rewrite'
$Vdi = Assert-ExactFile `
    -Path $VdiPath `
    -Bytes $ExpectedVdiBytes `
    -SHA256 $ExpectedVdiHash `
    -Label 'incomplete copied VDI'
$Iso = Assert-ExactFile `
    -Path $IsoPath `
    -Bytes $ExpectedIsoBytes `
    -SHA256 $ExpectedIsoHash `
    -Label 'incomplete copied ISO'
$IncompleteItem = Get-Item -LiteralPath $IncompletePath -ErrorAction Stop
$IncompleteHash = (Get-FileHash -LiteralPath $IncompletePath -Algorithm SHA256).Hash

$VBoxFileId = Get-FileId -Path $VBox.Path -Label 'incomplete copied VBOX'
$VdiFileId = Get-FileId -Path $Vdi.Path -Label 'incomplete copied VDI'
$IsoFileId = Get-FileId -Path $Iso.Path -Label 'incomplete copied ISO'
if ($VBoxFileId -ceq $ExpectedSealedVBoxFileId) {
    throw 'incomplete copied VBOX is not a distinct NTFS object'
}
if (
    $VdiFileId -ceq $ExpectedSealedVdiFileId -or
    $VdiFileId -ceq $ExpectedLiveVdiFileId
) {
    throw 'incomplete copied VDI is not distinct from sealed/live VDI objects'
}
if ($IsoFileId -ceq $ExpectedSealedIsoFileId) {
    throw 'incomplete copied ISO is not a distinct NTFS object'
}

$VBoxUserHomeFiles = @(
    Get-ChildItem -LiteralPath $VBoxUserHome -Recurse -Force -File -ErrorAction Stop
)
$VBoxUserHomeDirectories = @(
    Get-ChildItem -LiteralPath $VBoxUserHome -Recurse -Force -Directory -ErrorAction Stop
)
if ($VBoxUserHomeFiles.Count -ne 0 -or $VBoxUserHomeDirectories.Count -ne 0) {
    throw (
        'incomplete VBoxUserHome is not empty: ' +
        "files=$($VBoxUserHomeFiles.Count) dirs=$($VBoxUserHomeDirectories.Count)"
    )
}

$AllFiles = @(
    Get-ChildItem -LiteralPath $Root -Recurse -Force -File -ErrorAction Stop |
        Sort-Object FullName
)
$AllDirectories = @(
    Get-ChildItem -LiteralPath $Root -Recurse -Force -Directory -ErrorAction Stop |
        Sort-Object FullName
)

$VBoxText = [System.IO.File]::ReadAllText($VBox.Path)
[xml]$Document = $VBoxText

$HardDisks = @(
    $Document.SelectNodes(
        "//*[local-name()='MediaRegistry']/*[local-name()='HardDisks']/*[local-name()='HardDisk']"
    )
)
$DvdImages = @(
    $Document.SelectNodes(
        "//*[local-name()='MediaRegistry']/*[local-name()='DVDImages']/*[local-name()='Image']"
    )
)

$TargetHardDisks = @(
    $HardDisks | Where-Object {
        (ConvertTo-NormalizedUuid `
            -Value $_.GetAttribute('uuid') `
            -Label 'HardDisk UUID') -ceq $ExpectedVdiUuid
    }
)
$TargetDvdImages = @(
    $DvdImages | Where-Object {
        (ConvertTo-NormalizedUuid `
            -Value $_.GetAttribute('uuid') `
            -Label 'DVD Image UUID') -ceq $ExpectedIsoUuid
    }
)
if ($TargetHardDisks.Count -ne 1) {
    throw "target VDI media-registry row count mismatch: $($TargetHardDisks.Count)"
}
if ($TargetDvdImages.Count -ne 1) {
    throw "target ISO media-registry row count mismatch: $($TargetDvdImages.Count)"
}

$TargetVdiLocation = $TargetHardDisks[0].GetAttribute('location')
$TargetIsoLocation = $TargetDvdImages[0].GetAttribute('location')
if ([string]::IsNullOrWhiteSpace($TargetVdiLocation)) {
    throw 'target VDI location attribute is empty'
}
if ([string]::IsNullOrWhiteSpace($TargetIsoLocation)) {
    throw 'target ISO location attribute is empty'
}

$SealedVdiPath = Join-Path (Join-Path $ExpectedSealedRoot 'Machine') 'Temple1.10.vdi'
$SealedIsoPath = Join-Path (Join-Path $ExpectedSealedRoot 'Machine') 'TempleOSTS.iso'

$OccurrenceRows = [ordered]@{
    sealed_vdi_absolute = Get-OrdinalCount -Text $VBoxText -Needle $SealedVdiPath
    copied_vdi_absolute = Get-OrdinalCount -Text $VBoxText -Needle $Vdi.Path
    vdi_basename = Get-OrdinalCount -Text $VBoxText -Needle 'Temple1.10.vdi'
    sealed_iso_absolute = Get-OrdinalCount -Text $VBoxText -Needle $SealedIsoPath
    copied_iso_absolute = Get-OrdinalCount -Text $VBoxText -Needle $Iso.Path
    iso_basename = Get-OrdinalCount -Text $VBoxText -Needle 'TempleOSTS.iso'
}

$FinalVBoxUserHome = [Environment]::GetEnvironmentVariable(
    'VBOX_USER_HOME',
    [EnvironmentVariableTarget]::Process
)
if (-not [string]::Equals(
    $FinalVBoxUserHome,
    $OriginalVBoxUserHome,
    [System.StringComparison]::Ordinal
)) {
    throw (
        'process VBOX_USER_HOME changed during inspection: ' +
        "before=$OriginalVBoxUserHome after=$FinalVBoxUserHome"
    )
}
if (Test-Path -LiteralPath $PreparationReport) {
    throw "preparation report appeared during inspection: $PreparationReport"
}
if (Test-Path -LiteralPath $ManifestPath) {
    throw "final boot-attempt manifest appeared during inspection: $ManifestPath"
}

$Lines = [System.Collections.Generic.List[string]]::new()
$Lines.Add('DBYTE-HOLYC-OPT')
$Lines.Add('TEMPLEOSTS 1.10 VDI-ONLY BOOT INCOMPLETE R1 READ-ONLY INSPECTION')
$Lines.Add('')
$Lines.Add("created_utc`t$([DateTimeOffset]::UtcNow.ToString('o'))")
$Lines.Add("incomplete_root`t$Root")
$Lines.Add("preparation_report`t$PreparationReport")
$Lines.Add("preparation_report_absent`tTrue")
$Lines.Add("process_vbox_user_home_before`t$OriginalVBoxUserHome")
$Lines.Add("process_vbox_user_home_after`t$FinalVBoxUserHome")
$Lines.Add('vboxmanage_invocation`tNOT-EXECUTED')
$Lines.Add('virtualbox_mutation`tNOT-EXECUTED')
$Lines.Add('vm_start`tNOT-AUTHORIZED')
$Lines.Add('')
$Lines.Add("vbox_path`t$($VBox.Path)")
$Lines.Add("vbox_bytes`t$($VBox.Bytes)")
$Lines.Add("vbox_sha256`t$($VBox.SHA256)")
$Lines.Add("vbox_file_id`t$VBoxFileId")
$Lines.Add("vdi_path`t$($Vdi.Path)")
$Lines.Add("vdi_bytes`t$($Vdi.Bytes)")
$Lines.Add("vdi_sha256`t$($Vdi.SHA256)")
$Lines.Add("vdi_file_id`t$VdiFileId")
$Lines.Add("iso_path`t$($Iso.Path)")
$Lines.Add("iso_bytes`t$($Iso.Bytes)")
$Lines.Add("iso_sha256`t$($Iso.SHA256)")
$Lines.Add("iso_file_id`t$IsoFileId")
$Lines.Add("incomplete_marker_bytes`t$($IncompleteItem.Length)")
$Lines.Add("incomplete_marker_sha256`t$IncompleteHash")
$Lines.Add("final_manifest_absent`tTrue")
$Lines.Add("vbox_user_home_file_count`t$($VBoxUserHomeFiles.Count)")
$Lines.Add("vbox_user_home_directory_count`t$($VBoxUserHomeDirectories.Count)")
$Lines.Add('')
$Lines.Add("hard_disk_row_count`t$($HardDisks.Count)")
for ($Index = 0; $Index -lt $HardDisks.Count; $Index++) {
    $Node = $HardDisks[$Index]
    $Number = $Index + 1
    $Lines.Add("hard_disk_${Number}_uuid`t$($Node.GetAttribute('uuid'))")
    $Lines.Add("hard_disk_${Number}_location`t$($Node.GetAttribute('location'))")
    $Lines.Add("hard_disk_${Number}_format`t$($Node.GetAttribute('format'))")
    $Lines.Add("hard_disk_${Number}_type`t$($Node.GetAttribute('type'))")
}
$Lines.Add("dvd_image_row_count`t$($DvdImages.Count)")
for ($Index = 0; $Index -lt $DvdImages.Count; $Index++) {
    $Node = $DvdImages[$Index]
    $Number = $Index + 1
    $Lines.Add("dvd_image_${Number}_uuid`t$($Node.GetAttribute('uuid'))")
    $Lines.Add("dvd_image_${Number}_location`t$($Node.GetAttribute('location'))")
}
$Lines.Add("target_vdi_uuid`t$ExpectedVdiUuid")
$Lines.Add("target_vdi_location`t$TargetVdiLocation")
$Lines.Add("target_iso_uuid`t$ExpectedIsoUuid")
$Lines.Add("target_iso_location`t$TargetIsoLocation")
$Lines.Add('')
foreach ($Key in $OccurrenceRows.Keys) {
    $Lines.Add("${Key}_occurrences`t$($OccurrenceRows[$Key])")
}
$Lines.Add('')
$Lines.Add("directory_count`t$($AllDirectories.Count)")
for ($Index = 0; $Index -lt $AllDirectories.Count; $Index++) {
    $Relative = $AllDirectories[$Index].FullName.Substring($Root.Length).TrimStart('\', '/')
    $Lines.Add("directory_$($Index + 1)`t$Relative")
}
$Lines.Add("file_count`t$($AllFiles.Count)")
for ($Index = 0; $Index -lt $AllFiles.Count; $Index++) {
    $File = $AllFiles[$Index]
    $Relative = $File.FullName.Substring($Root.Length).TrimStart('\', '/')
    $Hash = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash
    $Lines.Add("file_$($Index + 1)_relative`t$Relative")
    $Lines.Add("file_$($Index + 1)_bytes`t$($File.Length)")
    $Lines.Add("file_$($Index + 1)_sha256`t$Hash")
}
$Lines.Add('')
$Lines.Add('INSPECTION`tCOMPLETE')
$Lines.Add('INCOMPLETE ROOT`tPRESERVED')
$Lines.Add('COPIED VBOX REWRITE`tNOT-OBSERVED')
$Lines.Add('COPIED VM REGISTRATION`tNOT-EXECUTED')
$Lines.Add('COPIED VM CONFIGURATION MUTATION`tNOT-EXECUTED')
$Lines.Add('VM START`tNOT-AUTHORIZED')
$Lines.Add('RESTORE BOOT`tNOT-OBSERVED')
$Lines.Add('RECOVERY POINT`tNOT-SEALED')
$Lines.Add('BUILD EXECUTION`tNOT-AUTHORIZED')
$Lines.Add('VERDICT`tINCOMPLETE R1 MEDIA-LOCATION INSPECTION COMPLETE')

Write-Utf8Lines -Path $Output -Lines $Lines.ToArray()
$ReportHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

Write-Host "INCOMPLETE ROOT:       $Root"
Write-Host "VBOX SHA256:           $($VBox.SHA256)"
Write-Host "VBOX FILE ID:          $VBoxFileId"
Write-Host "VDI FILE ID:           $VdiFileId"
Write-Host "ISO FILE ID:           $IsoFileId"
Write-Host "TARGET VDI LOCATION:   $TargetVdiLocation"
Write-Host "TARGET ISO LOCATION:   $TargetIsoLocation"
Write-Host "SEALED VDI ABS COUNT:  $($OccurrenceRows.sealed_vdi_absolute)"
Write-Host "COPIED VDI ABS COUNT:  $($OccurrenceRows.copied_vdi_absolute)"
Write-Host "VDI BASENAME COUNT:    $($OccurrenceRows.vdi_basename)"
Write-Host "SEALED ISO ABS COUNT:  $($OccurrenceRows.sealed_iso_absolute)"
Write-Host "COPIED ISO ABS COUNT:  $($OccurrenceRows.copied_iso_absolute)"
Write-Host "ISO BASENAME COUNT:    $($OccurrenceRows.iso_basename)"
Write-Host "VBOXUSERHOME FILES:    $($VBoxUserHomeFiles.Count)"
Write-Host "VBOXUSERHOME DIRS:     $($VBoxUserHomeDirectories.Count)"
Write-Host "REPORT:                $Output"
Write-Host "REPORT SHA256:         $ReportHash"
Write-Host 'VBOXMANAGE:            NOT-EXECUTED'
Write-Host 'VIRTUALBOX MUTATION:   NOT-EXECUTED'
Write-Host 'VM START:              NOT-AUTHORIZED'
Write-Host 'VERDICT:               INCOMPLETE R1 MEDIA-LOCATION INSPECTION COMPLETE'
