#requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ModelDatabasePath = Join-Path $PSScriptRoot 'hardware-models.json'
$OutputRoot = Join-Path $PSScriptRoot 'output'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Section {
    param([Parameter(Mandatory)][string]$Title)

    Write-Host ''
    Write-Host "=== $Title ===" -ForegroundColor Cyan
}

function Read-MenuChoice {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][int]$Minimum,
        [Parameter(Mandatory)][int]$Maximum
    )

    while ($true) {
        $Text = (Read-Host $Prompt).Trim()
        $Number = 0
        if ([int]::TryParse($Text, [ref]$Number) -and $Number -ge $Minimum -and $Number -le $Maximum) {
            return $Number
        }

        Write-Warning "Wpisz liczbę od $Minimum do $Maximum."
    }
}

function Read-TextValue {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [AllowNull()]$Default,
        [switch]$AllowEmpty
    )

    while ($true) {
        $DisplayPrompt = $Prompt
        if ($null -ne $Default) {
            $DisplayPrompt += " [$Default]"
        }

        $Value = (Read-Host $DisplayPrompt).Trim()
        if ([string]::IsNullOrWhiteSpace($Value) -and $null -ne $Default) {
            return [string]$Default
        }
        if ($AllowEmpty -or -not [string]::IsNullOrWhiteSpace($Value)) {
            return $Value
        }

        Write-Warning 'Wartość nie może być pusta.'
    }
}

function Test-IsoDate {
    param([Parameter(Mandatory)][string]$Value)

    $Parsed = [datetime]::MinValue
    return [datetime]::TryParseExact(
        $Value,
        'yyyy-MM-dd',
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::None,
        [ref]$Parsed
    )
}

function Read-IsoDate {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [AllowNull()]$Default
    )

    while ($true) {
        $Value = Read-TextValue -Prompt "$Prompt (rok-miesiąc-dzień)" -Default $Default
        if (Test-IsoDate -Value $Value) {
            return $Value
        }

        Write-Warning 'Podaj prawidłową datę w formacie YYYY-MM-DD, np. 2025-05-28.'
    }
}

function Read-Warranty {
    param([AllowNull()]$Default)

    while ($true) {
        $Value = Read-TextValue -Prompt 'Gwarancja (YYYY-MM-DD+liczba lat)' -Default $Default
        $Match = [regex]::Match($Value, '^(?<date>\d{4}-\d{2}-\d{2})\+(?<years>\d+)$')
        if ($Match.Success -and (Test-IsoDate -Value $Match.Groups['date'].Value)) {
            $Years = 0
            if ([int]::TryParse($Match.Groups['years'].Value, [ref]$Years) -and $Years -gt 0) {
                return $Value
            }
        }

        Write-Warning 'Podaj gwarancję w formacie YYYY-MM-DD+N, np. 2021-05-20+3.'
    }
}

function Read-Price {
    param([AllowNull()]$Default)

    while ($true) {
        $Value = Read-TextValue -Prompt 'Cena netto w PLN (z przecinkiem, bez symbolu waluty)' -Default $Default
        if ($Value -match '^\d+,\d{2}$') {
            return $Value
        }

        Write-Warning 'Podaj cenę z dwiema cyframi po przecinku, np. 1414,08.'
    }
}

function Read-LicenseLabel {
    param([AllowNull()][string]$Current)

    Write-Host '[1] W10P'
    Write-Host '[2] W11P'
    if (-not [string]::IsNullOrWhiteSpace($Current)) {
        Write-Host "Aktualna wartość: $Current" -ForegroundColor DarkGray
    }
    $Choice = Read-MenuChoice -Prompt 'Wybierz etykietę systemu [1/2]' -Minimum 1 -Maximum 2
    if ($Choice -eq 1) { return 'W10P' }
    return 'W11P'
}

function Read-ManualData {
    param([AllowNull()][psobject]$Current)

    $WarrantyDefault = $null
    $PriceDefault = $null
    $RoomDefault = 'A216'
    $NoteDefault = 'SCC:;REFURBISHED;'
    $CurrentLabel = $null
    if ($null -ne $Current) {
        $WarrantyDefault = [string]$Current.Warranty
        $PriceDefault = [string]$Current.Price
        $RoomDefault = [string]$Current.Room
        $NoteDefault = [string]$Current.Note
        $CurrentLabel = [string]$Current.Label
    }

    Write-Section -Title 'Dane uzupełniane ręcznie'
    $Warranty = Read-Warranty -Default $WarrantyDefault
    $Price = Read-Price -Default $PriceDefault
    $Label = Read-LicenseLabel -Current $CurrentLabel
    $Room = Read-TextValue -Prompt 'Pomieszczenie' -Default $RoomDefault
    $Note = Read-TextValue -Prompt 'Notatka (uzupełnij numer po SCC:)' -Default $NoteDefault

    return [pscustomobject]@{
        Warranty = $Warranty
        Price    = $Price
        Label    = $Label
        Room     = $Room
        Note     = $Note
    }
}

function Import-ModelDatabase {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Nie znaleziono bazy modeli: $Path"
    }

    try {
        # Windows PowerShell 5.1 zwraca główną tablicę JSON jako pojedynczy
        # obiekt tablicowy, dlatego jawnie rozwijamy jej elementy w potoku.
        $ParsedModels = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        $Models = @($ParsedModels | ForEach-Object { $_ })
    }
    catch {
        throw "Baza modeli nie jest poprawnym plikiem JSON: $($_.Exception.Message)"
    }

    if ($Models.Count -eq 0) {
        throw 'Baza modeli jest pusta.'
    }

    $RequiredProperties = @('model', 'baseboardFallback', 'memorySpec', 'powerMaxW', 'powerW', 'other', 'deviceType')
    foreach ($Entry in $Models) {
        foreach ($PropertyName in $RequiredProperties) {
            if ($PropertyName -notin $Entry.PSObject.Properties.Name) {
                throw "Wpis modelu nie zawiera pola '$PropertyName'."
            }
        }

        if ([string]::IsNullOrWhiteSpace([string]$Entry.model)) {
            throw 'Baza modeli zawiera wpis z pustą nazwą modelu.'
        }
        if ([string]::IsNullOrWhiteSpace([string]$Entry.baseboardFallback)) {
            throw "Model '$($Entry.model)' ma puste pole baseboardFallback."
        }

        $PowerMax = 0
        $Power = 0
        if (-not [int]::TryParse([string]$Entry.powerMaxW, [ref]$PowerMax) -or $PowerMax -lt 0) {
            throw "Model '$($Entry.model)' ma nieprawidłowe powerMaxW."
        }
        if (-not [int]::TryParse([string]$Entry.powerW, [ref]$Power) -or $Power -lt 0) {
            throw "Model '$($Entry.model)' ma nieprawidłowe powerW."
        }
    }

    $Duplicates = @(
        $Models |
            Group-Object { ([string]$_.model).Trim().ToUpperInvariant() } |
            Where-Object Count -gt 1
    )
    if ($Duplicates.Count -gt 0) {
        throw "Baza modeli zawiera zduplikowaną nazwę: $($Duplicates[0].Group[0].model)"
    }

    return $Models
}

function Wait-ForKnownModel {
    param(
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$DatabasePath
    )

    while ($true) {
        try {
            $Models = Import-ModelDatabase -Path $DatabasePath
            $Matches = @($Models | Where-Object { ([string]$_.model).Trim() -ieq $Model.Trim() })
            if ($Matches.Count -eq 1) {
                return $Matches[0]
            }

            Write-Warning "Modelu '$Model' nie ma w bazie. Dopisz go ręcznie do: $DatabasePath"
        }
        catch {
            Write-Warning $_.Exception.Message
        }

        $Answer = (Read-Host 'Po zapisaniu bazy naciśnij Enter, aby wczytać ją ponownie, albo wpisz Q, aby anulować').Trim()
        if ($Answer -ieq 'Q') {
            throw [OperationCanceledException]::new('Anulowano oczekiwanie na model.')
        }
    }
}

