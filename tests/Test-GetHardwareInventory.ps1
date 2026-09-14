#requires -Version 5.1

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $ProjectRoot 'Get-HardwareInventory.ps1')

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

$Models = @(Import-ModelDatabase -Path (Join-Path $ProjectRoot 'hardware-models.json'))
Assert-True -Condition ($Models.Count -gt 0) -Message 'The model database should not be empty.'
Assert-True -Condition (@($Models | Where-Object model -EQ 'Latitude 7420').Count -eq 1) -Message 'Latitude 7420 should be unique.'

Assert-True -Condition (Test-IsoDate -Value '2025-05-28') -Message 'A valid ISO date should pass.'
Assert-True -Condition (-not (Test-IsoDate -Value '2025-02-30')) -Message 'An invalid calendar date should fail.'
Assert-True -Condition (Test-ServiceTag -Value '13QJ7D3') -Message 'A Dell Service Tag should pass.'
Assert-True -Condition (-not (Test-ServiceTag -Value 'To be filled by O.E.M.')) -Message 'A BIOS placeholder should fail.'

# Regression test for Windows PowerShell 5.1: @($list) fails for a generic
# List[object] containing PSCustomObject, so production code must use ToArray().
$GenericParts = New-Object System.Collections.Generic.List[object]
$GenericParts.Add((New-HardwarePart -Type 'RAM' -Description '16GB' -Connection 'slot'))
$ConvertedParts = $GenericParts.ToArray()
Assert-True -Condition ($ConvertedParts.Count -eq 1) -Message 'A generic hardware list should convert to an object array.'

$ClockFromGhzName = Get-ProcessorClockSpeedMhz -Processors @(
    [pscustomobject]@{ Name = '11th Gen Intel(R) Core(TM) i7-1185G7 @ 3.00GHz'; MaxClockSpeed = 1805 }
)
Assert-True -Condition ($ClockFromGhzName -eq 3000) -Message 'The processor frequency in GHz should be read from its name and converted to MHz.'

$ClockFromWmiFallback = Get-ProcessorClockSpeedMhz -Processors @(
    [pscustomobject]@{ Name = 'Intel(R) Core(TM) Ultra Test'; MaxClockSpeed = 2100 }
)
Assert-True -Condition ($ClockFromWmiFallback -eq 2100) -Message 'MaxClockSpeed should be used when the processor name has no frequency.'

Initialize-NvmeHealthApi
$MockHealthLog = New-Object byte[] 512
$MockHealthLog[5] = 3
[BitConverter]::GetBytes([uint64]2000000).CopyTo($MockHealthLog, 32)
[BitConverter]::GetBytes([uint64]1000000).CopyTo($MockHealthLog, 48)
[BitConverter]::GetBytes([uint64]2400).CopyTo($MockHealthLog, 128)
$ParsedHealthLog = [GetHardware.NvmeHealthReaderV1]::ParseHealthLog($MockHealthLog)
Assert-True -Condition ($ParsedHealthLog.PercentageUsed -eq 3) -Message 'The NVMe health parser should read PercentageUsed.'
Assert-True -Condition ($ParsedHealthLog.DataUnitsRead -eq 2000000) -Message 'The NVMe health parser should read DataUnitsRead.'
Assert-True -Condition ($ParsedHealthLog.DataUnitsWritten -eq 1000000) -Message 'The NVMe health parser should read DataUnitsWritten.'
Assert-True -Condition ($ParsedHealthLog.PowerOnHours -eq 2400) -Message 'The NVMe health parser should read PowerOnHours.'

$script:FailedCimClass = $null

