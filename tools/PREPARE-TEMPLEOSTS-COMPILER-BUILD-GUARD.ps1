[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ExtractRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ManifestPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$WorkRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$InstallReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$BuildRouteReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$GuardRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedManifestHash =
    '6556485E4425386687C53F4F626146A2136AE12F38E075E2646C98147D61CB68'
$ExpectedInstallReportHash =
    '59B0BB29AA5C088114E38FE27FCF5CB5E2D3F59120CD6FD2678DF9D566C75E32'
$ExpectedBuildRouteReportHash =
    'ED5108F73DE8363E948D559F7625F8752C15B6AD0AED941C40EDD01D0A8488A6'
$ExpectedFileCount = 1057

$Files = [ordered]@{
    'recovery-raw/Compiler/Compiler.PRJ.Z' = @(
        'raw',
        'Compiler/Compiler.PRJ.Z',
        434L,
        'EA47905E08F6DA8517B76BCFC6EC36B85E4E73A7F2FC247AE686CD7743408FCD'
    )
    'recovery-raw/Compiler/Compiler.BIN.Z' = @(
        'raw',
        'Compiler/Compiler.BIN.Z',
        123896L,
        '76779475B81AAB0EBEDA7C1C184FA17806C001E485062663029A548016E82A17'
    )
    'recovery-raw/Compiler/Compiler.MAP.Z' = @(
        'raw',
        'Compiler/Compiler.MAP.Z',
        66287L,
        '56F128A690021233F4FBB61873A9ECD627D4C9625E0B57A47CE15EF2E42CAD3D'
    )
    'recovery-raw/Compiler/ICLCC.CPP.Z' = @(
        'raw',
        'Compiler/ICLCC.CPP.Z',
        5213L,
        '22420A60C16B8EB46129AA89B6A0BF29315B3F92E5FF671F9179F8EFB8B4F21C'
    )
    'baseline-expanded/Compiler/Compiler.PRJ' = @(
        'expanded',
        'Compiler/Compiler.PRJ',
        858L,
        'D82BBFE3B9A75B67D5C3E1B6E5EB03628960B81FAC9E3453212AE1163A47F779'
    )
    'baseline-expanded/Compiler/Compiler.BIN' = @(
        'expanded',
        'Compiler/Compiler.BIN',
        206512L,
        '010F06358F26B5804600EE5BD6E6D313209C006C606E5F72C1E68D4028825AD1'
    )
    'baseline-expanded/Compiler/Compiler.MAP' = @(
        'expanded',
        'Compiler/Compiler.MAP',
        202757L,
        '8509A6224474915233209975E9D56598FA79E005F616B31B878D4350CED247A5'
    )
    'baseline-expanded/Compiler/ICLCC.CPP' = @(
        'expanded',
        'Compiler/ICLCC.CPP',
        10465L,
        '2F7A5A00947504E1D4D7DCFDBC99B16944D44F6C1DCEDABF2DAE6C60E5CD4873'
    )
    'candidate-expanded/Compiler/ICLCC.CPP' = @(
        'workspace',
        'Compiler/ICLCC.CPP',
        10527L,
        'DB1C75A5EE71B07ADAEC32E984146602E73D9A0D606E2B76B8CCCC624E0CDCB8'
    )
}

function Assert-ExactFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [long]$Bytes,

        [Parameter(Mandatory = $true)]
        [string]$SHA256,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label missing: $Path"
    }
    $Item = Get-Item -LiteralPath $Path
    $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($Item.Length -ne $Bytes -or $Hash -cne $SHA256) {
        throw "$Label identity mismatch: bytes=$($Item.Length) SHA256=$Hash"
    }
}

function Get-Prefix([string]$Path) {
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/') +
        [System.IO.Path]::DirectorySeparatorChar
}

$Root = (Resolve-Path -LiteralPath $ExtractRoot -ErrorAction Stop).Path
$Raw = [System.IO.Path]::GetFullPath((Join-Path $Root 'raw'))
$Expanded = [System.IO.Path]::GetFullPath((Join-Path $Root 'expanded'))
$Manifest = (Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop).Path
$Work = (Resolve-Path -LiteralPath $WorkRoot -ErrorAction Stop).Path
$InstallReport = (Resolve-Path -LiteralPath $InstallReportPath -ErrorAction Stop).Path
$BuildRouteReport = (
    Resolve-Path -LiteralPath $BuildRouteReportPath -ErrorAction Stop
).Path
$Guard = [System.IO.Path]::GetFullPath($GuardRoot)
$Output = [System.IO.Path]::GetFullPath($OutPath)

foreach ($RequiredDirectory in @($Raw, $Expanded, $Work)) {
    if (-not (Test-Path -LiteralPath $RequiredDirectory -PathType Container)) {
        throw "required directory missing: $RequiredDirectory"
    }
}
if (Test-Path -LiteralPath $Guard) {
    throw "guard root already exists: $Guard"
}
if (Test-Path -LiteralPath $Output) {
    throw "output already exists: $Output"
}