function Test-ServiceTag {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $Normalized = $Value.Trim()
    if ($Normalized -match '^(To be filled by O\.E\.M\.|Default string|System Serial Number|Unknown|None)$') {
        return $false
    }
    if ($Normalized.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) { return $false }
    return $Normalized -match '^[A-Za-z0-9._-]+$'
}

function Resolve-ServiceTag {
    param([AllowNull()][string]$DetectedValue)

    if (Test-ServiceTag -Value $DetectedValue) {
        $Tag = $DetectedValue.Trim().ToUpperInvariant()
        Write-Host "Wykryty Service Tag: $Tag" -ForegroundColor Green
        return $Tag
    }

    Write-Warning "Nie udało się wiarygodnie odczytać Service Tagu z BIOS-u. Odczytana wartość: '$DetectedValue'"
    while ($true) {
        $Tag = (Read-Host 'Wpisz Service Tag/numer seryjny').Trim().ToUpperInvariant()
        if (Test-ServiceTag -Value $Tag) {
            return $Tag
        }
        Write-Warning 'Identyfikator może zawierać wyłącznie litery, cyfry, kropkę, podkreślenie i myślnik.'
    }
}

function Get-ProcessorClockSpeedMhz {
    param([Parameter(Mandatory)][object[]]$Processors)

    $SpeedsFromName = foreach ($Processor in $Processors) {
        $Name = ([string]$Processor.Name).Trim()
        $Match = [regex]::Match(
            $Name,
            '@\s*(?<value>\d+(?:[\.,]\d+)?)\s*(?<unit>GHz|MHz)\b',
            [Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        if (-not $Match.Success) { continue }

        $NumericValue = 0.0
        $NormalizedValue = $Match.Groups['value'].Value.Replace(',', '.')
        if (-not [double]::TryParse(
            $NormalizedValue,
            [Globalization.NumberStyles]::AllowDecimalPoint,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$NumericValue
        )) {
            continue
        }

        if ($Match.Groups['unit'].Value -ieq 'GHz') {
            $NumericValue *= 1000
        }
        [int][math]::Round($NumericValue, 0, [MidpointRounding]::AwayFromZero)
    }

    if (@($SpeedsFromName).Count -gt 0) {
        return [int](($SpeedsFromName | Measure-Object -Maximum).Maximum)
    }

    $FallbackSpeed = [int](($Processors | Measure-Object -Property MaxClockSpeed -Maximum).Maximum)
    if ($FallbackSpeed -le 0) {
        throw 'Nie udało się ustalić taktowania procesora ani z jego nazwy, ani z MaxClockSpeed.'
    }
    return $FallbackSpeed
}

function Get-SystemOverview {
    Write-Section -Title 'Odczyt danych komputera'

    # Każde źródło CIM jest odczytywane niezależnie. Dzięki temu niedostępny
    # BIOS nie blokuje danych systemu i procesora, a pusty Service Tag uruchamia
    # później uzgodniony mechanizm ręcznego wpisania identyfikatora.
    $ComputerSystem = $null
    try {
        $ComputerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop |
            Select-Object -First 1
    }
    catch {
        Write-Warning "Nie udało się odczytać danych systemu z Win32_ComputerSystem: $($_.Exception.Message)"
    }

    $Bios = $null
    try {
        $Bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop |
            Select-Object -First 1
    }
    catch {
        Write-Warning "Nie udało się odczytać danych BIOS-u z Win32_BIOS: $($_.Exception.Message)"
    }

    $BaseBoard = $null
    try {
        $BaseBoard = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction Stop |
            Select-Object -First 1
    }
    catch {
        Write-Warning "Nie udało się odczytać płyty głównej z Win32_BaseBoard: $($_.Exception.Message)"
    }

    $Processors = @()
    try {
        $Processors = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
    }
    catch {
        Write-Warning "Nie udało się odczytać procesora z Win32_Processor: $($_.Exception.Message)"
    }

    if ($null -eq $ComputerSystem -or [string]::IsNullOrWhiteSpace([string]$ComputerSystem.Model)) {
        throw 'Nie udało się odczytać modelu komputera z Win32_ComputerSystem. Model jest wymagany do wyszukania urządzenia w bazie.'
    }
    if ($Processors.Count -eq 0) {
        throw 'Nie udało się odczytać procesora z Win32_Processor. Dane procesora są wymagane do utworzenia wpisu.'
    }

    $CoreCount = [int](($Processors | Measure-Object -Property NumberOfCores -Sum).Sum)
    $ClockSpeedMhz = Get-ProcessorClockSpeedMhz -Processors $Processors
    $ProcessorNames = @($Processors | ForEach-Object { ([string]$_.Name).Trim() } | Select-Object -Unique)

    $ServiceTag = ''
    if ($null -ne $Bios) {
        $ServiceTag = ([string]$Bios.SerialNumber).Trim()
    }

    return [pscustomobject]@{
        ServiceTag     = $ServiceTag
        Model          = ([string]$ComputerSystem.Model).Trim()
        Manufacturer   = ([string]$ComputerSystem.Manufacturer).Trim()
        Processor      = ($ProcessorNames -join ' / ')
        CoreCount      = $CoreCount
        ClockSpeedMhz  = $ClockSpeedMhz
        BaseBoardManufacturer = if ($null -ne $BaseBoard) { ([string]$BaseBoard.Manufacturer).Trim() } else { '' }
        BaseBoardProduct      = if ($null -ne $BaseBoard) { ([string]$BaseBoard.Product).Trim() } else { '' }
        BaseBoardVersion      = if ($null -ne $BaseBoard) { ([string]$BaseBoard.Version).Trim() } else { '' }
    }
}

function Test-BaseBoardProduct {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return $Value.Trim() -notmatch '^(To be filled by O\.E\.M\.|Default string|Base Board|System Product Name|Unknown|None|N/A)$'
}

function Join-MainboardDescription {
    param(
        [Parameter(Mandatory)][string]$BaseBoardDescription,
        [AllowEmptyString()][string]$MemorySpec = ''
    )

    $Description = $BaseBoardDescription.Trim()
    $NormalizedMemorySpec = $MemorySpec.Trim().Trim('(', ')').Trim()
    if (-not [string]::IsNullOrWhiteSpace($NormalizedMemorySpec)) {
        $Description += " ($NormalizedMemorySpec)"
    }
    return $Description
}

function Resolve-MainboardDescription {
    param(
        [Parameter(Mandatory)][psobject]$ModelEntry,
        [Parameter(Mandatory)][AllowEmptyString()][string]$MemorySpec,
        [AllowNull()][string]$Manufacturer,
        [AllowNull()][string]$Product,
        [AllowNull()][string]$Version
    )

    if (Test-BaseBoardProduct -Value $Product) {
        $Segments = New-Object System.Collections.Generic.List[string]
        foreach ($Value in @($Manufacturer, $Product, $Version)) {
            $Normalized = ([string]$Value).Trim()
            if ((Test-BaseBoardProduct -Value $Normalized) -and $Normalized -notin $Segments) {
                $Segments.Add($Normalized)
            }
        }
        $BaseBoardDescription = $Segments -join ' '
    }
    else {
        Write-Warning 'Nie udało się wykryć modelu płyty głównej z Win32_BaseBoard.'
        $BaseBoardDescription = Read-TextValue `
            -Prompt 'Opis płyty głównej — Enter zatwierdza wartość z bazy, możesz też wpisać własną' `
            -Default ([string]$ModelEntry.baseboardFallback)
    }

    return Join-MainboardDescription `
        -BaseBoardDescription $BaseBoardDescription `
        -MemorySpec $MemorySpec
}

function Convert-EdidText {
    param([AllowNull()]$Values)

    if ($null -eq $Values) { return '' }
    return (-join @($Values | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })).Trim()
}

function New-HardwarePart {
    param(
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)][string]$Description,
        [AllowEmptyString()][string]$Connection = '',
        [AllowEmptyString()][string]$SerialNumber = ''
    )

    return [pscustomobject]@{
        Pt   = $Type.Trim()
        Desc = $Description.Trim()
        Conn = $Connection.Trim()
        Sn   = $SerialNumber.Trim()
    }
}

