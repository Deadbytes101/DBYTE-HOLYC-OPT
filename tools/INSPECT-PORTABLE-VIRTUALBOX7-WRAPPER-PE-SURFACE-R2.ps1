[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$PortableVirtualBoxRoot,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$WrapperBinaryInspectionReportPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedPortableRoot = 'D:\Portable-VirtualBox7'
$ExpectedWrapperInspectionReport = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-portable-vbox-wrapper-binary-loader-inspection.txt'
$ExpectedWrapperInspectionHash = '57DB3BA61960C74AF529C0AB1EBA86DD44CE06C7AFDD7D58E0A961B7794AB721'
$ExpectedWrapperHash = '2F0F9F4E4096F7BA67284F8168D03E1CE0A992047782F49233374CA33B5F6E8E'
$ExpectedOut = 'D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-portable-vbox-wrapper-pe-surface-inspection.txt'

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
        throw "${Label} out of range: offset=$Offset length=$Length bytes=$($Bytes.LongLength)"
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
        [Parameter(Mandatory = $true)][string]$Label,
        [int]$Maximum = 4096
    )
    Assert-Range -Bytes $Bytes -Offset $Offset -Length 1 -Label $Label
    $End = $Offset
    $Limit = [Math]::Min($Bytes.LongLength, $Offset + $Maximum)
    while ($End -lt $Limit -and $Bytes[[int]$End] -ne 0) {
        $End++
    }
    if ($End -ge $Limit) {
        throw "${Label} has no bounded NUL terminator"
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
    $Text = [System.Text.Encoding]::ASCII.GetString($Bytes, [int]$Offset, 8)
    $Null = $Text.IndexOf([char]0)
    if ($Null -ge 0) {
        return $Text.Substring(0, $Null)
    }
    return $Text
}

function Get-Entropy {
    param([byte[]]$Bytes, [long]$Offset, [long]$Length)
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
        $Entropy -= $P * [Math]::Log($P, 2.0)
    }
    return $Entropy
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
        $Span = [Math]::Max([uint64]$Section.VirtualSize, [uint64]$Section.RawSize)
        $Start = [uint64]$Section.VirtualAddress
        $End = $Start + $Span
        if ([uint64]$Rva -ge $Start -and [uint64]$Rva -lt $End) {
            $Delta = [uint64]$Rva - $Start
            if ($Delta -ge [uint64]$Section.RawSize) {
                throw "${Label} RVA maps beyond raw bytes in section $($Section.Name)"
            }
            $Offset = [uint64]$Section.RawOffset + $Delta
            Assert-Range -Bytes $Bytes -Offset ([long]$Offset) -Length 1 -Label $Label
            return [long]$Offset
        }
    }
    throw "${Label} RVA not mapped: 0x$('{0:X8}' -f $Rva)"
}

function Find-MarkerOffsets {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][string]$Token
    )
    $Rows = [System.Collections.Generic.List[object]]::new()
    foreach ($EncodingName in @('ASCII', 'UTF16LE')) {
        $Pattern = if ($EncodingName -ceq 'ASCII') {
            [System.Text.Encoding]::ASCII.GetBytes($Token)
        }
        else {
            [System.Text.Encoding]::Unicode.GetBytes($Token)
        }
        if ($Pattern.Length -eq 0 -or $Pattern.Length -gt $Bytes.Length) {
            continue
        }
        for ($Index = 0; $Index -le ($Bytes.Length - $Pattern.Length); $Index++) {
            $Same = $true
            for ($Inner = 0; $Inner -lt $Pattern.Length; $Inner++) {
                if ($Bytes[$Index + $Inner] -ne $Pattern[$Inner]) {
                    $Same = $false
                    break
                }
            }
            if ($Same) {
                $Rows.Add([pscustomobject]@{
                    Encoding = $EncodingName
                    Offset = [long]$Index
                    Token = $Token
                })
            }
        }
    }
    return $Rows.ToArray()
}

$PortableRoot = (Resolve-Path -LiteralPath $PortableVirtualBoxRoot -ErrorAction Stop).Path
$WrapperReport = (Resolve-Path -LiteralPath $WrapperBinaryInspectionReportPath -ErrorAction Stop).Path
$Output = Get-FullPath -Path $OutPath

