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

$ExpectedPortableRoot = 'D:\Portable-VirtualBox7'
$ExpectedWrapperInspectionReport =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-portable-vbox-wrapper-binary-loader-inspection.txt'
$ExpectedWrapperInspectionHash =
    '57DB3BA61960C74AF529C0AB1EBA86DD44CE06C7AFDD7D58E0A961B7794AB721'
$ExpectedWrapperHash =
    '2F0F9F4E4096F7BA67284F8168D03E1CE0A992047782F49233374CA33B5F6E8E'
$ExpectedOut =
    'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-portable-vbox-wrapper-pe-surface-inspection.txt'

function Get-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath(
        [Environment]::ExpandEnvironmentVariables($Path)
    ).TrimEnd([char]92, [char]47)
}

function Assert-PathEquals {
    param(
        [Parameter(Mandatory = $true)][string]$Observed,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not [string]::Equals(
        (Get-FullPath -Path $Observed),
        (Get-FullPath -Path $Expected),
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "${Label} mismatch: observed=$Observed expected=$Expected"
    }
}

function Assert-Range {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][long]$Offset,
        [Parameter(Mandatory = $true)][long]$Length,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (
        $Offset -lt 0 -or
        $Length -lt 0 -or
        $Offset -gt $Bytes.LongLength -or
        $Length -gt ($Bytes.LongLength - $Offset)
    ) {
        throw "${Label} range out of bounds: offset=$Offset length=$Length bytes=$($Bytes.LongLength)"
    }
}

function Read-U16 {
    param([byte[]]$Bytes, [long]$Offset, [string]$Label)
    Assert-Range -Bytes $Bytes -Offset $Offset -Length 2 -Label $Label
    return [BitConverter]::ToUInt16($Bytes, [int]$Offset)
}

function Read-U32 {
    param([byte[]]$Bytes, [long]$Offset, [string]$Label)
    Assert-Range -Bytes $Bytes -Offset $Offset -Length 4 -Label $Label
    return [BitConverter]::ToUInt32($Bytes, [int]$Offset)
}

function Read-U64 {
    param([byte[]]$Bytes, [long]$Offset, [string]$Label)
    Assert-Range -Bytes $Bytes -Offset $Offset -Length 8 -Label $Label
    return [BitConverter]::ToUInt64($Bytes, [int]$Offset)
}

function Read-AsciiZ {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][long]$Offset,
        [int]$Maximum = 4096,
        [Parameter(Mandatory = $true)][string]$Label
    )

    Assert-Range -Bytes $Bytes -Offset $Offset -Length 1 -Label $Label
    $End = $Offset
    $Limit = [Math]::Min($Bytes.LongLength, $Offset + $Maximum)
    while ($End -lt $Limit -and $Bytes[[int]$End] -ne 0) {
        $End++
    }
    if ($End -ge $Limit) {
        throw "${Label} missing NUL terminator within $Maximum bytes"
    }
    return [System.Text.Encoding]::ASCII.GetString(
        $Bytes,
        [int]$Offset,
        [int]($End - $Offset)
    )
}

function Get-SectionName {
    param([byte[]]$Bytes, [long]$Offset)

    Assert-Range -Bytes $Bytes -Offset $Offset -Length 8 -Label 'section name'
    $Raw = [System.Text.Encoding]::ASCII.GetString($Bytes, [int]$Offset, 8)
    $Null = $Raw.IndexOf([char]0)
    if ($Null -ge 0) {
        return $Raw.Substring(0, $Null)
    }
    return $Raw
}

