[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$ExpectedOut='D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-r3-root-locator.txt'
$ExpectedR3Root='D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r3'
$ExpectedMachineUuid='9c98691e-27cd-4487-a306-587969c2c78c'
$ExpectedVdiUuid='55c1f29d-a681-402e-b90d-bfbb6b09f207'
$ExpectedIsoUuid='ab97b3a5-1331-494d-a917-e85b6e728c45'
$ExpectedVdiHash='90D453A94F075760A11E0772862E60C4B031ED874F28AA396EAE638F7EB8B31B'
$ExpectedIsoHash='DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$ExpectedSecondAttempt='D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-r3-second-controlled-boot-attempt.txt'
$ExpectedSecondAttemptHash='E6780E727989B974727402F782CA16B1B870FBF05591FACA6D131F6244F71430'

$SearchRoots=@(
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT',
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-REHEARSAL',
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-RECOVERY'
)

function Get-FullPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    return [System.IO.Path]::GetFullPath(
        [Environment]::ExpandEnvironmentVariables($Path)
    ).TrimEnd([char]92,[char]47)
}

function Assert-PathEquals {
    param(
        [Parameter(Mandatory=$true)][string]$Observed,
        [Parameter(Mandatory=$true)][string]$Expected,
        [Parameter(Mandatory=$true)][string]$Label
    )
    if(-not [string]::Equals(
        (Get-FullPath $Observed),
        (Get-FullPath $Expected),
        [System.StringComparison]::OrdinalIgnoreCase
    )){
        throw "${Label} mismatch observed=$Observed expected=$Expected"
    }
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

function Add-Row {
    param(
        [Parameter(Position=0)]$Lines,
        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNullOrEmpty()]
        [string]$Key,
        [Parameter(Position=2)]
        [AllowEmptyString()]
        [string]$Value
    )

    if($null -eq $Lines){throw 'Add-Row Lines is null'}
    if($Lines -isnot [System.Collections.Generic.List[string]]){
        throw "Add-Row Lines type mismatch: $($Lines.GetType().FullName)"
    }

    $Lines.Add($Key+"`t"+$Value)
}

$Output=Get-FullPath $OutPath
Assert-PathEquals -Observed $Output -Expected $ExpectedOut -Label 'locator output'
if(Test-Path -LiteralPath $Output){throw "locator report already exists: $Output"}

$SecondAttemptPresent=Test-Path -LiteralPath $ExpectedSecondAttempt -PathType Leaf
$SecondAttemptHash=if($SecondAttemptPresent){(Get-FileHash -LiteralPath $ExpectedSecondAttempt -Algorithm SHA256).Hash}else{'<missing>'}
if($SecondAttemptPresent -and $SecondAttemptHash -cne $ExpectedSecondAttemptHash){
    throw "second attempt report hash mismatch expected=$ExpectedSecondAttemptHash actual=$SecondAttemptHash"
}

$Lines=[System.Collections.Generic.List[string]]::new()
$Lines.Add('DBYTE-HOLYC-OPT')
$Lines.Add('TEMPLEOSTS 1.10 / R3 ROOT LOCATOR / READ-ONLY R2')
$Lines.Add('')
Add-Row $Lines 'expected_r3_root' $ExpectedR3Root
Add-Row $Lines 'expected_r3_root_exists' ([string](Test-Path -LiteralPath $ExpectedR3Root -PathType Container))
Add-Row $Lines 'second_attempt_report_present' ([string]$SecondAttemptPresent)
Add-Row $Lines 'second_attempt_report_sha256' $SecondAttemptHash
$Lines.Add('')

$ExistingSearchRoots=0
foreach($SearchRoot in $SearchRoots){
    $Exists=Test-Path -LiteralPath $SearchRoot -PathType Container
    if($Exists){$ExistingSearchRoots++}
    Add-Row $Lines 'search_root' ($SearchRoot+' | exists='+$Exists)

    if($Exists){
        $TopDirs=@(
            Get-ChildItem -LiteralPath $SearchRoot -Directory -Force -ErrorAction Stop |
                Sort-Object -Property FullName
        )
        foreach($Dir in $TopDirs){
            Add-Row $Lines 'top_level_directory' $Dir.FullName
        }
    }
}
Add-Row $Lines 'existing_search_root_count' ([string]$ExistingSearchRoots)
$Lines.Add('')

$CandidateVboxes=[System.Collections.Generic.List[System.IO.FileInfo]]::new()
$NamedVdis=[System.Collections.Generic.List[System.IO.FileInfo]]::new()
$NamedIsos=[System.Collections.Generic.List[System.IO.FileInfo]]::new()

foreach($SearchRoot in $SearchRoots){
    if(-not(Test-Path -LiteralPath $SearchRoot -PathType Container)){continue}

    foreach($File in @(
        Get-ChildItem -LiteralPath $SearchRoot -Recurse -File -Force -Filter 'Temple1.10.vbox' -ErrorAction SilentlyContinue
    )){[void]$CandidateVboxes.Add($File)}

    foreach($File in @(
        Get-ChildItem -LiteralPath $SearchRoot -Recurse -File -Force -Filter 'Temple1.10.vdi' -ErrorAction SilentlyContinue
    )){[void]$NamedVdis.Add($File)}

    foreach($File in @(
        Get-ChildItem -LiteralPath $SearchRoot -Recurse -File -Force -Filter 'TempleOSTS.iso' -ErrorAction SilentlyContinue
    )){[void]$NamedIsos.Add($File)}
}