Assert-PathEquals -Observed $PortableRoot -Expected $ExpectedPortableRoot -Label 'portable root'
Assert-PathEquals -Observed $WrapperReport -Expected $ExpectedWrapperInspectionReport -Label 'wrapper inspection report'
Assert-PathEquals -Observed $Output -Expected $ExpectedOut -Label 'PE inspection report'

if (Test-Path -LiteralPath $Output) {
    throw "PE inspection report already exists: $Output"
}
$OutputParent = Split-Path -Parent $Output
if (-not (Test-Path -LiteralPath $OutputParent -PathType Container)) {
    throw "PE inspection report parent missing: $OutputParent"
}

$WrapperReportHash = (Get-FileHash -LiteralPath $WrapperReport -Algorithm SHA256).Hash
if ($WrapperReportHash -cne $ExpectedWrapperInspectionHash) {
    throw "wrapper inspection report SHA256 mismatch: observed=$WrapperReportHash expected=$ExpectedWrapperInspectionHash"
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

if ($Bytes.Length -lt 256 -or $Bytes[0] -ne 0x4d -or $Bytes[1] -ne 0x5a) {
    throw 'wrapper DOS MZ contract failed'
}
$PeOffset = [long](Read-U32 -Bytes $Bytes -Offset 0x3c -Label 'e_lfanew')
Assert-Range -Bytes $Bytes -Offset $PeOffset -Length 24 -Label 'PE header'
if (
    $Bytes[[int]$PeOffset] -ne 0x50 -or
    $Bytes[[int]($PeOffset + 1)] -ne 0x45 -or
    $Bytes[[int]($PeOffset + 2)] -ne 0 -or
    $Bytes[[int]($PeOffset + 3)] -ne 0
) {
    throw 'PE signature missing'
}

$Coff = $PeOffset + 4
$Machine = Read-U16 -Bytes $Bytes -Offset $Coff -Label 'Machine'
$SectionCount = Read-U16 -Bytes $Bytes -Offset ($Coff + 2) -Label 'NumberOfSections'
$TimeDateStamp = Read-U32 -Bytes $Bytes -Offset ($Coff + 4) -Label 'TimeDateStamp'
$OptionalSize = Read-U16 -Bytes $Bytes -Offset ($Coff + 16) -Label 'SizeOfOptionalHeader'
$Characteristics = Read-U16 -Bytes $Bytes -Offset ($Coff + 18) -Label 'Characteristics'
if ($SectionCount -le 0 -or $SectionCount -gt 96) {
    throw "section count outside bounded contract: $SectionCount"
}

$Optional = $Coff + 20
Assert-Range -Bytes $Bytes -Offset $Optional -Length $OptionalSize -Label 'optional header'
$Magic = Read-U16 -Bytes $Bytes -Offset $Optional -Label 'optional magic'
if ($Magic -eq 0x10b) {
    if ($OptionalSize -lt 96) {
        throw "PE32 optional header too small: $OptionalSize"
    }
    $PeKind = 'PE32'
    $DirectoryBase = $Optional + 96
    $DirectoryCountOffset = $Optional + 92
    $ThunkSize = 4
    $OrdinalMask = [uint64]0x80000000
}
elseif ($Magic -eq 0x20b) {
    if ($OptionalSize -lt 112) {
        throw "PE32+ optional header too small: $OptionalSize"
    }
    $PeKind = 'PE32+'
    $DirectoryBase = $Optional + 112
    $DirectoryCountOffset = $Optional + 108
    $ThunkSize = 8
    $OrdinalMask = [uint64]::Parse(
        '8000000000000000',
        [System.Globalization.NumberStyles]::HexNumber,
        [System.Globalization.CultureInfo]::InvariantCulture
    )
}
else {
    throw "unsupported optional magic: 0x$('{0:X4}' -f $Magic)"
}

$EntryPointRva = Read-U32 -Bytes $Bytes -Offset ($Optional + 16) -Label 'entry point'
$SizeOfImage = Read-U32 -Bytes $Bytes -Offset ($Optional + 56) -Label 'SizeOfImage'
$SizeOfHeaders = Read-U32 -Bytes $Bytes -Offset ($Optional + 60) -Label 'SizeOfHeaders'
$Subsystem = Read-U16 -Bytes $Bytes -Offset ($Optional + 68) -Label 'Subsystem'
$DllCharacteristics = Read-U16 -Bytes $Bytes -Offset ($Optional + 70) -Label 'DllCharacteristics'
$DirectoryCount = Read-U32 -Bytes $Bytes -Offset $DirectoryCountOffset -Label 'NumberOfRvaAndSizes'
$BoundedDirectoryCount = [Math]::Min([uint32]16, $DirectoryCount)
$DirectoryBytes = [long]$BoundedDirectoryCount * 8
if (($DirectoryBase + $DirectoryBytes) -gt ($Optional + $OptionalSize)) {
    throw 'data directories exceed optional-header boundary'
}

$SectionTable = $Optional + $OptionalSize
Assert-Range -Bytes $Bytes -Offset $SectionTable -Length ([long]$SectionCount * 40) -Label 'section table'
$Sections = @(
    for ($Index = 0; $Index -lt $SectionCount; $Index++) {
        $Base = $SectionTable + ($Index * 40)
        $Name = Get-SectionName -Bytes $Bytes -Offset $Base
        $VirtualSize = Read-U32 -Bytes $Bytes -Offset ($Base + 8) -Label 'VirtualSize'
        $VirtualAddress = Read-U32 -Bytes $Bytes -Offset ($Base + 12) -Label 'VirtualAddress'
        $RawSize = Read-U32 -Bytes $Bytes -Offset ($Base + 16) -Label 'SizeOfRawData'
        $RawOffset = Read-U32 -Bytes $Bytes -Offset ($Base + 20) -Label 'PointerToRawData'
        $SectionFlags = Read-U32 -Bytes $Bytes -Offset ($Base + 36) -Label 'section Characteristics'
        if ($RawSize -gt 0) {
            Assert-Range -Bytes $Bytes -Offset $RawOffset -Length $RawSize -Label "section $Name raw bytes"
        }
        $Entropy = if ($RawSize -gt 0) {
            Get-Entropy -Bytes $Bytes -Offset $RawOffset -Length $RawSize
        }
        else {
            0.0
        }
        [pscustomobject]@{
            Index = $Index
            Name = $Name
            VirtualSize = [uint32]$VirtualSize
            VirtualAddress = [uint32]$VirtualAddress
            RawSize = [uint32]$RawSize
            RawOffset = [uint32]$RawOffset
            Flags = [uint32]$SectionFlags
            Entropy = [double]$Entropy
        }
    }
)

$EntrySectionRows = @(
    $Sections | Where-Object {
        $Span = [Math]::Max([uint64]$_.VirtualSize, [uint64]$_.RawSize)
        [uint64]$EntryPointRva -ge [uint64]$_.VirtualAddress -and
        [uint64]$EntryPointRva -lt ([uint64]$_.VirtualAddress + $Span)
    }
)
$EntrySection = if ($EntrySectionRows.Count -eq 1) { $EntrySectionRows[0].Name } else { '<unresolved>' }

$Directories = @(
    for ($Index = 0; $Index -lt $BoundedDirectoryCount; $Index++) {
        $Base = $DirectoryBase + ($Index * 8)
        [pscustomobject]@{
            Index = $Index
            Va = Read-U32 -Bytes $Bytes -Offset $Base -Label "directory[$Index] VA"
            Size = Read-U32 -Bytes $Bytes -Offset ($Base + 4) -Label "directory[$Index] size"
        }
    }
)
function Get-DirectoryRow {
    param([int]$Index)
    $Rows = @($Directories | Where-Object { $_.Index -eq $Index })
    if ($Rows.Count -eq 0) {
        return [pscustomobject]@{ Index = $Index; Va = [uint32]0; Size = [uint32]0 }
    }
    return $Rows[0]
}
$ImportDirectory = Get-DirectoryRow -Index 1
$ResourceDirectory = Get-DirectoryRow -Index 2
$SecurityDirectory = Get-DirectoryRow -Index 4

$Imports = [System.Collections.Generic.List[object]]::new()
$Functions = [System.Collections.Generic.List[object]]::new()
if ($ImportDirectory.Va -ne 0 -and $ImportDirectory.Size -ne 0) {
    $ImportOffset = Convert-RvaToOffset -Rva $ImportDirectory.Va -Sections $Sections -SizeOfHeaders $SizeOfHeaders -Bytes $Bytes -Label 'import directory'
    $SawTerminator = $false
    for ($DescriptorIndex = 0; $DescriptorIndex -lt 1024; $DescriptorIndex++) {
        $Descriptor = $ImportOffset + ($DescriptorIndex * 20)
        Assert-Range -Bytes $Bytes -Offset $Descriptor -Length 20 -Label 'import descriptor'
        $OriginalThunk = Read-U32 -Bytes $Bytes -Offset $Descriptor -Label 'OriginalFirstThunk'
        $Stamp = Read-U32 -Bytes $Bytes -Offset ($Descriptor + 4) -Label 'Import TimeDateStamp'
        $Forwarder = Read-U32 -Bytes $Bytes -Offset ($Descriptor + 8) -Label 'ForwarderChain'
        $NameRva = Read-U32 -Bytes $Bytes -Offset ($Descriptor + 12) -Label 'Import Name RVA'
        $FirstThunk = Read-U32 -Bytes $Bytes -Offset ($Descriptor + 16) -Label 'FirstThunk'
        if ($OriginalThunk -eq 0 -and $Stamp -eq 0 -and $Forwarder -eq 0 -and $NameRva -eq 0 -and $FirstThunk -eq 0) {
            $SawTerminator = $true
            break
        }
        if ($NameRva -eq 0) {
            throw 'import descriptor has zero DLL-name RVA'
        }
        $DllNameOffset = Convert-RvaToOffset -Rva $NameRva -Sections $Sections -SizeOfHeaders $SizeOfHeaders -Bytes $Bytes -Label 'DLL name'
        $DllName = Read-AsciiZ -Bytes $Bytes -Offset $DllNameOffset -Label 'DLL name'
        $ThunkRva = if ($OriginalThunk -ne 0) { $OriginalThunk } else { $FirstThunk }
        $FunctionCount = 0
        if ($ThunkRva -ne 0) {
            $ThunkOffset = Convert-RvaToOffset -Rva $ThunkRva -Sections $Sections -SizeOfHeaders $SizeOfHeaders -Bytes $Bytes -Label 'import thunk'
            $SawThunkTerminator = $false
            for ($ThunkIndex = 0; $ThunkIndex -lt 65536; $ThunkIndex++) {
                $EntryOffset = $ThunkOffset + ($ThunkIndex * $ThunkSize)
                $Value = if ($ThunkSize -eq 4) {
                    [uint64](Read-U32 -Bytes $Bytes -Offset $EntryOffset -Label 'import thunk')
                }
                else {
                    Read-U64 -Bytes $Bytes -Offset $EntryOffset -Label 'import thunk'
                }
                if ($Value -eq 0) {
                    $SawThunkTerminator = $true
                    break
                }
                $FunctionCount++
                if (($Value -band $OrdinalMask) -ne 0) {
                    $Functions.Add([pscustomobject]@{
                        Dll = $DllName
                        Kind = 'ordinal'
                        Name = '#' + [string]([uint16]($Value -band 0xffff))
                    })
                }
                else {
                    if ($Value -gt [uint64][uint32]::MaxValue) {
                        throw 'import name RVA exceeds 32-bit PE RVA range'
                    }
                    $NameOffset = Convert-RvaToOffset -Rva ([uint32]$Value) -Sections $Sections -SizeOfHeaders $SizeOfHeaders -Bytes $Bytes -Label 'import hint/name'
                    [void](Read-U16 -Bytes $Bytes -Offset $NameOffset -Label 'import hint')
                    $FunctionName = Read-AsciiZ -Bytes $Bytes -Offset ($NameOffset + 2) -Label 'import function name'
                    $Functions.Add([pscustomobject]@{
                        Dll = $DllName
                        Kind = 'name'
                        Name = $FunctionName
                    })
                }
            }
            if (-not $SawThunkTerminator) {
                throw "import thunk list exceeded bounded contract for $DllName"
            }
        }
        $Imports.Add([pscustomobject]@{
            Dll = $DllName
            FunctionCount = $FunctionCount
        })
    }
    if (-not $SawTerminator) {
        throw 'import descriptor list exceeded bounded contract'
    }
}

$InterestingNames = @(
    'OpenSCManagerA','OpenSCManagerW','CreateServiceA','CreateServiceW',
    'OpenServiceA','OpenServiceW','StartServiceA','StartServiceW',
    'ControlService','DeleteService','CloseServiceHandle',
    'CreateProcessA','CreateProcessW','CreateProcessAsUserA','CreateProcessAsUserW',
    'WinExec','ShellExecuteA','ShellExecuteW','ShellExecuteExA','ShellExecuteExW',
    'RegCreateKeyExA','RegCreateKeyExW','RegOpenKeyExA','RegOpenKeyExW',
    'RegSetValueExA','RegSetValueExW','RegDeleteKeyA','RegDeleteKeyW',
    'LoadLibraryA','LoadLibraryW','GetProcAddress'
)
$InterestingImports = @(
    $Functions | Where-Object { $InterestingNames -contains $_.Name } | Sort-Object Dll, Name
)

$ResourceSectionRows = @()
if ($ResourceDirectory.Va -ne 0) {
    $ResourceSectionRows = @(
        $Sections | Where-Object {
            $Span = [Math]::Max([uint64]$_.VirtualSize, [uint64]$_.RawSize)
            [uint64]$ResourceDirectory.Va -ge [uint64]$_.VirtualAddress -and
            [uint64]$ResourceDirectory.Va -lt ([uint64]$_.VirtualAddress + $Span)
        }
    )
}
$ResourceSection = if ($ResourceSectionRows.Count -eq 1) { $ResourceSectionRows[0].Name } else { '<none-or-unresolved>' }

$RawEnd = [long]$SizeOfHeaders
foreach ($Section in $Sections) {
    $End = [long]$Section.RawOffset + [long]$Section.RawSize
    if ($End -gt $RawEnd) {
        $RawEnd = $End
    }
}
if ($SecurityDirectory.Va -ne 0 -and $SecurityDirectory.Size -ne 0) {
    $SecurityEnd = [long]$SecurityDirectory.Va + [long]$SecurityDirectory.Size
    if ($SecurityEnd -gt $RawEnd) {
        $RawEnd = $SecurityEnd
    }
}
$OverlayOffset = [Math]::Min($RawEnd, $Bytes.LongLength)
$OverlayBytes = $Bytes.LongLength - $OverlayOffset

$Markers = [System.Collections.Generic.List[object]]::new()
foreach ($Token in @(
    'UPX!','UPX0','UPX1','UPX2','MPRESS1','MPRESS2','MPRESS',
    'AutoIt v3','AutoIt3','AutoIt','AutoHotkey','Nullsoft','NSIS',
    'Inno Setup','ASPack','PECompact','Themida','VMProtect','7-Zip SFX'
)) {
    foreach ($Row in @(Find-MarkerOffsets -Bytes $Bytes -Token $Token)) {
        $Markers.Add($Row)
    }
}

$Lines = [System.Collections.Generic.List[string]]::new()
$Lines.Add('DBYTE-HOLYC-OPT')
$Lines.Add('PORTABLE VIRTUALBOX7 WRAPPER PE SURFACE R2 READ-ONLY INSPECTION')
$Lines.Add('')
$Lines.Add("portable_root`t$PortableRoot")
$Lines.Add("bound_wrapper_inspection_sha256`t$WrapperReportHash")
$Lines.Add("wrapper_path`t$WrapperPath")
$Lines.Add("wrapper_bytes`t$($WrapperItem.Length)")
$Lines.Add("wrapper_sha256`t$WrapperHash")
$Lines.Add("pe_kind`t$PeKind")
$Lines.Add("pe_offset`t0x$('{0:X}' -f $PeOffset)")
$Lines.Add("machine`t0x$('{0:X4}' -f $Machine)")
$Lines.Add("section_count`t$SectionCount")
$Lines.Add("timestamp`t0x$('{0:X8}' -f $TimeDateStamp)")
$Lines.Add("characteristics`t0x$('{0:X4}' -f $Characteristics)")
$Lines.Add("dll_characteristics`t0x$('{0:X4}' -f $DllCharacteristics)")
$Lines.Add("subsystem`t$Subsystem")
$Lines.Add("entry_point_rva`t0x$('{0:X8}' -f $EntryPointRva)")
$Lines.Add("entry_point_section`t$EntrySection")
$Lines.Add("size_of_image`t$SizeOfImage")
$Lines.Add("size_of_headers`t$SizeOfHeaders")
$Lines.Add('')
$Lines.Add("section_row_count`t$($Sections.Count)")
foreach ($Section in $Sections) {
    $Lines.Add(
        'section_row' + "`t" + $Section.Index + "`t" + $Section.Name + "`t" +
        ('0x{0:X8}' -f $Section.VirtualAddress) + "`t" + $Section.VirtualSize + "`t" +
        ('0x{0:X8}' -f $Section.RawOffset) + "`t" + $Section.RawSize + "`t" +
        ('{0:F4}' -f $Section.Entropy) + "`t" + ('0x{0:X8}' -f $Section.Flags)
    )
}
$Lines.Add('')
$Lines.Add("import_directory_rva`t0x$('{0:X8}' -f $ImportDirectory.Va)")
$Lines.Add("import_directory_size`t$($ImportDirectory.Size)")
$Lines.Add("import_dll_count`t$($Imports.Count)")
foreach ($Import in $Imports) {
    $Lines.Add("import_dll`t$($Import.Dll)`t$($Import.FunctionCount)")
}
$Lines.Add("import_function_count`t$($Functions.Count)")
foreach ($Function in $Functions) {
    $Lines.Add("import_function`t$($Function.Dll)`t$($Function.Kind)`t$($Function.Name)")
}
$Lines.Add("interesting_import_count`t$($InterestingImports.Count)")
foreach ($Function in $InterestingImports) {
    $Lines.Add("interesting_import`t$($Function.Dll)`t$($Function.Name)")
}
$Lines.Add('')
$Lines.Add("resource_directory_rva`t0x$('{0:X8}' -f $ResourceDirectory.Va)")
$Lines.Add("resource_directory_size`t$($ResourceDirectory.Size)")
$Lines.Add("resource_section`t$ResourceSection")
$Lines.Add("security_directory_file_offset`t0x$('{0:X8}' -f $SecurityDirectory.Va)")
$Lines.Add("security_directory_size`t$($SecurityDirectory.Size)")
$Lines.Add("overlay_offset`t0x$('{0:X}' -f $OverlayOffset)")
$Lines.Add("overlay_bytes`t$OverlayBytes")
$Lines.Add("marker_count`t$($Markers.Count)")
foreach ($Marker in $Markers) {
    $Lines.Add("marker`t$($Marker.Encoding)`t0x$('{0:X}' -f $Marker.Offset)`t$($Marker.Token)")
}
$Lines.Add('')
$Lines.Add("HOST MUTATION`tNOT-EXECUTED")
$Lines.Add("WRAPPER EXECUTION`tNOT-EXECUTED")
$Lines.Add("DRIVER INSTALL/START`tNOT-EXECUTED")
$Lines.Add("VBOXMANAGE`tNOT-EXECUTED")
$Lines.Add("VM START`tNOT-AUTHORIZED")
$Lines.Add("VERDICT`tPORTABLE WRAPPER PE SURFACE R2 INSPECTION COMPLETE")
$Lines.Add('')
$Lines.Add('REPORTS ARE CLAIMS, NOT EVIDENCE.')

[System.IO.File]::WriteAllText(
    $Output,
    (($Lines.ToArray() -join "`n") + "`n"),
    [System.Text.UTF8Encoding]::new($false)
)

$ReportHash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash
Write-Host "PORTABLE ROOT:          $PortableRoot"
Write-Host "BOUND WRAPPER REPORT:   $WrapperReportHash"
Write-Host "WRAPPER SHA256:         $WrapperHash"
Write-Host "PE KIND:                $PeKind"
Write-Host "SECTIONS:               $($Sections.Count)"
Write-Host "ENTRYPOINT SECTION:     $EntrySection"
Write-Host "IMPORT DLLS:            $($Imports.Count)"
Write-Host "IMPORT FUNCTIONS:       $($Functions.Count)"
Write-Host "INTERESTING IMPORTS:    $($InterestingImports.Count)"
Write-Host "RESOURCE SECTION:       $ResourceSection"
Write-Host "OVERLAY BYTES:          $OverlayBytes"
Write-Host "PACKER/MARKER HITS:     $($Markers.Count)"
Write-Host "REPORT:                 $Output"
Write-Host "REPORT SHA256:          $ReportHash"
Write-Host 'HOST MUTATION:          NOT-EXECUTED'
Write-Host 'WRAPPER EXECUTION:      NOT-EXECUTED'
Write-Host 'DRIVER INSTALL/START:   NOT-EXECUTED'
Write-Host 'VBOXMANAGE:             NOT-EXECUTED'
Write-Host 'VM START:               NOT-AUTHORIZED'
Write-Host 'VERDICT:                PORTABLE WRAPPER PE SURFACE R2 INSPECTION COMPLETE'
