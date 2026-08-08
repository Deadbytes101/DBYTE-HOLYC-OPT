[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PortableVirtualBoxRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$WrapperBinaryInspectionReportPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedSourceBlob = 'f1c28ad864ad6cbf9c4465ac1e15613745f6d000'
$SourceRelative = 'tools/INSPECT-PORTABLE-VIRTUALBOX7-WRAPPER-PE-SURFACE-R2.ps1'

function Get-OccurrenceCount {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Needle
    )

    if ($Needle.Length -eq 0) {
        throw 'empty occurrence needle'
    }

    $Count = 0
    $Offset = 0
    while ($true) {
        $Found = $Text.IndexOf(
            $Needle,
            $Offset,
            [System.StringComparison]::Ordinal
        )
        if ($Found -lt 0) {
            break
        }
        $Count++
        $Offset = $Found + $Needle.Length
    }
    return $Count
}

$RepoRoot = Split-Path -Parent $PSScriptRoot
$SourcePath = Join-Path $RepoRoot $SourceRelative
if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    throw "bound R2 inspector missing: $SourcePath"
}

$TreeBlobRows = @(
    & git -C $RepoRoot rev-parse "HEAD:$SourceRelative" 2>&1 |
        ForEach-Object { [string]$_ }
)
if ($LASTEXITCODE -ne 0 -or $TreeBlobRows.Count -ne 1) {
    throw "tree blob query failed: $($TreeBlobRows -join ' | ')"
}
$TreeBlob = $TreeBlobRows[0].Trim()

$LocalBlobRows = @(
    & git -C $RepoRoot hash-object -- $SourceRelative 2>&1 |
        ForEach-Object { [string]$_ }
)
if ($LASTEXITCODE -ne 0 -or $LocalBlobRows.Count -ne 1) {
    throw "local blob query failed: $($LocalBlobRows -join ' | ')"
}
$LocalBlob = $LocalBlobRows[0].Trim()

if (
    $TreeBlob -cne $ExpectedSourceBlob -or
    $LocalBlob -cne $ExpectedSourceBlob
) {
    throw (
        'bound R2 inspector blob mismatch ' +
        "expected=$ExpectedSourceBlob tree=$TreeBlob local=$LocalBlob"
    )
}

$Source = [System.IO.File]::ReadAllText($SourcePath)
$Old = '    $OrdinalMask = [uint64]0x80000000'
$New = @'
    $OrdinalMask = [uint64]::Parse(
        '80000000',
        [System.Globalization.NumberStyles]::HexNumber,
        [System.Globalization.CultureInfo]::InvariantCulture
    )
'@

$OldBefore = Get-OccurrenceCount -Text $Source -Needle $Old
$NewBefore = Get-OccurrenceCount -Text $Source -Needle $New
if ($OldBefore -ne 1 -or $NewBefore -ne 0) {
    throw "ordinal-mask replacement precondition mismatch: old=$OldBefore new=$NewBefore"
}

$PatchedSource = $Source.Replace($Old, $New)
$OldAfter = Get-OccurrenceCount -Text $PatchedSource -Needle $Old
$NewAfter = Get-OccurrenceCount -Text $PatchedSource -Needle $New
if ($OldAfter -ne 0 -or $NewAfter -ne 1) {
    throw "ordinal-mask replacement postcondition mismatch: old=$OldAfter new=$NewAfter"
}

$Tokens = $null
$ParseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput(
    $PatchedSource,
    [ref]$Tokens,
    [ref]$ParseErrors
)
if ($ParseErrors.Count -ne 0) {
    throw (
        'patched inspector parse failed: ' +
        (($ParseErrors | ForEach-Object { $_.Message }) -join ' | ')
    )
}

$PatchedBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($PatchedSource)
$Sha = [System.Security.Cryptography.SHA256]::Create()
try {
    $PatchedHash = -join (
        $Sha.ComputeHash($PatchedBytes) |
            ForEach-Object { $_.ToString('X2') }
    )
}
finally {
    $Sha.Dispose()
}

Write-Host "BOUND FAILED R2:       $ExpectedSourceBlob"
Write-Host 'CORRECTION:            PE32 ORDINAL MASK UINT64 HEX PARSE'
Write-Host 'REPLACEMENT:           EXACT SOURCE CARDINALITY 1 -> 1'
Write-Host 'PE PARSER LOGIC:       OTHERWISE UNCHANGED'
Write-Host 'WRAPPER EXECUTION:     NONE'
Write-Host 'DRIVER MUTATION:       NONE'
Write-Host "PATCHED INSPECTOR SHA: $PatchedHash"

$Inspector = [scriptblock]::Create($PatchedSource)
& $Inspector `
    -PortableVirtualBoxRoot $PortableVirtualBoxRoot `
    -WrapperBinaryInspectionReportPath $WrapperBinaryInspectionReportPath `
    -OutPath $OutPath
