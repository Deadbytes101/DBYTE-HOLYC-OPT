[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ReportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedReportHash =
    'C7253681589771FF0E36A56DDFA7627C6FCA48398A1AEE1465645470DC8B3A11'
$ExpectedInspectorHash =
    '6393BCD2E0B6E0FCFCC01D74D0B4C3F6F035B5D686CF61ECB349B84E853C0594'
$ExpectedResourceCommit =
    '37b0457e8735ab8cc34a23f2717fcfb808e6a7a8'
$ExpectedTargetName = 'Temple1.10'
$ExpectedTargetUuid = '9c98691e-27cd-4487-a306-587969c2c78c'
$ExpectedLiveVBoxHash =
    'E537469A1B1A88DE13D18704B5D6299F3AF202DA518FB266F045485A8FC4F1E6'
$ExpectedBaselineVBoxHash =
    'E7A884AD2590BAD05AF4465A22FD857A75F64AB9F91042E4638256E8B21AEB46'
$ExpectedLiveNormalizedHash =
    'CCB9C85945B1A432B35E1021D8C174E932E932FE1E2988D4655072FA68211859'
$ExpectedBaselineNormalizedHash =
    '1E3FB6296E757B388F89A17AC05F02A0525C42D609CE67A8212032FE9E791866'
$ExpectedVdiHash =
    '90D453A94F075760A11E0772862E60C4B031ED874F28AA396EAE638F7EB8B31B'
$ExpectedIsoHash =
    'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$ExpectedFirstDifference = '971'
$ExpectedRowCount = 9

function Assert-UniqueLine {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Expected
    )

    $Count = @($Lines | Where-Object { $_ -ceq $Expected }).Count
    if ($Count -ne 1) {
        throw "required line count mismatch: $Expected count=$Count"
    }
}

function Get-UniqueTabValue {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Key
    )

    $Prefix = "$Key`t"
    $Found = @($Lines | Where-Object { $_.StartsWith($Prefix) })
    if ($Found.Count -ne 1) {
        throw "report field count mismatch: $Key count=$($Found.Count)"
    }
    return $Found[0].Substring($Prefix.Length)
}

function Assert-FieldEquals {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Expected
    )

    $Observed = Get-UniqueTabValue -Lines $Lines -Key $Key
    if ($Observed -cne $Expected) {
        throw "report field mismatch: $Key expected=$Expected observed=$Observed"
    }
}

$Report = (Resolve-Path -LiteralPath $ReportPath -ErrorAction Stop).Path
if (-not (Test-Path -LiteralPath $Report -PathType Leaf)) {
    throw "normalized difference report is not a file: $Report"
}

$ReportHash = (Get-FileHash -LiteralPath $Report -Algorithm SHA256).Hash
if ($ReportHash -cne $ExpectedReportHash) {
    throw "normalized difference report SHA256 mismatch: $ReportHash"
}

$Lines = [System.IO.File]::ReadAllLines($Report)
Assert-UniqueLine `
    -Lines $Lines `
    -Expected 'TEMPLEOSTS 1.10 VBOX NORMALIZED DIFFERENCE DIAGNOSTIC'
Assert-FieldEquals `
    -Lines $Lines `
    -Key 'inspector_report_sha256' `
    -Expected $ExpectedInspectorHash
Assert-FieldEquals `
    -Lines $Lines `
    -Key 'resource_commit' `
    -Expected $ExpectedResourceCommit
Assert-FieldEquals `
    -Lines $Lines `
    -Key 'target_name' `
    -Expected $ExpectedTargetName
Assert-FieldEquals `
    -Lines $Lines `
    -Key 'target_uuid' `
    -Expected $ExpectedTargetUuid
Assert-FieldEquals -Lines $Lines -Key 'vm_state' -Expected 'poweroff'
Assert-FieldEquals `
    -Lines $Lines `
    -Key 'live_vbox_sha256' `
    -Expected $ExpectedLiveVBoxHash
Assert-FieldEquals `
    -Lines $Lines `
    -Key 'baseline_vbox_sha256' `
    -Expected $ExpectedBaselineVBoxHash
Assert-FieldEquals `
    -Lines $Lines `
    -Key 'live_vbox_normalized_sha256' `
    -Expected $ExpectedLiveNormalizedHash
Assert-FieldEquals `
    -Lines $Lines `
    -Key 'baseline_vbox_normalized_sha256' `
    -Expected $ExpectedBaselineNormalizedHash
Assert-FieldEquals `
    -Lines $Lines `
    -Key 'first_normalized_character_difference' `
    -Expected $ExpectedFirstDifference
Assert-FieldEquals `
    -Lines $Lines `
    -Key 'normalized_line_diff_rows' `
    -Expected ([string]$ExpectedRowCount)
