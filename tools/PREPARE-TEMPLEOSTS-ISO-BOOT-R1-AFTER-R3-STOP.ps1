[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$VBoxManagePath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$R3Root,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$R3StopReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$SealedRehearsalRoot,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RehearsalVerificationReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$BootReadinessReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$IsoBootRoot,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedVBoxManage = 'D:\Portable-VirtualBox7\app64\VBoxManage.exe'
$ExpectedR3Root = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r3'
$ExpectedR3StopReport = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r3-controlled-stop-after-no-boot.txt'
$ExpectedSealedRoot = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-REHEARSAL\templeosts-1.10-isolated-r1'
$ExpectedVerificationReport = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-isolated-rehearsal-verification.txt'
$ExpectedVerificationHash = 'F16F263F1A9217022F24FC318DC0CB4A9BEAFA295723AFB889C043EF428E51E8'
$ExpectedReadinessReport = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-isolated-boot-readiness-adjudication.txt'
$ExpectedReadinessHash = 'C96EA11818CCEF207D914F165CD6B5822ADFC71B4712E7025371E085D3627461'
$ExpectedIsoBootRoot = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-iso-boot-r1'
$ExpectedOut = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-iso-boot-r1-preparation.txt'

$ExpectedSecondAttemptHash = 'E6780E727989B974727402F782CA16B1B870FBF05591FACA6D131F6244F71430'
$ExpectedSealedManifestHash = 'AC2609C9C6EFC87316835BB6A4174AF5C28FEEE8DCEBD37E0E9D3DADB14D383F'
$ExpectedSealedVBoxHash = '69224A832694CA0C657CA2135ED370F6B7E667B84F93C08D921AED4A6D21F39B'
$ExpectedVdiHash = '90D453A94F075760A11E0772862E60C4B031ED874F28AA396EAE638F7EB8B31B'
$ExpectedIsoHash = 'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$ExpectedVdiBytes = 2097152L
$ExpectedIsoBytes = 30558208L
$ExpectedSealedVBoxId = '0X0000000000000000000100000006010A'
$ExpectedSealedVdiId = '0X0000000000000000000100000006010B'
$ExpectedSealedIsoId = '0X0000000000000000000100000006010C'

$ExpectedMachineName = 'Temple1.10'
$ExpectedMachineUuid = '9c98691e-27cd-4487-a306-587969c2c78c'
$ExpectedVdiUuid = '55c1f29d-a681-402e-b90d-bfbb6b09f207'
$ExpectedIsoUuid = 'ab97b3a5-1331-494d-a917-e85b6e728c45'
$ExpectedVBoxVersion = '7.0.12r159484'
$ExpectedDriverPath = 'D:\Portable-VirtualBox7\app64\drivers\vboxsup\VBoxSup.sys'
$ExpectedDriverHash = '3344E2909580A9965E38B26AB9E9958842315DDEA1B0D0E274DA314DDCAB97F4'
$ScPath = Join-Path $env:SystemRoot 'System32\sc.exe'
$FsutilPath = Join-Path $env:SystemRoot 'System32\fsutil.exe'

function Get-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath(
        [Environment]::ExpandEnvironmentVariables($Path)
    ).TrimEnd([char]92, [char]47)
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
    )) { throw "${Label} mismatch: observed=$Observed expected=$Expected" }
}

function Assert-OutsideRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $Full = Get-FullPath -Path $Path
    $RootFull = Get-FullPath -Path $Root
    $Prefix = $RootFull + [System.IO.Path]::DirectorySeparatorChar
    if (
        [string]::Equals($Full, $RootFull, [System.StringComparison]::OrdinalIgnoreCase) -or
        $Full.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)
    ) { throw "${Label} is inside forbidden root: $RootFull" }
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $OldEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $Rows = @(& $FilePath @Arguments 2>&1 | ForEach-Object { [string]$_ })
        $ExitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $OldEap }
    return [pscustomobject]@{ Label=$Label; ExitCode=[int]$ExitCode; Output=[string[]]$Rows }
}

function Require-NativeSuccess {
    param([Parameter(Mandatory = $true)][object]$Result)
    if ($Result.ExitCode -ne 0) {
        throw "$($Result.Label) failed exit=$($Result.ExitCode) output=$($Result.Output -join ' | ')"
    }
}

function Assert-ExactFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][long]$Bytes,
        [Parameter(Mandatory = $true)][string]$Hash,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "${Label} missing: $Path" }
    $Item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($Item.Length -ne $Bytes) { throw "${Label} bytes mismatch: $($Item.Length) expected=$Bytes" }
    $ObservedHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($ObservedHash -cne $Hash) { throw "${Label} SHA256 mismatch: $ObservedHash expected=$Hash" }
    return $Item.FullName
}

