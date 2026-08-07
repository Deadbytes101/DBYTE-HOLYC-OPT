[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PortableVirtualBoxRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$HostDriverInspectionReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedPortableRoot = 'D:\Portable-VirtualBox7'
$ExpectedHostReport = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r3-host-driver-failure-inspection.txt'
$ExpectedHostReportHash = '510E65B93889271010509F917DEE681E95273DD001B1BF3A9F222663410CD6F8'
$ExpectedOut = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-portable-vbox-driver-loader-surface-inspection.txt'
$ExpectedVBoxSupSysHash = '3344E2909580A9965E38B26AB9E9958842315DDEA1B0D0E274DA314DDCAB97F4'
$ExpectedVBoxVersion = '7.0.12.159484'

function Get-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath(
        [Environment]::ExpandEnvironmentVariables($Path)
    ).TrimEnd([char]92, [char]47)
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

function Get-PortableRelativePath {
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
        throw "path is outside portable root: $PathFull"
    }
    return $PathFull.Substring($Prefix.Length).Replace('/', '\')
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

function Get-SignatureSummary {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        $Signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
        $Signer = '<missing>'
        if ($null -ne $Signature.SignerCertificate) {
            $Signer = [string]$Signature.SignerCertificate.Subject
        }
        return [pscustomobject]@{
            Status = [string]$Signature.Status
            StatusMessage = [string]$Signature.StatusMessage
            Signer = $Signer
        }
    }
    catch {
        return [pscustomobject]@{
            Status = '<query-error>'
            StatusMessage = $_.Exception.Message
            Signer = '<missing>'
        }
    }
}

function Get-ContextLines {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)][string[]]$Needles,
        [int]$Radius = 2
    )

    $Indexes = [System.Collections.Generic.HashSet[int]]::new()
    for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
        $Matched = $false
        foreach ($Needle in $Needles) {
            if ($Lines[$Index].IndexOf(
                $Needle,
                [System.StringComparison]::OrdinalIgnoreCase
            ) -ge 0) {
                $Matched = $true
                break
            }
        }
        if ($Matched) {
            $Start = [Math]::Max(0, $Index - $Radius)
            $End = [Math]::Min($Lines.Count - 1, $Index + $Radius)
            for ($ContextIndex = $Start; $ContextIndex -le $End; $ContextIndex++) {
                [void]$Indexes.Add($ContextIndex)
            }
        }
    }

    return @(
        $Indexes |
            Sort-Object |
            ForEach-Object {
                [pscustomobject]@{
                    LineNumber = $_ + 1
                    Text = $Lines[$_]
                }
            }
    )
}

$PortableRoot = (Resolve-Path -LiteralPath $PortableVirtualBoxRoot -ErrorAction Stop).Path
$HostReport = (Resolve-Path -LiteralPath $HostDriverInspectionReportPath -ErrorAction Stop).Path
$Output = Get-FullPath -Path $OutPath

Assert-PathEquals -Observed $PortableRoot -Expected $ExpectedPortableRoot -Label 'portable VirtualBox root'
Assert-PathEquals -Observed $HostReport -Expected $ExpectedHostReport -Label 'host driver inspection report'
Assert-PathEquals -Observed $Output -Expected $ExpectedOut -Label 'loader-surface inspection report'

if (Test-Path -LiteralPath $Output) {
    throw "loader-surface inspection report already exists: $Output"
}
$OutputParent = Split-Path -Parent $Output
if (-not (Test-Path -LiteralPath $OutputParent -PathType Container)) {
    throw "loader-surface inspection report parent missing: $OutputParent"
}

$HostReportHash = (Get-FileHash -LiteralPath $HostReport -Algorithm SHA256).Hash
if ($HostReportHash -cne $ExpectedHostReportHash) {
    throw "host driver inspection report SHA256 mismatch: observed=$HostReportHash expected=$ExpectedHostReportHash"
}

