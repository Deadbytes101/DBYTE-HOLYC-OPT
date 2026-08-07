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

$ExpectedR5Blob = '8ffc92184d5ba46c387fc3d7f6ef9e2e09709259'
$R5Relative = 'tools/PREPARE-TEMPLEOSTS-VDI-ONLY-BOOT-ATTEMPT-R5.ps1'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$R5Path = Join-Path $RepoRoot (
    $R5Relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
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
    $OldOccurrencesPerNew = [regex]::Matches(
        $New,
        [regex]::Escape($Old),
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    ).Count
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
    if (
        $OldCountAfter -ne $OldOccurrencesPerNew -or
        $NewCountAfter -ne 1
    ) {
        throw (
            "${Label} replacement mismatch: " +
            "old_after=$OldCountAfter " +
            "expected_old_after=$OldOccurrencesPerNew " +
            "new_after=$NewCountAfter"
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

function Get-ExactPSScriptRootVariableCount {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Tokens = $null
    $Errors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseInput(
        $Text,
        [ref]$Tokens,
        [ref]$Errors
    )
    $ParseErrors = @($Errors)
    if ($ParseErrors.Count -ne 0) {
        throw (
            "${Label} PowerShell parse failed: " +
            (($ParseErrors | ForEach-Object { $_.Message }) -join ' | ')
        )
    }

    $Matches = @(
        $Ast.FindAll(
            {
                param($Node)
                $Node -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $Node.VariablePath.UserPath -ceq 'PSScriptRoot'
            },
            $true
        )
    )
    return $Matches.Count
}

if (-not (Test-Path -LiteralPath $R5Path -PathType Leaf)) {
    throw "R5 preparer missing: $R5Path"
}

$TreeBlob = @(
    Invoke-GitRead `
        -Arguments @('rev-parse', "HEAD`:$R5Relative") `
        -Label 'R5 preparer tree blob'
)
$LocalBlob = @(
    Invoke-GitRead `
        -Arguments @('hash-object', '--', $R5Relative) `
        -Label 'R5 preparer local blob'
)
if (
    $TreeBlob.Count -ne 1 -or
    $LocalBlob.Count -ne 1 -or
    $TreeBlob[0] -cne $ExpectedR5Blob -or
    $LocalBlob[0] -cne $ExpectedR5Blob
) {
    throw (
        'R5 preparer blob mismatch: ' +
        "tree=$($TreeBlob -join '|') local=$($LocalBlob -join '|')"
    )
}

$Source = [System.IO.File]::ReadAllText($R5Path)

$OldHelperInsertion = @'
    return $Matches.Count
}

if (-not (Test-Path -LiteralPath $R4Path -PathType Leaf)) {
'@
$NewHelperInsertion = @'
    return $Matches.Count
}

function Get-ExactRepoRootAssignmentCount {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Tokens = $null
    $Errors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseInput(
        $Text,
        [ref]$Tokens,
        [ref]$Errors
    )
    $ParseErrors = @($Errors)
    if ($ParseErrors.Count -ne 0) {
        throw (
            "${Label} PowerShell parse failed: " +
            (($ParseErrors | ForEach-Object { $_.Message }) -join ' | ')
        )
    }

    $Matches = @(
        $Ast.FindAll(
            {
                param($Node)
                $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $Node.Extent.Text -ceq '$RepoRoot = Split-Path -Parent $PSScriptRoot'
            },
            $true
        )
    )
    return $Matches.Count
}

if (-not (Test-Path -LiteralPath $R4Path -PathType Leaf)) {
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $Source `
    -Old $OldHelperInsertion `
    -New $NewHelperInsertion `
    -Label 'R5 executable repository-root assignment classifier'

$OldR4AnchorCount = @'
$R4RepoRootCountBefore = [regex]::Matches(
    $PatchedSource,
    [regex]::Escape('$RepoRoot = Split-Path -Parent $PSScriptRoot'),
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
).Count
'@
$NewR4AnchorCount = @'
$R4RepoRootCountBefore = Get-ExactRepoRootAssignmentCount `
    -Text $PatchedSource `
    -Label 'R4 source before repository-root injection'
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldR4AnchorCount `
    -New $NewR4AnchorCount `
    -Label 'R5 R4 repository-root AST assignment count'

$OldR5RepoRootSeam = @'
$R4Relative = 'tools/PREPARE-TEMPLEOSTS-VDI-ONLY-BOOT-ATTEMPT-R4.ps1'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$R4Path = Join-Path $RepoRoot (
'@
$R5ExactPSScriptRootBefore = Get-ExactPSScriptRootVariableCount `
    -Text $PatchedSource `
    -Label 'R5 source before repository-root injection'
if ($R5ExactPSScriptRootBefore -ne 1) {
    throw (
        'R5 repository-root variable cardinality mismatch: ' +
        "exact_variable=$R5ExactPSScriptRootBefore"
    )
}

$InjectedRepoRoot = ConvertTo-SingleQuotedLiteral -Value $RepoRoot
$NewR5RepoRootSeam = (
    '$R4Relative = ''tools/PREPARE-TEMPLEOSTS-VDI-ONLY-BOOT-ATTEMPT-R4.ps1''' + "`n" +
    '$RepoRoot = ' + $InjectedRepoRoot + "`n" +
    '$R4Path = Join-Path $RepoRoot (' + "`n"
)
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldR5RepoRootSeam `
    -New $NewR5RepoRootSeam `
    -Label 'R5 file-backed repository-root injection'

$R5ExactPSScriptRootAfter = Get-ExactPSScriptRootVariableCount `
    -Text $PatchedSource `
    -Label 'patched R5 dynamic source'
if ($R5ExactPSScriptRootAfter -ne 0) {
    throw (
        'patched R5 retains exact PSScriptRoot variable tokens: ' +
        $R5ExactPSScriptRootAfter
    )
}
if ($PatchedSource -ceq $Source) {
    throw 'R6 corrections produced no R5 source change'
}

$PatchedHash = Get-TextSha256 -Text $PatchedSource
$R5 = [scriptblock]::Create($PatchedSource)
$InvokeArguments = @{
    VBoxManagePath = $VBoxManagePath
    ResourceRoot = $ResourceRoot
    RehearsalVerificationReportPath = $RehearsalVerificationReportPath
    BootReadinessReportPath = $BootReadinessReportPath
    SealedRehearsalRoot = $SealedRehearsalRoot
    BootAttemptRoot = $BootAttemptRoot
    OutPath = $OutPath
}

Write-Host "ORIGINAL R5 PREPARER: $ExpectedR5Blob"
Write-Host 'ANCHOR CLASSIFIER:    POWERSHELL AST / EXACT ASSIGNMENT STATEMENT'
Write-Host 'R4 ANCHOR CONTRACT:   EXECUTABLE REPO ROOT ASSIGNMENT EXACTLY ONE'
Write-Host 'R5 REPO ROOT ANCHOR:  FILE-BACKED R6 / EXACT-ONE-REPLACEMENT'
Write-Host "INJECTED REPO ROOT:   $RepoRoot"
Write-Host "PATCHED R5 SHA:       $PatchedHash"
& $R5 @InvokeArguments
