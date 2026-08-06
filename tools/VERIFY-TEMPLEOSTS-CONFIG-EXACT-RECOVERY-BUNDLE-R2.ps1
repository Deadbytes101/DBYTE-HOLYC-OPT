[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VBoxManagePath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DiffReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PreparationReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RecoveryRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PreservedIncompleteRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedOriginalBlob = '8abcae1286332b8b8fc23e1d298b798cbaca614c'
$OriginalRelative =
    'tools/VERIFY-TEMPLEOSTS-CONFIG-EXACT-RECOVERY-BUNDLE.ps1'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$OriginalPath = Join-Path $RepoRoot (
    $OriginalRelative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
)

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
        throw "$Label failed`n$($Captured -join "`n")"
    }
    return $Captured
}

function Invoke-ExactReplacement {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Old,
        [Parameter(Mandatory = $true)][string]$New,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $OldCount = [regex]::Matches(
        $Source,
        [regex]::Escape($Old),
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    ).Count
    $NewCountBefore = [regex]::Matches(
        $Source,
        [regex]::Escape($New),
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    ).Count
    if ($OldCount -ne 1 -or $NewCountBefore -ne 0) {
        throw (
            "$Label source cardinality mismatch: " +
            "old=$OldCount new_before=$NewCountBefore"
        )
    }

    $Patched = $Source.Replace($Old, $New)
    $OldCountAfter = [regex]::Matches(
        $Patched,
        [regex]::Escape($Old),
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    ).Count
    $NewCountAfter = [regex]::Matches(
        $Patched,
        [regex]::Escape($New),
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    ).Count
    if ($OldCountAfter -ne 0 -or $NewCountAfter -ne 1) {
        throw (
            "$Label replacement contract mismatch: " +
            "old_after=$OldCountAfter new_after=$NewCountAfter"
        )
    }
    return $Patched
}

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Text)

    $Bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Text)
    $Sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return (
            [System.BitConverter]::ToString($Sha.ComputeHash($Bytes))
        ).Replace('-', '')
    }
    finally {
        $Sha.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $OriginalPath -PathType Leaf)) {
    throw "original verifier missing: $OriginalPath"
}

$TreeBlob = @(
    Invoke-GitRead `
        -Arguments @('rev-parse', "HEAD`:$OriginalRelative") `
        -Label 'original verifier tree blob'
)
$LocalBlob = @(
    Invoke-GitRead `
        -Arguments @('hash-object', '--', $OriginalRelative) `
        -Label 'original verifier local blob'
)
if (
    $TreeBlob.Count -ne 1 -or
    $LocalBlob.Count -ne 1 -or
    $TreeBlob[0] -cne $ExpectedOriginalBlob -or
    $LocalBlob[0] -cne $ExpectedOriginalBlob
) {
    throw (
        "original verifier blob mismatch: " +
        "tree=$($TreeBlob -join '|') local=$($LocalBlob -join '|')"
    )
}

$Source = [System.IO.File]::ReadAllText($OriginalPath)

$OldRunningParameter = @'
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Running,
'@
$NewRunningParameter = @'
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Running,
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $Source `
    -Old $OldRunningParameter `
    -New $NewRunningParameter `
    -Label 'captured running empty-string parameter contract'

$OldRunningEvaluation = @'
    $RunningPattern = '^"' + [regex]::Escape($ExpectedTargetName) + '" '
    if (@($Running | Where-Object { $_ -match $RunningPattern }).Count -ne 0) {
        throw 'target is currently listed as running'
    }
'@
$NewRunningEvaluation = @'
    $WhitespaceOnlyRunning = @(
        $Running | Where-Object {
            $_ -cne '' -and [string]::IsNullOrWhiteSpace($_)
        }
    )
    if ($WhitespaceOnlyRunning.Count -ne 0) {
        throw 'running inventory contains nonempty whitespace-only rows'
    }
    $NonEmptyRunning = @($Running | Where-Object { $_ -cne '' })
    $RunningPattern = '^"' + [regex]::Escape($ExpectedTargetName) + '" '
    if (@($NonEmptyRunning | Where-Object { $_ -match $RunningPattern }).Count -ne 0) {
        throw 'target is currently listed as running'
    }
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldRunningEvaluation `
    -New $NewRunningEvaluation `
    -Label 'captured running exact-empty normalization'

if ($PatchedSource -ceq $Source) {
    throw 'in-memory verifier hardening produced no source change'
}
$PatchedHash = Get-TextSha256 -Text $PatchedSource
$Verifier = [scriptblock]::Create($PatchedSource)
$InvokeArguments = @{
    VBoxManagePath = $VBoxManagePath
    ResourceRoot = $ResourceRoot
    DiffReportPath = $DiffReportPath
    PreparationReportPath = $PreparationReportPath
    RecoveryRoot = $RecoveryRoot
    PreservedIncompleteRoot = $PreservedIncompleteRoot
    OutPath = $OutPath
}

Write-Host "ORIGINAL VERIFIER:    $ExpectedOriginalBlob"
Write-Host 'RUNNING PARAM GUARD:  IN-MEMORY / EXACT-ONE-REPLACEMENT'
Write-Host 'RUNNING ROW GUARD:    EXACT EMPTY ONLY / EXACT-ONE-REPLACEMENT'
Write-Host "PATCHED SOURCE SHA:   $PatchedHash"
& $Verifier @InvokeArguments