$VBoxSupDir = Join-Path $PortableRoot 'app64\drivers\vboxsup'
$VBoxSupSys = Join-Path $VBoxSupDir 'VBoxSup.sys'
if (-not (Test-Path -LiteralPath $VBoxSupSys -PathType Leaf)) {
    throw "VBoxSup.sys missing: $VBoxSupSys"
}
$VBoxSupSysItem = Get-Item -LiteralPath $VBoxSupSys -Force -ErrorAction Stop
$VBoxSupSysHash = (Get-FileHash -LiteralPath $VBoxSupSys -Algorithm SHA256).Hash
if ($VBoxSupSysHash -cne $ExpectedVBoxSupSysHash) {
    throw "VBoxSup.sys SHA256 mismatch: observed=$VBoxSupSysHash expected=$ExpectedVBoxSupSysHash"
}
if ([string]$VBoxSupSysItem.VersionInfo.FileVersion -cne $ExpectedVBoxVersion) {
    throw "VBoxSup.sys version mismatch: observed=$($VBoxSupSysItem.VersionInfo.FileVersion) expected=$ExpectedVBoxVersion"
}
$VBoxSupSysSignature = Get-SignatureSummary -Path $VBoxSupSys

$VBoxSupDirectoryFiles = @(
    Get-ChildItem -LiteralPath $VBoxSupDir -Force -File -ErrorAction Stop |
        Sort-Object Name |
        ForEach-Object {
            [pscustomobject]@{
                Relative = Get-PortableRelativePath -Root $PortableRoot -Path $_.FullName
                Bytes = [long]$_.Length
                SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                Version = [string]$_.VersionInfo.FileVersion
                Extension = [string]$_.Extension
            }
        }
)

$InfFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $PortableRoot 'app64\drivers') -Recurse -Force -File -Filter '*.inf' -ErrorAction Stop |
        Sort-Object FullName
)
$VBoxSupInfCandidates = @(
    $InfFiles | Where-Object {
        $_.FullName.StartsWith(
            $VBoxSupDir + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase
        ) -or
        $_.BaseName -match '(?i)vboxsup|vboxdrv'
    }
)

$InfRelevantRows = [System.Collections.Generic.List[object]]::new()
$InfNeedles = @(
    'VBoxSup',
    'VBoxDrv',
    'VBoxDrvStub',
    'AddService',
    'ServiceBinary',
    'ServiceType',
    'StartType',
    'ErrorControl',
    'DefaultInstall',
    'DefaultUninstall',
    'CopyFiles',
    'DelService',
    'Root\\'
)
foreach ($Inf in $VBoxSupInfCandidates) {
    $InfLines = @([System.IO.File]::ReadAllLines($Inf.FullName))
    $Relevant = @(Get-ContextLines -Lines $InfLines -Needles $InfNeedles -Radius 1)
    foreach ($Row in $Relevant) {
        $InfRelevantRows.Add([pscustomobject]@{
            Relative = Get-PortableRelativePath -Root $PortableRoot -Path $Inf.FullName
            LineNumber = $Row.LineNumber
            Text = $Row.Text
        })
    }
}

$CatalogFiles = @(
    Get-ChildItem -LiteralPath $VBoxSupDir -Force -File -Filter '*.cat' -ErrorAction SilentlyContinue |
        Sort-Object Name
)
$CatalogRows = @(
    foreach ($Catalog in $CatalogFiles) {
        $Signature = Get-SignatureSummary -Path $Catalog.FullName
        [pscustomobject]@{
            Relative = Get-PortableRelativePath -Root $PortableRoot -Path $Catalog.FullName
            Bytes = [long]$Catalog.Length
            SHA256 = (Get-FileHash -LiteralPath $Catalog.FullName -Algorithm SHA256).Hash
            SignatureStatus = $Signature.Status
            Signer = $Signature.Signer
        }
    }
)

$RootEntries = @(
    Get-ChildItem -LiteralPath $PortableRoot -Force -ErrorAction Stop |
        Sort-Object PSIsContainer, Name |
        ForEach-Object {
            [pscustomobject]@{
                Type = if ($_.PSIsContainer) { 'directory' } else { 'file' }
                Name = $_.Name
                Bytes = if ($_.PSIsContainer) { -1L } else { [long]$_.Length }
            }
        }
)

