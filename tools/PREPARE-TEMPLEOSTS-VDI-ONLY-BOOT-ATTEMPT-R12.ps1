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

$ExpectedR2Blob = '796f23166f2ddf14f2e981a14fc31cc5732c5c71'
$R2Relative = 'tools/PREPARE-TEMPLEOSTS-VDI-ONLY-BOOT-ATTEMPT-R2.ps1'
$OldModifyRelative = 'tools/r12/R2-OLD-MODIFYVM-BLOCK.txt'
$NewModifyRelative = 'tools/r12/R2-NEW-MODIFYVM-BLOCK.txt'
$PolicyRelative = 'tools/r12/R2-POLICY-INJECTION.ps1.txt'
$ExpectedOldModifyBlob = '7464fbe67b9456cc7eb679255c98b3ecbc6cdecc'
$ExpectedNewModifyBlob = '36b5df298e4d657d54c1603e98104a8fe8f0ce0e'
$ExpectedPolicyBlob = '528175dabdcefa025bbf719f02b7f8c9bb2dd8f2'
$ExpectedProbeReportPath = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vboxmanage-modifyvm-help-surface-probe.txt'
$ExpectedProbeReportHash = '57117B1D94D963C8DBDFFED0E3D4FE90CA410B2AF8712ACDCDAA1B70245266E7'
$ExpectedInspectionReportPath = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r1-incomplete-inspection.txt'
$ExpectedInspectionReportHash = '3D48BD2FCE6BA9363E086270D52C76A1AC326947A565F48F917C818435F70912'
$ExpectedPreservedRoot = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r1'
$ExpectedBootRoot = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r2'
$ExpectedPreparationReport = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-boot-attempt-preparation.txt'
$ExpectedVBoxVersion = '7.0.12r159484'
$ExpectedPreservedVBoxHash = '69224A832694CA0C657CA2135ED370F6B7E667B84F93C08D921AED4A6D21F39B'
$ExpectedPreservedVBoxFileId = '0X0000000000000000000100000006034F'
$ExpectedPreservedVdiFileId = '0X00000000000000000001000000060350'
$ExpectedPreservedIsoFileId = '0X00000000000000000001000000060351'

$RepoRoot = Split-Path -Parent $PSScriptRoot

function Get-RepoPath {
    param([Parameter(Mandatory = $true)][string]$Relative)
    return Join-Path $RepoRoot ($Relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
}

function Get-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path)).TrimEnd('\', '/')
}

