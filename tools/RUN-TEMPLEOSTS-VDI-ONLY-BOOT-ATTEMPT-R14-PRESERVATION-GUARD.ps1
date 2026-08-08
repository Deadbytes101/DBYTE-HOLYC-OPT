[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$VBoxManagePath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ResourceRoot,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RehearsalVerificationReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$BootReadinessReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ModifyVmHelpProbeReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$R2InspectionReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$R2AdjudicationReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$PreservedR1Root,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$PreservedR2Root,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$SealedRehearsalRoot,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$BootAttemptRoot,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedR14Blob = '4ddfa4597c23b58b41731bbc180b119fef1f3f3f'
$R14Relative = 'tools/PREPARE-TEMPLEOSTS-VDI-ONLY-BOOT-ATTEMPT-R14.ps1'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$R14Path = Join-Path $RepoRoot (
    $R14Relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
)

$ExpectedR1Root = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r1'
$ExpectedR2Root = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r2'
$ExpectedR3Root = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r3'
$ExpectedOut = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-boot-attempt-preparation.txt'

$ExpectedR1VBoxHash = '69224A832694CA0C657CA2135ED370F6B7E667B84F93C08D921AED4A6D21F39B'
$ExpectedR1VBoxId = '0X0000000000000000000100000006034F'
$ExpectedR1VdiId = '0X00000000000000000001000000060350'
$ExpectedR1IsoId = '0X00000000000000000001000000060351'

$ExpectedR2VBoxHash = '8EADB39D54CABE5E7B791E5D7E05BCF4CBBF32D4AB6B58291BEC0B2FAD607C0C'
$ExpectedR2VBoxId = '0X00000000000000000005000000060670'
$ExpectedR2PrevHash = 'C93D128227EE80B647DB63FE64277CEF1BDC61C224110472C73CBFFEC63877A7'
$ExpectedR2PrevId = '0X00000000000000000004000000060676'
$ExpectedR2VdiId = '0X00000000000000000001000000060671'
$ExpectedR2IsoId = '0X00000000000000000001000000060672'
$ExpectedVdiHash = '90D453A94F075760A11E0772862E60C4B031ED874F28AA396EAE638F7EB8B31B'
$ExpectedIsoHash = 'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'

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

function Invoke-GitRead {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $Captured = @(
        & git -C $RepoRoot @Arguments 2>&1 |
            ForEach-Object { [string]$_ }
    )
    if ($LASTEXITCODE -ne 0) {
        throw "${Label} failed`n$($Captured -join "`n")"
    }
    return $Captured
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

function Assert-FileState {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$SHA256,
        [Parameter(Mandatory = $true)][string]$FileId,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "${Label} missing: $Path"
    }
    $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($Hash -cne $SHA256) {
        throw "${Label} SHA256 mismatch: observed=$Hash expected=$SHA256"
    }
    $ObservedId = Get-FileId -Path $Path -Label $Label
    if ($ObservedId -cne $FileId) {
        throw "${Label} file-ID mismatch: observed=$ObservedId expected=$FileId"
    }
}

if (-not (Test-Path -LiteralPath $R14Path -PathType Leaf)) {
    throw "R14 preparer missing: $R14Path"
}
$TreeBlob = @(Invoke-GitRead -Arguments @('rev-parse', "HEAD`:$R14Relative") -Label 'R14 tree blob')
$LocalBlob = @(Invoke-GitRead -Arguments @('hash-object', '--', $R14Relative) -Label 'R14 local blob')
if (
    $TreeBlob.Count -ne 1 -or
    $LocalBlob.Count -ne 1 -or
    $TreeBlob[0] -cne $ExpectedR14Blob -or
    $LocalBlob[0] -cne $ExpectedR14Blob
) {
    throw "R14 blob mismatch: tree=$($TreeBlob -join '|') local=$($LocalBlob -join '|')"
}

$R1 = Get-FullPath -Path $PreservedR1Root
$R2 = Get-FullPath -Path $PreservedR2Root
$R3 = Get-FullPath -Path $BootAttemptRoot
$Output = Get-FullPath -Path $OutPath
Assert-PathEquals -Observed $R1 -Expected $ExpectedR1Root -Label 'r1 root'
Assert-PathEquals -Observed $R2 -Expected $ExpectedR2Root -Label 'r2 root'
Assert-PathEquals -Observed $R3 -Expected $ExpectedR3Root -Label 'r3 root'
Assert-PathEquals -Observed $Output -Expected $ExpectedOut -Label 'preparation report'
if (-not (Test-Path -LiteralPath $R1 -PathType Container)) { throw "r1 root missing: $R1" }
if (-not (Test-Path -LiteralPath $R2 -PathType Container)) { throw "r2 root missing: $R2" }
if (Test-Path -LiteralPath $R3) { throw "r3 root already exists: $R3" }
if (Test-Path -LiteralPath $Output) { throw "preparation report already exists: $Output" }

$R1Machine = Join-Path $R1 'Machine'
Assert-FileState -Path (Join-Path $R1Machine 'Temple1.10.vbox') -SHA256 $ExpectedR1VBoxHash -FileId $ExpectedR1VBoxId -Label 'r1 VBOX'
Assert-FileState -Path (Join-Path $R1Machine 'Temple1.10.vdi') -SHA256 $ExpectedVdiHash -FileId $ExpectedR1VdiId -Label 'r1 VDI'
Assert-FileState -Path (Join-Path $R1Machine 'TempleOSTS.iso') -SHA256 $ExpectedIsoHash -FileId $ExpectedR1IsoId -Label 'r1 ISO'

$R2Machine = Join-Path $R2 'Machine'
Assert-FileState -Path (Join-Path $R2Machine 'Temple1.10.vbox') -SHA256 $ExpectedR2VBoxHash -FileId $ExpectedR2VBoxId -Label 'r2 current VBOX'
Assert-FileState -Path (Join-Path $R2Machine 'Temple1.10.vbox-prev') -SHA256 $ExpectedR2PrevHash -FileId $ExpectedR2PrevId -Label 'r2 previous VBOX'
Assert-FileState -Path (Join-Path $R2Machine 'Temple1.10.vdi') -SHA256 $ExpectedVdiHash -FileId $ExpectedR2VdiId -Label 'r2 VDI'
Assert-FileState -Path (Join-Path $R2Machine 'TempleOSTS.iso') -SHA256 $ExpectedIsoHash -FileId $ExpectedR2IsoId -Label 'r2 ISO'

$R2Incomplete = Join-Path $R2 'BOOT-ATTEMPT-INCOMPLETE.txt'
$R2Manifest = Join-Path $R2 'BOOT-ATTEMPT-MANIFEST.txt'
if (-not (Test-Path -LiteralPath $R2Incomplete -PathType Leaf)) {
    throw 'r2 incomplete marker is missing'
}
if (Test-Path -LiteralPath $R2Manifest) {
    throw 'r2 final manifest unexpectedly exists'
}
$R2GenerationNames = @(
    Get-ChildItem -LiteralPath $R2Machine -Force -File |
        Where-Object { $_.Name -match '^Temple1\.10\.vbox(?:-prev|-new)?$' } |
        ForEach-Object { $_.Name } |
        Sort-Object
)
if (
    $R2GenerationNames.Count -ne 2 -or
    -not ($R2GenerationNames -ccontains 'Temple1.10.vbox') -or
    -not ($R2GenerationNames -ccontains 'Temple1.10.vbox-prev')
) {
    throw "r2 generation inventory mismatch: $($R2GenerationNames -join '|')"
}

$InvokeArguments = @{
    VBoxManagePath = $VBoxManagePath
    ResourceRoot = $ResourceRoot
    RehearsalVerificationReportPath = $RehearsalVerificationReportPath
    BootReadinessReportPath = $BootReadinessReportPath
    ModifyVmHelpProbeReportPath = $ModifyVmHelpProbeReportPath
    R2InspectionReportPath = $R2InspectionReportPath
    R2AdjudicationReportPath = $R2AdjudicationReportPath
    PreservedR1Root = $PreservedR1Root
    PreservedR2Root = $PreservedR2Root
    SealedRehearsalRoot = $SealedRehearsalRoot
    BootAttemptRoot = $BootAttemptRoot
    OutPath = $OutPath
}

Write-Host "BOUND R14 PREPARER:    $ExpectedR14Blob"
Write-Host 'R1 PRESERVATION:       VBOX/VDI/ISO HASH + FILE-ID EXACT'
Write-Host 'R2 PRESERVATION:       CURRENT/PREV VBOX + VDI/ISO HASH + FILE-ID EXACT'
Write-Host 'R2 INCOMPLETE MARKER:  PRESENT'
Write-Host 'R2 FINAL MANIFEST:     ABSENT'
Write-Host 'R2 VBOX GENERATIONS:   CURRENT + .vbox-prev ONLY'
Write-Host "NEW R3 ROOT:           $R3"
Write-Host 'GUARD VBOXMANAGE:      NOT-EXECUTED'
Write-Host 'GUARD MUTATION:        NONE'
& $R14Path @InvokeArguments