function Convert-RvaToOffset {
    param(
        [Parameter(Mandatory = $true)][uint32]$Rva,
        [Parameter(Mandatory = $true)][object[]]$Sections,
        [Parameter(Mandatory = $true)][uint32]$SizeOfHeaders,
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ($Rva -lt $SizeOfHeaders) {
        Assert-Range -Bytes $Bytes -Offset $Rva -Length 1 -Label $Label
        return [long]$Rva
    }

    foreach ($Section in $Sections) {
        $Span = [Math]::Max(
            [uint64]$Section.VirtualSize,
            [uint64]$Section.SizeOfRawData
        )
        $Start = [uint64]$Section.VirtualAddress
        $End = $Start + $Span
        if ([uint64]$Rva -ge $Start -and [uint64]$Rva -lt $End) {
            $Delta = [uint64]$Rva - $Start
            if ($Delta -ge [uint64]$Section.SizeOfRawData) {
                throw "${Label} RVA maps beyond raw section data: rva=0x$('{0:X8}' -f $Rva) section=$($Section.Name)"
            }
            $Offset = [uint64]$Section.PointerToRawData + $Delta
            Assert-Range -Bytes $Bytes -Offset ([long]$Offset) -Length 1 -Label $Label
            return [long]$Offset
        }
    }

    throw "${Label} RVA not mapped by sections: 0x$('{0:X8}' -f $Rva)"
}

function Get-ShannonEntropy {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][long]$Offset,
        [Parameter(Mandatory = $true)][long]$Length
    )

    if ($Length -eq 0) {
        return 0.0
    }
    Assert-Range -Bytes $Bytes -Offset $Offset -Length $Length -Label 'entropy source'
    $Counts = New-Object 'long[]' 256
    for ($Index = $Offset; $Index -lt ($Offset + $Length); $Index++) {
        $Counts[$Bytes[[int]$Index]]++
    }
    $Entropy = 0.0
    foreach ($Count in $Counts) {
        if ($Count -eq 0) {
            continue
        }
        $P = [double]$Count / [double]$Length
        $Entropy -= $P * ([Math]::Log($P, 2.0))
    }
    return $Entropy
}

function Find-BytePattern {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][byte[]]$Pattern
    )

    $Rows = [System.Collections.Generic.List[long]]::new()
    if ($Pattern.Length -eq 0 -or $Pattern.Length -gt $Bytes.Length) {
        return $Rows.ToArray()
    }
    for ($Index = 0; $Index -le ($Bytes.Length - $Pattern.Length); $Index++) {
        $Match = $true
        for ($Inner = 0; $Inner -lt $Pattern.Length; $Inner++) {
            if ($Bytes[$Index + $Inner] -ne $Pattern[$Inner]) {
                $Match = $false
                break
            }
        }
        if ($Match) {
            $Rows.Add([long]$Index)
        }
    }
    return $Rows.ToArray()
}

$PortableRoot = (
    Resolve-Path -LiteralPath $PortableVirtualBoxRoot -ErrorAction Stop
).Path
$WrapperInspectionReport = (
    Resolve-Path -LiteralPath $WrapperBinaryInspectionReportPath -ErrorAction Stop
).Path
$Output = Get-FullPath -Path $OutPath

Assert-PathEquals -Observed $PortableRoot -Expected $ExpectedPortableRoot -Label 'portable VirtualBox root'
Assert-PathEquals -Observed $WrapperInspectionReport -Expected $ExpectedWrapperInspectionReport -Label 'wrapper inspection report'
Assert-PathEquals -Observed $Output -Expected $ExpectedOut -Label 'PE inspection report'

if (Test-Path -LiteralPath $Output) {
    throw "PE inspection report already exists: $Output"
}
$OutputParent = Split-Path -Parent $Output
if (-not (Test-Path -LiteralPath $OutputParent -PathType Container)) {
    throw "PE inspection report parent missing: $OutputParent"
}

$WrapperInspectionHash = (
    Get-FileHash -LiteralPath $WrapperInspectionReport -Algorithm SHA256
).Hash
if ($WrapperInspectionHash -cne $ExpectedWrapperInspectionHash) {
    throw (
        'wrapper inspection report SHA256 mismatch: ' +
        "observed=$WrapperInspectionHash expected=$ExpectedWrapperInspectionHash"
    )
}

$WrapperPath = Join-Path $PortableRoot 'Portable-VirtualBox7.exe'
if (-not (Test-Path -LiteralPath $WrapperPath -PathType Leaf)) {
    throw "wrapper missing: $WrapperPath"
}
$WrapperItem = Get-Item -LiteralPath $WrapperPath -Force -ErrorAction Stop
$WrapperHash = (Get-FileHash -LiteralPath $WrapperPath -Algorithm SHA256).Hash
if ($WrapperHash -cne $ExpectedWrapperHash) {
    throw "wrapper SHA256 mismatch: observed=$WrapperHash expected=$ExpectedWrapperHash"
}

