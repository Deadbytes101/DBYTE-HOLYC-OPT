[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VBoxManagePath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PreparedRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PreparedVerificationReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$BootAuthorizationReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedRoot =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r3'
$ExpectedPreparedVerificationReport =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r3-prepared-verification.txt'
$ExpectedPreparedVerificationHash =
    '26DC5258CF4692FD55EC95D81E48E3CFE05B4667BC20CDAC0CFFD58DC8433EF7'
$ExpectedBootAuthorizationReport =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r3-boot-authorization-adjudication.txt'
$ExpectedBootAuthorizationHash =
    'F8596A2CDECB75BE1FEC02377E9B6A428F15A3F4FC2C81D33F27A0CD962C3482'
$ExpectedOut =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r3-single-controlled-boot-attempt.txt'

$ExpectedVBoxVersion = '7.0.12r159484'
$ExpectedMachineName = 'Temple1.10'
$ExpectedMachineUuid = '9c98691e-27cd-4487-a306-587969c2c78c'
$ExpectedVdiUuid = '55c1f29d-a681-402e-b90d-bfbb6b09f207'

$ExpectedCurrentVBoxHash =
    '8EADB39D54CABE5E7B791E5D7E05BCF4CBBF32D4AB6B58291BEC0B2FAD607C0C'
$ExpectedPreviousVBoxHash =
    'C93D128227EE80B647DB63FE64277CEF1BDC61C224110472C73CBFFEC63877A7'
$ExpectedVdiHash =
    '90D453A94F075760A11E0772862E60C4B031ED874F28AA396EAE638F7EB8B31B'
$ExpectedIsoHash =
    'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'

$ExpectedCurrentVBoxId = '0X000000000000000000050000000609A1'
$ExpectedPreviousVBoxId = '0X000000000000000000040000000609A7'
$ExpectedVdiId = '0X000000000000000000010000000609A2'
$ExpectedIsoId = '0X000000000000000000010000000609A3'
$ExpectedRegistryHash =
    '99DB185525D245B1AAFF6937B459518089435882373A55CD2159D03FC82FDCBF'

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

function Assert-HashFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$SHA256,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "${Label} missing: $Path"
    }
    $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($Hash -cne $SHA256) {
        throw "${Label} SHA256 mismatch: observed=$Hash expected=$SHA256"
    }
    return $Hash
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
    [void](Assert-HashFile -Path $Path -SHA256 $SHA256 -Label $Label)
    $ObservedId = Get-FileId -Path $Path -Label $Label
    if ($ObservedId -cne $FileId) {
        throw "${Label} file-ID mismatch: observed=$ObservedId expected=$FileId"
    }
}

function Invoke-VBoxRead {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $OldEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $Captured = @(
            & $script:VBox @Arguments 2>&1 |
                ForEach-Object { [string]$_ }
        )
        $ExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $OldEap
    }
    if ($ExitCode -ne 0) {
        throw "${Label} failed exit=$ExitCode`n$($Captured -join "`n")"
    }
    return $Captured
}

function Invoke-VBoxSnapshotInventory {
    param(
        [Parameter(Mandatory = $true)][string]$Uuid,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $OldEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $Captured = @(
            & $script:VBox 'snapshot' $Uuid 'list' '--machinereadable' 2>&1 |
                ForEach-Object { [string]$_ }
        )
        $ExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $OldEap
    }
    if ($ExitCode -eq 0) {
        return $Captured
    }
    if (
        $Captured.Count -eq 1 -and
        $Captured[0].Trim() -ceq 'This machine does not have any snapshots'
    ) {
        return @()
    }
    throw "${Label} failed exit=$ExitCode`n$($Captured -join "`n")"
}

