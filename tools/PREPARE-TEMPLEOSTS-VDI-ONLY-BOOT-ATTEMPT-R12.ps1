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
    [string]$IncompleteInspectionReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PreservedIncompleteRoot,

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
$ExpectedInspectionReportPath =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r1-incomplete-inspection.txt'
$ExpectedInspectionReportHash =
    '3D48BD2FCE6BA9363E086270D52C76A1AC326947A565F48F917C818435F70912'
$ExpectedPreservedRoot =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r1'
$ExpectedBootRoot =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r2'
$ExpectedPreparationReport =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-boot-attempt-preparation.txt'
$ExpectedVBoxVersion = '7.0.12r159484'
$ExpectedPreservedVBoxHash =
    '69224A832694CA0C657CA2135ED370F6B7E667B84F93C08D921AED4A6D21F39B'
$ExpectedPreservedVBoxFileId = '0X0000000000000000000100000006034F'
$ExpectedPreservedVdiFileId = '0X00000000000000000001000000060350'
$ExpectedPreservedIsoFileId = '0X00000000000000000001000000060351'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$R2Path = Join-Path $RepoRoot (
    $R2Relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
)

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

function Get-MixedReportField {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Key
    )

    $RealTabPrefix = $Key + "`t"
    $LiteralPrefix = $Key + '`t'
    $Matches = [System.Collections.Generic.List[object]]::new()
    foreach ($Line in $Lines) {
        if ($Line.StartsWith($RealTabPrefix, [System.StringComparison]::Ordinal)) {
            $Matches.Add([pscustomobject]@{
                Line = $Line
                PrefixLength = $RealTabPrefix.Length
            })
        }
        if ($Line.StartsWith($LiteralPrefix, [System.StringComparison]::Ordinal)) {
            $Matches.Add([pscustomobject]@{
                Line = $Line
                PrefixLength = $LiteralPrefix.Length
            })
        }
    }
    if ($Matches.Count -ne 1) {
        throw "report field combined cardinality mismatch: key=$Key count=$($Matches.Count)"
    }
    return $Matches[0].Line.Substring([int]$Matches[0].PrefixLength)
}

function Get-TabReportField {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Key
    )

    $Prefix = $Key + "`t"
    $Matches = @(
        $Lines | Where-Object {
            $_.StartsWith($Prefix, [System.StringComparison]::Ordinal)
        }
    )
    if ($Matches.Count -ne 1) {
        throw "tab report field cardinality mismatch: key=$Key count=$($Matches.Count)"
    }
    return $Matches[0].Substring($Prefix.Length)
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

$ResolvedVBox = (Resolve-Path -LiteralPath $VBoxManagePath -ErrorAction Stop).Path
$ProbeReport = (
    Resolve-Path -LiteralPath $ModifyVmHelpProbeReportPath -ErrorAction Stop
).Path
$InspectionReport = (
    Resolve-Path -LiteralPath $IncompleteInspectionReportPath -ErrorAction Stop
).Path
$PreservedRoot = Get-FullPath -Path $PreservedIncompleteRoot
$NewBootRoot = Get-FullPath -Path $BootAttemptRoot
$PreparationReport = Get-FullPath -Path $OutPath

Assert-PathEquals -Observed $ProbeReport -Expected $ExpectedProbeReportPath -Label 'probe report path'
Assert-PathEquals -Observed $InspectionReport -Expected $ExpectedInspectionReportPath -Label 'inspection report path'
Assert-PathEquals -Observed $PreservedRoot -Expected $ExpectedPreservedRoot -Label 'preserved r1 root'
Assert-PathEquals -Observed $NewBootRoot -Expected $ExpectedBootRoot -Label 'new r2 boot root'
Assert-PathEquals -Observed $PreparationReport -Expected $ExpectedPreparationReport -Label 'preparation report path'

$ProbeHash = (Get-FileHash -LiteralPath $ProbeReport -Algorithm SHA256).Hash
$InspectionHash = (Get-FileHash -LiteralPath $InspectionReport -Algorithm SHA256).Hash
if ($ProbeHash -cne $ExpectedProbeReportHash) {
    throw "probe report SHA256 mismatch: observed=$ProbeHash expected=$ExpectedProbeReportHash"
}
if ($InspectionHash -cne $ExpectedInspectionReportHash) {
    throw "inspection report SHA256 mismatch: observed=$InspectionHash expected=$ExpectedInspectionReportHash"
}

if (-not (Test-Path -LiteralPath $PreservedRoot -PathType Container)) {
    throw "preserved r1 root missing: $PreservedRoot"
}
if (Test-Path -LiteralPath $NewBootRoot) {
    throw "new r2 boot root already exists: $NewBootRoot"
}
if (Test-Path -LiteralPath $PreparationReport) {
    throw "preparation report already exists: $PreparationReport"
}

