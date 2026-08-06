[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TempleOS
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path -LiteralPath $TempleOS -ErrorAction Stop).Path
$Verifier = Join-Path $PSScriptRoot 'VERIFY-TEMPLEOS-TARGET.ps1'
$Patch = Join-Path $PSScriptRoot '..\patch\templeos-5.03\0001-add-optdeadbyte-gate.patch'
$Source = Join-Path $PSScriptRoot '..\patch\templeos-5.03\Compiler\OptDeadByte.HC'
$Destination = Join-Path $Root 'Compiler\OptDeadByte.HC'

$Verifier = (Resolve-Path -LiteralPath $Verifier -ErrorAction Stop).Path
$Patch = (Resolve-Path -LiteralPath $Patch -ErrorAction Stop).Path
$Source = (Resolve-Path -LiteralPath $Source -ErrorAction Stop).Path

& $Verifier -Path $Root

$Copied = $false
try {
    Copy-Item -LiteralPath $Source -Destination $Destination -ErrorAction Stop
    $Copied = $true

    $ApplyOutput = & git -C $Root apply --whitespace=error-all -- $Patch 2>&1
    if ($LASTEXITCODE -ne 0) {
        $Joined = ($ApplyOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "integration patch failed:`n$Joined"
    }

    $DiffCheck = & git -C $Root diff --check 2>&1
    if ($LASTEXITCODE -ne 0) {
        $Joined = ($DiffCheck | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "patched tree failed git diff --check:`n$Joined"
    }

    $Changed = & git -C $Root status --short --untracked-files=all 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "unable to inspect patched tree"
    }

    $Expected = @(
        ' M Compiler/CExts.HC',
        ' M Compiler/Compiler.PRJ',
        ' M Compiler/PrsLib.HC',
        '?? Compiler/OptDeadByte.HC'
    )
    $Actual = @($Changed | ForEach-Object { $_.ToString().Replace('\', '/') })

    if (($Actual -join "`n") -ne ($Expected -join "`n")) {
        throw (
            "unexpected patched tree:`n" +
            ($Actual -join "`n")
        )
    }

    Write-Host "INSTALL:  FOUNDATION"
    Write-Host "REWRITE:  DISABLED"
    Write-Host "VERIFIER: ACTIVE"
    Write-Host "FILES:    4"
    Write-Host "VERDICT:  PASS"
}
catch {
    & git -C $Root apply --reverse --whitespace=nowarn -- $Patch 2>$null
    if ($Copied -and (Test-Path -LiteralPath $Destination)) {
        Remove-Item -LiteralPath $Destination -Force
    }
    throw
}
