[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-ISOBOOT-FRESH-R1'
$RuntimeReport = Join-Path $Root 'RUNTIME-STATE-R1.txt'
$VBoxLog = Join-Path (Join-Path $Root 'Machine\Logs') 'VBox.log'
$HardeningLog = Join-Path (Join-Path $Root 'Machine\Logs') 'VBoxHardening.log'
$Output = Join-Path $Root 'POWEROFF-CAUSE-R1.txt'
$ExpectedRuntimeHash = '0C4D594761ED669BBDD096B8B73BECD05685A8D1CE0568DAFC4849235E5EBC8A'
$ExpectedVBoxLogHash = '0204349284DE922DAAF831B3C0C848A7DA63C733ED545390CB436AAE037B17C5'
$ExpectedHardeningHash = '6D316434677F0C97794CA47468947DBB697B1397F8BD342A5E6BFC9C73EB9A75'

foreach ($Path in @($RuntimeReport,$VBoxLog,$HardeningLog)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "missing: $Path" }
}
if (Test-Path -LiteralPath $Output) { throw "output exists: $Output" }
if ((Get-FileHash -LiteralPath $RuntimeReport -Algorithm SHA256).Hash -cne $ExpectedRuntimeHash) { throw 'runtime report hash mismatch' }
if ((Get-FileHash -LiteralPath $VBoxLog -Algorithm SHA256).Hash -cne $ExpectedVBoxLogHash) { throw 'VBox.log hash mismatch' }
if ((Get-FileHash -LiteralPath $HardeningLog -Algorithm SHA256).Hash -cne $ExpectedHardeningHash) { throw 'VBoxHardening.log hash mismatch' }

$Rows = [System.IO.File]::ReadAllLines($VBoxLog)
$StateIndexes = [System.Collections.Generic.List[int]]::new()
$CandidateIndexes = [System.Collections.Generic.List[int]]::new()
$ErrorIndexes = [System.Collections.Generic.List[int]]::new()

for ($I = 0; $I -lt $Rows.Length; $I++) {
    $Row = $Rows[$I]
    if ($Row -match '(?i)(Changing the VM state from|Machine state changed to)') { [void]$StateIndexes.Add($I) }
    if ($Row -match '(?i)(ACPI.*power|power button|guest.*shutdown|shutdown.*guest|powering.?off|VMSetError|Guru Meditation|fatal error|runtime error|assertion failed|VERR_[A-Z0-9_]+|GUI:.*(close|quit)|aboutToQuit)') { [void]$CandidateIndexes.Add($I) }
    if ($Row -match '(?i)(VMSetError|Guru Meditation|fatal error|runtime error|assertion failed|VERR_[A-Z0-9_]+)') { [void]$ErrorIndexes.Add($I) }
}

$DestroyIndex = -1
for ($I = 0; $I -lt $Rows.Length; $I++) {
    if ($Rows[$I] -match "Changing the VM state from '.*' to 'DESTROYING'") { $DestroyIndex = $I; break }
}

$PreDestroyCandidates = @($CandidateIndexes | Where-Object { $DestroyIndex -lt 0 -or $_ -lt $DestroyIndex })
$PreDestroyErrors = @($ErrorIndexes | Where-Object { $DestroyIndex -lt 0 -or $_ -lt $DestroyIndex })
$ContextIndexes = [System.Collections.Generic.SortedSet[int]]::new()
foreach ($Index in @($StateIndexes) + @($PreDestroyCandidates)) {
    $First = [Math]::Max(0,$Index - 6)
    $Last = [Math]::Min($Rows.Length - 1,$Index + 6)
    for ($J = $First; $J -le $Last; $J++) { [void]$ContextIndexes.Add($J) }
}

$Verdict = if ($PreDestroyErrors.Count -gt 0) {
    'ERROR-MARKERS-BEFORE-DESTROYING-OBSERVED'
} elseif ($PreDestroyCandidates.Count -gt 0) {
    'CANDIDATE-POWEROFF-MARKERS-OBSERVED'
} else {
    'POWEROFF-TRIGGER-UNRESOLVED-IN-VBOX-LOG'
}

$Out = [System.Collections.Generic.List[string]]::new()
[void]$Out.Add('DBYTE-HOLYC-OPT')
[void]$Out.Add('TEMPLEOSTS 1.10 / FRESH ISO BOOT R1 / POWEROFF CAUSE READ-ONLY')
[void]$Out.Add('')
[void]$Out.Add("runtime_report_sha256`t$ExpectedRuntimeHash")
[void]$Out.Add("vbox_log_sha256`t$ExpectedVBoxLogHash")
[void]$Out.Add("hardening_log_sha256`t$ExpectedHardeningHash")
[void]$Out.Add("vbox_log_lines`t$($Rows.Length)")
[void]$Out.Add("state_transition_rows`t$($StateIndexes.Count)")
[void]$Out.Add("pre_destroy_candidate_rows`t$($PreDestroyCandidates.Count)")
[void]$Out.Add("pre_destroy_error_rows`t$($PreDestroyErrors.Count)")
[void]$Out.Add("destroying_line`t$(if($DestroyIndex -ge 0){$DestroyIndex + 1}else{'<missing>'})")
[void]$Out.Add("verdict`t$Verdict")
[void]$Out.Add('')
foreach ($Index in $StateIndexes) { [void]$Out.Add("state`t$($Index + 1)`t$($Rows[$Index])") }
[void]$Out.Add('')
foreach ($Index in $PreDestroyCandidates) { [void]$Out.Add("candidate`t$($Index + 1)`t$($Rows[$Index])") }
[void]$Out.Add('')
foreach ($Index in $ContextIndexes) { [void]$Out.Add("context`t$($Index + 1)`t$($Rows[$Index])") }
[void]$Out.Add('')
[void]$Out.Add('VM START/STOP/RESET`tNOT-EXECUTED')
[void]$Out.Add('CONTROLVM`tNOT-EXECUTED')
[void]$Out.Add('STORAGE MUTATION`tNOT-EXECUTED')
[void]$Out.Add('SERVICE MUTATION`tNOT-EXECUTED')
[void]$Out.Add('COMPILER BUILD`tNOT-EXECUTED')
[void]$Out.Add('')
[void]$Out.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')

[System.IO.File]::WriteAllText($Output,(($Out.ToArray() -join "`n") + "`n"),[System.Text.UTF8Encoding]::new($false))
$Hash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

Write-Host "VBOX LOG LINES: $($Rows.Length)"
Write-Host "STATE ROWS: $($StateIndexes.Count)"
Write-Host "PRE-DESTROY CANDIDATES: $($PreDestroyCandidates.Count)"
Write-Host "PRE-DESTROY ERRORS: $($PreDestroyErrors.Count)"
Write-Host "DESTROYING LINE: $(if($DestroyIndex -ge 0){$DestroyIndex + 1}else{'<missing>'})"
Write-Host "VERDICT: $Verdict"
Write-Host "REPORT: $Output"
Write-Host "REPORT SHA256: $Hash"
