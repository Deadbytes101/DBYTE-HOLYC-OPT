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
    [string]$InspectorReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedResourceCommit =
    '37b0457e8735ab8cc34a23f2717fcfb808e6a7a8'
$ExpectedInspectorReportHash =
    '6393BCD2E0B6E0FCFCC01D74D0B4C3F6F035B5D686CF61ECB349B84E853C0594'
$ExpectedTargetName = 'Temple1.10'
$ExpectedTargetUuid = '9c98691e-27cd-4487-a306-587969c2c78c'
$ExpectedVBoxPath = 'D:\VirtualBox VMs\Temple1.10\Temple1.10.vbox'
$ExpectedVdiPath = 'D:\VirtualBox VMs\Temple1.10\Temple1.10.vdi'
$ExpectedVdiBytes = 2097152L
$ExpectedVdiHash =
    '90D453A94F075760A11E0772862E60C4B031ED874F28AA396EAE638F7EB8B31B'
$ExpectedIsoPath = 'D:\TempleOSTS.iso'
$ExpectedIsoBytes = 30558208L
$ExpectedIsoHash =
    'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$ExpectedBaselineVBoxBytes = 2503L
$ExpectedBaselineVBoxHash =
    'E7A884AD2590BAD05AF4465A22FD857A75F64AB9F91042E4638256E8B21AEB46'
$BaselineRelative =
    'vm-output/virtualbox/Temple1.10-adopted-baseline/baseline1'
$LastStateChangePattern = 'lastStateChange="[^"]*"'

function Get-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path)
}

function Get-Prefix {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FullPath -Path $Path).TrimEnd('\', '/') +
        [System.IO.Path]::DirectorySeparatorChar
}

function Assert-OutsideRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $Full = Get-FullPath -Path $Path
    $RootFull = Get-FullPath -Path $Root
    if (
        [string]::Equals(
            $Full,
            $RootFull,
            [System.StringComparison]::OrdinalIgnoreCase
        ) -or
        $Full.StartsWith(
            (Get-Prefix -Path $Root),
            [System.StringComparison]::OrdinalIgnoreCase
        )
    ) {
        throw "output is inside read-only resource root: $Full"
    }
}

function Assert-ExactFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][long]$Bytes,
        [Parameter(Mandatory = $true)][string]$SHA256,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label missing: $Path"
    }

    $Item = Get-Item -LiteralPath $Path
    $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($Item.Length -ne $Bytes -or $Hash -cne $SHA256) {
        throw (
            "$Label identity mismatch: bytes=$($Item.Length) " +
            "SHA256=$Hash path=$Path"
        )
    }

    return [pscustomobject]@{
        Path = $Item.FullName
        Bytes = $Item.Length
        SHA256 = $Hash
    }
}

function Assert-UniqueLine {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Expected
    )

    $Count = @($Lines | Where-Object { $_ -ceq $Expected }).Count
    if ($Count -ne 1) {
        throw "required report line count mismatch: $Expected count=$Count"
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

function Get-UniqueInt64 {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Key
    )

    $Text = Get-UniqueTabValue -Lines $Lines -Key $Key
    if ($Text -notmatch '^[0-9]+$') {
        throw "report integer field is invalid: $Key value=$Text"
    }
    return [long]$Text
}

function Assert-FieldEquals {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Expected,
        [switch]$IgnoreCase
    )

    $Observed = Get-UniqueTabValue -Lines $Lines -Key $Key
    $Comparison = if ($IgnoreCase) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }
    if (-not [string]::Equals($Observed, $Expected, $Comparison)) {
        throw "report field mismatch: $Key expected=$Expected observed=$Observed"
    }
}

function Assert-HashText {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ($Value -notmatch '^[0-9A-F]{64}$') {
        throw "$Label is not an uppercase SHA256: $Value"
    }
}

function Invoke-GitRead {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Captured = @(
        & git -C $script:Resource @Arguments 2>&1 |
            ForEach-Object { [string]$_ }
    )
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed`n$($Captured -join "`n")"
    }
    return $Captured
}

function Invoke-VBoxReadOnly {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Captured = @(
        & $script:VBox @Arguments 2>&1 |
            ForEach-Object { [string]$_ }
    )
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed`n$($Captured -join "`n")"
    }
    return $Captured
}

