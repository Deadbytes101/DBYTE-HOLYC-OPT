[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$VBoxManagePath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ResourceRoot,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RehearsalVerificationReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$BootReadinessReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ModifyVmHelpProbeReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$R2InspectionReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$R2AdjudicationReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$PreservedR1Root,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$PreservedR2Root,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$SealedRehearsalRoot,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$BootAttemptRoot,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedR2Blob = '796f23166f2ddf14f2e981a14fc31cc5732c5c71'
$ExpectedOldModifyBlob = '7464fbe67b9456cc7eb679255c98b3ecbc6cdecc'
$ExpectedNewModifyBlob = '36b5df298e4d657d54c1603e98104a8fe8f0ce0e'
$ExpectedPolicyBlob = '41c05f339f378e325a115860000193fbbbf86e29'

$ExpectedHelpProbeHash = '57117B1D94D963C8DBDFFED0E3D4FE90CA410B2AF8712ACDCDAA1B70245266E7'
$ExpectedR2InspectionHash = '9C2F6A2C2838CF00412F37BA2753DBB1718605FBE165B6D9D2A9FFBFC5E2D42A'
$ExpectedR2AdjudicationHash = '7580785C1CCDD4471344F8B7BD9E361F0CC6D6B36DF9A798756C1C2A84EA26B5'

$ExpectedR1Root = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r1'
$ExpectedR2Root = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r2'
$ExpectedR3Root = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r3'
$ExpectedOut = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-boot-attempt-preparation.txt'
$ExpectedHelpProbePath = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vboxmanage-modifyvm-help-surface-probe.txt'
$ExpectedR2InspectionPath = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r2-incomplete-inspection.txt'
$ExpectedR2AdjudicationPath = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r2-incomplete-adjudication.txt'

$ExpectedR1VBoxHash = '69224A832694CA0C657CA2135ED370F6B7E667B84F93C08D921AED4A6D21F39B'
$ExpectedR1VBoxFileId = '0X0000000000000000000100000006034F'
$ExpectedR1VdiFileId = '0X00000000000000000001000000060350'
$ExpectedR1IsoFileId = '0X00000000000000000001000000060351'

$ExpectedR2VBoxHash = '8EADB39D54CABE5E7B791E5D7E05BCF4CBBF32D4AB6B58291BEC0B2FAD607C0C'
$ExpectedR2VBoxFileId = '0X00000000000000000005000000060670'
$ExpectedR2PrevHash = 'C93D128227EE80B647DB63FE64277CEF1BDC61C224110472C73CBFFEC63877A7'
$ExpectedR2PrevFileId = '0X00000000000000000004000000060676'
$ExpectedR2VdiFileId = '0X00000000000000000001000000060671'
$ExpectedR2IsoFileId = '0X00000000000000000001000000060672'
$ExpectedVdiHash = '90D453A94F075760A11E0772862E60C4B031ED874F28AA396EAE638F7EB8B31B'
$ExpectedIsoHash = 'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'

$R2Relative = 'tools/PREPARE-TEMPLEOSTS-VDI-ONLY-BOOT-ATTEMPT-R2.ps1'
$OldModifyRelative = 'tools/r12/R2-OLD-MODIFYVM-BLOCK.txt'
$NewModifyRelative = 'tools/r12/R2-NEW-MODIFYVM-BLOCK.txt'
$PolicyRelative = 'tools/r14/R2-GENERATION-POLICY-INJECTION.ps1.txt'
$RepoRoot = Split-Path -Parent $PSScriptRoot

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
    $Captured = @(
        & git -C $RepoRoot @Arguments 2>&1 |
            ForEach-Object { [string]$_ }
    )
    if ($LASTEXITCODE -ne 0) {
        throw "${Label} failed`n$($Captured -join "`n")"
    }
    return $Captured
}

function Assert-BoundRepoFile {
    param(
        [Parameter(Mandatory = $true)][string]$Relative,
        [Parameter(Mandatory = $true)][string]$ExpectedBlob,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $Path = Join-Path $RepoRoot (
        $Relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    )
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

function Assert-HashFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$SHA256,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $Resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $Hash = (Get-FileHash -LiteralPath $Resolved -Algorithm SHA256).Hash
    if ($Hash -cne $SHA256) {
        throw "${Label} SHA256 mismatch: observed=$Hash expected=$SHA256"
    }
    return $Resolved
}

function Get-FileId {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $Captured = @(
        & fsutil file queryfileid $Path 2>&1 |
            ForEach-Object { [string]$_ }
    )
    if ($LASTEXITCODE -ne 0) {
        throw "${Label} file-ID query failed`n$($Captured -join "`n")"
    }
    $Ids = @(
        foreach ($Line in $Captured) {
            foreach ($Match in [regex]::Matches($Line, '0x[0-9A-Fa-f]+')) {
                $Match.Value.ToUpperInvariant()
            }
        }
    )
    if ($Ids.Count -ne 1) {
        throw "${Label} file-ID parse mismatch: count=$($Ids.Count)"
    }
    return $Ids[0]
}

