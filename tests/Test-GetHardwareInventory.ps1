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

$script:FailedCimClass = $null

function Get-PnpDevice { return @() }
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
        'Win32_Processor' {
            return [pscustomobject]@{
                Name          = 'Test CPU'
                NumberOfCores = 4
                MaxClockSpeed = 3000
            }
        }
        'WmiMonitorBasicDisplayParams' { return @() }
        'WmiMonitorID' { return @() }
        'Win32_PhysicalMemory' {
            return [pscustomobject]@{
                Capacity             = 16GB
                ConfiguredClockSpeed = 3200
                Speed                = 3200
                SMBIOSMemoryType     = 26
                DeviceLocator        = 'DIMM A'
                BankLabel            = 'BANK 0'
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

$script:FailedCimClass = 'Win32_BIOS'
$SystemWithoutBios = Get-SystemOverview
Assert-True -Condition ($SystemWithoutBios.ServiceTag -eq '') -Message 'A BIOS failure should produce an empty Service Tag for manual fallback.'
Assert-True -Condition ($SystemWithoutBios.Model -eq 'Latitude 7420') -Message 'A BIOS failure should not discard computer-system data.'
Assert-True -Condition ($SystemWithoutBios.Processor -eq 'Test CPU') -Message 'A BIOS failure should not discard processor data.'
$script:FailedCimClass = $null

$DetectedMockParts = @(Get-HardwareParts -ComputerModel 'Latitude 7420')
Assert-True -Condition ($DetectedMockParts.Count -eq 6) -Message 'The mocked hardware scan should return all six component categories.'
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
    MaxClockSpeed = 1804
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