function ConvertFrom-VBoxMachineReadable {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    $Result = @{}
    foreach ($Line in $Lines) {
        $Equals = $Line.IndexOf('=')
        if ($Equals -le 0) {
            continue
        }

        $Key = $Line.Substring(0, $Equals)
        $Value = $Line.Substring($Equals + 1)
        if (
            $Value.Length -ge 2 -and
            $Value[0] -eq '"' -and
            $Value[$Value.Length - 1] -eq '"'
        ) {
            $Value = $Value.Substring(1, $Value.Length - 2)
            $Value = $Value.Replace('\"', '"').Replace('\\', '\')
        }
        $Result[$Key] = $Value
    }
    return $Result
}

function Assert-MachineValue {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Info,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Expected
    )

    if (-not $Info.ContainsKey($Key)) {
        throw "live machine field missing: $Key"
    }
    $Observed = [string]$Info[$Key]
    if (-not [string]::Equals(
        $Observed,
        $Expected,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "live machine field mismatch: $Key=$Observed"
    }
}

function Get-NormalizedVBox {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label missing: $Path"
    }

    $Text = [System.IO.File]::ReadAllText($Path)
    $Matches = [regex]::Matches(
        $Text,
        $script:LastStateChangePattern,
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    )
    if ($Matches.Count -ne 1) {
        throw "$Label lastStateChange count mismatch: $($Matches.Count)"
    }

    $Normalized = [regex]::Replace(
        $Text,
        $script:LastStateChangePattern,
        'lastStateChange="<VOLATILE>"',
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    )
    $Bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Normalized)
    $Sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $Hash = (
            [System.BitConverter]::ToString($Sha.ComputeHash($Bytes))
        ).Replace('-', '')
    }
    finally {
        $Sha.Dispose()
    }

    return [pscustomobject]@{
        NormalizedText = $Normalized
        NormalizedSHA256 = $Hash
        LastStateChangeCount = $Matches.Count
        LastStateChange = $Matches[0].Value
    }
}

$script:Resource = (
    Resolve-Path -LiteralPath $ResourceRoot -ErrorAction Stop
).Path
$script:VBox = (
    Resolve-Path -LiteralPath $VBoxManagePath -ErrorAction Stop
).Path
$InspectorReport = (
    Resolve-Path -LiteralPath $InspectorReportPath -ErrorAction Stop
).Path
$Output = Get-FullPath -Path $OutPath
$script:LastStateChangePattern = $LastStateChangePattern

if (-not (Test-Path -LiteralPath $script:Resource -PathType Container)) {
    throw "resource root is not a directory: $script:Resource"
}
if (-not (Test-Path -LiteralPath $script:VBox -PathType Leaf)) {
    throw "VBoxManage is not a file: $script:VBox"
}
Assert-OutsideRoot -Path $Output -Root $script:Resource
if (Test-Path -LiteralPath $Output) {
    throw "output already exists: $Output"
}

$InspectorItem = Get-Item -LiteralPath $InspectorReport
$InspectorIdentity = Assert-ExactFile `
    -Path $InspectorReport `
    -Bytes $InspectorItem.Length `
    -SHA256 $ExpectedInspectorReportHash `
    -Label 'failed recovery inspector report'
$Lines = [System.IO.File]::ReadAllLines($InspectorReport)
foreach ($Expected in @(
    "phase`tPREFLIGHT",
    "classification`tREGISTERED-ARTIFACT-MISMATCH",
    "target row count`t1",
    "running target count`t0",
    "unrelated inaccessible count`t0",
    "target VM state`tpoweroff",
    "VBOX state`tMISMATCH",
    "VDI state`tEXACT",
    "ISO destination state`tEXACT",
    "adopted baseline state`tEXACT"
)) {
    Assert-UniqueLine -Lines $Lines -Expected $Expected
}

Assert-FieldEquals -Lines $Lines -Key 'VM name' -Expected $ExpectedTargetName
Assert-FieldEquals -Lines $Lines -Key 'VM UUID' -Expected $ExpectedTargetUuid
Assert-FieldEquals -Lines $Lines -Key 'observed name' -Expected $ExpectedTargetName
Assert-FieldEquals -Lines $Lines -Key 'observed UUID' -Expected $ExpectedTargetUuid
Assert-FieldEquals `
    -Lines $Lines `
    -Key 'CfgFile expected' `
    -Expected $ExpectedVBoxPath `
    -IgnoreCase
Assert-FieldEquals `
    -Lines $Lines `
    -Key 'observed CfgFile' `
    -Expected $ExpectedVBoxPath `
    -IgnoreCase
Assert-FieldEquals `
    -Lines $Lines `
    -Key 'VDI expected' `
    -Expected $ExpectedVdiPath `
    -IgnoreCase
