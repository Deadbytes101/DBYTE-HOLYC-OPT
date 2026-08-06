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
    [string]$InspectorReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedOriginalBlob = '608419dd64b805430fee8e72887029fa644ff9ab'
$OriginalRelative = 'tools/DIAGNOSE-TEMPLEOSTS-VBOX-NORMALIZED-DIFF.ps1'
$FaultyExpression = '[int[]]@($CurrentCount + 1, $BaselineCount + 1)'
$CorrectedExpression = '[int[]]@(($CurrentCount + 1), ($BaselineCount + 1))'
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

if (-not (Test-Path -LiteralPath $OriginalPath -PathType Leaf)) {
    throw "original diagnostic missing: $OriginalPath"
}

$TreeBlob = @(
    Invoke-GitRead `
        -Arguments @('rev-parse', "HEAD`:$OriginalRelative") `
        -Label 'original diagnostic tree blob'
)
$LocalBlob = @(
    Invoke-GitRead `
        -Arguments @('hash-object', '--', $OriginalRelative) `
        -Label 'original diagnostic local blob'
)
if (
    $TreeBlob.Count -ne 1 -or
    $LocalBlob.Count -ne 1 -or
    $TreeBlob[0] -cne $ExpectedOriginalBlob -or
    $LocalBlob[0] -cne $ExpectedOriginalBlob
) {
    throw (
        "original diagnostic blob mismatch: " +
        "tree=$($TreeBlob -join '|') local=$($LocalBlob -join '|')"
    )
}

$Source = [System.IO.File]::ReadAllText($OriginalPath)
$FaultCount = [regex]::Matches(
    $Source,
    [regex]::Escape($FaultyExpression),
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
).Count
if ($FaultCount -ne 1) {
    throw "faulty LCS dimension expression count mismatch: $FaultCount"
}
if ($Source.Contains($CorrectedExpression)) {
    throw 'original diagnostic already contains the corrected expression'
}

$PatchedSource = $Source.Replace($FaultyExpression, $CorrectedExpression)
if ($PatchedSource -ceq $Source) {
    throw 'in-memory LCS correction produced no source change'
}
$CorrectedCount = [regex]::Matches(
    $PatchedSource,
    [regex]::Escape($CorrectedExpression),
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
).Count
$RemainingFaultCount = [regex]::Matches(
    $PatchedSource,
    [regex]::Escape($FaultyExpression),
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
).Count
if ($CorrectedCount -ne 1 -or $RemainingFaultCount -ne 0) {
    throw (
        "in-memory correction contract mismatch: " +
        "corrected=$CorrectedCount remaining_fault=$RemainingFaultCount"
    )
}

$Diagnostic = [scriptblock]::Create($PatchedSource)
$InvokeArguments = @{
    VBoxManagePath = $VBoxManagePath
    ResourceRoot = $ResourceRoot
    InspectorReportPath = $InspectorReportPath
    OutPath = $OutPath
}

Write-Host "ORIGINAL DIAGNOSTIC:  $ExpectedOriginalBlob"
Write-Host 'LCS DIMENSION FIX:    IN-MEMORY / EXACT-ONE-REPLACEMENT'
& $Diagnostic @InvokeArguments