function Assert-PathEquals {
    param(
        [Parameter(Mandatory = $true)][string]$Observed,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not [string]::Equals(
        (Get-FullPath -Path $Observed),
        (Get-FullPath -Path $Expected),
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "${Label} mismatch: observed=$Observed expected=$Expected"
    }
}

function Invoke-GitRead {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $Captured = @(& git -C $RepoRoot @Arguments 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0) {
        throw "${Label} failed`n$($Captured -join "`n")"
    }
    return $Captured
}

function Assert-RepoBlob {
    param(
        [Parameter(Mandatory = $true)][string]$Relative,
        [Parameter(Mandatory = $true)][string]$ExpectedBlob,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $Path = Get-RepoPath -Relative $Relative
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "${Label} missing: $Path"
    }
    $Tree = @(Invoke-GitRead -Arguments @('rev-parse', "HEAD`:$Relative") -Label "${Label} tree blob")
    $Local = @(Invoke-GitRead -Arguments @('hash-object', '--', $Relative) -Label "${Label} local blob")
    if (
        $Tree.Count -ne 1 -or
        $Local.Count -ne 1 -or
        $Tree[0] -cne $ExpectedBlob -or
        $Local[0] -cne $ExpectedBlob
    ) {
        throw "${Label} blob mismatch: tree=$($Tree -join '|') local=$($Local -join '|')"
    }
    return $Path
}

function Get-FileId {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $Captured = @(& fsutil file queryfileid $Path 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0) {
        throw "${Label} file-id query failed`n$($Captured -join "`n")"
    }
    $Ids = @(
        foreach ($Line in $Captured) {
            foreach ($Match in [regex]::Matches($Line, '0x[0-9A-Fa-f]+')) {
                $Match.Value.ToUpperInvariant()
            }
        }
    )
    if ($Ids.Count -ne 1) {
        throw "${Label} file-id parse mismatch: count=$($Ids.Count)"
    }
    return $Ids[0]
}

function Get-ParsedAst {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $Tokens = $null
    $Errors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$Tokens, [ref]$Errors)
    $ParseErrors = @($Errors)
    if ($ParseErrors.Count -ne 0) {
        throw "${Label} PowerShell parse failed: $((@($ParseErrors | ForEach-Object { $_.Message })) -join ' | ')"
    }
    return $Ast
}

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Text)
    $Bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Text)
    $Sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($Sha.ComputeHash($Bytes))).Replace('-', '')
    }
    finally {
        $Sha.Dispose()
    }
}

function Get-ExactNewLine {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $CrLf = [regex]::Matches($Text, "`r`n").Count
    $Lf = [regex]::Matches($Text, "(?<!`r)`n").Count
    if (($CrLf -gt 0 -and $Lf -gt 0) -or ($CrLf -eq 0 -and $Lf -eq 0)) {
        throw "${Label} newline style is mixed or absent: crlf=$CrLf bare_lf=$Lf"
    }
    if ($CrLf -gt 0) { return "`r`n" }
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
        throw "${Label} contains standalone carriage return"
    }
    if ($NewLine -ceq "`n") { return $Normalized }
    if ($NewLine -ceq "`r`n") { return $Normalized.Replace("`n", "`r`n") }
    throw "${Label} unsupported newline"
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
    $OldCount = [regex]::Matches($Source, [regex]::Escape($Old), [System.Text.RegularExpressions.RegexOptions]::CultureInvariant).Count
    $NewCountBefore = [regex]::Matches($Source, [regex]::Escape($New), [System.Text.RegularExpressions.RegexOptions]::CultureInvariant).Count
    if ($OldCount -ne $ExpectedOldCount -or $NewCountBefore -ne 0) {
        throw "${Label} source cardinality mismatch: old=$OldCount expected_old=$ExpectedOldCount new_before=$NewCountBefore"
    }
    $Patched = $Source.Replace($Old, $New)
    $OldAfter = [regex]::Matches($Patched, [regex]::Escape($Old), [System.Text.RegularExpressions.RegexOptions]::CultureInvariant).Count
    $NewAfter = [regex]::Matches($Patched, [regex]::Escape($New), [System.Text.RegularExpressions.RegexOptions]::CultureInvariant).Count
    if ($OldAfter -ne 0 -or $NewAfter -ne $ExpectedOldCount) {
        throw "${Label} replacement mismatch: old_after=$OldAfter new_after=$NewAfter"
    }
    return $Patched
}

function Get-MixedField {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Key
    )
    $Real = $Key + "`t"
    $Literal = $Key + '`t'
    $Found = [System.Collections.Generic.List[object]]::new()
    foreach ($Line in $Lines) {
        if ($Line.StartsWith($Real, [System.StringComparison]::Ordinal)) {
            $Found.Add([pscustomobject]@{ Line = $Line; Prefix = $Real.Length })
        }
        if ($Line.StartsWith($Literal, [System.StringComparison]::Ordinal)) {
            $Found.Add([pscustomobject]@{ Line = $Line; Prefix = $Literal.Length })
        }
    }
    if ($Found.Count -ne 1) {
        throw "mixed report field cardinality mismatch: key=$Key count=$($Found.Count)"
    }
    return $Found[0].Line.Substring([int]$Found[0].Prefix)
}

function Get-TabField {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Key
    )
    $Prefix = $Key + "`t"
    $Found = @($Lines | Where-Object { $_.StartsWith($Prefix, [System.StringComparison]::Ordinal) })
    if ($Found.Count -ne 1) {
        throw "tab report field cardinality mismatch: key=$Key count=$($Found.Count)"
    }
    return $Found[0].Substring($Prefix.Length)
}