function Assert-FileState {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$SHA256,
        [Parameter(Mandatory = $true)][string]$FileId,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $Resolved = Assert-HashFile -Path $Path -SHA256 $SHA256 -Label $Label
    $ObservedId = Get-FileId -Path $Resolved -Label $Label
    if ($ObservedId -cne $FileId) {
        throw "${Label} file-ID mismatch: observed=$ObservedId expected=$FileId"
    }
    return $Resolved
}

function Get-ParsedAst {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $Tokens = $null
    $Errors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseInput(
        $Text, [ref]$Tokens, [ref]$Errors
    )
    if (@($Errors).Count -ne 0) {
        throw "${Label} PowerShell parse failed: $((@($Errors) | ForEach-Object { $_.Message }) -join ' | ')"
    }
    return $Ast
}

function Get-ExactNewLine {
    param([Parameter(Mandatory = $true)][string]$Text)
    $CrLf = [regex]::Matches($Text, "`r`n").Count
    $BareLf = [regex]::Matches($Text, "(?<!`r)`n").Count
    if (($CrLf -gt 0 -and $BareLf -gt 0) -or ($CrLf -eq 0 -and $BareLf -eq 0)) {
        throw "source newline style is mixed or absent: crlf=$CrLf bare_lf=$BareLf"
    }
    if ($CrLf -gt 0) { return "`r`n" }
    return "`n"
}

function Convert-ToNewLine {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$NewLine
    )
    $Normalized = $Text.Replace("`r`n", "`n")
    if ($Normalized.Contains("`r")) {
        throw 'fragment contains standalone carriage return'
    }
    if ($NewLine -ceq "`n") { return $Normalized }
    if ($NewLine -ceq "`r`n") { return $Normalized.Replace("`n", "`r`n") }
    throw 'unsupported newline style'
}

function Invoke-ExactReplacement {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Old,
        [Parameter(Mandatory = $true)][string]$New,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if ($Old.Length -eq 0) { throw "${Label} old text is empty" }
    $OldCount = [regex]::Matches($Source, [regex]::Escape($Old), [System.Text.RegularExpressions.RegexOptions]::CultureInvariant).Count
    $NewBefore = [regex]::Matches($Source, [regex]::Escape($New), [System.Text.RegularExpressions.RegexOptions]::CultureInvariant).Count
    if ($OldCount -ne 1 -or $NewBefore -ne 0) {
        throw "${Label} source cardinality mismatch: old=$OldCount new_before=$NewBefore"
    }
    $OldPerNew = [regex]::Matches($New, [regex]::Escape($Old), [System.Text.RegularExpressions.RegexOptions]::CultureInvariant).Count
    $Patched = $Source.Replace($Old, $New)
    $OldAfter = [regex]::Matches($Patched, [regex]::Escape($Old), [System.Text.RegularExpressions.RegexOptions]::CultureInvariant).Count
    $NewAfter = [regex]::Matches($Patched, [regex]::Escape($New), [System.Text.RegularExpressions.RegexOptions]::CultureInvariant).Count
    if ($OldAfter -ne $OldPerNew -or $NewAfter -ne 1) {
        throw "${Label} replacement mismatch: old_after=$OldAfter expected_old_after=$OldPerNew new_after=$NewAfter"
    }
    return $Patched
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
        return ([System.BitConverter]::ToString($Sha.ComputeHash($Bytes))).Replace('-', '')
    }
    finally { $Sha.Dispose() }
}

$R1 = Get-FullPath -Path $PreservedR1Root
$R2Root = Get-FullPath -Path $PreservedR2Root
$R3 = Get-FullPath -Path $BootAttemptRoot
$Output = Get-FullPath -Path $OutPath
Assert-PathEquals -Observed $R1 -Expected $ExpectedR1Root -Label 'preserved r1 root'
Assert-PathEquals -Observed $R2Root -Expected $ExpectedR2Root -Label 'preserved r2 root'
Assert-PathEquals -Observed $R3 -Expected $ExpectedR3Root -Label 'new r3 root'
Assert-PathEquals -Observed $Output -Expected $ExpectedOut -Label 'preparation report'
if (-not (Test-Path -LiteralPath $R1 -PathType Container)) { throw "preserved r1 root missing: $R1" }
if (-not (Test-Path -LiteralPath $R2Root -PathType Container)) { throw "preserved r2 root missing: $R2Root" }
if (Test-Path -LiteralPath $R3) { throw "r3 boot-attempt root already exists: $R3" }
if (Test-Path -LiteralPath $Output) { throw "preparation report already exists: $Output" }