$LauncherCandidates = @(
    Get-ChildItem -LiteralPath $PortableRoot -Recurse -Force -File -ErrorAction Stop |
        Where-Object {
            $Relative = Get-PortableRelativePath -Root $PortableRoot -Path $_.FullName
            $OutsideApp64 = -not $Relative.StartsWith(
                'app64\',
                [System.StringComparison]::OrdinalIgnoreCase
            )
            $ExecutableOrScript = $_.Extension -in @('.exe', '.cmd', '.bat', '.ps1', '.vbs', '.js')
            $InterestingName = $_.Name -match '(?i)portable|launch|start|setup|install|driver|service|vbox'
            $ExecutableOrScript -and ($OutsideApp64 -or $InterestingName)
        } |
        Sort-Object FullName |
        ForEach-Object {
            $Signature = if ($_.Extension -ieq '.exe') {
                Get-SignatureSummary -Path $_.FullName
            }
            else {
                [pscustomobject]@{ Status = '<not-executable>'; StatusMessage = ''; Signer = '<not-applicable>' }
            }
            [pscustomobject]@{
                Relative = Get-PortableRelativePath -Root $PortableRoot -Path $_.FullName
                Bytes = [long]$_.Length
                SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                Version = [string]$_.VersionInfo.FileVersion
                SignatureStatus = $Signature.Status
                Signer = $Signature.Signer
            }
        }
)

$TextExtensions = @('.ini', '.cfg', '.conf', '.xml', '.txt', '.cmd', '.bat', '.ps1', '.vbs', '.js', '.inf')
$LoaderTokens = @(
    'VBoxSup',
    'VBoxDrv',
    'VBoxDrvStub',
    'drivers\\vboxsup',
    'drivers/vboxsup',
    'sc.exe',
    'sc create',
    'sc start',
    'pnputil',
    'net start',
    'AddService',
    'Portable-VirtualBox',
    'driver install',
    'driver start'
)
$TextTokenRows = [System.Collections.Generic.List[object]]::new()
$TextCandidates = @(
    Get-ChildItem -LiteralPath $PortableRoot -Recurse -Force -File -ErrorAction Stop |
        Where-Object {
            $_.Length -le 2097152 -and
            $TextExtensions -contains $_.Extension.ToLowerInvariant()
        } |
        Sort-Object FullName
)
foreach ($File in $TextCandidates) {
    $Lines = @()
    try {
        $Lines = @([System.IO.File]::ReadAllLines($File.FullName))
    }
    catch {
        continue
    }
    for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
        $Line = $Lines[$Index]
        foreach ($Token in $LoaderTokens) {
            if ($Line.IndexOf($Token, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $TextTokenRows.Add([pscustomobject]@{
                    Relative = Get-PortableRelativePath -Root $PortableRoot -Path $File.FullName
                    LineNumber = $Index + 1
                    Token = $Token
                    Text = $Line
                })
                break
            }
        }
    }
}

$ServiceRegistryRows = @()
try {
    $ServiceRegistryRows = @(
        Get-ChildItem -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services' -ErrorAction Stop |
            Where-Object { $_.PSChildName -match '(?i)vbox|virtualbox' } |
            Sort-Object PSChildName |
            ForEach-Object {
                $Properties = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
                [pscustomobject]@{
                    Name = $_.PSChildName
                    DisplayName = if ($null -eq $Properties) { '<missing>' } else { Get-SafePropertyText -Object $Properties -Name 'DisplayName' }
                    ImagePath = if ($null -eq $Properties) { '<missing>' } else { Get-SafePropertyText -Object $Properties -Name 'ImagePath' }
                    Type = if ($null -eq $Properties) { '<missing>' } else { Get-SafePropertyText -Object $Properties -Name 'Type' }
                    Start = if ($null -eq $Properties) { '<missing>' } else { Get-SafePropertyText -Object $Properties -Name 'Start' }
                    ErrorControl = if ($null -eq $Properties) { '<missing>' } else { Get-SafePropertyText -Object $Properties -Name 'ErrorControl' }
                }
            }
    )
}
catch {
    $ServiceRegistryRows = @(
        [pscustomobject]@{
            Name = '<registry-query-error>'
            DisplayName = $_.Exception.Message
            ImagePath = '<missing>'
            Type = '<missing>'
            Start = '<missing>'
            ErrorControl = '<missing>'
        }
    )
}

$CimDriverRows = @()
$CimDriverQueryError = ''
try {
    $CimDriverRows = @(
        Get-CimInstance -ClassName Win32_SystemDriver -ErrorAction Stop |
            Where-Object {
                (Get-SafePropertyText -Object $_ -Name 'Name') -match '(?i)vbox|virtualbox' -or
                (Get-SafePropertyText -Object $_ -Name 'DisplayName') -match '(?i)vbox|virtualbox' -or
                (Get-SafePropertyText -Object $_ -Name 'PathName') -match '(?i)vbox|virtualbox'
            } |
            Sort-Object Name
    )
}
catch {
    $CimDriverQueryError = $_.Exception.Message
}

