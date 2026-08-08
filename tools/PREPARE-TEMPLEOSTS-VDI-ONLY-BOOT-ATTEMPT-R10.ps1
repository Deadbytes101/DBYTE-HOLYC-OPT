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
    [string]$ModifyVmHelpProbeReportPath,

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

$ExpectedR8Blob = '8e051b4cff813de4160311c45833174180f11bd9'
$R8Relative = 'tools/PREPARE-TEMPLEOSTS-VDI-ONLY-BOOT-ATTEMPT-R8.ps1'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$R8Path = Join-Path $RepoRoot (
    $R8Relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
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

function Invoke-ExactReplacement {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Old,
        [Parameter(Mandatory = $true)][string]$New,
        [Parameter(Mandatory = $true)][int]$ExpectedOldCount,
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
    if ($OldCount -ne $ExpectedOldCount -or $NewCountBefore -ne 0) {
        throw (
            "${Label} source cardinality mismatch: " +
            "old=$OldCount expected_old=$ExpectedOldCount " +
            "new_before=$NewCountBefore"
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
    if ($OldCountAfter -ne 0 -or $NewCountAfter -ne $ExpectedOldCount) {
        throw (
            "${Label} replacement mismatch: " +
            "old_after=$OldCountAfter new_after=$NewCountAfter " +
            "expected_new_after=$ExpectedOldCount"
        )
    }
    return $Patched
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

function Get-ExactPSScriptRootVariableCount {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Ast = Get-ParsedAst -Text $Text -Label $Label
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

if (-not (Test-Path -LiteralPath $R8Path -PathType Leaf)) {
    throw "R8 preparer missing: $R8Path"
}

$TreeBlob = @(
    Invoke-GitRead `
        -Arguments @('rev-parse', "HEAD`:$R8Relative") `
        -Label 'R8 preparer tree blob'
)
$LocalBlob = @(
    Invoke-GitRead `
        -Arguments @('hash-object', '--', $R8Relative) `
        -Label 'R8 preparer local blob'
)
if (
    $TreeBlob.Count -ne 1 -or
    $LocalBlob.Count -ne 1 -or
    $TreeBlob[0] -cne $ExpectedR8Blob -or
    $LocalBlob[0] -cne $ExpectedR8Blob
) {
    throw (
        'R8 preparer blob mismatch: ' +
        "tree=$($TreeBlob -join '|') local=$($LocalBlob -join '|')"
    )
}

$Source = [System.IO.File]::ReadAllText($R8Path)

$OldLinesParameter =
    '[Parameter(Mandatory = $true)][string[]]$Lines,'
$NewLinesParameter =
    '[Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Lines,'
$PatchedSource = Invoke-ExactReplacement `
    -Source $Source `
    -Old $OldLinesParameter `
    -New $NewLinesParameter `
    -ExpectedOldCount 3 `
    -Label 'blank report-row collection binding'

$AstBefore = Get-ParsedAst `
    -Text $PatchedSource `
    -Label 'R8 source before AST-offset repository-root injection'
$RepoAssignments = @(
    $AstBefore.FindAll(
        {
            param($Node)
            $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $Node.Extent.Text -ceq '$RepoRoot = Split-Path -Parent $PSScriptRoot'
        },
        $true
    )
)
if ($RepoAssignments.Count -ne 1) {
    throw (
        'R8 executable repository-root assignment cardinality mismatch: ' +
        $RepoAssignments.Count
    )
}

$PSScriptRootBefore = @(
    $AstBefore.FindAll(
        {
            param($Node)
            $Node -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $Node.VariablePath.UserPath -ceq 'PSScriptRoot'
        },
        $true
    )
).Count
if ($PSScriptRootBefore -ne 1) {
    throw (
        'R8 executable PSScriptRoot variable cardinality mismatch before injection: ' +
        $PSScriptRootBefore
    )
}

$RepoAssignment = $RepoAssignments[0]
$StartOffset = [int]$RepoAssignment.Extent.StartOffset
$EndOffset = [int]$RepoAssignment.Extent.EndOffset
if (
    $StartOffset -lt 0 -or
    $EndOffset -le $StartOffset -or
    $EndOffset -gt $PatchedSource.Length
) {
    throw (
        'R8 repository-root AST extent is invalid: ' +
        "start=$StartOffset end=$EndOffset length=$($PatchedSource.Length)"
    )
}
$ObservedExtent = $PatchedSource.Substring(
    $StartOffset,
    $EndOffset - $StartOffset
)
if ($ObservedExtent -cne '$RepoRoot = Split-Path -Parent $PSScriptRoot') {
    throw "R8 repository-root AST extent text mismatch: $ObservedExtent"
}

$InjectedRepoRoot = ConvertTo-SingleQuotedLiteral -Value $RepoRoot
$NewAssignment = '$RepoRoot = ' + $InjectedRepoRoot
$PatchedSource = (
    $PatchedSource.Substring(0, $StartOffset) +
    $NewAssignment +
    $PatchedSource.Substring($EndOffset)
)

$AstAfter = Get-ParsedAst `
    -Text $PatchedSource `
    -Label 'final patched R8 source'
$PSScriptRootAfter = @(
    $AstAfter.FindAll(
        {
            param($Node)
            $Node -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $Node.VariablePath.UserPath -ceq 'PSScriptRoot'
        },
        $true
    )
).Count
$OldAssignmentAfter = @(
    $AstAfter.FindAll(
        {
            param($Node)
            $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $Node.Extent.Text -ceq '$RepoRoot = Split-Path -Parent $PSScriptRoot'
        },
        $true
    )
).Count
if ($PSScriptRootAfter -ne 0 -or $OldAssignmentAfter -ne 0) {
    throw (
        'patched R8 retains executable repository-root dependency: ' +
        "psscriptroot=$PSScriptRootAfter assignment=$OldAssignmentAfter"
    )
}
if ($PatchedSource -ceq $Source) {
    throw 'R10 corrections produced no R8 source change'
}

$PatchedHash = Get-TextSha256 -Text $PatchedSource
$R8 = [scriptblock]::Create($PatchedSource)
$InvokeArguments = @{
    VBoxManagePath = $VBoxManagePath
    ResourceRoot = $ResourceRoot
    RehearsalVerificationReportPath = $RehearsalVerificationReportPath
    BootReadinessReportPath = $BootReadinessReportPath
    ModifyVmHelpProbeReportPath = $ModifyVmHelpProbeReportPath
    SealedRehearsalRoot = $SealedRehearsalRoot
    BootAttemptRoot = $BootAttemptRoot
    OutPath = $OutPath
}

Write-Host "BOUND R8 PREPARER:    $ExpectedR8Blob"
Write-Host 'REPORT ROW BINDING:   ALLOW EMPTY STRING / EXACT THREE PARAMETERS'
Write-Host 'ROOT CLASSIFIER:      POWERSHELL AST / EXACT ASSIGNMENT STATEMENT'
Write-Host 'ROOT REPLACEMENT:     AST STARTOFFSET/ENDOFFSET SPLICE'
Write-Host 'LAYOUT DEPENDENCY:    NONE BEYOND ASSIGNMENT EXTENT'
Write-Host "INJECTED REPO ROOT:   $RepoRoot"
Write-Host "PATCHED R8 SHA:       $PatchedHash"
& $R8 @InvokeArguments