function Get-MemoryTypeName {
    param([int]$SmbiosMemoryType)

    switch ($SmbiosMemoryType) {
        20 { return 'DDR' }
        21 { return 'DDR2' }
        24 { return 'DDR3' }
        25 { return 'FB-DIMM' }
        26 { return 'DDR4' }
        27 { return 'LPDDR' }
        28 { return 'LPDDR2' }
        29 { return 'LPDDR3' }
        30 { return 'LPDDR4' }
        32 { return 'HBM' }
        33 { return 'HBM2' }
        34 { return 'DDR5' }
        35 { return 'LPDDR5' }
        36 { return 'HBM3' }
        default { return '' }
    }
}

function Test-MemorySerialNumber {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $Normalized = $Value.Trim()
    return $Normalized -notmatch '^(0+|F+|Unknown|None|N/A|Default string|Not Specified)$'
}

function Get-MemoryPlacement {
    param([Parameter(Mandatory)][psobject]$Memory)

    $Locator = "$($Memory.DeviceLocator) $($Memory.BankLabel)".Trim()
    if ($Locator -match '(?i)motherboard|system\s*board|on\s*board|onboard|solder') {
        return 'soldered'
    }
    if ([int]$Memory.FormFactor -in @(8, 12) -or $Locator -match '(?i)\bSO-?DIMM\b|\bDIMM\b|\bslot\b') {
        return 'slot'
    }
    return 'unknown'
}

function ConvertTo-MemoryInventory {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$MemoryDevices,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$MemoryArrays
    )

    $NormalizedDevices = New-Object System.Collections.Generic.List[object]
    foreach ($Memory in $MemoryDevices) {
        try {
            $CapacityGb = [math]::Round([double]$Memory.Capacity / 1GB, 2)
            $RatedSpeed = if ([int]$Memory.Speed -gt 0) { [int]$Memory.Speed } else { [int]$Memory.ConfiguredClockSpeed }
            $MemoryType = Get-MemoryTypeName -SmbiosMemoryType ([int]$Memory.SMBIOSMemoryType)
            $Placement = Get-MemoryPlacement -Memory $Memory
            $SerialNumber = if (Test-MemorySerialNumber -Value ([string]$Memory.SerialNumber)) {
                ([string]$Memory.SerialNumber).Trim()
            }
            else {
                ''
            }

            $NormalizedDevices.Add([pscustomobject]@{
                CapacityGb  = $CapacityGb
                SpeedMhz    = $RatedSpeed
                MemoryType  = $MemoryType
                Placement   = $Placement
                SerialNumber = $SerialNumber
            })
        }
        catch {
            $LocatorProperty = $Memory.PSObject.Properties['DeviceLocator']
            $BankProperty = $Memory.PSObject.Properties['BankLabel']
            $LocatorValue = if ($null -ne $LocatorProperty) { [string]$LocatorProperty.Value } else { '' }
            $BankValue = if ($null -ne $BankProperty) { [string]$BankProperty.Value } else { '' }
            $MemoryIdentifier = "$LocatorValue $BankValue".Trim()
            if ([string]::IsNullOrWhiteSpace($MemoryIdentifier)) { $MemoryIdentifier = 'bez identyfikatora' }
            Write-Warning "Pominięto nieprawidłowy rekord pamięci '$MemoryIdentifier': $($_.Exception.Message)"
        }
    }

    $Parts = New-Object System.Collections.Generic.List[object]
    $SolderedDevices = @($NormalizedDevices | Where-Object Placement -EQ 'soldered')
    if ($SolderedDevices.Count -gt 0) {
        foreach ($Group in @($SolderedDevices | Group-Object MemoryType, SpeedMhz)) {
            $CapacityGb = [double](($Group.Group | Measure-Object -Property CapacityGb -Sum).Sum)
            $First = $Group.Group | Select-Object -First 1
            $Description = "$($CapacityGb.ToString('0.##', [Globalization.CultureInfo]::InvariantCulture))GB"
            if ($First.SpeedMhz -gt 0) { $Description += " $($First.SpeedMhz)MHz" }
            if (-not [string]::IsNullOrWhiteSpace($First.MemoryType)) { $Description += " $($First.MemoryType)" }
            $Parts.Add((New-HardwarePart -Type 'RAM' -Description $Description -Connection 'soldered'))
        }
    }

    foreach ($Memory in @($NormalizedDevices | Where-Object Placement -NE 'soldered')) {
        $Description = "$($Memory.CapacityGb.ToString('0.##', [Globalization.CultureInfo]::InvariantCulture))GB"
        if ($Memory.SpeedMhz -gt 0) { $Description += " $($Memory.SpeedMhz)MHz" }
        if (-not [string]::IsNullOrWhiteSpace($Memory.MemoryType)) { $Description += " $($Memory.MemoryType)" }
        $Parts.Add((New-HardwarePart -Type 'RAM' -Description $Description -Connection 'on board' -SerialNumber $Memory.SerialNumber))
    }

    $SystemArrays = @($MemoryArrays | Where-Object { [int]$_.Use -eq 3 -or [int]$_.Location -eq 3 })
    if ($SystemArrays.Count -eq 0) { $SystemArrays = @($MemoryArrays) }
    $MaximumCapacityKb = 0.0
    $MemoryDeviceCount = 0
    foreach ($Array in $SystemArrays) {
        $CapacityKb = if ([double]$Array.MaxCapacityEx -gt 0) { [double]$Array.MaxCapacityEx } else { [double]$Array.MaxCapacity }
        $MaximumCapacityKb += $CapacityKb
        $MemoryDeviceCount += [int]$Array.MemoryDevices
    }
    $MaximumCapacityGb = if ($MaximumCapacityKb -gt 0) { [math]::Round($MaximumCapacityKb / 1MB, 2) } else { 0 }

    $Types = @($NormalizedDevices.MemoryType | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    $Speeds = @($NormalizedDevices.SpeedMhz | Where-Object { $_ -gt 0 } | Select-Object -Unique)
    $Placements = @($NormalizedDevices.Placement | Select-Object -Unique)
    $DetectedSpec = ''
    $SpecReliable = (
        $NormalizedDevices.Count -gt 0 -and
        $Types.Count -eq 1 -and
        $Speeds.Count -eq 1 -and
        $Placements.Count -eq 1 -and
        $Placements[0] -ne 'unknown' -and
        $MaximumCapacityGb -gt 0
    )
    if ($SpecReliable) {
        $MaxText = $MaximumCapacityGb.ToString('0.##', [Globalization.CultureInfo]::InvariantCulture)
        if ($Placements[0] -eq 'soldered') {
            $DetectedSpec = "$($Types[0]) $($Speeds[0])MHz soldered, max${MaxText}GB"
        }
        elseif ($MemoryDeviceCount -gt 0) {
            $DetectedSpec = "$($Types[0]) $($Speeds[0])MHz x$MemoryDeviceCount, max${MaxText}GB"
        }
        else {
            $SpecReliable = $false
        }
    }

    return [pscustomobject]@{
        Parts         = $Parts.ToArray()
        DetectedSpec  = $DetectedSpec
        SpecReliable  = $SpecReliable
    }
}

function Get-MemoryInventory {
    try {
        $MemoryDevices = @(Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction Stop)
    }
    catch {
        Write-Warning "Nie udało się odczytać pamięci RAM z Win32_PhysicalMemory: $($_.Exception.Message)"
        $MemoryDevices = @()
    }

    try {
        $MemoryArrays = @(Get-CimInstance -ClassName Win32_PhysicalMemoryArray -ErrorAction Stop)
    }
    catch {
        Write-Warning "Nie udało się odczytać możliwości pamięci z Win32_PhysicalMemoryArray: $($_.Exception.Message)"
        $MemoryArrays = @()
    }

    return ConvertTo-MemoryInventory -MemoryDevices $MemoryDevices -MemoryArrays $MemoryArrays
}

function Get-NormalizedMemorySpec {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return ([regex]::Replace($Value.Trim(), '\s+', ' ')).ToUpperInvariant()
}

