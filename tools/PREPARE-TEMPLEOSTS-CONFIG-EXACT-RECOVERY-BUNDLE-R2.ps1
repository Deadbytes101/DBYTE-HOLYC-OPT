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
    [string]$RecoveryRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedOriginalBlob = '33957db6d124f20025be638eb41d74e7e4190bcc'
$OriginalRelative =
    'tools/PREPARE-TEMPLEOSTS-CONFIG-EXACT-RECOVERY-BUNDLE.ps1'
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
    throw "original preparer missing: $OriginalPath"
}

$TreeBlob = @(
    Invoke-GitRead `
        -Arguments @('rev-parse', "HEAD`:$OriginalRelative") `
        -Label 'original preparer tree blob'
)
$LocalBlob = @(
    Invoke-GitRead `
        -Arguments @('hash-object', '--', $OriginalRelative) `
        -Label 'original preparer local blob'
)
if (
    $TreeBlob.Count -ne 1 -or
    $LocalBlob.Count -ne 1 -or
    $TreeBlob[0] -cne $ExpectedOriginalBlob -or
    $LocalBlob[0] -cne $ExpectedOriginalBlob
) {
    throw (
        "original preparer blob mismatch: " +
        "tree=$($TreeBlob -join '|') local=$($LocalBlob -join '|')"
    )
}

$Source = [System.IO.File]::ReadAllText($OriginalPath)

$OldRootBlock = @'
foreach ($ForbiddenRoot in @($script:Resource, $LiveVmRoot)) {
    Assert-OutsideRoot `
        -Path $FinalRoot `
        -Root $ForbiddenRoot `
        -Label 'recovery root'
    Assert-OutsideRoot `
        -Path $Output `
        -Root $ForbiddenRoot `
        -Label 'preparation report'
}
Assert-OutsideRoot `
    -Path $Output `
    -Root $FinalRoot `
    -Label 'preparation report'
'@
$NewRootBlock = @'
foreach ($ForbiddenRoot in @($script:Resource, $LiveVmRoot)) {
    Assert-OutsideRoot `
        -Path $FinalRoot `
        -Root $ForbiddenRoot `
        -Label 'recovery root'
    Assert-OutsideRoot `
        -Path $Output `
        -Root $ForbiddenRoot `
        -Label 'preparation report'
}
foreach ($ProtectedRoot in @($script:Resource, $LiveVmRoot)) {
    Assert-OutsideRoot `
        -Path $ProtectedRoot `
        -Root $FinalRoot `
        -Label 'protected root'
}
Assert-OutsideRoot `
    -Path $Output `
    -Root $FinalRoot `
    -Label 'preparation report'
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $Source `
    -Old $OldRootBlock `
    -New $NewRootBlock `
    -Label 'bidirectional root-disjoint guard'

$OldFinalBlock = @'
    [void](Assert-LiveTarget `
        -Registered $RegisteredFinal `
        -Running $RunningFinal `
        -Show $ShowFinal)
    [void](Assert-ExactHashFile `
        -Path $ExpectedLiveVBoxPath `
        -SHA256 $ExpectedLiveVBoxHash `
        -Label 'final live VBOX')
'@
$NewFinalBlock = @'
    [void](Assert-LiveTarget `
        -Registered $RegisteredFinal `
        -Running $RunningFinal `
        -Show $ShowFinal)
    $SnapshotsFinal = @(
        Invoke-VBoxReadOnly `
            -Arguments @('snapshot', $ExpectedTargetUuid, 'list', '--machinereadable') `
            -Label 'final target snapshot inventory'
    )
    $SnapshotRowsFinal = @(
        $SnapshotsFinal | Where-Object {
            $_ -match '^Snapshot(Name|UUID|Node)'
        }
    )
    if ($SnapshotRowsFinal.Count -ne 0) {
        throw "final target snapshot rows are not zero: $($SnapshotRowsFinal.Count)"
    }
    [void](Assert-ExactHashFile `
        -Path $ExpectedLiveVBoxPath `
        -SHA256 $ExpectedLiveVBoxHash `
        -Label 'final live VBOX')
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldFinalBlock `
    -New $NewFinalBlock `
    -Label 'final zero-snapshot revalidation'

if ($PatchedSource -ceq $Source) {
    throw 'in-memory preparer hardening produced no source change'
}
$PatchedHash = Get-TextSha256 -Text $PatchedSource
$Preparer = [scriptblock]::Create($PatchedSource)
$InvokeArguments = @{
    VBoxManagePath = $VBoxManagePath
    ResourceRoot = $ResourceRoot
    DiffReportPath = $DiffReportPath
    RecoveryRoot = $RecoveryRoot
    OutPath = $OutPath
}

Write-Host "ORIGINAL PREPARER:    $ExpectedOriginalBlob"
Write-Host 'ROOT DISJOINT GUARD:  IN-MEMORY / EXACT-ONE-REPLACEMENT'
Write-Host 'FINAL SNAPSHOT GUARD: IN-MEMORY / EXACT-ONE-REPLACEMENT'
Write-Host "PATCHED SOURCE SHA:   $PatchedHash"
& $Preparer @InvokeArguments
