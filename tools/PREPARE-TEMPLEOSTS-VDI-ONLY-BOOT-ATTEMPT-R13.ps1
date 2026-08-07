[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$VBoxManagePath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ResourceRoot,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RehearsalVerificationReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$BootReadinessReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ModifyVmHelpProbeReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$IncompleteInspectionReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$PreservedIncompleteRoot,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$SealedRehearsalRoot,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$BootAttemptRoot,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedR12Blob = '655b1b84c761af190b52765e17b8916875adc980'
$R12Relative = 'tools/PREPARE-TEMPLEOSTS-VDI-ONLY-BOOT-ATTEMPT-R12.ps1'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$R12Path = Join-Path $RepoRoot (
    $R12Relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
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

function Get-ParsedAst {
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
    return $Ast
}

function Get-ExactNewLine {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $CrLfCount = [regex]::Matches($Text, "`r`n").Count
    $BareLfCount = [regex]::Matches($Text, "(?<!`r)`n").Count
    if (
        ($CrLfCount -gt 0 -and $BareLfCount -gt 0) -or
        ($CrLfCount -eq 0 -and $BareLfCount -eq 0)
    ) {
        throw (
            "${Label} newline style is mixed or absent: " +
            "crlf=$CrLfCount bare_lf=$BareLfCount"
        )
    }
    if ($CrLfCount -gt 0) {
        return "`r`n"
    }
    return "`n"
}

function Convert-ToNewLine {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$NewLine,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Normalized = $Text.Replace("`r`n", "`n")
    if ($Normalized.Contains("`r")) {
        throw "${Label} contains unsupported standalone carriage return"
    }
    if ($NewLine -ceq "`n") {
        return $Normalized
    }
    if ($NewLine -ceq "`r`n") {
        return $Normalized.Replace("`n", "`r`n")
    }
    throw "${Label} requested unsupported newline representation"
}

function ConvertTo-SingleQuotedLiteral {
    param([Parameter(Mandatory = $true)][string]$Value)

    return "'" + $Value.Replace("'", "''") + "'"
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

if (-not (Test-Path -LiteralPath $R12Path -PathType Leaf)) {
    throw "R12 preparer missing: $R12Path"
}

$TreeBlob = @(
    Invoke-GitRead `
        -Arguments @('rev-parse', "HEAD`:$R12Relative") `
        -Label 'R12 preparer tree blob'
)
$LocalBlob = @(
    Invoke-GitRead `
        -Arguments @('hash-object', '--', $R12Relative) `
        -Label 'R12 preparer local blob'
)
if (
    $TreeBlob.Count -ne 1 -or
    $LocalBlob.Count -ne 1 -or
    $TreeBlob[0] -cne $ExpectedR12Blob -or
    $LocalBlob[0] -cne $ExpectedR12Blob
) {
    throw (
        'R12 preparer blob mismatch: ' +
        "tree=$($TreeBlob -join '|') local=$($LocalBlob -join '|')"
    )
}

$Source = [System.IO.File]::ReadAllText($R12Path)
$NewLine = Get-ExactNewLine -Text $Source -Label 'R12 source'
$InitialAst = Get-ParsedAst -Text $Source -Label 'bound R12 source'

$HelperFunctions = @(
    $InitialAst.FindAll(
        {
            param($Node)
            $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $Node.Name -ceq 'Invoke-ExactReplacement'
        },
        $true
    )
)
if ($HelperFunctions.Count -ne 1) {
    throw "R12 replacement-helper function count mismatch: $($HelperFunctions.Count)"
}

$Helper = $HelperFunctions[0]
$HelperStart = [int]$Helper.Extent.StartOffset
$HelperEnd = [int]$Helper.Extent.EndOffset
if (
    $HelperStart -lt 0 -or
    $HelperEnd -le $HelperStart -or
    $HelperEnd -gt $Source.Length
) {
    throw (
        'R12 replacement-helper AST extent invalid: ' +
        "start=$HelperStart end=$HelperEnd length=$($Source.Length)"
    )
}
$ObservedHelper = $Source.Substring($HelperStart, $HelperEnd - $HelperStart)
if (-not $ObservedHelper.StartsWith(
    'function Invoke-ExactReplacement {',
    [System.StringComparison]::Ordinal
)) {
    throw 'R12 replacement-helper AST extent text mismatch'
}

$CorrectedHelper = @'
function Invoke-ExactReplacement {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Old,
        [Parameter(Mandatory = $true)][string]$New,
        [Parameter(Mandatory = $true)][int]$ExpectedOldCount,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ($Old.Length -eq 0) {
        throw "${Label} old replacement text is empty"
    }

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
    if ($OldCount -ne $ExpectedOldCount -or $NewCountBefore -ne 0) {
        throw (
            "${Label} source cardinality mismatch: " +
            "old=$OldCount expected_old=$ExpectedOldCount " +
            "new_before=$NewCountBefore"
        )
    }

    $OldOccurrencesPerNew = [regex]::Matches(
        $New,
        [regex]::Escape($Old),
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    ).Count
    $ExpectedOldAfter = $ExpectedOldCount * $OldOccurrencesPerNew

    $Patched = $Source.Replace($Old, $New)
    $OldAfter = [regex]::Matches(
        $Patched,
        [regex]::Escape($Old),
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    ).Count
    $NewAfter = [regex]::Matches(
        $Patched,
        [regex]::Escape($New),
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    ).Count
    if (
        $OldAfter -ne $ExpectedOldAfter -or
        $NewAfter -ne $ExpectedOldCount
    ) {
        throw (
            "${Label} replacement mismatch: " +
            "old_after=$OldAfter expected_old_after=$ExpectedOldAfter " +
            "new_after=$NewAfter expected_new_after=$ExpectedOldCount"
        )
    }
    return $Patched
}
'@
$CorrectedHelper = Convert-ToNewLine `
    -Text $CorrectedHelper `
    -NewLine $NewLine `
    -Label 'corrected replacement helper'

$Patched = (
    $Source.Substring(0, $HelperStart) +
    $CorrectedHelper +
    $Source.Substring($HelperEnd)
)

$AfterHelperAst = Get-ParsedAst -Text $Patched -Label 'R12 after helper correction'
$RepoAssignments = @(
    $AfterHelperAst.FindAll(
        {
            param($Node)
            $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $Node.Extent.Text -ceq '$RepoRoot = Split-Path -Parent $PSScriptRoot'
        },
        $true
    )
)
$PSScriptRootBefore = @(
    $AfterHelperAst.FindAll(
        {
            param($Node)
            $Node -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $Node.VariablePath.UserPath -ceq 'PSScriptRoot'
        },
        $true
    )
).Count
if ($RepoAssignments.Count -ne 1 -or $PSScriptRootBefore -ne 1) {
    throw (
        'R12 repository-root AST mismatch: ' +
        "assignments=$($RepoAssignments.Count) psscriptroot=$PSScriptRootBefore"
    )
}

$RepoAssignment = $RepoAssignments[0]
$RepoStart = [int]$RepoAssignment.Extent.StartOffset
$RepoEnd = [int]$RepoAssignment.Extent.EndOffset
if (
    $RepoStart -lt 0 -or
    $RepoEnd -le $RepoStart -or
    $RepoEnd -gt $Patched.Length
) {
    throw (
        'R12 repository-root AST extent invalid: ' +
        "start=$RepoStart end=$RepoEnd length=$($Patched.Length)"
    )
}
if (
    $Patched.Substring($RepoStart, $RepoEnd - $RepoStart) -cne
    '$RepoRoot = Split-Path -Parent $PSScriptRoot'
) {
    throw 'R12 repository-root AST extent text mismatch'
}

$Patched = (
    $Patched.Substring(0, $RepoStart) +
    '$RepoRoot = ' +
    (ConvertTo-SingleQuotedLiteral -Value $RepoRoot) +
    $Patched.Substring($RepoEnd)
)

$FinalAst = Get-ParsedAst -Text $Patched -Label 'final corrected R12'
$PSScriptRootAfter = @(
    $FinalAst.FindAll(
        {
            param($Node)
            $Node -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $Node.VariablePath.UserPath -ceq 'PSScriptRoot'
        },
        $true
    )
).Count
if ($PSScriptRootAfter -ne 0) {
    throw "final corrected R12 retains executable PSScriptRoot: $PSScriptRootAfter"
}

$PatchedHash = Get-TextSha256 -Text $Patched
$R12 = [scriptblock]::Create($Patched)
$InvokeArguments = @{
    VBoxManagePath = $VBoxManagePath
    ResourceRoot = $ResourceRoot
    RehearsalVerificationReportPath = $RehearsalVerificationReportPath
    BootReadinessReportPath = $BootReadinessReportPath
    ModifyVmHelpProbeReportPath = $ModifyVmHelpProbeReportPath
    IncompleteInspectionReportPath = $IncompleteInspectionReportPath
    PreservedIncompleteRoot = $PreservedIncompleteRoot
    SealedRehearsalRoot = $SealedRehearsalRoot
    BootAttemptRoot = $BootAttemptRoot
    OutPath = $OutPath
}

Write-Host "BOUND R12 PREPARER:   $ExpectedR12Blob"
Write-Host 'CORRECTION:           SELF-CONTAINING EXACT-REPLACEMENT INVARIANT'
Write-Host 'HELPER CLASSIFIER:    POWERSHELL AST / EXACT FUNCTION NAME'
Write-Host 'HELPER REPLACEMENT:   AST STARTOFFSET/ENDOFFSET SPLICE'
Write-Host 'OLD-AFTER CONTRACT:   EXPECTED COUNT * OLD OCCURRENCES INSIDE NEW'
Write-Host 'R12 ROOT CLASSIFIER:  POWERSHELL AST / EXACT ASSIGNMENT STATEMENT'
Write-Host 'R12 ROOT REPLACEMENT: AST STARTOFFSET/ENDOFFSET SPLICE'
Write-Host "INJECTED REPO ROOT:   $RepoRoot"
Write-Host "PATCHED R12 SHA:      $PatchedHash"
& $R12 @InvokeArguments