$CandidateVboxes=@($CandidateVboxes | Sort-Object -Property FullName -Unique)
$NamedVdis=@($NamedVdis | Sort-Object -Property FullName -Unique)
$NamedIsos=@($NamedIsos | Sort-Object -Property FullName -Unique)

Add-Row $Lines 'candidate_vbox_count' ([string]$CandidateVboxes.Count)
foreach($VBoxFile in $CandidateVboxes){
    $Text=[System.IO.File]::ReadAllText($VBoxFile.FullName)
    $HasMachineUuid=$Text.IndexOf($ExpectedMachineUuid,[System.StringComparison]::OrdinalIgnoreCase) -ge 0
    $HasVdiUuid=$Text.IndexOf($ExpectedVdiUuid,[System.StringComparison]::OrdinalIgnoreCase) -ge 0
    $HasIsoUuid=$Text.IndexOf($ExpectedIsoUuid,[System.StringComparison]::OrdinalIgnoreCase) -ge 0

    Add-Row $Lines 'candidate_vbox' (
        $VBoxFile.FullName+
        ' | sha256='+(Get-HashOrMissing $VBoxFile.FullName)+
        ' | machine_uuid='+$HasMachineUuid+
        ' | vdi_uuid='+$HasVdiUuid+
        ' | iso_uuid='+$HasIsoUuid
    )
}
$Lines.Add('')

Add-Row $Lines 'named_vdi_count' ([string]$NamedVdis.Count)
foreach($VdiFile in $NamedVdis){
    $Hash=Get-HashOrMissing $VdiFile.FullName
    Add-Row $Lines 'named_vdi' (
        $VdiFile.FullName+
        ' | bytes='+(Get-LengthOrMissing $VdiFile.FullName)+
        ' | sha256='+$Hash+
        ' | expected_hash='+($Hash -ceq $ExpectedVdiHash)
    )
}
$Lines.Add('')

Add-Row $Lines 'named_iso_count' ([string]$NamedIsos.Count)
foreach($IsoFile in $NamedIsos){
    $Hash=Get-HashOrMissing $IsoFile.FullName
    Add-Row $Lines 'named_iso' (
        $IsoFile.FullName+
        ' | bytes='+(Get-LengthOrMissing $IsoFile.FullName)+
        ' | sha256='+$Hash+
        ' | expected_hash='+($Hash -ceq $ExpectedIsoHash)
    )
}
$Lines.Add('')

$ProcessRows=[System.Collections.Generic.List[string]]::new()
try{
    $Processes=@(
        Get-CimInstance Win32_Process -ErrorAction Stop |
            Where-Object {
                $_.Name -match '(?i)^(VBoxSVC|VirtualBoxVM|VBoxHeadless|VirtualBox|VBoxManage)\.exe$'
            } |
            Sort-Object -Property Name,ProcessId
    )
    foreach($Process in $Processes){
        $CommandLine=if([string]::IsNullOrWhiteSpace([string]$Process.CommandLine)){'<missing>'}else{[string]$Process.CommandLine}
        [void]$ProcessRows.Add(
            ([string]$Process.Name)+' | pid='+([string]$Process.ProcessId)+' | cmd='+$CommandLine
        )
    }
}catch{
    [void]$ProcessRows.Add('<cim-query-error> '+$_.Exception.Message)
}
Add-Row $Lines 'virtualbox_process_row_count' ([string]$ProcessRows.Count)
foreach($Row in $ProcessRows){Add-Row $Lines 'virtualbox_process' $Row}
$Lines.Add('')

$Lines.Add('HOST MUTATION`tNOT-EXECUTED')
$Lines.Add('FILE COPY/MOVE/DELETE`tNOT-EXECUTED')
$Lines.Add('VBOXMANAGE`tNOT-EXECUTED')
$Lines.Add('VM START/STOP`tNOT-EXECUTED')
$Lines.Add('ISO PREPARATION`tNOT-EXECUTED')
$Lines.Add('COMPILER BUILD`tNOT-EXECUTED')
$Lines.Add('STATUS`tR3-ROOT-LOCATION-INVENTORIED-READ-ONLY-R2')
$Lines.Add('')
$Lines.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')

$Parent=Split-Path -Parent $Output
if(-not(Test-Path -LiteralPath $Parent -PathType Container)){
    throw "output parent missing: $Parent"
}
[System.IO.File]::WriteAllText(
    $Output,
    (($Lines.ToArray()-join "`n")+"`n"),
    [System.Text.UTF8Encoding]::new($false)
)
$ReportHash=(Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

Write-Host "EXPECTED R3 ROOT:       $ExpectedR3Root"
Write-Host ('EXPECTED ROOT EXISTS:   '+(Test-Path -LiteralPath $ExpectedR3Root -PathType Container))
Write-Host "SEARCH ROOTS PRESENT:   $ExistingSearchRoots / $($SearchRoots.Count)"
Write-Host "CANDIDATE VBOXES:       $($CandidateVboxes.Count)"
Write-Host "NAMED VDIS:             $($NamedVdis.Count)"
Write-Host "NAMED ISOS:             $($NamedIsos.Count)"
Write-Host "VBOX PROCESS ROWS:      $($ProcessRows.Count)"
Write-Host "REPORT:                 $Output"
Write-Host "REPORT SHA256:          $ReportHash"
Write-Host 'HOST MUTATION:          NOT-EXECUTED'
Write-Host 'VBOXMANAGE:             NOT-EXECUTED'
Write-Host 'VERDICT:                R3 ROOT LOCATION INVENTORIED READ-ONLY R2'