$Bytes = [System.IO.File]::ReadAllBytes($WrapperPath)
if ($Bytes.Length -lt 0x100) {
    throw 'wrapper too small to be a valid PE image'
}
if ($Bytes[0] -ne 0x4d -or $Bytes[1] -ne 0x5a) {
    throw 'DOS MZ signature missing'
}

$PeOffset = [long](Read-U32 -Bytes $Bytes -Offset 0x3c -Label 'e_lfanew')
Assert-Range -Bytes $Bytes -Offset $PeOffset -Length 24 -Label 'PE header'
if (
    $Bytes[[int]$PeOffset] -ne 0x50 -or
    $Bytes[[int]($PeOffset + 1)] -ne 0x45 -or
    $Bytes[[int]($PeOffset + 2)] -ne 0 -or
    $Bytes[[int]($PeOffset + 3)] -ne 0
) {
    throw 'PE signature missing at e_lfanew'
}

$Coff = $PeOffset + 4
$Machine = Read-U16 -Bytes $Bytes -Offset $Coff -Label 'COFF Machine'
$NumberOfSections = Read-U16 -Bytes $Bytes -Offset ($Coff + 2) -Label 'COFF NumberOfSections'
$TimeDateStamp = Read-U32 -Bytes $Bytes -Offset ($Coff + 4) -Label 'COFF TimeDateStamp'
$OptionalSize = Read-U16 -Bytes $Bytes -Offset ($Coff + 16) -Label 'COFF SizeOfOptionalHeader'
$Characteristics = Read-U16 -Bytes $Bytes -Offset ($Coff + 18) -Label 'COFF Characteristics'

if ($NumberOfSections -le 0 -or $NumberOfSections -gt 96) {
    throw "section count outside bounded contract: $NumberOfSections"
}

$Optional = $Coff + 20
Assert-Range -Bytes $Bytes -Offset $Optional -Length $OptionalSize -Label 'optional header'
$Magic = Read-U16 -Bytes $Bytes -Offset $Optional -Label 'optional header magic'
if ($Magic -eq 0x10b) {
    $PeKind = 'PE32'
    $DataDirectoryBase = $Optional + 96
    $NumberOfRvaAndSizesOffset = $Optional + 92
    $ThunkSize = 4
    $OrdinalMask = [uint64]0x80000000
}
elif ($Magic -eq 0x20b) {
    $PeKind = 'PE32+'
    $DataDirectoryBase = $Optional + 112
    $NumberOfRvaAndSizesOffset = $Optional + 108
    $ThunkSize = 8
    $OrdinalMask = [uint64]0x8000000000000000
}
else {
    throw "unsupported optional-header magic: 0x$('{0:X4}' -f $Magic)"
}

$AddressOfEntryPoint = Read-U32 -Bytes $Bytes -Offset ($Optional + 16) -Label 'AddressOfEntryPoint'
$ImageBase = if ($PeKind -ceq 'PE32') {
    [uint64](Read-U32 -Bytes $Bytes -Offset ($Optional + 28) -Label 'ImageBase')
}
else {
    Read-U64 -Bytes $Bytes -Offset ($Optional + 24) -Label 'ImageBase'
}
$SectionAlignment = Read-U32 -Bytes $Bytes -Offset ($Optional + 32) -Label 'SectionAlignment'
$FileAlignment = Read-U32 -Bytes $Bytes -Offset ($Optional + 36) -Label 'FileAlignment'
$SizeOfImage = Read-U32 -Bytes $Bytes -Offset ($Optional + 56) -Label 'SizeOfImage'
$SizeOfHeaders = Read-U32 -Bytes $Bytes -Offset ($Optional + 60) -Label 'SizeOfHeaders'
$Subsystem = Read-U16 -Bytes $Bytes -Offset ($Optional + 68) -Label 'Subsystem'
$DllCharacteristics = Read-U16 -Bytes $Bytes -Offset ($Optional + 70) -Label 'DllCharacteristics'
$NumberOfRvaAndSizes = Read-U32 -Bytes $Bytes -Offset $NumberOfRvaAndSizesOffset -Label 'NumberOfRvaAndSizes'

