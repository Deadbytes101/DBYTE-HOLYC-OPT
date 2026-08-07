[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PreparedRoot,

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
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r3'
$ExpectedReport =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-boot-attempt-preparation.txt'
$ExpectedOut =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r3-prepared-verification.txt'

$ExpectedReportHash =
    '2A2986A07E04C854E27CCC04198C1F9935208F429969C9FDA33E8818E81CE4EC'
$ExpectedManifestHash =
    '4A6E43CC01A2686DBAD4FD0D64185D7E23FBE691CBEECAD65742A8F1957D4DAF'

$ExpectedMachineName = 'Temple1.10'
$ExpectedMachineUuid = '9c98691e-27cd-4487-a306-587969c2c78c'
$ExpectedVdiUuid = '55c1f29d-a681-402e-b90d-bfbb6b09f207'
$ExpectedIsoUuid = 'ab97b3a5-1331-494d-a917-e85b6e728c45'
$ExpectedVBoxVersion = '7.0.12r159484'

$ExpectedPreRegistrationVBoxHash =
    '69224A832694CA0C657CA2135ED370F6B7E667B84F93C08D921AED4A6D21F39B'
$ExpectedCurrentVBoxHash =
    '8EADB39D54CABE5E7B791E5D7E05BCF4CBBF32D4AB6B58291BEC0B2FAD607C0C'
$ExpectedPreviousVBoxHash =
    'C93D128227EE80B647DB63FE64277CEF1BDC61C224110472C73CBFFEC63877A7'
$ExpectedVdiHash =
    '90D453A94F075760A11E0772862E60C4B031ED874F28AA396EAE638F7EB8B31B'
$ExpectedIsoHash =
    'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'

$ExpectedPreRegistrationVBoxId = '0X000000000000000000010000000609A1'
$ExpectedCurrentVBoxId = '0X000000000000000000050000000609A1'
$ExpectedPreviousVBoxId = '0X000000000000000000040000000609A7'
$ExpectedVdiId = '0X000000000000000000010000000609A2'
$ExpectedIsoId = '0X000000000000000000010000000609A3'

$ExpectedVdiBytes = 2097152L
$ExpectedIsoBytes = 30558208L

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
        throw "${Label} file-ID query failed`n$($Captured -join "`n")"
    }

    $Ids = @(
        foreach ($Line in $Captured) {
            foreach ($Match in [regex]::Matches($Line, '0x[0-9A-Fa-f]+')) {
                $Match.Value.ToUpperInvariant()
            }
        }
    )
    if ($Ids.Count -ne 1) {
        throw "${Label} file-ID parse mismatch: count=$($Ids.Count)"
    }
    return $Ids[0]
}

function Assert-ExactFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [long]$Bytes = -1,
        [Parameter(Mandatory = $true)][string]$SHA256,
        [Parameter(Mandatory = $true)][string]$FileId,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "${Label} missing: $Path"
    }
    $Item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($Bytes -ge 0 -and $Item.Length -ne $Bytes) {
        throw "${Label} byte count mismatch: observed=$($Item.Length) expected=$Bytes"
    }
    $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($Hash -cne $SHA256) {
        throw "${Label} SHA256 mismatch: observed=$Hash expected=$SHA256"
    }
    $ObservedId = Get-FileId -Path $Path -Label $Label
    if ($ObservedId -cne $FileId) {
        throw "${Label} file-ID mismatch: observed=$ObservedId expected=$FileId"
    }
    return [pscustomobject]@{
        Path = $Item.FullName
        Bytes = [long]$Item.Length
        SHA256 = $Hash
        FileId = $ObservedId
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

function Assert-FieldEquals {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Expected
    )

    $Observed = Get-ExactField -Lines $Lines -Key $Key
    if ($Observed -cne $Expected) {
        throw "field mismatch: key=$Key observed=$Observed expected=$Expected"
    }
}

function ConvertTo-NormalizedUuid {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Normalized = $Value.Trim().Trim('{', '}').ToLowerInvariant()
    $Parsed = [Guid]::Empty
    if (-not [Guid]::TryParse($Normalized, [ref]$Parsed)) {
        throw "${Label} is not a UUID: $Value"
    }
    return $Parsed.ToString('D').ToLowerInvariant()
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $RootFull = Get-FullPath -Path $Root
    $PathFull = Get-FullPath -Path $Path
    $Prefix = $RootFull + [System.IO.Path]::DirectorySeparatorChar
    if (-not $PathFull.StartsWith(
        $Prefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "path is outside prepared root: $PathFull"
    }
    return $PathFull.Substring($Prefix.Length)
}

function Test-IsVolatileLogPath {
    param([Parameter(Mandatory = $true)][string]$Relative)

    return $Relative.Replace('/', '\') -cmatch
        '^VBoxUserHome\\VBoxSVC\.log(?:\.[1-9][0-9]*)?$'
}

function Convert-InventoryRow {
    param(
        [Parameter(Mandatory = $true)][string]$Line,
        [Parameter(Mandatory = $true)][string]$ExpectedKey
    )

    $Parts = @($Line.Split([char]9))
    if ($Parts.Count -ne 4 -or $Parts[0] -cne $ExpectedKey) {
        throw "${ExpectedKey} inventory row shape mismatch: $Line"
    }
    if (
        [string]::IsNullOrWhiteSpace($Parts[1]) -or
        [System.IO.Path]::IsPathRooted($Parts[1]) -or
        $Parts[1] -match '(^|[\\/])\.\.([\\/]|$)'
    ) {
        throw "${ExpectedKey} inventory relative path invalid: $($Parts[1])"
    }
    $Bytes = 0L
    if (-not [long]::TryParse($Parts[2], [ref]$Bytes)) {
        throw "${ExpectedKey} inventory byte parse failed: $Line"
    }
    if ($Parts[3] -notmatch '^[0-9A-F]{64}$') {
        throw "${ExpectedKey} inventory SHA256 shape mismatch: $Line"
    }
    return [pscustomobject]@{
        Relative = $Parts[1].Replace('/', '\')
        Bytes = $Bytes
        SHA256 = $Parts[3]
    }
}

$Root = (Resolve-Path -LiteralPath $PreparedRoot -ErrorAction Stop).Path
$Report = (Resolve-Path -LiteralPath $PreparationReportPath -ErrorAction Stop).Path
$Output = Get-FullPath -Path $OutPath

Assert-PathEquals -Observed $Root -Expected $ExpectedRoot -Label 'prepared r3 root'
Assert-PathEquals -Observed $Report -Expected $ExpectedReport -Label 'preparation report'
Assert-PathEquals -Observed $Output -Expected $ExpectedOut -Label 'verification report'

if (Test-Path -LiteralPath $Output) {
    throw "verification report already exists: $Output"
}
$OutputParent = Split-Path -Parent $Output
if (-not (Test-Path -LiteralPath $OutputParent -PathType Container)) {
    throw "verification report parent missing: $OutputParent"
}

$MachineRoot = Join-Path $Root 'Machine'
$HomeRoot = Join-Path $Root 'VBoxUserHome'
$ManifestPath = Join-Path $Root 'BOOT-ATTEMPT-MANIFEST.txt'
$IncompletePath = Join-Path $Root 'BOOT-ATTEMPT-INCOMPLETE.txt'
$CurrentVBoxPath = Join-Path $MachineRoot 'Temple1.10.vbox'
$PreviousVBoxPath = Join-Path $MachineRoot 'Temple1.10.vbox-prev'
$VdiPath = Join-Path $MachineRoot 'Temple1.10.vdi'
$IsoPath = Join-Path $MachineRoot 'TempleOSTS.iso'
$RegistryPath = Join-Path $HomeRoot 'VirtualBox.xml'

if (-not (Test-Path -LiteralPath $MachineRoot -PathType Container)) {
    throw "prepared Machine directory missing: $MachineRoot"
}
if (-not (Test-Path -LiteralPath $HomeRoot -PathType Container)) {
    throw "prepared VBoxUserHome directory missing: $HomeRoot"
}
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "prepared manifest missing: $ManifestPath"
}
if (Test-Path -LiteralPath $IncompletePath) {
    throw "prepared incomplete marker still exists: $IncompletePath"
}
if (-not (Test-Path -LiteralPath $RegistryPath -PathType Leaf)) {
    throw "isolated VirtualBox registry missing: $RegistryPath"
}

$ReportHash = (Get-FileHash -LiteralPath $Report -Algorithm SHA256).Hash
if ($ReportHash -cne $ExpectedReportHash) {
    throw "preparation report SHA256 mismatch: observed=$ReportHash expected=$ExpectedReportHash"
}
$ManifestHash = (Get-FileHash -LiteralPath $ManifestPath -Algorithm SHA256).Hash
if ($ManifestHash -cne $ExpectedManifestHash) {
    throw "prepared manifest SHA256 mismatch: observed=$ManifestHash expected=$ExpectedManifestHash"
}

$ReportLines = @([System.IO.File]::ReadAllLines($Report))
$ManifestLines = @([System.IO.File]::ReadAllLines($ManifestPath))

$ReportFields = [ordered]@{
    boot_attempt_manifest_sha256 = $ExpectedManifestHash
    boot_attempt_root = $ExpectedRoot
    isolated_vbox_user_home = (Join-Path $ExpectedRoot 'VBoxUserHome')
    virtualbox_version = $ExpectedVBoxVersion
    machine_name = $ExpectedMachineName
    machine_uuid = $ExpectedMachineUuid
    machine_state = 'poweroff'
    vdi_uuid = $ExpectedVdiUuid
    iso_uuid = $ExpectedIsoUuid
    dvd_controller = 'IDE'
    iso_slot_value_after_detach = 'none'
    boot1 = 'disk'
    boot2 = 'none'
    boot3 = 'none'
    boot4 = 'none'
    network_disabled = 'True'
    clipboard_disabled = 'True'
    drag_and_drop_disabled = 'True'
    iso_attached = 'False'
    boot_vbox_sha256 = $ExpectedCurrentVBoxHash
    boot_vbox_pre_registration_file_id = $ExpectedPreRegistrationVBoxId
    boot_vbox_post_correction_file_id = $ExpectedCurrentVBoxId
    boot_vbox_prev_sha256 = $ExpectedPreviousVBoxHash
    boot_vbox_prev_file_id = $ExpectedPreviousVBoxId
    boot_vbox_prev_matches_pre_registration_hash = 'False'
    boot_vdi_sha256 = $ExpectedVdiHash
    boot_vdi_file_id = $ExpectedVdiId
    boot_iso_sha256 = $ExpectedIsoHash
    boot_iso_file_id = $ExpectedIsoId
    'BOOT ATTEMPT COPY' = 'PREPARED'
    'POWERED-OFF CORRECTED CONFIGURATION' = 'OBSERVED'
    'VM START' = 'NOT-AUTHORIZED'
    'RESTORE BOOT' = 'NOT-OBSERVED'
    'POWERED-OFF RECOVERY POINT' = 'NOT-SEALED'
    'BUILD EXECUTION' = 'NOT-AUTHORIZED'
}
foreach ($Key in $ReportFields.Keys) {
    Assert-FieldEquals `
        -Lines $ReportLines `
        -Key $Key `
        -Expected ([string]$ReportFields[$Key])
}