function Assert-Value {
    param(
        [Parameter(Mandatory = $true)][string]$Observed,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if ($Observed -cne $Expected) {
        throw "${Label} mismatch: observed=$Observed expected=$Expected"
    }
}

$R2Path = Assert-RepoBlob -Relative $R2Relative -ExpectedBlob $ExpectedR2Blob -Label 'R2 preparer'
$OldModifyPath = Assert-RepoBlob -Relative $OldModifyRelative -ExpectedBlob $ExpectedOldModifyBlob -Label 'old modifyvm seam'
$NewModifyPath = Assert-RepoBlob -Relative $NewModifyRelative -ExpectedBlob $ExpectedNewModifyBlob -Label 'new modifyvm seam'
$PolicyPath = Assert-RepoBlob -Relative $PolicyRelative -ExpectedBlob $ExpectedPolicyBlob -Label 'relative-media policy payload'

$ResolvedVBox = (Resolve-Path -LiteralPath $VBoxManagePath -ErrorAction Stop).Path
$ProbeReport = (Resolve-Path -LiteralPath $ModifyVmHelpProbeReportPath -ErrorAction Stop).Path
$InspectionReport = (Resolve-Path -LiteralPath $IncompleteInspectionReportPath -ErrorAction Stop).Path
$R1 = Get-FullPath -Path $PreservedIncompleteRoot
$R2Root = Get-FullPath -Path $BootAttemptRoot
$Output = Get-FullPath -Path $OutPath

Assert-PathEquals -Observed $ProbeReport -Expected $ExpectedProbeReportPath -Label 'probe report path'
Assert-PathEquals -Observed $InspectionReport -Expected $ExpectedInspectionReportPath -Label 'inspection report path'
Assert-PathEquals -Observed $R1 -Expected $ExpectedPreservedRoot -Label 'preserved r1 root'
Assert-PathEquals -Observed $R2Root -Expected $ExpectedBootRoot -Label 'new r2 root'
Assert-PathEquals -Observed $Output -Expected $ExpectedPreparationReport -Label 'preparation report path'

if ((Get-FileHash -LiteralPath $ProbeReport -Algorithm SHA256).Hash -cne $ExpectedProbeReportHash) {
    throw 'modifyvm probe report SHA256 mismatch'
}
if ((Get-FileHash -LiteralPath $InspectionReport -Algorithm SHA256).Hash -cne $ExpectedInspectionReportHash) {
    throw 'incomplete inspection report SHA256 mismatch'
}
if (-not (Test-Path -LiteralPath $R1 -PathType Container)) {
    throw "preserved r1 root missing: $R1"
}
if (Test-Path -LiteralPath $R2Root) {
    throw "new r2 root already exists: $R2Root"
}
if (Test-Path -LiteralPath $Output) {
    throw "preparation report already exists: $Output"
}
if (-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable('VBOX_USER_HOME', [EnvironmentVariableTarget]::Process))) {
    throw 'process VBOX_USER_HOME must be unset'
}

$R1Machine = Join-Path $R1 'Machine'
$R1VBox = Join-Path $R1Machine 'Temple1.10.vbox'
$R1Vdi = Join-Path $R1Machine 'Temple1.10.vdi'
$R1Iso = Join-Path $R1Machine 'TempleOSTS.iso'
if ((Get-FileHash -LiteralPath $R1VBox -Algorithm SHA256).Hash -cne $ExpectedPreservedVBoxHash) {
    throw 'preserved r1 VBOX identity changed'
}
Assert-Value -Observed (Get-FileId -Path $R1VBox -Label 'r1 VBOX') -Expected $ExpectedPreservedVBoxFileId -Label 'r1 VBOX file ID'
Assert-Value -Observed (Get-FileId -Path $R1Vdi -Label 'r1 VDI') -Expected $ExpectedPreservedVdiFileId -Label 'r1 VDI file ID'
Assert-Value -Observed (Get-FileId -Path $R1Iso -Label 'r1 ISO') -Expected $ExpectedPreservedIsoFileId -Label 'r1 ISO file ID'