$OriginalVBoxUserHome = [Environment]::GetEnvironmentVariable(
    'VBOX_USER_HOME',
    [EnvironmentVariableTarget]::Process
)
if (-not [string]::IsNullOrEmpty($OriginalVBoxUserHome)) {
    throw "process VBOX_USER_HOME must be unset: $OriginalVBoxUserHome"
}

$PreservedVBox = Join-Path (Join-Path $PreservedRoot 'Machine') 'Temple1.10.vbox'
$PreservedVdi = Join-Path (Join-Path $PreservedRoot 'Machine') 'Temple1.10.vdi'
$PreservedIso = Join-Path (Join-Path $PreservedRoot 'Machine') 'TempleOSTS.iso'
if ((Get-FileHash -LiteralPath $PreservedVBox -Algorithm SHA256).Hash -cne $ExpectedPreservedVBoxHash) {
    throw 'preserved r1 VBOX no longer matches inspection identity'
}
Assert-Value -Observed (Get-FileId -Path $PreservedVBox -Label 'preserved r1 VBOX') -Expected $ExpectedPreservedVBoxFileId -Label 'preserved r1 VBOX file ID'
Assert-Value -Observed (Get-FileId -Path $PreservedVdi -Label 'preserved r1 VDI') -Expected $ExpectedPreservedVdiFileId -Label 'preserved r1 VDI file ID'
Assert-Value -Observed (Get-FileId -Path $PreservedIso -Label 'preserved r1 ISO') -Expected $ExpectedPreservedIsoFileId -Label 'preserved r1 ISO file ID'

$ProbeLines = [System.IO.File]::ReadAllLines($ProbeReport)
Assert-Value -Observed (Get-MixedReportField -Lines $ProbeLines -Key 'vboxmanage_path') -Expected $ResolvedVBox -Label 'probe VBoxManage path'
Assert-Value -Observed (Get-MixedReportField -Lines $ProbeLines -Key 'vboxmanage_version') -Expected $ExpectedVBoxVersion -Label 'probe VBoxManage version'
for ($Attempt = 1; $Attempt -le 4; $Attempt++) {
    Assert-Value -Observed (Get-MixedReportField -Lines $ProbeLines -Key "attempt_${Attempt}_modifyvm_usage_marker") -Expected 'True' -Label "attempt $Attempt usage marker"
    Assert-Value -Observed (Get-MixedReportField -Lines $ProbeLines -Key "attempt_${Attempt}_clipboard_mode_marker") -Expected 'True' -Label "attempt $Attempt clipboard-mode marker"
    Assert-Value -Observed (Get-MixedReportField -Lines $ProbeLines -Key "attempt_${Attempt}_drag_and_drop_marker") -Expected 'True' -Label "attempt $Attempt drag-and-drop marker"
    Assert-Value -Observed (Get-MixedReportField -Lines $ProbeLines -Key "attempt_${Attempt}_draganddrop_marker") -Expected 'False' -Label "attempt $Attempt compact dragdrop marker"
}

