[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PreparedRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$BootAttemptReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PortableVirtualBoxRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedRoot =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r3'
$ExpectedBootAttemptReport =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r3-single-controlled-boot-attempt.txt'
$ExpectedBootAttemptHash =
    'AC22D9A63234B8BC16FFFAE21BDAAE78704BDE6635A4072093EECCD070EE80D4'
$ExpectedPortableRoot = 'D:\Portable-VirtualBox7'
$ExpectedOut =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r3-host-driver-failure-inspection.txt'

$ExpectedCurrentVBoxHash =
    '8EADB39D54CABE5E7B791E5D7E05BCF4CBBF32D4AB6B58291BEC0B2FAD607C0C'
$ExpectedPreviousVBoxHash =
    'C93D128227EE80B647DB63FE64277CEF1BDC61C224110472C73CBFFEC63877A7'
$ExpectedVdiHash =
    '90D453A94F075760A11E0772862E60C4B031ED874F28AA396EAE638F7EB8B31B'
$ExpectedIsoHash =
    'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$ExpectedRegistryHash =
    '99DB185525D245B1AAFF6937B459518089435882373A55CD2159D03FC82FDCBF'

$ExpectedCurrentVBoxId = '0X000000000000000000050000000609A1'
$ExpectedPreviousVBoxId = '0X000000000000000000040000000609A7'
$ExpectedVdiId = '0X000000000000000000010000000609A2'
$ExpectedIsoId = '0X000000000000000000010000000609A3'

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

function Get-ObservedFileState {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedHash,
        [Parameter(Mandatory = $true)][string]$ExpectedFileId,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "${Label} missing: $Path"
    }
    $Item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    $FileId = Get-FileId -Path $Path -Label $Label

    return [pscustomobject]@{
        Path = $Item.FullName
        Bytes = [long]$Item.Length
        SHA256 = $Hash
        FileId = $FileId
        HashMatchesExpected = ($Hash -ceq $ExpectedHash)
        FileIdMatchesExpected = ($FileId -ceq $ExpectedFileId)
    }
}

function Get-SafePropertyText {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $Property = $Object.PSObject.Properties[$Name]
    if ($null -eq $Property -or $null -eq $Property.Value) {
        return '<missing>'
    }
    return [string]$Property.Value
}

$Root = (Resolve-Path -LiteralPath $PreparedRoot -ErrorAction Stop).Path
$BootReport = (Resolve-Path -LiteralPath $BootAttemptReportPath -ErrorAction Stop).Path
$PortableRoot = (Resolve-Path -LiteralPath $PortableVirtualBoxRoot -ErrorAction Stop).Path
$Output = Get-FullPath -Path $OutPath

Assert-PathEquals -Observed $Root -Expected $ExpectedRoot -Label 'prepared r3 root'
Assert-PathEquals -Observed $BootReport -Expected $ExpectedBootAttemptReport -Label 'controlled-start report'
Assert-PathEquals -Observed $PortableRoot -Expected $ExpectedPortableRoot -Label 'portable VirtualBox root'
Assert-PathEquals -Observed $Output -Expected $ExpectedOut -Label 'inspection report'

if (Test-Path -LiteralPath $Output) {
    throw "inspection report already exists: $Output"
}
$OutputParent = Split-Path -Parent $Output
if (-not (Test-Path -LiteralPath $OutputParent -PathType Container)) {
    throw "inspection report parent missing: $OutputParent"
}

$BootReportHash = (Get-FileHash -LiteralPath $BootReport -Algorithm SHA256).Hash
if ($BootReportHash -cne $ExpectedBootAttemptHash) {
    throw "controlled-start report SHA256 mismatch: observed=$BootReportHash expected=$ExpectedBootAttemptHash"
}

$MachineRoot = Join-Path $Root 'Machine'
$HomeRoot = Join-Path $Root 'VBoxUserHome'
$CurrentVBoxPath = Join-Path $MachineRoot 'Temple1.10.vbox'
$PreviousVBoxPath = Join-Path $MachineRoot 'Temple1.10.vbox-prev'
$VdiPath = Join-Path $MachineRoot 'Temple1.10.vdi'
$IsoPath = Join-Path $MachineRoot 'TempleOSTS.iso'
$RegistryPath = Join-Path $HomeRoot 'VirtualBox.xml'
$HardeningLogPath = Join-Path $MachineRoot 'Logs\VBoxHardening.log'

