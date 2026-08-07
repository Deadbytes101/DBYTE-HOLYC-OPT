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
    [string]$RehearsalRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedOriginalBlob = 'c5cc5684617f019dcbb6c23e0ee5f4905d5a5cac'
$OriginalRelative =
    'tools/ADJUDICATE-TEMPLEOSTS-ISOLATED-BOOT-READINESS.ps1'
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
    throw "original adjudicator missing: $OriginalPath"
}

$TreeBlob = @(
    Invoke-GitRead `
        -Arguments @('rev-parse', "HEAD`:$OriginalRelative") `
        -Label 'original adjudicator tree blob'
)
$LocalBlob = @(
    Invoke-GitRead `
        -Arguments @('hash-object', '--', $OriginalRelative) `
        -Label 'original adjudicator local blob'
)
if (
    $TreeBlob.Count -ne 1 -or
    $LocalBlob.Count -ne 1 -or
    $TreeBlob[0] -cne $ExpectedOriginalBlob -or
    $LocalBlob[0] -cne $ExpectedOriginalBlob
) {
    throw (
        'original adjudicator blob mismatch: ' +
        "tree=$($TreeBlob -join '|') local=$($LocalBlob -join '|')"
    )
}

$Source = [System.IO.File]::ReadAllText($OriginalPath)
$PSScriptRootReferences = [regex]::Matches(
    $Source,
    [regex]::Escape('$PSScriptRoot'),
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
).Count
if ($PSScriptRootReferences -ne 0) {
    throw (
        'original adjudicator is not safe for dynamic execution: ' +
        "PSScriptRoot references=$PSScriptRootReferences"
    )
}

$OldIsoAttachmentExpression = @'
    $VdiFirstBoot = @('disk', 'harddisk') -contains $Boot1.ToLowerInvariant()
    $IsoAttached = -not [string]::IsNullOrWhiteSpace(
        Get-RequiredMachineValue -Info $IsolatedInfo -Key 'IDE-0-1' -Label 'isolated target'
    )
'@
$NewIsoAttachmentExpression = @'
    $VdiFirstBoot = @('disk', 'harddisk') -contains $Boot1.ToLowerInvariant()
    $IsoAttachmentPath = Get-RequiredMachineValue `
        -Info $IsolatedInfo `
        -Key 'IDE-0-1' `
        -Label 'isolated target'
    $IsoAttached = -not [string]::IsNullOrWhiteSpace(
        $IsoAttachmentPath
    )
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $Source `
    -Old $OldIsoAttachmentExpression `
    -New $NewIsoAttachmentExpression `
    -Label 'ISO attachment parser seam'

if ($PatchedSource -ceq $Source) {
    throw 'in-memory boot-readiness parser correction produced no source change'
}

$PatchedHash = Get-TextSha256 -Text $PatchedSource
$Adjudicator = [scriptblock]::Create($PatchedSource)
$InvokeArguments = @{
    VBoxManagePath = $VBoxManagePath
    ResourceRoot = $ResourceRoot
    RehearsalVerificationReportPath = $RehearsalVerificationReportPath
    RehearsalRoot = $RehearsalRoot
    OutPath = $OutPath
}

Write-Host "ORIGINAL ADJUDICATOR: $ExpectedOriginalBlob"
Write-Host 'ISO ATTACHMENT PARSER: VALUE-FIRST / EXACT-ONE-REPLACEMENT'
Write-Host 'DYNAMIC CONTEXT:      NO PSSCRIPTROOT REFERENCES'
Write-Host "PATCHED SOURCE SHA:   $PatchedHash"
& $Adjudicator @InvokeArguments