$InspectionLines = [System.IO.File]::ReadAllLines($InspectionReport)
Assert-Value -Observed (Get-TabReportField -Lines $InspectionLines -Key 'incomplete_root') -Expected $ExpectedPreservedRoot -Label 'inspection root'
Assert-Value -Observed (Get-TabReportField -Lines $InspectionLines -Key 'preparation_report_absent') -Expected 'True' -Label 'inspection preparation absence'
Assert-Value -Observed (Get-TabReportField -Lines $InspectionLines -Key 'vbox_sha256') -Expected $ExpectedPreservedVBoxHash -Label 'inspection VBOX hash'
Assert-Value -Observed (Get-TabReportField -Lines $InspectionLines -Key 'vbox_file_id') -Expected $ExpectedPreservedVBoxFileId -Label 'inspection VBOX file ID'
Assert-Value -Observed (Get-TabReportField -Lines $InspectionLines -Key 'vdi_file_id') -Expected $ExpectedPreservedVdiFileId -Label 'inspection VDI file ID'
Assert-Value -Observed (Get-TabReportField -Lines $InspectionLines -Key 'iso_file_id') -Expected $ExpectedPreservedIsoFileId -Label 'inspection ISO file ID'
Assert-Value -Observed (Get-TabReportField -Lines $InspectionLines -Key 'target_vdi_location') -Expected 'Temple1.10.vdi' -Label 'inspection target VDI location'
Assert-Value -Observed (Get-TabReportField -Lines $InspectionLines -Key 'target_iso_location') -Expected 'TempleOSTS.iso' -Label 'inspection target ISO location'
Assert-Value -Observed (Get-TabReportField -Lines $InspectionLines -Key 'sealed_vdi_absolute_occurrences') -Expected '0' -Label 'inspection sealed VDI absolute count'
Assert-Value -Observed (Get-TabReportField -Lines $InspectionLines -Key 'copied_vdi_absolute_occurrences') -Expected '0' -Label 'inspection copied VDI absolute count'
Assert-Value -Observed (Get-TabReportField -Lines $InspectionLines -Key 'vdi_basename_occurrences') -Expected '1' -Label 'inspection VDI basename count'
Assert-Value -Observed (Get-TabReportField -Lines $InspectionLines -Key 'sealed_iso_absolute_occurrences') -Expected '0' -Label 'inspection sealed ISO absolute count'
Assert-Value -Observed (Get-TabReportField -Lines $InspectionLines -Key 'copied_iso_absolute_occurrences') -Expected '0' -Label 'inspection copied ISO absolute count'
Assert-Value -Observed (Get-TabReportField -Lines $InspectionLines -Key 'iso_basename_occurrences') -Expected '1' -Label 'inspection ISO basename count'
Assert-Value -Observed (Get-TabReportField -Lines $InspectionLines -Key 'vbox_user_home_file_count') -Expected '0' -Label 'inspection VBoxUserHome file count'
Assert-Value -Observed (Get-TabReportField -Lines $InspectionLines -Key 'vbox_user_home_directory_count') -Expected '0' -Label 'inspection VBoxUserHome directory count'
Assert-Value -Observed (Get-TabReportField -Lines $InspectionLines -Key 'vboxmanage_invocation') -Expected 'NOT-EXECUTED' -Label 'inspection VBoxManage classification'
Assert-Value -Observed (Get-TabReportField -Lines $InspectionLines -Key 'virtualbox_mutation') -Expected 'NOT-EXECUTED' -Label 'inspection mutation classification'
Assert-Value -Observed (Get-TabReportField -Lines $InspectionLines -Key 'INSPECTION') -Expected 'COMPLETE' -Label 'inspection completion'
Assert-Value -Observed (Get-TabReportField -Lines $InspectionLines -Key 'INCOMPLETE ROOT') -Expected 'PRESERVED' -Label 'inspection root preservation'

$Source = [System.IO.File]::ReadAllText($R2Path)
$SourceNewLine = Get-ExactNewLine -Text $Source -Label 'R2 source'