$CurrentVBox = Get-ObservedFileState `
    -Path $CurrentVBoxPath `
    -ExpectedHash $ExpectedCurrentVBoxHash `
    -ExpectedFileId $ExpectedCurrentVBoxId `
    -Label 'r3 current VBOX after failed start'
$PreviousVBox = Get-ObservedFileState `
    -Path $PreviousVBoxPath `
    -ExpectedHash $ExpectedPreviousVBoxHash `
    -ExpectedFileId $ExpectedPreviousVBoxId `
    -Label 'r3 previous VBOX after failed start'
$Vdi = Get-ObservedFileState `
    -Path $VdiPath `
    -ExpectedHash $ExpectedVdiHash `
    -ExpectedFileId $ExpectedVdiId `
    -Label 'r3 VDI after failed start'
$Iso = Get-ObservedFileState `
    -Path $IsoPath `
    -ExpectedHash $ExpectedIsoHash `
    -ExpectedFileId $ExpectedIsoId `
    -Label 'r3 ISO after failed start'

if (-not (Test-Path -LiteralPath $RegistryPath -PathType Leaf)) {
    throw "isolated VirtualBox registry missing: $RegistryPath"
}
$RegistryHash = (Get-FileHash -LiteralPath $RegistryPath -Algorithm SHA256).Hash
$RegistryMatchesExpected = ($RegistryHash -ceq $ExpectedRegistryHash)

$HardeningLogPresent = Test-Path -LiteralPath $HardeningLogPath -PathType Leaf
$HardeningLogBytes = 0L
$HardeningLogHash = '<missing>'
$HardeningLines = @()
$HardeningMatches = @()
if ($HardeningLogPresent) {
    $HardeningItem = Get-Item -LiteralPath $HardeningLogPath -Force -ErrorAction Stop
    $HardeningLogBytes = [long]$HardeningItem.Length
    $HardeningLogHash = (Get-FileHash -LiteralPath $HardeningLogPath -Algorithm SHA256).Hash
    $HardeningLines = @([System.IO.File]::ReadAllLines($HardeningLogPath))
    $Needles = @(
        'VBoxDrvStub',
        'STATUS_OBJECT_NAME_NOT_FOUND',
        'VERR_OPEN_FAILED',
        'supR3HardenedWinReSpawn',
        'NtCreateFile',
        'Error',
        'error',
        'Driver',
        'driver'
    )
    $HardeningMatches = @(
        for ($Index = 0; $Index -lt $HardeningLines.Count; $Index++) {
            $Line = $HardeningLines[$Index]
            $Matched = $false
            foreach ($Needle in $Needles) {
                if ($Line.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $Matched = $true
                    break
                }
            }
            if ($Matched) {
                [pscustomobject]@{
                    LineNumber = $Index + 1
                    Text = $Line
                }
            }
        }
    )
}

$VBoxDrivers = @()
$DriverQueryError = ''
try {
    $VBoxDrivers = @(
        Get-CimInstance -ClassName Win32_SystemDriver -ErrorAction Stop |
            Where-Object {
                $Name = Get-SafePropertyText -Object $_ -Name 'Name'
                $DisplayName = Get-SafePropertyText -Object $_ -Name 'DisplayName'
                $PathName = Get-SafePropertyText -Object $_ -Name 'PathName'
                $Name -match '(?i)vbox|virtualbox' -or
                $DisplayName -match '(?i)vbox|virtualbox' -or
                $PathName -match '(?i)vbox|virtualbox'
            } |
            Sort-Object Name
    )
}
catch {
    $DriverQueryError = $_.Exception.Message
}

$ScCandidates = @('vboxsup', 'vboxdrv', 'vboxdrvstub')
$ScRows = [System.Collections.Generic.List[object]]::new()
foreach ($Name in $ScCandidates) {
    $OutputRows = @(& sc.exe query $Name 2>&1 | ForEach-Object { [string]$_ })
    $Code = $LASTEXITCODE
    $ScRows.Add([pscustomobject]@{
        Name = $Name
        ExitCode = $Code
        Output = ($OutputRows -join ' | ')
    })
}