$ManifestFields = [ordered]@{
    boot_attempt_root = $ExpectedRoot
    isolated_vbox_user_home = (Join-Path $ExpectedRoot 'VBoxUserHome')
    virtualbox_version = $ExpectedVBoxVersion
    machine_name = $ExpectedMachineName
    machine_uuid = $ExpectedMachineUuid
    machine_state = 'poweroff'
    vdi_uuid = $ExpectedVdiUuid
    iso_uuid = $ExpectedIsoUuid
    dvd_controller = 'IDE'
    iso_slot_value_after_detach = 'none'
    boot1 = 'disk'
    boot2 = 'none'
    boot3 = 'none'
    boot4 = 'none'
    network_disabled = 'True'
    clipboard_disabled = 'True'
    drag_and_drop_disabled = 'True'
    iso_attached = 'False'
    boot_vbox_pre_media_policy_sha256 = $ExpectedPreRegistrationVBoxHash
    boot_vbox_post_media_policy_sha256 = $ExpectedPreRegistrationVBoxHash
    boot_vbox_post_correction_sha256 = $ExpectedCurrentVBoxHash
    boot_vbox_pre_registration_file_id = $ExpectedPreRegistrationVBoxId
    boot_vbox_post_correction_file_id = $ExpectedCurrentVBoxId
    boot_vbox_prev_sha256 = $ExpectedPreviousVBoxHash
    boot_vbox_prev_file_id = $ExpectedPreviousVBoxId
    boot_vbox_prev_matches_pre_registration_hash = 'False'
    boot_vdi_sha256 = $ExpectedVdiHash
    boot_vdi_file_id = $ExpectedVdiId
    boot_iso_sha256 = $ExpectedIsoHash
    boot_iso_file_id = $ExpectedIsoId
    'BOOT ATTEMPT COPY' = 'PREPARED'
    'POWERED-OFF CORRECTED CONFIGURATION' = 'OBSERVED'
    'VM START' = 'NOT-AUTHORIZED'
    'RESTORE BOOT' = 'NOT-OBSERVED'
    'POWERED-OFF RECOVERY POINT' = 'NOT-SEALED'
    'BUILD EXECUTION' = 'NOT-AUTHORIZED'
}
foreach ($Key in $ManifestFields.Keys) {
    Assert-FieldEquals `
        -Lines $ManifestLines `
        -Key $Key `
        -Expected ([string]$ManifestFields[$Key])
}

$CurrentVBox = Assert-ExactFile `
    -Path $CurrentVBoxPath `
    -SHA256 $ExpectedCurrentVBoxHash `
    -FileId $ExpectedCurrentVBoxId `
    -Label 'r3 current VBOX'
$PreviousVBox = Assert-ExactFile `
    -Path $PreviousVBoxPath `
    -SHA256 $ExpectedPreviousVBoxHash `
    -FileId $ExpectedPreviousVBoxId `
    -Label 'r3 previous VBOX'
$Vdi = Assert-ExactFile `
    -Path $VdiPath `
    -Bytes $ExpectedVdiBytes `
    -SHA256 $ExpectedVdiHash `
    -FileId $ExpectedVdiId `
    -Label 'r3 VDI'
$Iso = Assert-ExactFile `
    -Path $IsoPath `
    -Bytes $ExpectedIsoBytes `
    -SHA256 $ExpectedIsoHash `
    -FileId $ExpectedIsoId `
    -Label 'r3 ISO'

if ($CurrentVBox.FileId -ceq $PreviousVBox.FileId) {
    throw 'r3 current and previous VBOX generations share a file ID'
}
if ($CurrentVBox.SHA256 -ceq $PreviousVBox.SHA256) {
    throw 'r3 current and previous VBOX generations share a SHA256'
}

$GenerationNames = @(
    Get-ChildItem -LiteralPath $MachineRoot -Force -File |
        Where-Object { $_.Name -match '^Temple1\.10\.vbox(?:-prev|-new)?$' } |
        ForEach-Object { $_.Name } |
        Sort-Object
)
if (
    $GenerationNames.Count -ne 2 -or
    -not ($GenerationNames -ccontains 'Temple1.10.vbox') -or
    -not ($GenerationNames -ccontains 'Temple1.10.vbox-prev')
) {
    throw "r3 VBOX generation inventory mismatch: $($GenerationNames -join '|')"
}

$NvramFiles = @(
    Get-ChildItem -LiteralPath $Root -Recurse -Force -File |
        Where-Object { $_.Extension -ieq '.nvram' }
)
if ($NvramFiles.Count -ne 0) {
    throw "r3 NVRAM file count is not zero: $($NvramFiles.Count)"
}

$ImmutableRowsRaw = @(Get-ExactRows -Lines $ManifestLines -Key 'file')
$VolatileRowsRaw = @(Get-ExactRows -Lines $ManifestLines -Key 'volatile_log')
$ImmutableRows = @(
    $ImmutableRowsRaw | ForEach-Object {
        Convert-InventoryRow -Line $_ -ExpectedKey 'file'
    }
)
$VolatileRows = @(
    $VolatileRowsRaw | ForEach-Object {
        Convert-InventoryRow -Line $_ -ExpectedKey 'volatile_log'
    }
)
if ($ImmutableRows.Count -le 0) {
    throw 'r3 immutable manifest inventory is empty'
}

$DeclaredImmutableCount = 0
if (-not [int]::TryParse(
    (Get-ExactField -Lines $ManifestLines -Key 'immutable_inventory_files'),
    [ref]$DeclaredImmutableCount
)) {
    throw 'immutable_inventory_files is not an integer'
}
if ($DeclaredImmutableCount -ne $ImmutableRows.Count) {
    throw "immutable inventory count mismatch: declared=$DeclaredImmutableCount rows=$($ImmutableRows.Count)"
}

$DeclaredVolatileCount = 0
if (-not [int]::TryParse(
    (Get-ExactField -Lines $ManifestLines -Key 'volatile_log_files'),
    [ref]$DeclaredVolatileCount
)) {
    throw 'volatile_log_files is not an integer'
}
if ($DeclaredVolatileCount -ne $VolatileRows.Count) {
    throw "volatile inventory count mismatch: declared=$DeclaredVolatileCount rows=$($VolatileRows.Count)"
}

$ManifestImmutableByRelative = @{}
foreach ($Row in $ImmutableRows) {
    if ($ManifestImmutableByRelative.ContainsKey($Row.Relative)) {
        throw "duplicate immutable manifest path: $($Row.Relative)"
    }
    $ManifestImmutableByRelative[$Row.Relative] = $Row
    $Path = Join-Path $Root $Row.Relative
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "immutable manifest file missing: $($Row.Relative)"
    }
    $Item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($Item.Length -ne $Row.Bytes) {
        throw "immutable file byte mismatch: $($Row.Relative)"
    }
    $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($Hash -cne $Row.SHA256) {
        throw "immutable file SHA256 mismatch: $($Row.Relative)"
    }
}

$ActualImmutableRelatives = @(
    Get-ChildItem -LiteralPath $Root -Recurse -Force -File |
        Where-Object {
            $_.FullName -cne $ManifestPath -and
            $_.FullName -cne $IncompletePath
        } |
        ForEach-Object {
            $Relative = (Get-RelativePath -Root $Root -Path $_.FullName).Replace('/', '\')
            if (-not (Test-IsVolatileLogPath -Relative $Relative)) {
                $Relative
            }
        } |
        Sort-Object
)
$ManifestImmutableRelatives = @(
    $ImmutableRows | ForEach-Object { $_.Relative } | Sort-Object
)
if ($ActualImmutableRelatives.Count -ne $ManifestImmutableRelatives.Count) {
    throw (
        'immutable filesystem inventory count mismatch: ' +
        "actual=$($ActualImmutableRelatives.Count) manifest=$($ManifestImmutableRelatives.Count)"
    )
}
for ($Index = 0; $Index -lt $ActualImmutableRelatives.Count; $Index++) {
    if ($ActualImmutableRelatives[$Index] -cne $ManifestImmutableRelatives[$Index]) {
        throw (
            'immutable filesystem inventory path mismatch: ' +
            "index=$Index actual=$($ActualImmutableRelatives[$Index]) " +
            "manifest=$($ManifestImmutableRelatives[$Index])"
        )
    }
}

$CurrentVolatileRelatives = @(
    Get-ChildItem -LiteralPath $Root -Recurse -Force -File |
        ForEach-Object {
            $Relative = (Get-RelativePath -Root $Root -Path $_.FullName).Replace('/', '\')
            if (Test-IsVolatileLogPath -Relative $Relative) {
                $Relative
            }
        } |
        Sort-Object
)

[xml]$VBoxXml = [System.IO.File]::ReadAllText($CurrentVBoxPath)
$MachineNodes = @($VBoxXml.SelectNodes("//*[local-name()='Machine']"))
if ($MachineNodes.Count -ne 1) {
    throw "r3 current VBOX Machine node count mismatch: $($MachineNodes.Count)"
}
$MachineUuid = ConvertTo-NormalizedUuid `
    -Value $MachineNodes[0].GetAttribute('uuid') `
    -Label 'r3 current VBOX machine UUID'
if ($MachineUuid -cne $ExpectedMachineUuid) {
    throw "r3 current VBOX machine UUID mismatch: $MachineUuid"
}

$HardDisks = @(
    $VBoxXml.SelectNodes(
        "//*[local-name()='MediaRegistry']/*[local-name()='HardDisks']/*[local-name()='HardDisk']"
    )
)
$TargetVdiRows = @(
    $HardDisks | Where-Object {
        (ConvertTo-NormalizedUuid `
            -Value $_.GetAttribute('uuid') `
            -Label 'r3 HardDisk UUID') -ceq $ExpectedVdiUuid
    }
)
if ($TargetVdiRows.Count -ne 1) {
    throw "r3 target VDI registry row count mismatch: $($TargetVdiRows.Count)"
}
if ($TargetVdiRows[0].GetAttribute('location') -cne 'Temple1.10.vdi') {
    throw "r3 target VDI location mismatch: $($TargetVdiRows[0].GetAttribute('location'))"
}

$IsoRows = @(
    $VBoxXml.SelectNodes(
        "//*[local-name()='MediaRegistry']/*[local-name()='DVDImages']/*[local-name()='Image']"
    ) | Where-Object {
        (ConvertTo-NormalizedUuid `
            -Value $_.GetAttribute('uuid') `
            -Label 'r3 DVD Image UUID') -ceq $ExpectedIsoUuid
    }
)
if ($IsoRows.Count -gt 1) {
    throw "r3 target ISO registry row count exceeds one: $($IsoRows.Count)"
}
if ($IsoRows.Count -eq 1 -and $IsoRows[0].GetAttribute('location') -cne 'TempleOSTS.iso') {
    throw "r3 target ISO location mismatch: $($IsoRows[0].GetAttribute('location'))"
}

$AttachedTargetIso = @(
    $VBoxXml.SelectNodes("//*[local-name()='AttachedDevice']/*[local-name()='Image']") |
        Where-Object {
            (ConvertTo-NormalizedUuid `
                -Value $_.GetAttribute('uuid') `
                -Label 'r3 attached image UUID') -ceq $ExpectedIsoUuid
        }
)
if ($AttachedTargetIso.Count -ne 0) {
    throw "r3 attached target ISO count is not zero: $($AttachedTargetIso.Count)"
}

$AttachedTargetVdi = @(
    $VBoxXml.SelectNodes("//*[local-name()='AttachedDevice']/*[local-name()='Image']") |
        Where-Object {
            (ConvertTo-NormalizedUuid `
                -Value $_.GetAttribute('uuid') `
                -Label 'r3 attached image UUID') -ceq $ExpectedVdiUuid
        }
)
if ($AttachedTargetVdi.Count -ne 1) {
    throw "r3 attached target VDI count mismatch: $($AttachedTargetVdi.Count)"
}

$BootNodes = @($VBoxXml.SelectNodes("//*[local-name()='Boot']/*[local-name()='Order']"))
if ($BootNodes.Count -ne 4) {
    throw "r3 boot-order node count mismatch: $($BootNodes.Count)"
}
$ExpectedBoot = @{
    '1' = 'HardDisk'
    '2' = 'None'
    '3' = 'None'
    '4' = 'None'
}
foreach ($Position in @('1', '2', '3', '4')) {
    $Matches = @(
        $BootNodes | Where-Object {
            $_.GetAttribute('position') -ceq $Position
        }
    )
    if ($Matches.Count -ne 1) {
        throw "r3 boot position $Position row count mismatch: $($Matches.Count)"
    }
    if ($Matches[0].GetAttribute('device') -cne $ExpectedBoot[$Position]) {
        throw (
            "r3 boot position $Position device mismatch: " +
            $Matches[0].GetAttribute('device')
        )
    }
}

$SnapshotNodes = @($VBoxXml.SelectNodes("//*[local-name()='Snapshot']"))
if ($SnapshotNodes.Count -ne 0) {
    throw "r3 current VBOX snapshot node count is not zero: $($SnapshotNodes.Count)"
}

[xml]$RegistryXml = [System.IO.File]::ReadAllText($RegistryPath)
$RegistryEntries = @(
    $RegistryXml.SelectNodes(
        "//*[local-name()='MachineRegistry']/*[local-name()='MachineEntry']"
    )
)
if ($RegistryEntries.Count -ne 1) {
    throw "r3 isolated registry machine-entry count mismatch: $($RegistryEntries.Count)"
}
$RegistryTarget = @(
    $RegistryEntries | Where-Object {
        (ConvertTo-NormalizedUuid `
            -Value $_.GetAttribute('uuid') `
            -Label 'r3 isolated registry machine UUID') -ceq $ExpectedMachineUuid
    }
)
if ($RegistryTarget.Count -ne 1) {
    throw "r3 isolated registry target row count mismatch: $($RegistryTarget.Count)"
}
$RegistrySrc = $RegistryTarget[0].GetAttribute('src')
Assert-PathEquals `
    -Observed $RegistrySrc `
    -Expected $CurrentVBoxPath `
    -Label 'r3 isolated registry config path'

$Lines = [System.Collections.Generic.List[string]]::new()
$Lines.Add('DBYTE-HOLYC-OPT')
$Lines.Add('TEMPLEOSTS 1.10 VDI-ONLY BOOT ATTEMPT R3 PREPARED READ-ONLY VERIFICATION')
$Lines.Add('')
$Lines.Add("prepared_root`t$Root")
$Lines.Add("preparation_report_sha256`t$ReportHash")
$Lines.Add("boot_attempt_manifest_sha256`t$ManifestHash")
$Lines.Add("machine_uuid`t$MachineUuid")
$Lines.Add("vbox_sha256`t$($CurrentVBox.SHA256)")
$Lines.Add("vbox_file_id`t$($CurrentVBox.FileId)")
$Lines.Add("vbox_prev_sha256`t$($PreviousVBox.SHA256)")
$Lines.Add("vbox_prev_file_id`t$($PreviousVBox.FileId)")
$Lines.Add("vdi_sha256`t$($Vdi.SHA256)")
$Lines.Add("vdi_file_id`t$($Vdi.FileId)")
$Lines.Add("iso_sha256`t$($Iso.SHA256)")
$Lines.Add("iso_file_id`t$($Iso.FileId)")
$Lines.Add("vbox_generation_count`t$($GenerationNames.Count)")
foreach ($Name in $GenerationNames) {
    $Lines.Add("vbox_generation`t$Name")
}
$Lines.Add("immutable_inventory_files`t$($ImmutableRows.Count)")
$Lines.Add("manifest_volatile_log_files`t$($VolatileRows.Count)")
$Lines.Add("current_volatile_log_files`t$($CurrentVolatileRelatives.Count)")
foreach ($Relative in $CurrentVolatileRelatives) {
    $Lines.Add("current_volatile_log`t$Relative")
}
$Lines.Add("target_vdi_registry_rows`t$($TargetVdiRows.Count)")
$Lines.Add("target_vdi_location`t$($TargetVdiRows[0].GetAttribute('location'))")
$Lines.Add("target_iso_registry_rows`t$($IsoRows.Count)")
if ($IsoRows.Count -eq 1) {
    $Lines.Add("target_iso_location`t$($IsoRows[0].GetAttribute('location'))")
}
$Lines.Add("attached_target_vdi_count`t$($AttachedTargetVdi.Count)")
$Lines.Add("attached_target_iso_count`t$($AttachedTargetIso.Count)")
$Lines.Add("boot_order_node_count`t$($BootNodes.Count)")
$Lines.Add("snapshot_node_count`t$($SnapshotNodes.Count)")
$Lines.Add("isolated_registry_machine_entry_count`t$($RegistryEntries.Count)")
$Lines.Add("isolated_registry_target_entry_count`t$($RegistryTarget.Count)")
$Lines.Add("isolated_registry_target_src`t$RegistrySrc")
$Lines.Add("incomplete_marker_absent`t$(-not (Test-Path -LiteralPath $IncompletePath))")
$Lines.Add("nvram_file_count`t$($NvramFiles.Count)")
$Lines.Add('')
$Lines.Add("VBOXMANAGE`tNOT-EXECUTED")
$Lines.Add("VIRTUALBOX MUTATION`tNOT-EXECUTED")
$Lines.Add("VM START`tNOT-AUTHORIZED")
$Lines.Add("RESTORE BOOT`tNOT-OBSERVED")
$Lines.Add("POWERED-OFF RECOVERY POINT`tNOT-SEALED")
$Lines.Add("BUILD EXECUTION`tNOT-AUTHORIZED")
$Lines.Add("R3 PREPARED COPY`tVERIFIED")
$Lines.Add('')
$Lines.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')

[System.IO.File]::WriteAllText(
    $Output,
    (($Lines.ToArray() -join "`n") + "`n"),
    [System.Text.UTF8Encoding]::new($false)
)
$OutputHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

Write-Host "PREPARED R3 ROOT:      $Root"
Write-Host "PREPARATION REPORT:    $ReportHash"
Write-Host "BOOT MANIFEST:         $ManifestHash"
Write-Host "VBOX SHA256:           $($CurrentVBox.SHA256)"
Write-Host "VBOX FILE ID:          $($CurrentVBox.FileId)"
Write-Host "VBOX PREV SHA256:      $($PreviousVBox.SHA256)"
Write-Host "VBOX PREV FILE ID:     $($PreviousVBox.FileId)"
Write-Host "VDI FILE ID:           $($Vdi.FileId)"
Write-Host "ISO FILE ID:           $($Iso.FileId)"
Write-Host "VBOX GENERATIONS:      $($GenerationNames.Count)"
Write-Host "IMMUTABLE FILES:       $($ImmutableRows.Count)"
Write-Host "TARGET VDI LOCATION:   $($TargetVdiRows[0].GetAttribute('location'))"
Write-Host "TARGET ISO ROWS:       $($IsoRows.Count)"
if ($IsoRows.Count -eq 1) {
    Write-Host "TARGET ISO LOCATION:   $($IsoRows[0].GetAttribute('location'))"
}
else {
    Write-Host 'TARGET ISO LOCATION:   <missing>'
}
Write-Host "ATTACHED VDI COUNT:    $($AttachedTargetVdi.Count)"
Write-Host "ATTACHED ISO COUNT:    $($AttachedTargetIso.Count)"
Write-Host "BOOT ORDER NODES:      $($BootNodes.Count)"
Write-Host "SNAPSHOT NODES:        $($SnapshotNodes.Count)"
Write-Host "REGISTRY TARGET ROWS:  $($RegistryTarget.Count)"
Write-Host "INCOMPLETE MARKER:     ABSENT"
Write-Host "NVRAM FILES:           $($NvramFiles.Count)"
Write-Host "REPORT:                $Output"
Write-Host "REPORT SHA256:         $OutputHash"
Write-Host 'VBOXMANAGE:            NOT-EXECUTED'
Write-Host 'VIRTUALBOX MUTATION:   NOT-EXECUTED'
Write-Host 'VM START:              NOT-AUTHORIZED'
Write-Host 'VERDICT:               R3 PREPARED COPY VERIFIED READ-ONLY'
