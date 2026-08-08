[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$VBoxManagePath = 'D:\Portable-VirtualBox7\app64\VBoxManage.exe'
$Root = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-ISOBOOT-FRESH-R1'
$LocatorReport = 'D:\TECHNICAL\templeosts-r3-root-locator-r3.txt'
$SourceRoot = 'D:\TECHNICAL\DBYTE-HOLYC-TOOLS\vm-output\virtualbox\Temple1.10-adopted-baseline\baseline1'
$ExpectedLocatorHash = 'D1CE0E7839DD474EEB92247074E30824A51BB7F852A6BEAC75251AE5B098E8EA'
$ExpectedSourceVBoxHash = 'E7A884AD2590BAD05AF4465A22FD857A75F64AB9F91042E4638256E8B21AEB46'
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
    if ($Result.ExitCode -ne 0) { throw "$($Result.Label) failed exit=$($Result.ExitCode) output=$($Result.Output -join ' | ')" }
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
    $DoubleSlash = $Slash+$Slash
    $EscapedQuote = $Slash+[string][char]34
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

function Get-TabValue {
    param([string[]]$Lines,[string]$Key)
    $Prefix = $Key+"`t"
    $Rows = @($Lines | Where-Object { $_.StartsWith($Prefix,[System.StringComparison]::Ordinal) })
    if ($Rows.Count -ne 1) { throw "report field count mismatch key=$Key count=$($Rows.Count)" }
    return $Rows[0].Substring($Prefix.Length)
}

function Get-SnapshotRows {
    param([string]$VBox,[string]$Uuid)
    $Result = Invoke-Native $VBox @('snapshot',$Uuid,'list','--machinereadable') 'snapshot list'
    if ($Result.ExitCode -eq 0) { return [string[]]@($Result.Output | Where-Object { $_ -match '^Snapshot(Name|UUID|Node)' }) }
    if (($Result.Output -join "`n") -match '(?i)does not have any snapshots') { return [string[]]@() }
    throw "snapshot list failed exit=$($Result.ExitCode) output=$($Result.Output -join ' | ')"
}

function Get-HardeningEvidence {
    param([string]$MachineDir)
    $Path = Join-Path (Join-Path $MachineDir 'Logs') 'VBoxHardening.log'
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return [pscustomobject]@{Path=$Path;Hash='';Tail=@();Error=''} }
    try {
        return [pscustomobject]@{
            Path=$Path
            Hash=(Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
            Tail=[string[]]@(Get-Content -LiteralPath $Path -Tail 80 -ErrorAction Stop)
            Error=''
        }
    }
    catch { return [pscustomobject]@{Path=$Path;Hash='';Tail=@();Error=$_.Exception.Message} }
}

function Write-StartReport {
    param([string]$Path,[string]$Status,[string]$PrepHash,[string]$ManifestHash,[string]$StartArgs,[int]$StartExit,[string[]]$StartOutput,[string]$PostState,[int]$PostRunning,[string]$ErrorText)
    if (Test-Path -LiteralPath $Path) { throw "start report already exists: $Path" }
    $Hardening = Get-HardeningEvidence (Join-Path $Root 'Machine')
    $Lines = [System.Collections.Generic.List[string]]::new()
    [void]$Lines.Add('DBYTE-HOLYC-OPT')
    [void]$Lines.Add('TEMPLEOSTS 1.10 / FRESH ISO BOOT R1 / CONTROLLED START')
    [void]$Lines.Add('')
    [void]$Lines.Add("preparation_sha256`t$PrepHash")
    [void]$Lines.Add("manifest_sha256`t$ManifestHash")
    [void]$Lines.Add("machine_uuid`t$ExpectedMachineUuid")
    [void]$Lines.Add("start_arguments`t$StartArgs")
    [void]$Lines.Add("start_exit_code`t$StartExit")
    foreach ($Row in $StartOutput) { [void]$Lines.Add("start_output`t$Row") }
    [void]$Lines.Add("post_start_vm_state`t$PostState")
    [void]$Lines.Add("post_start_running_vm_rows`t$PostRunning")
    if (-not [string]::IsNullOrWhiteSpace($ErrorText)) { [void]$Lines.Add("error`t$ErrorText") }
    [void]$Lines.Add("hardening_log_path`t$($Hardening.Path)")
    [void]$Lines.Add("hardening_log_sha256`t$($Hardening.Hash)")
    [void]$Lines.Add("hardening_log_capture_error`t$($Hardening.Error)")
    foreach ($Row in $Hardening.Tail) { [void]$Lines.Add("hardening_tail`t$Row") }
    [void]$Lines.Add('')
    [void]$Lines.Add('VBOXMANAGE`tSTARTVM-ONCE-PLUS-READ-ONLY-OBSERVATION')
    [void]$Lines.Add('CONTROLVM`tNOT-EXECUTED')
    [void]$Lines.Add('STORAGEATTACH`tNOT-EXECUTED')
    [void]$Lines.Add('SERVICE MUTATION`tNOT-EXECUTED')
    [void]$Lines.Add('COMPILER BUILD`tNOT-EXECUTED')
    [void]$Lines.Add('GUEST VISUAL BOOT`tNOT-OBSERVED-BY-HOST-SCRIPT')
    [void]$Lines.Add("STATUS`t$Status")
    [void]$Lines.Add('')
    [void]$Lines.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')
    [System.IO.File]::WriteAllText($Path,(($Lines.ToArray()-join "`n")+"`n"),[System.Text.UTF8Encoding]::new($false))
}

foreach ($Required in @($VBoxManagePath,$ScPath,$FsutilPath,$ExpectedDriverPath,$LocatorReport)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) { throw "required file missing: $Required" }
}
if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw "fresh ISO root missing: $Root" }
$Incomplete = Join-Path $Root 'INCOMPLETE.txt'
if (Test-Path -LiteralPath $Incomplete) { throw "fresh ISO root remains incomplete: $Incomplete" }