function Get-PnpDevice {
    param([switch]$PresentOnly, $ErrorAction)
    return @()
}
function Get-PnpDeviceProperty {
    param([string]$InstanceId, [string]$KeyName, $ErrorAction)
    return [pscustomobject]@{ Data = @() }
}
function Get-PhysicalDisk {
    param($ErrorAction)
    return [pscustomobject]@{
        DeviceId          = '0'
        FriendlyName      = 'EG6 KIOXIA 512GB'
        Manufacturer      = ''
        Model             = 'EG6 KIOXIA 512GB'
        SerialNumber      = '8CE3_8E04_0558_F5B4.'
        FirmwareVersion   = '11600104'
        MediaType         = 'SSD'
        BusType           = 'NVMe'
        Size              = 512000000000
        HealthStatus      = 'Healthy'
        OperationalStatus = 'OK'
        PhysicalLocation  = 'Integrated : Bus 1 : Device 0 : Function 0 : Adapter 0'
        UniqueId          = 'eui.8CE38E040558F5B4'
    }
}
$script:MockDiskFormFactorName = 'M.2'
function Get-NativeDiskFormFactor {
    param([int]$DiskNumber)
    $Code = if ($script:MockDiskFormFactorName -eq 'M.2') { 8 } else { 0 }
    return [pscustomobject]@{ Code = $Code; Name = $script:MockDiskFormFactorName; Source = 'Mock'; Detail = '' }
}
function Get-NativeNvmeHealth {
    param([int]$DiskNumber)
    return [pscustomobject]@{
        Available        = $true
        PowerOnHours     = [uint64]2400
        DataUnitsRead    = [uint64]2000000
        DataUnitsWritten = [uint64]1000000
        PercentageUsed   = 3
    }
}
function Get-DiskReliabilityData {
    param([psobject]$Disk)
    return $null
}
function Get-NetAdapter {
    param([string]$Name, [switch]$IncludeHidden, $ErrorAction)
    return @(
        [pscustomobject]@{ Name = 'Ethernet'; InterfaceDescription = 'Intel(R) Ethernet Connection (14) I219-LM'; PermanentAddress = 'A0291926DE3D'; MacAddress = 'A0-29-19-26-DE-3D'; HardwareInterface = $true; Virtual = $false; ConnectorPresent = $true; PhysicalMediaType = '802.3'; PnPDeviceID = 'PCI\VEN_8086&DEV_15F9' }
        [pscustomobject]@{ Name = 'Wi-Fi'; InterfaceDescription = 'Intel(R) Wi-Fi 6 AX201 160MHz'; PermanentAddress = 'AC74B13CDD18'; MacAddress = 'AC-74-B1-3C-DD-18'; HardwareInterface = $true; Virtual = $false; ConnectorPresent = $true; PhysicalMediaType = 'Native 802.11'; PnPDeviceID = 'PCI\VEN_8086&DEV_43F0' }
        [pscustomobject]@{ Name = 'Bluetooth Network Connection'; InterfaceDescription = 'Bluetooth Device (Personal Area Network)'; PermanentAddress = 'AC74B13CDD1C'; MacAddress = 'AC-74-B1-3C-DD-1C'; HardwareInterface = $false; Virtual = $true; ConnectorPresent = $false; PhysicalMediaType = 'BlueTooth'; PnPDeviceID = 'BTH\MS_BTHPAN' }
        [pscustomobject]@{ Name = 'Ethernet 3'; InterfaceDescription = 'Realtek USB GbE Family Controller'; PermanentAddress = 'C03EBA333E88'; MacAddress = 'C0-3E-BA-33-3E-88'; HardwareInterface = $true; Virtual = $false; ConnectorPresent = $true; PhysicalMediaType = '802.3'; PnPDeviceID = 'USB\VID_0BDA&PID_8153' }
        [pscustomobject]@{ Name = 'Ethernet 2'; InterfaceDescription = 'Cisco AnyConnect Virtual Miniport Adapter for Windows x64'; PermanentAddress = '00059A3C7A00'; MacAddress = '00-05-9A-3C-7A-00'; HardwareInterface = $false; Virtual = $true; ConnectorPresent = $false; PhysicalMediaType = 'Unspecified'; PnPDeviceID = 'ROOT\NET\0000' }
        [pscustomobject]@{ Name = 'Local Area Connection* 1'; InterfaceDescription = 'Microsoft Wi-Fi Direct Virtual Adapter'; PermanentAddress = 'AC74B13CDD19'; MacAddress = 'AC-74-B1-3C-DD-19'; HardwareInterface = $false; Virtual = $true; ConnectorPresent = $false; PhysicalMediaType = 'Native 802.11'; PnPDeviceID = '{5d624f94-8850-40c3-a3fa-a4fd2080baf3}\vwifimp_wfd' }
        [pscustomobject]@{ Name = 'Local Area Connection* 7'; InterfaceDescription = 'WAN Miniport (IP)'; PermanentAddress = ''; MacAddress = ''; HardwareInterface = $false; Virtual = $true; ConnectorPresent = $false; PhysicalMediaType = 'Unspecified'; PnPDeviceID = 'SWD\MSRRAS\MS_NDISWANIP' }
    )
}
function Get-CimInstance {
    param(
        [string]$ClassName,
        [string]$Namespace,
        $ErrorAction
    )

    if ($ClassName -eq $script:FailedCimClass) {
        throw "Mocked CIM failure: $ClassName"
    }

    switch ($ClassName) {
        'Win32_ComputerSystem' {
            return [pscustomobject]@{
                Model        = 'Latitude 7420'
                Manufacturer = 'Dell Inc.'
            }
        }
        'Win32_BIOS' {
            return [pscustomobject]@{ SerialNumber = '13QJ7D3' }
        }
        'Win32_BaseBoard' {
            return [pscustomobject]@{
                Manufacturer = 'Dell Inc.'
                Product      = '0FFCXR'
                Version      = 'A00'
            }
        }
        'Win32_SystemEnclosure' {
            return [pscustomobject]@{
                Manufacturer = 'Dell Inc.'
                SerialNumber = '13QJ7D3'
                ChassisTypes = [uint16[]](10)
            }
        }
        'Win32_Processor' {
            return [pscustomobject]@{
                Name          = 'Test CPU'
                NumberOfCores = 4
                MaxClockSpeed = 3000
            }
        }
        'WmiMonitorBasicDisplayParams' {
            return [pscustomobject]@{
                InstanceName          = 'DISPLAY\NCP002B\TEST_0'
                MaxHorizontalImageSize = 31
                MaxVerticalImageSize   = 17
            }
        }
        'WmiMonitorConnectionParams' {
            return [pscustomobject]@{
                InstanceName         = 'DISPLAY\NCP002B\TEST_0'
                VideoOutputTechnology = [uint32]2147483648
            }
        }
        'WmiMonitorListedSupportedSourceModes' {
            return [pscustomobject]@{
                InstanceName       = 'DISPLAY\NCP002B\TEST_0'
                MonitorSourceModes = @(
                    [pscustomobject]@{ HorizontalActivePixels = 1280; VerticalActivePixels = 720 }
                    [pscustomobject]@{ HorizontalActivePixels = 1920; VerticalActivePixels = 1080 }
                )
            }
        }
        'WmiMonitorID' {
            return [pscustomobject]@{
                InstanceName    = 'DISPLAY\NCP002B\TEST_0'
                Active          = $true
                ManufacturerName = [byte[]](78, 67, 80, 0)
                ProductCodeID    = [byte[]](48, 48, 50, 66, 0)
                UserFriendlyName = [byte[]](0)
                SerialNumberID   = [byte[]](48, 0)
            }
        }
        'Win32_PhysicalMemory' {
            return [pscustomobject]@{
                Capacity             = 16GB
                ConfiguredClockSpeed = 3200
                Speed                = 3200
                SMBIOSMemoryType     = 26
                FormFactor           = 12
                DeviceLocator        = 'DIMM A'
                BankLabel            = 'BANK 0'
                SerialNumber         = '16596967'
            }
        }
        'Win32_PhysicalMemoryArray' {
            return [pscustomobject]@{
                MemoryDevices = 2
                MaxCapacity   = 33554432
                MaxCapacityEx = 33554432
                Location      = 3
                Use           = 3
            }
        }
        'Win32_DiskDrive' {
            return [pscustomobject]@{
                Size          = 256000000000
                Model         = 'TEST NVME'
                PNPDeviceID   = 'PCI\NVME_TEST'
                InterfaceType = 'SCSI'
            }
        }
        'Win32_NetworkAdapter' {
            return [pscustomobject]@{
                PhysicalAdapter = $true
                MACAddress      = 'D0:3C:1F:D5:C7:D0'
                Description     = 'Test network adapter'
            }
        }
        'Win32_SoundDevice' {
            return [pscustomobject]@{ Caption = 'Test audio' }
        }
        'Win32_VideoController' {
            return @(
                [pscustomobject]@{ AdapterRAM = 1GB; Caption = 'Test graphics'; PNPDeviceID = 'PCI\VEN_8086&DEV_TEST' }
                [pscustomobject]@{ AdapterRAM = 0; Caption = 'Microsoft Remote Display Adapter'; PNPDeviceID = 'ROOT\RDPIDD' }
            )
        }
        'Win32_Battery' {
            return [pscustomobject]@{ Name = 'Internal Battery'; Description = 'Battery' }
        }
        default { throw "Unexpected mocked CIM class: $ClassName" }
    }
}

