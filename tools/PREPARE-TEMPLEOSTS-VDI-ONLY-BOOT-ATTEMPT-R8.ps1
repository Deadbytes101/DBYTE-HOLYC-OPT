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

$ExpectedR2Blob = '796f23166f2ddf14f2e981a14fc31cc5732c5c71'
$R2Relative = 'tools/PREPARE-TEMPLEOSTS-VDI-ONLY-BOOT-ATTEMPT-R2.ps1'
$ExpectedProbeReportPath =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vboxmanage-modifyvm-help-surface-probe.txt'
$ExpectedProbeReportHash =
    '57117B1D94D963C8DBDFFED0E3D4FE90CA410B2AF8712ACDCDAA1B70245266E7'
$ExpectedVBoxVersion = '7.0.12r159484'
$ExpectedBootAttemptRoot =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r1'
$ExpectedPreparationReport =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-boot-attempt-preparation.txt'
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

function Get-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath(
        [Environment]::ExpandEnvironmentVariables($Path)
    ).TrimEnd('\', '/')
}

function Assert-PathEquals {
    param(
        [Parameter(Mandatory = $true)][string]$Observed,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not [string]::Equals(
        $Observed,
        $Expected,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "${Label} mismatch: observed=$Observed expected=$Expected"
    }
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

function Get-ReportField {
    param(
        [Parameter(Mandatory = $true)][string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Key
    )

    $Prefix = $Key + "`t"
    $Matches = @($Lines | Where-Object { $_.StartsWith($Prefix, [System.StringComparison]::Ordinal) })
    if ($Matches.Count -ne 1) {
        throw "probe report field cardinality mismatch: key=$Key count=$($Matches.Count)"
    }
    return $Matches[0].Substring($Prefix.Length)
}

function Assert-ReportField {
    param(
        [Parameter(Mandatory = $true)][string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Expected
    )

    $Observed = Get-ReportField -Lines $Lines -Key $Key
    if ($Observed -cne $Expected) {
        throw (
            "probe report field mismatch: key=$Key " +
            "observed=$Observed expected=$Expected"
        )
    }
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

$ProbeReport = (
    Resolve-Path -LiteralPath $ModifyVmHelpProbeReportPath -ErrorAction Stop
).Path
Assert-PathEquals `
    -Observed $ProbeReport `
    -Expected $ExpectedProbeReportPath `
    -Label 'modifyvm help probe report path'
$ObservedProbeHash = (
    Get-FileHash -LiteralPath $ProbeReport -Algorithm SHA256
).Hash
if ($ObservedProbeHash -cne $ExpectedProbeReportHash) {
    throw (
        'modifyvm help probe report SHA256 mismatch: ' +
        "observed=$ObservedProbeHash expected=$ExpectedProbeReportHash"
    )
}
$ProbeLines = [System.IO.File]::ReadAllLines($ProbeReport)

foreach ($Field in @(
    @('vboxmanage_version', $ExpectedVBoxVersion),
    @('version_exit_code', '0'),
    @('boot_attempt_root', $ExpectedBootAttemptRoot),
    @('boot_attempt_root_absent', 'True'),
    @('preparation_report', $ExpectedPreparationReport),
    @('preparation_report_absent', 'True'),
    @('process_vbox_user_home_before', ''),
    @('process_vbox_user_home_after', ''),
    @('virtualbox_registry_query', 'NOT-EXECUTED'),
    @('virtualbox_mutation', 'NOT-EXECUTED'),
    @('vm_start', 'NOT-AUTHORIZED'),
    @('PROBE', 'COMPLETE'),
    @('BOOT ATTEMPT COPY', 'NOT-PREPARED'),
    @('VM START', 'NOT-AUTHORIZED'),
    @('RESTORE BOOT', 'NOT-OBSERVED'),
    @('RECOVERY POINT', 'NOT-SEALED'),
    @('BUILD EXECUTION', 'NOT-AUTHORIZED'),
    @('VERDICT', 'READ-ONLY MODIFYVM HELP SURFACE PROBE COMPLETE')
)) {
    Assert-ReportField -Lines $ProbeLines -Key $Field[0] -Expected $Field[1]
}

$ExpectedAttempts = @(
    @('1', 'modifyvm --help', '2', '0',
        'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855',
        '7057',
        '81512DB8141ECC159671E0D0FC558859D802AB0D9F1E2E9FE6F0C0ACA845A46B'),
    @('2', '--help modifyvm', '1', '70110',
        '221D40C22A784A7AE2BC6F241C4174B75B3745EB9686AE351E3FC479B818A899',
        '0',
        'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855'),
    @('3', 'help modifyvm', '1', '70110',
        '221D40C22A784A7AE2BC6F241C4174B75B3745EB9686AE351E3FC479B818A899',
        '0',
        'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855'),
    @('4', 'modifyvm', '1', '6834',
        'FC8D05B08C87A25ECCA0F8C307EFCB192326610676F4DE4A46C33E7C7501C5AF',
        '0',
        'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855')
)
foreach ($Attempt in $ExpectedAttempts) {
    $Number = $Attempt[0]
    foreach ($Field in @(
        @("attempt_${Number}_arguments", $Attempt[1]),
        @("attempt_${Number}_exit_code", $Attempt[2]),
        @("attempt_${Number}_stdout_utf8_bytes", $Attempt[3]),
        @("attempt_${Number}_stdout_sha256", $Attempt[4]),
        @("attempt_${Number}_stderr_utf8_bytes", $Attempt[5]),
        @("attempt_${Number}_stderr_sha256", $Attempt[6]),
        @("attempt_${Number}_modifyvm_usage_marker", 'True'),
        @("attempt_${Number}_clipboard_mode_marker", 'True'),
        @("attempt_${Number}_clipboard_marker", 'True'),
        @("attempt_${Number}_drag_and_drop_marker", 'True'),
        @("attempt_${Number}_draganddrop_marker", 'False')
    )) {
        Assert-ReportField -Lines $ProbeLines -Key $Field[0] -Expected $Field[1]
    }
}

$Source = [System.IO.File]::ReadAllText($R2Path)
$SourceNewLine = Get-ExactNewLine -Text $Source -Label 'R2 source'

$OldVersionBoundFunction = @'
$NewModifyHelp = @'
function Get-ModifyVmSwitches {
    $Attempts = @(
        @('modifyvm', '--help'),
        @('--help', 'modifyvm')
    )
    $Successful = [System.Collections.Generic.List[string]]::new()
    foreach ($Arguments in $Attempts) {
        $Captured = @(
            & $script:VBox @Arguments 2>&1 |
                ForEach-Object { [string]$_ }
        )
        if ($LASTEXITCODE -eq 0) {
            $Successful.Add(($Captured -join "`n"))
        }
    }
    if ($Successful.Count -le 0) {
        throw 'no successful modifyvm help invocation'
    }
    $Text = $Successful -join "`n"
    $ClipboardSwitch = if ($Text -match '(?m)--clipboard-mode(?:\s|=)') {
        '--clipboard-mode'
    }
    elseif ($Text -match '(?m)--clipboard(?:\s|=)') {
        '--clipboard'
    }
    else {
        throw 'no supported clipboard modifyvm switch found'
    }
    $DragDropSwitch = if ($Text -match '(?m)--drag-and-drop(?:\s|=)') {
        '--drag-and-drop'
    }
    elseif ($Text -match '(?m)--draganddrop(?:\s|=)') {
        '--draganddrop'
    }
    else {
        throw 'no supported drag-and-drop modifyvm switch found'
    }
    return [pscustomobject]@{
        Clipboard = $ClipboardSwitch
        DragDrop = $DragDropSwitch
    }
}
'@
'@
$NewVersionBoundFunction = @'
$NewModifyHelp = @'
function Get-ModifyVmSwitches {
    return [pscustomobject]@{
        Clipboard = '--clipboard-mode'
        DragDrop = '--drag-and-drop'
    }
}
'@
'@
$OldVersionBoundFunction = Convert-ToNewLine `
    -Text $OldVersionBoundFunction `
    -NewLine $SourceNewLine `
    -Label 'dynamic modifyvm help function old seam'
$NewVersionBoundFunction = Convert-ToNewLine `
    -Text $NewVersionBoundFunction `
    -NewLine $SourceNewLine `
    -Label 'fixed report-bound modifyvm function new seam'
$PatchedSource = Invoke-ExactReplacement `
    -Source $Source `
    -Old $OldVersionBoundFunction `
    -New $NewVersionBoundFunction `
    -Label 'report-bound fixed modifyvm switches'

$OldOutputLine = "Write-Host 'MODIFYVM HELP:        TWO READ-ONLY PROBES'"
$NewOutputLine = "Write-Host 'MODIFYVM SWITCHES:    REPORT-BOUND / VERSION-EXACT'"
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldOutputLine `
    -New $NewOutputLine `
    -Label 'R2 fixed-switch output classification'

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
    throw 'R8 corrections produced no R2 source change'
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
Write-Host "BOUND PROBE REPORT:   $ExpectedProbeReportHash"
Write-Host 'EXECUTION PATH:       DIRECT R2 / R3-R7 NOT INVOKED'
Write-Host 'OPTION DISCOVERY:     FIXED REPORT-BOUND CONTRACT'
Write-Host 'CLIPBOARD SWITCH:     --clipboard-mode'
Write-Host 'DRAGDROP SWITCH:      --drag-and-drop'
Write-Host 'NATIVE HELP CALLS:    NONE DURING PREPARATION'
Write-Host 'R2 ROOT CONTRACT:     AST ASSIGNMENT 1 BEFORE / 0 AFTER'
Write-Host "INJECTED REPO ROOT:   $RepoRoot"
Write-Host "PATCHED R2 SHA:       $PatchedHash"
& $R2 @InvokeArguments
