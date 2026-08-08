[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$VBoxManagePath = 'D:\Portable-VirtualBox7\app64\VBoxManage.exe'
$SourceRoot = 'D:\TECHNICAL\DBYTE-HOLYC-TOOLS\vm-output\virtualbox\Temple1.10-adopted-baseline\baseline1'
$LocatorReport = 'D:\TECHNICAL\templeosts-r3-root-locator-r3.txt'
$NewRoot = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-ISOBOOT-FRESH-R1'

$ExpectedLocatorHash = 'D1CE0E7839DD474EEB92247074E30824A51BB7F852A6BEAC75251AE5B098E8EA'
$ExpectedSourceVBoxHash = 'E7A884AD2590BAD05AF4465A22FD857A75F64AB9F91042E4638256E8B21AEB46'
$ExpectedLiveVBoxHash = 'E537469A1B1A88DE13D18704B5D6299F3AF202DA518FB266F045485A8FC4F1E6'
$ExpectedVdiHash = '90D453A94F075760A11E0772862E60C4B031ED874F28AA396EAE638F7EB8B31B'
$ExpectedIsoHash = 'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$ExpectedVdiBytes = 2097152L
$ExpectedIsoBytes = 30558208L
$ExpectedMachineName = 'Temple1.10'
$ExpectedMachineUuid = '9c98691e-27cd-4487-a306-587969c2c78c'
$ExpectedVdiUuid = '55c1f29d-a681-402e-b90d-bfbb6b09f207'
$ExpectedIsoUuid = 'ab97b3a5-1331-494d-a917-e85b6e728c45'
$ExpectedVBoxVersion = '7.0.12r159484'
$ExpectedDriverPath = 'D:\Portable-VirtualBox7\app64\drivers\vboxsup\VBoxSup.sys'
$ExpectedDriverHash = '3344E2909580A9965E38B26AB9E9958842315DDEA1B0D0E274DA314DDCAB97F4'
$LiveVBox = 'D:\VirtualBox VMs\Temple1.10\Temple1.10.vbox'
$LiveVdi = 'D:\VirtualBox VMs\Temple1.10\Temple1.10.vdi'
$LiveIso = 'D:\TempleOSTS.iso'
$ScPath = Join-Path $env:SystemRoot 'System32\sc.exe'
$FsutilPath = Join-Path $env:SystemRoot 'System32\fsutil.exe'

function Invoke-Native {
    param([string]$FilePath,[AllowEmptyCollection()][string[]]$Arguments,[string]$Label)
    $Old = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $Rows = @(& $FilePath @Arguments 2>&1 | ForEach-Object { [string]$_ })
        $Exit = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $Old }
    return [pscustomobject]@{Label=$Label;ExitCode=[int]$Exit;Output=[string[]]$Rows}
}

function Require-Success {
    param([object]$Result)
    if ($Result.ExitCode -ne 0) {
        throw "$($Result.Label) failed exit=$($Result.ExitCode) output=$($Result.Output -join ' | ')"
    }
}