function Assert-Hash {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Hash,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "${Label} missing: $Path" }
    $Observed = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($Observed -cne $Hash) { throw "${Label} SHA256 mismatch: $Observed expected=$Hash" }
    return (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
}

function Get-FileId {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Label)
    $Result = Invoke-Native -FilePath $FsutilPath -Arguments @('file','queryfileid',$Path) -Label "fsutil $Label"
    Require-NativeSuccess -Result $Result
    $Ids = @([regex]::Matches(($Result.Output -join "`n"), '(?i)0x[0-9a-f]+') | ForEach-Object { $_.Value.ToUpperInvariant() })
    if ($Ids.Count -ne 1) { throw "${Label} file ID count mismatch: $($Ids.Count)" }
    return $Ids[0]
}

function Require-VBoxSupRunning {
    $Result = Invoke-Native -FilePath $ScPath -Arguments @('query','VBoxSup') -Label 'sc query VBoxSup'
    Require-NativeSuccess -Result $Result
    if (($Result.Output -join "`n") -notmatch '(?im)^\s*STATE\s*:\s*4\b') { throw 'VBoxSup STATE 4 not observed' }
}

function Convert-MachineReadable {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Rows)
    $Map = @{}
    $Slash = [string][char]92
    $DoubleSlash = $Slash + $Slash
    $EscapedQuote = $Slash + [string][char]34
    foreach ($Row in $Rows) {
        if ($Row -notmatch '^([^=]+)=(.*)$') { continue }
        $Key = [string]$Matches[1]
        $Value = [string]$Matches[2]
        if ($Key.Length -ge 2 -and $Key[0] -eq [char]34 -and $Key[$Key.Length-1] -eq [char]34) {
            $Key = $Key.Substring(1,$Key.Length-2).Replace($EscapedQuote,[string][char]34).Replace($DoubleSlash,$Slash)
        }
        if ($Value.Length -ge 2 -and $Value[0] -eq [char]34 -and $Value[$Value.Length-1] -eq [char]34) {
            $Value = $Value.Substring(1,$Value.Length-2).Replace($EscapedQuote,[string][char]34).Replace($DoubleSlash,$Slash)
        }
        if ([string]::IsNullOrWhiteSpace($Key)) { throw 'machine-readable key normalized empty' }
        if ($Map.ContainsKey($Key)) { throw "duplicate machine-readable key: $Key" }
        $Map[$Key] = $Value
    }
    return $Map
}

function Require-MapValue {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Map,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not $Map.ContainsKey($Key)) { throw "${Label} missing key: $Key" }
    $Observed = [string]$Map[$Key]
    if (-not [string]::Equals($Observed,$Expected,[System.StringComparison]::OrdinalIgnoreCase)) {
        throw "${Label} mismatch: $Key=$Observed expected=$Expected"
    }
}

function Get-TabValue {
    param([Parameter(Mandatory = $true)][string[]]$Lines,[Parameter(Mandatory = $true)][string]$Key)
    $Prefix = $Key + "`t"
    $Matches = @($Lines | Where-Object { $_.StartsWith($Prefix,[System.StringComparison]::Ordinal) })
    if ($Matches.Count -ne 1) { throw "report field count mismatch: $Key count=$($Matches.Count)" }
    return $Matches[0].Substring($Prefix.Length)
}

function Wait-VBoxSVCExit {
    param([int]$Seconds = 30)
    $Deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    while ([DateTime]::UtcNow -lt $Deadline) {
        if (@(Get-Process -Name 'VBoxSVC' -ErrorAction SilentlyContinue).Count -eq 0) { return }
        Start-Sleep -Milliseconds 250
    }
    $Pids = @(Get-Process -Name 'VBoxSVC' -ErrorAction SilentlyContinue).Id
    throw "VBoxSVC did not exit: $($Pids -join ',')"
}

function Get-DvdControllerName {
    param([Parameter(Mandatory = $true)][string]$VBoxPath)
    [xml]$Xml = [System.IO.File]::ReadAllText($VBoxPath)
    $Found = [System.Collections.Generic.List[string]]::new()
    foreach ($Controller in @($Xml.SelectNodes("//*[local-name()='StorageController']"))) {
        foreach ($Device in @($Controller.SelectNodes("./*[local-name()='AttachedDevice']"))) {
            if ($Device.GetAttribute('type') -ceq 'DVD' -and $Device.GetAttribute('port') -ceq '0' -and $Device.GetAttribute('device') -ceq '1') {
                $Name = $Controller.GetAttribute('name')
                if ([string]::IsNullOrWhiteSpace($Name)) { throw 'DVD controller name empty' }
                $Found.Add($Name)
            }
        }
    }
    if ($Found.Count -ne 1) { throw "DVD controller match count mismatch: $($Found.Count)" }
    return $Found[0]
}

