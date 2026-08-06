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
    [string]$ManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedIsoBytes = 30558208L
$ExpectedIsoHash = 'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'
$ExpectedToolsCommit = '37b0457e8735ab8cc34a23f2717fcfb808e6a7a8'
$RequiredMarkers = [ordered]@{
    COCCompile = 'COCCompile('
    OptPass6 = 'OptPass6('
    OptPass789A = 'OptPass789A('
    CIntermediateCode = 'CIntermediateCode'
}

$ToolsRoot = (Resolve-Path -LiteralPath $HolyTools -ErrorAction Stop).Path
$Iso = (Resolve-Path -LiteralPath $IsoPath -ErrorAction Stop).Path
$OutRoot = [System.IO.Path]::GetFullPath($ExtractRoot)
$OutManifest = [System.IO.Path]::GetFullPath($ManifestPath)
$ResourceVerifier = Join-Path $PSScriptRoot 'VERIFY-HOLYC-TOOLS-RESOURCE.ps1'
$ResourceVerifier = (Resolve-Path -LiteralPath $ResourceVerifier -ErrorAction Stop).Path

& $ResourceVerifier -Path $ToolsRoot

$IsoItem = Get-Item -LiteralPath $Iso -ErrorAction Stop
$IsoHash = (Get-FileHash -LiteralPath $Iso -Algorithm SHA256).Hash
if ($IsoItem.Length -ne $ExpectedIsoBytes) {
    throw "rare ISO byte count mismatch: expected=$ExpectedIsoBytes actual=$($IsoItem.Length)"
}
if ($IsoHash -cne $ExpectedIsoHash) {
    throw "rare ISO hash mismatch: expected=$ExpectedIsoHash actual=$IsoHash"
}

if (Test-Path -LiteralPath $OutRoot) {
    throw "extraction output already exists: $OutRoot"
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

$Expanded = Join-Path $OutRoot 'expanded'
$Raw = Join-Path $OutRoot 'raw'
$Normalized = Join-Path $OutRoot 'holy'
foreach ($RequiredDirectory in @($Raw, $Expanded, $Normalized)) {
    if (-not (Test-Path -LiteralPath $RequiredDirectory -PathType Container)) {
        throw "extraction directory missing: $RequiredDirectory"
    }
}

$Files = @(
    Get-ChildItem -LiteralPath $Expanded -Recurse -File |
        Sort-Object FullName
)
if ($Files.Count -eq 0) {
    throw 'expanded rare corpus is empty'
}

$MarkerHits = [System.Collections.Generic.List[object]]::new()
foreach ($File in $Files) {
    if ($File.Length -gt 16MB) {
        continue
    }

    $Bytes = [System.IO.File]::ReadAllBytes($File.FullName)
    $Text = [System.Text.Encoding]::Latin1.GetString($Bytes)

    foreach ($Marker in $RequiredMarkers.GetEnumerator()) {
        if ($Text.IndexOf($Marker.Value, [System.StringComparison]::Ordinal) -ge 0) {
            $Relative = [System.IO.Path]::GetRelativePath($Expanded, $File.FullName).Replace('\', '/')
            $MarkerHits.Add([pscustomobject]@{
                Marker = $Marker.Key
                RelativePath = $Relative
                FullPath = $File.FullName
            })
        }
    }
}

foreach ($Marker in $RequiredMarkers.Keys) {
    if (@($MarkerHits | Where-Object { $_.Marker -ceq $Marker }).Count -eq 0) {
        throw "rare compiler marker not found in expanded bytes: $Marker"
    }
}

function Find-CompilerRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    $Directory = [System.IO.DirectoryInfo](Split-Path -Parent $FilePath)
    while ($null -ne $Directory) {
        if ($Directory.Name -in @('Compiler', 'COMPILE')) {
            return $Directory.FullName
        }
        if ($Directory.FullName -ceq $Expanded) {
            break
        }
        $Directory = $Directory.Parent
    }

    return Split-Path -Parent $FilePath
}

$CompilerRoots = @(
    $MarkerHits |
        ForEach-Object { Find-CompilerRoot -FilePath $_.FullPath } |
        Sort-Object -Unique
)

$CompilerFiles = @(
    @(
        foreach ($Root in $CompilerRoots) {
            Get-ChildItem -LiteralPath $Root -Recurse -File
        }
    ) | Sort-Object FullName -Unique
)

if ($CompilerFiles.Count -eq 0) {
    throw 'no rare compiler files were selected'
}

$Rows = @(
    foreach ($File in $CompilerFiles) {
        $Relative = [System.IO.Path]::GetRelativePath($Expanded, $File.FullName).Replace('\', '/')
        $Hash = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash
        [pscustomobject]@{
            Path = $Relative
            Bytes = $File.Length
            SHA256 = $Hash
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
    'TEMPLEOSTS 1.10 INTERNAL COMPILER CORPUS',
    '',
    "TOOLS_COMMIT`t$ExpectedToolsCommit",
    "ISO_BYTES`t$ExpectedIsoBytes",
    "ISO_SHA256`t$ExpectedIsoHash",
    "EXTRACTION_LAYER`texpanded",
    'PATCH_AUTHORITY`texpanded historical bytes only',
    '',
    'MARKERS',
    'marker`tpath'
)) {
    $Lines.Add($Line)
}

foreach ($Hit in ($MarkerHits | Sort-Object Marker, RelativePath)) {
    $Lines.Add("$($Hit.Marker)`t$($Hit.RelativePath)")
}

foreach ($Line in @(
    '',
    'COMPILER FILES',
    'path`tbytes`tSHA256'
)) {
    $Lines.Add($Line)
}

foreach ($Row in $Rows) {
    $Lines.Add("$($Row.Path)`t$($Row.Bytes)`t$($Row.SHA256)")
}

foreach ($Line in @(
    '',
    'BOUNDARY',
    'No compiler patch has been applied.',
    'The normalized holy tree is not patch authority.',
    'Common public mirrors are not target inputs.',
    'The insertion seam remains unsealed until reviewed from these exact files.',
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
Write-Host "RARE ISO:       PASS"
Write-Host "ROLE:           TS-INTERNAL"
Write-Host "EXPANDED FILES: $($Files.Count)"
Write-Host "COMPILER FILES: $($Rows.Count)"
Write-Host "MARKER HITS:    $($MarkerHits.Count)"
Write-Host "MANIFEST:       $OutManifest"
Write-Host "MANIFEST SHA256 $ManifestHash"
Write-Host "PATCH STATUS:   NOT AUTHORIZED"
Write-Host "VERDICT:        PASS"