$ProbeLines = [System.IO.File]::ReadAllLines($ProbeReport)
Assert-Value -Observed (Get-MixedField -Lines $ProbeLines -Key 'vboxmanage_path') -Expected $ResolvedVBox -Label 'probe VBoxManage path'
Assert-Value -Observed (Get-MixedField -Lines $ProbeLines -Key 'vboxmanage_version') -Expected $ExpectedVBoxVersion -Label 'probe VBoxManage version'
for ($N = 1; $N -le 4; $N++) {
    Assert-Value -Observed (Get-MixedField -Lines $ProbeLines -Key "attempt_${N}_modifyvm_usage_marker") -Expected 'True' -Label "attempt $N usage"
    Assert-Value -Observed (Get-MixedField -Lines $ProbeLines -Key "attempt_${N}_clipboard_mode_marker") -Expected 'True' -Label "attempt $N clipboard-mode"
    Assert-Value -Observed (Get-MixedField -Lines $ProbeLines -Key "attempt_${N}_drag_and_drop_marker") -Expected 'True' -Label "attempt $N drag-and-drop"
    Assert-Value -Observed (Get-MixedField -Lines $ProbeLines -Key "attempt_${N}_draganddrop_marker") -Expected 'False' -Label "attempt $N compact dragdrop"
}

$InspectionLines = [System.IO.File]::ReadAllLines($InspectionReport)
$InspectionExpectations = [ordered]@{
    incomplete_root = $ExpectedPreservedRoot
    preparation_report_absent = 'True'
    vbox_sha256 = $ExpectedPreservedVBoxHash
    vbox_file_id = $ExpectedPreservedVBoxFileId
    vdi_file_id = $ExpectedPreservedVdiFileId
    iso_file_id = $ExpectedPreservedIsoFileId
    target_vdi_location = 'Temple1.10.vdi'
    target_iso_location = 'TempleOSTS.iso'
    sealed_vdi_absolute_occurrences = '0'
    copied_vdi_absolute_occurrences = '0'
    vdi_basename_occurrences = '1'
    sealed_iso_absolute_occurrences = '0'
    copied_iso_absolute_occurrences = '0'
    iso_basename_occurrences = '1'
    vbox_user_home_file_count = '0'
    vbox_user_home_directory_count = '0'
    vboxmanage_invocation = 'NOT-EXECUTED'
    virtualbox_mutation = 'NOT-EXECUTED'
    INSPECTION = 'COMPLETE'
    'INCOMPLETE ROOT' = 'PRESERVED'
}
foreach ($Key in $InspectionExpectations.Keys) {
    Assert-Value -Observed (Get-TabField -Lines $InspectionLines -Key $Key) -Expected ([string]$InspectionExpectations[$Key]) -Label "inspection $Key"
}

$Source = [System.IO.File]::ReadAllText($R2Path)
$NewLine = Get-ExactNewLine -Text $Source -Label 'R2 source'
$OldModify = Convert-ToNewLine -Text ([System.IO.File]::ReadAllText($OldModifyPath)) -NewLine $NewLine -Label 'old modifyvm fragment'
$NewModify = Convert-ToNewLine -Text ([System.IO.File]::ReadAllText($NewModifyPath)) -NewLine $NewLine -Label 'new modifyvm fragment'
$Policy = Convert-ToNewLine -Text ([System.IO.File]::ReadAllText($PolicyPath)) -NewLine $NewLine -Label 'policy payload'

