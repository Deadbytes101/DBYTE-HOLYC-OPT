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

function Get-ExactRepoRootAssignmentCount {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Ast = Get-ParsedAst -Text $Text -Label $Label
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
$SourceNewLine = Get-ExactNewLine -Text $Source -Label 'R2 source'

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
$OldAttemptBlock = Convert-ToNewLine `
    -Text $OldAttemptBlock `
    -NewLine $SourceNewLine `
    -Label 'typed help-array old seam'
$NewAttemptBlock = Convert-ToNewLine `
    -Text $NewAttemptBlock `
    -NewLine $SourceNewLine `
    -Label 'typed help-array new seam'
$PatchedSource = Invoke-ExactReplacement `
    -Source $Source `
    -Old $OldAttemptBlock `
    -New $NewAttemptBlock `
    -Label 'typed modifyvm help argument arrays'

$OldHelpExecution = @'
    foreach ($Arguments in $Attempts) {
        $Captured = @(
            & $script:VBox @Arguments 2>&1 |
                ForEach-Object { [string]$_ }
        )
        if ($LASTEXITCODE -eq 0) {
            $Successful.Add(($Captured -join "`n"))
        }
    }
'@
$NewHelpExecution = @'
    foreach ($Arguments in $Attempts) {
        $PreviousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $Captured = @(
                & $script:VBox @Arguments 2>&1 |
                    ForEach-Object { [string]$_ }
            )
            $ExitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $PreviousErrorActionPreference
        }
        if ($ExitCode -eq 0) {
            $Successful.Add(($Captured -join "`n"))
        }
    }
'@
$OldHelpExecution = Convert-ToNewLine `
    -Text $OldHelpExecution `
    -NewLine $SourceNewLine `
    -Label 'native help execution old seam'
$NewHelpExecution = Convert-ToNewLine `
    -Text $NewHelpExecution `
    -NewLine $SourceNewLine `
    -Label 'native help execution new seam'
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldHelpExecution `
    -New $NewHelpExecution `
    -Label 'Windows PowerShell native help stderr handling'

$ExactPSScriptRootBefore = Get-ExactPSScriptRootVariableCount `
    -Text $PatchedSource `
    -Label 'R2 source before repository-root injection'
$ExactRepoRootBefore = Get-ExactRepoRootAssignmentCount `
    -Text $PatchedSource `
    -Label 'R2 source before repository-root injection'
if ($ExactPSScriptRootBefore -ne 1 -or $ExactRepoRootBefore -ne 1) {
    throw (
        'R2 repository-root syntax cardinality mismatch: ' +
        "psscriptroot=$ExactPSScriptRootBefore assignment=$ExactRepoRootBefore"
    )
}

$OldRepoRootAnchor = '$RepoRoot = Split-Path -Parent $PSScriptRoot'
$InjectedRepoRoot = ConvertTo-SingleQuotedLiteral -Value $RepoRoot
$NewRepoRootAnchor = '$RepoRoot = ' + $InjectedRepoRoot
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldRepoRootAnchor `
    -New $NewRepoRootAnchor `
    -Label 'R2 file-backed repository-root injection'

$ExactPSScriptRootAfter = Get-ExactPSScriptRootVariableCount `
    -Text $PatchedSource `
    -Label 'patched R2 dynamic source'
$ExactRepoRootAfter = Get-ExactRepoRootAssignmentCount `
    -Text $PatchedSource `
    -Label 'patched R2 dynamic source'
if ($ExactPSScriptRootAfter -ne 0 -or $ExactRepoRootAfter -ne 0) {
    throw (
        'patched R2 retains executable repository-root dependency: ' +
        "psscriptroot=$ExactPSScriptRootAfter assignment=$ExactRepoRootAfter"
    )
}
if ($PatchedSource -ceq $Source) {
    throw 'R7 corrections produced no R2 source change'
}

[void](Get-ParsedAst -Text $PatchedSource -Label 'final patched R2 source')
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

Write-Host "BOUND R2 PREPARER:    $ExpectedR2Blob"
Write-Host 'EXECUTION PATH:       DIRECT R2 / R3-R6 NOT INVOKED'
Write-Host 'SOURCE NEWLINES:      EXACT SINGLE STYLE / SEAMS NORMALIZED'
Write-Host 'HELP ARGUMENT ARRAYS: LIST[OBJECT] OF STRING[]'
Write-Host 'NATIVE STDERR GUARD:  EAP CONTINUE / FINALLY RESTORE'
Write-Host 'HELP EXIT CODE:       CAPTURED BEFORE POLICY RESTORE'
Write-Host 'R2 ROOT CONTRACT:     AST ASSIGNMENT 1 BEFORE / 0 AFTER'
Write-Host "INJECTED REPO ROOT:   $RepoRoot"
Write-Host "PATCHED R2 SHA:       $PatchedHash"
& $R2 @InvokeArguments