[void](Require-Hash $LocatorReport $ExpectedLocatorHash 'R3 locator report')
[void](Require-Hash $ExpectedDriverPath $ExpectedDriverHash 'VBoxSup.sys')
Require-VBoxSupRunning

$MachineDir = Join-Path $Root 'Machine'
$VBoxUserHome = Join-Path $Root 'VBoxUserHome'
$BootVBox = Join-Path $MachineDir 'Temple1.10.vbox'
$BootVdi = Join-Path $MachineDir 'Temple1.10.vdi'
$BootIso = Join-Path $MachineDir 'TempleOSTS.iso'
$Manifest = Join-Path $Root 'MANIFEST.txt'
$PrepReport = Join-Path $Root 'PREPARATION.txt'
$StartReport = Join-Path $Root 'START.txt'
$Registry = Join-Path $VBoxUserHome 'VirtualBox.xml'
foreach ($Required in @($BootVBox,$BootVdi,$BootIso,$Manifest,$PrepReport,$Registry)) {
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf)) { throw "fresh ISO artifact missing: $Required" }
}
if (Test-Path -LiteralPath $StartReport) { throw "fresh ISO start report already exists: $StartReport" }

[void](Require-Hash (Join-Path $SourceRoot 'Temple1.10.vbox') $ExpectedSourceVBoxHash 'source VBOX before start')
Require-ExactFile (Join-Path $SourceRoot 'Temple1.10.vdi') $ExpectedVdiBytes $ExpectedVdiHash 'source VDI before start'
Require-ExactFile (Join-Path $SourceRoot 'TempleOSTS.iso') $ExpectedIsoBytes $ExpectedIsoHash 'source ISO before start'
Require-ExactFile $BootVdi $ExpectedVdiBytes $ExpectedVdiHash 'fresh VDI before start'
Require-ExactFile $BootIso $ExpectedIsoBytes $ExpectedIsoHash 'fresh ISO before start'