function Require-Hash {
    param([string]$Path,[string]$Expected,[string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "${Label} missing: $Path" }
    $Actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($Actual -cne $Expected) { throw "${Label} SHA256 mismatch actual=$Actual expected=$Expected" }
    return $Actual
}

function Require-ExactFile {
    param([string]$Path,[long]$Bytes,[string]$Hash,[string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "${Label} missing: $Path" }
    $Item = Get-Item -LiteralPath $Path -Force
    if ($Item.Length -ne $Bytes) { throw "${Label} byte mismatch actual=$($Item.Length) expected=$Bytes" }
    [void](Require-Hash $Path $Hash $Label)
}

function Get-FileId {
    param([string]$Path,[string]$Label)
    $Result = Invoke-Native $FsutilPath @('file','queryfileid',$Path) "fsutil $Label"
    Require-Success $Result
    $Ids = @([regex]::Matches(($Result.Output -join "`n"),'(?i)0x[0-9a-f]+') | ForEach-Object { $_.Value.ToUpperInvariant() })
    if ($Ids.Count -ne 1) { throw "${Label} file ID count mismatch: $($Ids.Count)" }
    return $Ids[0]
}

function Require-VBoxSupRunning {
    $Result = Invoke-Native $ScPath @('query','VBoxSup') 'sc query VBoxSup'
    Require-Success $Result
    if (($Result.Output -join "`n") -notmatch '(?im)^\s*STATE\s*:\s*4\b') { throw 'VBoxSup STATE 4 not observed' }
}

function Convert-MachineReadable {
    param([AllowEmptyCollection()][string[]]$Rows)
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
    param([hashtable]$Map,[string]$Key,[string]$Expected,[string]$Label)
    if (-not $Map.ContainsKey($Key)) { throw "${Label} missing key: $Key" }
    $Observed = [string]$Map[$Key]
    if (-not [string]::Equals($Observed,$Expected,[System.StringComparison]::OrdinalIgnoreCase)) {
        throw "${Label} mismatch $Key=$Observed expected=$Expected"
    }
}

function Get-SnapshotRows {
    param([string]$VBox,[string]$Uuid)
    $Result = Invoke-Native $VBox @('snapshot',$Uuid,'list','--machinereadable') 'snapshot list'
    if ($Result.ExitCode -eq 0) {
        return [string[]]@($Result.Output | Where-Object { $_ -match '^Snapshot(Name|UUID|Node)' })
    }
    if (($Result.Output -join "`n") -match '(?i)does not have any snapshots') { return [string[]]@() }
    throw "snapshot list failed exit=$($Result.ExitCode) output=$($Result.Output -join ' | ')"
}

function Wait-VBoxSVCExit {
    param([int]$Seconds=30)
    $Deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    while ([DateTime]::UtcNow -lt $Deadline) {
        if (@(Get-Process -Name VBoxSVC -ErrorAction SilentlyContinue).Count -eq 0) { return }
        Start-Sleep -Milliseconds 250
    }
    $Pids = @(Get-Process -Name VBoxSVC -ErrorAction SilentlyContinue).Id
    throw "VBoxSVC did not exit: $($Pids -join ',')"
}

function Get-OrdinalCount {
    param([string]$Text,[string]$Needle)
    if ($Needle.Length -eq 0) { throw 'empty count needle' }
    $Count = 0
    $Offset = 0
    while ($true) {
        $At = $Text.IndexOf($Needle,$Offset,[System.StringComparison]::Ordinal)
        if ($At -lt 0) { break }
        $Count++
        $Offset = $At + $Needle.Length
    }
    return $Count
}

foreach ($Required in @($VBoxManagePath,$ScPath,$FsutilPath,$ExpectedDriverPath,$LocatorReport)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) { throw "required file missing: $Required" }
}
if (Test-Path -LiteralPath $NewRoot) { throw "fresh ISO root already exists; preserve it: $NewRoot" }
if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) { throw "adopted baseline root missing: $SourceRoot" }

[void](Require-Hash $LocatorReport $ExpectedLocatorHash 'R3 locator report')
[void](Require-Hash $ExpectedDriverPath $ExpectedDriverHash 'VBoxSup.sys')
Require-VBoxSupRunning

$SourceVBox = Join-Path $SourceRoot 'Temple1.10.vbox'
$SourceVdi = Join-Path $SourceRoot 'Temple1.10.vdi'
$SourceIso = Join-Path $SourceRoot 'TempleOSTS.iso'
[void](Require-Hash $SourceVBox $ExpectedSourceVBoxHash 'adopted baseline VBOX')
Require-ExactFile $SourceVdi $ExpectedVdiBytes $ExpectedVdiHash 'adopted baseline VDI'
Require-ExactFile $SourceIso $ExpectedIsoBytes $ExpectedIsoHash 'adopted baseline ISO'
[void](Require-Hash $LiveVBox $ExpectedLiveVBoxHash 'live VBOX read-only cross-check')
Require-ExactFile $LiveVdi $ExpectedVdiBytes $ExpectedVdiHash 'live VDI read-only cross-check'
Require-ExactFile $LiveIso $ExpectedIsoBytes $ExpectedIsoHash 'live ISO read-only cross-check'