function Set-ModelMemorySpec {
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][AllowEmptyString()][string]$MemorySpec
    )

    $Models = @(Import-ModelDatabase -Path $DatabasePath)
    $Matches = @($Models | Where-Object { ([string]$_.model).Trim() -ieq $Model.Trim() })
    if ($Matches.Count -ne 1) {
        throw "Nie można zaktualizować memorySpec: model '$Model' nie występuje w bazie dokładnie jeden raz."
    }
    $Matches[0].memorySpec = $MemorySpec.Trim()

    $Json = ConvertTo-Json -InputObject $Models -Depth 6
    $TemporaryPath = Join-Path `
        (Split-Path -Parent $DatabasePath) `
        ".$([IO.Path]::GetFileName($DatabasePath)).$([guid]::NewGuid().ToString('N')).tmp"
    $BackupPath = "$TemporaryPath.bak"
    try {
        Write-Utf8NoBomFile -Path $TemporaryPath -Content ($Json + [Environment]::NewLine)
        $null = Import-ModelDatabase -Path $TemporaryPath
        [IO.File]::Replace($TemporaryPath, $DatabasePath, $BackupPath)
    }
    finally {
        foreach ($CleanupPath in @($TemporaryPath, $BackupPath)) {
            if (Test-Path -LiteralPath $CleanupPath) {
                Remove-Item -LiteralPath $CleanupPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
    Write-Host "Zaktualizowano memorySpec dla modelu '$Model' w hardware-models.json." -ForegroundColor Green
}

function Resolve-MemorySpec {
    param(
        [Parameter(Mandatory)][psobject]$ModelEntry,
        [Parameter(Mandatory)][psobject]$MemoryInventory,
        [Parameter(Mandatory)][string]$DatabasePath
    )

    $DatabaseSpec = ([string]$ModelEntry.memorySpec).Trim()
    $DetectedSpec = ([string]$MemoryInventory.DetectedSpec).Trim()
    $DetectedReliable = [bool]$MemoryInventory.SpecReliable -and -not [string]::IsNullOrWhiteSpace($DetectedSpec)

    if ($DetectedReliable -and
        (Get-NormalizedMemorySpec -Value $DetectedSpec) -eq (Get-NormalizedMemorySpec -Value $DatabaseSpec)) {
        return $DetectedSpec
    }

    Write-Section -Title 'Konfiguracja pamięci w płycie głównej'
    if ($DetectedReliable) {
        Write-Host "Wykryta konfiguracja: $DetectedSpec" -ForegroundColor Green
        Write-Host "Wartość w JSON:       $DatabaseSpec"
        Write-Host '[1] Użyj wykrytej wartości i zapisz ją w JSON'
        Write-Host '[2] Użyj wykrytej wartości tylko dla tego komputera'
        Write-Host '[3] Użyj wartości zapisanej w JSON'
        Write-Host '[4] Wpisz własną wartość'
        $Choice = Read-MenuChoice -Prompt 'Wybierz operację [1-4]' -Minimum 1 -Maximum 4
        switch ($Choice) {
            1 {
                Set-ModelMemorySpec -DatabasePath $DatabasePath -Model ([string]$ModelEntry.model) -MemorySpec $DetectedSpec
                $ModelEntry.memorySpec = $DetectedSpec
                return $DetectedSpec
            }
            2 { return $DetectedSpec }
            3 { return $DatabaseSpec }
            4 {
                $CustomSpec = Read-TextValue -Prompt 'Wpisz konfigurację pamięci dla pola mainb' -Default $DetectedSpec
            }
        }
    }
    else {
        Write-Warning 'Nie udało się jednoznacznie ustalić konfiguracji pamięci dla pola mainb.'
        $PromptDefault = if ([string]::IsNullOrWhiteSpace($DatabaseSpec)) { $null } else { $DatabaseSpec }
        $CustomSpec = Read-TextValue `
            -Prompt 'Wpisz konfigurację pamięci lub zatwierdź wartość z JSON' `
            -Default $PromptDefault
    }

    if ((Get-NormalizedMemorySpec -Value $CustomSpec) -ne (Get-NormalizedMemorySpec -Value $DatabaseSpec)) {
        Write-Host '[1] Zapisz tę wartość w JSON'
        Write-Host '[2] Użyj jej tylko dla tego komputera'
        $SaveChoice = Read-MenuChoice -Prompt 'Wybierz operację [1-2]' -Minimum 1 -Maximum 2
        if ($SaveChoice -eq 1) {
            Set-ModelMemorySpec -DatabasePath $DatabasePath -Model ([string]$ModelEntry.model) -MemorySpec $CustomSpec
            $ModelEntry.memorySpec = $CustomSpec
        }
    }
    return $CustomSpec
}

function Get-HardwareParts {
    param(
        [Parameter(Mandatory)][string]$ComputerModel,
        [AllowNull()][psobject]$MemoryInventory
    )

    $Parts = New-Object System.Collections.Generic.List[object]

    # EKRANY: EDID dostarcza nazwę, numer seryjny i fizyczny rozmiar. Powiązanie
    # rozdzielczości z EDID jest przybliżone, dlatego wynik zawsze podlega przeglądowi.
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $Resolutions = @(
            [System.Windows.Forms.Screen]::AllScreens |
                ForEach-Object { '{0}x{1}' -f $_.Bounds.Width, $_.Bounds.Height }
        )
        $TouchDetected = $false
        if (Get-Command -Name Get-PnpDevice -ErrorAction SilentlyContinue) {
            $TouchDetected = $null -ne (Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object FriendlyName -Match 'touch ?screen' | Select-Object -First 1)
        }

        $DisplayParameters = @{}
        foreach ($Parameter in @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBasicDisplayParams -ErrorAction Stop)) {
            $DisplayParameters[[string]$Parameter.InstanceName] = $Parameter
        }

        $MonitorIndex = 0
        foreach ($Monitor in @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop)) {
            $Name = Convert-EdidText -Values $Monitor.UserFriendlyName
            $Serial = Convert-EdidText -Values $Monitor.SerialNumberID
            $Resolution = if ($MonitorIndex -lt $Resolutions.Count) { $Resolutions[$MonitorIndex] } else { '' }
            $Parameter = $DisplayParameters[[string]$Monitor.InstanceName]
            $SizeText = ''
            if ($null -ne $Parameter -and $Parameter.MaxHorizontalImageSize -gt 0 -and $Parameter.MaxVerticalImageSize -gt 0) {
                $Diagonal = [math]::Sqrt(
                    [math]::Pow([double]$Parameter.MaxHorizontalImageSize, 2) +
                    [math]::Pow([double]$Parameter.MaxVerticalImageSize, 2)
                ) / 2.54
                $SizeText = ('{0:0.#}"' -f $Diagonal)
            }

            $IsInternal = [string]::IsNullOrWhiteSpace($Serial)
            $Type = if ($IsInternal) { 'Matrix' } else { 'Monitor' }
            $Connection = if ($IsInternal) { 'on board' } else { 'VGA,DVI,DP' }
            $DescriptionParts = @($SizeText, $Name, $Resolution) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            $Description = ($DescriptionParts -join ' ').Trim()
            if ($IsInternal -and $TouchDetected) { $Description += ' touch' }
            if ([string]::IsNullOrWhiteSpace($Description)) { $Description = 'QQ_POPRAW' }

            $Parts.Add((New-HardwarePart -Type $Type -Description $Description -Connection $Connection -SerialNumber $Serial))
            $MonitorIndex++
        }
    }
    catch {
        Write-Warning "Nie udało się odczytać ekranów: $($_.Exception.Message)"
    }

    # PAMIĘĆ RAM: pamięć lutowana jest grupowana, a wymienne moduły pozostają
    # osobnymi wpisami. Dla pamięci niewlutowanej importer oczekuje `on board`.
    if ($null -eq $MemoryInventory) {
        $MemoryInventory = Get-MemoryInventory
    }
    foreach ($MemoryPart in @($MemoryInventory.Parts)) {
        $Parts.Add($MemoryPart)
    }

    # DYSKI: pojemność jest liczona dziesiętnie, aby odpowiadała oznaczeniom
    # producentów (np. około 256 GB zamiast 238 GiB).
    try {
        foreach ($Disk in @(Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction Stop)) {
            $CapacityGb = [math]::Round([double]$Disk.Size / 1000000000)
            $Description = "$($CapacityGb)GB $(([string]$Disk.Model).Trim())".Trim()
            $Connection = if ([string]$Disk.PNPDeviceID -match 'NVME') { 'M.2' } elseif ($Disk.InterfaceType) { [string]$Disk.InterfaceType } else { '' }
            $Parts.Add((New-HardwarePart -Type 'Hard Disk' -Description $Description -Connection $Connection))
        }
    }
    catch {
        Write-Warning "Nie udało się odczytać dysków: $($_.Exception.Message)"
    }

    # SIEĆ: zachowujemy wszystkie fizyczne adaptery z adresem MAC, w tym
    # Bluetooth PAN i adaptery USB, zgodnie z formatem istniejącej bazy.
    try {
        $Adapters = @(
            Get-CimInstance -ClassName Win32_NetworkAdapter -ErrorAction Stop |
                Where-Object { $_.PhysicalAdapter -eq $true -and -not [string]::IsNullOrWhiteSpace([string]$_.MACAddress) }
        )
        foreach ($Adapter in $Adapters) {
            $Mac = ([string]$Adapter.MACAddress -replace '[:-]', '').ToUpperInvariant()
            $Parts.Add((New-HardwarePart -Type 'Network Card' -Description ([string]$Adapter.Description) -Connection 'on board' -SerialNumber $Mac))
        }
    }
    catch {
        Write-Warning "Nie udało się odczytać kart sieciowych: $($_.Exception.Message)"
    }

    # DŹWIĘK: WMI może zwrócić więcej niż jedno urządzenie audio; każde jest
    # pozostawione do zatwierdzenia przez użytkownika.
    try {
        foreach ($Sound in @(Get-CimInstance -ClassName Win32_SoundDevice -ErrorAction Stop)) {
            $Parts.Add((New-HardwarePart -Type 'Sound Card' -Description ([string]$Sound.Caption) -Connection 'on board'))
        }
    }
    catch {
        Write-Warning "Nie udało się odczytać kart dźwiękowych: $($_.Exception.Message)"
    }

    # GRAFIKA: AdapterRAM w WMI bywa niedokładne dla nowych kart; wartość jest
    # pokazywana użytkownikowi i może zostać poprawiona przed zapisem.
    try {
        foreach ($Graphics in @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop)) {
            $MemoryText = ''
            if ($null -ne $Graphics.AdapterRAM -and [double]$Graphics.AdapterRAM -gt 0) {
                $MemoryText = "$([math]::Round([double]$Graphics.AdapterRAM / 1MB))MB "
            }
            $Parts.Add((New-HardwarePart -Type 'Graphic Card' -Description "$MemoryText$($Graphics.Caption)" -Connection 'on board,HDMI'))
        }
    }
    catch {
        Write-Warning "Nie udało się odczytać kart graficznych: $($_.Exception.Message)"
    }

    # BATERIA: brak wpisów jest prawidłowy dla komputerów stacjonarnych.
    try {
        foreach ($Battery in @(Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop)) {
            $Description = if ($Battery.Name) { [string]$Battery.Name } else { [string]$Battery.Description }
            $Parts.Add((New-HardwarePart -Type 'Battery' -Description $Description -Connection ''))
        }
    }
    catch {
        Write-Warning "Nie udało się odczytać baterii: $($_.Exception.Message)"
    }

    if ($Parts.Count -eq 0) {
        throw 'Nie udało się wykryć żadnego podzespołu.'
    }

    # W Windows PowerShell 5.1 użycie @($Parts) dla List[object]
    # zawierającej PSCustomObject kończy się błędem "Argument types do not match".
    # ToArray() wykonuje jednoznaczną i zgodną konwersję.
    return $Parts.ToArray()
}