$OldFunctionBase64 = 'JE5ld01vZGlmeUhlbHAgPSBAJwpmdW5jdGlvbiBHZXQtTW9kaWZ5Vm1Td2l0Y2hlcyB7CiAgICAkQXR0ZW1wdHMgPSBAKAogICAgICAgIEAoJ21vZGlmeXZtJywgJy0taGVscCcpLAogICAgICAgIEAoJy0taGVscCcsICdtb2RpZnl2bScpCiAgICApCiAgICAkU3VjY2Vzc2Z1bCA9IFtTeXN0ZW0uQ29sbGVjdGlvbnMuR2VuZXJpYy5MaXN0W3N0cmluZ11dOjpuZXcoKQogICAgZm9yZWFjaCAoJEFyZ3VtZW50cyBpbiAkQXR0ZW1wdHMpIHsKICAgICAgICAkQ2FwdHVyZWQgPSBAKAogICAgICAgICAgICAmICRzY3JpcHQ6VkJveCBAQXJndW1lbnRzIDI+JjEgfAogICAgICAgICAgICAgICAgRm9yRWFjaC1PYmplY3QgeyBbc3RyaW5nXSRfIH0KICAgICAgICApCiAgICAgICAgaWYgKCRMQVNURVhJVENPREUgLWVxIDApIHsKICAgICAgICAgICAgJFN1Y2Nlc3NmdWwuQWRkKCgkQ2FwdHVyZWQgLWpvaW4gImBuIikpCiAgICAgICAgfQogICAgfQogICAgaWYgKCRTdWNjZXNzZnVsLkNvdW50IC1sZSAwKSB7CiAgICAgICAgdGhyb3cgJ25vIHN1Y2Nlc3NmdWwgbW9kaWZ5dm0gaGVscCBpbnZvY2F0aW9uJwogICAgfQogICAgJFRleHQgPSAkU3VjY2Vzc2Z1bCAtam9pbiAiYG4iCiAgICAkQ2xpcGJvYXJkU3dpdGNoID0gaWYgKCRUZXh0IC1tYXRjaCAnKD9tKS0tY2xpcGJvYXJkLW1vZGUoPzpcc3w9KScpIHsKICAgICAgICAnLS1jbGlwYm9hcmQtbW9kZScKICAgIH0KICAgIGVsc2VpZiAoJFRleHQgLW1hdGNoICcoP20pLS1jbGlwYm9hcmQoPzpcc3w9KScpIHsKICAgICAgICAnLS1jbGlwYm9hcmQnCiAgICB9CiAgICBlbHNlIHsKICAgICAgICB0aHJvdyAnbm8gc3VwcG9ydGVkIGNsaXBib2FyZCBtb2RpZnl2bSBzd2l0Y2ggZm91bmQnCiAgICB9CiAgICAkRHJhZ0Ryb3BTd2l0Y2ggPSBpZiAoJFRleHQgLW1hdGNoICcoP20pLS1kcmFnLWFuZC1kcm9wKD86XHN8PSknKSB7CiAgICAgICAgJy0tZHJhZy1hbmQtZHJvcCcKICAgIH0KICAgIGVsc2VpZiAoJFRleHQgLW1hdGNoICcoP20pLS1kcmFnYW5kZHJvcCg/OlxzfD0pJykgewogICAgICAgICctLWRyYWdhbmRkcm9wJwogICAgfQogICAgZWxzZSB7CiAgICAgICAgdGhyb3cgJ25vIHN1cHBvcnRlZCBkcmFnLWFuZC1kcm9wIG1vZGlmeXZtIHN3aXRjaCBmb3VuZCcKICAgIH0KICAgIHJldHVybiBbcHNjdXN0b21vYmplY3RdQHsKICAgICAgICBDbGlwYm9hcmQgPSAkQ2xpcGJvYXJkU3dpdGNoCiAgICAgICAgRHJhZ0Ryb3AgPSAkRHJhZ0Ryb3BTd2l0Y2gKICAgIH0KfQonQA=='
$NewFunctionBase64 = 'JE5ld01vZGlmeUhlbHAgPSBAJwpmdW5jdGlvbiBHZXQtTW9kaWZ5Vm1Td2l0Y2hlcyB7CiAgICByZXR1cm4gW3BzY3VzdG9tb2JqZWN0XUB7CiAgICAgICAgQ2xpcGJvYXJkID0gJy0tY2xpcGJvYXJkLW1vZGUnCiAgICAgICAgRHJhZ0Ryb3AgPSAnLS1kcmFnLWFuZC1kcm9wJwogICAgfQp9CidA'
$OldFunction = [System.Text.Encoding]::UTF8.GetString(
    [System.Convert]::FromBase64String($OldFunctionBase64)
)
$NewFunction = [System.Text.Encoding]::UTF8.GetString(
    [System.Convert]::FromBase64String($NewFunctionBase64)
)
$OldFunction = Convert-ToNewLine -Text $OldFunction -NewLine $SourceNewLine -Label 'old fixed-switch seam'
$NewFunction = Convert-ToNewLine -Text $NewFunction -NewLine $SourceNewLine -Label 'new fixed-switch seam'
$PatchedSource = Invoke-ExactReplacement `
    -Source $Source `
    -Old $OldFunction `
    -New $NewFunction `
    -ExpectedOldCount 1 `
    -Label 'report-bound fixed modifyvm switches'

$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old "Write-Host 'MODIFYVM HELP:        TWO READ-ONLY PROBES'" `
    -New "Write-Host 'MODIFYVM SWITCHES:    REPORT-BOUND / VERSION-EXACT'" `
    -ExpectedOldCount 1 `
    -Label 'R2 output fixed-switch classification'

