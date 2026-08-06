[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedRepository = 'Deadbytes101/DBYTE-HOLYC-TOOLS'
$ExpectedCommit = '37b0457e8735ab8cc34a23f2717fcfb808e6a7a8'
$ExpectedBlobs = [ordered]@{
    'PROJECT-CLOSURE.txt' = '6b60a22b63ef188caae5cb49937c30185d559636'
    'preservation/templeos-legacy/README.md' = 'e15a165115d55344a52857b34370e504ffd0f281'
    'preservation/templeos-legacy/STATUS.txt' = '7ce7efa9f16219bd0e03c7117a95cb4dba1f3864'
    'preservation/templeos-legacy/ISOS.tsv' = '8866fc6603ea210283233681adeb982b653098c1'
    'scripts/verify-templeos-ts-110-install-corpus.ps1' = 'a1c2508642d5ab942b48ce3120b1f3dbfcb3ae96'
    'docs/LOSETHOS-CODEGEN-MILESTONE.md' = '9a77331b1a2f0df6a97c8c39bfb29624afee8edb'
    'scripts/run-losethos-deep-archaeology.ps1' = '71c3e7d22e39cef24a78f75f4f917eeb53f2e3d0'
    'crates/holylex/lib.rs' = '4ac74cc7f87020c24b3935dbb4a96bb0b7310c0c'
    'crates/holyindex/src/lib.rs' = 'e189c9ebf4ce9ad8d9d5c237b81c010252386722'
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $Output = & git -C $script:Root @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        $Joined = ($Output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "git $($Arguments -join ' ') failed:`n$Joined"
    }

    return (($Output | ForEach-Object { $_.ToString() }) -join "`n").Trim()
}

$Resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
$Root = $Resolved.Path

if (-not (Test-Path -LiteralPath (Join-Path $Root '.git'))) {
    throw "not a Git working tree: $Root"
}

$Inside = Invoke-Git -Arguments @('rev-parse', '--is-inside-work-tree')
if ($Inside -ne 'true') {
    throw "not inside a Git working tree: $Root"
}

$Remote = Invoke-Git -Arguments @('remote', 'get-url', 'origin')
$NormalizedRemote = $Remote.Replace('\', '/').TrimEnd('/')
$NormalizedRemote = $NormalizedRemote -replace '\.git$', ''

$RepositoryMatch =
    $NormalizedRemote -eq "https://github.com/$ExpectedRepository" -or
    $NormalizedRemote -eq "git@github.com:$ExpectedRepository" -or
    $NormalizedRemote.EndsWith("/$ExpectedRepository") -or
    $NormalizedRemote.EndsWith(":$ExpectedRepository")

if (-not $RepositoryMatch) {
    throw "resource repository mismatch: expected=$ExpectedRepository actual=$Remote"
}

$Head = Invoke-Git -Arguments @('rev-parse', 'HEAD')
if ($Head -ne $ExpectedCommit) {
    throw "resource commit mismatch: expected=$ExpectedCommit actual=$Head"
}

$TrackedChanges = Invoke-Git -Arguments @(
    'status',
    '--porcelain=v1',
    '--untracked-files=no'
)
if ($TrackedChanges) {
    throw "resource has tracked changes:`n$TrackedChanges"
}

foreach ($Entry in $ExpectedBlobs.GetEnumerator()) {
    $PathName = $Entry.Key
    $ExpectedBlob = $Entry.Value
    $ActualBlob = Invoke-Git -Arguments @(
        'rev-parse',
        "$ExpectedCommit`:$PathName"
    )

    if ($ActualBlob -ne $ExpectedBlob) {
        throw (
            "resource blob mismatch: path=$PathName " +
            "expected=$ExpectedBlob actual=$ActualBlob"
        )
    }
}

$IsoTable = Join-Path $Root 'preservation\templeos-legacy\ISOS.tsv'
$RareRow = Import-Csv -LiteralPath $IsoTable -Delimiter "`t" |
    Where-Object { $_.artifact_id -ceq 'templeos-1.10-ts-internal' }

if (@($RareRow).Count -ne 1) {
    throw 'rare target row missing or duplicated in ISOS.tsv'
}

if ($RareRow.filename -cne 'TempleOSTS.iso' -or
    [Int64]$RareRow.bytes -ne 30558208L -or
    $RareRow.sha256 -cne 'DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC' -or
    $RareRow.runtime_version -cne '1.10' -or
    $RareRow.role -cne 'TS-INTERNAL') {
    throw 'rare target identity in ISOS.tsv does not match the optimizer contract'
}

Write-Host "RESOURCE: DBYTE-HOLYC-TOOLS"
Write-Host "REMOTE:   $Remote"
Write-Host "COMMIT:   $Head"
Write-Host "BLOBS:    $($ExpectedBlobs.Count)/$($ExpectedBlobs.Count)"
Write-Host "RARE ISO: TempleOSTS.iso"
Write-Host "ROLE:     TS-INTERNAL"
Write-Host "TRACKED:  CLEAN"
Write-Host "VERDICT:  PASS"
