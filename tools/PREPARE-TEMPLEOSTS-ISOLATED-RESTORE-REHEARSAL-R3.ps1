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
    [string]$VerificationReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RouteReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RecoveryRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RehearsalRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedR2Blob = '5ba96e9792911ba2f254d1bbf87f1e45db925677'
$R2Relative =
    'tools/PREPARE-TEMPLEOSTS-ISOLATED-RESTORE-REHEARSAL-R2.ps1'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$R2Path = Join-Path $RepoRoot (
    $R2Relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
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

if (-not (Test-Path -LiteralPath $R2Path -PathType Leaf)) {
    throw "R2 wrapper missing: $R2Path"
}

$TreeBlob = @(
    Invoke-GitRead `
        -Arguments @('rev-parse', "HEAD`:$R2Relative") `
        -Label 'R2 wrapper tree blob'
)
$LocalBlob = @(
    Invoke-GitRead `
        -Arguments @('hash-object', '--', $R2Relative) `
        -Label 'R2 wrapper local blob'
)
if (
    $TreeBlob.Count -ne 1 -or
    $LocalBlob.Count -ne 1 -or
    $TreeBlob[0] -cne $ExpectedR2Blob -or
    $LocalBlob[0] -cne $ExpectedR2Blob
) {
    throw (
        'R2 wrapper blob mismatch: ' +
        "tree=$($TreeBlob -join '|') local=$($LocalBlob -join '|')"
    )
}

$Source = [System.IO.File]::ReadAllText($R2Path)

$OldPostcondition = @'
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
    if ($OldCountAfter -ne 0 -or $NewCountAfter -ne $ExpectedCount) {
        throw (
            "$Label replacement contract mismatch: " +
            "old_after=$OldCountAfter new_after=$NewCountAfter " +
            "expected=$ExpectedCount"
        )
    }
'@
$NewPostcondition = @'
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
    $OldOccurrencesPerNew = [regex]::Matches(
        $New,
        [regex]::Escape($Old),
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    ).Count
    $ExpectedOldCountAfter = $ExpectedCount * $OldOccurrencesPerNew
    if (
        $OldCountAfter -ne $ExpectedOldCountAfter -or
        $NewCountAfter -ne $ExpectedCount
    ) {
        throw (
            "$Label replacement contract mismatch: " +
            "old_after=$OldCountAfter " +
            "expected_old_after=$ExpectedOldCountAfter " +
            "old_per_new=$OldOccurrencesPerNew " +
            "new_after=$NewCountAfter expected=$ExpectedCount"
        )
    }
'@

$OldCount = [regex]::Matches(
    $Source,
    [regex]::Escape($OldPostcondition),
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
).Count
$NewCountBefore = [regex]::Matches(
    $Source,
    [regex]::Escape($NewPostcondition),
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
).Count
if ($OldCount -ne 1 -or $NewCountBefore -ne 0) {
    throw (
        'R2 helper postcondition source cardinality mismatch: ' +
        "old=$OldCount new_before=$NewCountBefore"
    )
}

$PatchedSource = $Source.Replace($OldPostcondition, $NewPostcondition)
$OldCountAfter = [regex]::Matches(
    $PatchedSource,
    [regex]::Escape($OldPostcondition),
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
).Count
$NewCountAfter = [regex]::Matches(
    $PatchedSource,
    [regex]::Escape($NewPostcondition),
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
).Count
if ($OldCountAfter -ne 0 -or $NewCountAfter -ne 1) {
    throw (
        'R2 helper postcondition replacement mismatch: ' +
        "old_after=$OldCountAfter new_after=$NewCountAfter"
    )
}
if ($PatchedSource -ceq $Source) {
    throw 'R2 helper correction produced no source change'
}

$PatchedHash = Get-TextSha256 -Text $PatchedSource
$R2 = [scriptblock]::Create($PatchedSource)
$InvokeArguments = @{
    VBoxManagePath = $VBoxManagePath
    ResourceRoot = $ResourceRoot
    VerificationReportPath = $VerificationReportPath
    RouteReportPath = $RouteReportPath
    RecoveryRoot = $RecoveryRoot
    RehearsalRoot = $RehearsalRoot
    OutPath = $OutPath
}

Write-Host "ORIGINAL R2 WRAPPER:  $ExpectedR2Blob"
Write-Host 'EXTENSION CONTRACT:   OLD-IN-NEW CARDINALITY / EXACT-ONE-REPLACEMENT'
Write-Host "PATCHED R2 SHA:       $PatchedHash"
& $R2 @InvokeArguments