Assert-FieldEquals `
    -Lines $Lines `
    -Key 'observed VDI' `
    -Expected $ExpectedVdiPath `
    -IgnoreCase
Assert-FieldEquals `
    -Lines $Lines `
    -Key 'ISO expected' `
    -Expected $ExpectedIsoPath `
    -IgnoreCase
Assert-FieldEquals `
    -Lines $Lines `
    -Key 'observed ISO' `
    -Expected $ExpectedIsoPath `
    -IgnoreCase

$ReportVBoxBytes = Get-UniqueInt64 -Lines $Lines -Key 'VBOX bytes'
$ReportVBoxHash = Get-UniqueTabValue -Lines $Lines -Key 'VBOX SHA256'
$ReportVBoxNormalized = Get-UniqueTabValue `
    -Lines $Lines `
    -Key 'VBOX normalized SHA256'
$ReportBaselineNormalized = Get-UniqueTabValue `
    -Lines $Lines `
    -Key 'baseline VBOX normalized SHA256'
$ReportVdiBytes = Get-UniqueInt64 -Lines $Lines -Key 'VDI bytes'
$ReportVdiHash = Get-UniqueTabValue -Lines $Lines -Key 'VDI SHA256'
$ReportIsoBytes = Get-UniqueInt64 -Lines $Lines -Key 'ISO bytes'
$ReportIsoHash = Get-UniqueTabValue -Lines $Lines -Key 'ISO SHA256'
$ReportBaselineVBoxHash = Get-UniqueTabValue `
    -Lines $Lines `
    -Key 'baseline VBOX SHA256'
$ReportBaselineVdiHash = Get-UniqueTabValue `
    -Lines $Lines `
    -Key 'baseline VDI SHA256'
$ReportBaselineIsoHash = Get-UniqueTabValue `
    -Lines $Lines `
    -Key 'baseline ISO SHA256'

Assert-HashText -Value $ReportVBoxHash -Label 'reported current VBOX SHA256'
Assert-HashText `
    -Value $ReportVBoxNormalized `
    -Label 'reported current normalized VBOX SHA256'
Assert-HashText `
    -Value $ReportBaselineNormalized `
    -Label 'reported baseline normalized VBOX SHA256'
Assert-HashText -Value $ReportVdiHash -Label 'reported VDI SHA256'
Assert-HashText -Value $ReportIsoHash -Label 'reported ISO SHA256'
Assert-HashText `
    -Value $ReportBaselineVBoxHash `
    -Label 'reported baseline VBOX SHA256'
Assert-HashText `
    -Value $ReportBaselineVdiHash `
    -Label 'reported baseline VDI SHA256'
Assert-HashText `
    -Value $ReportBaselineIsoHash `
    -Label 'reported baseline ISO SHA256'

if (
    $ReportVdiBytes -ne $ExpectedVdiBytes -or
    $ReportVdiHash -cne $ExpectedVdiHash -or
    $ReportIsoBytes -ne $ExpectedIsoBytes -or
    $ReportIsoHash -cne $ExpectedIsoHash -or
    $ReportBaselineVBoxHash -cne $ExpectedBaselineVBoxHash -or
    $ReportBaselineVdiHash -cne $ExpectedVdiHash -or
    $ReportBaselineIsoHash -cne $ExpectedIsoHash
) {
    throw 'inspector report artifact identities do not match the sealed contract'
}

$Head = @(Invoke-GitRead -Arguments @('rev-parse', 'HEAD') -Label 'resource HEAD')
if ($Head.Count -ne 1 -or $Head[0] -cne $ExpectedResourceCommit) {
    throw "resource HEAD mismatch: $($Head -join ' | ')"
}
[void](Invoke-GitRead -Arguments @('diff', '--check') -Label 'resource diff check')
$Worktree = @(
    Invoke-GitRead -Arguments @('diff', '--name-only') -Label 'resource worktree diff'
)
$Index = @(
    Invoke-GitRead -Arguments @('diff', '--cached', '--name-only') -Label 'resource index diff'
)
if ($Worktree.Count -ne 0 -or $Index.Count -ne 0) {
    throw 'resource tracked tree is not clean'
}

$BaselineRoot = Join-Path $script:Resource (
    $BaselineRelative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
)
$BaselineVBox = Assert-ExactFile `
    -Path (Join-Path $BaselineRoot 'Temple1.10.vbox') `
    -Bytes $ExpectedBaselineVBoxBytes `
    -SHA256 $ExpectedBaselineVBoxHash `
    -Label 'adopted baseline VBOX'
