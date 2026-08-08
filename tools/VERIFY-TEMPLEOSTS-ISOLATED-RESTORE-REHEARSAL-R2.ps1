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
    [string]$VerificationReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RouteReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PreparationReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RecoveryRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RehearsalRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedOriginalBlob = 'fe7437577605a8e72f27c7fa0c0f54558d62af6c'
$OriginalRelative =
    'tools/VERIFY-TEMPLEOSTS-ISOLATED-RESTORE-REHEARSAL.ps1'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$OriginalPath = Join-Path $RepoRoot (
    $OriginalRelative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
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
        throw "$Label failed`n$($Captured -join "`n")"
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
            "$Label source cardinality mismatch: " +
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
            "$Label replacement contract mismatch: " +
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

if (-not (Test-Path -LiteralPath $OriginalPath -PathType Leaf)) {
    throw "original verifier missing: $OriginalPath"
}

$TreeBlob = @(
    Invoke-GitRead `
        -Arguments @('rev-parse', "HEAD`:$OriginalRelative") `
        -Label 'original verifier tree blob'
)
$LocalBlob = @(
    Invoke-GitRead `
        -Arguments @('hash-object', '--', $OriginalRelative) `
        -Label 'original verifier local blob'
)
if (
    $TreeBlob.Count -ne 1 -or
    $LocalBlob.Count -ne 1 -or
    $TreeBlob[0] -cne $ExpectedOriginalBlob -or
    $LocalBlob[0] -cne $ExpectedOriginalBlob
) {
    throw (
        'original verifier blob mismatch: ' +
        "tree=$($TreeBlob -join '|') local=$($LocalBlob -join '|')"
    )
}

$Source = [System.IO.File]::ReadAllText($OriginalPath)

$OldInventoryMatcher = @'
function Assert-InventoryMatches {
    param(
        [Parameter(Mandatory = $true)][object[]]$Expected,
        [Parameter(Mandatory = $true)][object[]]$Observed,
        [Parameter(Mandatory = $true)][string]$Label
    )

    Assert-ExactNameSet `
        -Observed @($Observed | ForEach-Object { $_.Relative }) `
        -Expected @($Expected | ForEach-Object { $_.Relative }) `
        -Label "$Label file set"

    $ObservedByName = @{}
    foreach ($Row in $Observed) {
        $ObservedByName[$Row.Relative] = $Row
    }
    foreach ($ExpectedRow in $Expected) {
        $ObservedRow = $ObservedByName[$ExpectedRow.Relative]
        if ($null -eq $ObservedRow) {
            throw "$Label file missing: $($ExpectedRow.Relative)"
        }
        if ($ObservedRow.Bytes -ne $ExpectedRow.Bytes) {
            throw (
                "$Label byte-count mismatch: $($ExpectedRow.Relative) " +
                "observed=$($ObservedRow.Bytes) expected=$($ExpectedRow.Bytes)"
            )
        }
        if ($ObservedRow.SHA256 -cne $ExpectedRow.SHA256) {
            throw (
                "$Label SHA256 mismatch: $($ExpectedRow.Relative) " +
                "observed=$($ObservedRow.SHA256) expected=$($ExpectedRow.SHA256)"
            )
        }
    }
}
'@
$NewInventoryMatcher = @'
function Test-IsVolatileRehearsalPath {
    param([Parameter(Mandatory = $true)][string]$Relative)

    $Normalized = $Relative.Replace('/', '\')
    return $Normalized -cmatch (
        '^VBoxUserHome\\VBoxSVC\.log(?:\.[1-9][0-9]*)?$'
    )
}

function Assert-VolatileLogSequence {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Rows,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ($Rows.Count -le 0) {
        throw "$Label does not contain an active VBoxSVC.log"
    }

    $Suffixes = [System.Collections.Generic.List[int]]::new()
    foreach ($Row in $Rows) {
        $Normalized = ([string]$Row.Relative).Replace('/', '\')
        if (-not (Test-IsVolatileRehearsalPath -Relative $Normalized)) {
            throw "$Label contains a disallowed volatile path: $Normalized"
        }
        if ($Normalized -ceq 'VBoxUserHome\VBoxSVC.log') {
            $Suffixes.Add(0)
            continue
        }
        $Match = [regex]::Match(
            $Normalized,
            '^VBoxUserHome\\VBoxSVC\.log\.(?<suffix>[1-9][0-9]*)$'
        )
        if (-not $Match.Success) {
            throw "$Label suffix parse failed: $Normalized"
        }
        $Suffix = 0
        if (-not [int]::TryParse($Match.Groups['suffix'].Value, [ref]$Suffix)) {
            throw "$Label suffix exceeds Int32: $Normalized"
        }
        $Suffixes.Add($Suffix)
    }

    $Sorted = @($Suffixes.ToArray() | Sort-Object)
    if (@($Sorted | Select-Object -Unique).Count -ne $Sorted.Count) {
        throw "$Label contains duplicate log suffixes"
    }
    for ($Index = 0; $Index -lt $Sorted.Count; $Index++) {
        if ($Sorted[$Index] -ne $Index) {
            throw (
                "$Label is not one contiguous VBoxSVC.log sequence: " +
                "index=$Index suffix=$($Sorted[$Index])"
            )
        }
    }
}

function Assert-InventoryMatches {
    param(
        [Parameter(Mandatory = $true)][object[]]$Expected,
        [Parameter(Mandatory = $true)][object[]]$Observed,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $ExpectedVolatile = @(
        $Expected | Where-Object {
            Test-IsVolatileRehearsalPath -Relative ([string]$_.Relative)
        }
    )
    $ObservedVolatile = @(
        $Observed | Where-Object {
            Test-IsVolatileRehearsalPath -Relative ([string]$_.Relative)
        }
    )
    $ExpectedImmutable = @(
        $Expected | Where-Object {
            -not (Test-IsVolatileRehearsalPath -Relative ([string]$_.Relative))
        }
    )
    $ObservedImmutable = @(
        $Observed | Where-Object {
            -not (Test-IsVolatileRehearsalPath -Relative ([string]$_.Relative))
        }
    )

    [void](Assert-VolatileLogSequence `
        -Rows $ExpectedVolatile `
        -Label "$Label manifest volatile log set")
    [void](Assert-VolatileLogSequence `
        -Rows $ObservedVolatile `
        -Label "$Label observed volatile log set")

    Assert-ExactNameSet `
        -Observed @($ObservedImmutable | ForEach-Object { $_.Relative }) `
        -Expected @($ExpectedImmutable | ForEach-Object { $_.Relative }) `
        -Label "$Label immutable file set"

    $ObservedByName = @{}
    foreach ($Row in $ObservedImmutable) {
        $ObservedByName[$Row.Relative] = $Row
    }
    foreach ($ExpectedRow in $ExpectedImmutable) {
        $ObservedRow = $ObservedByName[$ExpectedRow.Relative]
        if ($null -eq $ObservedRow) {
            throw "$Label immutable file missing: $($ExpectedRow.Relative)"
        }
        if ($ObservedRow.Bytes -ne $ExpectedRow.Bytes) {
            throw (
                "$Label immutable byte-count mismatch: $($ExpectedRow.Relative) " +
                "observed=$($ObservedRow.Bytes) expected=$($ExpectedRow.Bytes)"
            )
        }
        if ($ObservedRow.SHA256 -cne $ExpectedRow.SHA256) {
            throw (
                "$Label immutable SHA256 mismatch: $($ExpectedRow.Relative) " +
                "observed=$($ObservedRow.SHA256) expected=$($ExpectedRow.SHA256)"
            )
        }
    }

    return [pscustomobject]@{
        ImmutableCount = $ExpectedImmutable.Count
        ManifestVolatileCount = $ExpectedVolatile.Count
        ObservedVolatileCount = $ObservedVolatile.Count
        VolatileRows = [object[]]@(
            $ObservedVolatile | Sort-Object Relative
        )
    }
}
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $Source `
    -Old $OldInventoryMatcher `
    -New $NewInventoryMatcher `
    -Label 'bounded VBoxSVC log inventory policy'

$OldBeforeInventory = @'
$ObservedInventoryBefore = @(
    Get-RehearsalInventory -Root $Rehearsal -ExcludeManifest
)
Assert-InventoryMatches `
    -Expected $ManifestInventory `
    -Observed $ObservedInventoryBefore `
    -Label 'rehearsal inventory before registry verification'
$AllFilesBefore = @(Get-RehearsalInventory -Root $Rehearsal)
if ($AllFilesBefore.Count -ne ($ManifestInventory.Count + 1)) {
    throw (
        "rehearsal total file count mismatch: observed=$($AllFilesBefore.Count) " +
        "expected=$($ManifestInventory.Count + 1)"
    )
}
'@
$NewBeforeInventory = @'
$ObservedInventoryBefore = @(
    Get-RehearsalInventory -Root $Rehearsal -ExcludeManifest
)
$InventoryPolicyBefore = Assert-InventoryMatches `
    -Expected $ManifestInventory `
    -Observed $ObservedInventoryBefore `
    -Label 'rehearsal inventory before registry verification'
$AllFilesBefore = @(Get-RehearsalInventory -Root $Rehearsal)
$ExpectedAllNamesBefore = @(
    @($ObservedInventoryBefore | ForEach-Object { $_.Relative }) +
    'ISOLATED-REHEARSAL-MANIFEST.txt'
)
Assert-ExactNameSet `
    -Observed @($AllFilesBefore | ForEach-Object { $_.Relative }) `
    -Expected $ExpectedAllNamesBefore `
    -Label 'rehearsal complete file set before registry verification'
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldBeforeInventory `
    -New $NewBeforeInventory `
    -Label 'pre-verification volatile inventory capture'

$OldAfterInventory = @'
$ObservedInventoryAfter = @(
    Get-RehearsalInventory -Root $Rehearsal -ExcludeManifest
)
Assert-InventoryMatches `
    -Expected $ManifestInventory `
    -Observed $ObservedInventoryAfter `
    -Label 'rehearsal inventory after registry verification'
$AllFilesAfter = @(Get-RehearsalInventory -Root $Rehearsal)
if ($AllFilesAfter.Count -ne ($ManifestInventory.Count + 1)) {
    throw (
        "rehearsal total file count changed: observed=$($AllFilesAfter.Count) " +
        "expected=$($ManifestInventory.Count + 1)"
    )
}
'@
$NewAfterInventory = @'
$ObservedInventoryAfter = @(
    Get-RehearsalInventory -Root $Rehearsal -ExcludeManifest
)
$InventoryPolicyAfter = Assert-InventoryMatches `
    -Expected $ManifestInventory `
    -Observed $ObservedInventoryAfter `
    -Label 'rehearsal inventory after registry verification'
$AllFilesAfter = @(Get-RehearsalInventory -Root $Rehearsal)
$ExpectedAllNamesAfter = @(
    @($ObservedInventoryAfter | ForEach-Object { $_.Relative }) +
    'ISOLATED-REHEARSAL-MANIFEST.txt'
)
Assert-ExactNameSet `
    -Observed @($AllFilesAfter | ForEach-Object { $_.Relative }) `
    -Expected $ExpectedAllNamesAfter `
    -Label 'rehearsal complete file set after registry verification'
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldAfterInventory `
    -New $NewAfterInventory `
    -Label 'post-verification volatile inventory capture'

$OldReportInventory = @'
$Report.Add("manifest_inventory_files`t$($ManifestInventory.Count)")
$Report.Add("rehearsal_total_files`t$($AllFilesAfter.Count)")
$Report.Add('')
'@
$NewReportInventory = @'
$Report.Add("manifest_inventory_files`t$($ManifestInventory.Count)")
$Report.Add("immutable_inventory_files`t$($InventoryPolicyAfter.ImmutableCount)")
$Report.Add("manifest_volatile_log_files`t$($InventoryPolicyAfter.ManifestVolatileCount)")
$Report.Add("volatile_log_files_before`t$($InventoryPolicyBefore.ObservedVolatileCount)")
$Report.Add("volatile_log_files_after`t$($InventoryPolicyAfter.ObservedVolatileCount)")
$Report.Add("rehearsal_total_files`t$($AllFilesAfter.Count)")
$Report.Add('')
foreach ($Row in $InventoryPolicyBefore.VolatileRows) {
    $Report.Add(
        "volatile_log_before`t$($Row.Relative)`t$($Row.Bytes)`t$($Row.SHA256)"
    )
}
foreach ($Row in $InventoryPolicyAfter.VolatileRows) {
    $Report.Add(
        "volatile_log_after`t$($Row.Relative)`t$($Row.Bytes)`t$($Row.SHA256)"
    )
}
$Report.Add('')
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldReportInventory `
    -New $NewReportInventory `
    -Label 'volatile log report fields'

$OldReportClaims = @'
$Report.Add('Every manifest inventory row was reopened and rehashed before isolated registry access.')
$Report.Add('The isolated registry contained exactly one powered-off disposable VM with exact local attachments.')
$Report.Add('The isolated VDI and ISO UUIDs matched the sealed route identities.')
$Report.Add('After VBoxSVC shutdown, every manifest inventory row was reopened and matched again.')
$Report.Add('The default registry, live artifacts, sealed reports and recovery bundle were revalidated after isolation.')
$Report.Add('No VM start, restore boot, snapshot mutation, guest delivery or compiler execution occurred.')
'@
$NewReportClaims = @'
$Report.Add('Every non-volatile manifest inventory row was reopened and rehashed before isolated registry access.')
$Report.Add('Only VBoxUserHome\\VBoxSVC.log and one contiguous numbered rotation sequence were classified as volatile.')
$Report.Add('The complete volatile log inventories before and after isolated access were recorded above.')
$Report.Add('The isolated registry contained exactly one powered-off disposable VM with exact local attachments.')
$Report.Add('The isolated VDI and ISO UUIDs matched the sealed route identities.')
$Report.Add('After VBoxSVC shutdown, every non-volatile manifest inventory row was reopened and matched again.')
$Report.Add('The default registry, live artifacts, sealed reports and recovery bundle were revalidated after isolation.')
$Report.Add('No VM start, restore boot, snapshot mutation, guest delivery or compiler execution occurred.')
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldReportClaims `
    -New $NewReportClaims `
    -Label 'bounded volatility report claims'

$OldTerminalInventory = @'
Write-Host "MANIFEST FILES:       $($ManifestInventory.Count)"
Write-Host "TOTAL FILES:          $($AllFilesAfter.Count)"
'@
$NewTerminalInventory = @'
Write-Host "MANIFEST FILES:       $($ManifestInventory.Count)"
Write-Host "IMMUTABLE FILES:      $($InventoryPolicyAfter.ImmutableCount)"
Write-Host "VOLATILE BEFORE:      $($InventoryPolicyBefore.ObservedVolatileCount)"
Write-Host "VOLATILE AFTER:       $($InventoryPolicyAfter.ObservedVolatileCount)"
Write-Host "TOTAL FILES:          $($AllFilesAfter.Count)"
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldTerminalInventory `
    -New $NewTerminalInventory `
    -Label 'bounded volatility terminal fields'

if ($PatchedSource -ceq $Source) {
    throw 'in-memory verifier correction produced no source change'
}
$PatchedHash = Get-TextSha256 -Text $PatchedSource
$Verifier = [scriptblock]::Create($PatchedSource)
$InvokeArguments = @{
    VBoxManagePath = $VBoxManagePath
    ResourceRoot = $ResourceRoot
    VerificationReportPath = $VerificationReportPath
    RouteReportPath = $RouteReportPath
    PreparationReportPath = $PreparationReportPath
    RecoveryRoot = $RecoveryRoot
    RehearsalRoot = $RehearsalRoot
    OutPath = $OutPath
}

Write-Host "ORIGINAL VERIFIER:    $ExpectedOriginalBlob"
Write-Host 'VOLATILE PATH GUARD:  EXACT VBOXSVC.LOG[.N] ONLY'
Write-Host 'ROTATION SEQUENCE:    ACTIVE LOG + CONTIGUOUS 1..N'
Write-Host 'IMMUTABLE INVENTORY:  MANIFEST PATH/BYTES/SHA256 EXACT'
Write-Host 'VOLATILE REPORTING:   BEFORE + AFTER ROWS'
Write-Host "PATCHED SOURCE SHA:   $PatchedHash"
& $Verifier @InvokeArguments