$SystemOverview = Get-SystemOverview
Assert-True -Condition ($SystemOverview.ServiceTag -eq '13QJ7D3') -Message 'The system overview should read the BIOS serial number.'
Assert-True -Condition ($SystemOverview.Model -eq 'Latitude 7420') -Message 'The system overview should read the computer model.'
Assert-True -Condition ($SystemOverview.BaseBoardProduct -eq '0FFCXR') -Message 'The system overview should read the baseboard product.'
Assert-True -Condition ($SystemOverview.ChassisDescription -eq 'Notebook (10)') -Message 'The system overview should expose the SMBIOS chassis name and code.'
Assert-True -Condition ($SystemOverview.DetectedDeviceType -eq 'laptop') -Message 'Notebook chassis type 10 should map to laptop.'

$script:FailedCimClass = 'Win32_BIOS'
$SystemWithoutBios = Get-SystemOverview
Assert-True -Condition ($SystemWithoutBios.ServiceTag -eq '') -Message 'A BIOS failure should produce an empty Service Tag for manual fallback.'
Assert-True -Condition ($SystemWithoutBios.Model -eq 'Latitude 7420') -Message 'A BIOS failure should not discard computer-system data.'
Assert-True -Condition ($SystemWithoutBios.Processor -eq 'Test CPU') -Message 'A BIOS failure should not discard processor data.'
$script:FailedCimClass = $null