function Invoke-SingleStart {
    param([Parameter(Mandatory = $true)][string]$Uuid)

    $Allowed = @('startvm', $Uuid, '--type', 'gui')
    $OldEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $Captured = @(
            & $script:VBox @Allowed 2>&1 |
                ForEach-Object { [string]$_ }
        )
        $ExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $OldEap
    }
    return [pscustomobject]@{
        Arguments = ($Allowed -join ' ')
        ExitCode = $ExitCode
        Output = $Captured
    }
}

function ConvertFrom-VBoxMachineReadable {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines
    )
    $Result = @{}
    $Backslash = [string][char]92
    $Quote = [string][char]34
    $EscapedQuote = $Backslash + $Quote
    $EscapedBackslash = $Backslash + $Backslash
    foreach ($Line in $Lines) {
        $Equals = $Line.IndexOf('=')
        if ($Equals -le 0) {
            continue
        }
        $Key = $Line.Substring(0, $Equals)
        $Value = $Line.Substring($Equals + 1)
        if (
            $Key.Length -ge 2 -and
            $Key[0] -eq [char]34 -and
            $Key[$Key.Length - 1] -eq [char]34
        ) {
            $Key = $Key.Substring(1, $Key.Length - 2)
            $Key = $Key.Replace($EscapedQuote, $Quote).Replace(
                $EscapedBackslash,
                $Backslash
            )
        }
        if (
            $Value.Length -ge 2 -and
            $Value[0] -eq [char]34 -and
            $Value[$Value.Length - 1] -eq [char]34
        ) {
            $Value = $Value.Substring(1, $Value.Length - 2)
            $Value = $Value.Replace($EscapedQuote, $Quote).Replace(
                $EscapedBackslash,
                $Backslash
            )
        }
        if ([string]::IsNullOrWhiteSpace($Key)) {
            throw 'machine-readable key normalized to empty text'
        }
        if ($Result.ContainsKey($Key)) {
            throw "duplicate machine-readable key after normalization: $Key"
        }
        $Result[$Key] = [string]$Value
    }
    return $Result
}

function Get-RequiredMachineValue {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Info,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not $Info.ContainsKey($Key)) {
        throw "${Label} field missing: $Key"
    }
    return [string]$Info[$Key]
}

function Assert-MachineValue {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Info,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $Observed = Get-RequiredMachineValue -Info $Info -Key $Key -Label $Label
    if (-not [string]::Equals(
        $Observed,
        $Expected,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "${Label} field mismatch: $Key=$Observed expected=$Expected"
    }
}

function Get-ColonValue {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Key
    )
    $Pattern = '^\s*' + [regex]::Escape($Key) + ':\s*(?<value>.+?)\s*$'
    $Found = @($Lines | Where-Object { $_ -match $Pattern })
    if ($Found.Count -ne 1) {
        throw "medium field count mismatch: $Key count=$($Found.Count)"
    }
    return [regex]::Match($Found[0], $Pattern).Groups['value'].Value
}

function ConvertTo-NormalizedUuid {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $Trimmed = $Value.Trim().Trim('{', '}')
    $Parsed = [guid]::Empty
    if (-not [guid]::TryParse($Trimmed, [ref]$Parsed)) {
        throw "${Label} is not a UUID: $Value"
    }
    return $Parsed.ToString().ToLowerInvariant()
}