$RuntimeProcesses = @(
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -match '(?i)^(VBoxSVC|VirtualBoxVM|VBoxHeadless|VirtualBox)$' }
)
if ($RuntimeProcesses.Count -ne 0) {
    throw ('VirtualBox runtime already present: ' + (($RuntimeProcesses | ForEach-Object { "$($_.ProcessName):$($_.Id)" }) -join ', '))
}
$OriginalVBoxHome = [Environment]::GetEnvironmentVariable('VBOX_USER_HOME',[EnvironmentVariableTarget]::Process)
if (-not [string]::IsNullOrEmpty($OriginalVBoxHome)) { throw "process VBOX_USER_HOME must be unset: $OriginalVBoxHome" }

$MachineDir = Join-Path $NewRoot 'Machine'
$VBoxUserHome = Join-Path $NewRoot 'VBoxUserHome'
$BootVBox = Join-Path $MachineDir 'Temple1.10.vbox'
$BootVdi = Join-Path $MachineDir 'Temple1.10.vdi'
$BootIso = Join-Path $MachineDir 'TempleOSTS.iso'
$Incomplete = Join-Path $NewRoot 'INCOMPLETE.txt'
$Manifest = Join-Path $NewRoot 'MANIFEST.txt'
$PrepReport = Join-Path $NewRoot 'PREPARATION.txt'
$RootCreated = $false
$Registered = $false