Assert-FieldEquals `
    -Lines $Lines `
    -Key 'live_vdi_sha256' `
    -Expected $ExpectedVdiHash
Assert-FieldEquals `
    -Lines $Lines `
    -Key 'live_iso_sha256' `
    -Expected $ExpectedIsoHash
Assert-FieldEquals `
    -Lines $Lines `
    -Key 'VBOX NORMALIZED RELATIONSHIP' `
    -Expected 'MISMATCH-DISPLAYED'
Assert-FieldEquals `
    -Lines $Lines `
    -Key 'DIFFERENCE CLASSIFICATION' `
    -Expected 'UNRESOLVED'
Assert-FieldEquals `
    -Lines $Lines `
    -Key 'POWERED-OFF RECOVERY POINT' `
    -Expected 'NOT-SEALED'
Assert-FieldEquals `
    -Lines $Lines `
    -Key 'BUILD EXECUTION' `
    -Expected 'NOT-AUTHORIZED'

$SectionMatches = @(
    for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
        if ($Lines[$Index] -ceq 'NORMALIZED LINE DIFF') {
            $Index
        }
    }
)
if ($SectionMatches.Count -ne 1) {
    throw "NORMALIZED LINE DIFF section count mismatch: $($SectionMatches.Count)"
}
$SectionIndex = [int]$SectionMatches[0]
$HeaderIndex = $SectionIndex + 1
if (
    $HeaderIndex -ge $Lines.Count -or
    $Lines[$HeaderIndex] -cne
    'kind current_line baseline_line line_sha256 text'
) {
    throw 'NORMALIZED LINE DIFF header mismatch'
}

$Rows = [System.Collections.Generic.List[string]]::new()
$RowIndex = $HeaderIndex + 1
while ($RowIndex -lt $Lines.Count -and $Lines[$RowIndex] -cne '') {
    $Rows.Add($Lines[$RowIndex])
    $RowIndex++
}
if ($Rows.Count -ne $ExpectedRowCount) {
    throw "normalized line-diff row count mismatch: $($Rows.Count)"
}

$RowPattern =
    '^(CURRENT-ONLY|BASELINE-ONLY)\t([0-9]+)\t([0-9]+)\t([0-9A-F]{64})\t(.*)$'
$CurrentOnly = 0
$BaselineOnly = 0
for ($Index = 0; $Index -lt $Rows.Count; $Index++) {
    $Match = [regex]::Match($Rows[$Index], $RowPattern)
    if (-not $Match.Success) {
        throw "normalized line-diff row schema mismatch: row=$($Index + 1)"
    }

    $Kind = $Match.Groups[1].Value
    $CurrentLine = [int]$Match.Groups[2].Value
    $BaselineLine = [int]$Match.Groups[3].Value
    if ($Kind -ceq 'CURRENT-ONLY') {
        if ($CurrentLine -le 0 -or $BaselineLine -ne 0) {
            throw "CURRENT-ONLY line coordinates invalid: row=$($Index + 1)"
        }
        $CurrentOnly++
    }
    else {
        if ($CurrentLine -ne 0 -or $BaselineLine -le 0) {
            throw "BASELINE-ONLY line coordinates invalid: row=$($Index + 1)"
        }
        $BaselineOnly++
    }
}
if ($CurrentOnly + $BaselineOnly -ne $ExpectedRowCount) {
    throw 'normalized line-diff kind accounting mismatch'
}

Write-Host "REPORT:               $Report"
Write-Host "REPORT SHA256:        $ReportHash"
Write-Host "TARGET:               $ExpectedTargetName"
Write-Host "TARGET UUID:          $ExpectedTargetUuid"
Write-Host 'VM STATE:             poweroff'
Write-Host "LIVE VBOX:            $ExpectedLiveVBoxHash"
Write-Host "BASELINE VBOX:        $ExpectedBaselineVBoxHash"
Write-Host "LIVE NORMALIZED:      $ExpectedLiveNormalizedHash"
Write-Host "BASE NORMALIZED:      $ExpectedBaselineNormalizedHash"
Write-Host "FIRST DIFFERENCE:     $ExpectedFirstDifference"
Write-Host "DIFF ROWS:            $ExpectedRowCount"
Write-Host "CURRENT-ONLY ROWS:    $CurrentOnly"
Write-Host "BASELINE-ONLY ROWS:   $BaselineOnly"
Write-Host ''
Write-Host 'NORMALIZED LINE DIFF'
Write-Host 'kind current_line baseline_line line_sha256 text'
foreach ($Row in $Rows) {
    Write-Host $Row
}
Write-Host ''
Write-Host 'DIFFERENCE CLASS:     UNRESOLVED'
Write-Host 'RECOVERY POINT:       NOT-SEALED'
Write-Host 'BUILD:                NOT-AUTHORIZED'
Write-Host 'VERDICT:              SEALED NORMALIZED DIFF DISPLAY COMPLETE'
