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

$ExpectedOriginalBlob = '3e12ae01d062b60cf7011cc7f960b1d64b2700b4'
$OriginalRelative = 'tools/PREPARE-TEMPLEOSTS-VDI-ONLY-BOOT-ATTEMPT.ps1'
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
$PSScriptRootReferences = [regex]::Matches(
    $Source,
    [regex]::Escape('$PSScriptRoot'),
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
).Count
if ($PSScriptRootReferences -ne 0) {
    throw (
        'original preparer is not safe for dynamic execution: ' +
        "PSScriptRoot references=$PSScriptRootReferences"
    )
}

$OldTargetFunctionSignature = @'
        [Parameter(Mandatory = $true)][string]$ExpectedConfig,
        [Parameter(Mandatory = $true)][string]$ExpectedVdi,
        [Parameter(Mandatory = $true)][string]$Label
'@
$NewTargetFunctionSignature = @'
        [Parameter(Mandatory = $true)][string]$ExpectedConfig,
        [Parameter(Mandatory = $true)][string]$ExpectedVdi,
        [AllowEmptyString()][string]$ExpectedIso = '',
        [Parameter(Mandatory = $true)][string]$Label
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $Source `
    -Old $OldTargetFunctionSignature `
    -New $NewTargetFunctionSignature `
    -Label 'target-state optional ISO parameter'

$OldTargetAttachmentGate = @'
    Assert-MachineValue -Info $Info -Key 'CfgFile' -Expected $ExpectedConfig -Label $Label
    Assert-MachineValue -Info $Info -Key 'IDE-1-0' -Expected $ExpectedVdi -Label $Label

    $SharedKeys = @(
'@
$NewTargetAttachmentGate = @'
    Assert-MachineValue -Info $Info -Key 'CfgFile' -Expected $ExpectedConfig -Label $Label
    Assert-MachineValue -Info $Info -Key 'IDE-1-0' -Expected $ExpectedVdi -Label $Label
    if (-not [string]::IsNullOrWhiteSpace($ExpectedIso)) {
        Assert-MachineValue `
            -Info $Info `
            -Key 'IDE-0-1' `
            -Expected $ExpectedIso `
            -Label $Label
    }

    $SharedKeys = @(
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldTargetAttachmentGate `
    -New $NewTargetAttachmentGate `
    -Label 'target-state optional ISO attachment gate'

$OldXmlIsoRegistryGate = @'
    if ($IsoImages.Count -ne 1 -or $MatchingIsoImages.Count -ne 1) {
        throw 'boot-attempt VBOX ISO media-registry path mismatch'
    }

    $AttachedIsoNodes = @(
'@
$NewXmlIsoRegistryGate = @'
    if ($IsoImages.Count -gt 1 -or $MatchingIsoImages.Count -ne $IsoImages.Count) {
        throw 'boot-attempt VBOX ISO media-registry path mismatch'
    }

    $AttachedIsoNodes = @(
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldXmlIsoRegistryGate `
    -New $NewXmlIsoRegistryGate `
    -Label 'detached ISO optional machine-local registry row'

$OldModifyHelp = @'
function Get-ModifyVmSwitches {
    $Help = @(
        Invoke-VBoxRead -Arguments @('modifyvm', '--help') -Label 'modifyvm help'
    )
    $Text = $Help -join "`n"
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
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldModifyHelp `
    -New $NewModifyHelp `
    -Label 'modifyvm help probing'

$OldDefaultBeforeCall = @'
    -ExpectedConfig $ExpectedLiveVBoxPath `
    -ExpectedVdi $ExpectedLiveVdiPath `
    -Label 'default registry before boot-copy preparation')
'@
$NewDefaultBeforeCall = @'
    -ExpectedConfig $ExpectedLiveVBoxPath `
    -ExpectedVdi $ExpectedLiveVdiPath `
    -ExpectedIso $ExpectedLiveIsoPath `
    -Label 'default registry before boot-copy preparation')
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldDefaultBeforeCall `
    -New $NewDefaultBeforeCall `
    -Label 'default pre-preparation ISO binding'

$OldBootBeforeCall = @'
            -ExpectedConfig $BootVBox `
            -ExpectedVdi $BootVdi `
            -Label 'boot-copy registry before correction')
'@
$NewBootBeforeCall = @'
            -ExpectedConfig $BootVBox `
            -ExpectedVdi $BootVdi `
            -ExpectedIso $BootIso `
            -Label 'boot-copy registry before correction')
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldBootBeforeCall `
    -New $NewBootBeforeCall `
    -Label 'boot-copy pre-correction ISO binding'