function Write-ResultReport {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$StartArguments,
        [Parameter(Mandatory = $true)][int]$StartExitCode,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$StartOutput,
        [AllowEmptyString()][string]$PostState = '',
        [AllowEmptyString()][string]$PostRunningCount = '',
        [AllowEmptyString()][string]$ErrorText = ''
    )
    if (Test-Path -LiteralPath $Path) {
        throw "boot-attempt report already exists: $Path"
    }
    $Lines = [System.Collections.Generic.List[string]]::new()
    $Lines.Add('DBYTE-HOLYC-OPT')
    $Lines.Add('TEMPLEOSTS 1.10 VDI-ONLY R3 SINGLE CONTROLLED BOOT ATTEMPT')
    $Lines.Add('')
    $Lines.Add("prepared_root`t$script:Root")
    $Lines.Add("prepared_verification_sha256`t$ExpectedPreparedVerificationHash")
    $Lines.Add("boot_authorization_sha256`t$ExpectedBootAuthorizationHash")
    $Lines.Add("machine_uuid`t$ExpectedMachineUuid")
    $Lines.Add("start_arguments`t$StartArguments")
    $Lines.Add("start_exit_code`t$StartExitCode")
    foreach ($Line in $StartOutput) {
        $Lines.Add("start_output`t$Line")
    }
    $Lines.Add("post_start_vm_state`t$PostState")
    $Lines.Add("post_start_running_vm_rows`t$PostRunningCount")
    if (-not [string]::IsNullOrWhiteSpace($ErrorText)) {
        $Lines.Add("error`t$ErrorText")
    }
    $Lines.Add('')
    $Lines.Add("VBOXMANAGE`tSTARTVM-ONCE-PLUS-READ-ONLY-OBSERVATION")
    $Lines.Add("CONFIGURATION MUTATION`tNOT-EXECUTED")
    $Lines.Add("STORAGE MUTATION`tNOT-EXECUTED")
    $Lines.Add("SNAPSHOT MUTATION`tNOT-EXECUTED")
    $Lines.Add("CONTROLVM`tNOT-EXECUTED")
    $Lines.Add("GUESTCONTROL`tNOT-EXECUTED")
    $Lines.Add("COMPILER BUILD`tNOT-EXECUTED")
    $Lines.Add("GUEST VISUAL BOOT`tNOT-OBSERVED-BY-HOST-SCRIPT")
    $Lines.Add("BOOT ATTEMPT STATUS`t$Status")
    $Lines.Add('')
    $Lines.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')
    [System.IO.File]::WriteAllText(
        $Path,
        (($Lines.ToArray() -join "`n") + "`n"),
        [System.Text.UTF8Encoding]::new($false)
    )
}

$script:VBox = (Resolve-Path -LiteralPath $VBoxManagePath -ErrorAction Stop).Path
$script:Root = (Resolve-Path -LiteralPath $PreparedRoot -ErrorAction Stop).Path
$PreparedVerification = (
    Resolve-Path -LiteralPath $PreparedVerificationReportPath -ErrorAction Stop
).Path
$BootAuthorization = (
    Resolve-Path -LiteralPath $BootAuthorizationReportPath -ErrorAction Stop
).Path
$Output = Get-FullPath -Path $OutPath

Assert-PathEquals -Observed $script:Root -Expected $ExpectedRoot -Label 'prepared r3 root'
Assert-PathEquals -Observed $PreparedVerification -Expected $ExpectedPreparedVerificationReport -Label 'prepared verification report'
Assert-PathEquals -Observed $BootAuthorization -Expected $ExpectedBootAuthorizationReport -Label 'boot authorization report'
Assert-PathEquals -Observed $Output -Expected $ExpectedOut -Label 'boot attempt report'
if (Test-Path -LiteralPath $Output) {
    throw "boot attempt report already exists: $Output"
}
$OutputParent = Split-Path -Parent $Output
if (-not (Test-Path -LiteralPath $OutputParent -PathType Container)) {
    throw "boot attempt report parent missing: $OutputParent"
}

[void](Assert-HashFile -Path $PreparedVerification -SHA256 $ExpectedPreparedVerificationHash -Label 'prepared verification report')
[void](Assert-HashFile -Path $BootAuthorization -SHA256 $ExpectedBootAuthorizationHash -Label 'boot authorization report')

$MachineRoot = Join-Path $script:Root 'Machine'
$HomeRoot = Join-Path $script:Root 'VBoxUserHome'
$CurrentVBox = Join-Path $MachineRoot 'Temple1.10.vbox'
$PreviousVBox = Join-Path $MachineRoot 'Temple1.10.vbox-prev'
$Vdi = Join-Path $MachineRoot 'Temple1.10.vdi'
$Iso = Join-Path $MachineRoot 'TempleOSTS.iso'
$Registry = Join-Path $HomeRoot 'VirtualBox.xml'

