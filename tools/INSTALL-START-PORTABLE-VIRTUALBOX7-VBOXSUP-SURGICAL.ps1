[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PortableVirtualBoxRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$LoaderSurfaceReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$WrapperPeReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedPortableRoot = 'D:\Portable-VirtualBox7'
$ExpectedLoaderReport = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-portable-vbox-driver-loader-surface-inspection.txt'
$ExpectedLoaderHash = '7C9ABBAE87AA926F11D73A16B17C24AC287EEBB7AB620A63C9A6EBA58866AA2C'
$ExpectedPeReport = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-portable-vbox-wrapper-pe-surface-inspection.txt'
$ExpectedPeHash = '7B830675C981216B58497F9080ADA5025F7FB2EFE1521CE506F5CFA56BC7E512'
$ExpectedOut = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-portable-vbox-vboxsup-surgical-install-start.txt'

$ExpectedDriverHash = '3344E2909580A9965E38B26AB9E9958842315DDEA1B0D0E274DA314DDCAB97F4'
$ExpectedDriverVersion = '7.0.12.159484'
$ExpectedInfHash = 'B34D56477E8273C6C2B177B38A7F5CBE1DD4708A1C2BAF7A2D2170302ECAC7F6'
$ExpectedCatHash = '09DFDCD84B7CE8970B32AF5BB18000738155C04444C6276B5353C98CB1CA6999'

$ServiceName = 'VBoxSup'
$DisplayName = 'PortableVBoxSUP'
$ServiceRegistryPath = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\VBoxSup'
$ScPath = Join-Path $env:SystemRoot 'System32\sc.exe'

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

function Invoke-Sc {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Arguments
    )

    $OldEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $Output = @(
            & $ScPath @Arguments 2>&1 |
                ForEach-Object { [string]$_ }
        )
        $ExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $OldEap
    }

    return [pscustomobject]@{
        ExitCode = [int]$ExitCode
        Output = [string[]]$Output
    }
}

function Add-ScEvidence {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [System.Collections.Generic.List[string]]$Lines,
        [Parameter(Mandatory = $true)]
        [string]$Prefix,
        [Parameter(Mandatory = $true)]
        [object]$Result
    )

    $Lines.Add("${Prefix}_exit`t$($Result.ExitCode)")
    foreach ($Row in @($Result.Output)) {
        $Lines.Add("${Prefix}_output`t$Row")
    }
}

function Normalize-DriverImagePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $Value = $Path.Trim().Trim([char]34)
    if ($Value.StartsWith('\??\', [System.StringComparison]::Ordinal)) {
        $Value = $Value.Substring(4)
    }
    return Get-FullPath -Path $Value
}

if (-not (Test-Path -LiteralPath $ScPath -PathType Leaf)) {
    throw "sc.exe missing: $ScPath"
}

$PortableRoot = (Resolve-Path -LiteralPath $PortableVirtualBoxRoot -ErrorAction Stop).Path
$LoaderReport = (Resolve-Path -LiteralPath $LoaderSurfaceReportPath -ErrorAction Stop).Path
$PeReport = (Resolve-Path -LiteralPath $WrapperPeReportPath -ErrorAction Stop).Path
$Output = Get-FullPath -Path $OutPath

Assert-PathEquals -Observed $PortableRoot -Expected $ExpectedPortableRoot -Label 'portable root'
Assert-PathEquals -Observed $LoaderReport -Expected $ExpectedLoaderReport -Label 'loader report'
Assert-PathEquals -Observed $PeReport -Expected $ExpectedPeReport -Label 'PE report'
Assert-PathEquals -Observed $Output -Expected $ExpectedOut -Label 'mutation report'

if (Test-Path -LiteralPath $Output) {
    throw "VBoxSup mutation report already exists: $Output"
}
$OutputParent = Split-Path -Parent $Output
if (-not (Test-Path -LiteralPath $OutputParent -PathType Container)) {
    throw "mutation report parent missing: $OutputParent"
}

$LoaderHash = (Get-FileHash -LiteralPath $LoaderReport -Algorithm SHA256).Hash
if ($LoaderHash -cne $ExpectedLoaderHash) {
    throw "loader report SHA256 mismatch: observed=$LoaderHash expected=$ExpectedLoaderHash"
}
$PeHash = (Get-FileHash -LiteralPath $PeReport -Algorithm SHA256).Hash
if ($PeHash -cne $ExpectedPeHash) {
    throw "PE report SHA256 mismatch: observed=$PeHash expected=$ExpectedPeHash"
}