function Get-SnapshotRows {
    param([Parameter(Mandatory = $true)][string]$VBox,[Parameter(Mandatory = $true)][string]$Uuid)
    $Result = Invoke-Native -FilePath $VBox -Arguments @('snapshot',$Uuid,'list','--machinereadable') -Label 'snapshot list'
    if ($Result.ExitCode -eq 0) { return [string[]]@($Result.Output | Where-Object { $_.Trim().Length -gt 0 }) }
    if (($Result.Output -join "`n") -match '(?i)does not have any snapshots') { return [string[]]@() }
    throw "snapshot list failed exit=$($Result.ExitCode) output=$($Result.Output -join ' | ')"
}

function Write-Lines {
    param([Parameter(Mandatory = $true)][string]$Path,[Parameter(Mandatory = $true)][string[]]$Lines)
    [System.IO.File]::WriteAllText($Path,(($Lines -join "`n")+"`n"),[System.Text.UTF8Encoding]::new($false))
}

foreach ($Exe in @($VBoxManagePath,$ScPath,$FsutilPath,$ExpectedDriverPath)) {
    if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) { throw "required file missing: $Exe" }
}

$VBox = (Resolve-Path -LiteralPath $VBoxManagePath -ErrorAction Stop).Path
$ResolvedR3 = (Resolve-Path -LiteralPath $R3Root -ErrorAction Stop).Path
$StopReport = (Resolve-Path -LiteralPath $R3StopReportPath -ErrorAction Stop).Path
$Sealed = (Resolve-Path -LiteralPath $SealedRehearsalRoot -ErrorAction Stop).Path
$Verification = (Resolve-Path -LiteralPath $RehearsalVerificationReportPath -ErrorAction Stop).Path
$Readiness = (Resolve-Path -LiteralPath $BootReadinessReportPath -ErrorAction Stop).Path
$NewRoot = Get-FullPath -Path $IsoBootRoot
$Output = Get-FullPath -Path $OutPath

Assert-PathEquals -Observed $VBox -Expected $ExpectedVBoxManage -Label 'VBoxManage'
Assert-PathEquals -Observed $ResolvedR3 -Expected $ExpectedR3Root -Label 'R3 root'
Assert-PathEquals -Observed $StopReport -Expected $ExpectedR3StopReport -Label 'R3 stop report'
Assert-PathEquals -Observed $Sealed -Expected $ExpectedSealedRoot -Label 'sealed rehearsal root'
Assert-PathEquals -Observed $Verification -Expected $ExpectedVerificationReport -Label 'verification report'
Assert-PathEquals -Observed $Readiness -Expected $ExpectedReadinessReport -Label 'readiness report'
Assert-PathEquals -Observed $NewRoot -Expected $ExpectedIsoBootRoot -Label 'ISO boot root'
Assert-PathEquals -Observed $Output -Expected $ExpectedOut -Label 'preparation report'
Assert-OutsideRoot -Path $NewRoot -Root $ResolvedR3 -Label 'new ISO root'
Assert-OutsideRoot -Path $NewRoot -Root $Sealed -Label 'new ISO root'
if (Test-Path -LiteralPath $NewRoot) { throw "ISO boot root already exists: $NewRoot" }
if (Test-Path -LiteralPath $Output) { throw "ISO preparation report already exists: $Output" }

[void](Assert-Hash -Path $Verification -Hash $ExpectedVerificationHash -Label 'rehearsal verification report')
[void](Assert-Hash -Path $Readiness -Hash $ExpectedReadinessHash -Label 'boot readiness report')
$StopLines = [System.IO.File]::ReadAllLines($StopReport)
if ((Get-TabValue -Lines $StopLines -Key 'second_attempt_report_sha256') -cne $ExpectedSecondAttemptHash) { throw 'R3 stop report second-attempt binding mismatch' }
if ((Get-TabValue -Lines $StopLines -Key 'poweroff_exit_code') -cne '0') { throw 'R3 stop report poweroff exit is not zero' }
if ((Get-TabValue -Lines $StopLines -Key 'CONTROLVM') -cne 'POWEROFF-ONCE') { throw 'R3 stop report controlvm field mismatch' }
if ((Get-TabValue -Lines $StopLines -Key 'STATUS') -cne 'R3-POWERED-OFF-PRESERVED') { throw 'R3 stop report status mismatch' }
$StopReportHash = (Get-FileHash -LiteralPath $StopReport -Algorithm SHA256).Hash

[void](Assert-Hash -Path $ExpectedDriverPath -Hash $ExpectedDriverHash -Label 'VBoxSup.sys')
Require-VBoxSupRunning