Assert-FileState -Path $CurrentVBox -SHA256 $ExpectedCurrentVBoxHash -FileId $ExpectedCurrentVBoxId -Label 'r3 current VBOX before start'
Assert-FileState -Path $PreviousVBox -SHA256 $ExpectedPreviousVBoxHash -FileId $ExpectedPreviousVBoxId -Label 'r3 previous VBOX before start'
Assert-FileState -Path $Vdi -SHA256 $ExpectedVdiHash -FileId $ExpectedVdiId -Label 'r3 VDI before start'
Assert-FileState -Path $Iso -SHA256 $ExpectedIsoHash -FileId $ExpectedIsoId -Label 'r3 ISO before start'
[void](Assert-HashFile -Path $Registry -SHA256 $ExpectedRegistryHash -Label 'r3 isolated registry before start')

$OriginalVBoxUserHome = [Environment]::GetEnvironmentVariable(
    'VBOX_USER_HOME',
    [EnvironmentVariableTarget]::Process
)
if (-not [string]::IsNullOrEmpty($OriginalVBoxUserHome)) {
    throw "process VBOX_USER_HOME must be unset: $OriginalVBoxUserHome"
}
$ExistingService = @(Get-Process -Name 'VBoxSVC' -ErrorAction SilentlyContinue)
if ($ExistingService.Count -ne 0) {
    throw "VBoxSVC already running before controlled start; PIDs=$($ExistingService.Id -join ',')"
}

$StartIssued = $false
$StartArguments = 'NOT-ISSUED'
$StartExitCode = -1
$StartOutput = @()
$PostState = ''
$PostRunningCount = ''