$DriverPath = Join-Path $PortableRoot 'app64\drivers\vboxsup\VBoxSup.sys'
$InfPath = Join-Path $PortableRoot 'app64\drivers\vboxsup\VBoxSup.inf'
$CatPath = Join-Path $PortableRoot 'app64\drivers\vboxsup\VBoxSup.cat'
foreach ($Path in @($DriverPath, $InfPath, $CatPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "required VBoxSup payload missing: $Path"
    }
}

$DriverItem = Get-Item -LiteralPath $DriverPath -Force -ErrorAction Stop
$DriverHash = (Get-FileHash -LiteralPath $DriverPath -Algorithm SHA256).Hash
$InfHash = (Get-FileHash -LiteralPath $InfPath -Algorithm SHA256).Hash
$CatHash = (Get-FileHash -LiteralPath $CatPath -Algorithm SHA256).Hash
if ($DriverHash -cne $ExpectedDriverHash) {
    throw "VBoxSup.sys SHA256 mismatch: observed=$DriverHash expected=$ExpectedDriverHash"
}
if ($DriverItem.VersionInfo.FileVersion -cne $ExpectedDriverVersion) {
    throw "VBoxSup.sys version mismatch: observed=$($DriverItem.VersionInfo.FileVersion) expected=$ExpectedDriverVersion"
}
if ($InfHash -cne $ExpectedInfHash) {
    throw "VBoxSup.inf SHA256 mismatch: observed=$InfHash expected=$ExpectedInfHash"
}
if ($CatHash -cne $ExpectedCatHash) {
    throw "VBoxSup.cat SHA256 mismatch: observed=$CatHash expected=$ExpectedCatHash"
}

$Signature = Get-AuthenticodeSignature -LiteralPath $DriverPath
if ($Signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
    throw "VBoxSup.sys signature is not Valid: $($Signature.Status)"
}
$Signer = if ($null -eq $Signature.SignerCertificate) {
    '<missing>'
}
else {
    [string]$Signature.SignerCertificate.Subject
}

$Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = [System.Security.Principal.WindowsPrincipal]::new($Identity)
$IsAdministrator = $Principal.IsInRole(
    [System.Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $IsAdministrator) {
    throw 'administrator token required before VBoxSup host mutation'
}

$VBoxProcesses = @(
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProcessName -match '^(?i)(VBox|VirtualBox)'
        } |
        Sort-Object ProcessName, Id
)
if ($VBoxProcesses.Count -ne 0) {
    throw (
        'VBox/VirtualBox processes are running; mutation denied: ' +
        (($VBoxProcesses | ForEach-Object { "$($_.ProcessName):$($_.Id)" }) -join ', ')
    )
}

if (Test-Path -LiteralPath $ServiceRegistryPath) {
    throw 'VBoxSup service registry key already exists; mutation denied'
}
$PreQuery = Invoke-Sc -Arguments @('query', $ServiceName)
if ($PreQuery.ExitCode -ne 1060) {
    throw (
        'VBoxSup pre-query did not prove service absence: exit=' +
        $PreQuery.ExitCode + ' output=' + ($PreQuery.Output -join ' | ')
    )
}

$Lines = [System.Collections.Generic.List[string]]::new()
$Lines.Add('DBYTE-HOLYC-OPT')
$Lines.Add('PORTABLE VIRTUALBOX7 VBOXSUP SURGICAL HOST MUTATION')
$Lines.Add('')
$Lines.Add("portable_root`t$PortableRoot")
$Lines.Add("bound_loader_report_sha256`t$LoaderHash")
$Lines.Add("bound_pe_report_sha256`t$PeHash")
$Lines.Add("driver_path`t$DriverPath")
$Lines.Add("driver_sha256`t$DriverHash")
$Lines.Add("driver_version`t$($DriverItem.VersionInfo.FileVersion)")
$Lines.Add("driver_signature_status`t$($Signature.Status)")
$Lines.Add("driver_signature_signer`t$Signer")
$Lines.Add("inf_sha256`t$InfHash")
$Lines.Add("cat_sha256`t$CatHash")
$Lines.Add("administrator`t$IsAdministrator")
$Lines.Add("pre_vbox_process_count`t$($VBoxProcesses.Count)")
Add-ScEvidence -Lines $Lines -Prefix 'pre_sc_query' -Result $PreQuery
$Lines.Add('')
$Lines.Add("authorized_mutation_1`tsc create VBoxSup / exact portable VBoxSup.sys / kernel / auto")
$Lines.Add("authorized_mutation_2`tsc start VBoxSup")
$Lines.Add("automatic_rollback`tNONE")
$Lines.Add('')