$HelpReport = Assert-HashFile -Path $ModifyVmHelpProbeReportPath -SHA256 $ExpectedHelpProbeHash -Label 'modifyvm help report'
$R2Inspection = Assert-HashFile -Path $R2InspectionReportPath -SHA256 $ExpectedR2InspectionHash -Label 'r2 inspection report'
$R2Adjudication = Assert-HashFile -Path $R2AdjudicationReportPath -SHA256 $ExpectedR2AdjudicationHash -Label 'r2 adjudication report'
Assert-PathEquals -Observed $HelpReport -Expected $ExpectedHelpProbePath -Label 'modifyvm help report path'
Assert-PathEquals -Observed $R2Inspection -Expected $ExpectedR2InspectionPath -Label 'r2 inspection report path'
Assert-PathEquals -Observed $R2Adjudication -Expected $ExpectedR2AdjudicationPath -Label 'r2 adjudication report path'

$R1Machine = Join-Path $R1 'Machine'
[void](Assert-FileState -Path (Join-Path $R1Machine 'Temple1.10.vbox') -SHA256 $ExpectedR1VBoxHash -FileId $ExpectedR1VBoxFileId -Label 'preserved r1 VBOX')
if ((Get-FileId -Path (Join-Path $R1Machine 'Temple1.10.vdi') -Label 'preserved r1 VDI') -cne $ExpectedR1VdiFileId) { throw 'preserved r1 VDI file-ID changed' }
if ((Get-FileId -Path (Join-Path $R1Machine 'TempleOSTS.iso') -Label 'preserved r1 ISO') -cne $ExpectedR1IsoFileId) { throw 'preserved r1 ISO file-ID changed' }

$R2Machine = Join-Path $R2Root 'Machine'
[void](Assert-FileState -Path (Join-Path $R2Machine 'Temple1.10.vbox') -SHA256 $ExpectedR2VBoxHash -FileId $ExpectedR2VBoxFileId -Label 'preserved r2 current VBOX')
[void](Assert-FileState -Path (Join-Path $R2Machine 'Temple1.10.vbox-prev') -SHA256 $ExpectedR2PrevHash -FileId $ExpectedR2PrevFileId -Label 'preserved r2 previous VBOX')
[void](Assert-FileState -Path (Join-Path $R2Machine 'Temple1.10.vdi') -SHA256 $ExpectedVdiHash -FileId $ExpectedR2VdiFileId -Label 'preserved r2 VDI')
[void](Assert-FileState -Path (Join-Path $R2Machine 'TempleOSTS.iso') -SHA256 $ExpectedIsoHash -FileId $ExpectedR2IsoFileId -Label 'preserved r2 ISO')

$R2Path = Assert-BoundRepoFile -Relative $R2Relative -ExpectedBlob $ExpectedR2Blob -Label 'R2 preparer'
$OldModifyPath = Assert-BoundRepoFile -Relative $OldModifyRelative -ExpectedBlob $ExpectedOldModifyBlob -Label 'old modifyvm fragment'
$NewModifyPath = Assert-BoundRepoFile -Relative $NewModifyRelative -ExpectedBlob $ExpectedNewModifyBlob -Label 'fixed modifyvm fragment'
$PolicyPath = Assert-BoundRepoFile -Relative $PolicyRelative -ExpectedBlob $ExpectedPolicyBlob -Label 'R14 policy fragment'

$Source = [System.IO.File]::ReadAllText($R2Path)
$NewLine = Get-ExactNewLine -Text $Source
$OldModify = Convert-ToNewLine -Text ([System.IO.File]::ReadAllText($OldModifyPath)) -NewLine $NewLine
$NewModify = Convert-ToNewLine -Text ([System.IO.File]::ReadAllText($NewModifyPath)) -NewLine $NewLine
$Policy = Convert-ToNewLine -Text ([System.IO.File]::ReadAllText($PolicyPath)) -NewLine $NewLine

