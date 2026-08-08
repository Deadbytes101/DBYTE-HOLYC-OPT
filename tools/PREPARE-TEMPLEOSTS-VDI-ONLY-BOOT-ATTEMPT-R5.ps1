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
    [string]$RehearsalVerificationReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$BootReadinessReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SealedRehearsalRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$BootAttemptRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedR4Blob = 'fcdec4c784f2d0610d8227aeb95ac138fa7e77d4'
$R4Relative = 'tools/PREPARE-TEMPLEOSTS-VDI-ONLY-BOOT-ATTEMPT-R4.ps1'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$R4Path = Join-Path $RepoRoot (
    $R4Relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
)

function Invoke-GitRead {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Captured = @(
        & git -C $RepoRoot @Arguments 2>&1 |
            ForEach-Object { [string]$_ }
    )
    if ($LASTEXITCODE -ne 0) {
        throw "${Label} failed`n$($Captured -join "`n")"
    }
    return $Captured
}

function Invoke-ExactReplacement {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Old,
        [Parameter(Mandatory = $true)][string]$New,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $OldCount = [regex]::Matches(
        $Source,
        [regex]::Escape($Old),
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    ).Count
    $NewCountBefore = [regex]::Matches(
        $Source,
        [regex]::Escape($New),
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    ).Count
    if ($OldCount -ne 1 -or $NewCountBefore -ne 0) {
        throw (
            "${Label} source cardinality mismatch: " +
            "old=$OldCount new_before=$NewCountBefore"
        )
    }

    $Patched = $Source.Replace($Old, $New)
    $OldOccurrencesPerNew = [regex]::Matches(
        $New,
        [regex]::Escape($Old),
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    ).Count
    $OldCountAfter = [regex]::Matches(
        $Patched,
        [regex]::Escape($Old),
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    ).Count
    $NewCountAfter = [regex]::Matches(
        $Patched,
        [regex]::Escape($New),
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    ).Count
    if (
        $OldCountAfter -ne $OldOccurrencesPerNew -or
        $NewCountAfter -ne 1
    ) {
        throw (
            "${Label} replacement mismatch: " +
            "old_after=$OldCountAfter " +
            "expected_old_after=$OldOccurrencesPerNew " +
            "new_after=$NewCountAfter"
        )
    }
    return $Patched
}

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Text)

    $Bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Text)
    $Sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return (
            [System.BitConverter]::ToString($Sha.ComputeHash($Bytes))
        ).Replace('-', '')
    }
    finally {
        $Sha.Dispose()
    }
}

function ConvertTo-SingleQuotedLiteral {
    param([Parameter(Mandatory = $true)][string]$Value)

    return "'" + $Value.Replace("'", "''") + "'"
}

function Get-ExactPSScriptRootVariableCount {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Tokens = $null
    $Errors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseInput(
        $Text,
        [ref]$Tokens,
        [ref]$Errors
    )
    $ParseErrors = @($Errors)
    if ($ParseErrors.Count -ne 0) {
        throw (
            "${Label} PowerShell parse failed: " +
            (($ParseErrors | ForEach-Object { $_.Message }) -join ' | ')
        )
    }

    $Matches = @(
        $Ast.FindAll(
            {
                param($Node)
                $Node -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $Node.VariablePath.UserPath -ceq 'PSScriptRoot'
            },
            $true
        )
    )
    return $Matches.Count
}

if (-not (Test-Path -LiteralPath $R4Path -PathType Leaf)) {
    throw "R4 preparer missing: $R4Path"
}

$TreeBlob = @(
    Invoke-GitRead `
        -Arguments @('rev-parse', "HEAD`:$R4Relative") `
        -Label 'R4 preparer tree blob'
)
$LocalBlob = @(
    Invoke-GitRead `
        -Arguments @('hash-object', '--', $R4Relative) `
        -Label 'R4 preparer local blob'
)
if (
    $TreeBlob.Count -ne 1 -or
    $LocalBlob.Count -ne 1 -or
    $TreeBlob[0] -cne $ExpectedR4Blob -or
    $LocalBlob[0] -cne $ExpectedR4Blob
) {
    throw (
        'R4 preparer blob mismatch: ' +
        "tree=$($TreeBlob -join '|') local=$($LocalBlob -join '|')"
    )
}

$Source = [System.IO.File]::ReadAllText($R4Path)

$OldR4InjectionAnchor = @'
$Source = [System.IO.File]::ReadAllText($R3Path)

$OldBeforeTokenGuard = @'
'@
$OldR3HelpProbeInjectionBase64 = 'JFBhdGNoZWRTb3VyY2UgPSBJbnZva2UtRXhhY3RSZXBsYWNlbWVudCBgCiAgICAtU291cmNlICRTb3VyY2UgYAogICAgLU9sZCAkT2xkQXR0ZW1wdEJsb2NrIGAKICAgIC1OZXcgJE5ld0F0dGVtcHRCbG9jayBgCiAgICAtTGFiZWwgJ21vZGlmeXZtIGhlbHAgYXJndW1lbnQgYXJyYXlzJwoKJE9sZFJlcG9Sb290QW5jaG9yID0gJyRSZXBvUm9vdCA9IFNwbGl0LVBhdGggLVBhcmVudCAkUFNTY3JpcHRSb290Jw=='
$NewR3HelpProbeInjectionBase64 = 'JFBhdGNoZWRTb3VyY2UgPSBJbnZva2UtRXhhY3RSZXBsYWNlbWVudCBgCiAgICAtU291cmNlICRTb3VyY2UgYAogICAgLU9sZCAkT2xkQXR0ZW1wdEJsb2NrIGAKICAgIC1OZXcgJE5ld0F0dGVtcHRCbG9jayBgCiAgICAtTGFiZWwgJ21vZGlmeXZtIGhlbHAgYXJndW1lbnQgYXJyYXlzJwoKJE9sZEhlbHBQcm9iZUV4ZWN1dGlvbiA9IEAnCiAgICBmb3JlYWNoICgkQXJndW1lbnRzIGluICRBdHRlbXB0cykgewogICAgICAgICRDYXB0dXJlZCA9IEAoCiAgICAgICAgICAgICYgJHNjcmlwdDpWQm94IEBBcmd1bWVudHMgMj4mMSB8CiAgICAgICAgICAgICAgICBGb3JFYWNoLU9iamVjdCB7IFtzdHJpbmddJF8gfQogICAgICAgICkKICAgICAgICBpZiAoJExBU1RFWElUQ09ERSAtZXEgMCkgewogICAgICAgICAgICAkU3VjY2Vzc2Z1bC5BZGQoKCRDYXB0dXJlZCAtam9pbiAiYG4iKSkKICAgICAgICB9CiAgICB9CidACiROZXdIZWxwUHJvYmVFeGVjdXRpb24gPSBAJwogICAgZm9yZWFjaCAoJEFyZ3VtZW50cyBpbiAkQXR0ZW1wdHMpIHsKICAgICAgICAkUHJldmlvdXNFcnJvckFjdGlvblByZWZlcmVuY2UgPSAkRXJyb3JBY3Rpb25QcmVmZXJlbmNlCiAgICAgICAgdHJ5IHsKICAgICAgICAgICAgJEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICdDb250aW51ZScKICAgICAgICAgICAgJENhcHR1cmVkID0gQCgKICAgICAgICAgICAgICAgICYgJHNjcmlwdDpWQm94IEBBcmd1bWVudHMgMj4mMSB8CiAgICAgICAgICAgICAgICAgICAgRm9yRWFjaC1PYmplY3QgeyBbc3RyaW5nXSRfIH0KICAgICAgICAgICAgKQogICAgICAgICAgICAkRXhpdENvZGUgPSAkTEFTVEVYSVRDT0RFCiAgICAgICAgfQogICAgICAgIGZpbmFsbHkgewogICAgICAgICAgICAkRXJyb3JBY3Rpb25QcmVmZXJlbmNlID0gJFByZXZpb3VzRXJyb3JBY3Rpb25QcmVmZXJlbmNlCiAgICAgICAgfQogICAgICAgIGlmICgkRXhpdENvZGUgLWVxIDApIHsKICAgICAgICAgICAgJFN1Y2Nlc3NmdWwuQWRkKCgkQ2FwdHVyZWQgLWpvaW4gImBuIikpCiAgICAgICAgfQogICAgfQonQAokUGF0Y2hlZFNvdXJjZSA9IEludm9rZS1FeGFjdFJlcGxhY2VtZW50IGAKICAgIC1Tb3VyY2UgJFBhdGNoZWRTb3VyY2UgYAogICAgLU9sZCAkT2xkSGVscFByb2JlRXhlY3V0aW9uIGAKICAgIC1OZXcgJE5ld0hlbHBQcm9iZUV4ZWN1dGlvbiBgCiAgICAtTGFiZWwgJ1dpbmRvd3MgUG93ZXJTaGVsbCBuYXRpdmUgaGVscCBzdGRlcnIgY2FwdHVyZScKCiRPbGRSZXBvUm9vdEFuY2hvciA9ICckUmVwb1Jvb3QgPSBTcGxpdC1QYXRoIC1QYXJlbnQgJFBTU2NyaXB0Um9vdCc='
$OldR3HelpProbeInjection = [System.Text.Encoding]::UTF8.GetString(
    [System.Convert]::FromBase64String($OldR3HelpProbeInjectionBase64)
)
$NewR3HelpProbeInjection = [System.Text.Encoding]::UTF8.GetString(
    [System.Convert]::FromBase64String($NewR3HelpProbeInjectionBase64)
)
$NewR4InjectionAnchor = (
    '$Source = [System.IO.File]::ReadAllText($R3Path)' + "`n`n" +
    '$OldR3HelpProbeInjection = [System.Text.Encoding]::UTF8.GetString(' + "`n" +
    '    [System.Convert]::FromBase64String(' +
    (ConvertTo-SingleQuotedLiteral -Value $OldR3HelpProbeInjectionBase64) + ')' + "`n" +
    ')' + "`n" +
    '$NewR3HelpProbeInjection = [System.Text.Encoding]::UTF8.GetString(' + "`n" +
    '    [System.Convert]::FromBase64String(' +
    (ConvertTo-SingleQuotedLiteral -Value $NewR3HelpProbeInjectionBase64) + ')' + "`n" +
    ')' + "`n" +
    '$Source = Invoke-ExactReplacement `' + "`n" +
    '    -Source $Source `' + "`n" +
    '    -Old $OldR3HelpProbeInjection `' + "`n" +
    '    -New $NewR3HelpProbeInjection `' + "`n" +
    "    -Label 'R3 native help stderr correction injection'" + "`n`n" +
    '$OldBeforeTokenGuard = @''' + "`n"
)
$PatchedSource = Invoke-ExactReplacement `
    -Source $Source `
    -Old $OldR4InjectionAnchor `
    -New $NewR4InjectionAnchor `
    -Label 'R4 native help stderr correction seam'

$OldR4RepoRootSeam = @'
$R3Relative = 'tools/PREPARE-TEMPLEOSTS-VDI-ONLY-BOOT-ATTEMPT-R3.ps1'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$R3Path = Join-Path $RepoRoot (
'@
$R4ExactPSScriptRootBefore = Get-ExactPSScriptRootVariableCount `
    -Text $PatchedSource `
    -Label 'R4 source before repository-root injection'
$R4RepoRootCountBefore = [regex]::Matches(
    $PatchedSource,
    [regex]::Escape('$RepoRoot = Split-Path -Parent $PSScriptRoot'),
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
).Count
if ($R4ExactPSScriptRootBefore -ne 1 -or $R4RepoRootCountBefore -ne 1) {
    throw (
        'R4 repository-root syntax cardinality mismatch: ' +
        "exact_variable=$R4ExactPSScriptRootBefore anchor=$R4RepoRootCountBefore"
    )
}

$InjectedRepoRoot = ConvertTo-SingleQuotedLiteral -Value $RepoRoot
$NewR4RepoRootSeam = (
    '$R3Relative = ''tools/PREPARE-TEMPLEOSTS-VDI-ONLY-BOOT-ATTEMPT-R3.ps1''' + "`n" +
    '$RepoRoot = ' + $InjectedRepoRoot + "`n" +
    '$R3Path = Join-Path $RepoRoot (' + "`n"
)
$PatchedSource = Invoke-ExactReplacement `
    -Source $PatchedSource `
    -Old $OldR4RepoRootSeam `
    -New $NewR4RepoRootSeam `
    -Label 'R4 file-backed repository-root injection'

$R4ExactPSScriptRootAfter = Get-ExactPSScriptRootVariableCount `
    -Text $PatchedSource `
    -Label 'patched R4 dynamic source'
if ($R4ExactPSScriptRootAfter -ne 0) {
    throw (
        'patched R4 retains exact PSScriptRoot variable tokens: ' +
        $R4ExactPSScriptRootAfter
    )
}
if ($PatchedSource -ceq $Source) {
    throw 'R5 corrections produced no R4 source change'
}

$PatchedHash = Get-TextSha256 -Text $PatchedSource
$R4 = [scriptblock]::Create($PatchedSource)
$InvokeArguments = @{
    VBoxManagePath = $VBoxManagePath
    ResourceRoot = $ResourceRoot
    RehearsalVerificationReportPath = $RehearsalVerificationReportPath
    BootReadinessReportPath = $BootReadinessReportPath
    SealedRehearsalRoot = $SealedRehearsalRoot
    BootAttemptRoot = $BootAttemptRoot
    OutPath = $OutPath
}

Write-Host "ORIGINAL R4 PREPARER: $ExpectedR4Blob"
Write-Host 'NATIVE STDERR GUARD:  EAP CONTINUE / FINALLY RESTORE'
Write-Host 'HELP EXIT CODE:       CAPTURED BEFORE POLICY RESTORE'
Write-Host 'R4 REPO ROOT ANCHOR:  FILE-BACKED R5 / EXACT-ONE-REPLACEMENT'
Write-Host "INJECTED REPO ROOT:   $RepoRoot"
Write-Host "PATCHED R4 SHA:       $PatchedHash"
& $R4 @InvokeArguments