$SectionTable = $Optional + $OptionalSize
Assert-Range -Bytes $Bytes -Offset $SectionTable -Length ([long]$NumberOfSections * 40) -Label 'section table'
$Sections = @(
    for ($Index = 0; $Index -lt $NumberOfSections; $Index++) {
        $Base = $SectionTable + ($Index * 40)
        $Name = Get-SectionName -Bytes $Bytes -Offset $Base
        $VirtualSize = Read-U32 -Bytes $Bytes -Offset ($Base + 8) -Label "section[$Index] VirtualSize"
        $VirtualAddress = Read-U32 -Bytes $Bytes -Offset ($Base + 12) -Label "section[$Index] VirtualAddress"
        $SizeOfRawData = Read-U32 -Bytes $Bytes -Offset ($Base + 16) -Label "section[$Index] SizeOfRawData"
        $PointerToRawData = Read-U32 -Bytes $Bytes -Offset ($Base + 20) -Label "section[$Index] PointerToRawData"
        $SectionCharacteristics = Read-U32 -Bytes $Bytes -Offset ($Base + 36) -Label "section[$Index] Characteristics"
        if ($SizeOfRawData -gt 0) {
            Assert-Range -Bytes $Bytes -Offset $PointerToRawData -Length $SizeOfRawData -Label "section[$Index] raw data"
        }
        $Entropy = if ($SizeOfRawData -gt 0) {
            Get-ShannonEntropy -Bytes $Bytes -Offset $PointerToRawData -Length $SizeOfRawData
        }
        else {
            0.0
        }
        [pscustomobject]@{
            Index = $Index
            Name = $Name
            VirtualSize = [uint32]$VirtualSize
            VirtualAddress = [uint32]$VirtualAddress
            SizeOfRawData = [uint32]$SizeOfRawData
            PointerToRawData = [uint32]$PointerToRawData
            Characteristics = [uint32]$SectionCharacteristics
            Entropy = [double]$Entropy
        }
    }
)

$DirectoryCount = [Math]::Min([uint32]16, $NumberOfRvaAndSizes)
$Directories = @()
for ($Index = 0; $Index -lt $DirectoryCount; $Index++) {
    $Base = $DataDirectoryBase + ($Index * 8)
    Assert-Range -Bytes $Bytes -Offset $Base -Length 8 -Label "data directory[$Index]"
    $Directories += [pscustomobject]@{
        Index = $Index
        VirtualAddress = Read-U32 -Bytes $Bytes -Offset $Base -Label "data directory[$Index] VA"
        Size = Read-U32 -Bytes $Bytes -Offset ($Base + 4) -Label "data directory[$Index] size"
    }
}

function Get-Directory {
    param([int]$Index)
    $Rows = @($Directories | Where-Object { $_.Index -eq $Index })
    if ($Rows.Count -eq 0) {
        return [pscustomobject]@{ Index = $Index; VirtualAddress = [uint32]0; Size = [uint32]0 }
    }
    return $Rows[0]
}

$ImportDirectory = Get-Directory -Index 1
$ResourceDirectory = Get-Directory -Index 2
$SecurityDirectory = Get-Directory -Index 4

