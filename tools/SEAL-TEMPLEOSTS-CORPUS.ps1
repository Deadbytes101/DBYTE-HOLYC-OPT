[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$HolyTools,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$IsoPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ExtractRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ManifestPath,

    [switch]$ResumeExistingExtraction
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedIsoBytes = 30558208L
$ExpectedIsoHash = 'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$ExpectedToolsCommit = '37b0457e8735ab8cc34a23f2717fcfb808e6a7a8'

$ToolsRoot = (Resolve-Path -LiteralPath $HolyTools -ErrorAction Stop).Path
$Iso = (Resolve-Path -LiteralPath $IsoPath -ErrorAction Stop).Path
$OutRoot = [System.IO.Path]::GetFullPath($ExtractRoot)
$OutManifest = [System.IO.Path]::GetFullPath($ManifestPath)
$ResourceVerifier = (
    Resolve-Path `
        -LiteralPath (Join-Path $PSScriptRoot 'VERIFY-HOLYC-TOOLS-RESOURCE.ps1') `
        -ErrorAction Stop
).Path

& $ResourceVerifier -Path $ToolsRoot

$IsoItem = Get-Item -LiteralPath $Iso -ErrorAction Stop
$IsoHash = (Get-FileHash -LiteralPath $Iso -Algorithm SHA256).Hash
if ($IsoItem.Length -ne $ExpectedIsoBytes) {
    throw "rare ISO byte count mismatch: expected=$ExpectedIsoBytes actual=$($IsoItem.Length)"
}
if ($IsoHash -cne $ExpectedIsoHash) {
    throw "rare ISO hash mismatch: expected=$ExpectedIsoHash actual=$IsoHash"
}

$ExtractionExists = Test-Path -LiteralPath $OutRoot
if ($ExtractionExists -and -not (Test-Path -LiteralPath $OutRoot -PathType Container)) {
    throw "extraction output is not a directory: $OutRoot"
}
if ($ExtractionExists -and -not $ResumeExistingExtraction) {
    throw @"
Extraction output already exists:
  $OutRoot

To preserve and revalidate an extraction left before manifest creation, rerun with:
  -ResumeExistingExtraction
"@
}
if (-not $ExtractionExists -and $ResumeExistingExtraction) {
    throw "resume requested but extraction output does not exist: $OutRoot"
}
if (Test-Path -LiteralPath $OutManifest) {
    throw "manifest output already exists: $OutManifest"
}

Push-Location $ToolsRoot
try {
    $CheckOutput = @(
        & cargo run --quiet --locked -p holyarchive -- check-iso $Iso 2>&1
    )
    $CheckCode = $LASTEXITCODE
}
finally {
    Pop-Location
}
if ($CheckCode -ne 0) {
    throw "holyarchive check-iso failed:`n$($CheckOutput -join [Environment]::NewLine)"
}

$CheckText = $CheckOutput -join "`n"
foreach ($Required in @(
    'image bytes 30558208',
    'files 1057',
    'legacy CArc 937',
    'modern CArc 0',
    'runtime version 1.10',
    'distro role TS-INTERNAL',
    'holyarchive: check ok'
)) {
    if ($CheckText.IndexOf($Required, [System.StringComparison]::Ordinal) -lt 0) {
        throw "holyarchive identity output missing: $Required"
    }
}

if (-not $ExtractionExists) {
    Push-Location $ToolsRoot
    try {
        $ExtractOutput = @(
            & cargo run --quiet --locked -p holyarchive -- extract-iso $Iso $OutRoot 2>&1
        )
        $ExtractCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    if ($ExtractCode -ne 0) {
        if (Test-Path -LiteralPath $OutRoot) {
            Remove-Item -LiteralPath $OutRoot -Recurse -Force
        }
        throw "holyarchive extract-iso failed:`n$($ExtractOutput -join [Environment]::NewLine)"
    }
    Write-Host 'EXTRACTION:    CREATED'
}
else {
    Write-Host 'EXTRACTION:    RESUME / REVALIDATE'
}

$Raw = Join-Path $OutRoot 'raw'
$Expanded = Join-Path $OutRoot 'expanded'
$Normalized = Join-Path $OutRoot 'holy'
foreach ($RequiredDirectory in @($Raw, $Expanded, $Normalized)) {
    if (-not (Test-Path -LiteralPath $RequiredDirectory -PathType Container)) {
        throw "extraction directory missing: $RequiredDirectory"
    }
}

$ExpandedFull = [System.IO.Path]::GetFullPath($Expanded)
$ExpandedPrefix = $ExpandedFull.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar

function Get-ExpandedRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $Full = [System.IO.Path]::GetFullPath($Path)
    if (-not $Full.StartsWith($ExpandedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "path escapes expanded corpus: $Full"
    }

    return $Full.Substring($ExpandedPrefix.Length).Replace('\', '/')
}

$Files = @(
    Get-ChildItem -LiteralPath $Expanded -Recurse -File |
        Sort-Object FullName
)
if ($Files.Count -eq 0) {
    throw 'expanded rare corpus is empty'
}

$Rows = @(
    foreach ($File in $Files) {
        [pscustomobject]@{
            Path = Get-ExpandedRelativePath -Path $File.FullName
            Bytes = $File.Length
            SHA256 = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash
        }
    }
)

$ManifestDirectory = Split-Path -Parent $OutManifest
if ($ManifestDirectory) {
    New-Item -ItemType Directory -Path $ManifestDirectory -Force | Out-Null
}

$Lines = [System.Collections.Generic.List[string]]::new()
foreach ($Line in @(
    'DBYTE-HOLYC-OPT',
    'TEMPLEOSTS 1.10 INTERNAL EXPANDED CORPUS',
    '',
    "TOOLS_COMMIT`t$ExpectedToolsCommit",
    "ISO_BYTES`t$ExpectedIsoBytes",
    "ISO_SHA256`t$ExpectedIsoHash",
    "EXTRACTION_LAYER`texpanded",
    "PATCH_AUTHORITY`texpanded historical bytes only",
    "FILE_COUNT`t$($Rows.Count)",
    '',
    'FILES',
    "path`tbytes`tSHA256"
)) {
    $Lines.Add($Line)
}

foreach ($Row in $Rows) {
    $Lines.Add("$($Row.Path)`t$($Row.Bytes)`t$($Row.SHA256)")
}

foreach ($Line in @(
    '',
    'BOUNDARY',
    'This manifest seals every file in the expanded historical corpus.',
    'It does not identify the compiler, optimizer passes, or an insertion seam.',
    'The normalized holy tree is navigation only and is not patch authority.',
    'Common public mirrors are not target inputs.',
    '',
    'REPORTS ARE CLAIMS, NOT EVIDENCE.'
)) {
    $Lines.Add($Line)
}

[System.IO.File]::WriteAllText(
    $OutManifest,
    (($Lines -join "`n") + "`n"),
    [System.Text.UTF8Encoding]::new($false)
)

$TrackedWorktree = @(& git -C $ToolsRoot diff --name-only)
$WorktreeCode = $LASTEXITCODE
$TrackedIndex = @(& git -C $ToolsRoot diff --cached --name-only)
$IndexCode = $LASTEXITCODE
if ($WorktreeCode -ne 0 -or $IndexCode -ne 0) {
    throw 'unable to verify resource repository after rare corpus sealing'
}
if ($TrackedWorktree.Count -ne 0 -or $TrackedIndex.Count -ne 0) {
    throw 'resource repository changed during rare corpus sealing'
}

$ManifestHash = (Get-FileHash -LiteralPath $OutManifest -Algorithm SHA256).Hash
Write-Host 'RARE ISO:       PASS'
Write-Host 'ROLE:           TS-INTERNAL'
Write-Host "EXPANDED FILES: $($Rows.Count)"
Write-Host "MANIFEST:       $OutManifest"
Write-Host "MANIFEST SHA256 $ManifestHash"
Write-Host 'COMPILER:       UNRESOLVED'
Write-Host 'SEAM:           UNRESOLVED'
Write-Host 'PATCH STATUS:   NOT AUTHORIZED'
Write-Host 'VERDICT:        PASS'