$PnpOutput = @()
$PnpExitCode = -1
$PnpContextRows = @()
try {
    $OldEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $PnpOutput = @(
            & pnputil.exe /enum-drivers 2>&1 |
                ForEach-Object { [string]$_ }
        )
        $PnpExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $OldEap
    }
    $PnpContextRows = @(
        Get-ContextLines \
            -Lines $PnpOutput \
            -Needles @('VirtualBox', 'VBox', 'Oracle') \
            -Radius 4
    )
}
catch {
    $PnpContextRows = @(
        [pscustomobject]@{
            LineNumber = -1
            Text = 'pnputil query error: ' + $_.Exception.Message
        }
    )
}

$Lines = [System.Collections.Generic.List[string]]::new()
$Lines.Add('DBYTE-HOLYC-OPT')
$Lines.Add('PORTABLE VIRTUALBOX 7 DRIVER LOADER SURFACE READ-ONLY INSPECTION')
$Lines.Add('')
$Lines.Add("portable_root`t$PortableRoot")
$Lines.Add("bound_host_driver_inspection_sha256`t$HostReportHash")
$Lines.Add("vboxsup_sys_path`t$VBoxSupSys")
$Lines.Add("vboxsup_sys_bytes`t$($VBoxSupSysItem.Length)")
$Lines.Add("vboxsup_sys_sha256`t$VBoxSupSysHash")
$Lines.Add("vboxsup_sys_version`t$($VBoxSupSysItem.VersionInfo.FileVersion)")
$Lines.Add("vboxsup_sys_signature_status`t$($VBoxSupSysSignature.Status)")
$Lines.Add("vboxsup_sys_signature_signer`t$($VBoxSupSysSignature.Signer)")
$Lines.Add('')

$Lines.Add("root_entry_count`t$($RootEntries.Count)")
foreach ($Entry in $RootEntries) {
    $Lines.Add("root_entry`t$($Entry.Type)`t$($Entry.Name)`t$($Entry.Bytes)")
}
$Lines.Add('')

$Lines.Add("vboxsup_directory_file_count`t$($VBoxSupDirectoryFiles.Count)")
foreach ($File in $VBoxSupDirectoryFiles) {
    $Lines.Add("vboxsup_directory_file`t$($File.Relative)`t$($File.Bytes)`t$($File.SHA256)`t$($File.Version)")
}
$Lines.Add("vboxsup_inf_candidate_count`t$($VBoxSupInfCandidates.Count)")
foreach ($Inf in $VBoxSupInfCandidates) {
    $Relative = Get-PortableRelativePath -Root $PortableRoot -Path $Inf.FullName
    $Lines.Add("vboxsup_inf_candidate`t$Relative`t$($Inf.Length)`t$((Get-FileHash -LiteralPath $Inf.FullName -Algorithm SHA256).Hash)")
}
$Lines.Add("vboxsup_inf_relevant_row_count`t$($InfRelevantRows.Count)")
foreach ($Row in $InfRelevantRows) {
    $Lines.Add("vboxsup_inf_row`t$($Row.Relative)`t$($Row.LineNumber)`t$($Row.Text)")
}
$Lines.Add('')

$Lines.Add("vboxsup_catalog_count`t$($CatalogRows.Count)")
foreach ($Catalog in $CatalogRows) {
    $Lines.Add("vboxsup_catalog`t$($Catalog.Relative)`t$($Catalog.Bytes)`t$($Catalog.SHA256)`t$($Catalog.SignatureStatus)`t$($Catalog.Signer)")
}
$Lines.Add('')

$Lines.Add("launcher_candidate_count`t$($LauncherCandidates.Count)")
foreach ($Candidate in $LauncherCandidates) {
    $Lines.Add("launcher_candidate`t$($Candidate.Relative)`t$($Candidate.Bytes)`t$($Candidate.SHA256)`t$($Candidate.Version)`t$($Candidate.SignatureStatus)`t$($Candidate.Signer)")
}
$Lines.Add('')