$PortableDriverFiles = @(
    Get-ChildItem -LiteralPath $PortableRoot -Recurse -Force -File -ErrorAction Stop |
        Where-Object {
            $_.Extension -ieq '.sys' -and
            $_.Name -match '(?i)^vbox'
        } |
        Sort-Object FullName |
        ForEach-Object {
            [pscustomobject]@{
                Relative = $_.FullName.Substring($PortableRoot.Length).TrimStart('\', '/')
                Bytes = [long]$_.Length
                SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                Version = [string]$_.VersionInfo.FileVersion
            }
        }
)

$PortableExecutables = @(
    Get-ChildItem -LiteralPath $PortableRoot -Recurse -Force -File -ErrorAction Stop |
        Where-Object {
            $_.Name -in @(
                'VBoxManage.exe',
                'VirtualBox.exe',
                'VirtualBoxVM.exe',
                'Portable-VirtualBox.exe'
            )
        } |
        Sort-Object FullName |
        ForEach-Object {
            [pscustomobject]@{
                Relative = $_.FullName.Substring($PortableRoot.Length).TrimStart('\', '/')
                Bytes = [long]$_.Length
                SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                Version = [string]$_.VersionInfo.FileVersion
            }
        }
)

$VBoxProcesses = @(
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -match '(?i)^vbox|^virtualbox' } |
        Sort-Object ProcessName, Id
)

$Lines = [System.Collections.Generic.List[string]]::new()
$Lines.Add('DBYTE-HOLYC-OPT')
$Lines.Add('TEMPLEOSTS 1.10 R3 FAILED START HOST DRIVER READ-ONLY INSPECTION')
$Lines.Add('')
$Lines.Add("prepared_root`t$Root")
$Lines.Add("controlled_start_report_sha256`t$BootReportHash")
$Lines.Add("portable_virtualbox_root`t$PortableRoot")
$Lines.Add('')

foreach ($Pair in @(
    @('current_vbox', $CurrentVBox),
    @('previous_vbox', $PreviousVBox),
    @('vdi', $Vdi),
    @('iso', $Iso)
)) {
    $Label = [string]$Pair[0]
    $State = $Pair[1]
    $Lines.Add("${Label}_path`t$($State.Path)")
    $Lines.Add("${Label}_bytes`t$($State.Bytes)")
    $Lines.Add("${Label}_sha256`t$($State.SHA256)")
    $Lines.Add("${Label}_file_id`t$($State.FileId)")
    $Lines.Add("${Label}_hash_matches_prestart`t$($State.HashMatchesExpected)")
    $Lines.Add("${Label}_file_id_matches_prestart`t$($State.FileIdMatchesExpected)")
}
$Lines.Add("isolated_registry_sha256`t$RegistryHash")
$Lines.Add("isolated_registry_matches_prestart`t$RegistryMatchesExpected")
$Lines.Add('')

$Lines.Add("hardening_log_present`t$HardeningLogPresent")
$Lines.Add("hardening_log_path`t$HardeningLogPath")
$Lines.Add("hardening_log_bytes`t$HardeningLogBytes")
$Lines.Add("hardening_log_sha256`t$HardeningLogHash")
$Lines.Add("hardening_match_count`t$($HardeningMatches.Count)")
foreach ($Match in $HardeningMatches) {
    $Lines.Add("hardening_match`t$($Match.LineNumber)`t$($Match.Text)")
}
$Lines.Add('')

$Lines.Add("cim_driver_query_error`t$DriverQueryError")
$Lines.Add("cim_vbox_driver_count`t$($VBoxDrivers.Count)")
foreach ($Driver in $VBoxDrivers) {
    $Lines.Add(
        'cim_vbox_driver' + "`t" +
        (Get-SafePropertyText -Object $Driver -Name 'Name') + "`t" +
        (Get-SafePropertyText -Object $Driver -Name 'DisplayName') + "`t" +
        (Get-SafePropertyText -Object $Driver -Name 'State') + "`t" +
        (Get-SafePropertyText -Object $Driver -Name 'StartMode') + "`t" +
        (Get-SafePropertyText -Object $Driver -Name 'PathName')
    )
}
foreach ($Row in $ScRows) {
    $Lines.Add("sc_query`t$($Row.Name)`t$($Row.ExitCode)`t$($Row.Output)")
}
$Lines.Add('')

$Lines.Add("portable_vbox_driver_file_count`t$($PortableDriverFiles.Count)")
foreach ($DriverFile in $PortableDriverFiles) {
    $Lines.Add(
        "portable_vbox_driver_file`t$($DriverFile.Relative)`t$($DriverFile.Bytes)`t$($DriverFile.SHA256)`t$($DriverFile.Version)"
    )
}
$Lines.Add("portable_vbox_executable_count`t$($PortableExecutables.Count)")
foreach ($Executable in $PortableExecutables) {
    $Lines.Add(
        "portable_vbox_executable`t$($Executable.Relative)`t$($Executable.Bytes)`t$($Executable.SHA256)`t$($Executable.Version)"
    )
}
$Lines.Add('')

$Lines.Add("vbox_process_count`t$($VBoxProcesses.Count)")
foreach ($Process in $VBoxProcesses) {
    $Lines.Add("vbox_process`t$($Process.ProcessName)`t$($Process.Id)")
}
$Lines.Add('')
$Lines.Add("SC MUTATION`tNOT-EXECUTED")
$Lines.Add("DRIVER INSTALL`tNOT-EXECUTED")
$Lines.Add("DRIVER START`tNOT-EXECUTED")
$Lines.Add("DRIVER STOP`tNOT-EXECUTED")
$Lines.Add("VBOXMANAGE`tNOT-EXECUTED")
$Lines.Add("VM START`tNOT-AUTHORIZED")
$Lines.Add("R3 MUTATION`tNOT-EXECUTED")
$Lines.Add("VERDICT`tHOST DRIVER FAILURE INSPECTION COMPLETE")
$Lines.Add('')
$Lines.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')

[System.IO.File]::WriteAllText(
    $Output,
    (($Lines.ToArray() -join "`n") + "`n"),
    [System.Text.UTF8Encoding]::new($false)
)
$OutputHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

Write-Host "PREPARED R3 ROOT:       $Root"
Write-Host "BOUND START REPORT:     $BootReportHash"
Write-Host "CURRENT VBOX MATCH:     $($CurrentVBox.HashMatchesExpected) / $($CurrentVBox.FileIdMatchesExpected)"
Write-Host "PREVIOUS VBOX MATCH:    $($PreviousVBox.HashMatchesExpected) / $($PreviousVBox.FileIdMatchesExpected)"
Write-Host "VDI MATCH:              $($Vdi.HashMatchesExpected) / $($Vdi.FileIdMatchesExpected)"
Write-Host "ISO MATCH:              $($Iso.HashMatchesExpected) / $($Iso.FileIdMatchesExpected)"
Write-Host "REGISTRY MATCH:         $RegistryMatchesExpected"
Write-Host "HARDENING LOG PRESENT:  $HardeningLogPresent"
Write-Host "HARDENING LOG SHA256:   $HardeningLogHash"
Write-Host "HARDENING MATCHES:      $($HardeningMatches.Count)"
Write-Host "CIM VBOX DRIVERS:       $($VBoxDrivers.Count)"
Write-Host "PORTABLE VBOX DRIVERS:  $($PortableDriverFiles.Count)"
Write-Host "VBOX PROCESSES:         $($VBoxProcesses.Count)"
Write-Host "REPORT:                 $Output"
Write-Host "REPORT SHA256:          $OutputHash"
Write-Host 'SC MUTATION:            NOT-EXECUTED'
Write-Host 'DRIVER INSTALL/START:   NOT-EXECUTED'
Write-Host 'VBOXMANAGE:             NOT-EXECUTED'
Write-Host 'VM START:               NOT-AUTHORIZED'
Write-Host 'VERDICT:                HOST DRIVER FAILURE INSPECTION COMPLETE'