$ImportRows = [System.Collections.Generic.List[object]]::new()
$ImportFunctionRows = [System.Collections.Generic.List[object]]::new()
if ($ImportDirectory.VirtualAddress -ne 0 -and $ImportDirectory.Size -ne 0) {
    $ImportOffset = Convert-RvaToOffset -Rva $ImportDirectory.VirtualAddress -Sections $Sections -SizeOfHeaders $SizeOfHeaders -Bytes $Bytes -Label 'import directory'
    for ($DescriptorIndex = 0; $DescriptorIndex -lt 1024; $DescriptorIndex++) {
        $Descriptor = $ImportOffset + ($DescriptorIndex * 20)
        Assert-Range -Bytes $Bytes -Offset $Descriptor -Length 20 -Label "import descriptor[$DescriptorIndex]"
        $OriginalFirstThunk = Read-U32 -Bytes $Bytes -Offset $Descriptor -Label 'OriginalFirstThunk'
        $Time = Read-U32 -Bytes $Bytes -Offset ($Descriptor + 4) -Label 'Import TimeDateStamp'
        $ForwarderChain = Read-U32 -Bytes $Bytes -Offset ($Descriptor + 8) -Label 'ForwarderChain'
        $NameRva = Read-U32 -Bytes $Bytes -Offset ($Descriptor + 12) -Label 'Import Name RVA'
        $FirstThunk = Read-U32 -Bytes $Bytes -Offset ($Descriptor + 16) -Label 'FirstThunk'
        if (
            $OriginalFirstThunk -eq 0 -and
            $Time -eq 0 -and
            $ForwarderChain -eq 0 -and
            $NameRva -eq 0 -and
            $FirstThunk -eq 0
        ) {
            break
        }
        if ($NameRva -eq 0) {
            throw "import descriptor[$DescriptorIndex] has zero Name RVA"
        }
        $NameOffset = Convert-RvaToOffset -Rva $NameRva -Sections $Sections -SizeOfHeaders $SizeOfHeaders -Bytes $Bytes -Label "import DLL[$DescriptorIndex] name"
        $DllName = Read-AsciiZ -Bytes $Bytes -Offset $NameOffset -Label "import DLL[$DescriptorIndex] name"
        $ThunkRva = if ($OriginalFirstThunk -ne 0) { $OriginalFirstThunk } else { $FirstThunk }
        $FunctionCount = 0
        if ($ThunkRva -ne 0) {
            $ThunkOffset = Convert-RvaToOffset -Rva $ThunkRva -Sections $Sections -SizeOfHeaders $SizeOfHeaders -Bytes $Bytes -Label "import DLL[$DescriptorIndex] thunk"
            for ($ThunkIndex = 0; $ThunkIndex -lt 65536; $ThunkIndex++) {
                $EntryOffset = $ThunkOffset + ($ThunkIndex * $ThunkSize)
                $ThunkValue = if ($ThunkSize -eq 4) {
                    [uint64](Read-U32 -Bytes $Bytes -Offset $EntryOffset -Label 'import thunk')
                }
                else {
                    Read-U64 -Bytes $Bytes -Offset $EntryOffset -Label 'import thunk'
                }
                if ($ThunkValue -eq 0) {
                    break
                }
                $FunctionCount++
                if (($ThunkValue -band $OrdinalMask) -ne 0) {
                    $Ordinal = [uint16]($ThunkValue -band 0xffff)
                    $ImportFunctionRows.Add([pscustomobject]@{
                        Dll = $DllName
                        Kind = 'ordinal'
                        Name = "#$Ordinal"
                    })
                    continue
                }
                if ($ThunkValue -gt [uint64][uint32]::MaxValue) {
                    throw "import name RVA outside 32-bit range: 0x$('{0:X}' -f $ThunkValue)"
                }
                $HintNameRva = [uint32]$ThunkValue
                $HintNameOffset = Convert-RvaToOffset -Rva $HintNameRva -Sections $Sections -SizeOfHeaders $SizeOfHeaders -Bytes $Bytes -Label 'import hint/name'
                [void](Read-U16 -Bytes $Bytes -Offset $HintNameOffset -Label 'import hint')
                $FunctionName = Read-AsciiZ -Bytes $Bytes -Offset ($HintNameOffset + 2) -Label 'import function name'
                $ImportFunctionRows.Add([pscustomobject]@{
                    Dll = $DllName
                    Kind = 'name'
                    Name = $FunctionName
                })
            }
        }
        $ImportRows.Add([pscustomobject]@{
            Dll = $DllName
            FunctionCount = $FunctionCount
        })
    }
}

$InterestingImportNames = @(
    'OpenSCManagerA','OpenSCManagerW',
    'CreateServiceA','CreateServiceW',
    'OpenServiceA','OpenServiceW',
    'StartServiceA','StartServiceW',
    'ControlService','DeleteService','CloseServiceHandle',
    'CreateProcessA','CreateProcessW','WinExec',
    'ShellExecuteA','ShellExecuteW','ShellExecuteExA','ShellExecuteExW',
    'CreateProcessAsUserA','CreateProcessAsUserW',
    'RegCreateKeyExA','RegCreateKeyExW','RegOpenKeyExA','RegOpenKeyExW',
    'RegSetValueExA','RegSetValueExW','RegDeleteKeyA','RegDeleteKeyW',
    'LoadLibraryA','LoadLibraryW','GetProcAddress'
)
$InterestingImports = @(
    $ImportFunctionRows |
        Where-Object { $InterestingImportNames -contains $_.Name } |
        Sort-Object Dll, Name
)

