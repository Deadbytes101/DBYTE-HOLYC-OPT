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
    [string]$RehearsalVerificationReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$BootReadinessReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SealedRehearsalRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$BootAttemptRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedR2Blob = '796f23166f2ddf14f2e981a14fc31cc5732c5c71'
$R2Relative = 'tools/PREPARE-TEMPLEOSTS-VDI-ONLY-BOOT-ATTEMPT-R2.ps1'
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
        throw "${Label} failed`n$($Captured -join "`n")"
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
            "${Label} source cardinality mismatch: " +
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
            "${Label} replacement mismatch: " +
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

function ConvertTo-SingleQuotedLiteral {
    param([Parameter(Mandatory = $true)][string]$Value)

    return "'" + $Value.Replace("'", "''") + "'"
}

if (-not (Test-Path -LiteralPath $R2Path -PathType Leaf)) {
    throw "R2 preparer missing: $R2Path"
}

$TreeBlob = @(
    Invoke-GitRead `
        -Arguments @('rev-parse', "HEAD`:$R2Relative") `
        -Label 'R2 preparer tree blob'
)
$LocalBlob = @(
    Invoke-GitRead `
        -Arguments @('hash-object', '--', $R2Relative) `
        -Label 'R2 preparer local blob'
)
if (
    $TreeBlob.Count -ne 1 -or
    $LocalBlob.Count -ne 1 -or
    $TreeBlob[0] -cne $ExpectedR2Blob -or
    $LocalBlob[0] -cne $ExpectedR2Blob
) {
    throw (
        'R2 preparer blob mismatch: ' +
        "tree=$($TreeBlob -join '|') local=$($LocalBlob -join '|')"
    )
}

$Source = [System.IO.File]::ReadAllText($R2Path)

$OldAttemptBlock = @'
    $Attempts = @(
        @('modifyvm', '--help'),
        @('--help', 'modifyvm')
    )
'@
$NewAttemptBlock = @'
    $Attempts = [System.Collections.Generic.List[object]]::new()
    $Attempts.Add([string[]]@('modifyvm', '--help'))
    $Attempts.Add([string[]]@('--help', 'modifyvm'))
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $Source `
    -Old $OldAttemptBlock `
    -New $NewAttemptBlock `
    -Label 'modifyvm help argument arrays'

$OldRepoRootAnchor = '$RepoRoot = Split-Path -Parent $PSScriptRoot'
$PSScriptRootCountBefore = [regex]::Matches(
    $PatchedSource,
    [regex]::Escape('$PSScriptRoot'),
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
).Count
$OldRepoRootCountBefore = [regex]::Matches(
    $PatchedSource,
    [regex]::Escape($OldRepoRootAnchor),
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
).Count
if ($PSScriptRootCountBefore -ne 1 -or $OldRepoRootCountBefore -ne 1) {
    throw (
        'R2 repository-root source cardinality mismatch: ' +
        "psscriptroot=$PSScriptRootCountBefore anchor=$OldRepoRootCountBefore"
    )
}

$InjectedRepoRoot = ConvertTo-SingleQuotedLiteral -Value $RepoRoot
$NewRepoRootAnchor = '$RepoRoot = ' + $InjectedRepoRoot
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldRepoRootAnchor `
    -New $NewRepoRootAnchor `
    -Label 'R2 repository-root anchor'

$PSScriptRootCountAfter = [regex]::Matches(
    $PatchedSource,
    [regex]::Escape('$PSScriptRoot'),
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
).Count
if ($PSScriptRootCountAfter -ne 0) {
    throw "R2 patched source retains PSScriptRoot references: $PSScriptRootCountAfter"
}
if ($PatchedSource -ceq $Source) {
    throw 'R3 corrections produced no R2 source change'
}

$PatchedHash = Get-TextSha256 -Text $PatchedSource
$R2 = [scriptblock]::Create($PatchedSource)
$InvokeArguments = @{
    VBoxManagePath = $VBoxManagePath
    ResourceRoot = $ResourceRoot
    RehearsalVerificationReportPath = $RehearsalVerificationReportPath
    BootReadinessReportPath = $BootReadinessReportPath
    SealedRehearsalRoot = $SealedRehearsalRoot
    BootAttemptRoot = $BootAttemptRoot
    OutPath = $OutPath
}

Write-Host "ORIGINAL R2 PREPARER: $ExpectedR2Blob"
Write-Host 'HELP ARGUMENT ARRAYS: LIST[OBJECT] OF STRING[] / EXACT-ONE-REPLACEMENT'
Write-Host 'REPO ROOT ANCHOR:     FILE-BACKED R3 / EXACT-ONE-REPLACEMENT'
Write-Host "INJECTED REPO ROOT:   $RepoRoot"
Write-Host "PATCHED R2 SHA:       $PatchedHash"
& $R2 @InvokeArguments