function Show-HardwareParts {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Parts,
        [Parameter(Mandatory)][string]$ServiceTag,
        [Parameter(Mandatory)][string]$ComputerModel,
        [Parameter(Mandatory)][string]$Processor,
        [Parameter(Mandatory)][int]$CoreCount,
        [Parameter(Mandatory)][int]$ClockSpeedMhz,
        [Parameter(Mandatory)][string]$Mainboard
    )

    Write-Section -Title 'Identyfikacja komputera'
    Write-Host "SN / Service Tag: $ServiceTag" -ForegroundColor Green
    Write-Host "Model:            $ComputerModel"

    Write-Section -Title 'Procesor'
    Write-Host "Model:               $Processor"
    Write-Host "Rdzenie fizyczne:     $CoreCount"
    Write-Host "Taktowanie (mhz):     $ClockSpeedMhz"

    Write-Section -Title 'Płyta główna'
    Write-Host $Mainboard

    Write-Section -Title 'Wykryte podzespoły'
    $Rows = for ($Index = 0; $Index -lt $Parts.Count; $Index++) {
        [pscustomobject]@{
            Nr   = $Index + 1
            Typ  = $Parts[$Index].Pt
            Opis = $Parts[$Index].Desc
            Polaczenie = $Parts[$Index].Conn
            SN   = $Parts[$Index].Sn
        }
    }
    Write-Host ($Rows | Format-Table -AutoSize | Out-String)
}

function Read-PartIndex {
    param(
        [Parameter(Mandatory)][object[]]$Parts,
        [Parameter(Mandatory)][string]$Prompt
    )

    return (Read-MenuChoice -Prompt $Prompt -Minimum 1 -Maximum $Parts.Count) - 1
}

function Read-HardwarePart {
    param([AllowNull()][psobject]$Current)

    $TypeDefault = $null
    $DescriptionDefault = $null
    $ConnectionDefault = ''
    $SerialDefault = ''
    if ($null -ne $Current) {
        $TypeDefault = [string]$Current.Pt
        $DescriptionDefault = [string]$Current.Desc
        $ConnectionDefault = [string]$Current.Conn
        $SerialDefault = [string]$Current.Sn
    }

    $Type = Read-TextValue -Prompt 'Typ podzespołu' -Default $TypeDefault
    $Description = Read-TextValue -Prompt 'Opis' -Default $DescriptionDefault
    $Connection = Read-TextValue -Prompt 'Połączenie' -Default $ConnectionDefault -AllowEmpty
    $Serial = Read-TextValue -Prompt 'SN/MAC (opcjonalnie)' -Default $SerialDefault -AllowEmpty
    return New-HardwarePart -Type $Type -Description $Description -Connection $Connection -SerialNumber $Serial
}