$TestModelEntry = $Models | Where-Object model -EQ 'Latitude 7420' | Select-Object -First 1

$SlotMemory = ConvertTo-MemoryInventory `
    -MemoryDevices @(
        [pscustomobject]@{ Capacity = 16GB; Speed = 3200; ConfiguredClockSpeed = 2933; SMBIOSMemoryType = 26; FormFactor = 12; DeviceLocator = 'DIMM A'; BankLabel = ''; SerialNumber = '16596967' }
        [pscustomobject]@{ Capacity = 16GB; Speed = 3200; ConfiguredClockSpeed = 2933; SMBIOSMemoryType = 26; FormFactor = 12; DeviceLocator = 'DIMM C'; BankLabel = ''; SerialNumber = '16596D3D' }
    ) `
    -MemoryArrays @(
        [pscustomobject]@{ MemoryDevices = 4; MaxCapacity = 134217728; MaxCapacityEx = 134217728; Location = 3; Use = 3 }
    )
Assert-True -Condition ($SlotMemory.Parts.Count -eq 2) -Message 'Replaceable RAM modules should remain separate PHP parts.'
Assert-True -Condition ($SlotMemory.Parts[0].Desc -eq '16GB 3200MHz DDR4') -Message 'RAM parts should use rated Speed instead of ConfiguredClockSpeed.'
Assert-True -Condition ($SlotMemory.Parts[0].Conn -eq 'on board') -Message 'Replaceable RAM should use the agreed on board connection.'
Assert-True -Condition ($SlotMemory.Parts[0].Sn -eq '16596967') -Message 'A valid RAM serial number should be preserved.'
Assert-True -Condition ($SlotMemory.DetectedSpec -eq 'DDR4 3200MHz x4, max128GB') -Message 'Slot count and maximum capacity should form memorySpec.'

$MemoryWithInvalidRecord = ConvertTo-MemoryInventory `
    -MemoryDevices @(
        [pscustomobject]@{ Capacity = 16GB; Speed = 3200; ConfiguredClockSpeed = 2933; SMBIOSMemoryType = 26; FormFactor = 12; DeviceLocator = 'DIMM A'; BankLabel = ''; SerialNumber = '16596967' }
        [pscustomobject]@{ DeviceLocator = 'BROKEN DIMM' }
    ) `
    -MemoryArrays @()
Assert-True -Condition ($MemoryWithInvalidRecord.Parts.Count -eq 1) -Message 'An invalid RAM record should not discard valid modules.'

$SolderedDevices = @(
    for ($Index = 0; $Index -lt 8; $Index++) {
        [pscustomobject]@{ Capacity = 2GB; Speed = 4267; ConfiguredClockSpeed = 4267; SMBIOSMemoryType = 30; FormFactor = 0; DeviceLocator = 'Motherboard'; BankLabel = "BANK $($Index % 4)"; SerialNumber = '00000000' }
    }
)
$SolderedMemory = ConvertTo-MemoryInventory `
    -MemoryDevices $SolderedDevices `
    -MemoryArrays @(
        [pscustomobject]@{ MemoryDevices = 8; MaxCapacity = 16777216; MaxCapacityEx = 16777216; Location = 3; Use = 3 }
    )
Assert-True -Condition ($SolderedMemory.Parts.Count -eq 1) -Message 'Soldered memory chips should be grouped into one PHP part.'
Assert-True -Condition ($SolderedMemory.Parts[0].Desc -eq '16GB 4267MHz LPDDR4') -Message 'Grouped soldered memory should contain total capacity, rated speed, and type.'
Assert-True -Condition ($SolderedMemory.Parts[0].Conn -eq 'soldered') -Message 'Motherboard LPDDR memory should be marked as soldered.'
Assert-True -Condition ($SolderedMemory.Parts[0].Sn -eq '') -Message 'Placeholder RAM serial numbers should be discarded.'
Assert-True -Condition ($SolderedMemory.DetectedSpec -eq 'LPDDR4 4267MHz soldered, max16GB') -Message 'Soldered memorySpec should not treat memory devices as slots.'