$ResourceRootRows = [System.Collections.Generic.List[object]]::new()
if ($ResourceDirectory.VirtualAddress -ne 0 -and $ResourceDirectory.Size -ne 0) {
    $ResourceBase = Convert-RvaToOffset -Rva $ResourceDirectory.VirtualAddress -Sections $Sections -SizeOfHeaders $SizeOfHeaders -Bytes $Bytes -Label 'resource directory'
    Assert-Range -Bytes $Bytes -Offset $ResourceBase -Length 16 -Label 'resource root'
    $Named = Read-U16 -Bytes $Bytes -Offset ($ResourceBase + 12) -Label 'resource named entries'
    $Ids = Read-U16 -Bytes $Bytes -Offset ($ResourceBase + 14) -Label 'resource ID entries'
    $Total = [int]$Named + [int]$Ids
    if ($Total -gt 4096) {
        throw "resource root entry count outside bounded contract: $Total"
    }
    Assert-Range -Bytes $Bytes -Offset ($ResourceBase + 16) -Length ([long]$Total * 8) -Label 'resource root entries'
    for ($Index = 0; $Index -lt $Total; $Index++) {
        $Entry = $ResourceBase + 16 + ($Index * 8)
        $NameField = Read-U32 -Bytes $Bytes -Offset $Entry -Label 'resource root name'
        $DataField = Read-U32 -Bytes $Bytes -Offset ($Entry + 4) -Label 'resource root data'
        $IsNamed = (($NameField -band 0x80000000) -ne 0)
        $Display = ''
        if ($IsNamed) {
            $NameRelative = [uint32]($NameField -band 0x7fffffff)
            $NameOffset = $ResourceBase + $NameRelative
            $Chars = Read-U16 -Bytes $Bytes -Offset $NameOffset -Label 'resource name length'
            Assert-Range -Bytes $Bytes -Offset ($NameOffset + 2) -Length ([long]$Chars * 2) -Label 'resource name text'
            $Display = [System.Text.Encoding]::Unicode.GetString(
                $Bytes,
                [int]($NameOffset + 2),
                [int]($Chars * 2)
            )
        }
        else {
            $Id = [uint16]($NameField -band 0xffff)
            $Known = switch ($Id) {
                1 { 'RT_CURSOR' }
                2 { 'RT_BITMAP' }
                3 { 'RT_ICON' }
                4 { 'RT_MENU' }
                5 { 'RT_DIALOG' }
                6 { 'RT_STRING' }
                9 { 'RT_ACCELERATOR' }
                10 { 'RT_RCDATA' }
                14 { 'RT_GROUP_ICON' }
                16 { 'RT_VERSION' }
                24 { 'RT_MANIFEST' }
                default { "ID_$Id" }
            }
            $Display = $Known
        }
        $ResourceRootRows.Add([pscustomobject]@{
            Name = $Display
            Named = $IsNamed
            IsDirectory = (($DataField -band 0x80000000) -ne 0)
            RawData = [uint32]($DataField -band 0x7fffffff)
        })
    }
}

$RawEnd = [long]$SizeOfHeaders
foreach ($Section in $Sections) {
    $Candidate = [long]$Section.PointerToRawData + [long]$Section.SizeOfRawData
    if ($Candidate -gt $RawEnd) {
        $RawEnd = $Candidate
    }
}
if ($SecurityDirectory.VirtualAddress -ne 0 -and $SecurityDirectory.Size -ne 0) {
    $SecurityEnd = [long]$SecurityDirectory.VirtualAddress + [long]$SecurityDirectory.Size
    if ($SecurityEnd -gt $RawEnd) {
        $RawEnd = $SecurityEnd
    }
}
$OverlayOffset = [Math]::Min($RawEnd, $Bytes.LongLength)
$OverlayBytes = $Bytes.LongLength - $OverlayOffset
$OverlayHash = '<none>'
if ($OverlayBytes -gt 0) {
    $Sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $OverlayHash = [BitConverter]::ToString(
            $Sha.ComputeHash($Bytes, [int]$OverlayOffset, [int]$OverlayBytes)
        ).Replace('-', '')
    }
    finally {
        $Sha.Dispose()
    }
}

