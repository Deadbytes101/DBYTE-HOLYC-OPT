[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VBoxManagePath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$BootAttemptRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PreparationReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedVersion = '7.0.12r159484'
$ExpectedBootAttemptRoot =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-BOOT\templeosts-1.10-vdi-only-r1'
$ExpectedPreparationReport =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-vdi-only-boot-attempt-preparation.txt'

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
        $Observed,
        $Expected,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "${Label} mismatch: observed=$Observed expected=$Expected"
    }
}

function Get-Utf8Sha256 {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    $Bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Text)
    $Sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [pscustomobject]@{
            Bytes = [int64]$Bytes.Length
            SHA256 = (
                [System.BitConverter]::ToString($Sha.ComputeHash($Bytes))
            ).Replace('-', '')
            Base64 = [System.Convert]::ToBase64String($Bytes)
        }
    }
    finally {
        $Sha.Dispose()
    }
}

function Test-OrdinalContains {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$Needle
    )

    return $Text.IndexOf(
        $Needle,
        [System.StringComparison]::Ordinal
    ) -ge 0
}

function Invoke-NativeCapture {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label
    )

    foreach ($Argument in $Arguments) {
        if ($Argument -notmatch '^[A-Za-z0-9_.:/-]+$') {
            throw "${Label} contains unsupported argument characters: $Argument"
        }
    }

    $StartInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $StartInfo.FileName = $script:VBox
    $StartInfo.Arguments = ($Arguments -join ' ')
    $StartInfo.UseShellExecute = $false
    $StartInfo.CreateNoWindow = $true
    $StartInfo.RedirectStandardOutput = $true
    $StartInfo.RedirectStandardError = $true
    $StartInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $StartInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $Process = [System.Diagnostics.Process]::new()
    $Process.StartInfo = $StartInfo
    try {
        if (-not $Process.Start()) {
            throw "${Label} process did not start"
        }
        $StdoutTask = $Process.StandardOutput.ReadToEndAsync()
        $StderrTask = $Process.StandardError.ReadToEndAsync()
        if (-not $Process.WaitForExit(15000)) {
            try {
                $Process.Kill()
            }
            catch {
                # Preserve the primary timeout classification.
            }
            throw "${Label} timed out after 15 seconds"
        }
        $Process.WaitForExit()
        $Stdout = [string]$StdoutTask.Result
        $Stderr = [string]$StderrTask.Result
        $ExitCode = [int]$Process.ExitCode
    }
    finally {
        $Process.Dispose()
    }

    $StdoutIdentity = Get-Utf8Sha256 -Text $Stdout
    $StderrIdentity = Get-Utf8Sha256 -Text $Stderr
    $Combined = $Stdout + "`n" + $Stderr

    return [pscustomobject]@{
        Label = $Label
        Arguments = [string[]]$Arguments
        ArgumentText = ($Arguments -join ' ')
        ExitCode = $ExitCode
        Stdout = $Stdout
        Stderr = $Stderr
        StdoutBytes = $StdoutIdentity.Bytes
        StdoutSHA256 = $StdoutIdentity.SHA256
        StdoutBase64 = $StdoutIdentity.Base64
        StderrBytes = $StderrIdentity.Bytes
        StderrSHA256 = $StderrIdentity.SHA256
        StderrBase64 = $StderrIdentity.Base64
        ModifyVmUsage = (Test-OrdinalContains -Text $Combined -Needle 'VBoxManage modifyvm')
        ClipboardMode = (Test-OrdinalContains -Text $Combined -Needle '--clipboard-mode')
        Clipboard = (Test-OrdinalContains -Text $Combined -Needle '--clipboard')
        DragAndDrop = (Test-OrdinalContains -Text $Combined -Needle '--drag-and-drop')
        DragAndDropCompact = (Test-OrdinalContains -Text $Combined -Needle '--draganddrop')
    }
}

function Write-Utf8Lines {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    [System.IO.File]::WriteAllText(
        $Path,
        (($Lines -join "`n") + "`n"),
        [System.Text.UTF8Encoding]::new($false)
    )
}

$script:VBox = (
    Resolve-Path -LiteralPath $VBoxManagePath -ErrorAction Stop
).Path
$BootRoot = Get-FullPath -Path $BootAttemptRoot
$PreparationReport = Get-FullPath -Path $PreparationReportPath
$Output = Get-FullPath -Path $OutPath