[Environment]::SetEnvironmentVariable(
    'VBOX_USER_HOME',
    $HomeRoot,
    [EnvironmentVariableTarget]::Process
)
try {
    $Version = @(Invoke-VBoxRead -Arguments @('--version') -Label 'pre-start VirtualBox version')
    if ($Version.Count -ne 1 -or $Version[0] -cne $ExpectedVBoxVersion) {
        throw "VirtualBox version mismatch: $($Version -join '|')"
    }

    $Registered = @(Invoke-VBoxRead -Arguments @('list', 'vms') -Label 'pre-start registered inventory')
    $Running = @(Invoke-VBoxRead -Arguments @('list', 'runningvms') -Label 'pre-start running inventory')
    $NonEmptyRegistered = @($Registered | Where-Object { $_ -cne '' })
    $NonEmptyRunning = @($Running | Where-Object { $_ -cne '' })
    $TargetPattern = '^"' + [regex]::Escape($ExpectedMachineName) + '" \{' + [regex]::Escape($ExpectedMachineUuid) + '\}$'
    if (
        $NonEmptyRegistered.Count -ne 1 -or
        @($NonEmptyRegistered | Where-Object { $_ -match $TargetPattern }).Count -ne 1
    ) {
        throw 'pre-start registered inventory mismatch'
    }
    if ($NonEmptyRunning.Count -ne 0) {
        throw "pre-start running inventory is not zero: $($NonEmptyRunning.Count)"
    }

    $Show = @(Invoke-VBoxRead -Arguments @('showvminfo', $ExpectedMachineUuid, '--machinereadable') -Label 'pre-start showvminfo')
    $Info = ConvertFrom-VBoxMachineReadable -Lines $Show
    Assert-MachineValue -Info $Info -Key 'name' -Expected $ExpectedMachineName -Label 'pre-start target'
    Assert-MachineValue -Info $Info -Key 'UUID' -Expected $ExpectedMachineUuid -Label 'pre-start target'
    Assert-MachineValue -Info $Info -Key 'VMState' -Expected 'poweroff' -Label 'pre-start target'
    Assert-MachineValue -Info $Info -Key 'CfgFile' -Expected $CurrentVBox -Label 'pre-start target'
    Assert-MachineValue -Info $Info -Key 'IDE-1-0' -Expected $Vdi -Label 'pre-start target'
    Assert-MachineValue -Info $Info -Key 'boot1' -Expected 'disk' -Label 'pre-start target'
    Assert-MachineValue -Info $Info -Key 'boot2' -Expected 'none' -Label 'pre-start target'
    Assert-MachineValue -Info $Info -Key 'boot3' -Expected 'none' -Label 'pre-start target'
    Assert-MachineValue -Info $Info -Key 'boot4' -Expected 'none' -Label 'pre-start target'
    Assert-MachineValue -Info $Info -Key 'clipboard' -Expected 'disabled' -Label 'pre-start target'
    Assert-MachineValue -Info $Info -Key 'draganddrop' -Expected 'disabled' -Label 'pre-start target'
    Assert-MachineValue -Info $Info -Key 'graphicscontroller' -Expected 'vboxvga' -Label 'pre-start target'
    Assert-MachineValue -Info $Info -Key 'vram' -Expected '9' -Label 'pre-start target'

    $NicKeys = @($Info.Keys | Where-Object { $_ -match '^nic[1-8]$' })
    if ($NicKeys.Count -le 0) {
        throw 'pre-start target exposes no NIC fields'
    }
    foreach ($Key in $NicKeys) {
        Assert-MachineValue -Info $Info -Key $Key -Expected 'none' -Label 'pre-start target'
    }
    $SharedKeys = @(
        $Info.Keys | Where-Object {
            $_ -like 'SharedFolderNameMachineMapping*' -or
            $_ -like 'SharedFolderPathMachineMapping*'
        }
    )
    if ($SharedKeys.Count -ne 0) {
        throw "pre-start shared-folder key count is not zero: $($SharedKeys.Count)"
    }
    if ($Info.ContainsKey('IDE-0-1')) {
        Assert-MachineValue -Info $Info -Key 'IDE-0-1' -Expected 'none' -Label 'pre-start target'
    }

    $Snapshots = @(Invoke-VBoxSnapshotInventory -Uuid $ExpectedMachineUuid -Label 'pre-start snapshots')
    if (@($Snapshots | Where-Object { $_ -match '^Snapshot(Name|UUID|Node)' }).Count -ne 0) {
        throw 'pre-start snapshot rows are not zero'
    }

    $VdiMedium = @(Invoke-VBoxRead -Arguments @('showmediuminfo', 'disk', $Vdi) -Label 'pre-start VDI medium')
    $ObservedVdiUuid = ConvertTo-NormalizedUuid -Value (Get-ColonValue -Lines $VdiMedium -Key 'UUID') -Label 'pre-start VDI UUID'
    if ($ObservedVdiUuid -cne $ExpectedVdiUuid) {
        throw "pre-start VDI UUID mismatch: $ObservedVdiUuid"
    }

    [void](Assert-HashFile -Path $Registry -SHA256 $ExpectedRegistryHash -Label 'r3 isolated registry after pre-start reads')
    Assert-FileState -Path $CurrentVBox -SHA256 $ExpectedCurrentVBoxHash -FileId $ExpectedCurrentVBoxId -Label 'r3 current VBOX at start boundary'
    Assert-FileState -Path $PreviousVBox -SHA256 $ExpectedPreviousVBoxHash -FileId $ExpectedPreviousVBoxId -Label 'r3 previous VBOX at start boundary'
    Assert-FileState -Path $Vdi -SHA256 $ExpectedVdiHash -FileId $ExpectedVdiId -Label 'r3 VDI at start boundary'
    Assert-FileState -Path $Iso -SHA256 $ExpectedIsoHash -FileId $ExpectedIsoId -Label 'r3 ISO at start boundary'

    Write-Host 'START BOUNDARY:         ALL PRE-START GATES PASSED'
    Write-Host 'AUTHORIZED MUTATION:    startvm TARGET --type gui / ONCE'
    Write-Host 'ROLLBACK MUTATION:      NONE'

    $Start = Invoke-SingleStart -Uuid $ExpectedMachineUuid
    $StartIssued = $true
    $StartArguments = $Start.Arguments
    $StartExitCode = [int]$Start.ExitCode
    $StartOutput = @($Start.Output)

    if ($StartExitCode -ne 0) {
        throw "startvm failed exit=$StartExitCode output=$($StartOutput -join ' | ')"
    }

    $PostShow = @(Invoke-VBoxRead -Arguments @('showvminfo', $ExpectedMachineUuid, '--machinereadable') -Label 'post-start showvminfo')
    $PostInfo = ConvertFrom-VBoxMachineReadable -Lines $PostShow
    $PostState = Get-RequiredMachineValue -Info $PostInfo -Key 'VMState' -Label 'post-start target'
    $PostRunning = @(Invoke-VBoxRead -Arguments @('list', 'runningvms') -Label 'post-start running inventory')
    $PostNonEmptyRunning = @($PostRunning | Where-Object { $_ -cne '' })
    $PostRunningCount = [string]$PostNonEmptyRunning.Count
    if (-not [string]::Equals($PostState, 'running', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "post-start VMState is not running: $PostState"
    }
    if (
        $PostNonEmptyRunning.Count -ne 1 -or
        @($PostNonEmptyRunning | Where-Object { $_ -match $TargetPattern }).Count -ne 1
    ) {
        throw "post-start running inventory mismatch: $($PostNonEmptyRunning -join ' | ')"
    }

    Write-ResultReport `
        -Path $Output `
        -Status 'START-ACCEPTED-HOST-RUNNING' `
        -StartArguments $StartArguments `
        -StartExitCode $StartExitCode `
        -StartOutput $StartOutput `
        -PostState $PostState `
        -PostRunningCount $PostRunningCount

    $ReportHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash
    Write-Host "START COMMAND:          $StartArguments"
    Write-Host "START EXIT CODE:        $StartExitCode"
    Write-Host "POST-START VM STATE:    $PostState"
    Write-Host "POST-START RUNNING VMS: $PostRunningCount"
    Write-Host "REPORT:                 $Output"
    Write-Host "REPORT SHA256:          $ReportHash"
    Write-Host 'GUEST VISUAL BOOT:      NOT-OBSERVED-BY-HOST-SCRIPT'
    Write-Host 'CONTROLVM:              NOT-EXECUTED'
    Write-Host 'BUILD:                  NOT-EXECUTED'
    Write-Host 'VERDICT:                START ACCEPTED / HOST RUNNING / VISUAL PROOF PENDING'
}
catch {
    $ErrorText = $_.Exception.Message
    if ($StartIssued -and -not (Test-Path -LiteralPath $Output)) {
        try {
            Write-ResultReport `
                -Path $Output `
                -Status 'START-ISSUED-POST-OBSERVATION-FAILED' `
                -StartArguments $StartArguments `
                -StartExitCode $StartExitCode `
                -StartOutput $StartOutput `
                -PostState $PostState `
                -PostRunningCount $PostRunningCount `
                -ErrorText $ErrorText
            $FailureHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash
            Write-Host "BOOT ATTEMPT FAILURE REPORT: $Output"
            Write-Host "BOOT ATTEMPT FAILURE SHA256: $FailureHash"
        }
        catch {
        }
    }
    throw
}
finally {
    [Environment]::SetEnvironmentVariable(
        'VBOX_USER_HOME',
        $OriginalVBoxUserHome,
        [EnvironmentVariableTarget]::Process
    )
}