$DisplayParts = @(ConvertTo-DisplayParts `
    -MonitorIds @([pscustomobject]@{ InstanceName = 'DISPLAY\NCP002B\TEST_0'; Active = $true; SerialNumberID = [byte[]](48, 0) }) `
    -DisplayParameters @([pscustomobject]@{ InstanceName = 'DISPLAY\NCP002B\TEST_0'; MaxHorizontalImageSize = 31; MaxVerticalImageSize = 17 }) `
    -ConnectionParameters @([pscustomobject]@{ InstanceName = 'DISPLAY\NCP002B\TEST_0'; VideoOutputTechnology = [uint32]2147483648 }) `
    -ModeLists @([pscustomobject]@{ InstanceName = 'DISPLAY\NCP002B\TEST_0'; MonitorSourceModes = @([pscustomobject]@{ HorizontalActivePixels = 1920; VerticalActivePixels = 1080 }) }) `
    -TouchDetected $false)
Assert-True -Condition ($DisplayParts.Count -eq 1) -Message 'The active internal panel should produce one display part.'
Assert-True -Condition ($DisplayParts[0].Pt -eq 'Matrix') -Message 'An INTERNAL video output should be classified as Matrix.'
Assert-True -Condition ($DisplayParts[0].Desc -eq '14" 1920x1080') -Message 'A 31x17 cm panel should be normalized to the agreed 14-inch native-resolution description.'
Assert-True -Condition ($DisplayParts[0].Conn -eq 'on board') -Message 'An internal panel should use the agreed on board connection.'
Assert-True -Condition ($DisplayParts[0].Sn -eq '') -Message 'A placeholder EDID serial number should not be written to PHP.'
Assert-True -Condition ((Get-DisplaySizeText -WidthCm 34 -HeightCm 19) -eq '15.6"') -Message 'An imprecise 15.3-inch WMI result should snap to the common 15.6-inch size.'
Assert-True -Condition ((Get-DisplaySizeText -WidthCm 38 -HeightCm 21) -eq '17.3"') -Message 'An imprecise 17.1-inch WMI result should snap to the common 17.3-inch size.'
Assert-True -Condition ((Get-DisplaySizeText -WidthCm 32 -HeightCm 18) -eq '14.5"') -Message 'A nonstandard size outside the tolerance should retain one decimal place.'

$TouchDisplayParts = @(ConvertTo-DisplayParts `
    -MonitorIds @([pscustomobject]@{ InstanceName = 'DISPLAY\NCP002B\TEST_0'; Active = $true; SerialNumberID = [byte[]](48, 0) }) `
    -DisplayParameters @([pscustomobject]@{ InstanceName = 'DISPLAY\NCP002B\TEST_0'; MaxHorizontalImageSize = 31; MaxVerticalImageSize = 17 }) `
    -ConnectionParameters @([pscustomobject]@{ InstanceName = 'DISPLAY\NCP002B\TEST_0'; VideoOutputTechnology = 11 }) `
    -ModeLists @([pscustomobject]@{ InstanceName = 'DISPLAY\NCP002B\TEST_0'; MonitorSourceModes = @([pscustomobject]@{ HorizontalActivePixels = 1920; VerticalActivePixels = 1080 }) }) `
    -TouchDetected $true)
Assert-True -Condition ($TouchDisplayParts[0].Desc -eq '14" 1920x1080 touch') -Message 'A detected HID touchscreen should add touch only to the internal matrix description.'

$DiskPart = New-PhysicalDiskPart -Disk (Get-PhysicalDisk)
Assert-True -Condition ($DiskPart.Desc -eq '512GB NVMe SSD EG6 KIOXIA') -Message 'The disk description should contain decimal capacity, bus, media type, and a deduplicated model.'
Assert-True -Condition ($DiskPart.Conn -eq 'M.2') -Message 'A native M.2 form factor should be accepted without an interactive fallback.'
Assert-True -Condition ($DiskPart.Sn -eq '8CE38E040558F5B4') -Message 'The grouped NVMe serial number should be normalized.'
Assert-True -Condition ($DiskPart.DiskHealthStatus -eq 'Healthy') -Message 'The disk diagnostic data should preserve HealthStatus.'
Assert-True -Condition ($DiskPart.DiskPowerOnHours -eq 2400) -Message 'The disk diagnostic data should preserve NVMe power-on hours.'
Assert-True -Condition ($DiskPart.DiskBytesRead -eq 1024000000000) -Message 'NVMe data units read should be converted to bytes.'
Assert-True -Condition ($DiskPart.DiskBytesWritten -eq 512000000000) -Message 'NVMe data units written should be converted to bytes.'
Assert-True -Condition ($DiskPart.DiskWearPercent -eq 3) -Message 'The disk diagnostic data should preserve the NVMe wear percentage.'
Assert-True -Condition ((Format-DiskPowerOnTime -Hours 2400) -match '^2400 h \(100[,.]0 dni\)$') -Message 'Power-on hours should also be shown as days.'
Assert-True -Condition ((Format-DiskDataAmount -Bytes 1024000000000) -match '^1[,.]02 TB$') -Message 'Disk byte counters should be shown in decimal TB.'
Assert-True -Condition ((Format-DiskWearLevel -WearPercent 3) -eq '3%') -Message 'Disk wear should be shown as a percentage.'