$OldDefaultAfterCall = @'
        -ExpectedConfig $ExpectedLiveVBoxPath `
        -ExpectedVdi $ExpectedLiveVdiPath `
        -Label 'default registry after boot-copy preparation')
'@
$NewDefaultAfterCall = @'
        -ExpectedConfig $ExpectedLiveVBoxPath `
        -ExpectedVdi $ExpectedLiveVdiPath `
        -ExpectedIso $ExpectedLiveIsoPath `
        -Label 'default registry after boot-copy preparation')
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldDefaultAfterCall `
    -New $NewDefaultAfterCall `
    -Label 'default post-preparation ISO binding'

$OldPreDetachSeam = @'
        [void](Invoke-VBoxMutation `
            -Arguments @('modifyvm', $ExpectedTargetUuid, $Switches.DragDrop, 'disabled') `
            -Label 'disable boot-copy drag-and-drop')
        $MutationSteps.Add("DISABLE-DRAGDROP-VIA-$($Switches.DragDrop)")

        [void](Invoke-VBoxMutation `
'@
$NewPreDetachSeam = @'
        [void](Invoke-VBoxMutation `
            -Arguments @('modifyvm', $ExpectedTargetUuid, $Switches.DragDrop, 'disabled') `
            -Label 'disable boot-copy drag-and-drop')
        $MutationSteps.Add("DISABLE-DRAGDROP-VIA-$($Switches.DragDrop)")

        $PreDetachIsoMedium = @(
            Invoke-VBoxRead `
                -Arguments @('showmediuminfo', 'dvd', $BootIso) `
                -Label 'boot-copy ISO medium info before detach'
        )
        $ObservedIsoUuid = ConvertTo-NormalizedUuid `
            -Value (Get-ColonValue -Lines $PreDetachIsoMedium -Key 'UUID') `
            -Label 'boot-copy ISO UUID before detach'
        if ($ObservedIsoUuid -cne $ExpectedIsoUuid) {
            throw "boot-copy ISO UUID mismatch before detach: $ObservedIsoUuid"
        }
        $MutationSteps.Add('VERIFY-ISO-UUID-BEFORE-DETACH')

        [void](Invoke-VBoxMutation `
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldPreDetachSeam `
    -New $NewPreDetachSeam `
    -Label 'pre-detach ISO UUID proof'

$OldPostStateGate = @'
        Assert-MachineValue -Info $PostInfo -Key 'clipboard' -Expected 'disabled' -Label 'boot-copy corrected state'
        Assert-MachineValue -Info $PostInfo -Key 'draganddrop' -Expected 'disabled' -Label 'boot-copy corrected state'
        for ($Index = 1; $Index -le 8; $Index++) {
            $NicKey = "nic$Index"
            if ($PostInfo.ContainsKey($NicKey)) {
                Assert-MachineValue `
                    -Info $PostInfo `
                    -Key $NicKey `
                    -Expected 'none' `
                    -Label 'boot-copy corrected state'
            }
        }

        $IsoSlotValue = Get-RequiredMachineValue `
            -Info $PostInfo `
            -Key 'IDE-0-1' `
            -Label 'boot-copy corrected state'
'@
$NewPostStateGate = @'
        Assert-MachineValue -Info $PostInfo -Key 'clipboard' -Expected 'disabled' -Label 'boot-copy corrected state'
        Assert-MachineValue -Info $PostInfo -Key 'draganddrop' -Expected 'disabled' -Label 'boot-copy corrected state'
        Assert-MachineValue -Info $PostInfo -Key 'graphicscontroller' -Expected 'vboxvga' -Label 'boot-copy corrected state'
        Assert-MachineValue -Info $PostInfo -Key 'vram' -Expected '9' -Label 'boot-copy corrected state'
        $NicKeys = @(
            $PostInfo.Keys | Where-Object { $_ -match '^nic[1-8]$' }
        )
        if ($NicKeys.Count -le 0) {
            throw 'boot-copy corrected state contains no NIC fields'
        }
        foreach ($NicKey in $NicKeys) {
            Assert-MachineValue `
                -Info $PostInfo `
                -Key $NicKey `
                -Expected 'none' `
                -Label 'boot-copy corrected state'
        }

        $IsoSlotValue = if ($PostInfo.ContainsKey('IDE-0-1')) {
            [string]$PostInfo['IDE-0-1']
        }
        else {
            '<missing>'
        }
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldPostStateGate `
    -New $NewPostStateGate `
    -Label 'corrected-state NIC graphics and detached-slot gates'

$OldPostMediumBlock = @'
        $VdiMedium = @(
            Invoke-VBoxRead `
                -Arguments @('showmediuminfo', 'disk', $BootVdi) `
                -Label 'boot-copy VDI medium info'
        )
        $IsoMedium = @(
            Invoke-VBoxRead `
                -Arguments @('showmediuminfo', 'dvd', $BootIso) `
                -Label 'boot-copy ISO medium info'
        )
        $ObservedVdiUuid = ConvertTo-NormalizedUuid `
            -Value (Get-ColonValue -Lines $VdiMedium -Key 'UUID') `
            -Label 'boot-copy VDI UUID'
        $ObservedIsoUuid = ConvertTo-NormalizedUuid `
            -Value (Get-ColonValue -Lines $IsoMedium -Key 'UUID') `
            -Label 'boot-copy ISO UUID'
        if ($ObservedVdiUuid -cne $ExpectedVdiUuid) {
            throw "boot-copy VDI UUID mismatch: $ObservedVdiUuid"
        }
        if ($ObservedIsoUuid -cne $ExpectedIsoUuid) {
            throw "boot-copy ISO UUID mismatch: $ObservedIsoUuid"
        }
'@
$NewPostMediumBlock = @'
        $VdiMedium = @(
            Invoke-VBoxRead `
                -Arguments @('showmediuminfo', 'disk', $BootVdi) `
                -Label 'boot-copy VDI medium info'
        )
        $ObservedVdiUuid = ConvertTo-NormalizedUuid `
            -Value (Get-ColonValue -Lines $VdiMedium -Key 'UUID') `
            -Label 'boot-copy VDI UUID'
        if ($ObservedVdiUuid -cne $ExpectedVdiUuid) {
            throw "boot-copy VDI UUID mismatch: $ObservedVdiUuid"
        }
'@
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldPostMediumBlock `
    -New $NewPostMediumBlock `
    -Label 'post-detach medium proof'

if ($PatchedSource -ceq $Source) {
    throw 'in-memory boot-attempt preparer hardening produced no source change'
}

$PatchedHash = Get-TextSha256 -Text $PatchedSource
$Preparer = [scriptblock]::Create($PatchedSource)
$InvokeArguments = @{
    VBoxManagePath = $VBoxManagePath
    ResourceRoot = $ResourceRoot
    RehearsalVerificationReportPath = $RehearsalVerificationReportPath
    BootReadinessReportPath = $BootReadinessReportPath
    SealedRehearsalRoot = $SealedRehearsalRoot
    BootAttemptRoot = $BootAttemptRoot
    OutPath = $OutPath
}

Write-Host "ORIGINAL PREPARER:    $ExpectedOriginalBlob"
Write-Host 'DEFAULT ISO BINDING:  BEFORE + AFTER'
Write-Host 'BOOT ISO UUID:        PRE-DETACH PROOF'
Write-Host 'DETACHED SLOT:        VALUE OR MISSING'
Write-Host 'NIC CARDINALITY:      AT LEAST ONE / ALL NONE'
Write-Host 'GRAPHICS RETENTION:   VBOXVGA / 9 MB'
Write-Host 'DVD REGISTRY ROW:     ZERO OR ONE / LOCAL PATH IF PRESENT'
Write-Host 'MODIFYVM HELP:        TWO READ-ONLY PROBES'
Write-Host 'DYNAMIC CONTEXT:      NO PSSCRIPTROOT REFERENCES'
Write-Host "PATCHED SOURCE SHA:   $PatchedHash"
& $Preparer @InvokeArguments