$SealedManifest = Assert-Hash -Path (Join-Path $Sealed 'ISOLATED-REHEARSAL-MANIFEST.txt') -Hash $ExpectedSealedManifestHash -Label 'sealed rehearsal manifest'
$SealedMachine = Join-Path $Sealed 'Machine'
$SealedVBox = Assert-Hash -Path (Join-Path $SealedMachine 'Temple1.10.vbox') -Hash $ExpectedSealedVBoxHash -Label 'sealed VBOX'
$SealedVdi = Assert-ExactFile -Path (Join-Path $SealedMachine 'Temple1.10.vdi') -Bytes $ExpectedVdiBytes -Hash $ExpectedVdiHash -Label 'sealed VDI'
$SealedIso = Assert-ExactFile -Path (Join-Path $SealedMachine 'TempleOSTS.iso') -Bytes $ExpectedIsoBytes -Hash $ExpectedIsoHash -Label 'sealed ISO'
if ((Get-FileId -Path $SealedVBox -Label 'sealed VBOX') -cne $ExpectedSealedVBoxId) { throw 'sealed VBOX file ID mismatch' }
if ((Get-FileId -Path $SealedVdi -Label 'sealed VDI') -cne $ExpectedSealedVdiId) { throw 'sealed VDI file ID mismatch' }
if ((Get-FileId -Path $SealedIso -Label 'sealed ISO') -cne $ExpectedSealedIsoId) { throw 'sealed ISO file ID mismatch' }

$OriginalHome = [Environment]::GetEnvironmentVariable('VBOX_USER_HOME',[EnvironmentVariableTarget]::Process)
if (-not [string]::IsNullOrEmpty($OriginalHome)) { throw "process VBOX_USER_HOME must be unset: $OriginalHome" }

$R3Home = Join-Path $ResolvedR3 'VBoxUserHome'
[Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$R3Home,[EnvironmentVariableTarget]::Process)
try {
    $R3Running = Invoke-Native -FilePath $VBox -Arguments @('list','runningvms') -Label 'R3 running inventory after stop'
    Require-NativeSuccess -Result $R3Running
    if (@($R3Running.Output | Where-Object { $_.Trim().Length -gt 0 }).Count -ne 0) { throw 'R3 still has running VM rows' }
    $R3InfoResult = Invoke-Native -FilePath $VBox -Arguments @('showvminfo',$ExpectedMachineUuid,'--machinereadable') -Label 'R3 showvminfo after stop'
    Require-NativeSuccess -Result $R3InfoResult
    $R3Info = Convert-MachineReadable -Rows $R3InfoResult.Output
    Require-MapValue -Map $R3Info -Key 'VMState' -Expected 'poweroff' -Label 'R3 post-stop state'
}
finally {
    [Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$null,[EnvironmentVariableTarget]::Process)
}
Wait-VBoxSVCExit

$MachineRoot = Join-Path $NewRoot 'Machine'
$NewHome = Join-Path $NewRoot 'VBoxUserHome'
$BootVBox = Join-Path $MachineRoot 'Temple1.10.vbox'
$BootVdi = Join-Path $MachineRoot 'Temple1.10.vdi'
$BootIso = Join-Path $MachineRoot 'TempleOSTS.iso'
$ManifestPath = Join-Path $NewRoot 'ISO-BOOT-R1-MANIFEST.txt'
$IncompletePath = Join-Path $NewRoot 'ISO-BOOT-R1-INCOMPLETE.txt'
$RootCreated = $false
$Registered = $false
$Steps = [System.Collections.Generic.List[string]]::new()

