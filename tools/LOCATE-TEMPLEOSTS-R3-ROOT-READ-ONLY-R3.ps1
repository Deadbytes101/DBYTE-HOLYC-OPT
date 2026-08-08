[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$ExpectedOut='D:\TECHNICAL\templeosts-r3-root-locator-r3.txt'
$ExpectedR3Root='D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r3'
$ExpectedEvidenceRoot='D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE'
$ExpectedMachineUuid='9c98691e-27cd-4487-a306-587969c2c78c'
$ExpectedVdiUuid='55c1f29d-a681-402e-b90d-bfbb6b09f207'
$ExpectedIsoUuid='ab97b3a5-1331-494d-a917-e85b6e728c45'
$ExpectedVdiHash='90D453A94F075760A11E0772862E60C4B031ED874F28AA396EAE638F7EB8B31B'
$ExpectedIsoHash='DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$ExpectedIsoBytes=30558208L
$ExpectedVdiBytes=2097152L
$ExpectedSecondAttempt='D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r3-second-controlled-boot-attempt.txt'
$ExpectedSecondAttemptHash='E6780E727989B974727402F782CA16B1B870FBF05591FACA6D131F6244F71430'
$KnownLiveRoot='D:\VirtualBox VMs\Temple1.10'
$KnownLiveIso='D:\TempleOSTS.iso'

function Get-FullPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    return [System.IO.Path]::GetFullPath(
        [Environment]::ExpandEnvironmentVariables($Path)
    ).TrimEnd([char]92,[char]47)
}

function Get-HashOrMissing {
    param([Parameter(Mandatory=$true)][string]$Path)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return '<missing>'}
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-LengthOrMissing {
    param([Parameter(Mandatory=$true)][string]$Path)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return '<missing>'}
    return [string](Get-Item -LiteralPath $Path -Force).Length
}

$Output=Get-FullPath $OutPath
if(-not [string]::Equals($Output,$ExpectedOut,[System.StringComparison]::OrdinalIgnoreCase)){
    throw "locator output mismatch observed=$Output expected=$ExpectedOut"
}
if(Test-Path -LiteralPath $Output){throw "locator report already exists: $Output"}
$Parent=Split-Path -Parent $Output
if(-not(Test-Path -LiteralPath $Parent -PathType Container)){
    throw "known output parent missing: $Parent"
}

$Lines=[System.Collections.Generic.List[string]]::new()
[void]$Lines.Add('DBYTE-HOLYC-OPT')
[void]$Lines.Add('TEMPLEOSTS 1.10 / R3 ROOT LOCATOR / READ-ONLY R3')
[void]$Lines.Add('')
[void]$Lines.Add("expected_r3_root`t$ExpectedR3Root")
[void]$Lines.Add("expected_r3_root_exists`t$([string](Test-Path -LiteralPath $ExpectedR3Root -PathType Container))")
[void]$Lines.Add("historical_evidence_root`t$ExpectedEvidenceRoot")
[void]$Lines.Add("historical_evidence_root_exists`t$([string](Test-Path -LiteralPath $ExpectedEvidenceRoot -PathType Container))")
[void]$Lines.Add("known_live_root`t$KnownLiveRoot")
[void]$Lines.Add("known_live_root_exists`t$([string](Test-Path -LiteralPath $KnownLiveRoot -PathType Container))")
[void]$Lines.Add("known_live_iso`t$KnownLiveIso")
[void]$Lines.Add("known_live_iso_exists`t$([string](Test-Path -LiteralPath $KnownLiveIso -PathType Leaf))")

$SecondAttemptPresent=Test-Path -LiteralPath $ExpectedSecondAttempt -PathType Leaf
$SecondAttemptHash=if($SecondAttemptPresent){(Get-FileHash -LiteralPath $ExpectedSecondAttempt -Algorithm SHA256).Hash}else{'<missing>'}
if($SecondAttemptPresent -and $SecondAttemptHash -cne $ExpectedSecondAttemptHash){
    throw "second attempt report hash mismatch expected=$ExpectedSecondAttemptHash actual=$SecondAttemptHash"
}
[void]$Lines.Add("second_attempt_report_present`t$([string]$SecondAttemptPresent)")
[void]$Lines.Add("second_attempt_report_sha256`t$SecondAttemptHash")
[void]$Lines.Add('')