$Lines.Add("text_candidate_count`t$($TextCandidates.Count)")
$Lines.Add("loader_token_hit_count`t$($TextTokenRows.Count)")
foreach ($Row in $TextTokenRows) {
    $Lines.Add("loader_token_hit`t$($Row.Relative)`t$($Row.LineNumber)`t$($Row.Token)`t$($Row.Text)")
}
$Lines.Add('')

$Lines.Add("service_registry_row_count`t$($ServiceRegistryRows.Count)")
foreach ($Row in $ServiceRegistryRows) {
    $Lines.Add("service_registry_row`t$($Row.Name)`t$($Row.DisplayName)`t$($Row.ImagePath)`t$($Row.Type)`t$($Row.Start)`t$($Row.ErrorControl)")
}
$Lines.Add("cim_driver_query_error`t$CimDriverQueryError")
$Lines.Add("cim_driver_row_count`t$($CimDriverRows.Count)")
foreach ($Driver in $CimDriverRows) {
    $Lines.Add(
        'cim_driver_row' + "`t" +
        (Get-SafePropertyText -Object $Driver -Name 'Name') + "`t" +
        (Get-SafePropertyText -Object $Driver -Name 'DisplayName') + "`t" +
        (Get-SafePropertyText -Object $Driver -Name 'State') + "`t" +
        (Get-SafePropertyText -Object $Driver -Name 'StartMode') + "`t" +
        (Get-SafePropertyText -Object $Driver -Name 'PathName')
    )
}
$Lines.Add('')

$Lines.Add("pnputil_enum_exit_code`t$PnpExitCode")
$Lines.Add("pnputil_context_row_count`t$($PnpContextRows.Count)")
foreach ($Row in $PnpContextRows) {
    $Lines.Add("pnputil_context`t$($Row.LineNumber)`t$($Row.Text)")
}
$Lines.Add('')

$Lines.Add("HOST MUTATION`tNOT-EXECUTED")
$Lines.Add("DRIVER INSTALL`tNOT-EXECUTED")
$Lines.Add("DRIVER START`tNOT-EXECUTED")
$Lines.Add("SERVICE CREATE`tNOT-EXECUTED")
$Lines.Add("VBOXMANAGE`tNOT-EXECUTED")
$Lines.Add("VM START`tNOT-AUTHORIZED")
$Lines.Add("VERDICT`tPORTABLE VIRTUALBOX DRIVER LOADER SURFACE INSPECTION COMPLETE")
$Lines.Add('')
$Lines.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')

[System.IO.File]::WriteAllText(
    $Output,
    (($Lines.ToArray() -join "`n") + "`n"),
    [System.Text.UTF8Encoding]::new($false)
)
$OutputHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

Write-Host "PORTABLE ROOT:          $PortableRoot"
Write-Host "BOUND HOST REPORT:      $HostReportHash"
Write-Host "VBOXSUP.SYS SHA256:     $VBoxSupSysHash"
Write-Host "VBOXSUP.SYS VERSION:    $($VBoxSupSysItem.VersionInfo.FileVersion)"
Write-Host "VBOXSUP SIGNATURE:      $($VBoxSupSysSignature.Status)"
Write-Host "VBOXSUP INF CANDIDATES: $($VBoxSupInfCandidates.Count)"
Write-Host "INF RELEVANT ROWS:      $($InfRelevantRows.Count)"
Write-Host "LAUNCHER CANDIDATES:    $($LauncherCandidates.Count)"
Write-Host "LOADER TOKEN HITS:      $($TextTokenRows.Count)"
Write-Host "SERVICE REGISTRY ROWS:  $($ServiceRegistryRows.Count)"
Write-Host "CIM VBOX DRIVERS:       $($CimDriverRows.Count)"
Write-Host "PNPUTIL EXIT:           $PnpExitCode"
Write-Host "PNPUTIL CONTEXT ROWS:   $($PnpContextRows.Count)"
Write-Host "REPORT:                 $Output"
Write-Host "REPORT SHA256:          $OutputHash"
Write-Host 'HOST MUTATION:          NOT-EXECUTED'
Write-Host 'DRIVER INSTALL/START:   NOT-EXECUTED'
Write-Host 'VBOXMANAGE:             NOT-EXECUTED'
Write-Host 'VM START:               NOT-AUTHORIZED'
Write-Host 'VERDICT:                PORTABLE VIRTUALBOX DRIVER LOADER SURFACE INSPECTION COMPLETE'
