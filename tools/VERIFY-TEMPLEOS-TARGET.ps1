[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedRepository = 'cia-foundation/TempleOS'
$ExpectedCommit = 'c26482bb6ad3f80106d28504ec5db3c6a360732c'
$ExpectedBlobs = [ordered]@{
    'Compiler/CExts.HC' = '13d2781ce98e21dd9f9cea1f3c462f78101b9548'
    'Compiler/Compiler.PRJ' = '72015bdce68bbbb330e56299ca805e665e908fd9'
    'Compiler/PrsLib.HC' = '6f0f6fc0e624bd397db5d9ccc83b769198277922'
    'Compiler/OptPass6.HC' = '0771991824a8029692def23c56395ee05634f77b'
    'Compiler/OptPass789A.HC' = '0894b5d151459bc40bd091cddbd7d9ac7a2e2b8e'
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

$Root = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
$PatchPath = Join-Path $PSScriptRoot '..\patch\templeos-5.03\0001-add-optdeadbyte-gate.patch'
$SourcePath = Join-Path $PSScriptRoot '..\patch\templeos-5.03\Compiler\OptDeadByte.HC'

$PatchPath = (Resolve-Path -LiteralPath $PatchPath -ErrorAction Stop).Path
$SourcePath = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).Path

if (-not (Test-Path -LiteralPath (Join-Path $Root '.git'))) {
    throw "not a Git working tree: $Root"
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
    throw "target repository mismatch: expected=$ExpectedRepository actual=$Remote"
}

$Head = Invoke-Git -Arguments @('rev-parse', 'HEAD')
if ($Head -ne $ExpectedCommit) {
    throw "target commit mismatch: expected=$ExpectedCommit actual=$Head"
}

$TrackedChanges = Invoke-Git -Arguments @(
    'status',
    '--porcelain=v1',
    '--untracked-files=no'
)
if ($TrackedChanges) {
    throw "target has tracked changes:`n$TrackedChanges"
}

$Destination = Join-Path $Root 'Compiler\OptDeadByte.HC'
if (Test-Path -LiteralPath $Destination) {
    throw "target already contains Compiler/OptDeadByte.HC"
}

foreach ($Entry in $ExpectedBlobs.GetEnumerator()) {
    $ActualBlob = Invoke-Git -Arguments @(
        'rev-parse',
        "$ExpectedCommit`:$($Entry.Key)"
    )
    if ($ActualBlob -ne $Entry.Value) {
        throw (
            "target blob mismatch: path=$($Entry.Key) " +
            "expected=$($Entry.Value) actual=$ActualBlob"
        )
    }
}

$ExpectedSourceHash = '4EECFD90C8CFF2548D91F3DA6F6FF6E56053F4BBD66B6FBB1B7362CCD229BDFB'
$ActualSourceHash = (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash
if ($ActualSourceHash -ne $ExpectedSourceHash) {
    throw "optimizer source hash mismatch: expected=$ExpectedSourceHash actual=$ActualSourceHash"
}

$ApplyCheck = & git -C $Root apply --check --whitespace=error-all -- $PatchPath 2>&1
if ($LASTEXITCODE -ne 0) {
    $Joined = ($ApplyCheck | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    throw "integration patch does not apply cleanly:`n$Joined"
}

Write-Host "TARGET:   $ExpectedRepository"
Write-Host "COMMIT:   $Head"
Write-Host "BLOBS:    $($ExpectedBlobs.Count)/$($ExpectedBlobs.Count)"
Write-Host "PATCH:    APPLIES"
Write-Host "SOURCE:   $ActualSourceHash"
Write-Host "VERDICT:  PASS"