$GuardPrefix = Get-Prefix $Guard
foreach ($Protected in @($Root, $Raw, $Expanded, $Work)) {
    $ProtectedFull = [System.IO.Path]::GetFullPath($Protected)
    if (
        $Guard -ceq $ProtectedFull -or
        $Guard.StartsWith(
            (Get-Prefix $ProtectedFull),
            [System.StringComparison]::OrdinalIgnoreCase
        ) -or
        $ProtectedFull.StartsWith(
            $GuardPrefix,
            [System.StringComparison]::OrdinalIgnoreCase
        )
    ) {
        throw "guard root overlaps protected tree: $ProtectedFull"
    }
}

$ManifestHash = (Get-FileHash -LiteralPath $Manifest -Algorithm SHA256).Hash
$InstallHash = (Get-FileHash -LiteralPath $InstallReport -Algorithm SHA256).Hash
$BuildRouteHash = (
    Get-FileHash -LiteralPath $BuildRouteReport -Algorithm SHA256
).Hash

if ($ManifestHash -cne $ExpectedManifestHash) {
    throw "manifest hash mismatch: $ManifestHash"
}
if ($InstallHash -cne $ExpectedInstallReportHash) {
    throw "install report hash mismatch: $InstallHash"
}
if ($BuildRouteHash -cne $ExpectedBuildRouteReportHash) {
    throw "build route report hash mismatch: $BuildRouteHash"
}

$ManifestLines = [System.IO.File]::ReadAllLines($Manifest)
foreach ($GuardRelative in $Files.Keys) {
    $Spec = $Files[$GuardRelative]
    if ($Spec[0] -ceq 'expanded') {
        $ManifestRow = "$($Spec[1])`t$($Spec[2])`t$($Spec[3])"
        if (-not ($ManifestLines -ccontains $ManifestRow)) {
            throw "manifest missing exact guard input: $($Spec[1])"
        }
    }
}

$WorkFiles = @(Get-ChildItem -LiteralPath $Work -Recurse -File)
if ($WorkFiles.Count -ne $ExpectedFileCount) {
    throw "workspace file count mismatch: expected=$ExpectedFileCount actual=$($WorkFiles.Count)"
}

foreach ($GuardRelative in $Files.Keys) {
    $Spec = $Files[$GuardRelative]
    $Native = $Spec[1].Replace(
        '/',
        [System.IO.Path]::DirectorySeparatorChar
    )
    switch ($Spec[0]) {
        'raw'       { $Source = Join-Path $Raw $Native }
        'expanded'  { $Source = Join-Path $Expanded $Native }
        'workspace' { $Source = Join-Path $Work $Native }
        default     { throw "unknown guard source: $($Spec[0])" }
    }
    Assert-ExactFile `
        -Path $Source `
        -Bytes $Spec[2] `
        -SHA256 $Spec[3] `
        -Label $GuardRelative
}

$Parent = Split-Path -Parent $Guard
if ($Parent) {
    New-Item -ItemType Directory -Path $Parent -Force | Out-Null
}
$Partial = "$Guard.partial-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $Partial -Force | Out-Null

foreach ($GuardRelative in $Files.Keys) {
    $Spec = $Files[$GuardRelative]
    $NativeSource = $Spec[1].Replace(
        '/',
        [System.IO.Path]::DirectorySeparatorChar
    )
    $NativeDestination = $GuardRelative.Replace(
        '/',
        [System.IO.Path]::DirectorySeparatorChar
    )
    switch ($Spec[0]) {
        'raw'       { $Source = Join-Path $Raw $NativeSource }
        'expanded'  { $Source = Join-Path $Expanded $NativeSource }
        'workspace' { $Source = Join-Path $Work $NativeSource }
    }
    $Destination = Join-Path $Partial $NativeDestination
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force |
        Out-Null
    [System.IO.File]::Copy($Source, $Destination, $false)
    Assert-ExactFile `
        -Path $Destination `
        -Bytes $Spec[2] `
        -SHA256 $Spec[3] `
        -Label "guard copy $GuardRelative"
}

$ContractPath = Join-Path $Partial 'BUILD-CONTRACT.TXT'
$Contract = @'
DBYTE-HOLYC-OPT
TEMPLEOSTS 1.10 GUARDED COMPILER BUILD CONTRACT

THIS FILE IS A PLAN, NOT BUILD AUTHORIZATION.

SEALED COMPILER-ONLY ROUTE

  Cd("/Compiler");
  if (Cmp("Compiler","Compiler",,':'))
    throw;

RESOLVED GUEST OBJECTS

  input     /Compiler/Compiler.PRJ.Z
  map       /Compiler/Compiler.MAP.Z
  binary    /Compiler/Compiler.BIN.Z

RECOVERY MATERIAL

  recovery-raw contains exact original .Z containers from TempleOSTS 1.10.
  baseline-expanded contains the matching expanded historical bytes.
  candidate-expanded contains only the authorized ICLCC assertion source.