$MutationStarted = $false
$CreateSucceeded = $false
$StartSucceeded = $false

try {
    $MutationStarted = $true
    $Create = Invoke-Sc -Arguments @(
        'create',
        $ServiceName,
        'binPath=', $DriverPath,
        'type=', 'kernel',
        'start=', 'auto',
        'error=', 'normal',
        'DisplayName=', $DisplayName
    )
    Add-ScEvidence -Lines $Lines -Prefix 'sc_create' -Result $Create
    if ($Create.ExitCode -ne 0) {
        throw "sc create VBoxSup failed exit=$($Create.ExitCode) output=$($Create.Output -join ' | ')"
    }
    $CreateSucceeded = $true

    if (-not (Test-Path -LiteralPath $ServiceRegistryPath)) {
        throw 'VBoxSup service registry key missing after successful sc create'
    }
    $ServiceProperties = Get-ItemProperty -LiteralPath $ServiceRegistryPath -ErrorAction Stop
    $ImagePathRaw = [string]$ServiceProperties.ImagePath
    $ImagePathNormalized = Normalize-DriverImagePath -Path $ImagePathRaw
    $ServiceType = [int]$ServiceProperties.Type
    $StartType = [int]$ServiceProperties.Start
    $ErrorControl = [int]$ServiceProperties.ErrorControl
    $ObservedDisplayName = [string]$ServiceProperties.DisplayName

    $Lines.Add("service_image_path_raw`t$ImagePathRaw")
    $Lines.Add("service_image_path_normalized`t$ImagePathNormalized")
    $Lines.Add("service_type`t$ServiceType")
    $Lines.Add("service_start_type`t$StartType")
    $Lines.Add("service_error_control`t$ErrorControl")
    $Lines.Add("service_display_name`t$ObservedDisplayName")

    Assert-PathEquals -Observed $ImagePathNormalized -Expected $DriverPath -Label 'VBoxSup service ImagePath'
    if ($ServiceType -ne 1) {
        throw "VBoxSup service Type mismatch: observed=$ServiceType expected=1"
    }
    if ($StartType -ne 2) {
        throw "VBoxSup service Start mismatch: observed=$StartType expected=2(AUTO_START)"
    }
    if ($ErrorControl -ne 1) {
        throw "VBoxSup service ErrorControl mismatch: observed=$ErrorControl expected=1"
    }
    if ($ObservedDisplayName -cne $DisplayName) {
        throw "VBoxSup DisplayName mismatch: observed=$ObservedDisplayName expected=$DisplayName"
    }

    $Start = Invoke-Sc -Arguments @('start', $ServiceName)
    Add-ScEvidence -Lines $Lines -Prefix 'sc_start' -Result $Start
    if ($Start.ExitCode -ne 0) {
        throw "sc start VBoxSup failed exit=$($Start.ExitCode) output=$($Start.Output -join ' | ')"
    }
    $StartSucceeded = $true

    $PostQuery = Invoke-Sc -Arguments @('query', $ServiceName)
    Add-ScEvidence -Lines $Lines -Prefix 'post_sc_query' -Result $PostQuery
    if ($PostQuery.ExitCode -ne 0) {
        throw "post-start sc query VBoxSup failed exit=$($PostQuery.ExitCode)"
    }
    $PostQueryText = $PostQuery.Output -join "`n"
    if ($PostQueryText -notmatch '(?im)^\s*STATE\s*:\s*4\s+RUNNING\s*$') {
        throw 'VBoxSup post-start query did not prove STATE 4 RUNNING'
    }

    $CimError = ''
    $CimRows = @()
    try {
        $CimRows = @(
            Get-CimInstance -ClassName Win32_SystemDriver -ErrorAction Stop |
                Where-Object { $_.Name -ieq $ServiceName }
        )
    }
    catch {
        $CimError = $_.Exception.Message
    }
    $Lines.Add("cim_query_error`t$CimError")
    $Lines.Add("cim_vboxsup_count`t$($CimRows.Count)")
    foreach ($Row in $CimRows) {
        $Lines.Add(
            'cim_vboxsup' + "`t" +
            [string]$Row.Name + "`t" +
            [string]$Row.State + "`t" +
            [string]$Row.StartMode + "`t" +
            [string]$Row.PathName
        )
    }

    $DriverHashAfter = (Get-FileHash -LiteralPath $DriverPath -Algorithm SHA256).Hash
    $InfHashAfter = (Get-FileHash -LiteralPath $InfPath -Algorithm SHA256).Hash
    $CatHashAfter = (Get-FileHash -LiteralPath $CatPath -Algorithm SHA256).Hash
    $Lines.Add("driver_sha256_after`t$DriverHashAfter")
    $Lines.Add("inf_sha256_after`t$InfHashAfter")
    $Lines.Add("cat_sha256_after`t$CatHashAfter")
    if ($DriverHashAfter -cne $ExpectedDriverHash) {
        throw 'VBoxSup.sys changed during create/start'
    }
    if ($InfHashAfter -cne $ExpectedInfHash) {
        throw 'VBoxSup.inf changed during create/start'
    }
    if ($CatHashAfter -cne $ExpectedCatHash) {
        throw 'VBoxSup.cat changed during create/start'
    }

    $Lines.Add('')
    $Lines.Add("SC CREATE`tEXECUTED-ONCE")
    $Lines.Add("SC START`tEXECUTED-ONCE")
    $Lines.Add("SERVICE STATE`tRUNNING / OBSERVED-BY-SC")
    $Lines.Add("SERVICE CLEANUP`tNOT-EXECUTED")
    $Lines.Add("VBOXMANAGE`tNOT-EXECUTED")
    $Lines.Add("VM START`tNOT-AUTHORIZED")
    $Lines.Add("VM RETRY`tNOT-AUTHORIZED / SEPARATE READ-ONLY VERIFICATION REQUIRED")
    $Lines.Add("VERDICT`tVBOXSUP CREATED + STARTED / VERIFICATION PENDING")
    $Lines.Add('')
    $Lines.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')

    [System.IO.File]::WriteAllText(
        $Output,
        (($Lines.ToArray() -join "`n") + "`n"),
        [System.Text.UTF8Encoding]::new($false)
    )
    $ReportHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

    Write-Host "PORTABLE ROOT:          $PortableRoot"
    Write-Host "BOUND LOADER REPORT:    $LoaderHash"
    Write-Host "BOUND PE REPORT:        $PeHash"
    Write-Host "VBOXSUP.SYS SHA256:     $DriverHash"
    Write-Host "VBOXSUP.SYS SIGNATURE:  $($Signature.Status)"
    Write-Host 'SC CREATE:              EXECUTED-ONCE / EXIT 0'
    Write-Host 'SC START:               EXECUTED-ONCE / EXIT 0'
    Write-Host 'SERVICE STATE:          RUNNING / OBSERVED-BY-SC'
    Write-Host "REPORT:                 $Output"
    Write-Host "REPORT SHA256:          $ReportHash"
    Write-Host 'SERVICE CLEANUP:        NOT-EXECUTED'
    Write-Host 'VBOXMANAGE:             NOT-EXECUTED'
    Write-Host 'VM START:               NOT-AUTHORIZED'
    Write-Host 'VM RETRY:               NOT-AUTHORIZED / VERIFY FIRST'
    Write-Host 'VERDICT:                VBOXSUP CREATED + STARTED / VERIFICATION PENDING'
}
catch {
    if ($MutationStarted -and -not (Test-Path -LiteralPath $Output)) {
        $Lines.Add('')
        $Lines.Add("failure_message`t$($_.Exception.Message)")
        $Lines.Add("create_succeeded`t$CreateSucceeded")
        $Lines.Add("start_succeeded`t$StartSucceeded")
        $Lines.Add("AUTOMATIC ROLLBACK`tNOT-EXECUTED")
        $Lines.Add("SERVICE CLEANUP`tNOT-EXECUTED")
        $Lines.Add("VBOXMANAGE`tNOT-EXECUTED")
        $Lines.Add("VM START`tNOT-AUTHORIZED")
        $Lines.Add("VERDICT`tVBOXSUP SURGICAL MUTATION FAILED / HOST STATE PRESERVED")
        $Lines.Add('')
        $Lines.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')
        [System.IO.File]::WriteAllText(
            $Output,
            (($Lines.ToArray() -join "`n") + "`n"),
            [System.Text.UTF8Encoding]::new($false)
        )
        $FailureHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash
        Write-Host "VBOXSUP FAILURE REPORT: $Output"
        Write-Host "FAILURE REPORT SHA256:  $FailureHash"
        Write-Host 'AUTOMATIC ROLLBACK:     NOT-EXECUTED'
    }
    throw
}
