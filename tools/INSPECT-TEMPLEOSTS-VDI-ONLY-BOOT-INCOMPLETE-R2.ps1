[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$IncompleteRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PreservedR1Root,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PreparationReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedR2Root = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r2'
$ExpectedR1Root = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r1'
$ExpectedPreparationReport = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-boot-attempt-preparation.txt'
$ExpectedOut = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r2-incomplete-inspection.txt'

$ExpectedR1VBoxHash = '69224A832694CA0C657CA2135ED370F6B7E667B84F93C08D921AED4A6D21F39B'
$ExpectedR1VBoxFileId = '0X0000000000000000000100000006034F'
$ExpectedR1VdiFileId = '0X00000000000000000001000000060350'
$ExpectedR1IsoFileId = '0X00000000000000000001000000060351'

$ExpectedVdiBytes = 2097152L
$ExpectedVdiHash = '90D453A94F075760A11E0772862E60C4B031ED874F28AA396EAE638F7EB8B31B'
$ExpectedIsoBytes = 30558208L
$ExpectedIsoHash = 'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$ExpectedMachineUuid = '9c98691e-27cd-4487-a306-587969c2c78c'
$ExpectedVdiUuid = '55c1f29d-a681-402e-b90d-bfbb6b09f207'
$ExpectedIsoUuid = 'ab97b3a5-1331-494d-a917-e85b6e728c45'
$ExpectedVdiLocation = 'Temple1.10.vdi'
$ExpectedIsoLocation = 'TempleOSTS.iso'

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

function Get-NormalizedUuid {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    return $Value.Trim().Trim('{', '}').ToLowerInvariant()
}

function Assert-ExactFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][long]$Bytes,
        [Parameter(Mandatory = $true)][string]$SHA256,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "${Label} missing: $Path"
    }
    $Item = Get-Item -LiteralPath $Path -Force
    if ($Item.Length -ne $Bytes) {
        throw "${Label} byte mismatch: observed=$($Item.Length) expected=$Bytes"
    }
    $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($Hash -cne $SHA256) {
        throw "${Label} SHA256 mismatch: observed=$Hash expected=$SHA256"
    }
    return [pscustomobject]@{
        Path = $Item.FullName
        Bytes = $Item.Length
        SHA256 = $Hash
        FileId = (Get-FileId -Path $Item.FullName -Label $Label)
    }
}