[void](Assert-ExactFile `
    -Path (Join-Path $BaselineRoot 'Temple1.10.vdi') `
    -Bytes $ExpectedVdiBytes `
    -SHA256 $ExpectedVdiHash `
    -Label 'adopted baseline VDI')
[void](Assert-ExactFile `
    -Path (Join-Path $BaselineRoot 'TempleOSTS.iso') `
    -Bytes $ExpectedIsoBytes `
    -SHA256 $ExpectedIsoHash `
    -Label 'adopted baseline ISO')

$Registered = @(
    Invoke-VBoxReadOnly -Arguments @('list', 'vms') -Label 'registered VM inventory'
)
$Running = @(
    Invoke-VBoxReadOnly -Arguments @('list', 'runningvms') -Label 'running VM inventory'
)
$RegisteredPattern = (
    '^"' + [regex]::Escape($ExpectedTargetName) + '" \{' +
    [regex]::Escape($ExpectedTargetUuid) + '\}$'
)
if (@($Registered | Where-Object { $_ -match $RegisteredPattern }).Count -ne 1) {
    throw 'live registered target identity mismatch'
}
$RunningPattern = '^"' + [regex]::Escape($ExpectedTargetName) + '" '
if (@($Running | Where-Object { $_ -match $RunningPattern }).Count -ne 0) {
    throw 'target is currently listed as running'
}

$Show = @(
    Invoke-VBoxReadOnly `
        -Arguments @('showvminfo', $ExpectedTargetUuid, '--machinereadable') `
        -Label 'target showvminfo'
)
$Info = ConvertFrom-VBoxMachineReadable -Lines $Show
Assert-MachineValue -Info $Info -Key 'name' -Expected $ExpectedTargetName
Assert-MachineValue -Info $Info -Key 'UUID' -Expected $ExpectedTargetUuid
Assert-MachineValue -Info $Info -Key 'VMState' -Expected 'poweroff'
Assert-MachineValue -Info $Info -Key 'CfgFile' -Expected $ExpectedVBoxPath
Assert-MachineValue -Info $Info -Key 'IDE-1-0' -Expected $ExpectedVdiPath
Assert-MachineValue -Info $Info -Key 'IDE-0-1' -Expected $ExpectedIsoPath

$CurrentVBoxItem = Get-Item -LiteralPath $ExpectedVBoxPath
$CurrentVBoxHash = (
    Get-FileHash -LiteralPath $ExpectedVBoxPath -Algorithm SHA256
).Hash
if (
    $CurrentVBoxItem.Length -ne $ReportVBoxBytes -or
    $CurrentVBoxHash -cne $ReportVBoxHash
) {
    throw (
        "current VBOX changed since inspector report: " +
        "bytes=$($CurrentVBoxItem.Length) SHA256=$CurrentVBoxHash"
    )
}
[void](Assert-ExactFile `
    -Path $ExpectedVdiPath `
    -Bytes $ExpectedVdiBytes `
    -SHA256 $ExpectedVdiHash `
    -Label 'live VDI')
[void](Assert-ExactFile `
    -Path $ExpectedIsoPath `
    -Bytes $ExpectedIsoBytes `
    -SHA256 $ExpectedIsoHash `
    -Label 'live ISO')

$CurrentNormalized = Get-NormalizedVBox `
    -Path $ExpectedVBoxPath `
    -Label 'current VBOX'
$BaselineNormalized = Get-NormalizedVBox `
    -Path $BaselineVBox.Path `
    -Label 'baseline VBOX'

if ($CurrentVBoxHash -ceq $BaselineVBox.SHA256) {
    throw 'current and baseline VBOX raw identities are unexpectedly equal'
}
if ($CurrentNormalized.NormalizedSHA256 -cne $ReportVBoxNormalized) {
    throw 'current normalized VBOX hash differs from inspector report'
}
if ($BaselineNormalized.NormalizedSHA256 -cne $ReportBaselineNormalized) {
    throw 'baseline normalized VBOX hash differs from inspector report'
}
if (
    $CurrentNormalized.NormalizedSHA256 -cne
    $BaselineNormalized.NormalizedSHA256
) {
    throw 'current and baseline normalized VBOX hashes differ'
}
if (-not [string]::Equals(
    $CurrentNormalized.NormalizedText,
    $BaselineNormalized.NormalizedText,
    [System.StringComparison]::Ordinal
)) {
    throw 'current and baseline normalized VBOX text differs'
}