$ManifestLines = [System.IO.File]::ReadAllLines($Manifest)
$PrepLines = [System.IO.File]::ReadAllLines($PrepReport)
$ManifestHash = (Get-FileHash -LiteralPath $Manifest -Algorithm SHA256).Hash
$PrepHash = (Get-FileHash -LiteralPath $PrepReport -Algorithm SHA256).Hash
if ((Get-TabValue $PrepLines 'manifest_sha256') -cne $ManifestHash) { throw 'preparation manifest binding mismatch' }
if ((Get-TabValue $PrepLines 'fresh_root') -cne $Root) { throw 'preparation fresh root mismatch' }
if ((Get-TabValue $PrepLines 'machine_state') -cne 'poweroff') { throw 'preparation machine state mismatch' }
if ((Get-TabValue $PrepLines 'boot_order') -cne 'dvd / disk / none / none') { throw 'preparation boot order mismatch' }
if ((Get-TabValue $PrepLines 'iso_attached') -cne 'True') { throw 'preparation ISO attachment mismatch' }
if ((Get-TabValue $PrepLines 'STATUS') -cne 'FRESH-ISO-BOOT-R1-PREPARED') { throw 'preparation status mismatch' }
if ((Get-TabValue $ManifestLines 'locator_report_sha256') -cne $ExpectedLocatorHash) { throw 'manifest locator binding mismatch' }
if ((Get-TabValue $ManifestLines 'source_vbox_sha256') -cne $ExpectedSourceVBoxHash) { throw 'manifest source VBOX mismatch' }
if ((Get-TabValue $ManifestLines 'vdi_sha256') -cne $ExpectedVdiHash) { throw 'manifest VDI mismatch' }
if ((Get-TabValue $ManifestLines 'iso_sha256') -cne $ExpectedIsoHash) { throw 'manifest ISO mismatch' }
if ((Get-TabValue $ManifestLines 'VM START') -cne 'NOT-EXECUTED') { throw 'manifest start state mismatch' }

$ExpectedVBoxHash = Get-TabValue $ManifestLines 'current_vbox_sha256'
$ExpectedRegistryHash = Get-TabValue $ManifestLines 'registry_sha256'
$ExpectedVdiId = Get-TabValue $ManifestLines 'vdi_file_id'
$ExpectedIsoId = Get-TabValue $ManifestLines 'iso_file_id'
[void](Require-Hash $BootVBox $ExpectedVBoxHash 'fresh VBOX before start')
[void](Require-Hash $Registry $ExpectedRegistryHash 'fresh registry before start')
if ((Get-FileId $BootVdi 'fresh VDI') -cne $ExpectedVdiId) { throw 'fresh VDI file ID mismatch' }
if ((Get-FileId $BootIso 'fresh ISO') -cne $ExpectedIsoId) { throw 'fresh ISO file ID mismatch' }

$RuntimeProcesses = @(
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -match '(?i)^(VBoxSVC|VirtualBoxVM|VBoxHeadless|VirtualBox)$' }
)
if ($RuntimeProcesses.Count -ne 0) {
    throw ('VirtualBox runtime already present before ISO start: ' + (($RuntimeProcesses | ForEach-Object { "$($_.ProcessName):$($_.Id)" }) -join ', '))
}
$OriginalVBoxHome = [Environment]::GetEnvironmentVariable('VBOX_USER_HOME',[EnvironmentVariableTarget]::Process)
if (-not [string]::IsNullOrEmpty($OriginalVBoxHome)) { throw "process VBOX_USER_HOME must be unset: $OriginalVBoxHome" }

$StartIssued = $false
$StartArgsText = 'NOT-ISSUED'
$StartExit = -1
$StartOutput = @()
$PostState = ''
$PostRunningCount = -1

[Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$VBoxUserHome,[EnvironmentVariableTarget]::Process)
try {
    $Version = Invoke-Native $VBoxManagePath @('--version') 'VBoxManage --version'
    Require-Success $Version
    if ($Version.Output.Count -ne 1 -or $Version.Output[0].Trim() -cne $ExpectedVBoxVersion) { throw 'VirtualBox version mismatch' }

    $List = Invoke-Native $VBoxManagePath @('list','vms') 'fresh ISO registered inventory'
    Require-Success $List
    $Rows = @($List.Output | Where-Object { $_.Trim().Length -gt 0 })
    $Quote = [string][char]34
    $ExpectedRow = $Quote+$ExpectedMachineName+$Quote+' {'+$ExpectedMachineUuid+'}'
    if ($Rows.Count -ne 1 -or $Rows[0].Trim() -cne $ExpectedRow) { throw "registered inventory mismatch: $($Rows -join '|')" }

    $Running = Invoke-Native $VBoxManagePath @('list','runningvms') 'fresh ISO pre-start running inventory'
    Require-Success $Running
    if (@($Running.Output | Where-Object { $_.Trim().Length -gt 0 }).Count -ne 0) { throw 'fresh ISO VM already running' }

    $InfoResult = Invoke-Native $VBoxManagePath @('showvminfo',$ExpectedMachineUuid,'--machinereadable') 'fresh ISO pre-start showvminfo'
    Require-Success $InfoResult
    $Info = Convert-MachineReadable $InfoResult.Output
    Require-MapValue $Info 'name' $ExpectedMachineName 'fresh ISO pre-start'
    Require-MapValue $Info 'UUID' $ExpectedMachineUuid 'fresh ISO pre-start'
    Require-MapValue $Info 'VMState' 'poweroff' 'fresh ISO pre-start'
    Require-MapValue $Info 'CfgFile' $BootVBox 'fresh ISO pre-start'
    Require-MapValue $Info 'IDE-1-0' $BootVdi 'fresh ISO pre-start'
    Require-MapValue $Info 'IDE-ImageUUID-1-0' $ExpectedVdiUuid 'fresh ISO pre-start'
    Require-MapValue $Info 'IDE-0-1' $BootIso 'fresh ISO pre-start'
    Require-MapValue $Info 'IDE-ImageUUID-0-1' $ExpectedIsoUuid 'fresh ISO pre-start'
    Require-MapValue $Info 'boot1' 'dvd' 'fresh ISO pre-start'
    Require-MapValue $Info 'boot2' 'disk' 'fresh ISO pre-start'
    Require-MapValue $Info 'boot3' 'none' 'fresh ISO pre-start'
    Require-MapValue $Info 'boot4' 'none' 'fresh ISO pre-start'
    Require-MapValue $Info 'clipboard' 'disabled' 'fresh ISO pre-start'
    Require-MapValue $Info 'draganddrop' 'disabled' 'fresh ISO pre-start'
    $SharedKeys = @($Info.Keys | Where-Object { $_ -like 'SharedFolderNameMachineMapping*' -or $_ -like 'SharedFolderPathMachineMapping*' })
    if ($SharedKeys.Count -ne 0) { throw "shared-folder key count mismatch: $($SharedKeys.Count)" }
    if (@(Get-SnapshotRows $VBoxManagePath $ExpectedMachineUuid).Count -ne 0) { throw 'snapshot inventory not zero' }

    Require-VBoxSupRunning
    [void](Require-Hash $BootVBox $ExpectedVBoxHash 'fresh VBOX at start boundary')
    [void](Require-Hash $Registry $ExpectedRegistryHash 'fresh registry at start boundary')
    Require-ExactFile $BootVdi $ExpectedVdiBytes $ExpectedVdiHash 'fresh VDI at start boundary'
    Require-ExactFile $BootIso $ExpectedIsoBytes $ExpectedIsoHash 'fresh ISO at start boundary'

    Write-Host 'ISO START BOUNDARY:     ALL PRE-START GATES PASSED'
    Write-Host 'SOURCE:                 ADOPTED BASELINE EXACT COPY'
    Write-Host 'BOOT ROUTE:             DVD -> DISK -> NONE -> NONE'
    Write-Host 'ISO ATTACHED:           TRUE / EXACT TEMPLEOSTS ISO'
    Write-Host 'VBOXSUP STATE:          4 / RUNNING'
    Write-Host 'AUTHORIZED MUTATION:    startvm TARGET --type gui / ONCE'
    Write-Host 'AUTOMATIC ROLLBACK:     NONE'

    $Args = @('startvm',$ExpectedMachineUuid,'--type','gui')
    $StartArgsText = $Args -join ' '
    $StartIssued = $true
    $Start = Invoke-Native $VBoxManagePath $Args 'fresh ISO controlled start'
    $StartExit = [int]$Start.ExitCode
    $StartOutput = @($Start.Output)
    Require-Success $Start

    $PostInfoResult = Invoke-Native $VBoxManagePath @('showvminfo',$ExpectedMachineUuid,'--machinereadable') 'post-start showvminfo'
    Require-Success $PostInfoResult
    $PostInfo = Convert-MachineReadable $PostInfoResult.Output
    if (-not $PostInfo.ContainsKey('VMState')) { throw 'post-start VMState missing' }
    $PostState = [string]$PostInfo['VMState']

    $PostList = Invoke-Native $VBoxManagePath @('list','runningvms') 'post-start running inventory'
    Require-Success $PostList
    $PostRows = @($PostList.Output | Where-Object { $_.Trim().Length -gt 0 })
    $PostRunningCount = $PostRows.Count
    if ($PostState -cne 'running') { throw "post-start VMState mismatch: $PostState" }
    if ($PostRows.Count -ne 1 -or $PostRows[0].Trim() -cne $ExpectedRow) { throw "post-start running inventory mismatch: $($PostRows -join '|')" }
    Require-VBoxSupRunning

    Write-StartReport $StartReport 'FRESH-ISO-START-ACCEPTED-HOST-RUNNING-VISUAL-PROOF-PENDING' $PrepHash $ManifestHash $StartArgsText $StartExit $StartOutput $PostState $PostRunningCount ''
    $StartReportHash = (Get-FileHash -LiteralPath $StartReport -Algorithm SHA256).Hash

    Write-Host "START EXIT CODE:        $StartExit"
    Write-Host "POST-START VM STATE:    $PostState"
    Write-Host "POST-START RUNNING VMS: $PostRunningCount"
    Write-Host 'POST-START VBOXSUP:     4'
    Write-Host "START REPORT:           $StartReport"
    Write-Host "START REPORT SHA256:    $StartReportHash"
    Write-Host 'GUEST VISUAL BOOT:      NOT-OBSERVED-BY-HOST-SCRIPT'
    Write-Host 'CONTROLVM:              NOT-EXECUTED'
    Write-Host 'COMPILER BUILD:         NOT-EXECUTED'
    Write-Host 'VERDICT:                FRESH ISO START ACCEPTED / HOST RUNNING / VISUAL PROOF PENDING'
}
catch {
    $ErrorText = $_.Exception.Message
    if ($StartIssued -and -not (Test-Path -LiteralPath $StartReport)) {
        try {
            Write-StartReport $StartReport 'FRESH-ISO-START-ISSUED-FAILED-OR-POST-OBSERVATION-FAILED' $PrepHash $ManifestHash $StartArgsText $StartExit $StartOutput $PostState $PostRunningCount $ErrorText
            Write-Host "START FAILURE REPORT:   $StartReport"
            Write-Host "FAILURE REPORT SHA256:  $((Get-FileHash -LiteralPath $StartReport -Algorithm SHA256).Hash)"
            Write-Host 'AUTOMATIC ROLLBACK:     NOT-EXECUTED'
        }
        catch { }
    }
    throw
}
finally {
    [Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$OriginalVBoxHome,[EnvironmentVariableTarget]::Process)
}