function Add-NodeAttributes {
    param(
        [Parameter(Mandatory = $true)][System.Collections.Generic.List[string]]$Lines,
        [Parameter(Mandatory = $true)][string]$Prefix,
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$Node
    )

    $Lines.Add("${Prefix}_name`t$($Node.LocalName)")
    if ($null -eq $Node.Attributes -or $Node.Attributes.Count -eq 0) {
        $Lines.Add("${Prefix}_attribute_count`t0")
        return
    }

    $Attributes = @($Node.Attributes | Sort-Object Name)
    $Lines.Add("${Prefix}_attribute_count`t$($Attributes.Count)")
    foreach ($Attribute in $Attributes) {
        $Lines.Add("${Prefix}_attribute`t$($Attribute.Name)`t$($Attribute.Value)")
    }
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $RootFull = Get-FullPath -Path $Root
    $PathFull = Get-FullPath -Path $Path
    if (-not $PathFull.StartsWith(
        $RootFull + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "path is outside expected root: root=$RootFull path=$PathFull"
    }
    return $PathFull.Substring($RootFull.Length + 1)
}

$R2 = Get-FullPath -Path $IncompleteRoot
$R1 = Get-FullPath -Path $PreservedR1Root
$PreparationReport = Get-FullPath -Path $PreparationReportPath
$Output = Get-FullPath -Path $OutPath

Assert-PathEquals -Observed $R2 -Expected $ExpectedR2Root -Label 'r2 incomplete root'
Assert-PathEquals -Observed $R1 -Expected $ExpectedR1Root -Label 'r1 preserved root'
Assert-PathEquals -Observed $PreparationReport -Expected $ExpectedPreparationReport -Label 'preparation report'
Assert-PathEquals -Observed $Output -Expected $ExpectedOut -Label 'inspection report'

if (-not (Test-Path -LiteralPath $R2 -PathType Container)) {
    throw "r2 incomplete root missing: $R2"
}
if (-not (Test-Path -LiteralPath $R1 -PathType Container)) {
    throw "r1 preserved root missing: $R1"
}
if (Test-Path -LiteralPath $PreparationReport) {
    throw "final preparation report exists: $PreparationReport"
}
if (Test-Path -LiteralPath $Output) {
    throw "inspection report already exists: $Output"
}
$OutputParent = Split-Path -Parent $Output
if (-not (Test-Path -LiteralPath $OutputParent -PathType Container)) {
    throw "inspection report parent missing: $OutputParent"
}

$R1Machine = Join-Path $R1 'Machine'
$R1VBox = Join-Path $R1Machine 'Temple1.10.vbox'
$R1Vdi = Join-Path $R1Machine 'Temple1.10.vdi'
$R1Iso = Join-Path $R1Machine 'TempleOSTS.iso'
if ((Get-FileHash -LiteralPath $R1VBox -Algorithm SHA256).Hash -cne $ExpectedR1VBoxHash) {
    throw 'r1 VBOX identity changed'
}
if ((Get-FileId -Path $R1VBox -Label 'r1 VBOX') -cne $ExpectedR1VBoxFileId) {
    throw 'r1 VBOX file ID changed'
}
if ((Get-FileId -Path $R1Vdi -Label 'r1 VDI') -cne $ExpectedR1VdiFileId) {
    throw 'r1 VDI file ID changed'
}
if ((Get-FileId -Path $R1Iso -Label 'r1 ISO') -cne $ExpectedR1IsoFileId) {
    throw 'r1 ISO file ID changed'
}

$MachineRoot = Join-Path $R2 'Machine'
$VBoxUserHome = Join-Path $R2 'VBoxUserHome'
$IncompleteMarker = Join-Path $R2 'BOOT-ATTEMPT-INCOMPLETE.txt'
$ManifestPath = Join-Path $R2 'BOOT-ATTEMPT-MANIFEST.txt'
$VBoxPath = Join-Path $MachineRoot 'Temple1.10.vbox'
$VdiPath = Join-Path $MachineRoot 'Temple1.10.vdi'
$IsoPath = Join-Path $MachineRoot 'TempleOSTS.iso'

if (-not (Test-Path -LiteralPath $IncompleteMarker -PathType Leaf)) {
    throw "r2 incomplete marker missing: $IncompleteMarker"
}
if (Test-Path -LiteralPath $ManifestPath) {
    throw "r2 final manifest unexpectedly exists: $ManifestPath"
}
if (-not (Test-Path -LiteralPath $VBoxPath -PathType Leaf)) {
    throw "r2 VBOX missing: $VBoxPath"
}

$Vdi = Assert-ExactFile -Path $VdiPath -Bytes $ExpectedVdiBytes -SHA256 $ExpectedVdiHash -Label 'r2 VDI'
$Iso = Assert-ExactFile -Path $IsoPath -Bytes $ExpectedIsoBytes -SHA256 $ExpectedIsoHash -Label 'r2 ISO'
$VBoxItem = Get-Item -LiteralPath $VBoxPath -Force
$VBoxHash = (Get-FileHash -LiteralPath $VBoxPath -Algorithm SHA256).Hash
$VBoxFileId = Get-FileId -Path $VBoxPath -Label 'r2 VBOX'
$VBoxMatchesPreRegistrationHash = $VBoxHash -ceq $ExpectedR1VBoxHash

[xml]$VBoxXml = [System.IO.File]::ReadAllText($VBoxPath)
$MachineNodes = @($VBoxXml.SelectNodes("//*[local-name()='Machine']"))
if ($MachineNodes.Count -ne 1) {
    throw "r2 VBOX Machine node count mismatch: $($MachineNodes.Count)"
}
$MachineNode = $MachineNodes[0]
$MachineUuid = Get-NormalizedUuid -Value $MachineNode.GetAttribute('uuid')
if ($MachineUuid -cne $ExpectedMachineUuid) {
    throw "r2 machine UUID mismatch: $MachineUuid"
}

$HardDisks = @($VBoxXml.SelectNodes("//*[local-name()='MediaRegistry']/*[local-name()='HardDisks']/*[local-name()='HardDisk']"))
$TargetVdiRows = @(
    $HardDisks | Where-Object {
        (Get-NormalizedUuid -Value $_.GetAttribute('uuid')) -ceq $ExpectedVdiUuid
    }
)
if ($TargetVdiRows.Count -ne 1) {
    throw "r2 target VDI registry row count mismatch: $($TargetVdiRows.Count)"
}
$TargetVdiLocation = $TargetVdiRows[0].GetAttribute('location')
$TargetVdiLocationMatches = $TargetVdiLocation -ceq $ExpectedVdiLocation

$DvdImages = @($VBoxXml.SelectNodes("//*[local-name()='MediaRegistry']/*[local-name()='DVDImages']/*[local-name()='Image']"))
$TargetIsoRows = @(
    $DvdImages | Where-Object {
        (Get-NormalizedUuid -Value $_.GetAttribute('uuid')) -ceq $ExpectedIsoUuid
    }
)
$TargetIsoLocations = @($TargetIsoRows | ForEach-Object { $_.GetAttribute('location') })
$TargetIsoLocationMatches = (
    $TargetIsoRows.Count -eq 0 -or
    (
        $TargetIsoRows.Count -eq 1 -and
        $TargetIsoLocations[0] -ceq $ExpectedIsoLocation
    )
)

$AttachedImages = @($VBoxXml.SelectNodes("//*[local-name()='AttachedDevice']/*[local-name()='Image']"))
$AttachedTargetIso = @(
    $AttachedImages | Where-Object {
        (Get-NormalizedUuid -Value $_.GetAttribute('uuid')) -ceq $ExpectedIsoUuid
    }
)

$BootOrderNodes = @($VBoxXml.SelectNodes("//*[local-name()='Boot']/*[local-name()='Order']"))
$NetworkAdapterNodes = @($VBoxXml.SelectNodes("//*[local-name()='Network']/*[local-name()='Adapter']"))
$GraphicsNodes = @($VBoxXml.SelectNodes("//*[local-name()='GraphicsAdapter']"))
$ClipboardDragNodes = @(
    $VBoxXml.SelectNodes('//*') | Where-Object {
        $_.LocalName -match '(?i)clipboard|drag'
    }
)
$StorageDeviceNodes = @($VBoxXml.SelectNodes("//*[local-name()='StorageController']/*[local-name()='AttachedDevice']"))

$MachineFiles = @(
    Get-ChildItem -LiteralPath $MachineRoot -Recurse -Force -File |
        Sort-Object FullName
)
$HomeFiles = if (Test-Path -LiteralPath $VBoxUserHome -PathType Container) {
    @(
        Get-ChildItem -LiteralPath $VBoxUserHome -Recurse -Force -File |
            Sort-Object FullName
    )
}
else {
    @()
}
$HomeDirectories = if (Test-Path -LiteralPath $VBoxUserHome -PathType Container) {
    @(
        Get-ChildItem -LiteralPath $VBoxUserHome -Recurse -Force -Directory |
            Sort-Object FullName
    )
}
else {
    @()
}

$RegistryXmlPath = Join-Path $VBoxUserHome 'VirtualBox.xml'
$RegistryMachineEntries = @()
$RegistryMachineUuidEntries = @()
if (Test-Path -LiteralPath $RegistryXmlPath -PathType Leaf) {
    [xml]$RegistryXml = [System.IO.File]::ReadAllText($RegistryXmlPath)
    $RegistryMachineEntries = @($RegistryXml.SelectNodes("//*[local-name()='MachineRegistry']/*[local-name()='MachineEntry']"))
    $RegistryMachineUuidEntries = @(
        $RegistryMachineEntries | Where-Object {
            (Get-NormalizedUuid -Value $_.GetAttribute('uuid')) -ceq $ExpectedMachineUuid
        }
    )
}

$Lines = [System.Collections.Generic.List[string]]::new()
$Lines.Add('DBYTE-HOLYC-OPT')
$Lines.Add('TEMPLEOSTS 1.10 VDI-ONLY BOOT INCOMPLETE R2 READ-ONLY INSPECTION')
$Lines.Add('')
$Lines.Add("incomplete_root`t$R2")
$Lines.Add("preserved_r1_root`t$R1")
$Lines.Add("preparation_report_absent`t$(-not (Test-Path -LiteralPath $PreparationReport))")
$Lines.Add("incomplete_marker_present`t$((Test-Path -LiteralPath $IncompleteMarker -PathType Leaf))")
$Lines.Add("final_manifest_absent`t$(-not (Test-Path -LiteralPath $ManifestPath))")
$Lines.Add('')
$Lines.Add("machine_uuid`t$MachineUuid")
$Lines.Add("vbox_bytes`t$($VBoxItem.Length)")
$Lines.Add("vbox_sha256`t$VBoxHash")
$Lines.Add("vbox_file_id`t$VBoxFileId")
$Lines.Add("vbox_matches_pre_registration_hash`t$VBoxMatchesPreRegistrationHash")
$Lines.Add("vdi_bytes`t$($Vdi.Bytes)")
$Lines.Add("vdi_sha256`t$($Vdi.SHA256)")
$Lines.Add("vdi_file_id`t$($Vdi.FileId)")
$Lines.Add("iso_bytes`t$($Iso.Bytes)")
$Lines.Add("iso_sha256`t$($Iso.SHA256)")
$Lines.Add("iso_file_id`t$($Iso.FileId)")
$Lines.Add('')
$Lines.Add("target_vdi_registry_rows`t$($TargetVdiRows.Count)")
$Lines.Add("target_vdi_location`t$TargetVdiLocation")
$Lines.Add("target_vdi_location_matches_expected`t$TargetVdiLocationMatches")
$Lines.Add("target_iso_registry_rows`t$($TargetIsoRows.Count)")
foreach ($Location in $TargetIsoLocations) {
    $Lines.Add("target_iso_location`t$Location")
}
$Lines.Add("target_iso_location_matches_expected`t$TargetIsoLocationMatches")
$Lines.Add("attached_target_iso_count`t$($AttachedTargetIso.Count)")
$Lines.Add('')

$VBoxLikeFiles = @(
    $MachineFiles | Where-Object {
        $_.Name -match '(?i)\.vbox(?:-.+)?$|\.vbox-prev$|\.vbox-new$'
    }
)
$Lines.Add("machine_file_count`t$($MachineFiles.Count)")
$Lines.Add("vbox_like_file_count`t$($VBoxLikeFiles.Count)")
foreach ($File in $MachineFiles) {
    $Relative = Get-RelativePath -Root $R2 -Path $File.FullName
    $Hash = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash
    $Lines.Add("machine_file`t$Relative`t$($File.Length)`t$Hash")
}
foreach ($File in $VBoxLikeFiles) {
    $Relative = Get-RelativePath -Root $R2 -Path $File.FullName
    $Hash = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash
    $FileId = Get-FileId -Path $File.FullName -Label "r2 VBOX-like file $Relative"
    $Lines.Add("vbox_like_file`t$Relative`t$($File.Length)`t$Hash`t$FileId")
}
$Lines.Add('')

$Lines.Add("boot_order_node_count`t$($BootOrderNodes.Count)")
for ($Index = 0; $Index -lt $BootOrderNodes.Count; $Index++) {
    Add-NodeAttributes -Lines $Lines -Prefix "boot_order_$($Index + 1)" -Node $BootOrderNodes[$Index]
}
$Lines.Add('')
$Lines.Add("network_adapter_node_count`t$($NetworkAdapterNodes.Count)")
for ($Index = 0; $Index -lt $NetworkAdapterNodes.Count; $Index++) {
    Add-NodeAttributes -Lines $Lines -Prefix "network_adapter_$($Index + 1)" -Node $NetworkAdapterNodes[$Index]
}
$Lines.Add('')
$Lines.Add("clipboard_drag_node_count`t$($ClipboardDragNodes.Count)")
for ($Index = 0; $Index -lt $ClipboardDragNodes.Count; $Index++) {
    Add-NodeAttributes -Lines $Lines -Prefix "clipboard_drag_$($Index + 1)" -Node $ClipboardDragNodes[$Index]
}
$Lines.Add('')
$Lines.Add("graphics_node_count`t$($GraphicsNodes.Count)")
for ($Index = 0; $Index -lt $GraphicsNodes.Count; $Index++) {
    Add-NodeAttributes -Lines $Lines -Prefix "graphics_$($Index + 1)" -Node $GraphicsNodes[$Index]
}
$Lines.Add('')
$Lines.Add("storage_device_node_count`t$($StorageDeviceNodes.Count)")
for ($Index = 0; $Index -lt $StorageDeviceNodes.Count; $Index++) {
    $Node = $StorageDeviceNodes[$Index]
    Add-NodeAttributes -Lines $Lines -Prefix "storage_device_$($Index + 1)" -Node $Node
    $ImageNodes = @($Node.SelectNodes("./*[local-name()='Image']"))
    foreach ($ImageNode in $ImageNodes) {
        $Lines.Add("storage_device_$($Index + 1)_image_uuid`t$($ImageNode.GetAttribute('uuid'))")
    }
}
$Lines.Add('')

$Lines.Add("vbox_user_home_present`t$((Test-Path -LiteralPath $VBoxUserHome -PathType Container))")
$Lines.Add("vbox_user_home_file_count`t$($HomeFiles.Count)")
$Lines.Add("vbox_user_home_directory_count`t$($HomeDirectories.Count)")
foreach ($File in $HomeFiles) {
    $Relative = Get-RelativePath -Root $R2 -Path $File.FullName
    $Hash = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash
    $Lines.Add("vbox_user_home_file`t$Relative`t$($File.Length)`t$Hash")
}
$Lines.Add("isolated_registry_xml_present`t$((Test-Path -LiteralPath $RegistryXmlPath -PathType Leaf))")
$Lines.Add("isolated_registry_machine_entry_count`t$($RegistryMachineEntries.Count)")
$Lines.Add("isolated_registry_target_entry_count`t$($RegistryMachineUuidEntries.Count)")
for ($Index = 0; $Index -lt $RegistryMachineEntries.Count; $Index++) {
    Add-NodeAttributes -Lines $Lines -Prefix "registry_machine_entry_$($Index + 1)" -Node $RegistryMachineEntries[$Index]
}
$Lines.Add('')
$Lines.Add("vboxmanage_invocation`tNOT-EXECUTED")
$Lines.Add("virtualbox_mutation`tNOT-EXECUTED")
$Lines.Add("vm_start`tNOT-AUTHORIZED")
$Lines.Add("INSPECTION`tCOMPLETE")
$Lines.Add("R1 ROOT`tPRESERVED")
$Lines.Add("R2 ROOT`tPRESERVED")
$Lines.Add('')
$Lines.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')

[System.IO.File]::WriteAllText(
    $Output,
    (($Lines.ToArray() -join "`n") + "`n"),
    [System.Text.UTF8Encoding]::new($false)
)
$ReportHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

Write-Host "INCOMPLETE R2 ROOT:    $R2"
Write-Host "VBOX SHA256:           $VBoxHash"
Write-Host "VBOX FILE ID:          $VBoxFileId"
Write-Host "VBOX MATCHES PRECOPY:  $VBoxMatchesPreRegistrationHash"
Write-Host "VDI FILE ID:           $($Vdi.FileId)"
Write-Host "ISO FILE ID:           $($Iso.FileId)"
Write-Host "TARGET VDI LOCATION:   $TargetVdiLocation"
Write-Host "TARGET VDI EXPECTED:   $TargetVdiLocationMatches"
Write-Host "TARGET ISO ROWS:       $($TargetIsoRows.Count)"
if ($TargetIsoLocations.Count -eq 0) {
    Write-Host 'TARGET ISO LOCATION:   <missing>'
}
else {
    foreach ($Location in $TargetIsoLocations) {
        Write-Host "TARGET ISO LOCATION:   $Location"
    }
}
Write-Host "TARGET ISO EXPECTED:   $TargetIsoLocationMatches"
Write-Host "ATTACHED ISO COUNT:    $($AttachedTargetIso.Count)"
Write-Host "VBOX-LIKE FILES:       $($VBoxLikeFiles.Count)"
Write-Host "BOOT ORDER NODES:      $($BootOrderNodes.Count)"
Write-Host "NETWORK ADAPTER NODES: $($NetworkAdapterNodes.Count)"
Write-Host "CLIP/DRAG NODES:       $($ClipboardDragNodes.Count)"
Write-Host "GRAPHICS NODES:        $($GraphicsNodes.Count)"
Write-Host "VBOXUSERHOME FILES:    $($HomeFiles.Count)"
Write-Host "REGISTRY TARGET ROWS:  $($RegistryMachineUuidEntries.Count)"
Write-Host "REPORT:                 $Output"
Write-Host "REPORT SHA256:          $ReportHash"
Write-Host 'VBOXMANAGE:             NOT-EXECUTED'
Write-Host 'VIRTUALBOX MUTATION:    NOT-EXECUTED'
Write-Host 'VM START:               NOT-AUTHORIZED'
Write-Host 'VERDICT:                INCOMPLETE R2 READ-ONLY INSPECTION COMPLETE'