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

$ExpectedBaseBlob = 'bd1ec076b0a34cf32792ffab39c7ced7697f5254'
$BaseRelative = 'tools/PREPARE-TEMPLEOSTS-ISO-BOOT-R1-AFTER-R3-STOP.ps1'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$BasePath = Join-Path $RepoRoot ($BaseRelative.Replace('/',[System.IO.Path]::DirectorySeparatorChar))

function Get-Count {
    param([Parameter(Mandatory=$true)][string]$Text,[Parameter(Mandatory=$true)][string]$Needle)
    if ($Needle.Length -eq 0) { throw 'empty needle' }
    $Count=0
    $Offset=0
    while ($true) {
        $At=$Text.IndexOf($Needle,$Offset,[System.StringComparison]::Ordinal)
        if ($At -lt 0) { break }
        $Count++
        $Offset=$At+$Needle.Length
    }
    return $Count
}

function Apply-Patch {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][string]$Old,
        [Parameter(Mandatory=$true)][string]$New,
        [Parameter(Mandatory=$true)][string]$Label
    )
    $OldBefore=Get-Count -Text $Text -Needle $Old
    $NewBefore=Get-Count -Text $Text -Needle $New
    if ($OldBefore -ne 1 -or $NewBefore -ne 0) {
        throw "R2 precondition mismatch $Label old=$OldBefore new=$NewBefore"
    }
    $Patched=$Text.Replace($Old,$New)
    $OldAfter=Get-Count -Text $Patched -Needle $Old
    $NewAfter=Get-Count -Text $Patched -Needle $New
    if ($OldAfter -ne 0 -or $NewAfter -ne 1) {
        throw "R2 postcondition mismatch $Label old=$OldAfter new=$NewAfter"
    }
    return $Patched
}

if (-not (Test-Path -LiteralPath $BasePath -PathType Leaf)) { throw "base ISO preparer missing: $BasePath" }
$Tree=@(& git -C $RepoRoot rev-parse "HEAD:$BaseRelative" 2>&1 | ForEach-Object {[string]$_})
if ($LASTEXITCODE -ne 0 -or $Tree.Count -ne 1) { throw "base tree blob query failed: $($Tree -join '|')" }
$Local=@(& git -C $RepoRoot hash-object -- $BaseRelative 2>&1 | ForEach-Object {[string]$_})
if ($LASTEXITCODE -ne 0 -or $Local.Count -ne 1) { throw "base local blob query failed: $($Local -join '|')" }
if ($Tree[0].Trim() -cne $ExpectedBaseBlob -or $Local[0].Trim() -cne $ExpectedBaseBlob) {
    throw "base preparer blob mismatch expected=$ExpectedBaseBlob tree=$($Tree[0]) local=$($Local[0])"
}

$Source=[System.IO.File]::ReadAllText($BasePath)

$OldSnapshot=@'
    if ($Result.ExitCode -eq 0) { return [string[]]@($Result.Output | Where-Object { $_.Trim().Length -gt 0 }) }
'@
$NewSnapshot=@'
    if ($Result.ExitCode -eq 0) {
        return [string[]]@(
            $Result.Output |
                Where-Object { $_ -match '^Snapshot(Name|UUID|Node)' }
        )
    }
'@
$Source=Apply-Patch -Text $Source -Old $OldSnapshot -New $NewSnapshot -Label 'snapshot-filter'

$OldRuntime=@'
Wait-VBoxSVCExit

$MachineRoot = Join-Path $NewRoot 'Machine'
'@
$NewRuntime=@'
Wait-VBoxSVCExit
$RuntimeProcesses = @(
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProcessName -match '(?i)^(VBoxSVC|VirtualBoxVM|VBoxHeadless|VirtualBox)$'
        }
)
if ($RuntimeProcesses.Count -ne 0) {
    throw (
        'VirtualBox runtime process remains after R3 stop: ' +
        (($RuntimeProcesses | ForEach-Object { "$($_.ProcessName):$($_.Id)" }) -join ', ')
    )
}

$MachineRoot = Join-Path $NewRoot 'Machine'
'@
$Source=Apply-Patch -Text $Source -Old $OldRuntime -New $NewRuntime -Label 'runtime-process-gate'

$OldEarlyRemove=@'
    Remove-Item -LiteralPath $IncompletePath -Force -ErrorAction Stop

    $Report = [System.Collections.Generic.List[string]]::new()
'@
$NewEarlyRemove=@'
    $Steps.Add('MANIFEST-WRITTEN-INCOMPLETE-MARKER-RETAINED')

    $Report = [System.Collections.Generic.List[string]]::new()
'@
$Source=Apply-Patch -Text $Source -Old $OldEarlyRemove -New $NewEarlyRemove -Label 'retain-incomplete-marker'

$OldReportHash=@'
    $OutputHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

    Write-Host "R3 STOP REPORT SHA256:  $StopReportHash"
'@
$NewReportHash=@'
    $OutputHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash
    Remove-Item -LiteralPath $IncompletePath -Force -ErrorAction Stop

    Write-Host "R3 STOP REPORT SHA256:  $StopReportHash"
'@
$Source=Apply-Patch -Text $Source -Old $OldReportHash -New $NewReportHash -Label 'remove-marker-after-report-hash'

$Tokens=$null
$ParseErrors=$null
[void][System.Management.Automation.Language.Parser]::ParseInput($Source,[ref]$Tokens,[ref]$ParseErrors)
if (@($ParseErrors).Count -ne 0) {
    throw 'patched ISO preparer parse failed: '+((@($ParseErrors)|ForEach-Object{$_.Message}) -join ' | ')
}

$Bytes=[System.Text.UTF8Encoding]::new($false).GetBytes($Source)
$Sha=[System.Security.Cryptography.SHA256]::Create()
try { $PatchedHash=-join($Sha.ComputeHash($Bytes)|ForEach-Object{$_.ToString('X2')}) }
finally { $Sha.Dispose() }

Write-Host "BOUND ISO PREPARER:     $ExpectedBaseBlob"
Write-Host 'CORRECTION 1:           SNAPSHOT ROWS FILTERED TO ACTUAL SNAPSHOT KEYS'
Write-Host 'CORRECTION 2:           NO VBOX RUNTIME PROCESS BEFORE NEW ISOLATED HOME'
Write-Host 'CORRECTION 3:           INCOMPLETE MARKER RETAINED UNTIL REPORT HASHED'
Write-Host 'REPLACEMENTS:           EXACT 1 -> 1 / 1 -> 1 / 1 -> 1 / 1 -> 1'
Write-Host 'VM START:               NONE'
Write-Host "PATCHED PREPARER SHA:   $PatchedHash"

$Runner=[scriptblock]::Create($Source)
& $Runner `
    -VBoxManagePath $VBoxManagePath `
    -R3Root $R3Root `
    -R3StopReportPath $R3StopReportPath `
    -SealedRehearsalRoot $SealedRehearsalRoot `
    -RehearsalVerificationReportPath $RehearsalVerificationReportPath `
    -BootReadinessReportPath $BootReadinessReportPath `
    -IsoBootRoot $IsoBootRoot `
    -OutPath $OutPath