Assert-PathEquals `
    -Observed $BootRoot `
    -Expected $ExpectedBootAttemptRoot `
    -Label 'boot-attempt root'
Assert-PathEquals `
    -Observed $PreparationReport `
    -Expected $ExpectedPreparationReport `
    -Label 'preparation report'

if (Test-Path -LiteralPath $BootRoot) {
    throw "boot-attempt root already exists: $BootRoot"
}
if (Test-Path -LiteralPath $PreparationReport) {
    throw "preparation report already exists: $PreparationReport"
}
if (Test-Path -LiteralPath $Output) {
    throw "probe report already exists: $Output"
}
$OutputParent = Split-Path -Parent $Output
if (-not (Test-Path -LiteralPath $OutputParent -PathType Container)) {
    throw "probe report parent directory missing: $OutputParent"
}

$OriginalVBoxUserHome = [Environment]::GetEnvironmentVariable(
    'VBOX_USER_HOME',
    [EnvironmentVariableTarget]::Process
)
if (-not [string]::IsNullOrEmpty($OriginalVBoxUserHome)) {
    throw "process VBOX_USER_HOME must be unset: $OriginalVBoxUserHome"
}

$VersionResult = Invoke-NativeCapture `
    -Arguments @('--version') `
    -Label 'VBoxManage version'
$VersionText = ($VersionResult.Stdout + $VersionResult.Stderr).Trim()
if ($VersionResult.ExitCode -ne 0) {
    throw "VBoxManage version exit code mismatch: $($VersionResult.ExitCode)"
}
if ($VersionText -cne $ExpectedVersion) {
    throw "VBoxManage version mismatch: observed=$VersionText expected=$ExpectedVersion"
}

$AttemptVectors = [System.Collections.Generic.List[object]]::new()
$AttemptVectors.Add([string[]]@('modifyvm', '--help'))
$AttemptVectors.Add([string[]]@('--help', 'modifyvm'))
$AttemptVectors.Add([string[]]@('help', 'modifyvm'))
$AttemptVectors.Add([string[]]@('modifyvm'))

$Results = [System.Collections.Generic.List[object]]::new()
for ($Index = 0; $Index -lt $AttemptVectors.Count; $Index++) {
    $Arguments = [string[]]$AttemptVectors[$Index]
    $Results.Add((
        Invoke-NativeCapture `
            -Arguments $Arguments `
            -Label ("modifyvm help attempt {0}" -f ($Index + 1))
    ))
}

if (Test-Path -LiteralPath $BootRoot) {
    throw "boot-attempt root appeared during read-only probe: $BootRoot"
}
if (Test-Path -LiteralPath $PreparationReport) {
    throw "preparation report appeared during read-only probe: $PreparationReport"
}
$FinalVBoxUserHome = [Environment]::GetEnvironmentVariable(
    'VBOX_USER_HOME',
    [EnvironmentVariableTarget]::Process
)
if (-not [string]::Equals(
    $FinalVBoxUserHome,
    $OriginalVBoxUserHome,
    [System.StringComparison]::Ordinal
)) {
    throw (
        'process VBOX_USER_HOME changed during read-only probe: ' +
        "before=$OriginalVBoxUserHome after=$FinalVBoxUserHome"
    )
}

$ReportLines = [System.Collections.Generic.List[string]]::new()
$ReportLines.Add('DBYTE-HOLYC-OPT')
$ReportLines.Add('TEMPLEOSTS 1.10 VBOXMANAGE MODIFYVM HELP SURFACE PROBE')
$ReportLines.Add('')
$ReportLines.Add("created_utc`t$([DateTimeOffset]::UtcNow.ToString('o'))")
$ReportLines.Add("vboxmanage_path`t$script:VBox")
$ReportLines.Add("vboxmanage_version`t$VersionText")
$ReportLines.Add("version_exit_code`t$($VersionResult.ExitCode)")
$ReportLines.Add("boot_attempt_root`t$BootRoot")
$ReportLines.Add("boot_attempt_root_absent`tTrue")
$ReportLines.Add("preparation_report`t$PreparationReport")
$ReportLines.Add("preparation_report_absent`tTrue")
$ReportLines.Add("process_vbox_user_home_before`t$OriginalVBoxUserHome")
$ReportLines.Add("process_vbox_user_home_after`t$FinalVBoxUserHome")
$ReportLines.Add('virtualbox_registry_query`tNOT-EXECUTED')
$ReportLines.Add('virtualbox_mutation`tNOT-EXECUTED')
$ReportLines.Add('vm_start`tNOT-AUTHORIZED')
$ReportLines.Add('')

