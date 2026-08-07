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
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedPortableRoot = 'D:\Portable-VirtualBox7'
$ExpectedLoaderSurfaceReport =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-portable-vbox-driver-loader-surface-inspection.txt'
$ExpectedLoaderSurfaceHash =
    '7C9ABBAE87AA926F11D73A16B17C24AC287EEBB7AB620A63C9A6EBA58866AA2C'
$ExpectedWrapperHash =
    '2F0F9F4E4096F7BA67284F8168D03E1CE0A992047782F49233374CA33B5F6E8E'
$ExpectedOut =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-portable-vbox-wrapper-binary-loader-inspection.txt'

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

function Test-PrintableAsciiByte {
    param([Parameter(Mandatory = $true)][byte]$Value)

    return ($Value -ge 0x20 -and $Value -le 0x7e)
}

function Get-AsciiStrings {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [int]$MinimumLength = 4
    )

    $Rows = [System.Collections.Generic.List[object]]::new()
    $Index = 0
    while ($Index -lt $Bytes.Length) {
        if (-not (Test-PrintableAsciiByte -Value $Bytes[$Index])) {
            $Index++
            continue
        }

        $Start = $Index
        while (
            $Index -lt $Bytes.Length -and
            (Test-PrintableAsciiByte -Value $Bytes[$Index])
        ) {
            $Index++
        }

        $Length = $Index - $Start
        if ($Length -ge $MinimumLength) {
            $Text = [System.Text.Encoding]::ASCII.GetString(
                $Bytes,
                $Start,
                $Length
            )
            $Rows.Add([pscustomobject]@{
                Encoding = 'ASCII'
                Offset = $Start
                Text = $Text
            })
        }
    }
    return $Rows.ToArray()
}

function Get-Utf16LeStrings {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [int]$MinimumLength = 4
    )

    $Rows = [System.Collections.Generic.List[object]]::new()
    $Index = 0
    while ($Index -lt ($Bytes.Length - 1)) {
        $IsPair = (
            (Test-PrintableAsciiByte -Value $Bytes[$Index]) -and
            $Bytes[$Index + 1] -eq 0
        )
        if (-not $IsPair) {
            $Index++
            continue
        }

        $Start = $Index
        $CharacterCount = 0
        while ($Index -lt ($Bytes.Length - 1)) {
            if (
                -not (Test-PrintableAsciiByte -Value $Bytes[$Index]) -or
                $Bytes[$Index + 1] -ne 0
            ) {
                break
            }
            $CharacterCount++
            $Index += 2
        }

        if ($CharacterCount -ge $MinimumLength) {
            $Text = [System.Text.Encoding]::Unicode.GetString(
                $Bytes,
                $Start,
                ($CharacterCount * 2)
            )
            $Rows.Add([pscustomobject]@{
                Encoding = 'UTF16LE'
                Offset = $Start
                Text = $Text
            })
        }
    }
    return $Rows.ToArray()
}

function Get-MatchingStringRows {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Rows,

        [Parameter(Mandatory = $true)]
        [string[]]$Tokens
    )

    $Matches = [System.Collections.Generic.List[object]]::new()
    foreach ($Row in $Rows) {
        foreach ($Token in $Tokens) {
            if (
                $Row.Text.IndexOf(
                    $Token,
                    [System.StringComparison]::OrdinalIgnoreCase
                ) -ge 0
            ) {
                $Matches.Add([pscustomobject]@{
                    Encoding = [string]$Row.Encoding
                    Offset = [long]$Row.Offset
                    Token = $Token
                    Text = [string]$Row.Text
                })
                break
            }
        }
    }
    return $Matches.ToArray()
}

$PortableRoot = (
    Resolve-Path -LiteralPath $PortableVirtualBoxRoot -ErrorAction Stop
).Path
$LoaderReport = (
    Resolve-Path -LiteralPath $LoaderSurfaceReportPath -ErrorAction Stop
).Path
$Output = Get-FullPath -Path $OutPath

Assert-PathEquals `
    -Observed $PortableRoot `
    -Expected $ExpectedPortableRoot `
    -Label 'portable VirtualBox root'
Assert-PathEquals `
    -Observed $LoaderReport `
    -Expected $ExpectedLoaderSurfaceReport `
    -Label 'loader-surface report'