$NetworkParts = @(Get-NetworkInventoryParts)
Assert-True -Condition ($NetworkParts.Count -eq 3) -Message 'Only built-in Ethernet, Wi-Fi, and Bluetooth PAN should remain.'
Assert-True -Condition (@($NetworkParts | Where-Object Desc -EQ 'Realtek USB GbE Family Controller').Count -eq 0) -Message 'A USB network adapter should not be written to PHP.'
Assert-True -Condition (@($NetworkParts | Where-Object Desc -EQ 'Cisco AnyConnect Virtual Miniport Adapter for Windows x64').Count -eq 0) -Message 'A VPN adapter should be excluded.'
Assert-True -Condition (($NetworkParts | Where-Object Desc -EQ 'Intel(R) Wi-Fi 6 AX201 160MHz').Sn -eq 'AC74B13CDD18') -Message 'PermanentAddress should be preferred and normalized.'
Assert-True -Condition (($NetworkParts | Where-Object Desc -EQ 'Bluetooth Device (Personal Area Network)').Conn -eq 'on board') -Message 'Bluetooth PAN should be retained despite Windows marking it virtual.'
Assert-True -Condition ((Get-NormalizedMacAddress -Value 'FF-FF-FF-FF-FF-FF') -eq '') -Message 'A broadcast MAC address should be rejected.'
Assert-True -Condition (Test-LocallyAdministeredMacAddress -Value '02-11-22-33-44-55') -Message 'A locally administered MAC address should be recognized.'

$DetectedMainboard = Resolve-MainboardDescription `
    -ModelEntry $TestModelEntry `
    -MemorySpec ([string]$TestModelEntry.memorySpec) `
    -Manufacturer $SystemOverview.BaseBoardManufacturer `
    -Product $SystemOverview.BaseBoardProduct `
    -Version $SystemOverview.BaseBoardVersion
Assert-True -Condition ($DetectedMainboard -eq "Dell Inc. 0FFCXR A00 ($($TestModelEntry.memorySpec))") -Message 'Detected baseboard data should be combined with memorySpec.'

$script:MockReadHostValue = ''
$script:MockReadHostQueue = New-Object System.Collections.Generic.Queue[string]
function Read-Host {
    param([string]$Prompt)
    if ($script:MockReadHostQueue.Count -gt 0) {
        return $script:MockReadHostQueue.Dequeue()
    }
    return $script:MockReadHostValue
}

Assert-True -Condition ((Resolve-DeviceType -DatabaseDeviceType 'laptop' -DetectedDeviceType 'laptop' -ChassisDescription 'Notebook (10)') -eq 'laptop') -Message 'Matching device types should be accepted without a question.'
$script:MockReadHostQueue.Enqueue('2')
Assert-True -Condition ((Resolve-DeviceType -DatabaseDeviceType 'desktop' -DetectedDeviceType 'laptop' -ChassisDescription 'Notebook (10)') -eq 'laptop') -Message 'The user should be able to use the detected type for the current device.'
Assert-True -Condition ((Resolve-DeviceType -DatabaseDeviceType 'server' -DetectedDeviceType '' -ChassisDescription 'Unknown (2)') -eq 'server') -Message 'An unknown chassis type should preserve the database value without a question.'

$script:MockDiskFormFactorName = 'Unknown'
$UnknownFormatDiskPart = New-PhysicalDiskPart -Disk (Get-PhysicalDisk)
Assert-True -Condition ($UnknownFormatDiskPart.Conn -eq 'M.2') -Message 'An unknown NVMe form factor should offer and accept M.2 as the default.'
$script:MockDiskFormFactorName = 'M.2'

$FallbackMainboard = Resolve-MainboardDescription `
    -ModelEntry $TestModelEntry `
    -MemorySpec ([string]$TestModelEntry.memorySpec) `
    -Manufacturer '' `
    -Product '' `
    -Version ''
Assert-True -Condition ($FallbackMainboard -eq "Latitude 7420 ($($TestModelEntry.memorySpec))") -Message 'Missing baseboard data should offer and accept baseboardFallback from JSON.'

