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

$ExpectedOriginalBlob = 'cec7ca5dc9439c11d0375eebe45f0864a5f7f995'
$OriginalRelative =
    'tools/PREPARE-TEMPLEOSTS-ISOLATED-RESTORE-REHEARSAL.ps1'
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
        [Parameter(Mandatory = $true)][int]$ExpectedCount,
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
    if ($OldCount -ne $ExpectedCount -or $NewCountBefore -ne 0) {
        throw (
            "$Label source cardinality mismatch: " +
            "old=$OldCount expected=$ExpectedCount new_before=$NewCountBefore"
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
    if ($OldCountAfter -ne 0 -or $NewCountAfter -ne $ExpectedCount) {
        throw (
            "$Label replacement contract mismatch: " +
            "old_after=$OldCountAfter new_after=$NewCountAfter " +
            "expected=$ExpectedCount"
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
    throw "original preparer missing: $OriginalPath"
}

$TreeBlob = @(
    Invoke-GitRead `
        -Arguments @('rev-parse', "HEAD`:$OriginalRelative") `
        -Label 'original preparer tree blob'
)
$LocalBlob = @(
    Invoke-GitRead `
        -Arguments @('hash-object', '--', $OriginalRelative) `
        -Label 'original preparer local blob'
)
if (
    $TreeBlob.Count -ne 1 -or
    $LocalBlob.Count -ne 1 -or
    $TreeBlob[0] -cne $ExpectedOriginalBlob -or
    $LocalBlob[0] -cne $ExpectedOriginalBlob
) {
    throw (
        'original preparer blob mismatch: ' +
        "tree=$($TreeBlob -join '|') local=$($LocalBlob -join '|')"
    )
}

$Source = [System.IO.File]::ReadAllText($OriginalPath)

$PatchedSource = Invoke-ExactReplacement `
    -Source $Source `
    -Old '    throw "$Label: VBoxSVC did not exit; PIDs=$($Remaining.Id -join '','')"' `
    -New '    throw "${Label}: VBoxSVC did not exit; PIDs=$($Remaining.Id -join '','')"' `
    -ExpectedCount 1 `
    -Label 'VBoxSVC label interpolation'

$OldFileIdBlock = @'
    $DisposableVdiFileId = Get-FileId -Path $DisposableVdi -Label 'disposable VDI'
    $DisposableIsoFileId = Get-FileId -Path $DisposableIso -Label 'disposable ISO'
    $BundleIsoFileId = Get-FileId -Path $BundleIso.Path -Label 'bundle ISO'
    if (
        $DisposableVdiFileId -ceq $ExpectedBundleVdiFileId -or
        $DisposableVdiFileId -ceq $ExpectedLiveVdiFileId
    ) {
        throw 'disposable VDI is not a distinct NTFS file object'
    }
    if ($DisposableIsoFileId -ceq $BundleIsoFileId) {
        throw 'disposable ISO is not a distinct NTFS file object'
    }
'@
$NewFileIdBlock = @'
    $DisposableVBoxFileId = Get-FileId -Path $DisposableVBox -Label 'disposable VBOX'
    $DisposableVdiFileId = Get-FileId -Path $DisposableVdi -Label 'disposable VDI'
    $DisposableIsoFileId = Get-FileId -Path $DisposableIso -Label 'disposable ISO'
    $BundleVBoxFileId = Get-FileId -Path $BundleVBox.Path -Label 'bundle VBOX'
    $BundleIsoFileId = Get-FileId -Path $BundleIso.Path -Label 'bundle ISO'
    if ($BundleVBoxFileId -cne $ExpectedBundleVBoxFileId) {
        throw "bundle VBOX file ID changed before rehearsal: $BundleVBoxFileId"
    }
    if ($DisposableVBoxFileId -ceq $BundleVBoxFileId) {
        throw 'disposable VBOX is not a distinct NTFS file object'
    }
    if (
        $DisposableVdiFileId -ceq $ExpectedBundleVdiFileId -or
        $DisposableVdiFileId -ceq $ExpectedLiveVdiFileId
    ) {
        throw 'disposable VDI is not a distinct NTFS file object'
    }
    if ($DisposableIsoFileId -ceq $BundleIsoFileId) {
        throw 'disposable ISO is not a distinct NTFS file object'
    }
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldFileIdBlock `
    -New $NewFileIdBlock `
    -ExpectedCount 1 `
    -Label 'disposable VBOX file identity gate'

$OldPostOperationSeam = @'
    Wait-VBoxServiceExit -Label 'default registry service shutdown after revalidation'

    $DisposableVBoxPostRegistrationHash = (
        Get-FileHash -LiteralPath $DisposableVBox -Algorithm SHA256
    ).Hash
'@
$NewPostOperationSeam = @'
    Wait-VBoxServiceExit -Label 'default registry service shutdown after revalidation'

    [void](Assert-ExactHashFile `
        -Path $VerificationReport `
        -SHA256 $ExpectedVerificationReportHash `
        -Label 'verification report after rehearsal')
    [void](Assert-ExactHashFile `
        -Path $RouteReport `
        -SHA256 $ExpectedRouteReportHash `
        -Label 'route report after rehearsal')
    [void](Assert-ExactHashFile `
        -Path $BundleManifest.Path `
        -SHA256 $ExpectedManifestHash `
        -Label 'bundle manifest after rehearsal')
    [void](Assert-ExactHashFile `
        -Path $BundleVBox.Path `
        -SHA256 $ExpectedLiveVBoxHash `
        -Label 'bundle VBOX after rehearsal')
    [void](Assert-ExactFile `
        -Path $BundleVdi.Path `
        -Bytes $ExpectedVdiBytes `
        -SHA256 $ExpectedVdiHash `
        -Label 'bundle VDI after rehearsal')
    [void](Assert-ExactFile `
        -Path $BundleIso.Path `
        -Bytes $ExpectedIsoBytes `
        -SHA256 $ExpectedIsoHash `
        -Label 'bundle ISO after rehearsal')
    if ((Get-FileId -Path $BundleVBox.Path -Label 'bundle VBOX after rehearsal') -cne $ExpectedBundleVBoxFileId) {
        throw 'bundle VBOX file ID changed after rehearsal'
    }
    if ((Get-FileId -Path $BundleVdi.Path -Label 'bundle VDI after rehearsal') -cne $ExpectedBundleVdiFileId) {
        throw 'bundle VDI file ID changed after rehearsal'
    }
    if ((Get-FileId -Path $BundleIso.Path -Label 'bundle ISO after rehearsal') -cne $BundleIsoFileId) {
        throw 'bundle ISO file ID changed after rehearsal'
    }
    [void](Assert-ExactFile `
        -Path $DisposableVdi `
        -Bytes $ExpectedVdiBytes `
        -SHA256 $ExpectedVdiHash `
        -Label 'disposable VDI after registration')
    [void](Assert-ExactFile `
        -Path $DisposableIso `
        -Bytes $ExpectedIsoBytes `
        -SHA256 $ExpectedIsoHash `
        -Label 'disposable ISO after registration')

    $DisposableVBoxPostRegistrationHash = (
        Get-FileHash -LiteralPath $DisposableVBox -Algorithm SHA256
    ).Hash
    $DisposableVBoxPostRegistrationFileId = Get-FileId `
        -Path $DisposableVBox `
        -Label 'disposable VBOX after registration'
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldPostOperationSeam `
    -New $NewPostOperationSeam `
    -ExpectedCount 1 `
    -Label 'post-operation sealed and disposable revalidation'

$OldManifestField = @'
    $Manifest.Add("disposable_vbox_post_registration_sha256`t$DisposableVBoxPostRegistrationHash")
'@
$NewManifestField = @'
    $Manifest.Add("disposable_vbox_post_registration_sha256`t$DisposableVBoxPostRegistrationHash")
    $Manifest.Add("disposable_vbox_pre_rewrite_file_id`t$DisposableVBoxFileId")
    $Manifest.Add("disposable_vbox_post_registration_file_id`t$DisposableVBoxPostRegistrationFileId")
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldManifestField `
    -New $NewManifestField `
    -ExpectedCount 1 `
    -Label 'manifest disposable VBOX file IDs'

$OldReportField = @'
    $Report.Add("disposable_vbox_post_registration_sha256`t$DisposableVBoxPostRegistrationHash")
'@
$NewReportField = @'
    $Report.Add("disposable_vbox_post_registration_sha256`t$DisposableVBoxPostRegistrationHash")
    $Report.Add("disposable_vbox_pre_rewrite_file_id`t$DisposableVBoxFileId")
    $Report.Add("disposable_vbox_post_registration_file_id`t$DisposableVBoxPostRegistrationFileId")
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldReportField `
    -New $NewReportField `
    -ExpectedCount 1 `
    -Label 'report disposable VBOX file IDs'

$OldTerminalField = @'
    Write-Host "VBOX POST-REGISTER:   $DisposableVBoxPostRegistrationHash"
    Write-Host "VDI FILE ID:          $DisposableVdiFileId"
'@
$NewTerminalField = @'
    Write-Host "VBOX POST-REGISTER:   $DisposableVBoxPostRegistrationHash"
    Write-Host "VBOX FILE ID PRE:     $DisposableVBoxFileId"
    Write-Host "VBOX FILE ID POST:    $DisposableVBoxPostRegistrationFileId"
    Write-Host "VDI FILE ID:          $DisposableVdiFileId"
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldTerminalField `
    -New $NewTerminalField `
    -ExpectedCount 1 `
    -Label 'terminal disposable VBOX file IDs'

if ($PatchedSource -ceq $Source) {
    throw 'in-memory rehearsal preparer hardening produced no source change'
}
$PatchedHash = Get-TextSha256 -Text $PatchedSource
$Preparer = [scriptblock]::Create($PatchedSource)
$InvokeArguments = @{
    VBoxManagePath = $VBoxManagePath
    ResourceRoot = $ResourceRoot
    VerificationReportPath = $VerificationReportPath
    RouteReportPath = $RouteReportPath
    RecoveryRoot = $RecoveryRoot
    RehearsalRoot = $RehearsalRoot
    OutPath = $OutPath
}

Write-Host "ORIGINAL PREPARER:    $ExpectedOriginalBlob"
Write-Host 'LABEL PARSE GUARD:    IN-MEMORY / EXACT-ONE-REPLACEMENT'
Write-Host 'VBOX FILE-ID GUARD:   IN-MEMORY / EXACT-ONE-REPLACEMENT'
Write-Host 'POST-HASH GUARD:      IN-MEMORY / EXACT-ONE-REPLACEMENT'
Write-Host 'REPORT FIELD GUARDS:  IN-MEMORY / EXACT-ONE-REPLACEMENTS'
Write-Host "PATCHED SOURCE SHA:   $PatchedHash"
& $Preparer @InvokeArguments