try {
    [void][System.IO.Directory]::CreateDirectory($MachineDir)
    [void][System.IO.Directory]::CreateDirectory($VBoxUserHome)
    $RootCreated = $true
    [System.IO.File]::WriteAllText($Incomplete,"DBYTE-HOLYC-OPT`nFRESH ISO BOOT R1 INCOMPLETE`nPRESERVE ON FAILURE.`n",[System.Text.UTF8Encoding]::new($false))

    Copy-Item -LiteralPath $SourceVBox -Destination $BootVBox -ErrorAction Stop
    Copy-Item -LiteralPath $SourceVdi -Destination $BootVdi -ErrorAction Stop
    Copy-Item -LiteralPath $SourceIso -Destination $BootIso -ErrorAction Stop

    [void](Require-Hash $BootVBox $ExpectedSourceVBoxHash 'copied VBOX before rewrite')
    Require-ExactFile $BootVdi $ExpectedVdiBytes $ExpectedVdiHash 'copied VDI'
    Require-ExactFile $BootIso $ExpectedIsoBytes $ExpectedIsoHash 'copied ISO'
    $BootVdiId = Get-FileId $BootVdi 'copied VDI'
    $BootIsoId = Get-FileId $BootIso 'copied ISO'
    if ($BootVdiId -ceq (Get-FileId $SourceVdi 'source VDI')) { throw 'copied VDI is not a distinct file object' }
    if ($BootIsoId -ceq (Get-FileId $SourceIso 'source ISO')) { throw 'copied ISO is not a distinct file object' }

    [xml]$SourceXml = [System.IO.File]::ReadAllText($BootVBox)
    $VdiLocationNodes = @(
        $SourceXml.SelectNodes('//*[@uuid and @location]') |
            Where-Object { $_.GetAttribute('uuid').Trim('{}') -ieq $ExpectedVdiUuid }
    )
    $IsoLocationNodes = @(
        $SourceXml.SelectNodes('//*[@uuid and @location]') |
            Where-Object { $_.GetAttribute('uuid').Trim('{}') -ieq $ExpectedIsoUuid }
    )
    if ($VdiLocationNodes.Count -ne 1) { throw "VDI location node count mismatch: $($VdiLocationNodes.Count)" }
    if ($IsoLocationNodes.Count -ne 1) { throw "ISO location node count mismatch: $($IsoLocationNodes.Count)" }
    $OldVdiLocation = [string]$VdiLocationNodes[0].GetAttribute('location')
    $OldIsoLocation = [string]$IsoLocationNodes[0].GetAttribute('location')
    if ([string]::IsNullOrWhiteSpace($OldVdiLocation) -or [string]::IsNullOrWhiteSpace($OldIsoLocation)) { throw 'source media location empty' }

    $VBoxText = [System.IO.File]::ReadAllText($BootVBox)
    if ((Get-OrdinalCount $VBoxText $OldVdiLocation) -ne 1) { throw 'source VDI path cardinality not one' }
    if ((Get-OrdinalCount $VBoxText $OldIsoLocation) -ne 1) { throw 'source ISO path cardinality not one' }
    $VBoxText = $VBoxText.Replace($OldVdiLocation,$BootVdi).Replace($OldIsoLocation,$BootIso)
    if ((Get-OrdinalCount $VBoxText $BootVdi) -ne 1 -or (Get-OrdinalCount $VBoxText $BootIso) -ne 1) { throw 'rewritten media path cardinality mismatch' }
    [System.IO.File]::WriteAllText($BootVBox,$VBoxText,[System.Text.UTF8Encoding]::new($false))

    [Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$VBoxUserHome,[EnvironmentVariableTarget]::Process)
    try {
        $Version = Invoke-Native $VBoxManagePath @('--version') 'VBoxManage --version'
        Require-Success $Version
        if ($Version.Output.Count -ne 1 -or $Version.Output[0].Trim() -cne $ExpectedVBoxVersion) { throw "VirtualBox version mismatch: $($Version.Output -join '|')" }

        $Before = Invoke-Native $VBoxManagePath @('list','vms') 'isolated inventory before register'
        Require-Success $Before
        if (@($Before.Output | Where-Object { $_.Trim().Length -gt 0 }).Count -ne 0) { throw 'fresh isolated registry is not empty' }

        $Register = Invoke-Native $VBoxManagePath @('registervm',$BootVBox) 'register fresh ISO copy'
        Require-Success $Register
        $Registered = $true

        foreach ($Args in @(
            @('modifyvm',$ExpectedMachineUuid,'--boot1','dvd','--boot2','disk','--boot3','none','--boot4','none'),
            @('modifyvm',$ExpectedMachineUuid,'--clipboard-mode','disabled'),
            @('modifyvm',$ExpectedMachineUuid,'--drag-and-drop','disabled'),
            @('modifyvm',$ExpectedMachineUuid,'--graphicscontroller','vboxvga'),
            @('modifyvm',$ExpectedMachineUuid,'--vram','9')
        )) {
            $Mut = Invoke-Native $VBoxManagePath $Args ('prepare ' + ($Args -join ' '))
            Require-Success $Mut
        }
        for ($Index=1; $Index -le 8; $Index++) {
            $Mut = Invoke-Native $VBoxManagePath @('modifyvm',$ExpectedMachineUuid,"--nic$Index",'none') "disable NIC $Index"
            Require-Success $Mut
        }

        $List = Invoke-Native $VBoxManagePath @('list','vms') 'registered inventory'
        Require-Success $List
        $Rows = @($List.Output | Where-Object { $_.Trim().Length -gt 0 })
        $Quote = [string][char]34
        $ExpectedRow = $Quote+$ExpectedMachineName+$Quote+' {'+$ExpectedMachineUuid+'}'
        if ($Rows.Count -ne 1 -or $Rows[0].Trim() -cne $ExpectedRow) { throw "registered inventory mismatch: $($Rows -join '|')" }

        $Running = Invoke-Native $VBoxManagePath @('list','runningvms') 'running inventory during preparation'
        Require-Success $Running
        if (@($Running.Output | Where-Object { $_.Trim().Length -gt 0 }).Count -ne 0) { throw 'fresh ISO copy unexpectedly running during preparation' }

        $InfoResult = Invoke-Native $VBoxManagePath @('showvminfo',$ExpectedMachineUuid,'--machinereadable') 'fresh ISO showvminfo'
        Require-Success $InfoResult
        $Info = Convert-MachineReadable $InfoResult.Output
        Require-MapValue $Info 'name' $ExpectedMachineName 'fresh ISO copy'
        Require-MapValue $Info 'UUID' $ExpectedMachineUuid 'fresh ISO copy'
        Require-MapValue $Info 'VMState' 'poweroff' 'fresh ISO copy'
        Require-MapValue $Info 'CfgFile' $BootVBox 'fresh ISO copy'
        Require-MapValue $Info 'IDE-1-0' $BootVdi 'fresh ISO copy'
        Require-MapValue $Info 'IDE-ImageUUID-1-0' $ExpectedVdiUuid 'fresh ISO copy'
        Require-MapValue $Info 'IDE-0-1' $BootIso 'fresh ISO copy'
        Require-MapValue $Info 'IDE-ImageUUID-0-1' $ExpectedIsoUuid 'fresh ISO copy'
        Require-MapValue $Info 'boot1' 'dvd' 'fresh ISO copy'
        Require-MapValue $Info 'boot2' 'disk' 'fresh ISO copy'
        Require-MapValue $Info 'boot3' 'none' 'fresh ISO copy'
        Require-MapValue $Info 'boot4' 'none' 'fresh ISO copy'
        Require-MapValue $Info 'clipboard' 'disabled' 'fresh ISO copy'
        Require-MapValue $Info 'draganddrop' 'disabled' 'fresh ISO copy'
        Require-MapValue $Info 'graphicscontroller' 'vboxvga' 'fresh ISO copy'
        Require-MapValue $Info 'vram' '9' 'fresh ISO copy'
        foreach ($Index in 1..8) {
            $Key = "nic$Index"
            if ($Info.ContainsKey($Key)) { Require-MapValue $Info $Key 'none' 'fresh ISO copy' }
        }
        $SharedKeys = @($Info.Keys | Where-Object { $_ -like 'SharedFolderNameMachineMapping*' -or $_ -like 'SharedFolderPathMachineMapping*' })
        if ($SharedKeys.Count -ne 0) { throw "shared-folder key count mismatch: $($SharedKeys.Count)" }
        if (@(Get-SnapshotRows $VBoxManagePath $ExpectedMachineUuid).Count -ne 0) { throw 'snapshot inventory not zero' }

        $VdiInfo = Invoke-Native $VBoxManagePath @('showmediuminfo','disk',$BootVdi) 'fresh ISO VDI medium info'
        Require-Success $VdiInfo
        if (($VdiInfo.Output -join "`n") -notmatch '(?im)^UUID:\s*55c1f29d-a681-402e-b90d-bfbb6b09f207\s*$') { throw 'fresh ISO VDI UUID mismatch' }
        $IsoInfo = Invoke-Native $VBoxManagePath @('showmediuminfo','dvd',$BootIso) 'fresh ISO DVD medium info'
        Require-Success $IsoInfo
        if (($IsoInfo.Output -join "`n") -notmatch '(?im)^UUID:\s*ab97b3a5-1331-494d-a917-e85b6e728c45\s*$') { throw 'fresh ISO UUID mismatch' }
    }
    finally {
        [Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$OriginalVBoxHome,[EnvironmentVariableTarget]::Process)
    }

    Wait-VBoxSVCExit
    Require-VBoxSupRunning
    Require-ExactFile $SourceVdi $ExpectedVdiBytes $ExpectedVdiHash 'source VDI after preparation'
    Require-ExactFile $SourceIso $ExpectedIsoBytes $ExpectedIsoHash 'source ISO after preparation'
    Require-ExactFile $LiveVdi $ExpectedVdiBytes $ExpectedVdiHash 'live VDI after preparation'
    Require-ExactFile $LiveIso $ExpectedIsoBytes $ExpectedIsoHash 'live ISO after preparation'
    Require-ExactFile $BootVdi $ExpectedVdiBytes $ExpectedVdiHash 'fresh VDI after preparation'
    Require-ExactFile $BootIso $ExpectedIsoBytes $ExpectedIsoHash 'fresh ISO after preparation'

    $FinalVBoxHash = (Get-FileHash -LiteralPath $BootVBox -Algorithm SHA256).Hash
    $Registry = Join-Path $VBoxUserHome 'VirtualBox.xml'
    if (-not (Test-Path -LiteralPath $Registry -PathType Leaf)) { throw 'fresh isolated registry missing after preparation' }
    $RegistryHash = (Get-FileHash -LiteralPath $Registry -Algorithm SHA256).Hash

    $ManifestLines = @(
        'DBYTE-HOLYC-OPT',
        'TEMPLEOSTS 1.10 / FRESH ISO BOOT R1 / ADOPTED BASELINE SOURCE',
        '',
        "locator_report_sha256`t$ExpectedLocatorHash",
        "source_root`t$SourceRoot",
        "source_vbox_sha256`t$ExpectedSourceVBoxHash",
        "source_vdi_sha256`t$ExpectedVdiHash",
        "source_iso_sha256`t$ExpectedIsoHash",
        "fresh_root`t$NewRoot",
        "machine_uuid`t$ExpectedMachineUuid",
        "machine_state`tpoweroff",
        "boot1`tdvd",
        "boot2`tdisk",
        "boot3`tnone",
        "boot4`tnone",
        "vdi_sha256`t$ExpectedVdiHash",
        "iso_sha256`t$ExpectedIsoHash",
        "vdi_file_id`t$BootVdiId",
        "iso_file_id`t$BootIsoId",
        "current_vbox_sha256`t$FinalVBoxHash",
        "registry_sha256`t$RegistryHash",
        "ISO ATTACHED`tTRUE",
        "NETWORK`tDISABLED",
        "VM START`tNOT-EXECUTED",
        "COMPILER BUILD`tNOT-EXECUTED",
        '',
        'REPORTS ARE CLAIMS, NOT EVIDENCE.'
    )
    [System.IO.File]::WriteAllText($Manifest,(($ManifestLines -join "`n")+"`n"),[System.Text.UTF8Encoding]::new($false))
    $ManifestHash = (Get-FileHash -LiteralPath $Manifest -Algorithm SHA256).Hash

    $ReportLines = @(
        'DBYTE-HOLYC-OPT',
        'TEMPLEOSTS 1.10 / FRESH ISO BOOT R1 / PREPARATION',
        '',
        "locator_report_sha256`t$ExpectedLocatorHash",
        "manifest_sha256`t$ManifestHash",
        "fresh_root`t$NewRoot",
        "machine_state`tpoweroff",
        "boot_order`tdvd / disk / none / none",
        "iso_attached`tTrue",
        "vdi_sha256`t$ExpectedVdiHash",
        "iso_sha256`t$ExpectedIsoHash",
        "current_vbox_sha256`t$FinalVBoxHash",
        "registry_sha256`t$RegistryHash",
        "VBOXMANAGE`tPREPARATION-MUTATIONS-ONLY",
        "LIVE VM MUTATION`tNOT-EXECUTED",
        "VM START`tNOT-EXECUTED",
        "COMPILER BUILD`tNOT-EXECUTED",
        "STATUS`tFRESH-ISO-BOOT-R1-PREPARED",
        '',
        'REPORTS ARE CLAIMS, NOT EVIDENCE.'
    )
    [System.IO.File]::WriteAllText($PrepReport,(($ReportLines -join "`n")+"`n"),[System.Text.UTF8Encoding]::new($false))
    $PrepHash = (Get-FileHash -LiteralPath $PrepReport -Algorithm SHA256).Hash

    Remove-Item -LiteralPath $Incomplete -Force -ErrorAction Stop

    Write-Host "SOURCE BASELINE:         $SourceRoot"
    Write-Host "FRESH ISO ROOT:          $NewRoot"
    Write-Host 'MACHINE STATE:           poweroff'
    Write-Host 'BOOT ORDER:              dvd / disk / none / none'
    Write-Host 'ISO ATTACHED:            True / exact TempleOSTS ISO'
    Write-Host 'NETWORK:                 disabled'
    Write-Host "MANIFEST SHA256:         $ManifestHash"
    Write-Host "PREPARATION SHA256:      $PrepHash"
    Write-Host 'LIVE VM MUTATION:        NOT-EXECUTED'
    Write-Host 'VM START:                NOT-EXECUTED'
    Write-Host 'VERDICT:                 FRESH ISO BOOT R1 PREPARED FROM ADOPTED BASELINE'
}
catch {
    if ($RootCreated -and (Test-Path -LiteralPath $NewRoot -PathType Container)) {
        try {
            [System.IO.File]::WriteAllText($Incomplete,("DBYTE-HOLYC-OPT`nFRESH ISO BOOT R1 PREPARATION FAILED`nerror`t"+$_.Exception.Message+"`nPRESERVE THIS ROOT. DO NOT REUSE.`n"),[System.Text.UTF8Encoding]::new($false))
        }
        catch { }
        Write-Host "INCOMPLETE ROOT:         $NewRoot"
        Write-Host "REGISTERED BEFORE FAIL: $Registered"
        Write-Host 'PRESERVE INCOMPLETE:     REQUIRED'
    }
    throw
}
finally {
    [Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$OriginalVBoxHome,[EnvironmentVariableTarget]::Process)
}