$SearchRoots=@(
    'D:\TECHNICAL',
    'D:\VirtualBox VMs'
)
foreach($SearchRoot in $SearchRoots){
    $Exists=Test-Path -LiteralPath $SearchRoot -PathType Container
    [void]$Lines.Add("search_root`t$SearchRoot | exists=$Exists")
    if($Exists){
        foreach($Dir in @(
            Get-ChildItem -LiteralPath $SearchRoot -Directory -Force -ErrorAction SilentlyContinue |
                Sort-Object -Property FullName
        )){
            [void]$Lines.Add("top_level_directory`t$($Dir.FullName)")
        }
    }
}
[void]$Lines.Add('')

$CandidateVboxes=@()
$NamedVdis=@()
$NamedIsos=@()
foreach($SearchRoot in $SearchRoots){
    if(-not(Test-Path -LiteralPath $SearchRoot -PathType Container)){continue}

    $CandidateVboxes += @(
        Get-ChildItem -LiteralPath $SearchRoot -Recurse -File -Force -Filter 'Temple1.10.vbox' -ErrorAction SilentlyContinue
    )
    $NamedVdis += @(
        Get-ChildItem -LiteralPath $SearchRoot -Recurse -File -Force -Filter 'Temple1.10.vdi' -ErrorAction SilentlyContinue
    )
    $NamedIsos += @(
        Get-ChildItem -LiteralPath $SearchRoot -Recurse -File -Force -Filter 'TempleOSTS.iso' -ErrorAction SilentlyContinue
    )
}
if(Test-Path -LiteralPath $KnownLiveIso -PathType Leaf){
    $NamedIsos += @(Get-Item -LiteralPath $KnownLiveIso -Force)
}

$CandidateVboxes=@($CandidateVboxes | Sort-Object -Property FullName -Unique)
$NamedVdis=@($NamedVdis | Sort-Object -Property FullName -Unique)
$NamedIsos=@($NamedIsos | Sort-Object -Property FullName -Unique)

[void]$Lines.Add("candidate_vbox_count`t$($CandidateVboxes.Count)")
foreach($VBoxFile in $CandidateVboxes){
    $Text=[System.IO.File]::ReadAllText($VBoxFile.FullName)
    $HasMachineUuid=$Text.IndexOf($ExpectedMachineUuid,[System.StringComparison]::OrdinalIgnoreCase) -ge 0
    $HasVdiUuid=$Text.IndexOf($ExpectedVdiUuid,[System.StringComparison]::OrdinalIgnoreCase) -ge 0
    $HasIsoUuid=$Text.IndexOf($ExpectedIsoUuid,[System.StringComparison]::OrdinalIgnoreCase) -ge 0
    $Hash=Get-HashOrMissing $VBoxFile.FullName
    [void]$Lines.Add(
        "candidate_vbox`t$($VBoxFile.FullName) | sha256=$Hash | machine_uuid=$HasMachineUuid | vdi_uuid=$HasVdiUuid | iso_uuid=$HasIsoUuid"
    )
}
[void]$Lines.Add('')

[void]$Lines.Add("named_vdi_count`t$($NamedVdis.Count)")
foreach($VdiFile in $NamedVdis){
    $Hash=Get-HashOrMissing $VdiFile.FullName
    $Length=Get-LengthOrMissing $VdiFile.FullName
    $Expected=($Hash -ceq $ExpectedVdiHash -and $Length -ceq [string]$ExpectedVdiBytes)
    [void]$Lines.Add(
        "named_vdi`t$($VdiFile.FullName) | bytes=$Length | sha256=$Hash | expected_exact=$Expected"
    )
}
[void]$Lines.Add('')

[void]$Lines.Add("named_iso_count`t$($NamedIsos.Count)")
foreach($IsoFile in $NamedIsos){
    $Hash=Get-HashOrMissing $IsoFile.FullName
    $Length=Get-LengthOrMissing $IsoFile.FullName
    $Expected=($Hash -ceq $ExpectedIsoHash -and $Length -ceq [string]$ExpectedIsoBytes)
    [void]$Lines.Add(
        "named_iso`t$($IsoFile.FullName) | bytes=$Length | sha256=$Hash | expected_exact=$Expected"
    )
}
[void]$Lines.Add('')