try {
    [void][System.IO.Directory]::CreateDirectory($MachineRoot)
    [void][System.IO.Directory]::CreateDirectory($NewHome)
    $RootCreated = $true
    Write-Lines -Path $IncompletePath -Lines @(
        'DBYTE-HOLYC-OPT',
        'TEMPLEOSTS 1.10 ISO BOOT R1 PREPARATION INCOMPLETE',
        '',
        ('created_utc' + "`t" + [DateTimeOffset]::UtcNow.ToString('o')),
        ('process_id' + "`t" + $PID),
        '',
        'PRESERVE THIS ROOT IF PREPARATION FAILS.'
    )

    Copy-Item -LiteralPath $SealedVBox -Destination $BootVBox -ErrorAction Stop
    Copy-Item -LiteralPath $SealedVdi -Destination $BootVdi -ErrorAction Stop
    Copy-Item -LiteralPath $SealedIso -Destination $BootIso -ErrorAction Stop
    $Steps.Add('COPY-SEALED-VBOX-VDI-ISO')

    [void](Assert-Hash -Path $BootVBox -Hash $ExpectedSealedVBoxHash -Label 'copied VBOX before rewrite')
    [void](Assert-ExactFile -Path $BootVdi -Bytes $ExpectedVdiBytes -Hash $ExpectedVdiHash -Label 'copied VDI')
    [void](Assert-ExactFile -Path $BootIso -Bytes $ExpectedIsoBytes -Hash $ExpectedIsoHash -Label 'copied ISO')
    $BootVdiId = Get-FileId -Path $BootVdi -Label 'copied VDI'
    $BootIsoId = Get-FileId -Path $BootIso -Label 'copied ISO'
    if ($BootVdiId -ceq $ExpectedSealedVdiId) { throw 'copied VDI file object not distinct from sealed VDI' }
    if ($BootIsoId -ceq $ExpectedSealedIsoId) { throw 'copied ISO file object not distinct from sealed ISO' }

    $VBoxText = [System.IO.File]::ReadAllText($BootVBox)
    $OldVdiCount = [regex]::Matches($VBoxText,[regex]::Escape($SealedVdi)).Count
    $OldIsoCount = [regex]::Matches($VBoxText,[regex]::Escape($SealedIso)).Count
    if ($OldVdiCount -ne 1 -or $OldIsoCount -ne 1) { throw "copied VBOX media path count mismatch: vdi=$OldVdiCount iso=$OldIsoCount" }
    $VBoxText = $VBoxText.Replace($SealedVdi,$BootVdi).Replace($SealedIso,$BootIso)
    if ($VBoxText.Contains($SealedVdi) -or $VBoxText.Contains($SealedIso)) { throw 'sealed media path remained after rewrite' }
    [System.IO.File]::WriteAllText($BootVBox,$VBoxText,[System.Text.UTF8Encoding]::new($false))
    $Steps.Add('REWRITE-COPY-MEDIA-PATHS')
    $DvdController = Get-DvdControllerName -VBoxPath $BootVBox

    [Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$NewHome,[EnvironmentVariableTarget]::Process)
    try {
        $Version = Invoke-Native -FilePath $VBox -Arguments @('--version') -Label 'ISO copy VBoxManage version'
        Require-NativeSuccess -Result $Version
        if ($Version.Output.Count -ne 1 -or $Version.Output[0].Trim() -cne $ExpectedVBoxVersion) { throw "VirtualBox version mismatch: $($Version.Output -join '|')" }
        $BeforeList = Invoke-Native -FilePath $VBox -Arguments @('list','vms') -Label 'empty isolated registry'
        Require-NativeSuccess -Result $BeforeList
        if (@($BeforeList.Output | Where-Object { $_.Trim().Length -gt 0 }).Count -ne 0) { throw 'new isolated registry is not empty' }

        $Register = Invoke-Native -FilePath $VBox -Arguments @('registervm',$BootVBox) -Label 'register ISO boot copy'
        Require-NativeSuccess -Result $Register
        $Registered = $true
        $Steps.Add('REGISTER-COPY-ISOLATED')

        $ModifyBoot = Invoke-Native -FilePath $VBox -Arguments @('modifyvm',$ExpectedMachineUuid,'--boot1','dvd','--boot2','disk','--boot3','none','--boot4','none') -Label 'set ISO-first boot order'
        Require-NativeSuccess -Result $ModifyBoot
        $Steps.Add('SET-BOOT-DVD-DISK-NONE-NONE')

        for ($Index=1; $Index -le 8; $Index++) {
            $Nic = Invoke-Native -FilePath $VBox -Arguments @('modifyvm',$ExpectedMachineUuid,"--nic$Index",'none') -Label "disable NIC $Index"
            Require-NativeSuccess -Result $Nic
        }
        $Steps.Add('DISABLE-NIC1-8')

        foreach ($Args in @(
            @('modifyvm',$ExpectedMachineUuid,'--clipboard-mode','disabled'),
            @('modifyvm',$ExpectedMachineUuid,'--drag-and-drop','disabled'),
            @('modifyvm',$ExpectedMachineUuid,'--graphicscontroller','vboxvga'),
            @('modifyvm',$ExpectedMachineUuid,'--vram','9')
        )) {
            $Mutation = Invoke-Native -FilePath $VBox -Arguments $Args -Label ('modify ISO boot copy ' + ($Args -join ' '))
            Require-NativeSuccess -Result $Mutation
        }
        $Steps.Add('DISABLE-CLIPBOARD-DRAGDROP-SET-VBOXVGA-9MB')

        $RegisteredRowsResult = Invoke-Native -FilePath $VBox -Arguments @('list','vms') -Label 'ISO copy registered inventory'
        Require-NativeSuccess -Result $RegisteredRowsResult
        $RegisteredRows = @($RegisteredRowsResult.Output | Where-Object { $_.Trim().Length -gt 0 })
        $Quote = [string][char]34
        $ExpectedRow = $Quote + $ExpectedMachineName + $Quote + ' {' + $ExpectedMachineUuid + '}'
        if ($RegisteredRows.Count -ne 1 -or $RegisteredRows[0].Trim() -cne $ExpectedRow) { throw "ISO copy registered row mismatch: $($RegisteredRows -join '|')" }

        $RunningResult = Invoke-Native -FilePath $VBox -Arguments @('list','runningvms') -Label 'ISO copy running inventory'
        Require-NativeSuccess -Result $RunningResult
        if (@($RunningResult.Output | Where-Object { $_.Trim().Length -gt 0 }).Count -ne 0) { throw 'ISO copy unexpectedly running during preparation' }

        $InfoResult = Invoke-Native -FilePath $VBox -Arguments @('showvminfo',$ExpectedMachineUuid,'--machinereadable') -Label 'ISO copy final showvminfo'
        Require-NativeSuccess -Result $InfoResult
        $Info = Convert-MachineReadable -Rows $InfoResult.Output
        Require-MapValue -Map $Info -Key 'name' -Expected $ExpectedMachineName -Label 'ISO copy'
        Require-MapValue -Map $Info -Key 'UUID' -Expected $ExpectedMachineUuid -Label 'ISO copy'
        Require-MapValue -Map $Info -Key 'VMState' -Expected 'poweroff' -Label 'ISO copy'
        Require-MapValue -Map $Info -Key 'CfgFile' -Expected $BootVBox -Label 'ISO copy'
        Require-MapValue -Map $Info -Key 'IDE-1-0' -Expected $BootVdi -Label 'ISO copy'
        Require-MapValue -Map $Info -Key 'IDE-ImageUUID-1-0' -Expected $ExpectedVdiUuid -Label 'ISO copy'
        Require-MapValue -Map $Info -Key 'IDE-0-1' -Expected $BootIso -Label 'ISO copy'
        Require-MapValue -Map $Info -Key 'IDE-ImageUUID-0-1' -Expected $ExpectedIsoUuid -Label 'ISO copy'
        Require-MapValue -Map $Info -Key 'boot1' -Expected 'dvd' -Label 'ISO copy'
        Require-MapValue -Map $Info -Key 'boot2' -Expected 'disk' -Label 'ISO copy'
        Require-MapValue -Map $Info -Key 'boot3' -Expected 'none' -Label 'ISO copy'
        Require-MapValue -Map $Info -Key 'boot4' -Expected 'none' -Label 'ISO copy'
        Require-MapValue -Map $Info -Key 'clipboard' -Expected 'disabled' -Label 'ISO copy'
        Require-MapValue -Map $Info -Key 'draganddrop' -Expected 'disabled' -Label 'ISO copy'
        Require-MapValue -Map $Info -Key 'graphicscontroller' -Expected 'vboxvga' -Label 'ISO copy'
        Require-MapValue -Map $Info -Key 'vram' -Expected '9' -Label 'ISO copy'
        $NicKeys = @($Info.Keys | Where-Object { $_ -match '^nic[1-8]$' })
        if ($NicKeys.Count -eq 0) { throw 'ISO copy exposes no NIC keys' }
        foreach ($Key in $NicKeys) { Require-MapValue -Map $Info -Key $Key -Expected 'none' -Label 'ISO copy' }
        $SharedKeys = @($Info.Keys | Where-Object { $_ -like 'SharedFolderNameMachineMapping*' -or $_ -like 'SharedFolderPathMachineMapping*' })
        if ($SharedKeys.Count -ne 0) { throw "ISO copy shared-folder key count mismatch: $($SharedKeys.Count)" }
        if (@(Get-SnapshotRows -VBox $VBox -Uuid $ExpectedMachineUuid).Count -ne 0) { throw 'ISO copy snapshot inventory not zero' }

        $VdiInfo = Invoke-Native -FilePath $VBox -Arguments @('showmediuminfo','disk',$BootVdi) -Label 'ISO copy VDI medium info'
        Require-NativeSuccess -Result $VdiInfo
        if (($VdiInfo.Output -join "`n") -notmatch '(?im)^UUID:\s*55c1f29d-a681-402e-b90d-bfbb6b09f207\s*$') { throw 'ISO copy VDI UUID mismatch' }
        $IsoInfo = Invoke-Native -FilePath $VBox -Arguments @('showmediuminfo','dvd',$BootIso) -Label 'ISO copy DVD medium info'
        Require-NativeSuccess -Result $IsoInfo
        if (($IsoInfo.Output -join "`n") -notmatch '(?im)^UUID:\s*ab97b3a5-1331-494d-a917-e85b6e728c45\s*$') { throw 'ISO copy ISO UUID mismatch' }
    }
    finally {
        [Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$null,[EnvironmentVariableTarget]::Process)
    }
    Wait-VBoxSVCExit

    [void](Assert-ExactFile -Path $BootVdi -Bytes $ExpectedVdiBytes -Hash $ExpectedVdiHash -Label 'ISO copy VDI after preparation')
    [void](Assert-ExactFile -Path $BootIso -Bytes $ExpectedIsoBytes -Hash $ExpectedIsoHash -Label 'ISO copy ISO after preparation')
    if ((Get-FileId -Path $BootVdi -Label 'ISO copy VDI after preparation') -cne $BootVdiId) { throw 'ISO copy VDI file ID changed during preparation' }
    if ((Get-FileId -Path $BootIso -Label 'ISO copy ISO after preparation') -cne $BootIsoId) { throw 'ISO copy ISO file ID changed during preparation' }
    [void](Assert-Hash -Path $SealedManifest -Hash $ExpectedSealedManifestHash -Label 'sealed manifest after preparation')
    [void](Assert-Hash -Path $SealedVBox -Hash $ExpectedSealedVBoxHash -Label 'sealed VBOX after preparation')
    [void](Assert-ExactFile -Path $SealedVdi -Bytes $ExpectedVdiBytes -Hash $ExpectedVdiHash -Label 'sealed VDI after preparation')
    [void](Assert-ExactFile -Path $SealedIso -Bytes $ExpectedIsoBytes -Hash $ExpectedIsoHash -Label 'sealed ISO after preparation')

    $CurrentVBox = Join-Path $MachineRoot 'Temple1.10.vbox'
    $PreviousVBox = Join-Path $MachineRoot 'Temple1.10.vbox-prev'
    $CurrentVBoxHash = (Get-FileHash -LiteralPath $CurrentVBox -Algorithm SHA256).Hash
    $CurrentVBoxId = Get-FileId -Path $CurrentVBox -Label 'ISO copy current VBOX'
    $PreviousVBoxHash = if (Test-Path -LiteralPath $PreviousVBox -PathType Leaf) { (Get-FileHash -LiteralPath $PreviousVBox -Algorithm SHA256).Hash } else { '<missing>' }
    $PreviousVBoxId = if (Test-Path -LiteralPath $PreviousVBox -PathType Leaf) { Get-FileId -Path $PreviousVBox -Label 'ISO copy previous VBOX' } else { '<missing>' }
    $Registry = Join-Path $NewHome 'VirtualBox.xml'
    $RegistryHash = (Get-FileHash -LiteralPath $Registry -Algorithm SHA256).Hash

    $Manifest = [System.Collections.Generic.List[string]]::new()
    $Manifest.Add('DBYTE-HOLYC-OPT')
    $Manifest.Add('TEMPLEOSTS 1.10 / FRESH EXACT ISO BOOT R1')
    $Manifest.Add('')
    $Manifest.Add("created_utc`t$([DateTimeOffset]::UtcNow.ToString('o'))")
    $Manifest.Add("r3_stop_report_sha256`t$StopReportHash")
    $Manifest.Add("sealed_rehearsal_manifest_sha256`t$ExpectedSealedManifestHash")
    $Manifest.Add("rehearsal_verification_sha256`t$ExpectedVerificationHash")
    $Manifest.Add("boot_readiness_sha256`t$ExpectedReadinessHash")
    $Manifest.Add("iso_boot_root`t$NewRoot")
    $Manifest.Add("isolated_vbox_user_home`t$NewHome")
    $Manifest.Add("machine_uuid`t$ExpectedMachineUuid")
    $Manifest.Add("machine_state`tpoweroff")
    $Manifest.Add("dvd_controller`t$DvdController")
    $Manifest.Add("boot1`tdvd")
    $Manifest.Add("boot2`tdisk")
    $Manifest.Add("boot3`tnone")
    $Manifest.Add("boot4`tnone")
    $Manifest.Add("iso_attached`tTrue")
    $Manifest.Add("network_disabled`tTrue")
    $Manifest.Add("clipboard_disabled`tTrue")
    $Manifest.Add("dragdrop_disabled`tTrue")
    $Manifest.Add("current_vbox_sha256`t$CurrentVBoxHash")
    $Manifest.Add("current_vbox_file_id`t$CurrentVBoxId")
    $Manifest.Add("previous_vbox_sha256`t$PreviousVBoxHash")
    $Manifest.Add("previous_vbox_file_id`t$PreviousVBoxId")
    $Manifest.Add("vdi_sha256`t$ExpectedVdiHash")
    $Manifest.Add("vdi_file_id`t$BootVdiId")
    $Manifest.Add("iso_sha256`t$ExpectedIsoHash")
    $Manifest.Add("iso_file_id`t$BootIsoId")
    $Manifest.Add("registry_sha256`t$RegistryHash")
    foreach ($Step in $Steps) { $Manifest.Add("preparation_step`t$Step") }
    $Manifest.Add('')
    $Manifest.Add("ISO BOOT COPY`tPREPARED")
    $Manifest.Add("VM START`tNOT-AUTHORIZED")
    $Manifest.Add("COMPILER BUILD`tNOT-AUTHORIZED")
    $Manifest.Add('')
    $Manifest.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')
    Write-Lines -Path $ManifestPath -Lines $Manifest.ToArray()
    $ManifestHash = (Get-FileHash -LiteralPath $ManifestPath -Algorithm SHA256).Hash

    Remove-Item -LiteralPath $IncompletePath -Force -ErrorAction Stop

    $Report = [System.Collections.Generic.List[string]]::new()
    $Report.Add('DBYTE-HOLYC-OPT')
    $Report.Add('TEMPLEOSTS 1.10 / FRESH EXACT ISO BOOT R1 PREPARATION')
    $Report.Add('')
    $Report.Add("r3_stop_report_sha256`t$StopReportHash")
    $Report.Add("iso_boot_manifest_sha256`t$ManifestHash")
    $Report.Add("iso_boot_root`t$NewRoot")
    $Report.Add("isolated_vbox_user_home`t$NewHome")
    $Report.Add("machine_uuid`t$ExpectedMachineUuid")
    $Report.Add("machine_state`tpoweroff")
    $Report.Add("boot1`tdvd")
    $Report.Add("boot2`tdisk")
    $Report.Add("boot3`tnone")
    $Report.Add("boot4`tnone")
    $Report.Add("iso_attached`tTrue")
    $Report.Add("vdi_sha256`t$ExpectedVdiHash")
    $Report.Add("iso_sha256`t$ExpectedIsoHash")
    $Report.Add("current_vbox_sha256`t$CurrentVBoxHash")
    $Report.Add("current_vbox_file_id`t$CurrentVBoxId")
    $Report.Add("previous_vbox_sha256`t$PreviousVBoxHash")
    $Report.Add("previous_vbox_file_id`t$PreviousVBoxId")
    $Report.Add("vdi_file_id`t$BootVdiId")
    $Report.Add("iso_file_id`t$BootIsoId")
    $Report.Add("registry_sha256`t$RegistryHash")
    $Report.Add("VBOXMANAGE`tPREPARATION-MUTATIONS-ONLY")
    $Report.Add("R3 MUTATION`tNOT-EXECUTED")
    $Report.Add("VM START`tNOT-EXECUTED")
    $Report.Add("COMPILER BUILD`tNOT-EXECUTED")
    $Report.Add("STATUS`tISO-BOOT-R1-PREPARED")
    $Report.Add('')
    $Report.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')
    Write-Lines -Path $Output -Lines $Report.ToArray()
    $OutputHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

    Write-Host "R3 STOP REPORT SHA256:  $StopReportHash"
    Write-Host "ISO BOOT ROOT:          $NewRoot"
    Write-Host "MACHINE UUID:           $ExpectedMachineUuid"
    Write-Host "BOOT ORDER:             dvd / disk / none / none"
    Write-Host 'ISO ATTACHED:           True'
    Write-Host 'NETWORK DISABLED:       True'
    Write-Host 'CLIPBOARD DISABLED:     True'
    Write-Host 'DRAGDROP DISABLED:      True'
    Write-Host "VBOX SHA256:            $CurrentVBoxHash"
    Write-Host "VBOX FILE ID:           $CurrentVBoxId"
    Write-Host "VDI FILE ID:            $BootVdiId"
    Write-Host "ISO FILE ID:            $BootIsoId"
    Write-Host "REGISTRY SHA256:        $RegistryHash"
    Write-Host "MANIFEST SHA256:        $ManifestHash"
    Write-Host "REPORT:                 $Output"
    Write-Host "REPORT SHA256:          $OutputHash"
    Write-Host 'VM START:               NOT-AUTHORIZED'
    Write-Host 'VERDICT:                FRESH EXACT ISO BOOT R1 PREPARED / POWERED OFF'
}
catch {
    if ($RootCreated -and (Test-Path -LiteralPath $NewRoot -PathType Container)) {
        try {
            Write-Lines -Path $IncompletePath -Lines @(
                'DBYTE-HOLYC-OPT',
                'TEMPLEOSTS 1.10 ISO BOOT R1 PREPARATION FAILED',
                '',
                ('failed_utc' + "`t" + [DateTimeOffset]::UtcNow.ToString('o')),
                ('registered_before_failure' + "`t" + $Registered),
                ('error' + "`t" + $_.Exception.Message),
                '',
                'PRESERVE THIS ROOT FOR REVIEW.',
                'DO NOT DELETE OR REUSE IT.'
            )
        }
        catch { }
        Write-Host "INCOMPLETE ISO ROOT:    $NewRoot"
        Write-Host 'PRESERVE INCOMPLETE:    REQUIRED'
    }
    throw
}
finally {
    [Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$OriginalHome,[EnvironmentVariableTarget]::Process)
}