function Review-HardwareParts {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$InitialParts,
        [Parameter(Mandatory)][string]$ServiceTag,
        [Parameter(Mandatory)][string]$ComputerModel,
        [Parameter(Mandatory)][string]$Processor,
        [Parameter(Mandatory)][int]$CoreCount,
        [Parameter(Mandatory)][int]$ClockSpeedMhz,
        [Parameter(Mandatory)][string]$Mainboard
    )

    $Parts = @($InitialParts)
    while ($true) {
        Show-HardwareParts `
            -Parts $Parts `
            -ServiceTag $ServiceTag `
            -ComputerModel $ComputerModel `
            -Processor $Processor `
            -CoreCount $CoreCount `
            -ClockSpeedMhz $ClockSpeedMhz `
            -Mainboard $Mainboard
        Write-Host '[1] Zaakceptuj listę'
        Write-Host '[2] Edytuj wybrany element'
        Write-Host '[3] Dodaj element'
        Write-Host '[4] Usuń element'
        Write-Host '[5] Odczytaj sprzęt ponownie'
        Write-Host '[6] Anuluj'
        $Choice = Read-MenuChoice -Prompt 'Wybierz operację [1-6]' -Minimum 1 -Maximum 6

        switch ($Choice) {
            1 { return [pscustomobject]@{ Action = 'Accept'; Parts = @($Parts) } }
            2 {
                if ($Parts.Count -eq 0) { Write-Warning 'Lista jest pusta.'; continue }
                $Index = Read-PartIndex -Parts $Parts -Prompt 'Numer elementu do edycji'
                $Parts[$Index] = Read-HardwarePart -Current $Parts[$Index]
            }
            3 { $Parts += Read-HardwarePart -Current $null }
            4 {
                if ($Parts.Count -eq 0) { Write-Warning 'Lista jest pusta.'; continue }
                $Index = Read-PartIndex -Parts $Parts -Prompt 'Numer elementu do usunięcia'
                $RemainingParts = for ($CurrentIndex = 0; $CurrentIndex -lt $Parts.Count; $CurrentIndex++) {
                    if ($CurrentIndex -ne $Index) { $Parts[$CurrentIndex] }
                }
                $Parts = @($RemainingParts)
            }
            5 { return [pscustomobject]@{ Action = 'Refresh'; Parts = @($Parts) } }
            6 { return [pscustomobject]@{ Action = 'Cancel'; Parts = @($Parts) } }
        }
    }
}

function Read-NewCollectionName {
    param([Parameter(Mandatory)][string]$Root)

    $ReservedNames = @('CON', 'PRN', 'AUX', 'NUL', 'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9', 'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9')
    while ($true) {
        $Name = (Read-Host 'Podaj nazwę nowego spisu').Trim()
        $Invalid = (
            [string]::IsNullOrWhiteSpace($Name) -or
            $Name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
            $Name -in @('.', '..') -or
            $Name.ToUpperInvariant() -in $ReservedNames
        )
        if ($Invalid) {
            Write-Warning 'Nazwa spisu jest pusta, zarezerwowana albo zawiera niedozwolone znaki.'
            continue
        }

        $Path = Join-Path $Root $Name
        if (Test-Path -LiteralPath $Path) {
            Write-Warning 'Taki spis już istnieje. Wybierz go z listy.'
            continue
        }

        return [pscustomobject]@{ Name = $Name; Path = $Path; IsNew = $true }
    }
}

function Select-Collection {
    param([Parameter(Mandatory)][string]$Root)

    $Existing = @()
    if (Test-Path -LiteralPath $Root -PathType Container) {
        $Existing = @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction Stop | Sort-Object Name)
    }

    Write-Section -Title 'Wybór spisu'
    if ($Existing.Count -eq 0) {
        Write-Host 'Nie znaleziono istniejących spisów. Utwórz pierwszy spis.'
        return Read-NewCollectionName -Root $Root
    }

    for ($Index = 0; $Index -lt $Existing.Count; $Index++) {
        Write-Host ('[{0}] {1}' -f ($Index + 1), $Existing[$Index].Name)
    }
    $CreateNumber = $Existing.Count + 1
    Write-Host "[$CreateNumber] Utwórz nowy spis"
    $Choice = Read-MenuChoice -Prompt "Wybierz spis [1-$CreateNumber]" -Minimum 1 -Maximum $CreateNumber
    if ($Choice -eq $CreateNumber) {
        return Read-NewCollectionName -Root $Root
    }

    $Selected = $Existing[$Choice - 1]
    return [pscustomobject]@{ Name = $Selected.Name; Path = $Selected.FullName; IsNew = $false }
}

function Get-CollectionBoughtDate {
    param([Parameter(Mandatory)][psobject]$Collection)

    $CollectionFile = Join-Path $Collection.Path "$($Collection.Name).php"
    if ($Collection.IsNew -or -not (Test-Path -LiteralPath $CollectionFile -PathType Leaf)) {
        return Read-IsoDate -Prompt 'Data zakupu/przyjęcia wspólna dla spisu' -Default $null
    }

    $Content = Get-Content -LiteralPath $CollectionFile -Raw -Encoding UTF8
    $Dates = @(
        [regex]::Matches($Content, "(?m),'bought'=>'(?<date>\d{4}-\d{2}-\d{2})'") |
            ForEach-Object { $_.Groups['date'].Value } |
            Select-Object -Unique
    )
    if ($Dates.Count -eq 0) {
        throw "Nie znaleziono pola bought w istniejącym spisie: $CollectionFile"
    }
    if ($Dates.Count -gt 1) {
        throw "Istniejący spis zawiera różne wartości bought: $($Dates -join ', ')"
    }
    if (-not (Test-IsoDate -Value $Dates[0])) {
        throw "Istniejący spis zawiera nieprawidłową datę bought: $($Dates[0])"
    }

    Write-Host "Data bought odczytana ze spisu: $($Dates[0])" -ForegroundColor Green
    return $Dates[0]
}

function Get-ExistingDeviceAction {
    param(
        [Parameter(Mandatory)][psobject]$Collection,
        [Parameter(Mandatory)][string]$ServiceTag
    )

    $DevicePath = Join-Path $Collection.Path "$ServiceTag.php"
    $CollectionPath = Join-Path $Collection.Path "$($Collection.Name).php"
    $Exists = Test-Path -LiteralPath $DevicePath -PathType Leaf
    if (-not $Exists -and (Test-Path -LiteralPath $CollectionPath -PathType Leaf)) {
        $Content = Get-Content -LiteralPath $CollectionPath -Raw -Encoding UTF8
        $Exists = $Content -match "(?m)^# GET-HARDWARE-BEGIN: $([regex]::Escape($ServiceTag))$"
    }
    if (-not $Exists) { return 'Add' }

    Write-Warning "Urządzenie $ServiceTag już istnieje w spisie '$($Collection.Name)'."
    Write-Host '[1] Zastąp istniejący rekord'
    Write-Host '[2] Pomiń zapis'
    Write-Host '[3] Anuluj'
    $Choice = Read-MenuChoice -Prompt 'Wybierz operację [1-3]' -Minimum 1 -Maximum 3
    switch ($Choice) {
        1 { return 'Replace' }
        2 { return 'Skip' }
        3 { return 'Cancel' }
    }
}

function ConvertTo-PhpSingleQuotedValue {
    param([AllowNull()][AllowEmptyString()][string]$Value)

    if ($null -eq $Value) { return '' }
    $Result = $Value.Replace('\', '\\').Replace("'", "\'")
    $Result = $Result.Replace("`r", ' ').Replace("`n", ' ')
    return $Result
}

function New-PhpRecordBody {
    param(
        [Parameter(Mandatory)][psobject]$Inventory,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Parts
    )

    $Lines = New-Object System.Collections.Generic.List[string]
    $Lines.Add('unset($partsLapt);$partsLapt = array();')
    foreach ($Part in $Parts) {
        $Line = "`$partsLapt[]=array('pt'=>'$(ConvertTo-PhpSingleQuotedValue $Part.Pt)', 'desc'=>'$(ConvertTo-PhpSingleQuotedValue $Part.Desc)', 'conn'=>'$(ConvertTo-PhpSingleQuotedValue $Part.Conn)'"
        if (-not [string]::IsNullOrWhiteSpace([string]$Part.Sn)) {
            $Line += ", 'sn'=>'$(ConvertTo-PhpSingleQuotedValue $Part.Sn)'"
        }
        $Line += ');'
        $Lines.Add($Line)
    }

    $Lines.Add('')
    $Lines.Add('unset($C);$C=array(')
    $Lines.Add("'model'=>'$(ConvertTo-PhpSingleQuotedValue $Inventory.Model)'")
    $Lines.Add(",'bought'=>'$(ConvertTo-PhpSingleQuotedValue $Inventory.Bought)'")
    $Lines.Add(",'warr'=>'$(ConvertTo-PhpSingleQuotedValue $Inventory.Warranty)'")
    $Lines.Add(",'cenan'=>'$(ConvertTo-PhpSingleQuotedValue $Inventory.Price)'")
    $Lines.Add(",'label'=>'$(ConvertTo-PhpSingleQuotedValue $Inventory.Label)'")
    $Lines.Add(",'proc'=>'$(ConvertTo-PhpSingleQuotedValue $Inventory.Processor)'")
    $Lines.Add(",'xcCores'=>$($Inventory.CoreCount)")
    $Lines.Add(",'mhz'=>$($Inventory.ClockSpeedMhz)")
    $Lines.Add(",'mainb'=>'$(ConvertTo-PhpSingleQuotedValue $Inventory.Mainboard)'")
    $Lines.Add(",'powerx'=>'$($Inventory.PowerMaxW)'")
    $Lines.Add(",'power'=>'$($Inventory.PowerW)'")
    $Lines.Add(",'manuf'=>'$(ConvertTo-PhpSingleQuotedValue $Inventory.Manufacturer)'")
    $Lines.Add(",'room'=>'$(ConvertTo-PhpSingleQuotedValue $Inventory.Room)'")
    $Lines.Add(",'other'=>'$(ConvertTo-PhpSingleQuotedValue $Inventory.Other)'")
    $Lines.Add(",'note'=>'$(ConvertTo-PhpSingleQuotedValue $Inventory.Note)'")
    $Lines.Add(');')
    $Lines.Add('')

    $IdentifierSuffix = if ($Inventory.DeviceType -in @('laptop', 'tablet')) { '_laptop' } else { '' }
    $Identifier = ConvertTo-PhpSingleQuotedValue "$($Inventory.ServiceTag)$IdentifierSuffix"
    $Lines.Add("addComp('$Identifier',`$C,`$partsLapt);")
    $Lines.Add("#https://www.dell.com/support/home/en-us/product-support/servicetag/$($Inventory.ServiceTag)/overview")
    return ($Lines -join "`r`n")
}