$MarkerTokens = @(
    'UPX!','UPX0','UPX1','UPX2',
    'MPRESS1','MPRESS2','MPRESS',
    'AutoIt v3','AutoIt3','AutoIt',
    'AutoHotkey','Nullsoft','NSIS','Inno Setup',
    'ASPack','PECompact','Themida','VMProtect','7-Zip SFX'
)
$MarkerRows = [System.Collections.Generic.List[object]]::new()
foreach ($Token in $MarkerTokens) {
    $Ascii = [System.Text.Encoding]::ASCII.GetBytes($Token)
    foreach ($Offset in @(Find-BytePattern -Bytes $Bytes -Pattern $Ascii)) {
        $MarkerRows.Add([pscustomobject]@{
            Encoding = 'ASCII'
            Offset = [long]$Offset
            Token = $Token
        })
    }
    $Utf16 = [System.Text.Encoding]::Unicode.GetBytes($Token)
    foreach ($Offset in @(Find-BytePattern -Bytes $Bytes -Pattern $Utf16)) {
        $MarkerRows.Add([pscustomobject]@{
            Encoding = 'UTF16LE'
            Offset = [long]$Offset
            Token = $Token
        })
    }
}

$Lines = [System.Collections.Generic.List[string]]::new()
$Lines.Add('DBYTE-HOLYC-OPT')
$Lines.Add('PORTABLE VIRTUALBOX7 WRAPPER PE SURFACE READ-ONLY INSPECTION')
$Lines.Add('')
$Lines.Add("portable_root`t$PortableRoot")
$Lines.Add("bound_wrapper_inspection_sha256`t$WrapperInspectionHash")
$Lines.Add("wrapper_path`t$WrapperPath")
$Lines.Add("wrapper_bytes`t$($WrapperItem.Length)")
$Lines.Add("wrapper_sha256`t$WrapperHash")
$Lines.Add("pe_kind`t$PeKind")
$Lines.Add("pe_offset`t0x$('{0:X}' -f $PeOffset)")
$Lines.Add("machine`t0x$('{0:X4}' -f $Machine)")
$Lines.Add("section_count`t$NumberOfSections")
$Lines.Add("timestamp`t0x$('{0:X8}' -f $TimeDateStamp)")
$Lines.Add("characteristics`t0x$('{0:X4}' -f $Characteristics)")
$Lines.Add("dll_characteristics`t0x$('{0:X4}' -f $DllCharacteristics)")
$Lines.Add("subsystem`t$Subsystem")
$Lines.Add("entry_point_rva`t0x$('{0:X8}' -f $AddressOfEntryPoint)")
$Lines.Add("image_base`t0x$('{0:X}' -f $ImageBase)")
$Lines.Add("section_alignment`t$SectionAlignment")
$Lines.Add("file_alignment`t$FileAlignment")
$Lines.Add("size_of_image`t$SizeOfImage")
$Lines.Add("size_of_headers`t$SizeOfHeaders")
$Lines.Add('')

$Lines.Add("section_row_count`t$($Sections.Count)")
foreach ($Section in $Sections) {
    $Lines.Add(
        'section_row' + "`t" +
        $Section.Index + "`t" +
        $Section.Name + "`t" +
        ('0x{0:X8}' -f $Section.VirtualAddress) + "`t" +
        $Section.VirtualSize + "`t" +
        ('0x{0:X8}' -f $Section.PointerToRawData) + "`t" +
        $Section.SizeOfRawData + "`t" +
        ('{0:F4}' -f $Section.Entropy) + "`t" +
        ('0x{0:X8}' -f $Section.Characteristics)
    )
}
$Lines.Add('')