$script:MockReadHostValue = 'Custom baseboard A01'
$CustomMainboard = Resolve-MainboardDescription `
    -ModelEntry $TestModelEntry `
    -MemorySpec ([string]$TestModelEntry.memorySpec) `
    -Manufacturer '' `
    -Product 'Unknown' `
    -Version ''
Assert-True -Condition ($CustomMainboard -eq "Custom baseboard A01 ($($TestModelEntry.memorySpec))") -Message 'The user should be able to replace the baseboard fallback.'

$script:MockReadHostValue = ''
$script:MockReadHostQueue.Enqueue('on board,HDMI,USB-C')
$DetectedMockParts = @(Get-HardwareParts -ComputerModel 'Latitude 7420')
Assert-True -Condition ($DetectedMockParts.Count -eq 9) -Message 'The mocked hardware scan should return all component categories and three built-in network adapters.'
Assert-True -Condition (($DetectedMockParts | Where-Object Pt -EQ 'Matrix').Desc -eq '14" 1920x1080') -Message 'The mocked scan should include the EDID-based matrix description.'
Assert-True -Condition (@($DetectedMockParts | Where-Object Pt -EQ 'RAM').Count -eq 1) -Message 'The mocked scan should include RAM.'
Assert-True -Condition (@($DetectedMockParts | Where-Object Pt -EQ 'Hard Disk').Count -eq 1) -Message 'The mocked scan should include a disk.'
Assert-True -Condition (($DetectedMockParts | Where-Object Pt -EQ 'Hard Disk').Desc -eq '512GB NVMe SSD EG6 KIOXIA') -Message 'The mocked scan should use Get-PhysicalDisk data.'
Assert-True -Condition (@($DetectedMockParts | Where-Object Pt -EQ 'Network Card').Count -eq 3) -Message 'The mocked scan should include only the approved built-in network adapters.'
Assert-True -Condition (@($DetectedMockParts | Where-Object Pt -EQ 'Graphic Card').Count -eq 1) -Message 'Software and remote display adapters should be excluded.'
Assert-True -Condition (($DetectedMockParts | Where-Object Pt -EQ 'Graphic Card').Conn -eq 'on board,HDMI,USB-C') -Message 'The user-entered graphics outputs should be preserved.'

$Inventory = [pscustomobject]@{
    ServiceTag    = '13QJ7D3'
    Model         = 'Latitude 7420'
    Bought        = '2025-05-28'
    Warranty      = '2021-05-20+3'
    Price         = '1414,08'
    Label         = 'W10P'
    Processor     = "Intel test's CPU"
    CoreCount     = 4
    ClockSpeedMhz = 3000
    Mainboard     = 'Latitude 7420'
    PowerMaxW     = 65
    PowerW        = 45
    Manufacturer  = 'Dell Inc.'
    Room          = 'A216'
    Other         = 'USB-C'
    Note          = 'SCC:21393;REFURBISHED;'
    DatabaseDeviceType = 'laptop'
    ChassisDescription = 'Notebook (10)'
    DetectedDeviceType = 'laptop'
    DeviceType    = 'laptop'
}
$Parts = @(
    New-HardwarePart -Type 'Matrix' -Description '14" 1920x1080 touch' -Connection 'on board'
    New-HardwarePart -Type 'Network Card' -Description "Adapter test's name" -Connection 'on board' -SerialNumber 'D03C1FD5C7D0'
)

$Body = New-PhpRecordBody -Inventory $Inventory -Parts $Parts
Assert-True -Condition ($Body.Contains("addComp('13QJ7D3_laptop',`$C,`$partsLapt);")) -Message 'The addComp call should contain the laptop suffix and three arguments.'
Assert-True -Condition ($Body.Contains("Intel test\'s CPU")) -Message 'Apostrophes should be escaped for PHP.'
Assert-True -Condition ($Body.Contains(",'mhz'=>3000")) -Message 'The resolved processor frequency should be written to mhz.'
Assert-True -Condition ($Body.Contains("'sn'=>'D03C1FD5C7D0'")) -Message 'Optional component serial numbers should be rendered.'

$DevicePhp = New-DevicePhp -Body $Body
Assert-True -Condition ($DevicePhp.StartsWith("<?php`r`n")) -Message 'A device file should start with a PHP opening tag.'
Assert-True -Condition ($DevicePhp.EndsWith("?>`r`n")) -Message 'A device file should end with a PHP closing tag.'

$FirstBlock = New-CollectionBlock -ServiceTag '13QJ7D3' -Body $Body
$CollectionPhp = Update-CollectionPhp -ExistingContent $null -ServiceTag '13QJ7D3' -Block $FirstBlock -Action Add
Assert-True -Condition ($CollectionPhp.Contains('# GET-HARDWARE-BEGIN: 13QJ7D3')) -Message 'The aggregate should contain a record marker.'

$SecondInventory = $Inventory.PSObject.Copy()
$SecondInventory.ServiceTag = 'SECOND1'
$SecondBody = New-PhpRecordBody -Inventory $SecondInventory -Parts $Parts
$SecondBlock = New-CollectionBlock -ServiceTag 'SECOND1' -Body $SecondBody
$CollectionPhp = Update-CollectionPhp -ExistingContent $CollectionPhp -ServiceTag 'SECOND1' -Block $SecondBlock -Action Add
Assert-True -Condition ($CollectionPhp.IndexOf('13QJ7D3') -lt $CollectionPhp.IndexOf('SECOND1')) -Message 'New records should be appended in order.'

$ChangedBody = $Body.Replace("'room'=>'A216'", "'room'=>'A217'")
$ChangedBlock = New-CollectionBlock -ServiceTag '13QJ7D3' -Body $ChangedBody
$CollectionPhp = Update-CollectionPhp -ExistingContent $CollectionPhp -ServiceTag '13QJ7D3' -Block $ChangedBlock -Action Replace
Assert-True -Condition ($CollectionPhp.Contains("'room'=>'A217'")) -Message 'Replacing a record should update its content.'
Assert-True -Condition ($CollectionPhp.IndexOf('13QJ7D3') -lt $CollectionPhp.IndexOf('SECOND1')) -Message 'Replacing a record should preserve its order.'

$TestOutputRoot = Join-Path $PSScriptRoot ('.output-' + [guid]::NewGuid().ToString('N'))
$script:OutputRoot = $TestOutputRoot
$TestCollection = [pscustomobject]@{
    Name  = 'TEST_COLLECTION'
    Path  = Join-Path $TestOutputRoot 'TEST_COLLECTION'
    IsNew = $true
}
try {
    $Saved = Save-InventoryFiles `
        -Collection $TestCollection `
        -ServiceTag $Inventory.ServiceTag `
        -DeviceContent $DevicePhp `
        -RecordBody $Body `
        -Action Add

    Assert-True -Condition (Test-Path -LiteralPath $Saved.DevicePath -PathType Leaf) -Message 'The individual PHP file should be saved.'
    Assert-True -Condition (Test-Path -LiteralPath $Saved.CollectionPath -PathType Leaf) -Message 'The aggregate PHP file should be saved.'
    $DeviceBytes = [IO.File]::ReadAllBytes($Saved.DevicePath)
    $HasUtf8Bom = $DeviceBytes.Length -ge 3 -and $DeviceBytes[0] -eq 0xEF -and $DeviceBytes[1] -eq 0xBB -and $DeviceBytes[2] -eq 0xBF
    Assert-True -Condition (-not $HasUtf8Bom) -Message 'Generated PHP should be UTF-8 without BOM.'

    $TestModelDatabase = Join-Path $TestOutputRoot 'hardware-models.json'
    [IO.File]::Copy((Join-Path $ProjectRoot 'hardware-models.json'), $TestModelDatabase)
    $TestModelsBeforeMemoryUpdate = @(Import-ModelDatabase -Path $TestModelDatabase)
    $TestModelBeforeMemoryUpdate = $TestModelsBeforeMemoryUpdate | Where-Object model -EQ 'Latitude 7420' | Select-Object -First 1
    $script:MockReadHostQueue.Enqueue('1')
    $ResolvedMemorySpec = Resolve-MemorySpec `
        -ModelEntry $TestModelBeforeMemoryUpdate `
        -MemoryInventory $SlotMemory `
        -DatabasePath $TestModelDatabase
    Assert-True -Condition ($ResolvedMemorySpec -eq 'DDR4 3200MHz x4, max128GB') -Message 'The detected memorySpec should be selected for the current PHP record.'
    $UpdatedModels = @(Import-ModelDatabase -Path $TestModelDatabase)
    $UpdatedModel = $UpdatedModels | Where-Object model -EQ 'Latitude 7420' | Select-Object -First 1
    Assert-True -Condition ($UpdatedModel.memorySpec -eq 'DDR4 3200MHz x4, max128GB') -Message 'Only the selected model memorySpec should be updated in JSON.'
    Assert-True -Condition ($UpdatedModels.Count -eq $Models.Count) -Message 'Updating memorySpec should preserve every model in JSON.'

    $ExistingTestCollection = [pscustomobject]@{
        Name  = $TestCollection.Name
        Path  = $TestCollection.Path
        IsNew = $false
    }
    $BoughtFromCollection = Get-CollectionBoughtDate -Collection $ExistingTestCollection
    Assert-True -Condition ($BoughtFromCollection -eq '2025-05-28') -Message 'The bought date should be reused from an existing collection.'

    $ReplacementDevicePhp = New-DevicePhp -Body $ChangedBody
    $SavedReplacement = Save-InventoryFiles `
        -Collection $ExistingTestCollection `
        -ServiceTag $Inventory.ServiceTag `
        -DeviceContent $ReplacementDevicePhp `
        -RecordBody $ChangedBody `
        -Action Replace
    $SavedAggregate = [IO.File]::ReadAllText($SavedReplacement.CollectionPath)
    Assert-True -Condition ($SavedAggregate.Contains("'room'=>'A217'")) -Message 'A saved replacement should update the aggregate file.'
}
finally {
    if (Test-Path -LiteralPath $TestOutputRoot -PathType Container) {
        Remove-Item -LiteralPath $TestOutputRoot -Recurse -Force
    }
}

Write-Host 'All GetHardware tests passed.' -ForegroundColor Green