$Patched = Invoke-ExactReplacement -Source $Source -Old $OldModify -New $NewModify -ExpectedOldCount 1 -Label 'fixed modifyvm switch contract'
$Patched = Invoke-ExactReplacement `
    -Source $Patched `
    -Old "Write-Host 'MODIFYVM HELP:        TWO READ-ONLY PROBES'" `
    -New "Write-Host 'MODIFYVM SWITCHES:    REPORT-BOUND / VERSION-EXACT'" `
    -ExpectedOldCount 1 `
    -Label 'fixed-switch output classification'

$Anchor = 'if ($PatchedSource -ceq $Source) {'
$PolicyWithAnchor = $Policy.TrimEnd("`r", "`n") + $NewLine + $NewLine + $Anchor
$Patched = Invoke-ExactReplacement -Source $Patched -Old $Anchor -New $PolicyWithAnchor -ExpectedOldCount 1 -Label 'R12 original-source policy injection'

$AstBefore = Get-ParsedAst -Text $Patched -Label 'R2 before repository-root injection'
$Assignments = @(
    $AstBefore.FindAll(
        {
            param($Node)
            $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $Node.Extent.Text -ceq '$RepoRoot = Split-Path -Parent $PSScriptRoot'
        },
        $true
    )
)
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
if ($Assignments.Count -ne 1 -or $PSScriptRootBefore -ne 1) {
    throw "R2 repository-root AST mismatch: assignments=$($Assignments.Count) psscriptroot=$PSScriptRootBefore"
}
$Assignment = $Assignments[0]
$Start = [int]$Assignment.Extent.StartOffset
$End = [int]$Assignment.Extent.EndOffset
if ($Start -lt 0 -or $End -le $Start -or $End -gt $Patched.Length) {
    throw "R2 repository-root AST extent invalid: start=$Start end=$End length=$($Patched.Length)"
}
if ($Patched.Substring($Start, $End - $Start) -cne '$RepoRoot = Split-Path -Parent $PSScriptRoot') {
    throw 'R2 repository-root AST extent text mismatch'
}
$Patched = $Patched.Substring(0, $Start) + '$RepoRoot = ' + (ConvertTo-SingleQuotedLiteral -Value $RepoRoot) + $Patched.Substring($End)
$AstAfter = Get-ParsedAst -Text $Patched -Label 'final patched R2'
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
if ($PSScriptRootAfter -ne 0) {
    throw "final R2 retains executable PSScriptRoot: $PSScriptRootAfter"
}

$PatchedHash = Get-TextSha256 -Text $Patched
$R2 = [scriptblock]::Create($Patched)
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
Write-Host "BOUND INSPECTION:     $ExpectedInspectionReportHash"
Write-Host 'EXECUTION PATH:       DIRECT R2 / R8-R11 NOT INVOKED'
Write-Host 'R1 STATUS:            PRESERVED / IDENTITY RECHECKED'
Write-Host "NEW BOOT ROOT:        $ExpectedBootRoot"
Write-Host 'MEDIA POLICY:         RELATIVE BASENAMES / NO PRE-REGISTRATION XML WRITE'
Write-Host 'TARGET VDI LOCATION:  Temple1.10.vdi'
Write-Host 'TARGET ISO LOCATION:  TempleOSTS.iso'
Write-Host 'CLIPBOARD SWITCH:     --clipboard-mode'
Write-Host 'DRAGDROP SWITCH:      --drag-and-drop'
Write-Host 'NATIVE HELP CALLS:    NONE DURING PREPARATION'
Write-Host 'R2 ROOT CONTRACT:     AST ASSIGNMENT 1 BEFORE / PSSCRIPTROOT 0 AFTER'
Write-Host "INJECTED REPO ROOT:   $RepoRoot"
Write-Host "PATCHED R2 SHA:       $PatchedHash"
& $R2 @InvokeArguments
