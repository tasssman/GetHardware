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

$script:FailedCimClass = $null

function Get-PnpDevice {
    param([switch]$PresentOnly, $ErrorAction)
    return @()
}
function Get-PnpDeviceProperty {
    param([string]$InstanceId, [string]$KeyName, $ErrorAction)
    return [pscustomobject]@{ Data = @() }
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
            return [pscustomobject]@{ AdapterRAM = 1GB; Caption = 'Test graphics' }
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

$DetectedMockParts = @(Get-HardwareParts -ComputerModel 'Latitude 7420')
Assert-True -Condition ($DetectedMockParts.Count -eq 7) -Message 'The mocked hardware scan should return all seven component categories.'
Assert-True -Condition (($DetectedMockParts | Where-Object Pt -EQ 'Matrix').Desc -eq '14" 1920x1080') -Message 'The mocked scan should include the EDID-based matrix description.'
Assert-True -Condition (@($DetectedMockParts | Where-Object Pt -EQ 'RAM').Count -eq 1) -Message 'The mocked scan should include RAM.'
Assert-True -Condition (@($DetectedMockParts | Where-Object Pt -EQ 'Hard Disk').Count -eq 1) -Message 'The mocked scan should include a disk.'

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
