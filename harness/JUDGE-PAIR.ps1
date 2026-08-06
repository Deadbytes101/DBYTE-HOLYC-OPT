[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Baseline,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Candidate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RequiredFields = @(
    'schema',
    'role',
    'case_id',
    'source_sha256',
    'compiler_sha256',
    'exit_kind',
    'return_i64',
    'exception',
    'stdout_sha256',
    'memory_sha256',
    'code_sha256',
    'code_bytes',
    'compile_ticks',
    'run_ticks',
    'transforms'
)

$SemanticFields = @(
    'exit_kind',
    'return_i64',
    'exception',
    'stdout_sha256',
    'memory_sha256'
)

function Read-Observation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateSet('baseline', 'candidate')]
        [string]$ExpectedRole
    )

    $Resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $Object = Get-Content -LiteralPath $Resolved -Raw -Encoding UTF8 |
        ConvertFrom-Json -ErrorAction Stop

    $Names = @($Object.PSObject.Properties.Name)
    foreach ($Field in $RequiredFields) {
        if ($Names -notcontains $Field) {
            throw "missing field: role=$ExpectedRole field=$Field file=$Resolved"
        }
    }

    if ($Object.schema -ne 'dbyte-holyc-observation-1') {
        throw "schema mismatch: file=$Resolved actual=$($Object.schema)"
    }
    if ($Object.role -ne $ExpectedRole) {
        throw "role mismatch: expected=$ExpectedRole actual=$($Object.role) file=$Resolved"
    }
    if ($Object.exit_kind -notin @('return', 'exception', 'timeout')) {
        throw "invalid exit_kind: role=$ExpectedRole value=$($Object.exit_kind)"
    }

    return $Object
}

function Canonical-Value {
    param([AllowNull()]$Value)
    return ConvertTo-Json -InputObject $Value -Compress -Depth 16
}

$Base = Read-Observation -Path $Baseline -ExpectedRole 'baseline'
$Opt = Read-Observation -Path $Candidate -ExpectedRole 'candidate'

$Mismatches = [System.Collections.Generic.List[object]]::new()

foreach ($Field in @('case_id', 'source_sha256')) {
    $Before = Canonical-Value $Base.$Field
    $After = Canonical-Value $Opt.$Field
    if ($Before -ne $After) {
        $Mismatches.Add([ordered]@{
            class = 'identity'
            field = $Field
            baseline = $Base.$Field
            candidate = $Opt.$Field
        })
    }
}

foreach ($Field in $SemanticFields) {
    $Before = Canonical-Value $Base.$Field
    $After = Canonical-Value $Opt.$Field
    if ($Before -ne $After) {
        $Mismatches.Add([ordered]@{
            class = 'semantic'
            field = $Field
            baseline = $Base.$Field
            candidate = $Opt.$Field
        })
    }
}

$Verdict = if ($Mismatches.Count -eq 0) { 'PASS' } else { 'FAIL' }

$Result = [ordered]@{
    schema = 'dbyte-holyc-judge-1'
    verdict = $Verdict
    case_id = $Base.case_id
    source_sha256 = $Base.source_sha256
    baseline_compiler_sha256 = $Base.compiler_sha256
    candidate_compiler_sha256 = $Opt.compiler_sha256
    mismatches = @($Mismatches)
    code_bytes = [ordered]@{
        baseline = [Int64]$Base.code_bytes
        candidate = [Int64]$Opt.code_bytes
        delta = [Int64]$Opt.code_bytes - [Int64]$Base.code_bytes
    }
    compile_ticks = [ordered]@{
        baseline = [Int64]$Base.compile_ticks
        candidate = [Int64]$Opt.compile_ticks
        delta = [Int64]$Opt.compile_ticks - [Int64]$Base.compile_ticks
    }
    run_ticks = [ordered]@{
        baseline = [Int64]$Base.run_ticks
        candidate = [Int64]$Opt.run_ticks
        delta = [Int64]$Opt.run_ticks - [Int64]$Base.run_ticks
    }
    transforms = @($Opt.transforms)
}

$Result | ConvertTo-Json -Depth 16

if ($Verdict -ne 'PASS') {
    exit 1
}