$Patched = Invoke-ExactReplacement -Source $Source -Old $OldModify -New $NewModify -Label 'fixed report-bound modifyvm switches'
$Anchor = @'
if ($PatchedSource -ceq $Source) {
    throw 'in-memory boot-attempt preparer hardening produced no source change'
}
'@
$Anchor = Convert-ToNewLine -Text $Anchor -NewLine $NewLine
$Injected = $Policy.TrimEnd("`r", "`n") + $NewLine + $NewLine + $Anchor
$Patched = Invoke-ExactReplacement -Source $Patched -Old $Anchor -New $Injected -Label 'R14 original-source generation policy injection'

$Ast = Get-ParsedAst -Text $Patched -Label 'R14 patched R2 before root injection'
$Assignments = @(
    $Ast.FindAll(
        {
            param($Node)
            $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $Node.Extent.Text -ceq '$RepoRoot = Split-Path -Parent $PSScriptRoot'
        },
        $true
    )
)
$RootRefs = @(
    $Ast.FindAll(
        {
            param($Node)
            $Node -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $Node.VariablePath.UserPath -ceq 'PSScriptRoot'
        },
        $true
    )
).Count
if ($Assignments.Count -ne 1 -or $RootRefs -ne 1) {
    throw "R2 repository-root AST mismatch: assignments=$($Assignments.Count) psscriptroot=$RootRefs"
}
$Assignment = $Assignments[0]
$Start = [int]$Assignment.Extent.StartOffset
$End = [int]$Assignment.Extent.EndOffset
if ($Start -lt 0 -or $End -le $Start -or $End -gt $Patched.Length) {
    throw "R2 repository-root extent invalid: start=$Start end=$End length=$($Patched.Length)"
}
if ($Patched.Substring($Start, $End - $Start) -cne '$RepoRoot = Split-Path -Parent $PSScriptRoot') {
    throw 'R2 repository-root extent text mismatch'
}
$Patched = $Patched.Substring(0, $Start) + '$RepoRoot = ' + (ConvertTo-SingleQuotedLiteral -Value $RepoRoot) + $Patched.Substring($End)

$FinalAst = Get-ParsedAst -Text $Patched -Label 'final R14 dynamic R2'
$FinalRootRefs = @(
    $FinalAst.FindAll(
        {
            param($Node)
            $Node -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $Node.VariablePath.UserPath -ceq 'PSScriptRoot'
        },
        $true
    )
).Count
if ($FinalRootRefs -ne 0) {
    throw "final R14 dynamic R2 retains executable PSScriptRoot: $FinalRootRefs"
}

$PatchedHash = Get-TextSha256 -Text $Patched
$DynamicR2 = [scriptblock]::Create($Patched)
$InvokeArguments = @{
    VBoxManagePath = $VBoxManagePath
    ResourceRoot = $ResourceRoot
    RehearsalVerificationReportPath = $RehearsalVerificationReportPath
    BootReadinessReportPath = $BootReadinessReportPath
    SealedRehearsalRoot = $SealedRehearsalRoot
    BootAttemptRoot = $BootAttemptRoot
    OutPath = $OutPath
}

Write-Host "BOUND R2 PREPARER:     $ExpectedR2Blob"
Write-Host "BOUND HELP REPORT:     $ExpectedHelpProbeHash"
Write-Host "BOUND R2 INSPECTION:   $ExpectedR2InspectionHash"
Write-Host "BOUND R2 ADJUDICATION: $ExpectedR2AdjudicationHash"
Write-Host 'EXECUTION PATH:        DIRECT R2 / R12-R13 NOT INVOKED'
Write-Host 'R1 STATUS:             PRESERVED / IDENTITY RECHECKED'
Write-Host 'R2 STATUS:             PRESERVED / IDENTITY RECHECKED'
Write-Host "NEW BOOT ROOT:         $R3"
Write-Host 'MEDIA POLICY:          RELATIVE BASENAMES / NO PRE-REGISTRATION XML WRITE'
Write-Host 'VBOX IDENTITY POLICY:  GENERATION-AWARE / PRE+POST IDS RECORDED'
Write-Host 'VBOX COMPANION:        .vbox-prev REQUIRED / HASH NOT HARDCODED'
Write-Host 'VDI/ISO FILE IDS:      MUST REMAIN STABLE THROUGH CORRECTION'
Write-Host 'CLIPBOARD SWITCH:      --clipboard-mode'
Write-Host 'DRAGDROP SWITCH:       --drag-and-drop'
Write-Host 'NATIVE HELP CALLS:     NONE DURING PREPARATION'
Write-Host 'R2 ROOT CONTRACT:      AST ASSIGNMENT 1 BEFORE / PSSCRIPTROOT 0 AFTER'
Write-Host "INJECTED REPO ROOT:    $RepoRoot"
Write-Host "PATCHED R2 SHA:        $PatchedHash"
& $DynamicR2 @InvokeArguments
