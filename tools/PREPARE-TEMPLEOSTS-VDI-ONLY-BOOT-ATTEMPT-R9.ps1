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
$SourceNewLine = Get-ExactNewLine -Text $Source -Label 'R8 source'

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

$ExactPSScriptRootBefore = Get-ExactPSScriptRootVariableCount `
    -Text $PatchedSource `
    -Label 'R8 source before repository-root injection'
if ($ExactPSScriptRootBefore -ne 1) {
    throw (
        'R8 repository-root variable cardinality mismatch before injection: ' +
        $ExactPSScriptRootBefore
    )
}

$OldRepoRootSeam = @'
$R2Relative = 'tools/PREPARE-TEMPLEOSTS-VDI-ONLY-BOOT-ATTEMPT-R2.ps1'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$R2Path = Join-Path $RepoRoot (
'@
$OldRepoRootSeam = Convert-ToNewLine `
    -Text $OldRepoRootSeam `
    -NewLine $SourceNewLine `
    -Label 'R8 repository-root old seam'
$InjectedRepoRoot = ConvertTo-SingleQuotedLiteral -Value $RepoRoot
$NewRepoRootSeam = (
    '$R2Relative = ''tools/PREPARE-TEMPLEOSTS-VDI-ONLY-BOOT-ATTEMPT-R2.ps1''' +
    $SourceNewLine +
    '$RepoRoot = ' + $InjectedRepoRoot +
    $SourceNewLine +
    '$R2Path = Join-Path $RepoRoot (' +
    $SourceNewLine
)
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldRepoRootSeam `
    -New $NewRepoRootSeam `
    -ExpectedOldCount 1 `
    -Label 'R8 file-backed repository-root injection'

$ExactPSScriptRootAfter = Get-ExactPSScriptRootVariableCount `
    -Text $PatchedSource `
    -Label 'patched R8 dynamic source'
if ($ExactPSScriptRootAfter -ne 0) {
    throw (
        'patched R8 retains exact PSScriptRoot variable tokens: ' +
        $ExactPSScriptRootAfter
    )
}
if ($PatchedSource -ceq $Source) {
    throw 'R9 corrections produced no R8 source change'
}

[void](Get-ParsedAst -Text $PatchedSource -Label 'final patched R8 source')
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
Write-Host 'FIELD CONTRACT:       UNCHANGED / EXACT KEY CARDINALITY'
Write-Host 'R8 REPO ROOT ANCHOR:  FILE-BACKED R9 / EXACT-ONE-REPLACEMENT'
Write-Host "INJECTED REPO ROOT:   $RepoRoot"
Write-Host "PATCHED R8 SHA:       $PatchedHash"
& $R8 @InvokeArguments