for ($Index = 0; $Index -lt $Results.Count; $Index++) {
    $Result = $Results[$Index]
    $Number = $Index + 1
    $ReportLines.Add("attempt_${Number}_arguments`t$($Result.ArgumentText)")
    $ReportLines.Add("attempt_${Number}_exit_code`t$($Result.ExitCode)")
    $ReportLines.Add("attempt_${Number}_stdout_utf8_bytes`t$($Result.StdoutBytes)")
    $ReportLines.Add("attempt_${Number}_stdout_sha256`t$($Result.StdoutSHA256)")
    $ReportLines.Add("attempt_${Number}_stdout_base64`t$($Result.StdoutBase64)")
    $ReportLines.Add("attempt_${Number}_stderr_utf8_bytes`t$($Result.StderrBytes)")
    $ReportLines.Add("attempt_${Number}_stderr_sha256`t$($Result.StderrSHA256)")
    $ReportLines.Add("attempt_${Number}_stderr_base64`t$($Result.StderrBase64)")
    $ReportLines.Add("attempt_${Number}_modifyvm_usage_marker`t$($Result.ModifyVmUsage)")
    $ReportLines.Add("attempt_${Number}_clipboard_mode_marker`t$($Result.ClipboardMode)")
    $ReportLines.Add("attempt_${Number}_clipboard_marker`t$($Result.Clipboard)")
    $ReportLines.Add("attempt_${Number}_drag_and_drop_marker`t$($Result.DragAndDrop)")
    $ReportLines.Add("attempt_${Number}_draganddrop_marker`t$($Result.DragAndDropCompact)")
    $ReportLines.Add('')
}

$ReportLines.Add('PROBE`tCOMPLETE')
$ReportLines.Add('BOOT ATTEMPT COPY`tNOT-PREPARED')
$ReportLines.Add('VM START`tNOT-AUTHORIZED')
$ReportLines.Add('RESTORE BOOT`tNOT-OBSERVED')
$ReportLines.Add('RECOVERY POINT`tNOT-SEALED')
$ReportLines.Add('BUILD EXECUTION`tNOT-AUTHORIZED')
$ReportLines.Add('VERDICT`tREAD-ONLY MODIFYVM HELP SURFACE PROBE COMPLETE')

Write-Utf8Lines -Path $Output -Lines $ReportLines.ToArray()
$ReportHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

Write-Host "VBOX VERSION:          $VersionText"
for ($Index = 0; $Index -lt $Results.Count; $Index++) {
    $Result = $Results[$Index]
    $Number = $Index + 1
    Write-Host "ATTEMPT ${Number} ARGS:       $($Result.ArgumentText)"
    Write-Host "ATTEMPT ${Number} EXIT:       $($Result.ExitCode)"
    Write-Host "ATTEMPT ${Number} STDOUT:     $($Result.StdoutBytes) / $($Result.StdoutSHA256)"
    Write-Host "ATTEMPT ${Number} STDERR:     $($Result.StderrBytes) / $($Result.StderrSHA256)"
    Write-Host "ATTEMPT ${Number} USAGE:      $($Result.ModifyVmUsage)"
    Write-Host "ATTEMPT ${Number} CLIP-MODE:  $($Result.ClipboardMode)"
    Write-Host "ATTEMPT ${Number} CLIPBOARD:  $($Result.Clipboard)"
    Write-Host "ATTEMPT ${Number} DND-HYPHEN: $($Result.DragAndDrop)"
    Write-Host "ATTEMPT ${Number} DND-COMPACT:$($Result.DragAndDropCompact)"
}
Write-Host "REPORT:                $Output"
Write-Host "REPORT SHA256:         $ReportHash"
Write-Host 'BOOT ATTEMPT ROOT:     ABSENT'
Write-Host 'VBOX REGISTRY QUERY:   NOT-EXECUTED'
Write-Host 'VBOX MUTATION:         NOT-EXECUTED'
Write-Host 'VM START:              NOT-AUTHORIZED'
Write-Host 'VERDICT:               READ-ONLY MODIFYVM HELP SURFACE PROBE COMPLETE'