$Report = [System.Collections.Generic.List[string]]::new()
$Report.Add('DBYTE-HOLYC-OPT')
$Report.Add('TEMPLEOSTS 1.10 VBOX DRIFT ADJUDICATION')
$Report.Add('')
$Report.Add("inspector_report_sha256`t$($InspectorIdentity.SHA256)")
$Report.Add("resource_commit`t$ExpectedResourceCommit")
$Report.Add('')
$Report.Add("target_name`t$ExpectedTargetName")
$Report.Add("target_uuid`t$ExpectedTargetUuid")
$Report.Add("vm_state`tpoweroff")
$Report.Add("live_vbox_path`t$ExpectedVBoxPath")
$Report.Add("live_vbox_bytes`t$($CurrentVBoxItem.Length)")
$Report.Add("live_vbox_sha256`t$CurrentVBoxHash")
$Report.Add("live_vbox_normalized_sha256`t$($CurrentNormalized.NormalizedSHA256)")
$Report.Add("live_last_state_change_count`t$($CurrentNormalized.LastStateChangeCount)")
$Report.Add("live_last_state_change`t$($CurrentNormalized.LastStateChange)")
$Report.Add('')
$Report.Add("baseline_vbox_path`t$($BaselineVBox.Path)")
$Report.Add("baseline_vbox_bytes`t$($BaselineVBox.Bytes)")
$Report.Add("baseline_vbox_sha256`t$($BaselineVBox.SHA256)")
$Report.Add("baseline_vbox_normalized_sha256`t$($BaselineNormalized.NormalizedSHA256)")
$Report.Add("baseline_last_state_change_count`t$($BaselineNormalized.LastStateChangeCount)")
$Report.Add("baseline_last_state_change`t$($BaselineNormalized.LastStateChange)")
$Report.Add('')
$Report.Add("normalized_text_equal`tTrue")
$Report.Add("live_vdi_sha256`t$ExpectedVdiHash")
$Report.Add("live_iso_sha256`t$ExpectedIsoHash")
$Report.Add('')
$Report.Add('The current and adopted baseline VBOX files have distinct raw identities.')
$Report.Add('After replacing exactly one lastStateChange attribute in each file, their full normalized text is ordinally equal.')
$Report.Add('No other VBOX difference is accepted by this adjudication.')
$Report.Add('No VM, attachment, VDI, ISO, guest file or compiler output was modified.')
$Report.Add('')
$Report.Add("VBOX DRIFT`tLASTSTATECHANGE-ONLY")
$Report.Add("RECOVERY INSPECTOR MODE`tPOST-OBSERVATION-REQUIRED")
$Report.Add("POWERED-OFF RECOVERY POINT`tNOT-SEALED")
$Report.Add("RESTORE EXECUTION`tNOT-OBSERVED")
$Report.Add("GUEST DELIVERY ROUTE`tUNRESOLVED")
$Report.Add("BUILD EXECUTION`tNOT-AUTHORIZED")
$Report.Add('')
$Report.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')

$Parent = Split-Path -Parent $Output
if ($Parent) {
    [void][System.IO.Directory]::CreateDirectory($Parent)
}
[System.IO.File]::WriteAllText(
    $Output,
    (($Report -join "`n") + "`n"),
    [System.Text.UTF8Encoding]::new($false)
)
$OutputHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

Write-Host "INSPECTOR REPORT:     $($InspectorIdentity.SHA256)"
Write-Host "TARGET NAME:          $ExpectedTargetName"
Write-Host "TARGET UUID:          $ExpectedTargetUuid"
Write-Host 'VM STATE:             poweroff'
Write-Host "LIVE VBOX:            $CurrentVBoxHash"
Write-Host "BASELINE VBOX:        $($BaselineVBox.SHA256)"
Write-Host "NORMALIZED VBOX:      $($CurrentNormalized.NormalizedSHA256)"
Write-Host "LIVE LASTSTATECHANGE: $($CurrentNormalized.LastStateChange)"
Write-Host "BASE LASTSTATECHANGE: $($BaselineNormalized.LastStateChange)"
Write-Host "VDI SHA256:           $ExpectedVdiHash"
Write-Host "ISO SHA256:           $ExpectedIsoHash"
Write-Host "REPORT:               $Output"
Write-Host "REPORT SHA256:        $OutputHash"
Write-Host 'VBOX DRIFT:           LASTSTATECHANGE-ONLY'
Write-Host 'RECOVERY MODE:        POST-OBSERVATION-REQUIRED'
Write-Host 'RECOVERY POINT:       NOT-SEALED'
Write-Host 'BUILD:                NOT-AUTHORIZED'
Write-Host 'VERDICT:              VBOX VOLATILE DRIFT ADJUDICATION COMPLETE'
