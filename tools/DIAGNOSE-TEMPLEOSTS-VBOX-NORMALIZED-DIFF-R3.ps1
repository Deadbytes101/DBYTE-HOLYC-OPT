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
        [Parameter(Mandatory = $true)][int]$ExpectedCount,
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
    if ($OldCount -ne $ExpectedCount -or $NewCountBefore -ne 0) {
        throw (
            "$Label source cardinality mismatch: " +
            "old=$OldCount expected=$ExpectedCount new_before=$NewCountBefore"
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
    if ($OldCountAfter -ne 0 -or $NewCountAfter -ne $ExpectedCount) {
        throw (
            "$Label replacement contract mismatch: " +
            "old_after=$OldCountAfter new_after=$NewCountAfter " +
            "expected=$ExpectedCount"
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
$PatchedSource = Invoke-ExactReplacement `
    -Source $Source `
    -Old '[int[]]@($CurrentCount + 1, $BaselineCount + 1)' `
    -New '[int[]]@(($CurrentCount + 1), ($BaselineCount + 1))' `
    -ExpectedCount 1 `
    -Label 'LCS dimension lengths'
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old '$Table[$CurrentIndex + 1, $BaselineIndex + 1]' `
    -New '$Table[($CurrentIndex + 1), ($BaselineIndex + 1)]' `
    -ExpectedCount 1 `
    -Label 'LCS diagonal index'
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old '$Table[$CurrentIndex + 1, $BaselineIndex]' `
    -New '$Table[($CurrentIndex + 1), $BaselineIndex]' `
    -ExpectedCount 3 `
    -Label 'LCS row-advance index'
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old '$Table[$CurrentIndex, $BaselineIndex + 1]' `
    -New '$Table[$CurrentIndex, ($BaselineIndex + 1)]' `
    -ExpectedCount 3 `
    -Label 'LCS column-advance index'

if ($PatchedSource -ceq $Source) {
    throw 'in-memory LCS correction produced no source change'
}
$PatchedHash = Get-TextSha256 -Text $PatchedSource

$Diagnostic = [scriptblock]::Create($PatchedSource)
$InvokeArguments = @{
    VBoxManagePath = $VBoxManagePath
    ResourceRoot = $ResourceRoot
    InspectorReportPath = $InspectorReportPath
    OutPath = $OutPath
}

Write-Host "ORIGINAL DIAGNOSTIC:  $ExpectedOriginalBlob"
Write-Host 'LCS DIMENSION FIX:    1/1 IN-MEMORY'
Write-Host 'LCS DIAGONAL FIX:     1/1 IN-MEMORY'
Write-Host 'LCS ROW-INDEX FIX:    3/3 IN-MEMORY'
Write-Host 'LCS COLUMN FIX:       3/3 IN-MEMORY'
Write-Host "PATCHED SOURCE SHA:   $PatchedHash"
& $Diagnostic @InvokeArguments