$ProcessRows=@()
try{
    $ProcessRows=@(
        Get-CimInstance Win32_Process -ErrorAction Stop |
            Where-Object {
                $_.Name -match '(?i)^(VBoxSVC|VirtualBoxVM|VBoxHeadless|VirtualBox|VBoxManage)\.exe$'
            } |
            Sort-Object -Property Name,ProcessId |
            ForEach-Object {
                $CommandLine=if([string]::IsNullOrWhiteSpace([string]$_.CommandLine)){'<missing>'}else{[string]$_.CommandLine}
                ([string]$_.Name)+' | pid='+([string]$_.ProcessId)+' | cmd='+$CommandLine
            }
    )
}
catch{
    $ProcessRows=@('<cim-query-error> '+$_.Exception.Message)
}
[void]$Lines.Add("virtualbox_process_row_count`t$($ProcessRows.Count)")
foreach($Row in $ProcessRows){[void]$Lines.Add("virtualbox_process`t$Row")}
[void]$Lines.Add('')

$ExactVdiRows=@($NamedVdis | Where-Object {
    (Get-LengthOrMissing $_.FullName) -ceq [string]$ExpectedVdiBytes -and
    (Get-HashOrMissing $_.FullName) -ceq $ExpectedVdiHash
})
$ExactIsoRows=@($NamedIsos | Where-Object {
    (Get-LengthOrMissing $_.FullName) -ceq [string]$ExpectedIsoBytes -and
    (Get-HashOrMissing $_.FullName) -ceq $ExpectedIsoHash
})
$MachineUuidVboxes=@($CandidateVboxes | Where-Object {
    ([System.IO.File]::ReadAllText($_.FullName)).IndexOf($ExpectedMachineUuid,[System.StringComparison]::OrdinalIgnoreCase) -ge 0
})

[void]$Lines.Add("exact_vdi_count`t$($ExactVdiRows.Count)")
[void]$Lines.Add("exact_iso_count`t$($ExactIsoRows.Count)")
[void]$Lines.Add("machine_uuid_vbox_count`t$($MachineUuidVboxes.Count)")
[void]$Lines.Add('')
[void]$Lines.Add("HOST MUTATION`tNOT-EXECUTED")
[void]$Lines.Add("FILE COPY/MOVE/DELETE`tNOT-EXECUTED")
[void]$Lines.Add("VBOXMANAGE`tNOT-EXECUTED")
[void]$Lines.Add("VM START/STOP`tNOT-EXECUTED")
[void]$Lines.Add("ISO PREPARATION`tNOT-EXECUTED")
[void]$Lines.Add("COMPILER BUILD`tNOT-EXECUTED")
[void]$Lines.Add("STATUS`tR3-ROOT-LOCATION-INVENTORIED-READ-ONLY-R3")
[void]$Lines.Add('')
[void]$Lines.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')

[System.IO.File]::WriteAllText(
    $Output,
    (($Lines.ToArray()-join "`n")+"`n"),
    [System.Text.UTF8Encoding]::new($false)
)
$ReportHash=(Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

Write-Host "EXPECTED R3 ROOT:       $ExpectedR3Root"
Write-Host ('EXPECTED ROOT EXISTS:   '+(Test-Path -LiteralPath $ExpectedR3Root -PathType Container))
Write-Host ('EVIDENCE ROOT EXISTS:   '+(Test-Path -LiteralPath $ExpectedEvidenceRoot -PathType Container))
Write-Host ('KNOWN LIVE ROOT EXISTS: '+(Test-Path -LiteralPath $KnownLiveRoot -PathType Container))
Write-Host "CANDIDATE VBOXES:       $($CandidateVboxes.Count)"
Write-Host "MACHINE UUID VBOXES:    $($MachineUuidVboxes.Count)"
Write-Host "NAMED VDIS:             $($NamedVdis.Count)"
Write-Host "EXACT VDIS:             $($ExactVdiRows.Count)"
Write-Host "NAMED ISOS:             $($NamedIsos.Count)"
Write-Host "EXACT ISOS:             $($ExactIsoRows.Count)"
Write-Host "VBOX PROCESS ROWS:      $($ProcessRows.Count)"
Write-Host "REPORT:                 $Output"
Write-Host "REPORT SHA256:          $ReportHash"
Write-Host 'VBOXMANAGE:             NOT-EXECUTED'
Write-Host 'VERDICT:                R3 LOCATION INVENTORIED READ-ONLY R3'
