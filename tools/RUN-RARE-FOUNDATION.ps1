[CmdletBinding()]
param(
    [string]$HolyTools,
    [string]$IsoPath,
    [string]$EvidenceRoot,
    [switch]$ResumeIncompleteExtraction
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedIsoBytes = 30558208L
$ExpectedIsoHash = 'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC'

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$ParentRoot = Split-Path -Parent $RepoRoot
$RareIsoSource = 'UNRESOLVED'

function Resolve-HolyToolsRoot {
    if (-not [string]::IsNullOrWhiteSpace($HolyTools)) {
        return (Resolve-Path -LiteralPath $HolyTools -ErrorAction Stop).Path
    }

    $Sibling = Join-Path $ParentRoot 'DBYTE-HOLYC-TOOLS'
    if (Test-Path -LiteralPath $Sibling -PathType Container) {
        return (Resolve-Path -LiteralPath $Sibling).Path
    }

    throw @"
DBYTE-HOLYC-TOOLS was not found beside this repository.
Expected sibling path:
  $Sibling

Clone or move it there, or run with:
  -HolyTools D:\actual\path\DBYTE-HOLYC-TOOLS
"@
}

function Get-IsoSearchRoots {
    $Roots = [System.Collections.Generic.List[string]]::new()
    foreach ($Candidate in @(
        $ParentRoot,
        (Join-Path $env:USERPROFILE 'Downloads'),
        (Join-Path $env:USERPROFILE 'Desktop'),
        (Join-Path $env:USERPROFILE 'Documents')
    )) {
        if (
            -not [string]::IsNullOrWhiteSpace($Candidate) -and
            (Test-Path -LiteralPath $Candidate -PathType Container)
        ) {
            $Resolved = (Resolve-Path -LiteralPath $Candidate).Path
            if (-not $Roots.Contains($Resolved)) {
                $Roots.Add($Resolved)
            }
        }
    }
    return @($Roots)
}

function Test-RareIso([string]$Path) {
    $Item = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($Item.Length -ne $ExpectedIsoBytes) {
        return $false
    }

    $Hash = (Get-FileHash -LiteralPath $Item.FullName -Algorithm SHA256).Hash
    return $Hash -ceq $ExpectedIsoHash
}

function Resolve-RareIsoPath {
    if (-not [string]::IsNullOrWhiteSpace($IsoPath)) {
        $Resolved = (Resolve-Path -LiteralPath $IsoPath -ErrorAction Stop).Path
        if (-not (Test-RareIso $Resolved)) {
            throw "ISO is not the exact TempleOSTS internal artifact: $Resolved"
        }
        $script:RareIsoSource = 'EXPLICIT'
        return $Resolved
    }

    $Canonical = Join-Path $script:ToolsRoot 'legacy-input\templeos-v1.10\TempleOSTS.iso'
    if (Test-Path -LiteralPath $Canonical -PathType Leaf) {
        $Canonical = (Resolve-Path -LiteralPath $Canonical).Path
        Write-Host "CHECK CANONICAL ISO: $Canonical"
        if (-not (Test-RareIso $Canonical)) {
            throw @"
Canonical TempleOSTS acquisition source failed identity verification:
  $Canonical

Expected bytes:  $ExpectedIsoBytes
Expected SHA256: $ExpectedIsoHash

The runner will not substitute a VM baseline copy for a corrupted canonical source.
"@
        }

        $script:RareIsoSource = 'CANONICAL-LEGACY-INPUT'
        Write-Host 'SELECT ISO: CANONICAL LEGACY INPUT'
        return $Canonical
    }

    $SearchRoots = @(Get-IsoSearchRoots)
    $Named = [System.Collections.Generic.List[string]]::new()
    foreach ($Root in $SearchRoots) {
        Write-Host "SEARCH ISO: $Root"
        foreach ($File in @(
            Get-ChildItem `
                -LiteralPath $Root `
                -Filter 'TempleOSTS.iso' `
                -File `
                -Recurse `
                -ErrorAction SilentlyContinue
        )) {
            if (-not $Named.Contains($File.FullName)) {
                $Named.Add($File.FullName)
            }
        }
    }

    $Exact = @(
        foreach ($Candidate in $Named) {
            Write-Host "CHECK ISO:  $Candidate"
            if (Test-RareIso $Candidate) {
                $Candidate
            }
        }
    )

    if ($Exact.Count -eq 0) {
        throw @"
Exact TempleOSTS.iso was not found.
Required bytes:  $ExpectedIsoBytes
Required SHA256: $ExpectedIsoHash

Run with the exact source path:
  .\tools\RUN-RARE-FOUNDATION.ps1 -IsoPath D:\actual\path\TempleOSTS.iso
"@
    }
    if ($Exact.Count -gt 1) {
        throw "multiple exact non-canonical ISO files found; pass -IsoPath explicitly:`n$($Exact -join "`n")"
    }

    $script:RareIsoSource = 'BOUNDED-DISCOVERY'
    return $Exact[0]
}

$ToolsRoot = Resolve-HolyToolsRoot
$RareIso = Resolve-RareIsoPath

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $EvidenceRoot = Join-Path $ParentRoot 'DBYTE-HOLYC-OPT-EVIDENCE'
}
$EvidenceRoot = [System.IO.Path]::GetFullPath($EvidenceRoot)

$ExtractRoot = Join-Path $EvidenceRoot 'templeosts-1.10-internal'
$ManifestPath = Join-Path $EvidenceRoot 'templeosts-expanded-manifest.txt'
$DiscoveryPath = Join-Path $EvidenceRoot 'templeosts-compiler-discovery.txt'

$Verifier = Join-Path $PSScriptRoot 'VERIFY-HOLYC-TOOLS-RESOURCE.ps1'
$Sealer = Join-Path $PSScriptRoot 'SEAL-TEMPLEOSTS-CORPUS.ps1'
$Discoverer = Join-Path $PSScriptRoot 'DISCOVER-TEMPLEOSTS-COMPILER.ps1'
foreach ($Script in @($Verifier, $Sealer, $Discoverer)) {
    if (-not (Test-Path -LiteralPath $Script -PathType Leaf)) {
        throw "required script missing: $Script"
    }
}

Write-Host "OPT ROOT:      $RepoRoot"
Write-Host "TOOLS ROOT:    $ToolsRoot"
Write-Host "RARE ISO:      $RareIso"
Write-Host "ISO SOURCE:    $RareIsoSource"
Write-Host "EVIDENCE ROOT: $EvidenceRoot"

& $Verifier -Path $ToolsRoot

$HaveExtract = Test-Path -LiteralPath $ExtractRoot -PathType Container
$HaveManifest = Test-Path -LiteralPath $ManifestPath -PathType Leaf

if (-not $HaveExtract -and $HaveManifest) {
    throw @"
Invalid evidence state.
Extract exists:  False
Manifest exists: True
No file was removed. Preserve and adjudicate:
  $EvidenceRoot
"@
}

if ($HaveExtract -and -not $HaveManifest) {
    if (-not $ResumeIncompleteExtraction) {
        throw @"
Incomplete evidence state.
Extract exists:  True
Manifest exists: False
No file was removed.

Revalidate the observed extraction by running:
  .\tools\RUN-RARE-FOUNDATION.ps1 -ResumeIncompleteExtraction
"@
    }

    Write-Host 'CORPUS:        RESUME INCOMPLETE EXTRACTION'
    & $Sealer `
        -HolyTools $ToolsRoot `
        -IsoPath $RareIso `
        -ExtractRoot $ExtractRoot `
        -ManifestPath $ManifestPath `
        -ResumeExistingExtraction
}
elseif (-not $HaveExtract) {
    New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null
    & $Sealer `
        -HolyTools $ToolsRoot `
        -IsoPath $RareIso `
        -ExtractRoot $ExtractRoot `
        -ManifestPath $ManifestPath
}
else {
    Write-Host 'CORPUS:        REUSE SEALED OUTPUT'
}

if (Test-Path -LiteralPath $DiscoveryPath) {
    $ExistingHash = (Get-FileHash -LiteralPath $DiscoveryPath -Algorithm SHA256).Hash
    throw @"
Compiler discovery report already exists and was not overwritten:
  $DiscoveryPath
  SHA256 $ExistingHash

Preserve it as evidence. Use another -EvidenceRoot for a new run.
"@
}

& $Discoverer `
    -ExtractRoot $ExtractRoot `
    -ManifestPath $ManifestPath `
    -OutPath $DiscoveryPath

$ManifestHash = (Get-FileHash -LiteralPath $ManifestPath -Algorithm SHA256).Hash
$DiscoveryHash = (Get-FileHash -LiteralPath $DiscoveryPath -Algorithm SHA256).Hash

Write-Host ''
Write-Host 'CORPUS FOUNDATION: PASS'
Write-Host "ISO SOURCE:       $RareIsoSource"
Write-Host "MANIFEST:         $ManifestPath"
Write-Host "MANIFEST SHA256   $ManifestHash"
Write-Host "DISCOVERY:        $DiscoveryPath"
Write-Host "DISCOVERY SHA256  $DiscoveryHash"
Write-Host 'COMPILER:         UNRESOLVED'
Write-Host 'SEAM:             UNRESOLVED'
Write-Host 'PATCH STATUS:     NOT AUTHORIZED'
