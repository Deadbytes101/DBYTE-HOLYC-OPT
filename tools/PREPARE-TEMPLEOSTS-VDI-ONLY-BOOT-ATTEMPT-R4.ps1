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

$ExpectedR3Blob = '462a54f375439f60d9aefc37a62b9b3dd41e681e'
$R3Relative = 'tools/PREPARE-TEMPLEOSTS-VDI-ONLY-BOOT-ATTEMPT-R3.ps1'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$R3Path = Join-Path $RepoRoot (
    $R3Relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
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

if (-not (Test-Path -LiteralPath $R3Path -PathType Leaf)) {
    throw "R3 preparer missing: $R3Path"
}

$TreeBlob = @(
    Invoke-GitRead `
        -Arguments @('rev-parse', "HEAD`:$R3Relative") `
        -Label 'R3 preparer tree blob'
)
$LocalBlob = @(
    Invoke-GitRead `
        -Arguments @('hash-object', '--', $R3Relative) `
        -Label 'R3 preparer local blob'
)
if (
    $TreeBlob.Count -ne 1 -or
    $LocalBlob.Count -ne 1 -or
    $TreeBlob[0] -cne $ExpectedR3Blob -or
    $LocalBlob[0] -cne $ExpectedR3Blob
) {
    throw (
        'R3 preparer blob mismatch: ' +
        "tree=$($TreeBlob -join '|') local=$($LocalBlob -join '|')"
    )
}

$Source = [System.IO.File]::ReadAllText($R3Path)

$OldBeforeTokenGuard = @'
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
'@
$NewBeforeTokenGuard = @'
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

$OldRepoRootAnchor = '$RepoRoot = Split-Path -Parent $PSScriptRoot'
$PSScriptRootCountBefore = Get-ExactPSScriptRootVariableCount `
    -Text $PatchedSource `
    -Label 'R2 source before repository-root injection'
$OldRepoRootCountBefore = [regex]::Matches(
    $PatchedSource,
    [regex]::Escape($OldRepoRootAnchor),
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
).Count
if ($PSScriptRootCountBefore -ne 1 -or $OldRepoRootCountBefore -ne 1) {
    throw (
        'R2 repository-root syntax cardinality mismatch: ' +
        "exact_variable=$PSScriptRootCountBefore anchor=$OldRepoRootCountBefore"
    )
}
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $Source `
    -Old $OldBeforeTokenGuard `
    -New $NewBeforeTokenGuard `
    -Label 'R3 exact PSScriptRoot AST precondition'

$OldAfterTokenGuard = @'
$PSScriptRootCountAfter = [regex]::Matches(
    $PatchedSource,
    [regex]::Escape('$PSScriptRoot'),
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
).Count
if ($PSScriptRootCountAfter -ne 0) {
    throw "R2 patched source retains PSScriptRoot references: $PSScriptRootCountAfter"
}
'@
$NewAfterTokenGuard = @'
$PSScriptRootCountAfter = Get-ExactPSScriptRootVariableCount `
    -Text $PatchedSource `
    -Label 'R2 source after repository-root injection'
if ($PSScriptRootCountAfter -ne 0) {
    throw "R2 patched source retains exact PSScriptRoot variable tokens: $PSScriptRootCountAfter"
}
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldAfterTokenGuard `
    -New $NewAfterTokenGuard `
    -Label 'R3 exact PSScriptRoot AST postcondition'

$OldR3RepoRootSeam = @'
$R2Relative = 'tools/PREPARE-TEMPLEOSTS-VDI-ONLY-BOOT-ATTEMPT-R2.ps1'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$R2Path = Join-Path $RepoRoot (
'@
$InjectedRepoRoot = ConvertTo-SingleQuotedLiteral -Value $RepoRoot
$NewR3RepoRootSeam = (
    '$R2Relative = ''tools/PREPARE-TEMPLEOSTS-VDI-ONLY-BOOT-ATTEMPT-R2.ps1''' + "`n" +
    '$RepoRoot = ' + $InjectedRepoRoot + "`n" +
    '$R2Path = Join-Path $RepoRoot (' + "`n"
)
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldR3RepoRootSeam `
    -New $NewR3RepoRootSeam `
    -Label 'R3 file-backed repository-root injection'

$R3ExactPSScriptRootAfter = Get-ExactPSScriptRootVariableCount `
    -Text $PatchedSource `
    -Label 'patched R3 dynamic source'
if ($R3ExactPSScriptRootAfter -ne 0) {
    throw (
        'patched R3 retains exact PSScriptRoot variable tokens: ' +
        $R3ExactPSScriptRootAfter
    )
}
if ($PatchedSource -ceq $Source) {
    throw 'R4 corrections produced no R3 source change'
}

$PatchedHash = Get-TextSha256 -Text $PatchedSource
$R3 = [scriptblock]::Create($PatchedSource)
$InvokeArguments = @{
    VBoxManagePath = $VBoxManagePath
    ResourceRoot = $ResourceRoot
    RehearsalVerificationReportPath = $RehearsalVerificationReportPath
    BootReadinessReportPath = $BootReadinessReportPath
    SealedRehearsalRoot = $SealedRehearsalRoot
    BootAttemptRoot = $BootAttemptRoot
    OutPath = $OutPath
}

Write-Host "ORIGINAL R3 PREPARER: $ExpectedR3Blob"
Write-Host 'TOKEN CLASSIFIER:     POWERSHELL AST / EXACT VARIABLE NAME'
Write-Host 'R2 TOKEN CONTRACT:    EXACT PSSCRIPTROOT 1 BEFORE / 0 AFTER'
Write-Host 'R3 REPO ROOT ANCHOR:  FILE-BACKED R4 / EXACT-ONE-REPLACEMENT'
Write-Host "INJECTED REPO ROOT:   $RepoRoot"
Write-Host "PATCHED R3 SHA:       $PatchedHash"
& $R3 @InvokeArguments