REQUIRED BEFORE INVOCATION

  observe candidate ICLCC.CPP delivery into the guest
  re-read the delivered candidate source
  create guest baseline copies of Compiler.BIN.Z and Compiler.MAP.Z
  record the guest baseline identities
  prove a restore procedure for both outputs
  establish a powered-off recovery point

NOT AUTHORIZED

  MakeAll
  MakeOSPrtBootInstall
  Cmp execution
  output replacement
  boot from candidate output

REPORTS ARE CLAIMS, NOT EVIDENCE.
'@
[System.IO.File]::WriteAllText(
    $ContractPath,
    $Contract.Replace("`r`n", "`n"),
    [System.Text.UTF8Encoding]::new($false)
)

$ManifestOut = Join-Path $Partial 'GUARD-MANIFEST.TXT'
$GuardLines = [System.Collections.Generic.List[string]]::new()
$GuardLines.Add('DBYTE-HOLYC-OPT')
$GuardLines.Add('TEMPLEOSTS 1.10 HOST BUILD GUARD SNAPSHOT')
$GuardLines.Add('')
$GuardLines.Add("expanded_manifest_sha256`t$ManifestHash")
$GuardLines.Add("install_report_sha256`t$InstallHash")
$GuardLines.Add("build_route_report_sha256`t$BuildRouteHash")
$GuardLines.Add('')
$GuardLines.Add("path`tbytes`tSHA256`tsource")

foreach ($GuardRelative in $Files.Keys) {
    $Spec = $Files[$GuardRelative]
    $GuardLines.Add(
        "$GuardRelative`t$($Spec[2])`t$($Spec[3])`t$($Spec[0])"
    )
}
$ContractItem = Get-Item -LiteralPath $ContractPath
$ContractHash = (Get-FileHash -LiteralPath $ContractPath -Algorithm SHA256).Hash
$GuardLines.Add(
    "BUILD-CONTRACT.TXT`t$($ContractItem.Length)`t$ContractHash`tgenerated-plan"
)
$GuardLines.Add('')
$GuardLines.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')

[System.IO.File]::WriteAllText(
    $ManifestOut,
    (($GuardLines -join "`n") + "`n"),
    [System.Text.UTF8Encoding]::new($false)
)
$GuardManifestHash = (
    Get-FileHash -LiteralPath $ManifestOut -Algorithm SHA256
).Hash

$PartialFiles = @(Get-ChildItem -LiteralPath $Partial -Recurse -File)
if ($PartialFiles.Count -ne 11) {
    throw "partial guard file count mismatch: $($PartialFiles.Count)"
}

Move-Item -LiteralPath $Partial -Destination $Guard -ErrorAction Stop

$FinalFiles = @(Get-ChildItem -LiteralPath $Guard -Recurse -File)
if ($FinalFiles.Count -ne 11) {
    throw "final guard file count mismatch: $($FinalFiles.Count)"
}

$Report = @(
    'DBYTE-HOLYC-OPT',
    'TEMPLEOSTS 1.10 HOST BUILD GUARD SNAPSHOT',
    '',
    "expanded_manifest_sha256`t$ManifestHash",
    "install_report_sha256`t$InstallHash",
    "build_route_report_sha256`t$BuildRouteHash",
    "guard_root`t$Guard",
    "guard_files`t$($FinalFiles.Count)",
    "guard_manifest_sha256`t$GuardManifestHash",
    '',
    'The host snapshot contains exact raw recovery containers, expanded baselines, and candidate ICLCC source.',
    'The snapshot does not prove guest delivery, guest backup, guest restore, or a build.',
    'No evidence, workspace, VM, VDI, ISO, or guest file was modified.',
    '',
    "HOST GUARD STATUS`tPREPARED",
    "GUEST DELIVERY STATUS`tUNRESOLVED",
    "GUEST RESTORE STATUS`tUNRESOLVED",
    "BUILD EXECUTION`tNOT-AUTHORIZED",
    "BUILD STATUS`tNOT-OBSERVED",
    '',
    'REPORTS ARE CLAIMS, NOT EVIDENCE.'
)

$OutDir = Split-Path -Parent $Output
if ($OutDir) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}
[System.IO.File]::WriteAllText(
    $Output,
    (($Report -join "`n") + "`n"),
    [System.Text.UTF8Encoding]::new($false)
)

$ReportHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash
Write-Host "WORKSPACE FILES:     $($WorkFiles.Count)/$ExpectedFileCount"
Write-Host "CANDIDATE ICLCC:     $($Files['candidate-expanded/Compiler/ICLCC.CPP'][3])"
Write-Host "GUARD FILES:         $($FinalFiles.Count)"
Write-Host "GUARD MANIFEST:      $GuardManifestHash"
Write-Host "GUARD ROOT:          $Guard"
Write-Host "REPORT:              $Output"
Write-Host "REPORT SHA256:       $ReportHash"
Write-Host 'HOST GUARD:          PREPARED'
Write-Host 'GUEST DELIVERY:      UNRESOLVED'
Write-Host 'BUILD:               NOT-AUTHORIZED'
Write-Host 'VERDICT:             HOST GUARD SNAPSHOT COMPLETE'