function New-DevicePhp {
    param([Parameter(Mandatory)][string]$Body)

    return "<?php`r`n`r`n$Body`r`n`r`n?>`r`n"
}

function New-CollectionBlock {
    param(
        [Parameter(Mandatory)][string]$ServiceTag,
        [Parameter(Mandatory)][string]$Body
    )

    return "# GET-HARDWARE-BEGIN: $ServiceTag`r`n$Body`r`n# GET-HARDWARE-END: $ServiceTag"
}

function Update-CollectionPhp {
    param(
        [AllowNull()][string]$ExistingContent,
        [Parameter(Mandatory)][string]$ServiceTag,
        [Parameter(Mandatory)][string]$Block,
        [Parameter(Mandatory)][ValidateSet('Add', 'Replace')][string]$Action
    )

    if ([string]::IsNullOrWhiteSpace($ExistingContent)) {
        return "<?php`r`n`r`n$Block`r`n`r`n?>`r`n"
    }
    if ($ExistingContent -notmatch '^\s*<\?php' -or $ExistingContent -notmatch '\?>\s*$') {
        throw 'Istniejący plik zbiorczy nie ma oczekiwanych znaczników PHP.'
    }

    $EscapedTag = [regex]::Escape($ServiceTag)
    $Pattern = "(?ms)^# GET-HARDWARE-BEGIN: $EscapedTag\r?\n.*?^# GET-HARDWARE-END: $EscapedTag"
    $HasBlock = [regex]::IsMatch($ExistingContent, $Pattern)
    if ($Action -eq 'Replace') {
        if (-not $HasBlock) {
            throw "Nie można bezpiecznie zastąpić rekordu ${ServiceTag}: w pliku zbiorczym brakuje jego znaczników."
        }
        return [regex]::Replace($ExistingContent, $Pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($Match) $Block }, 1)
    }
    if ($HasBlock) {
        throw "Rekord $ServiceTag już istnieje w pliku zbiorczym."
    }

    $WithoutClosingTag = [regex]::Replace($ExistingContent, '\s*\?>\s*$', '')
    return "$($WithoutClosingTag.TrimEnd())`r`n`r`n$Block`r`n`r`n?>`r`n"
}

function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )

    [IO.File]::WriteAllText($Path, $Content, $script:Utf8NoBom)
}