$PolicyBase64 = 'JE9sZEJvb3RSb290Q29uc3RhbnQgPSBAJwokRXhwZWN0ZWRCb290Um9vdCA9CiAgICAnRDpcVEVDSE5JQ0FMXERCWVRFLUhPTFlDLU9QVC1CT09UXHRlbXBsZW9zdHMtMS4xMC12ZGktb25seS1yMScKJ0AKJE5ld0Jvb3RSb290Q29uc3RhbnQgPSBAJwokRXhwZWN0ZWRCb290Um9vdCA9CiAgICAnRDpcVEVDSE5JQ0FMXERCWVRFLUhPTFlDLU9QVC1CT09UXHRlbXBsZW9zdHMtMS4xMC12ZGktb25seS1yMicKJ0AKJFBhdGNoZWRTb3VyY2UgPSBJbnZva2UtRXhhY3RSZXBsYWNlbWVudCBgCiAgICAtU291cmNlICRQYXRjaGVkU291cmNlIGAKICAgIC1PbGQgJE9sZEJvb3RSb290Q29uc3RhbnQgYAogICAgLU5ldyAkTmV3Qm9vdFJvb3RDb25zdGFudCBgCiAgICAtTGFiZWwgJ1IxMiBuZXcgYm9vdC1hdHRlbXB0IHJvb3QnCgokT2xkTWVkaWFSZXdyaXRlQmxvY2sgPSBAJwogICAgJFZCb3hUZXh0ID0gW1N5c3RlbS5JTy5GaWxlXTo6UmVhZEFsbFRleHQoJEJvb3RWQm94KQogICAgJFZCb3hUZXh0ID0gSW52b2tlLUV4YWN0VGV4dFJlcGxhY2VtZW50IGAKICAgICAgICAtU291cmNlICRWQm94VGV4dCBgCiAgICAgICAgLU9sZCAkU2VhbGVkVmRpLlBhdGggYAogICAgICAgIC1OZXcgJEJvb3RWZGkgYAogICAgICAgIC1MYWJlbCAnYm9vdC1jb3B5IFZESSBwYXRoIHJld3JpdGUnCiAgICAkVkJveFRleHQgPSBJbnZva2UtRXhhY3RUZXh0UmVwbGFjZW1lbnQgYAogICAgICAgIC1Tb3VyY2UgJFZCb3hUZXh0IGAKICAgICAgICAtT2xkICRTZWFsZWRJc28uUGF0aCBgCiAgICAgICAgLU5ldyAkQm9vdElzbyBgCiAgICAgICAgLUxhYmVsICdib290LWNvcHkgSVNPIHBhdGggcmV3cml0ZScKICAgIFdyaXRlLVV0ZjhUZXh0IC1QYXRoICRCb290VkJveCAtVGV4dCAkVkJveFRleHQKICAgICRNdXRhdGlvblN0ZXBzLkFkZCgnUkVXUklURS1DT1BJRUQtVkJPWC1NRURJQS1QQVRIUycpCiAgICAkQm9vdFZCb3hBZnRlclJld3JpdGVIYXNoID0gKAogICAgICAgIEdldC1GaWxlSGFzaCAtTGl0ZXJhbFBhdGggJEJvb3RWQm94IC1BbGdvcml0aG0gU0hBMjU2CiAgICApLkhhc2gKICAgICREdmRDb250cm9sbGVyID0gR2V0LUR2ZENvbnRyb2xsZXJOYW1lIC1WQm94UGF0aCAkQm9vdFZCb3gKJ0AKJE5ld01lZGlhUmV3cml0ZUJsb2NrID0gQCcKICAgICRWQm94VGV4dCA9IFtTeXN0ZW0uSU8uRmlsZV06OlJlYWRBbGxUZXh0KCRCb290VkJveCkKICAgIFt4bWxdJFByZVJlZ2lzdHJhdGlvblZCb3ggPSAkVkJveFRleHQKICAgICRQcmVIYXJkRGlza3MgPSBAKAogICAgICAgICRQcmVSZWdpc3RyYXRpb25WQm94LlNlbGVjdE5vZGVzKAogICAgICAgICAgICAiLy8qW2xvY2FsLW5hbWUoKT0nTWVkaWFSZWdpc3RyeSddLypbbG9jYWwtbmFtZSgpPSdIYXJkRGlza3MnXS8qW2xvY2FsLW5hbWUoKT0nSGFyZERpc2snXSIKICAgICAgICApCiAgICApCiAgICAkUHJlRHZkSW1hZ2VzID0gQCgKICAgICAgICAkUHJlUmVnaXN0cmF0aW9uVkJveC5TZWxlY3ROb2RlcygKICAgICAgICAgICAgIi8vKltsb2NhbC1uYW1lKCk9J01lZGlhUmVnaXN0cnknXS8qW2xvY2FsLW5hbWUoKT0nRFZESW1hZ2VzJ10vKltsb2NhbC1uYW1lKCk9J0ltYWdlJ10iCiAgICAgICAgKQogICAgKQogICAgJFByZVRhcmdldFZkaSA9IEAoCiAgICAgICAgJFByZUhhcmREaXNrcyB8IFdoZXJlLU9iamVjdCB7CiAgICAgICAgICAgIChDb252ZXJ0VG8tTm9ybWFsaXplZFV1aWQgYAogICAgICAgICAgICAgICAgLVZhbHVlICRfLkdldEF0dHJpYnV0ZSgndXVpZCcpIGAKICAgICAgICAgICAgICAgIC1MYWJlbCAncHJlLXJlZ2lzdHJhdGlvbiBIYXJkRGlzayBVVUlEJykgLWNlcSAkRXhwZWN0ZWRWZGlVdWlkCiAgICAgICAgfQogICAgKQogICAgJFByZVRhcmdldElzbyA9IEAoCiAgICAgICAgJFByZUR2ZEltYWdlcyB8IFdoZXJlLU9iamVjdCB7CiAgICAgICAgICAgIChDb252ZXJ0VG8tTm9ybWFsaXplZFV1aWQgYAogICAgICAgICAgICAgICAgLVZhbHVlICRfLkdldEF0dHJpYnV0ZSgndXVpZCcpIGAKICAgICAgICAgICAgICAgIC1MYWJlbCAncHJlLXJlZ2lzdHJhdGlvbiBEVkQgSW1hZ2UgVVVJRCcpIC1jZXEgJEV4cGVjdGVkSXNvVXVpZAogICAgICAgIH0KICAgICkKICAgIGlmICgkUHJlVGFyZ2V0VmRpLkNvdW50IC1uZSAxKSB7CiAgICAgICAgdGhyb3cgInByZS1yZWdpc3RyYXRpb24gdGFyZ2V0IFZESSByb3cgY291bnQgbWlzbWF0Y2g6ICQoJFByZVRhcmdldFZkaS5Db3VudCkiCiAgICB9CiAgICBpZiAoJFByZVRhcmdldElzby5Db3VudCAtbmUgMSkgewogICAgICAgIHRocm93ICJwcmUtcmVnaXN0cmF0aW9uIHRhcmdldCBJU08gcm93IGNvdW50IG1pc21hdGNoOiAkKCRQcmVUYXJnZXRJc28uQ291bnQpIgogICAgfQogICAgaWYgKCRQcmVUYXJnZXRWZGlbMF0uR2V0QXR0cmlidXRlKCdsb2NhdGlvbicpIC1jbmUgJ1RlbXBsZTEuMTAudmRpJykgewogICAgICAgIHRocm93ICgKICAgICAgICAgICAgJ3ByZS1yZWdpc3RyYXRpb24gdGFyZ2V0IFZESSBsb2NhdGlvbiBtaXNtYXRjaDogJyArCiAgICAgICAgICAgICRQcmVUYXJnZXRWZGlbMF0uR2V0QXR0cmlidXRlKCdsb2NhdGlvbicpCiAgICAgICAgKQogICAgfQogICAgaWYgKCRQcmVUYXJnZXRJc29bMF0uR2V0QXR0cmlidXRlKCdsb2NhdGlvbicpIC1jbmUgJ1RlbXBsZU9TVFMuaXNvJykgewogICAgICAgIHRocm93ICgKICAgICAgICAgICAgJ3ByZS1yZWdpc3RyYXRpb24gdGFyZ2V0IElTTyBsb2NhdGlvbiBtaXNtYXRjaDogJyArCiAgICAgICAgICAgICRQcmVUYXJnZXRJc29bMF0uR2V0QXR0cmlidXRlKCdsb2NhdGlvbicpCiAgICAgICAgKQogICAgfQoKICAgICRTZWFsZWRWZGlBYnNvbHV0ZUNvdW50ID0gW3JlZ2V4XTo6TWF0Y2hlcygKICAgICAgICAkVkJveFRleHQsCiAgICAgICAgW3JlZ2V4XTo6RXNjYXBlKCRTZWFsZWRWZGkuUGF0aCksCiAgICAgICAgW1N5c3RlbS5UZXh0LlJlZ3VsYXJFeHByZXNzaW9ucy5SZWdleE9wdGlvbnNdOjpJZ25vcmVDYXNlIC1ib3IKICAgICAgICBbU3lzdGVtLlRleHQuUmVndWxhckV4cHJlc3Npb25zLlJlZ2V4T3B0aW9uc106OkN1bHR1cmVJbnZhcmlhbnQKICAgICkuQ291bnQKICAgICRDb3BpZWRWZGlBYnNvbHV0ZUNvdW50ID0gW3JlZ2V4XTo6TWF0Y2hlcygKICAgICAgICAkVkJveFRleHQsCiAgICAgICAgW3JlZ2V4XTo6RXNjYXBlKCRCb290VmRpKSwKICAgICAgICBbU3lzdGVtLlRleHQuUmVndWxhckV4cHJlc3Npb25zLlJlZ2V4T3B0aW9uc106Oklnbm9yZUNhc2UgLWJvcgogICAgICAgIFtTeXN0ZW0uVGV4dC5SZWd1bGFyRXhwcmVzc2lvbnMuUmVnZXhPcHRpb25zXTo6Q3VsdHVyZUludmFyaWFudAogICAgKS5Db3VudAogICAgJFZkaUJhc2VuYW1lQ291bnQgPSBbcmVnZXhdOjpNYXRjaGVzKAogICAgICAgICRWQm94VGV4dCwKICAgICAgICBbcmVnZXhdOjpFc2NhcGUoJ1RlbXBsZTEuMTAudmRpJyksCiAgICAgICAgW1N5c3RlbS5UZXh0LlJlZ3VsYXJFeHByZXNzaW9ucy5SZWdleE9wdGlvbnNdOjpJZ25vcmVDYXNlIC1ib3IKICAgICAgICBbU3lzdGVtLlRleHQuUmVndWxhckV4cHJlc3Npb25zLlJlZ2V4T3B0aW9uc106OkN1bHR1cmVJbnZhcmlhbnQKICAgICkuQ291bnQKICAgICRTZWFsZWRJc29BYnNvbHV0ZUNvdW50ID0gW3JlZ2V4XTo6TWF0Y2hlcygKICAgICAgICAkVkJveFRleHQsCiAgICAgICAgW3JlZ2V4XTo6RXNjYXBlKCRTZWFsZWRJc28uUGF0aCksCiAgICAgICAgW1N5c3RlbS5UZXh0LlJlZ3VsYXJFeHByZXNzaW9ucy5SZWdleE9wdGlvbnNdOjpJZ25vcmVDYXNlIC1ib3IKICAgICAgICBbU3lzdGVtLlRleHQuUmVndWxhckV4cHJlc3Npb25zLlJlZ2V4T3B0aW9uc106OkN1bHR1cmVJbnZhcmlhbnQKICAgICkuQ291bnQKICAgICRDb3BpZWRJc29BYnNvbHV0ZUNvdW50ID0gW3JlZ2V4XTo6TWF0Y2hlcygKICAgICAgICAkVkJveFRleHQsCiAgICAgICAgW3JlZ2V4XTo6RXNjYXBlKCRCb290SXNvKSwKICAgICAgICBbU3lzdGVtLlRleHQuUmVndWxhckV4cHJlc3Npb25zLlJlZ2V4T3B0aW9uc106Oklnbm9yZUNhc2UgLWJvcgogICAgICAgIFtTeXN0ZW0uVGV4dC5SZWd1bGFyRXhwcmVzc2lvbnMuUmVnZXhPcHRpb25zXTo6Q3VsdHVyZUludmFyaWFudAogICAgKS5Db3VudAogICAgJElzb0Jhc2VuYW1lQ291bnQgPSBbcmVnZXhdOjpNYXRjaGVzKAogICAgICAgICRWQm94VGV4dCwKICAgICAgICBbcmVnZXhdOjpFc2NhcGUoJ1RlbXBsZU9TVFMuaXNvJyksCiAgICAgICAgW1N5c3RlbS5UZXh0LlJlZ3VsYXJFeHByZXNzaW9ucy5SZWdleE9wdGlvbnNdOjpJZ25vcmVDYXNlIC1ib3IKICAgICAgICBbU3lzdGVtLlRleHQuUmVndWxhckV4cHJlc3Npb25zLlJlZ2V4T3B0aW9uc106OkN1bHR1cmVJbnZhcmlhbnQKICAgICkuQ291bnQKICAgIGlmICgKICAgICAgICAkU2VhbGVkVmRpQWJzb2x1dGVDb3VudCAtbmUgMCAtb3IKICAgICAgICAkQ29waWVkVmRpQWJzb2x1dGVDb3VudCAtbmUgMCAtb3IKICAgICAgICAkVmRpQmFzZW5hbWVDb3VudCAtbmUgMSAtb3IKICAgICAgICAkU2VhbGVkSXNvQWJzb2x1dGVDb3VudCAtbmUgMCAtb3IKICAgICAgICAkQ29waWVkSXNvQWJzb2x1dGVDb3VudCAtbmUgMCAtb3IKICAgICAgICAkSXNvQmFzZW5hbWVDb3VudCAtbmUgMQogICAgKSB7CiAgICAgICAgdGhyb3cgKAogICAgICAgICAgICAncHJlLXJlZ2lzdHJhdGlvbiByZWxhdGl2ZSBtZWRpYSByZXByZXNlbnRhdGlvbiBtaXNtYXRjaDogJyArCiAgICAgICAgICAgICJzZWFsZWRfdmRpX2Ficz0kU2VhbGVkVmRpQWJzb2x1dGVDb3VudCAiICsKICAgICAgICAgICAgImNvcGllZF92ZGlfYWJzPSRDb3BpZWRWZGlBYnNvbHV0ZUNvdW50ICIgKwogICAgICAgICAgICAidmRpX2Jhc2VuYW1lPSRWZGlCYXNlbmFtZUNvdW50ICIgKwogICAgICAgICAgICAic2VhbGVkX2lzb19hYnM9JFNlYWxlZElzb0Fic29sdXRlQ291bnQgIiArCiAgICAgICAgICAgICJjb3BpZWRfaXNvX2Ficz0kQ29waWVkSXNvQWJzb2x1dGVDb3VudCAiICsKICAgICAgICAgICAgImlzb19iYXNlbmFtZT0kSXNvQmFzZW5hbWVDb3VudCIKICAgICAgICApCiAgICB9CgogICAgJE11dGF0aW9uU3RlcHMuQWRkKCdQUkVTRVJWRS1DT1BJRUQtVkJPWC1SRUxBVElWRS1NRURJQS1MT0NBVElPTlMnKQogICAgJEJvb3RWQm94QWZ0ZXJSZXdyaXRlSGFzaCA9ICRCb290VkJveEJlZm9yZVJld3JpdGUuU0hBMjU2CiAgICAkRHZkQ29udHJvbGxlciA9IEdldC1EdmRDb250cm9sbGVyTmFtZSAtVkJveFBhdGggJEJvb3RWQm94CidACiRQYXRjaGVkU291cmNlID0gSW52b2tlLUV4YWN0UmVwbGFjZW1lbnQgYAogICAgLVNvdXJjZSAkUGF0Y2hlZFNvdXJjZSBgCiAgICAtT2xkICRPbGRNZWRpYVJld3JpdGVCbG9jayBgCiAgICAtTmV3ICROZXdNZWRpYVJld3JpdGVCbG9jayIGCiAgICAtTGFiZWwgJ2luc3BlY3Rpb24tYm91bmQgcmVsYXRpdmUgbWVkaWEgcG9saWN5JwoKJE9sZFhtbFBvc3Rjb25kaXRpb25DYWxsID0gQCcKICAgIEFzc2VydC1Cb290VkJveFhtbCBgCiAgICAgICAgLVZCb3hQYXRoICRCb290VkJveCBgCiAgICAgICAgLUV4cGVjdGVkVmRpUGF0aCAkQm9vdFZkaSBgCiAgICAgICAgLUV4cGVjdGVkSXNvUmVnaXN0cnlQYXRoICRCb290SXNvCidACiROZXdYbWxQb3N0Y29uZGl0aW9uQ2FsbCA9IEAnCiAgICBBc3NlcnQtQm9vdFZCb3hYbWwgYAogICAgICAgIC1WQm94UGF0aCAkQm9vdFZCb3ggYAogICAgICAgIC1FeHBlY3RlZFZkaVBhdGggJ1RlbXBsZTEuMTAudmRpJyBgCiAgICAgICAgLUV4cGVjdGVkSXNvUmVnaXN0cnlQYXRoICdUZW1wbGVPU1RTLmlzbycKJ0AKJFBhdGNoZWRTb3VyY2UgPSBJbnZva2UtRXhhY3RSZXBsYWNlbWVudCBgCiAgICAtU291cmNlICRQYXRjaGVkU291cmNlIGAKICAgIC1PbGQgJE9sZFhtbFBvc3Rjb25kaXRpb25DYWxsIGAKICAgIC1OZXcgJE5ld1htbFBvc3Rjb25kaXRpb25DYWxsIGAKICAgIC1MYWJlbCAncmVsYXRpdmUgbWVkaWEgWE1MIHBvc3Rjb25kaXRpb24nCgokUGF0Y2hlZFNvdXJjZSA9IEludm9rZS1FeGFjdFJlcGxhY2VtZW50IGAKICAgIC1Tb3VyY2UgJFBhdGNoZWRTb3VyY2UgYAogICAgLU9sZCAnJE1hbmlmZXN0LkFkZCgiYm9vdF92Ym94X3ByZV9yZXdyaXRlX3NoYTI1NmB0JCgkQm9vdFZCb3hCZWZvcmVSZXdyaXRlLlNIQTI1NikiKScgYAogICAgLU5ldyAnJE1hbmlmZXN0LkFkZCgiYm9vdF92Ym94X3ByZV9tZWRpYV9wb2xpY3lfc2hhMjU2YHQkKCRCb290VkJveEJlZm9yZVJld3JpdGUuU0hBMjU2KSIpJyBgCiAgICAtTGFiZWwgJ21hbmlmZXN0IHByZS1tZWRpYS1wb2xpY3kgbGFiZWwnCiRQYXRjaGVkU291cmNlID0gSW52b2tlLUV4YWN0UmVwbGFjZW1lbnQgYAogICAgLVNvdXJjZSAkUGF0Y2hlZFNvdXJjZSBgCiAgICAtT2xkICckTWFuaWZlc3QuQWRkKCJib290X3Zib3hfcG9zdF9yZXdyaXRlX3NoYTI1NmB0JEJvb3RWQm94QWZ0ZXJSZXdyaXRlSGFzaCIpJyBgCiAgICAtTmV3ICckTWFuaWZlc3QuQWRkKCJib290X3Zib3hfcG9zdF9tZWRpYV9wb2xpY3lfc2hhMjU2YHQkQm9vdFZCb3hBZnRlclJld3JpdGVIYXNoIiknIGAKICAgIC1MYWJlbCAnbWFuaWZlc3QgcG9zdC1tZWRpYS1wb2xpY3kgbGFiZWwnCg==