$Lines.Add("import_directory_rva`t0x$('{0:X8}' -f $ImportDirectory.VirtualAddress)")
$Lines.Add("import_directory_size`t$($ImportDirectory.Size)")
$Lines.Add("import_dll_count`t$($ImportRows.Count)")
foreach ($Import in $ImportRows) {
    $Lines.Add("import_dll`t$($Import.Dll)`t$($Import.FunctionCount)")
}
$Lines.Add("import_function_count`t$($ImportFunctionRows.Count)")
foreach ($Import in $ImportFunctionRows) {
    $Lines.Add("import_function`t$($Import.Dll)`t$($Import.Kind)`t$($Import.Name)")
}
$Lines.Add("interesting_import_count`t$($InterestingImports.Count)")
foreach ($Import in $InterestingImports) {
    $Lines.Add("interesting_import`t$($Import.Dll)`t$($Import.Name)")
}
$Lines.Add('')

$Lines.Add("resource_directory_rva`t0x$('{0:X8}' -f $ResourceDirectory.VirtualAddress)")
$Lines.Add("resource_directory_size`t$($ResourceDirectory.Size)")
$Lines.Add("resource_root_entry_count`t$($ResourceRootRows.Count)")
foreach ($Resource in $ResourceRootRows) {
    $Lines.Add("resource_root_entry`t$($Resource.Name)`t$($Resource.Named)`t$($Resource.IsDirectory)`t0x$('{0:X8}' -f $Resource.RawData)")
}
$Lines.Add('')

$Lines.Add("security_directory_file_offset`t0x$('{0:X8}' -f $SecurityDirectory.VirtualAddress)")
$Lines.Add("security_directory_size`t$($SecurityDirectory.Size)")
$Lines.Add("overlay_offset`t0x$('{0:X}' -f $OverlayOffset)")
$Lines.Add("overlay_bytes`t$OverlayBytes")
$Lines.Add("overlay_sha256`t$OverlayHash")
$Lines.Add("marker_count`t$($MarkerRows.Count)")
foreach ($Marker in $MarkerRows) {
    $Lines.Add("marker`t$($Marker.Encoding)`t0x$('{0:X}' -f $Marker.Offset)`t$($Marker.Token)")
}
$Lines.Add('')
$Lines.Add("HOST MUTATION`tNOT-EXECUTED")
$Lines.Add("WRAPPER EXECUTION`tNOT-EXECUTED")
$Lines.Add("DRIVER INSTALL/START`tNOT-EXECUTED")
$Lines.Add("VBOXMANAGE`tNOT-EXECUTED")
$Lines.Add("VM START`tNOT-AUTHORIZED")
$Lines.Add("VERDICT`tPORTABLE WRAPPER PE SURFACE INSPECTION COMPLETE")
$Lines.Add('')
$Lines.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')

[System.IO.File]::WriteAllText(
    $Output,
    (($Lines.ToArray() -join "`n") + "`n"),
    [System.Text.UTF8Encoding]::new($false)
)

$ReportHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash
Write-Host "PORTABLE ROOT:          $PortableRoot"
Write-Host "BOUND WRAPPER REPORT:   $WrapperInspectionHash"
Write-Host "WRAPPER SHA256:         $WrapperHash"
Write-Host "PE KIND:                $PeKind"
Write-Host "SECTIONS:               $($Sections.Count)"
Write-Host "IMPORT DLLS:            $($ImportRows.Count)"
Write-Host "IMPORT FUNCTIONS:       $($ImportFunctionRows.Count)"
Write-Host "INTERESTING IMPORTS:    $($InterestingImports.Count)"
Write-Host "RESOURCE ROOT ENTRIES:  $($ResourceRootRows.Count)"
Write-Host "OVERLAY BYTES:          $OverlayBytes"
Write-Host "PACKER/MARKER HITS:     $($MarkerRows.Count)"
Write-Host "REPORT:                 $Output"
Write-Host "REPORT SHA256:          $ReportHash"
Write-Host 'HOST MUTATION:          NOT-EXECUTED'
Write-Host 'WRAPPER EXECUTION:      NOT-EXECUTED'
Write-Host 'DRIVER INSTALL/START:   NOT-EXECUTED'
Write-Host 'VBOXMANAGE:             NOT-EXECUTED'
Write-Host 'VM START:               NOT-AUTHORIZED'
Write-Host 'VERDICT:                PORTABLE WRAPPER PE SURFACE INSPECTION COMPLETE'