Assert-PathEquals `
    -Observed $Output `
    -Expected $ExpectedOut `
    -Label 'wrapper binary inspection report'

if (Test-Path -LiteralPath $Output) {
    throw "wrapper binary inspection report already exists: $Output"
}
$OutputParent = Split-Path -Parent $Output
if (-not (Test-Path -LiteralPath $OutputParent -PathType Container)) {
    throw "wrapper binary inspection report parent missing: $OutputParent"
}

$LoaderReportHash = (
    Get-FileHash -LiteralPath $LoaderReport -Algorithm SHA256
).Hash
if ($LoaderReportHash -cne $ExpectedLoaderSurfaceHash) {
    throw (
        'loader-surface report SHA256 mismatch: ' +
        "observed=$LoaderReportHash expected=$ExpectedLoaderSurfaceHash"
    )
}

$WrapperPath = Join-Path $PortableRoot 'Portable-VirtualBox7.exe'
if (-not (Test-Path -LiteralPath $WrapperPath -PathType Leaf)) {
    throw "Portable-VirtualBox7 wrapper missing: $WrapperPath"
}
$WrapperItem = Get-Item -LiteralPath $WrapperPath -Force -ErrorAction Stop
$WrapperHash = (
    Get-FileHash -LiteralPath $WrapperPath -Algorithm SHA256
).Hash
if ($WrapperHash -cne $ExpectedWrapperHash) {
    throw (
        'Portable-VirtualBox7 wrapper SHA256 mismatch: ' +
        "observed=$WrapperHash expected=$ExpectedWrapperHash"
    )
}
$WrapperSignature = Get-AuthenticodeSignature -LiteralPath $WrapperPath

$Bytes = [System.IO.File]::ReadAllBytes($WrapperPath)
$AsciiRows = @(Get-AsciiStrings -Bytes $Bytes -MinimumLength 4)
$Utf16Rows = @(Get-Utf16LeStrings -Bytes $Bytes -MinimumLength 4)
$AllRows = @($AsciiRows + $Utf16Rows)

$LoaderTokens = @(
    'VBoxSup',
    'VBoxDrv',
    'VBoxDrvStub',
    'VBoxSDS',
    'VBoxSup.inf',
    'VBoxSup.sys',
    'drivers\vboxsup',
    'drivers/vboxsup',
    'devcon',
    'devcon_x64',
    'devcon_x86',
    'pnputil',
    'rundll32',
    'InstallHinfSection',
    'SetupAPI',
    'SetupCopyOEMInf',
    'DiInstallDriver',
    'UpdateDriverForPlugAndPlayDevices',
    'NewDev',
    'OpenSCManager',
    'CreateService',
    'StartService',
    'ControlService',
    'DeleteService',
    'sc.exe',
    'net start',
    'driver install',
    'driver start',
    'admin',
    'elevat',
    'runas'
)

$DllTokens = @(
    'advapi32.dll',
    'setupapi.dll',
    'newdev.dll',
    'cfgmgr32.dll',
    'shell32.dll',
    'kernel32.dll'
)

$LoaderMatches = @(
    Get-MatchingStringRows -Rows $AllRows -Tokens $LoaderTokens |
        Sort-Object Offset, Encoding, Token, Text
)
$DllMatches = @(
    Get-MatchingStringRows -Rows $AllRows -Tokens $DllTokens |
        Sort-Object Offset, Encoding, Token, Text
)

$Lines = [System.Collections.Generic.List[string]]::new()
$Lines.Add('DBYTE-HOLYC-OPT')
$Lines.Add('PORTABLE VIRTUALBOX7 WRAPPER BINARY LOADER SURFACE READ-ONLY INSPECTION')
$Lines.Add('')
$Lines.Add("portable_root`t$PortableRoot")
$Lines.Add("bound_loader_surface_sha256`t$LoaderReportHash")
$Lines.Add("wrapper_path`t$WrapperPath")
$Lines.Add("wrapper_bytes`t$($WrapperItem.Length)")
$Lines.Add("wrapper_sha256`t$WrapperHash")
$Lines.Add("wrapper_version`t$($WrapperItem.VersionInfo.FileVersion)")
$Lines.Add("wrapper_signature_status`t$($WrapperSignature.Status)")
$Lines.Add("wrapper_signature_signer`t$($WrapperSignature.SignerCertificate.Subject)")
$Lines.Add('')
$Lines.Add("ascii_string_count`t$($AsciiRows.Count)")
$Lines.Add("utf16le_string_count`t$($Utf16Rows.Count)")
$Lines.Add("loader_match_count`t$($LoaderMatches.Count)")
foreach ($Match in $LoaderMatches) {
    $Lines.Add(
        'loader_match' + "`t" +
        $Match.Encoding + "`t" +
        ('0x{0:X}' -f $Match.Offset) + "`t" +
        $Match.Token + "`t" +
        $Match.Text
    )
}
$Lines.Add('')
$Lines.Add("dll_match_count`t$($DllMatches.Count)")
foreach ($Match in $DllMatches) {
    $Lines.Add(
        'dll_match' + "`t" +
        $Match.Encoding + "`t" +
        ('0x{0:X}' -f $Match.Offset) + "`t" +
        $Match.Token + "`t" +
        $Match.Text
    )
}
$Lines.Add('')
$Lines.Add("HOST MUTATION`tNOT-EXECUTED")
$Lines.Add("DRIVER INSTALL/START`tNOT-EXECUTED")
$Lines.Add("VBOXMANAGE`tNOT-EXECUTED")
$Lines.Add("VM START`tNOT-AUTHORIZED")
$Lines.Add("VERDICT`tPORTABLE WRAPPER BINARY LOADER SURFACE INSPECTION COMPLETE")
$Lines.Add('')
$Lines.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')

[System.IO.File]::WriteAllText(
    $Output,
    (($Lines.ToArray() -join "`n") + "`n"),
    [System.Text.UTF8Encoding]::new($false)
)

$ReportHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash
Write-Host "PORTABLE ROOT:          $PortableRoot"
Write-Host "BOUND LOADER REPORT:    $LoaderReportHash"
Write-Host "WRAPPER SHA256:         $WrapperHash"
Write-Host "WRAPPER VERSION:        $($WrapperItem.VersionInfo.FileVersion)"
Write-Host "WRAPPER SIGNATURE:      $($WrapperSignature.Status)"
Write-Host "ASCII STRINGS:          $($AsciiRows.Count)"
Write-Host "UTF16LE STRINGS:        $($Utf16Rows.Count)"
Write-Host "LOADER MATCHES:         $($LoaderMatches.Count)"
Write-Host "DLL MATCHES:            $($DllMatches.Count)"
Write-Host "REPORT:                 $Output"
Write-Host "REPORT SHA256:          $ReportHash"
Write-Host 'HOST MUTATION:          NOT-EXECUTED'
Write-Host 'DRIVER INSTALL/START:   NOT-EXECUTED'
Write-Host 'VBOXMANAGE:             NOT-EXECUTED'
Write-Host 'VM START:               NOT-AUTHORIZED'
Write-Host 'VERDICT:                PORTABLE WRAPPER BINARY LOADER SURFACE INSPECTION COMPLETE'