function Save-InventoryFiles {
    param(
        [Parameter(Mandatory)][psobject]$Collection,
        [Parameter(Mandatory)][string]$ServiceTag,
        [Parameter(Mandatory)][string]$DeviceContent,
        [Parameter(Mandatory)][string]$RecordBody,
        [Parameter(Mandatory)][ValidateSet('Add', 'Replace')][string]$Action
    )

    if (-not (Test-Path -LiteralPath $OutputRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $OutputRoot -ErrorAction Stop | Out-Null
    }
    if (-not (Test-Path -LiteralPath $Collection.Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Collection.Path -ErrorAction Stop | Out-Null
    }

    $DevicePath = Join-Path $Collection.Path "$ServiceTag.php"
    $CollectionPath = Join-Path $Collection.Path "$($Collection.Name).php"
    $LockPath = Join-Path $Collection.Path '.gethardware.lock'
    $LockStream = $null
    $DeviceTemporaryPath = Join-Path $Collection.Path ".$ServiceTag.$([guid]::NewGuid().ToString('N')).tmp"
    $CollectionTemporaryPath = Join-Path $Collection.Path ".$($Collection.Name).$([guid]::NewGuid().ToString('N')).tmp"
    $OldDeviceExists = Test-Path -LiteralPath $DevicePath -PathType Leaf
    $OldCollectionExists = Test-Path -LiteralPath $CollectionPath -PathType Leaf
    $OldDeviceContent = if ($OldDeviceExists) { [IO.File]::ReadAllText($DevicePath) } else { $null }
    $OldCollectionContent = if ($OldCollectionExists) { [IO.File]::ReadAllText($CollectionPath) } else { $null }

    try {
        try {
            $LockStream = [IO.File]::Open($LockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        }
        catch {
            throw 'Wybrany spis jest obecnie zapisywany przez inny proces. Spróbuj ponownie później.'
        }

        # Odczyt następuje ponownie po uzyskaniu blokady, aby nie nadpisać cudzych zmian.
        $CurrentCollectionContent = if (Test-Path -LiteralPath $CollectionPath -PathType Leaf) { [IO.File]::ReadAllText($CollectionPath) } else { $null }
        $Block = New-CollectionBlock -ServiceTag $ServiceTag -Body $RecordBody
        $NewCollectionContent = Update-CollectionPhp -ExistingContent $CurrentCollectionContent -ServiceTag $ServiceTag -Block $Block -Action $Action

        Write-Utf8NoBomFile -Path $DeviceTemporaryPath -Content $DeviceContent
        Write-Utf8NoBomFile -Path $CollectionTemporaryPath -Content $NewCollectionContent

        Move-Item -LiteralPath $DeviceTemporaryPath -Destination $DevicePath -Force -ErrorAction Stop
        try {
            Move-Item -LiteralPath $CollectionTemporaryPath -Destination $CollectionPath -Force -ErrorAction Stop
        }
        catch {
            if ($OldDeviceExists) {
                Write-Utf8NoBomFile -Path $DevicePath -Content $OldDeviceContent
            }
            elseif (Test-Path -LiteralPath $DevicePath -PathType Leaf) {
                Remove-Item -LiteralPath $DevicePath -Force -ErrorAction SilentlyContinue
            }
            throw
        }
    }
    finally {
        if ($null -ne $LockStream) { $LockStream.Dispose() }
        foreach ($TemporaryPath in @($DeviceTemporaryPath, $CollectionTemporaryPath)) {
            if (Test-Path -LiteralPath $TemporaryPath -PathType Leaf) {
                Remove-Item -LiteralPath $TemporaryPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    return [pscustomobject]@{ DevicePath = $DevicePath; CollectionPath = $CollectionPath }
}

function Show-InventorySummary {
    param(
        [Parameter(Mandatory)][psobject]$Inventory,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Parts,
        [Parameter(Mandatory)][psobject]$Collection
    )

    Write-Section -Title 'Podsumowanie'
    Write-Host "Spis:          $($Collection.Name)"
    Write-Host "Service Tag:   $($Inventory.ServiceTag)"
    Write-Host "Model:         $($Inventory.Model)"
    Write-Host "Płyta główna:  $($Inventory.Mainboard)"
    Write-Host "Bought:        $($Inventory.Bought)"
    Write-Host "Gwarancja:     $($Inventory.Warranty)"
    Write-Host "Cena netto:    $($Inventory.Price) PLN"
    Write-Host "Etykieta:      $($Inventory.Label)"
    Write-Host "Pomieszczenie: $($Inventory.Room)"
    Write-Host "Notatka:       $($Inventory.Note)"
    Write-Host "Podzespoły:    $($Parts.Count)"
    Write-Host "Plik sprzętu:  $(Join-Path $Collection.Path "$($Inventory.ServiceTag).php")"
    Write-Host "Plik zbiorczy: $(Join-Path $Collection.Path "$($Collection.Name).php")"
}

function Invoke-HardwareInventory {
    $System = Get-SystemOverview
    if ([string]::IsNullOrWhiteSpace($System.Model)) {
        throw 'Nie udało się odczytać modelu komputera.'
    }

    $ServiceTag = Resolve-ServiceTag -DetectedValue $System.ServiceTag
    Write-Host "Wykryty model: $($System.Model)" -ForegroundColor Green
    $ModelEntry = Wait-ForKnownModel -Model $System.Model -DatabasePath $ModelDatabasePath
    $MemoryInventory = Get-MemoryInventory
    $MemorySpec = Resolve-MemorySpec `
        -ModelEntry $ModelEntry `
        -MemoryInventory $MemoryInventory `
        -DatabasePath $ModelDatabasePath
    $Mainboard = Resolve-MainboardDescription `
        -ModelEntry $ModelEntry `
        -MemorySpec $MemorySpec `
        -Manufacturer $System.BaseBoardManufacturer `
        -Product $System.BaseBoardProduct `
        -Version $System.BaseBoardVersion

    while ($true) {
        $Collection = Select-Collection -Root $OutputRoot
        if ($Collection.Name -ine $ServiceTag) { break }
        Write-Warning 'Nazwa spisu nie może być taka sama jak Service Tag, ponieważ oba pliki miałyby tę samą ścieżkę.'
    }
    $ExistingAction = Get-ExistingDeviceAction -Collection $Collection -ServiceTag $ServiceTag
    if ($ExistingAction -eq 'Skip') {
        Write-Host 'Pominięto zapis istniejącego urządzenia.' -ForegroundColor Yellow
        return
    }
    if ($ExistingAction -eq 'Cancel') {
        throw [OperationCanceledException]::new('Anulowano zapis istniejącego urządzenia.')
    }

    $Bought = Get-CollectionBoughtDate -Collection $Collection

    while ($true) {
        $DetectedParts = Get-HardwareParts -ComputerModel $System.Model -MemoryInventory $MemoryInventory
        $Review = Review-HardwareParts `
            -InitialParts $DetectedParts `
            -ServiceTag $ServiceTag `
            -ComputerModel $System.Model `
            -Processor $System.Processor `
            -CoreCount $System.CoreCount `
            -ClockSpeedMhz $System.ClockSpeedMhz `
            -Mainboard $Mainboard
        if ($Review.Action -eq 'Accept') {
            $Parts = @($Review.Parts)
            break
        }
        if ($Review.Action -eq 'Cancel') {
            throw [OperationCanceledException]::new('Anulowano przegląd podzespołów.')
        }
        Write-Host 'Ponawiam odczyt sprzętu...' -ForegroundColor Yellow
        $MemoryInventory = Get-MemoryInventory
        $MemorySpec = Resolve-MemorySpec `
            -ModelEntry $ModelEntry `
            -MemoryInventory $MemoryInventory `
            -DatabasePath $ModelDatabasePath
        $Mainboard = Resolve-MainboardDescription `
            -ModelEntry $ModelEntry `
            -MemorySpec $MemorySpec `
            -Manufacturer $System.BaseBoardManufacturer `
            -Product $System.BaseBoardProduct `
            -Version $System.BaseBoardVersion
    }

    $Manual = Read-ManualData -Current $null
    while ($true) {
        $Inventory = [pscustomobject]@{
            ServiceTag    = $ServiceTag
            Model         = $System.Model
            Bought        = $Bought
            Warranty      = $Manual.Warranty
            Price         = $Manual.Price
            Label         = $Manual.Label
            Processor     = $System.Processor
            CoreCount     = $System.CoreCount
            ClockSpeedMhz = $System.ClockSpeedMhz
            Mainboard     = $Mainboard
            PowerMaxW     = [int]$ModelEntry.powerMaxW
            PowerW        = [int]$ModelEntry.powerW
            Manufacturer  = $System.Manufacturer
            Room          = $Manual.Room
            Other         = [string]$ModelEntry.other
            Note          = $Manual.Note
            DeviceType    = [string]$ModelEntry.deviceType
        }

        Show-InventorySummary -Inventory $Inventory -Parts $Parts -Collection $Collection
        Write-Host '[1] Zapisz pliki PHP'
        Write-Host '[2] Popraw dane ręczne'
        Write-Host '[3] Wróć do edycji podzespołów'
        Write-Host '[4] Anuluj'
        $FinalChoice = Read-MenuChoice -Prompt 'Wybierz operację [1-4]' -Minimum 1 -Maximum 4
        if ($FinalChoice -eq 1) { break }
        if ($FinalChoice -eq 2) {
            $Manual = Read-ManualData -Current $Manual
            continue
        }
        if ($FinalChoice -eq 3) {
            $Review = Review-HardwareParts `
                -InitialParts $Parts `
                -ServiceTag $ServiceTag `
                -ComputerModel $System.Model `
                -Processor $System.Processor `
                -CoreCount $System.CoreCount `
                -ClockSpeedMhz $System.ClockSpeedMhz `
                -Mainboard $Mainboard
            if ($Review.Action -eq 'Accept') { $Parts = @($Review.Parts); continue }
            if ($Review.Action -eq 'Refresh') {
                $MemoryInventory = Get-MemoryInventory
                $MemorySpec = Resolve-MemorySpec `
                    -ModelEntry $ModelEntry `
                    -MemoryInventory $MemoryInventory `
                    -DatabasePath $ModelDatabasePath
                $Mainboard = Resolve-MainboardDescription `
                    -ModelEntry $ModelEntry `
                    -MemorySpec $MemorySpec `
                    -Manufacturer $System.BaseBoardManufacturer `
                    -Product $System.BaseBoardProduct `
                    -Version $System.BaseBoardVersion
                $DetectedParts = Get-HardwareParts -ComputerModel $System.Model -MemoryInventory $MemoryInventory
                $Review = Review-HardwareParts `
                    -InitialParts $DetectedParts `
                    -ServiceTag $ServiceTag `
                    -ComputerModel $System.Model `
                    -Processor $System.Processor `
                    -CoreCount $System.CoreCount `
                    -ClockSpeedMhz $System.ClockSpeedMhz `
                    -Mainboard $Mainboard
                if ($Review.Action -eq 'Accept') { $Parts = @($Review.Parts); continue }
            }
            throw [OperationCanceledException]::new('Anulowano przegląd podzespołów.')
        }
        throw [OperationCanceledException]::new('Anulowano przed zapisem.')
    }

    $RecordBody = New-PhpRecordBody -Inventory $Inventory -Parts $Parts
    $DeviceContent = New-DevicePhp -Body $RecordBody
    $Saved = Save-InventoryFiles -Collection $Collection -ServiceTag $ServiceTag -DeviceContent $DeviceContent -RecordBody $RecordBody -Action $ExistingAction

    Write-Section -Title 'Zapis zakończony'
    Write-Host "Plik urządzenia: $($Saved.DevicePath)" -ForegroundColor Green
    Write-Host "Plik zbiorczy:   $($Saved.CollectionPath)" -ForegroundColor Green
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-HardwareInventory
        exit 0
    }
    catch [OperationCanceledException] {
        Write-Warning $_.Exception.Message
        exit 2
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        if (-not [string]::IsNullOrWhiteSpace($_.ScriptStackTrace)) {
            $ErrorMessage += "`r`nMiejsce błędu: $($_.ScriptStackTrace)"
        }
        Write-Error $ErrorMessage -ErrorAction Continue
        exit 1
    }
}
