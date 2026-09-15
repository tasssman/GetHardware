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

function Confirm-InventoryEnvironment {
    Write-Section -Title 'Przygotowanie do inwentaryzacji'
    Write-Host 'Przed rozpoczęciem:'
    Write-Host ''
    Write-Host '1. Odłącz wszystkie dodatkowe monitory.'
    Write-Host '   Dotyczy to również stacji dokujących i sesji pulpitu zdalnego.'
    Write-Host ''
    Write-Host '2. Odłącz zewnętrzne urządzenia USB, w szczególności:'
    Write-Host '   - karty sieciowe,'
    Write-Host '   - karty dźwiękowe,'
    Write-Host '   - dyski i pendrive''y,'
    Write-Host '   - stacje dokujące.'
    Write-Host ''
    Write-Warning 'Podłączone urządzenia mogą zostać błędnie zapisane jako podzespoły komputera.'
    Write-Host '[1] Sprzęt został przygotowany — rozpocznij'
    Write-Host '[2] Anuluj'
    $Choice = Read-MenuChoice -Prompt 'Wybierz operację [1-2]' -Minimum 1 -Maximum 2
    if ($Choice -eq 2) {
        throw [OperationCanceledException]::new('Anulowano przed rozpoczęciem odczytu sprzętu.')
    }
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
        $DefaultText = if ($null -eq $Default) { '' } else { [string]$Default }
        if (-not [string]::IsNullOrWhiteSpace($DefaultText)) {
            $DisplayPrompt += " [$DefaultText]"
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

function Read-NonNegativeInteger {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [AllowNull()]$Default
    )

    while ($true) {
        $Value = Read-TextValue -Prompt $Prompt -Default $Default
        $Number = 0
        if ([int]::TryParse($Value, [ref]$Number) -and $Number -ge 0) {
            return $Number
        }

        Write-Warning 'Wpisz liczbę całkowitą równą lub większą od zera.'
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

    Write-Section -Title 'Etykieta systemu'
    Write-Host '[1] W10P'
    Write-Host '[2] W11P'
    Write-Host '[3] Wpisz inną etykietę'
    if (-not [string]::IsNullOrWhiteSpace($Current)) {
        Write-Host "Aktualna wartość: $Current" -ForegroundColor DarkGray
    }
    $Choice = Read-MenuChoice -Prompt 'Wybierz etykietę systemu [1-3]' -Minimum 1 -Maximum 3
    if ($Choice -eq 1) { return 'W10P' }
    if ($Choice -eq 2) { return 'W11P' }

    $CustomDefault = if ([string]::IsNullOrWhiteSpace($Current)) { $null } else { $Current.Trim() }
    return Read-TextValue -Prompt 'Podaj własną etykietę systemu' -Default $CustomDefault
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

function Write-ModelDatabase {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Models
    )

    $Json = ConvertTo-Json -InputObject @($Models) -Depth 6
    $TemporaryPath = Join-Path `
        (Split-Path -Parent $Path) `
        ".$([IO.Path]::GetFileName($Path)).$([guid]::NewGuid().ToString('N')).tmp"
    $BackupPath = "$TemporaryPath.bak"
    try {
        Write-Utf8NoBomFile -Path $TemporaryPath -Content ($Json + [Environment]::NewLine)
        $null = Import-ModelDatabase -Path $TemporaryPath
        [IO.File]::Replace($TemporaryPath, $Path, $BackupPath)
    }
    finally {
        foreach ($CleanupPath in @($TemporaryPath, $BackupPath)) {
            if (Test-Path -LiteralPath $CleanupPath) {
                Remove-Item -LiteralPath $CleanupPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function New-ModelDatabaseEntry {
    param(
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$MemorySpec,
        [Parameter(Mandatory)][int]$PowerMaxW,
        [Parameter(Mandatory)][int]$PowerW,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Other,
        [Parameter(Mandatory)][string]$DeviceType
    )

    return [pscustomobject][ordered]@{
        model             = $Model.Trim()
        baseboardFallback = $Model.Trim()
        memorySpec        = $MemorySpec.Trim()
        powerMaxW         = $PowerMaxW
        powerW            = $PowerW
        other             = $Other.Trim()
        deviceType        = $DeviceType.Trim().ToLowerInvariant()
    }
}

function Add-ModelDatabaseEntry {
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][psobject]$Entry
    )

    $Models = @(Import-ModelDatabase -Path $DatabasePath)
    $Matches = @($Models | Where-Object { ([string]$_.model).Trim() -ieq ([string]$Entry.model).Trim() })
    if ($Matches.Count -gt 0) {
        throw "Nie można dodać modelu '$($Entry.model)', ponieważ jest już obecny w bazie."
    }

    $UpdatedModels = @($Models) + @($Entry)
    Write-ModelDatabase -Path $DatabasePath -Models $UpdatedModels
    $VerifiedModels = @(Import-ModelDatabase -Path $DatabasePath)
    $VerifiedMatches = @($VerifiedModels | Where-Object { ([string]$_.model).Trim() -ieq ([string]$Entry.model).Trim() })
    if ($VerifiedMatches.Count -ne 1) {
        throw "Nie udało się zweryfikować zapisu modelu '$($Entry.model)' w bazie."
    }
    return $VerifiedMatches[0]
}

function Read-DeviceTypeForNewModel {
    param([AllowNull()][string]$DetectedDeviceType)

    $Detected = ([string]$DetectedDeviceType).Trim().ToLowerInvariant()
    if ($Detected -in @('laptop', 'tablet', 'desktop', 'server', 'storage')) {
        return $Detected
    }

    Write-Warning 'Nie udało się jednoznacznie wykryć typu urządzenia z obudowy SMBIOS.'
    Write-Host '[1] laptop'
    Write-Host '[2] tablet'
    Write-Host '[3] desktop'
    Write-Host '[4] server'
    Write-Host '[5] storage'
    $Choice = Read-MenuChoice -Prompt 'Wybierz typ urządzenia [1-5]' -Minimum 1 -Maximum 5
    return @('laptop', 'tablet', 'desktop', 'server', 'storage')[$Choice - 1]
}

function Read-MemorySpecForNewModel {
    param(
        [Parameter(Mandatory)][string]$Model,
        [AllowNull()][psobject]$MemoryInventory
    )

    $DetectedSpec = ''
    if ($null -ne $MemoryInventory -and [bool]$MemoryInventory.SpecReliable) {
        $DetectedSpec = ([string]$MemoryInventory.DetectedSpec).Trim()
    }

    if ([string]::IsNullOrWhiteSpace($DetectedSpec)) {
        Write-Warning 'Nie udało się jednoznacznie wykryć typu, szybkości i konfiguracji pamięci.'
        return Read-CompleteMemorySpec -Model $Model -DetectedSpec $null
    }

    Write-Host "Wykryta konfiguracja pamięci: $DetectedSpec" -ForegroundColor Green
    Write-Host 'Maksimum podawane przez SMBIOS nie jest używane, ponieważ może być limitem kontrolera, a nie konkretnego modelu.' -ForegroundColor DarkGray
    while ($true) {
        $Maximum = Read-TextValue -Prompt 'Maksymalna obsługiwana pamięć w GB (sprawdź w dokumentacji producenta)' -Default $null
        $NormalizedMaximum = $Maximum.Replace(',', '.')
        $ParsedMaximum = 0.0
        if ($NormalizedMaximum -match '^\d+(?:\.\d+)?$' -and
            [double]::TryParse($NormalizedMaximum, [Globalization.NumberStyles]::AllowDecimalPoint, [Globalization.CultureInfo]::InvariantCulture, [ref]$ParsedMaximum) -and
            $ParsedMaximum -gt 0) {
            return "$DetectedSpec, max${NormalizedMaximum}GB"
        }
        Write-Warning 'Podaj dodatnią pojemność w GB, np. 64.'
    }
}

function Read-NewModelDatabaseEntry {
    param(
        [Parameter(Mandatory)][string]$Model,
        [AllowNull()][psobject]$MemoryInventory,
        [AllowNull()][string]$DetectedDeviceType
    )

    Write-Section -Title 'Nowy model w bazie'
    Write-Host "Model:               $Model"
    Write-Host "Awaryjny opis płyty: $Model"
    $MemorySpecDefault = Read-MemorySpecForNewModel -Model $Model -MemoryInventory $MemoryInventory
    $DeviceTypeDefault = Read-DeviceTypeForNewModel -DetectedDeviceType $DetectedDeviceType
    Write-Host "Typ urządzenia:      $DeviceTypeDefault" -ForegroundColor Green
    $PowerMaxDefault = $null
    $PowerDefault = $null
    $OtherDefault = ''

    while ($true) {
        $PowerMax = Read-NonNegativeInteger -Prompt 'Maksymalna moc zasilacza — powerMaxW [W]' -Default $PowerMaxDefault
        $Power = Read-NonNegativeInteger -Prompt 'Pobór mocy — powerW [W]' -Default $PowerDefault
        $Other = Read-TextValue -Prompt 'Dodatkowe informacje — other (opcjonalnie)' -Default $OtherDefault -AllowEmpty
        $Entry = New-ModelDatabaseEntry `
            -Model $Model `
            -MemorySpec $MemorySpecDefault `
            -PowerMaxW $PowerMax `
            -PowerW $Power `
            -Other $Other `
            -DeviceType $DeviceTypeDefault

        Write-Section -Title 'Podsumowanie nowego modelu'
        Write-Host (ConvertTo-Json -InputObject $Entry -Depth 4)
        Write-Host '[1] Zapisz wpis w hardware-models.json'
        Write-Host '[2] Popraw wartości ręczne'
        Write-Host '[3] Anuluj'
        $Choice = Read-MenuChoice -Prompt 'Wybierz operację [1-3]' -Minimum 1 -Maximum 3
        if ($Choice -eq 1) { return $Entry }
        if ($Choice -eq 3) {
            throw [OperationCanceledException]::new('Anulowano dodawanie nowego modelu.')
        }

        $PowerMaxDefault = $PowerMax
        $PowerDefault = $Power
        $OtherDefault = $Other
    }
}

function Wait-ForKnownModel {
    param(
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$DatabasePath,
        [AllowNull()][psobject]$MemoryInventory,
        [AllowNull()][string]$DetectedDeviceType
    )

    while ($true) {
        try {
            $Models = Import-ModelDatabase -Path $DatabasePath
            $Matches = @($Models | Where-Object { ([string]$_.model).Trim() -ieq $Model.Trim() })
            if ($Matches.Count -eq 1) {
                return $Matches[0]
            }

            Write-Warning "Modelu '$Model' nie ma w bazie."
            $NewEntry = Read-NewModelDatabaseEntry `
                -Model $Model `
                -MemoryInventory $MemoryInventory `
                -DetectedDeviceType $DetectedDeviceType
            $SavedEntry = Add-ModelDatabaseEntry -DatabasePath $DatabasePath -Entry $NewEntry
            Write-Host "Dodano model '$Model' do hardware-models.json." -ForegroundColor Green
            return $SavedEntry
        }
        catch {
            if ($_.Exception -is [OperationCanceledException]) { throw }
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

function Get-DellSupportUrl {
    param(
        [AllowNull()][string]$Manufacturer,
        [Parameter(Mandatory)][string]$ServiceTag
    )

    if (([string]$Manufacturer).Trim() -notmatch '(?i)\bDell\b') {
        return ''
    }
    if (-not (Test-ServiceTag -Value $ServiceTag)) {
        return ''
    }

    $EncodedServiceTag = [Uri]::EscapeDataString($ServiceTag.Trim().ToUpperInvariant())
    return "https://www.dell.com/support/home/en-us/product-support/servicetag/$EncodedServiceTag/overview"
}

function Open-DellSupportPage {
    param(
        [AllowNull()][string]$Manufacturer,
        [Parameter(Mandatory)][string]$ServiceTag
    )

    $Url = Get-DellSupportUrl -Manufacturer $Manufacturer -ServiceTag $ServiceTag
    if ([string]::IsNullOrWhiteSpace($Url)) {
        return
    }

    Write-Section -Title 'Wsparcie Dell'
    Write-Host "Strona urządzenia: $Url"
    try {
        Start-Process -FilePath $Url -ErrorAction Stop
        Write-Host 'Otwarto stronę w domyślnej przeglądarce.' -ForegroundColor Green
    }
    catch {
        Write-Warning "Nie udało się otworzyć domyślnej przeglądarki. Skopiuj powyższy adres ręcznie. Szczegóły: $($_.Exception.Message)"
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

function Get-ChassisTypeName {
    param([int]$Code)

    switch ($Code) {
        1 { return 'Other' }
        2 { return 'Unknown' }
        3 { return 'Desktop' }
        4 { return 'Low Profile Desktop' }
        5 { return 'Pizza Box' }
        6 { return 'Mini Tower' }
        7 { return 'Tower' }
        8 { return 'Portable' }
        9 { return 'Laptop' }
        10 { return 'Notebook' }
        11 { return 'Hand Held' }
        12 { return 'Docking Station' }
        13 { return 'All in One' }
        14 { return 'Sub Notebook' }
        15 { return 'Space-Saving' }
        16 { return 'Lunch Box' }
        17 { return 'Main System Chassis' }
        18 { return 'Expansion Chassis' }
        19 { return 'SubChassis' }
        20 { return 'Bus Expansion Chassis' }
        21 { return 'Peripheral Chassis' }
        22 { return 'Storage Chassis' }
        23 { return 'Rack Mount Chassis' }
        24 { return 'Sealed-Case PC' }
        30 { return 'Tablet' }
        31 { return 'Convertible' }
        32 { return 'Detachable' }
        default { return "Nieznany kod $Code" }
    }
}

function ConvertFrom-ChassisTypes {
    param([AllowNull()]$ChassisTypes)

    $Codes = @($ChassisTypes | ForEach-Object { [int]$_ } | Select-Object -Unique)
    $MappedTypes = @(
        foreach ($Code in $Codes) {
            switch ($Code) {
                { $_ -in @(8, 9, 10, 14, 31) } { 'laptop'; break }
                { $_ -in @(11, 30, 32) } { 'tablet'; break }
                { $_ -in @(3, 4, 5, 6, 7, 13, 15, 16, 24) } { 'desktop'; break }
                17 { 'server'; break }
                22 { 'storage'; break }
                23 { 'server'; break }
            }
        }
    )
    $MappedTypes = @($MappedTypes | Select-Object -Unique)
    $DetectedType = if ($MappedTypes.Count -eq 1) { [string]$MappedTypes[0] } else { '' }
    $Description = if ($Codes.Count -gt 0) {
        (@($Codes | ForEach-Object { '{0} ({1})' -f (Get-ChassisTypeName -Code $_), $_ })) -join ', '
    } else {
        'Nieznany'
    }

    return [pscustomobject]@{
        Codes          = $Codes
        Description    = $Description
        DetectedType   = $DetectedType
        IsUnambiguous  = -not [string]::IsNullOrWhiteSpace($DetectedType)
    }
}

function Resolve-DeviceType {
    param(
        [Parameter(Mandatory)][string]$DatabaseDeviceType,
        [AllowNull()][string]$DetectedDeviceType,
        [Parameter(Mandatory)][string]$ChassisDescription
    )

    $DatabaseType = $DatabaseDeviceType.Trim().ToLowerInvariant()
    $DetectedType = ([string]$DetectedDeviceType).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($DetectedType) -or $DetectedType -eq $DatabaseType) {
        return $DatabaseType
    }

    Write-Section -Title 'Niezgodny typ urządzenia'
    Write-Warning "Typ urządzenia w JSON ('$DatabaseType') jest sprzeczny z obudową SMBIOS '$ChassisDescription' ('$DetectedType')."
    Write-Host '[1] Zachowaj wartość z JSON'
    Write-Host '[2] Użyj wykrytej wartości tylko dla tego urządzenia'
    $Choice = Read-MenuChoice -Prompt 'Wybierz operację [1-2]' -Minimum 1 -Maximum 2
    if ($Choice -eq 2) { return $DetectedType }
    return $DatabaseType
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

    $Enclosure = $null
    try {
        $Enclosure = Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction Stop |
            Select-Object -First 1
    }
    catch {
        Write-Warning "Nie udało się odczytać typu obudowy z Win32_SystemEnclosure: $($_.Exception.Message)"
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
    $Chassis = ConvertFrom-ChassisTypes -ChassisTypes $(
        if ($null -ne $Enclosure) { $Enclosure.ChassisTypes } else { @() }
    )

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
        ChassisTypeCodes       = $Chassis.Codes
        ChassisDescription     = $Chassis.Description
        DetectedDeviceType     = $Chassis.DetectedType
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

function Get-OptionalPropertyValue {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $InputObject) { return $null }
    $Property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $Property) { return $null }
    return $Property.Value
}

function Test-InternalDisplayConnection {
    param([AllowNull()]$VideoOutputTechnology)

    if ($null -eq $VideoOutputTechnology) { return $false }
    $Technology = [int64]$VideoOutputTechnology
    if ($Technology -lt 0) { $Technology += 4294967296 }

    # D3DKMDT: LVDS, embedded DisplayPort, embedded UDI oraz INTERNAL.
    return $Technology -in @(6, 11, 13, 2147483648)
}

function Get-DisplaySizeText {
    param(
        [AllowNull()]$WidthCm,
        [AllowNull()]$HeightCm
    )

    if ($null -eq $WidthCm -or $null -eq $HeightCm -or
        [double]$WidthCm -le 0 -or [double]$HeightCm -le 0) {
        return ''
    }

    $Diagonal = [math]::Sqrt(
        [math]::Pow([double]$WidthCm, 2) +
        [math]::Pow([double]$HeightCm, 2)
    ) / 2.54
    $OneDecimal = [math]::Round($Diagonal, 1)

    $StandardSizes = @(10.1, 11.6, 12.5, 13.3, 14.0, 15.6, 16.0, 17.3, 18.0)
    $NearestStandard = $StandardSizes |
        Sort-Object { [math]::Abs([double]$_ - $Diagonal) } |
        Select-Object -First 1
    if ([math]::Abs([double]$NearestStandard - $Diagonal) -le 0.35) {
        if ([double]$NearestStandard -eq [math]::Truncate([double]$NearestStandard)) {
            return ('{0}"' -f [int]$NearestStandard)
        }
        return ('{0}"' -f ([double]$NearestStandard).ToString('0.0', [Globalization.CultureInfo]::InvariantCulture))
    }

    return ('{0}"' -f $OneDecimal.ToString('0.0', [Globalization.CultureInfo]::InvariantCulture))
}

function Test-DisplaySerialNumber {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return $Value.Trim() -notmatch '^(0+|Unknown|None|N/A|Not Specified)$'
}

function ConvertTo-DisplayParts {
    param(
        [AllowEmptyCollection()][object[]]$MonitorIds = @(),
        [AllowEmptyCollection()][object[]]$DisplayParameters = @(),
        [AllowEmptyCollection()][object[]]$ConnectionParameters = @(),
        [AllowEmptyCollection()][object[]]$ModeLists = @(),
        [bool]$TouchDetected = $false
    )

    $ParametersByInstance = @{}
    foreach ($Item in $DisplayParameters) {
        $InstanceName = [string](Get-OptionalPropertyValue -InputObject $Item -Name 'InstanceName')
        if (-not [string]::IsNullOrWhiteSpace($InstanceName)) { $ParametersByInstance[$InstanceName] = $Item }
    }
    $ConnectionsByInstance = @{}
    foreach ($Item in $ConnectionParameters) {
        $InstanceName = [string](Get-OptionalPropertyValue -InputObject $Item -Name 'InstanceName')
        if (-not [string]::IsNullOrWhiteSpace($InstanceName)) { $ConnectionsByInstance[$InstanceName] = $Item }
    }
    $ModesByInstance = @{}
    foreach ($Item in $ModeLists) {
        $InstanceName = [string](Get-OptionalPropertyValue -InputObject $Item -Name 'InstanceName')
        if (-not [string]::IsNullOrWhiteSpace($InstanceName)) { $ModesByInstance[$InstanceName] = $Item }
    }

    $Parts = New-Object System.Collections.Generic.List[object]
    foreach ($Monitor in $MonitorIds) {
        $Active = Get-OptionalPropertyValue -InputObject $Monitor -Name 'Active'
        if ($null -ne $Active -and -not [bool]$Active) { continue }

        $InstanceName = [string](Get-OptionalPropertyValue -InputObject $Monitor -Name 'InstanceName')
        $Parameter = $ParametersByInstance[$InstanceName]
        $Connection = $ConnectionsByInstance[$InstanceName]
        $ModeList = $ModesByInstance[$InstanceName]
        $IsInternal = Test-InternalDisplayConnection -VideoOutputTechnology (
            Get-OptionalPropertyValue -InputObject $Connection -Name 'VideoOutputTechnology'
        )

        $SizeText = Get-DisplaySizeText `
            -WidthCm (Get-OptionalPropertyValue -InputObject $Parameter -Name 'MaxHorizontalImageSize') `
            -HeightCm (Get-OptionalPropertyValue -InputObject $Parameter -Name 'MaxVerticalImageSize')

        $MaximumMode = @(
            @(Get-OptionalPropertyValue -InputObject $ModeList -Name 'MonitorSourceModes') |
                Where-Object {
                    [int](Get-OptionalPropertyValue -InputObject $_ -Name 'HorizontalActivePixels') -gt 0 -and
                    [int](Get-OptionalPropertyValue -InputObject $_ -Name 'VerticalActivePixels') -gt 0
                } |
                Sort-Object @{
                    Expression = {
                        [int64](Get-OptionalPropertyValue -InputObject $_ -Name 'HorizontalActivePixels') *
                        [int64](Get-OptionalPropertyValue -InputObject $_ -Name 'VerticalActivePixels')
                    }
                    Descending = $true
                } |
                Select-Object -First 1
        )
        $Resolution = ''
        if ($MaximumMode.Count -gt 0) {
            $Resolution = '{0}x{1}' -f `
                (Get-OptionalPropertyValue -InputObject $MaximumMode[0] -Name 'HorizontalActivePixels'), `
                (Get-OptionalPropertyValue -InputObject $MaximumMode[0] -Name 'VerticalActivePixels')
        }

        $Serial = Convert-EdidText -Values (Get-OptionalPropertyValue -InputObject $Monitor -Name 'SerialNumberID')
        if (-not (Test-DisplaySerialNumber -Value $Serial)) { $Serial = '' }

        if ($IsInternal) {
            $Description = (@($SizeText, $Resolution) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' '
            if ($TouchDetected) { $Description = "$Description touch".Trim() }
            if ([string]::IsNullOrWhiteSpace($Description)) { $Description = 'QQ_POPRAW' }
            $Parts.Add((New-HardwarePart -Type 'Matrix' -Description $Description -Connection 'on board'))
        }
        else {
            $Name = Convert-EdidText -Values (Get-OptionalPropertyValue -InputObject $Monitor -Name 'UserFriendlyName')
            $Description = (@($SizeText, $Name, $Resolution) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' '
            if ([string]::IsNullOrWhiteSpace($Description)) { $Description = 'QQ_POPRAW' }
            $Parts.Add((New-HardwarePart -Type 'Monitor' -Description $Description -Connection '' -SerialNumber $Serial))
        }
    }

    return $Parts.ToArray()
}

function Test-TouchScreenDetected {
    if (-not (Get-Command -Name Get-PnpDevice -ErrorAction SilentlyContinue) -or
        -not (Get-Command -Name Get-PnpDeviceProperty -ErrorAction SilentlyContinue)) {
        return $false
    }

    foreach ($Device in @(Get-PnpDevice -PresentOnly -ErrorAction Stop | Where-Object Class -EQ 'HIDClass')) {
        $HardwareIds = (Get-PnpDeviceProperty `
            -InstanceId $Device.InstanceId `
            -KeyName 'DEVPKEY_Device_HardwareIds' `
            -ErrorAction SilentlyContinue).Data
        if ($HardwareIds -match 'HID_DEVICE_UP:000D_U:0004') { return $true }
    }
    return $false
}

function Initialize-StorageTopologyApi {
    if ('GetHardware.StorageTopology' -as [type]) { return }

    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace GetHardware
{
    public sealed class DiskFormFactorResult
    {
        public int Code { get; set; }
        public string Name { get; set; }
        public string Source { get; set; }
        public string Detail { get; set; }
    }

    public sealed class NvmeHealthResult
    {
        public bool Available { get; set; }
        public string Source { get; set; }
        public string Detail { get; set; }
        public ulong? PowerOnHours { get; set; }
        public ulong? DataUnitsRead { get; set; }
        public ulong? DataUnitsWritten { get; set; }
        public int? PercentageUsed { get; set; }
    }

    public static class StorageTopology
    {
        private const uint IOCTL_STORAGE_QUERY_PROPERTY = 0x002D1400;
        private const uint FILE_SHARE_READ = 0x00000001;
        private const uint FILE_SHARE_WRITE = 0x00000002;
        private const uint OPEN_EXISTING = 3;
        private static readonly IntPtr InvalidHandleValue = new IntPtr(-1);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateFile(string fileName, uint desiredAccess, uint shareMode,
            IntPtr securityAttributes, uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool DeviceIoControl(IntPtr device, uint controlCode, byte[] input,
            uint inputSize, byte[] output, uint outputSize, out uint bytesReturned, IntPtr overlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr handle);

        public static DiskFormFactorResult Query(int diskNumber)
        {
            string path = @"\\.\PhysicalDrive" + diskNumber;
            IntPtr handle = CreateFile(path, 0, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero,
                OPEN_EXISTING, 0, IntPtr.Zero);
            if (handle == InvalidHandleValue)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Nie można otworzyć " + path);

            try
            {
                int[] propertyIds = new int[] { 54, 53 };
                string[] propertyNames = new string[] {
                    "StorageDevicePhysicalTopologyProperty", "StorageAdapterPhysicalTopologyProperty"
                };
                int lastError = 0;

                for (int propertyIndex = 0; propertyIndex < propertyIds.Length; propertyIndex++)
                {
                    byte[] query = new byte[12];
                    Buffer.BlockCopy(BitConverter.GetBytes(propertyIds[propertyIndex]), 0, query, 0, 4);
                    byte[] output = new byte[65536];
                    uint bytesReturned;
                    bool success = DeviceIoControl(handle, IOCTL_STORAGE_QUERY_PROPERTY, query,
                        (uint)query.Length, output, (uint)output.Length, out bytesReturned, IntPtr.Zero);
                    if (!success)
                    {
                        lastError = Marshal.GetLastWin32Error();
                        continue;
                    }
                    if (bytesReturned < 56) continue;

                    uint nodeCount = BitConverter.ToUInt32(output, 8);
                    for (uint nodeIndex = 0; nodeIndex < nodeCount; nodeIndex++)
                    {
                        long nodeOffset64 = 16L + (nodeIndex * 40L);
                        if (nodeOffset64 + 28 > bytesReturned) break;
                        int nodeOffset = (int)nodeOffset64;
                        uint deviceCount = BitConverter.ToUInt32(output, nodeOffset + 16);
                        uint deviceDataOffset = BitConverter.ToUInt32(output, nodeOffset + 24);
                        if (deviceCount == 0 || deviceDataOffset == 0 || deviceDataOffset + 24 > bytesReturned)
                            continue;

                        int code = BitConverter.ToInt32(output, (int)deviceDataOffset + 20);
                        return new DiskFormFactorResult {
                            Code = code,
                            Name = GetFormFactorName(code),
                            Source = propertyNames[propertyIndex],
                            Detail = code == 0 ? "Sterownik zwrócił nieznany format." : ""
                        };
                    }
                }

                return new DiskFormFactorResult {
                    Code = 0,
                    Name = "Unknown",
                    Source = "IOCTL_STORAGE_QUERY_PROPERTY",
                    Detail = lastError == 0 ? "Sterownik nie zwrócił danych o formacie."
                        : new Win32Exception(lastError).Message
                };
            }
            finally { CloseHandle(handle); }
        }

        public static NvmeHealthResult QueryNvmeHealth(int diskNumber)
        {
            string path = @"\\.\PhysicalDrive" + diskNumber;
            IntPtr handle = CreateFile(path, 0, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero,
                OPEN_EXISTING, 0, IntPtr.Zero);
            if (handle == InvalidHandleValue)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Nie można otworzyć " + path);

            try
            {
                // STORAGE_PROPERTY_QUERY (8 B) + STORAGE_PROTOCOL_SPECIFIC_DATA
                // (40 B) + standardowy 512-bajtowy dziennik NVMe SMART/Health.
                const int protocolOffset = 8;
                const int protocolSize = 40;
                const int healthLogSize = 512;
                const int bufferSize = protocolOffset + protocolSize + healthLogSize;
                int[] propertyIds = new int[] { 50, 49 };
                string[] propertyNames = new string[] {
                    "StorageDeviceProtocolSpecificProperty",
                    "StorageAdapterProtocolSpecificProperty"
                };
                int lastError = 0;

                for (int propertyIndex = 0; propertyIndex < propertyIds.Length; propertyIndex++)
                {
                    byte[] query = new byte[bufferSize];
                    Buffer.BlockCopy(BitConverter.GetBytes(propertyIds[propertyIndex]), 0, query, 0, 4);
                    // QueryType = PropertyStandardQuery (0).
                    Buffer.BlockCopy(BitConverter.GetBytes(3), 0, query, protocolOffset, 4);       // ProtocolTypeNvme
                    Buffer.BlockCopy(BitConverter.GetBytes(2), 0, query, protocolOffset + 4, 4);   // NVMeDataTypeLogPage
                    Buffer.BlockCopy(BitConverter.GetBytes(2), 0, query, protocolOffset + 8, 4);   // Health Information log
                    Buffer.BlockCopy(BitConverter.GetBytes(protocolSize), 0, query, protocolOffset + 16, 4);
                    Buffer.BlockCopy(BitConverter.GetBytes(healthLogSize), 0, query, protocolOffset + 20, 4);

                    byte[] output = new byte[bufferSize];
                    uint bytesReturned;
                    bool success = DeviceIoControl(handle, IOCTL_STORAGE_QUERY_PROPERTY, query,
                        (uint)query.Length, output, (uint)output.Length, out bytesReturned, IntPtr.Zero);
                    if (!success)
                    {
                        lastError = Marshal.GetLastWin32Error();
                        continue;
                    }
                    if (bytesReturned < protocolOffset + protocolSize) continue;

                    uint dataOffset = BitConverter.ToUInt32(output, protocolOffset + 16);
                    uint dataLength = BitConverter.ToUInt32(output, protocolOffset + 20);
                    long healthOffset64 = protocolOffset + dataOffset;
                    if (dataOffset < protocolSize || dataLength < healthLogSize ||
                        healthOffset64 < 0 || healthOffset64 + healthLogSize > bytesReturned)
                        continue;

                    NvmeHealthResult result = ParseHealthLog(output, (int)healthOffset64);
                    result.Available = true;
                    result.Source = propertyNames[propertyIndex];
                    return result;
                }

                return new NvmeHealthResult {
                    Available = false,
                    Source = "IOCTL_STORAGE_QUERY_PROPERTY",
                    Detail = lastError == 0 ? "Sterownik nie zwrócił dziennika NVMe SMART/Health."
                        : new Win32Exception(lastError).Message
                };
            }
            finally { CloseHandle(handle); }
        }

        public static NvmeHealthResult ParseHealthLog(byte[] healthLog)
        {
            if (healthLog == null) throw new ArgumentNullException("healthLog");
            return ParseHealthLog(healthLog, 0);
        }

        private static NvmeHealthResult ParseHealthLog(byte[] buffer, int offset)
        {
            if (buffer == null || offset < 0 || offset + 512 > buffer.Length)
                throw new ArgumentException("Dziennik NVMe SMART/Health musi mieć co najmniej 512 bajtów.");

            return new NvmeHealthResult {
                Available = true,
                Source = "NVMe SMART/Health",
                Detail = "",
                PercentageUsed = (int)buffer[offset + 5],
                DataUnitsRead = ReadUInt128AsUInt64(buffer, offset + 32),
                DataUnitsWritten = ReadUInt128AsUInt64(buffer, offset + 48),
                PowerOnHours = ReadUInt128AsUInt64(buffer, offset + 128)
            };
        }

        private static ulong? ReadUInt128AsUInt64(byte[] buffer, int offset)
        {
            // Rzeczywiste liczniki dysków użytkowych mieszczą się w UInt64. Jeśli
            // starsze 64 bity są niezerowe, nie obcinamy wartości i zgłaszamy brak.
            for (int index = 8; index < 16; index++)
                if (buffer[offset + index] != 0) return null;
            return BitConverter.ToUInt64(buffer, offset);
        }

        private static string GetFormFactorName(int code)
        {
            switch (code)
            {
                case 1: return "3.5 inch";
                case 2: return "2.5 inch";
                case 3: return "1.8 inch";
                case 4: return "Less than 1.8 inch";
                case 5: return "Embedded";
                case 6: return "Memory Card";
                case 7: return "mSATA";
                case 8: return "M.2";
                case 9: return "PCIe Board";
                case 10: return "DIMM";
                default: return "Unknown";
            }
        }
    }
}
'@ -ErrorAction Stop
}

function Initialize-NvmeHealthApi {
    # Add-Type nie pozwala zastąpić już załadowanej klasy w tej samej sesji
    # PowerShell. Odczyt NVMe ma własną wersjonowaną klasę, niezależną od klasy
    # formatu dysku, dzięki czemu aktualizacja skryptu nie wymaga nowej konsoli.
    if ('GetHardware.NvmeHealthReaderV1' -as [type]) { return }

    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace GetHardware
{
    public sealed class NvmeHealthSnapshotV1
    {
        public bool Available { get; set; }
        public string Source { get; set; }
        public string Detail { get; set; }
        public ulong? PowerOnHours { get; set; }
        public ulong? DataUnitsRead { get; set; }
        public ulong? DataUnitsWritten { get; set; }
        public int? PercentageUsed { get; set; }
    }

    public static class NvmeHealthReaderV1
    {
        private const uint IOCTL_STORAGE_QUERY_PROPERTY = 0x002D1400;
        private const uint FILE_SHARE_READ = 0x00000001;
        private const uint FILE_SHARE_WRITE = 0x00000002;
        private const uint OPEN_EXISTING = 3;
        private static readonly IntPtr InvalidHandleValue = new IntPtr(-1);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateFile(string fileName, uint desiredAccess, uint shareMode,
            IntPtr securityAttributes, uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool DeviceIoControl(IntPtr device, uint controlCode, byte[] input,
            uint inputSize, byte[] output, uint outputSize, out uint bytesReturned, IntPtr overlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr handle);

        public static NvmeHealthSnapshotV1 Query(int diskNumber)
        {
            string path = @"\\.\PhysicalDrive" + diskNumber;
            IntPtr handle = CreateFile(path, 0, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero,
                OPEN_EXISTING, 0, IntPtr.Zero);
            if (handle == InvalidHandleValue)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Nie można otworzyć " + path);

            try
            {
                const int protocolOffset = 8;
                const int protocolSize = 40;
                const int healthLogSize = 512;
                const int bufferSize = protocolOffset + protocolSize + healthLogSize;
                int[] propertyIds = new int[] { 50, 49 };
                string[] propertyNames = new string[] {
                    "StorageDeviceProtocolSpecificProperty",
                    "StorageAdapterProtocolSpecificProperty"
                };
                int lastError = 0;

                for (int propertyIndex = 0; propertyIndex < propertyIds.Length; propertyIndex++)
                {
                    byte[] query = new byte[bufferSize];
                    Buffer.BlockCopy(BitConverter.GetBytes(propertyIds[propertyIndex]), 0, query, 0, 4);
                    Buffer.BlockCopy(BitConverter.GetBytes(3), 0, query, protocolOffset, 4);
                    Buffer.BlockCopy(BitConverter.GetBytes(2), 0, query, protocolOffset + 4, 4);
                    Buffer.BlockCopy(BitConverter.GetBytes(2), 0, query, protocolOffset + 8, 4);
                    Buffer.BlockCopy(BitConverter.GetBytes(protocolSize), 0, query, protocolOffset + 16, 4);
                    Buffer.BlockCopy(BitConverter.GetBytes(healthLogSize), 0, query, protocolOffset + 20, 4);

                    byte[] output = new byte[bufferSize];
                    uint bytesReturned;
                    bool success = DeviceIoControl(handle, IOCTL_STORAGE_QUERY_PROPERTY, query,
                        (uint)query.Length, output, (uint)output.Length, out bytesReturned, IntPtr.Zero);
                    if (!success)
                    {
                        lastError = Marshal.GetLastWin32Error();
                        continue;
                    }
                    if (bytesReturned < protocolOffset + protocolSize) continue;

                    uint dataOffset = BitConverter.ToUInt32(output, protocolOffset + 16);
                    uint dataLength = BitConverter.ToUInt32(output, protocolOffset + 20);
                    long healthOffset = protocolOffset + dataOffset;
                    if (dataOffset < protocolSize || dataLength < healthLogSize ||
                        healthOffset + healthLogSize > bytesReturned) continue;

                    NvmeHealthSnapshotV1 result = Parse(output, (int)healthOffset);
                    result.Source = propertyNames[propertyIndex];
                    return result;
                }

                return new NvmeHealthSnapshotV1 {
                    Available = false,
                    Source = "IOCTL_STORAGE_QUERY_PROPERTY",
                    Detail = lastError == 0 ? "Sterownik nie zwrócił dziennika NVMe SMART/Health."
                        : new Win32Exception(lastError).Message
                };
            }
            finally { CloseHandle(handle); }
        }

        public static NvmeHealthSnapshotV1 ParseHealthLog(byte[] healthLog)
        {
            if (healthLog == null) throw new ArgumentNullException("healthLog");
            return Parse(healthLog, 0);
        }

        private static NvmeHealthSnapshotV1 Parse(byte[] buffer, int offset)
        {
            if (buffer == null || offset < 0 || offset + 512 > buffer.Length)
                throw new ArgumentException("Dziennik NVMe SMART/Health musi mieć co najmniej 512 bajtów.");

            return new NvmeHealthSnapshotV1 {
                Available = true,
                Source = "NVMe SMART/Health",
                Detail = "",
                PercentageUsed = (int)buffer[offset + 5],
                DataUnitsRead = ReadCounter(buffer, offset + 32),
                DataUnitsWritten = ReadCounter(buffer, offset + 48),
                PowerOnHours = ReadCounter(buffer, offset + 128)
            };
        }

        private static ulong? ReadCounter(byte[] buffer, int offset)
        {
            for (int index = 8; index < 16; index++)
                if (buffer[offset + index] != 0) return null;
            return BitConverter.ToUInt64(buffer, offset);
        }
    }
}
'@ -ErrorAction Stop
}

function Get-NativeDiskFormFactor {
    param([Parameter(Mandatory)][int]$DiskNumber)

    Initialize-StorageTopologyApi
    return [GetHardware.StorageTopology]::Query($DiskNumber)
}

function Get-NativeNvmeHealth {
    param([Parameter(Mandatory)][int]$DiskNumber)

    Initialize-NvmeHealthApi
    return [GetHardware.NvmeHealthReaderV1]::Query($DiskNumber)
}

function Get-DiskReliabilityData {
    param([Parameter(Mandatory)][psobject]$Disk)

    if (-not (Get-Command -Name Get-StorageReliabilityCounter -ErrorAction SilentlyContinue)) {
        return $null
    }
    return $Disk | Get-StorageReliabilityCounter -ErrorAction Stop
}

function Get-DiskHealthInformation {
    param(
        [Parameter(Mandatory)][psobject]$Disk,
        [Parameter(Mandatory)][int]$DiskNumber,
        [AllowNull()][string]$BusType
    )

    $Health = [string](Get-OptionalPropertyValue -InputObject $Disk -Name 'HealthStatus')
    $PowerOnHours = $null
    $BytesRead = $null
    $BytesWritten = $null
    $WearPercent = $null
    $Source = New-Object System.Collections.Generic.List[string]

    if (([string]$BusType).Trim() -ieq 'NVMe') {
        try {
            $Native = Get-NativeNvmeHealth -DiskNumber $DiskNumber
            if ($null -ne $Native -and $Native.Available) {
                $PowerOnHours = Get-OptionalPropertyValue -InputObject $Native -Name 'PowerOnHours'
                $DataUnitsRead = Get-OptionalPropertyValue -InputObject $Native -Name 'DataUnitsRead'
                $DataUnitsWritten = Get-OptionalPropertyValue -InputObject $Native -Name 'DataUnitsWritten'
                $WearPercent = Get-OptionalPropertyValue -InputObject $Native -Name 'PercentageUsed'
                if ($null -ne $DataUnitsRead) { $BytesRead = [decimal]$DataUnitsRead * 512000 }
                if ($null -ne $DataUnitsWritten) { $BytesWritten = [decimal]$DataUnitsWritten * 512000 }
                $Source.Add('NVMe SMART/Health')
            }
        }
        catch { }
    }

    if ($null -eq $PowerOnHours -or $null -eq $WearPercent) {
        try {
            $Reliability = Get-DiskReliabilityData -Disk $Disk
            if ($null -ne $Reliability) {
                if ($null -eq $PowerOnHours) {
                    $PowerOnHours = Get-OptionalPropertyValue -InputObject $Reliability -Name 'PowerOnHours'
                }
                if ($null -eq $WearPercent) {
                    $WearPercent = Get-OptionalPropertyValue -InputObject $Reliability -Name 'Wear'
                }
                $Source.Add('Get-StorageReliabilityCounter')
            }
        }
        catch { }
    }

    return [pscustomobject]@{
        HealthStatus = $Health
        PowerOnHours = $PowerOnHours
        BytesRead     = $BytesRead
        BytesWritten  = $BytesWritten
        WearPercent   = $WearPercent
        Source        = ($Source | Select-Object -Unique) -join ', '
    }
}

function Test-DiskSerialNumber {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return $Value.Trim() -notmatch '^(0+|Unknown|None|N/A|Default string|Not Specified)$'
}

function Get-NormalizedDiskSerialNumber {
    param(
        [AllowNull()][string]$SerialNumber,
        [AllowNull()][string]$UniqueId
    )

    $Serial = ([string]$SerialNumber).Trim().TrimEnd('.')
    if ($Serial -match '^(?:[0-9A-Fa-f]{4}_)+[0-9A-Fa-f]{4}$') {
        $Serial = $Serial -replace '_', ''
    }
    if (Test-DiskSerialNumber -Value $Serial) { return $Serial }

    $Fallback = ([string]$UniqueId).Trim()
    if ($Fallback -match '^(?i)eui\.(?<serial>[0-9a-f]+)$') {
        return $Matches['serial'].ToUpperInvariant()
    }
    return ''
}

function Get-NormalizedDiskModel {
    param(
        [AllowNull()][string]$Model,
        [AllowNull()][string]$FriendlyName,
        [Parameter(Mandatory)][int64]$CapacityGb,
        [AllowNull()][string]$BusType,
        [AllowNull()][string]$MediaType
    )

    $Value = if (-not [string]::IsNullOrWhiteSpace($Model)) { $Model } else { $FriendlyName }
    $Value = ([string]$Value -replace '\s+', ' ').Trim()
    $Value = [regex]::Replace($Value, "(?i)(?<!\d)$CapacityGb\s*(?:GB|G)\b", '')
    foreach ($RedundantValue in @($BusType, $MediaType)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$RedundantValue)) {
            $Value = [regex]::Replace($Value, "(?i)(?<![A-Z0-9])$([regex]::Escape([string]$RedundantValue))(?![A-Z0-9])", '')
        }
    }
    return ($Value -replace '\s+', ' ').Trim(' ', '-', '_')
}

function Get-DiskConnectionDefault {
    param([AllowNull()][string]$BusType)

    switch -Regex (([string]$BusType).Trim()) {
        '^(?i)NVMe$' { return 'M.2' }
        '^(?i)SATA|ATA$' { return 'SATA' }
        '^(?i)USB$' { return 'USB' }
        '^(?i)SAS$' { return 'SAS' }
        default { return ([string]$BusType).Trim() }
    }
}

function Convert-DiskFormFactorToConnection {
    param([AllowNull()][string]$FormFactor)

    switch (([string]$FormFactor).Trim()) {
        'M.2' { return 'M.2' }
        'mSATA' { return 'mSATA' }
        '3.5 inch' { return '3.5"' }
        '2.5 inch' { return '2.5"' }
        '1.8 inch' { return '1.8"' }
        'Less than 1.8 inch' { return '<1.8"' }
        'Embedded' { return 'on board' }
        'Memory Card' { return 'Memory Card' }
        'PCIe Board' { return 'PCIe' }
        'DIMM' { return 'DIMM' }
        default { return '' }
    }
}

function New-PhysicalDiskPart {
    param([Parameter(Mandatory)][psobject]$Disk)

    $Size = Get-OptionalPropertyValue -InputObject $Disk -Name 'Size'
    if ($null -eq $Size -or [double]$Size -le 0) { throw 'Brak prawidłowej pojemności dysku.' }
    $CapacityGb = [int64][math]::Round([double]$Size / 1000000000)
    $BusType = ([string](Get-OptionalPropertyValue -InputObject $Disk -Name 'BusType')).Trim()
    $MediaType = ([string](Get-OptionalPropertyValue -InputObject $Disk -Name 'MediaType')).Trim()
    if ($MediaType -eq 'Unspecified') { $MediaType = '' }
    $Model = Get-NormalizedDiskModel `
        -Model ([string](Get-OptionalPropertyValue -InputObject $Disk -Name 'Model')) `
        -FriendlyName ([string](Get-OptionalPropertyValue -InputObject $Disk -Name 'FriendlyName')) `
        -CapacityGb $CapacityGb `
        -BusType $BusType `
        -MediaType $MediaType
    $Description = (@("${CapacityGb}GB", $BusType, $MediaType, $Model) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' '
    $Serial = Get-NormalizedDiskSerialNumber `
        -SerialNumber ([string](Get-OptionalPropertyValue -InputObject $Disk -Name 'SerialNumber')) `
        -UniqueId ([string](Get-OptionalPropertyValue -InputObject $Disk -Name 'UniqueId'))

    $DiskNumber = 0
    $DeviceId = [string](Get-OptionalPropertyValue -InputObject $Disk -Name 'DeviceId')
    if (-not [int]::TryParse($DeviceId, [ref]$DiskNumber)) {
        throw "Nieprawidłowy DeviceId dysku: '$DeviceId'."
    }

    $NativeFormat = $null
    try { $NativeFormat = Get-NativeDiskFormFactor -DiskNumber $DiskNumber }
    catch { $NativeFormat = $null }
    $Connection = if ($null -ne $NativeFormat) {
        Convert-DiskFormFactorToConnection -FormFactor ([string]$NativeFormat.Name)
    } else { '' }
    if ([string]::IsNullOrWhiteSpace($Connection)) {
        Write-Warning "Nie udało się automatycznie ustalić formatu dysku: $Description"
        $Connection = Read-TextValue `
            -Prompt 'Połączenie/format dysku — Enter zatwierdza podpowiedź, możesz też wpisać własną wartość' `
            -Default (Get-DiskConnectionDefault -BusType $BusType)
    }

    $Health = [string](Get-OptionalPropertyValue -InputObject $Disk -Name 'HealthStatus')
    if (-not [string]::IsNullOrWhiteSpace($Health) -and $Health -ne 'Healthy') {
        Write-Warning "Dysk '$Description' zgłasza HealthStatus: $Health."
    }

    $HealthInformation = Get-DiskHealthInformation -Disk $Disk -DiskNumber $DiskNumber -BusType $BusType
    $Part = New-HardwarePart -Type 'Hard Disk' -Description $Description -Connection $Connection -SerialNumber $Serial
    $Part | Add-Member -NotePropertyName DiskHealthStatus -NotePropertyValue $HealthInformation.HealthStatus
    $Part | Add-Member -NotePropertyName DiskPowerOnHours -NotePropertyValue $HealthInformation.PowerOnHours
    $Part | Add-Member -NotePropertyName DiskBytesRead -NotePropertyValue $HealthInformation.BytesRead
    $Part | Add-Member -NotePropertyName DiskBytesWritten -NotePropertyValue $HealthInformation.BytesWritten
    $Part | Add-Member -NotePropertyName DiskWearPercent -NotePropertyValue $HealthInformation.WearPercent
    $Part | Add-Member -NotePropertyName DiskDiagnosticSource -NotePropertyValue $HealthInformation.Source
    return $Part
}

function New-Win32DiskPart {
    param([Parameter(Mandatory)][psobject]$Disk)

    $Size = Get-OptionalPropertyValue -InputObject $Disk -Name 'Size'
    if ($null -eq $Size -or [double]$Size -le 0) { throw 'Brak prawidłowej pojemności dysku.' }
    $CapacityGb = [int64][math]::Round([double]$Size / 1000000000)
    $Model = ([string](Get-OptionalPropertyValue -InputObject $Disk -Name 'Model') -replace '\s+', ' ').Trim()
    $Description = "${CapacityGb}GB $Model".Trim()
    $Interface = [string](Get-OptionalPropertyValue -InputObject $Disk -Name 'InterfaceType')
    $PnpDeviceId = [string](Get-OptionalPropertyValue -InputObject $Disk -Name 'PNPDeviceID')
    $DefaultConnection = if ($PnpDeviceId -match '(?i)NVME') { 'M.2' } else { Get-DiskConnectionDefault -BusType $Interface }
    Write-Warning "Dokładne źródło danych dysku jest niedostępne: $Description"
    $Connection = Read-TextValue `
        -Prompt 'Połączenie/format dysku — Enter zatwierdza podpowiedź, możesz też wpisać własną wartość' `
        -Default $DefaultConnection
    $Serial = Get-NormalizedDiskSerialNumber `
        -SerialNumber ([string](Get-OptionalPropertyValue -InputObject $Disk -Name 'SerialNumber')) `
        -UniqueId ''
    $Part = New-HardwarePart -Type 'Hard Disk' -Description $Description -Connection $Connection -SerialNumber $Serial
    $Part | Add-Member -NotePropertyName DiskHealthStatus -NotePropertyValue ''
    $Part | Add-Member -NotePropertyName DiskPowerOnHours -NotePropertyValue $null
    $Part | Add-Member -NotePropertyName DiskBytesRead -NotePropertyValue $null
    $Part | Add-Member -NotePropertyName DiskBytesWritten -NotePropertyValue $null
    $Part | Add-Member -NotePropertyName DiskWearPercent -NotePropertyValue $null
    $Part | Add-Member -NotePropertyName DiskDiagnosticSource -NotePropertyValue ''
    return $Part
}

function Get-DiskInventoryParts {
    $Parts = New-Object System.Collections.Generic.List[object]
    $PhysicalDisks = @()
    try { $PhysicalDisks = @(Get-PhysicalDisk -ErrorAction Stop) }
    catch { Write-Warning "Nie udało się użyć Get-PhysicalDisk: $($_.Exception.Message)" }

    if ($PhysicalDisks.Count -gt 0) {
        foreach ($Disk in $PhysicalDisks) {
            try { $Parts.Add((New-PhysicalDiskPart -Disk $Disk)) }
            catch {
                $Identity = [string](Get-OptionalPropertyValue -InputObject $Disk -Name 'FriendlyName')
                Write-Warning "Pominięto dysk '$Identity': $($_.Exception.Message)"
            }
        }
    }
    else {
        try {
            foreach ($Disk in @(Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction Stop)) {
                try { $Parts.Add((New-Win32DiskPart -Disk $Disk)) }
                catch {
                    $Identity = [string](Get-OptionalPropertyValue -InputObject $Disk -Name 'Model')
                    Write-Warning "Pominięto dysk '$Identity': $($_.Exception.Message)"
                }
            }
        }
        catch { Write-Warning "Nie udało się odczytać dysków z Win32_DiskDrive: $($_.Exception.Message)" }
    }

    return $Parts.ToArray()
}

function Test-PhysicalGraphicsAdapter {
    param([Parameter(Mandatory)][psobject]$Graphics)

    $Name = (@(
        [string](Get-OptionalPropertyValue -InputObject $Graphics -Name 'Caption')
        [string](Get-OptionalPropertyValue -InputObject $Graphics -Name 'Name')
        [string](Get-OptionalPropertyValue -InputObject $Graphics -Name 'Description')
    ) -join ' ').Trim()
    $SoftwareAdapterPattern = '(?i)Microsoft\s+Remote\s+Display|Microsoft\s+Basic\s+Display|Remote\s+Display|Virtual\s+(?:Display|Graphics)|VirtualBox|VMware\s+SVGA|Hyper-V\s+Video|Citrix.*Display|Parsec.*Display|IddSample'
    if ($Name -match $SoftwareAdapterPattern) { return $false }

    $PnpDeviceId = [string](Get-OptionalPropertyValue -InputObject $Graphics -Name 'PNPDeviceID')
    if ($PnpDeviceId -match '^(?i)ROOT\\(?:RDP|BASICDISPLAY|INDIRECTDISPLAY)') { return $false }
    return $true
}

function Get-NormalizedMacAddress {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $Mac = ($Value -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
    if ($Mac.Length -ne 12) { return '' }
    if ($Mac -match '^(?:0{12}|F{12})$') { return '' }

    $FirstOctet = 0
    if (-not [int]::TryParse($Mac.Substring(0, 2), [Globalization.NumberStyles]::HexNumber,
        [Globalization.CultureInfo]::InvariantCulture, [ref]$FirstOctet)) { return '' }
    if (($FirstOctet -band 1) -ne 0) { return '' }
    return $Mac
}

function Test-LocallyAdministeredMacAddress {
    param([AllowNull()][string]$Value)

    $Mac = Get-NormalizedMacAddress -Value $Value
    if ([string]::IsNullOrWhiteSpace($Mac)) { return $false }
    $FirstOctet = [Convert]::ToInt32($Mac.Substring(0, 2), 16)
    return ($FirstOctet -band 2) -ne 0
}

function Get-NetworkAdapterDecision {
    param([Parameter(Mandatory)][psobject]$Adapter)

    $Description = (@(
        [string](Get-OptionalPropertyValue -InputObject $Adapter -Name 'InterfaceDescription')
        [string](Get-OptionalPropertyValue -InputObject $Adapter -Name 'Description')
        [string](Get-OptionalPropertyValue -InputObject $Adapter -Name 'Name')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1).Trim()
    $PnpDeviceId = ([string](Get-OptionalPropertyValue -InputObject $Adapter -Name 'PnPDeviceID')).Trim()
    if ([string]::IsNullOrWhiteSpace($PnpDeviceId)) {
        $PnpDeviceId = ([string](Get-OptionalPropertyValue -InputObject $Adapter -Name 'PNPDeviceID')).Trim()
    }
    $PhysicalMediaType = [string](Get-OptionalPropertyValue -InputObject $Adapter -Name 'PhysicalMediaType')
    $HardwareInterface = Get-OptionalPropertyValue -InputObject $Adapter -Name 'HardwareInterface'
    if ($null -eq $HardwareInterface) {
        $HardwareInterface = Get-OptionalPropertyValue -InputObject $Adapter -Name 'PhysicalAdapter'
    }
    $Virtual = Get-OptionalPropertyValue -InputObject $Adapter -Name 'Virtual'

    if ($PnpDeviceId -match '^(?i)USB\\') {
        return [pscustomobject]@{ Include = $false; Description = $Description; Connection = ''; Reason = 'zewnętrzny adapter USB' }
    }

    # Bluetooth PAN jest przez Windows oznaczany jako adapter wirtualny, mimo że
    # reprezentuje fizyczny, zwykle wbudowany moduł Bluetooth.
    if ($PnpDeviceId -match '^(?i)BTH\\' -or $PhysicalMediaType -match '^(?i)Bluetooth$') {
        return [pscustomobject]@{ Include = $true; Description = $Description; Connection = 'on board'; Reason = 'Bluetooth PAN' }
    }

    $VirtualPattern = '(?i)WAN Miniport|Wi-Fi Direct Virtual|Virtual (?:Ethernet|Switch|Miniport)|VPN|AnyConnect|Hyper-V|Teredo|6to4|IP-HTTPS|Kernel Debug|Loopback'
    if ($Virtual -eq $true -or $Description -match $VirtualPattern -or
        $PnpDeviceId -match '^(?i)(?:ROOT|SWD)\\') {
        return [pscustomobject]@{ Include = $false; Description = $Description; Connection = ''; Reason = 'adapter wirtualny lub systemowy' }
    }

    if ($HardwareInterface -ne $true) {
        return [pscustomobject]@{ Include = $false; Description = $Description; Connection = ''; Reason = 'brak potwierdzenia fizycznego interfejsu' }
    }

    return [pscustomobject]@{ Include = $true; Description = $Description; Connection = 'on board'; Reason = 'fizyczny adapter sieciowy' }
}

function ConvertTo-NetworkAdapterPart {
    param([Parameter(Mandatory)][psobject]$Adapter)

    $Decision = Get-NetworkAdapterDecision -Adapter $Adapter
    if (-not $Decision.Include) {
        $DisplayName = if ([string]::IsNullOrWhiteSpace([string]$Decision.Description)) { '(bez nazwy)' } else { $Decision.Description }
        Write-Host "Pominięto adapter sieciowy '$DisplayName': $($Decision.Reason)." -ForegroundColor DarkGray
        return $null
    }

    $PermanentAddress = Get-NormalizedMacAddress -Value ([string](Get-OptionalPropertyValue -InputObject $Adapter -Name 'PermanentAddress'))
    $CurrentAddress = Get-NormalizedMacAddress -Value ([string](Get-OptionalPropertyValue -InputObject $Adapter -Name 'MacAddress'))
    if ([string]::IsNullOrWhiteSpace($CurrentAddress)) {
        $CurrentAddress = Get-NormalizedMacAddress -Value ([string](Get-OptionalPropertyValue -InputObject $Adapter -Name 'MACAddress'))
    }
    $Mac = if (-not [string]::IsNullOrWhiteSpace($PermanentAddress)) { $PermanentAddress } else { $CurrentAddress }

    if ([string]::IsNullOrWhiteSpace($Mac)) {
        Write-Warning "Adapter '$($Decision.Description)' nie udostępnia poprawnego adresu MAC. Zostanie zapisany bez pola sn."
    }
    elseif (Test-LocallyAdministeredMacAddress -Value $Mac) {
        Write-Warning "Adapter '$($Decision.Description)' zgłasza lokalnie administrowany adres MAC: $Mac. Zweryfikuj go przed zatwierdzeniem."
    }

    return New-HardwarePart `
        -Type 'Network Card' `
        -Description ([string]$Decision.Description) `
        -Connection ([string]$Decision.Connection) `
        -SerialNumber $Mac
}

function Get-NetworkInventoryParts {
    $Parts = New-Object System.Collections.Generic.List[object]
    $Adapters = @()
    $UseFallback = $false

    if (Get-Command -Name Get-NetAdapter -ErrorAction SilentlyContinue) {
        try { $Adapters = @(Get-NetAdapter -Name * -IncludeHidden -ErrorAction Stop) }
        catch {
            Write-Warning "Nie udało się użyć Get-NetAdapter: $($_.Exception.Message)"
            $UseFallback = $true
        }
    }
    else { $UseFallback = $true }

    if ($UseFallback) {
        try { $Adapters = @(Get-CimInstance -ClassName Win32_NetworkAdapter -ErrorAction Stop) }
        catch {
            Write-Warning "Nie udało się odczytać kart sieciowych z Win32_NetworkAdapter: $($_.Exception.Message)"
            return $Parts.ToArray()
        }
    }

    foreach ($Adapter in $Adapters) {
        try {
            $Part = ConvertTo-NetworkAdapterPart -Adapter $Adapter
            if ($null -ne $Part) { $Parts.Add($Part) }
        }
        catch {
            $Identity = [string](Get-OptionalPropertyValue -InputObject $Adapter -Name 'InterfaceDescription')
            if ([string]::IsNullOrWhiteSpace($Identity)) {
                $Identity = [string](Get-OptionalPropertyValue -InputObject $Adapter -Name 'Description')
            }
            Write-Warning "Pominięto adapter sieciowy '$Identity': $($_.Exception.Message)"
        }
    }

    return $Parts.ToArray()
}

function Get-SoundDeviceDescription {
    param([Parameter(Mandatory)][psobject]$Device)

    $Description = @(
        [string](Get-OptionalPropertyValue -InputObject $Device -Name 'Caption')
        [string](Get-OptionalPropertyValue -InputObject $Device -Name 'Name')
        [string](Get-OptionalPropertyValue -InputObject $Device -Name 'Description')
        [string](Get-OptionalPropertyValue -InputObject $Device -Name 'ProductName')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
    return ([string]$Description -replace '\s+', ' ').Trim()
}

function Get-SoundDeviceClassification {
    param([Parameter(Mandatory)][psobject]$Device)

    $Description = Get-SoundDeviceDescription -Device $Device
    $PnpDeviceId = ([string](Get-OptionalPropertyValue -InputObject $Device -Name 'PNPDeviceID')).Trim()

    if ($PnpDeviceId -match '^(?i)INTELAUDIO\\CTLR_' -or
        $Description -match '(?i)Intel.*Smart Sound Technology') {
        return [pscustomobject]@{ Kind = 'Controller'; Description = $Description; Reason = 'kontroler Intel Smart Sound Technology, a nie osobna karta' }
    }
    if ($PnpDeviceId -match '^(?i)BTH\\' -or $Description -match '(?i)Bluetooth') {
        return [pscustomobject]@{ Kind = 'Skip'; Description = $Description; Reason = 'urządzenie audio Bluetooth' }
    }
    if ($Description -match '(?i)Display Audio|HDMI|DisplayPort|NVIDIA.*Audio|AMD.*Audio') {
        return [pscustomobject]@{ Kind = 'Skip'; Description = $Description; Reason = 'audio HDMI/DisplayPort' }
    }
    if ($PnpDeviceId -match '^(?i)USB\\') {
        if ($Description -match '^(?i)Realtek(?:\(R\))? USB Audio$') {
            return [pscustomobject]@{ Kind = 'RealtekUsbFallback'; Description = $Description; Reason = 'kodek Realtek korzystający ze ścieżki USB' }
        }
        return [pscustomobject]@{ Kind = 'Skip'; Description = $Description; Reason = 'urządzenie audio USB' }
    }
    if ($PnpDeviceId -match '^(?i)(?:INTELAUDIO|HDAUDIO)\\FUNC_') {
        return [pscustomobject]@{ Kind = 'Codec'; Description = $Description; Reason = 'wewnętrzny kodek audio' }
    }
    return [pscustomobject]@{ Kind = 'Skip'; Description = $Description; Reason = 'nierozpoznane urządzenie audio' }
}

function Write-SoundDeviceHealthWarning {
    param([Parameter(Mandatory)][psobject]$Device)

    $Description = Get-SoundDeviceDescription -Device $Device
    $Status = [string](Get-OptionalPropertyValue -InputObject $Device -Name 'Status')
    $ErrorCode = Get-OptionalPropertyValue -InputObject $Device -Name 'ConfigManagerErrorCode'
    if ((-not [string]::IsNullOrWhiteSpace($Status) -and $Status -ne 'OK') -or
        ($null -ne $ErrorCode -and [int]$ErrorCode -ne 0)) {
        $StatusText = if ([string]::IsNullOrWhiteSpace($Status)) { 'brak danych' } else { $Status }
        $CodeText = if ($null -eq $ErrorCode) { 'brak danych' } else { [string]$ErrorCode }
        Write-Warning "Urządzenie audio '$Description' zgłasza Status=$StatusText, ConfigManagerErrorCode=$CodeText."
    }
}

function Get-SoundInventoryParts {
    $Parts = New-Object System.Collections.Generic.List[object]
    $Codecs = New-Object System.Collections.Generic.List[object]
    $UsbFallbacks = New-Object System.Collections.Generic.List[object]
    $Devices = @()

    try { $Devices = @(Get-CimInstance -ClassName Win32_SoundDevice -ErrorAction Stop) }
    catch {
        Write-Warning "Nie udało się odczytać kart dźwiękowych: $($_.Exception.Message)"
        return $Parts.ToArray()
    }

    foreach ($Device in $Devices) {
        try {
            Write-SoundDeviceHealthWarning -Device $Device
            $Classification = Get-SoundDeviceClassification -Device $Device
            switch ($Classification.Kind) {
                'Codec' { $Codecs.Add([pscustomobject]@{ Device = $Device; Classification = $Classification }) }
                'RealtekUsbFallback' { $UsbFallbacks.Add([pscustomobject]@{ Device = $Device; Classification = $Classification }) }
                default {
                    $DisplayName = if ([string]::IsNullOrWhiteSpace([string]$Classification.Description)) { '(bez nazwy)' } else { $Classification.Description }
                    Write-Host "Pominięto urządzenie audio '$DisplayName': $($Classification.Reason)." -ForegroundColor DarkGray
                }
            }
        }
        catch {
            $Identity = Get-SoundDeviceDescription -Device $Device
            Write-Warning "Pominięto urządzenie audio '$Identity': $($_.Exception.Message)"
        }
    }

    if ($Codecs.Count -gt 0) {
        $MainCodec = @($Codecs.ToArray() | Sort-Object @{ Expression = { if ($_.Classification.Description -match '(?i)Realtek') { 0 } else { 1 } } } | Select-Object -First 1)[0]
        $Parts.Add((New-HardwarePart -Type 'Sound Card' -Description $MainCodec.Classification.Description -Connection 'on board'))
        foreach ($AdditionalCodec in @($Codecs.ToArray() | Where-Object { $_ -ne $MainCodec })) {
            Write-Host "Pominięto dodatkowe urządzenie audio '$($AdditionalCodec.Classification.Description)': wybrano główny kodek '$($MainCodec.Classification.Description)'." -ForegroundColor DarkGray
        }
        foreach ($UsbDevice in $UsbFallbacks.ToArray()) {
            Write-Host "Pominięto urządzenie audio '$($UsbDevice.Classification.Description)': wykryto już główny kodek '$($MainCodec.Classification.Description)'." -ForegroundColor DarkGray
        }
        return $Parts.ToArray()
    }

    if ($UsbFallbacks.Count -gt 0) {
        $Candidate = $UsbFallbacks[0]
        Write-Section -Title 'Weryfikacja karty dźwiękowej'
        Write-Host "Wykryto tylko: $($Candidate.Classification.Description)" -ForegroundColor Yellow
        Write-Host 'Urządzenie używa magistrali USB, ale może być wewnętrznym kodekiem laptopa.'
        Write-Host '[1] Zapisz jako wewnętrzną kartę dźwiękową'
        Write-Host '[2] Pomiń urządzenie'
        $Choice = Read-MenuChoice -Prompt 'Wybierz operację [1-2]' -Minimum 1 -Maximum 2
        if ($Choice -eq 1) {
            $Parts.Add((New-HardwarePart -Type 'Sound Card' -Description $Candidate.Classification.Description -Connection 'on board'))
        }
        return $Parts.ToArray()
    }

    Write-Warning 'Nie wykryto głównego wewnętrznego kodeka audio.'
    return $Parts.ToArray()
}

function Get-BatteryReportData {
    $TemporaryPath = Join-Path ([IO.Path]::GetTempPath()) ("GetHardware-battery-$([guid]::NewGuid().ToString('N')).xml")
    try {
        $null = & powercfg.exe /batteryreport /xml /output $TemporaryPath 2>&1
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $TemporaryPath -PathType Leaf)) {
            throw 'Polecenie powercfg nie utworzyło raportu baterii.'
        }

        $Report = New-Object Xml.XmlDocument
        $Report.Load($TemporaryPath)
        return @($Report.BatteryReport.Batteries.Battery)
    }
    finally {
        if (Test-Path -LiteralPath $TemporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $TemporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function ConvertTo-BatteryNumber {
    param([AllowNull()]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    $Number = 0.0
    if ([double]::TryParse([string]$Value, [Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture, [ref]$Number)) { return $Number }
    if ([double]::TryParse([string]$Value, [ref]$Number)) { return $Number }
    return $null
}

function Find-Win32BatteryForReport {
    param(
        [Parameter(Mandatory)][psobject]$ReportBattery,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Win32Batteries
    )

    $ReportId = ([string](Get-OptionalPropertyValue -InputObject $ReportBattery -Name 'Id')).Trim()
    if (-not [string]::IsNullOrWhiteSpace($ReportId)) {
        $Match = $Win32Batteries | Where-Object {
            ([string](Get-OptionalPropertyValue -InputObject $_ -Name 'Name')).Trim() -ieq $ReportId -or
            ([string](Get-OptionalPropertyValue -InputObject $_ -Name 'DeviceID')) -like "*$ReportId*"
        } | Select-Object -First 1
        if ($null -ne $Match) { return $Match }
    }
    if ($Win32Batteries.Count -eq 1) { return $Win32Batteries[0] }
    return $null
}

function New-BatteryInventoryPart {
    param(
        [AllowNull()][psobject]$ReportBattery,
        [AllowNull()][psobject]$Win32Battery
    )

    $DeviceName = ''
    $Manufacturer = ''
    $DesignCapacity = $null
    $FullChargeCapacity = $null
    $CycleCount = $null
    if ($null -ne $ReportBattery) {
        $DeviceName = ([string](Get-OptionalPropertyValue -InputObject $ReportBattery -Name 'Id')).Trim()
        $Manufacturer = ([string](Get-OptionalPropertyValue -InputObject $ReportBattery -Name 'Manufacturer')).Trim()
        $DesignCapacity = ConvertTo-BatteryNumber -Value (Get-OptionalPropertyValue -InputObject $ReportBattery -Name 'DesignCapacity')
        $FullChargeCapacity = ConvertTo-BatteryNumber -Value (Get-OptionalPropertyValue -InputObject $ReportBattery -Name 'FullChargeCapacity')
        $RawCycleCount = ConvertTo-BatteryNumber -Value (Get-OptionalPropertyValue -InputObject $ReportBattery -Name 'CycleCount')
        # Przy zużytej baterii wartość 0 zwykle oznacza brak obsługi licznika,
        # dlatego nie prezentujemy jej jako rzeczywistych zero cykli.
        if ($null -ne $RawCycleCount -and $RawCycleCount -gt 0) { $CycleCount = [int64]$RawCycleCount }
    }
    if ([string]::IsNullOrWhiteSpace($DeviceName) -and $null -ne $Win32Battery) {
        $DeviceName = ([string](Get-OptionalPropertyValue -InputObject $Win32Battery -Name 'Name')).Trim()
    }

    $HealthPercent = $null
    $WearPercent = $null
    if ($null -ne $DesignCapacity -and $null -ne $FullChargeCapacity -and $DesignCapacity -gt 0 -and $FullChargeCapacity -gt 0) {
        $HealthPercent = [math]::Round(($FullChargeCapacity / $DesignCapacity) * 100, 1)
        $WearPercent = [math]::Round(100 - $HealthPercent, 1)
        if ($HealthPercent -lt 80) {
            Write-Warning "Kondycja baterii '$DeviceName' wynosi tylko $($HealthPercent.ToString('0.0', [Globalization.CultureInfo]::CurrentCulture))%."
        }
    }

    $Status = if ($null -ne $Win32Battery) {
        [string](Get-OptionalPropertyValue -InputObject $Win32Battery -Name 'Status')
    } else { '' }
    if (-not [string]::IsNullOrWhiteSpace($Status) -and $Status -ne 'OK') {
        Write-Warning "Bateria '$DeviceName' zgłasza Status: $Status."
    }

    $ChargePercent = if ($null -ne $Win32Battery) {
        ConvertTo-BatteryNumber -Value (Get-OptionalPropertyValue -InputObject $Win32Battery -Name 'EstimatedChargeRemaining')
    } else { $null }
    $VoltageMv = if ($null -ne $Win32Battery) {
        ConvertTo-BatteryNumber -Value (Get-OptionalPropertyValue -InputObject $Win32Battery -Name 'DesignVoltage')
    } else { $null }

    # Numer seryjny baterii jest celowo ignorowany. Użytkownik skanuje go
    # bezpośrednio z etykiety, a importer oczekuje pustego pola sn.
    $Part = New-HardwarePart -Type 'Battery' -Description 'Internal Battery' -Connection '' -SerialNumber ''
    $Part | Add-Member -NotePropertyName BatteryDeviceName -NotePropertyValue $DeviceName
    $Part | Add-Member -NotePropertyName BatteryManufacturer -NotePropertyValue $Manufacturer
    $Part | Add-Member -NotePropertyName BatteryDesignCapacityMWh -NotePropertyValue $DesignCapacity
    $Part | Add-Member -NotePropertyName BatteryFullChargeCapacityMWh -NotePropertyValue $FullChargeCapacity
    $Part | Add-Member -NotePropertyName BatteryHealthPercent -NotePropertyValue $HealthPercent
    $Part | Add-Member -NotePropertyName BatteryWearPercent -NotePropertyValue $WearPercent
    $Part | Add-Member -NotePropertyName BatteryCycleCount -NotePropertyValue $CycleCount
    $Part | Add-Member -NotePropertyName BatteryStatus -NotePropertyValue $Status
    $Part | Add-Member -NotePropertyName BatteryChargePercent -NotePropertyValue $ChargePercent
    $Part | Add-Member -NotePropertyName BatteryVoltageMv -NotePropertyValue $VoltageMv
    return $Part
}

function Get-BatteryInventoryParts {
    $Parts = New-Object System.Collections.Generic.List[object]
    $Win32Batteries = @()
    $ReportBatteries = @()

    try { $Win32Batteries = @(Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop) }
    catch { Write-Warning "Nie udało się odczytać baterii z Win32_Battery: $($_.Exception.Message)" }
    try { $ReportBatteries = @(Get-BatteryReportData) }
    catch { Write-Warning "Nie udało się odczytać raportu baterii z powercfg: $($_.Exception.Message)" }

    if ($ReportBatteries.Count -gt 0) {
        foreach ($ReportBattery in $ReportBatteries) {
            try {
                $Win32Battery = Find-Win32BatteryForReport -ReportBattery $ReportBattery -Win32Batteries $Win32Batteries
                $Parts.Add((New-BatteryInventoryPart -ReportBattery $ReportBattery -Win32Battery $Win32Battery))
            }
            catch {
                $Identity = [string](Get-OptionalPropertyValue -InputObject $ReportBattery -Name 'Id')
                Write-Warning "Pominięto baterię '$Identity': $($_.Exception.Message)"
            }
        }
        return $Parts.ToArray()
    }

    foreach ($Win32Battery in $Win32Batteries) {
        try { $Parts.Add((New-BatteryInventoryPart -ReportBattery $null -Win32Battery $Win32Battery)) }
        catch {
            $Identity = [string](Get-OptionalPropertyValue -InputObject $Win32Battery -Name 'Name')
            Write-Warning "Pominięto baterię '$Identity': $($_.Exception.Message)"
        }
    }
    return $Parts.ToArray()
}

function Get-GraphicsDescription {
    param([Parameter(Mandatory)][psobject]$Graphics)

    $Caption = ([string](Get-OptionalPropertyValue -InputObject $Graphics -Name 'Caption')).Trim()
    if ([string]::IsNullOrWhiteSpace($Caption)) {
        $Caption = ([string](Get-OptionalPropertyValue -InputObject $Graphics -Name 'Name')).Trim()
    }
    if ([string]::IsNullOrWhiteSpace($Caption)) { return 'QQ_POPRAW' }
    return ($Caption -replace '\s+', ' ').Trim()
}

function Get-GraphicsAdapterKind {
    param([Parameter(Mandatory)][psobject]$Graphics)

    $Identity = (@(
        Get-GraphicsDescription -Graphics $Graphics
        [string](Get-OptionalPropertyValue -InputObject $Graphics -Name 'VideoProcessor')
    ) -join ' ').Trim()

    if ($Identity -match '(?i)Intel(?:\(R\))?.*\b(?:UHD|Iris|HD)\b.*Graphics|Intel.*Graphics Family|AMD Radeon\(TM\) Graphics|Radeon Vega \d+ Graphics') {
        return 'Integrated'
    }
    if ($Identity -match '(?i)\bNVIDIA\b|\bGeForce\b|\bQuadro\b|\bTesla\b|Radeon\s+(?:RX|PRO\s+W|Pro\s+WX|R9\b)') {
        return 'Dedicated'
    }
    return 'Unknown'
}

function Resolve-GraphicsAdapterKind {
    param([Parameter(Mandatory)][psobject]$Graphics)

    $Kind = Get-GraphicsAdapterKind -Graphics $Graphics
    if ($Kind -ne 'Unknown') { return $Kind }

    $Description = Get-GraphicsDescription -Graphics $Graphics
    Write-Section -Title 'Typ karty graficznej'
    Write-Warning "Nie udało się jednoznacznie sklasyfikować karty '$Description'."
    Write-Host '[1] Grafika zintegrowana'
    Write-Host '[2] Grafika dedykowana'
    $Choice = Read-MenuChoice -Prompt 'Wybierz typ karty [1-2]' -Minimum 1 -Maximum 2
    if ($Choice -eq 1) { return 'Integrated' }
    return 'Dedicated'
}

function Write-GraphicsHealthWarning {
    param([Parameter(Mandatory)][psobject]$Graphics)

    $Description = Get-GraphicsDescription -Graphics $Graphics
    $Status = [string](Get-OptionalPropertyValue -InputObject $Graphics -Name 'Status')
    $ErrorCode = Get-OptionalPropertyValue -InputObject $Graphics -Name 'ConfigManagerErrorCode'
    if ((-not [string]::IsNullOrWhiteSpace($Status) -and $Status -ne 'OK') -or
        ($null -ne $ErrorCode -and [int]$ErrorCode -ne 0)) {
        $StatusText = if ([string]::IsNullOrWhiteSpace($Status)) { 'brak danych' } else { $Status }
        $CodeText = if ($null -eq $ErrorCode) { 'brak danych' } else { [string]$ErrorCode }
        Write-Warning "Karta graficzna '$Description' zgłasza Status=$StatusText, ConfigManagerErrorCode=$CodeText."
    }
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
        $Placements[0] -ne 'unknown'
    )
    if ($SpecReliable) {
        if ($Placements[0] -eq 'soldered') {
            $DetectedSpec = "$($Types[0]) $($Speeds[0])MHz soldered"
        }
        elseif ($MemoryDeviceCount -gt 0) {
            $DetectedSpec = "$($Types[0]) $($Speeds[0])MHz x$MemoryDeviceCount"
        }
        else {
            $SpecReliable = $false
        }
    }

    return [pscustomobject]@{
        Parts         = $Parts.ToArray()
        DetectedSpec  = $DetectedSpec
        SpecReliable  = $SpecReliable
        ReportedMaximumCapacityGb = $MaximumCapacityGb
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

function Get-MemorySpecMaximumText {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $Match = [regex]::Match($Value, '(?i)(?:^|[\s,;(])max\s*(?<capacity>\d+(?:[.,]\d+)?)\s*GB\b')
    if (-not $Match.Success) { return '' }
    $Capacity = $Match.Groups['capacity'].Value.Replace(',', '.')
    return "max${Capacity}GB"
}

function Test-MemorySpecHasMaximum {
    param([AllowNull()][string]$Value)

    return -not [string]::IsNullOrWhiteSpace((Get-MemorySpecMaximumText -Value $Value))
}

function Read-CompleteMemorySpec {
    param(
        [Parameter(Mandatory)][string]$Model,
        [AllowNull()][string]$DetectedSpec
    )

    while ($true) {
        $Value = Read-TextValue -Prompt 'Wpisz pełną konfigurację pamięci, łącznie z maksymalną pojemnością (np. DDR4 3200MHz x2, max64GB)' -Default $null
        if (Test-MemorySpecHasMaximum -Value $Value) { return $Value.Trim() }
        Write-Warning "Pole memorySpec dla modelu '$Model' musi zawierać maksymalną pojemność w formacie max...GB, np. max64GB."
        if (-not [string]::IsNullOrWhiteSpace($DetectedSpec)) {
            Write-Host "Dane wykryte automatycznie: $DetectedSpec" -ForegroundColor DarkGray
        }
    }
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
    Write-ModelDatabase -Path $DatabasePath -Models $Models
    Write-Host "Zaktualizowano memorySpec dla modelu '$Model' w hardware-models.json." -ForegroundColor Green
}

function Resolve-MemorySpec {
    param(
        [Parameter(Mandatory)][psobject]$ModelEntry,
        [Parameter(Mandatory)][psobject]$MemoryInventory,
        [Parameter(Mandatory)][string]$DatabasePath
    )

    $DatabaseSpec = ([string]$ModelEntry.memorySpec).Trim()
    $DetectedBaseSpec = ([string]$MemoryInventory.DetectedSpec).Trim()
    $DetectedReliable = [bool]$MemoryInventory.SpecReliable -and -not [string]::IsNullOrWhiteSpace($DetectedBaseSpec)

    if (-not (Test-MemorySpecHasMaximum -Value $DatabaseSpec)) {
        Write-Section -Title 'Konfiguracja pamięci w płycie głównej'
        Write-Warning "Pole memorySpec dla modelu '$($ModelEntry.model)' nie zawiera maksymalnej obsługiwanej pamięci."
        if ($DetectedReliable) {
            Write-Host "Dane wykryte automatycznie: $DetectedBaseSpec" -ForegroundColor Green
        }
        Write-Host 'Uzupełnij pełną specyfikację na podstawie dokumentacji producenta, np. DDR4 3200MHz x2, max64GB.'
        $CustomSpec = Read-CompleteMemorySpec -Model ([string]$ModelEntry.model) -DetectedSpec $DetectedBaseSpec
        Write-Host '[1] Zapisz tę wartość w JSON'
        Write-Host '[2] Użyj jej tylko dla tego komputera'
        $SaveChoice = Read-MenuChoice -Prompt 'Wybierz operację [1-2]' -Minimum 1 -Maximum 2
        if ($SaveChoice -eq 1) {
            Set-ModelMemorySpec -DatabasePath $DatabasePath -Model ([string]$ModelEntry.model) -MemorySpec $CustomSpec
            $ModelEntry.memorySpec = $CustomSpec
        }
        return $CustomSpec
    }

    $MaximumText = Get-MemorySpecMaximumText -Value $DatabaseSpec
    $DetectedSpec = if ($DetectedReliable) { "$DetectedBaseSpec, $MaximumText" } else { '' }

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

    # EKRANY: każde źródło WMI jest odczytywane osobno, a rekordy są łączone
    # wyłącznie po InstanceName. Do PHP dla matrycy trafiają tylko przekątna,
    # natywna rozdzielczość, opcjonalne `touch` oraz połączenie `on board`.
    $MonitorIds = @()
    $DisplayParameters = @()
    $ConnectionParameters = @()
    $ModeLists = @()
    $TouchDetected = $false
    try { $MonitorIds = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop) }
    catch { Write-Warning "Nie udało się odczytać identyfikacji ekranów: $($_.Exception.Message)" }
    try { $DisplayParameters = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBasicDisplayParams -ErrorAction Stop) }
    catch { Write-Warning "Nie udało się odczytać fizycznego rozmiaru ekranów: $($_.Exception.Message)" }
    try { $ConnectionParameters = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams -ErrorAction Stop) }
    catch { Write-Warning "Nie udało się odczytać typu połączenia ekranów: $($_.Exception.Message)" }
    try { $ModeLists = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorListedSupportedSourceModes -ErrorAction Stop) }
    catch { Write-Warning "Nie udało się odczytać natywnej rozdzielczości ekranów: $($_.Exception.Message)" }
    try { $TouchDetected = Test-TouchScreenDetected }
    catch { Write-Warning "Nie udało się sprawdzić obsługi dotyku: $($_.Exception.Message)" }

    foreach ($DisplayPart in @(ConvertTo-DisplayParts `
        -MonitorIds $MonitorIds `
        -DisplayParameters $DisplayParameters `
        -ConnectionParameters $ConnectionParameters `
        -ModeLists $ModeLists `
        -TouchDetected $TouchDetected)) {
        $Parts.Add($DisplayPart)
    }

    # PAMIĘĆ RAM: pamięć lutowana jest grupowana, a wymienne moduły pozostają
    # osobnymi wpisami. Dla pamięci niewlutowanej importer oczekuje `on board`.
    if ($null -eq $MemoryInventory) {
        $MemoryInventory = Get-MemoryInventory
    }
    foreach ($MemoryPart in @($MemoryInventory.Parts)) {
        $Parts.Add($MemoryPart)
    }

    # DYSKI: Get-PhysicalDisk dostarcza magistralę, typ nośnika, stan i stabilne
    # identyfikatory. Format fizyczny jest odczytywany natywnym zapytaniem Windows;
    # gdy sterownik go nie udostępnia, użytkownik zatwierdza podpowiedź z BusType.
    # Pojemność pozostaje dziesiętna, zgodna z oznaczeniami producentów.
    foreach ($DiskPart in @(Get-DiskInventoryParts)) {
        $Parts.Add($DiskPart)
    }

    # SIEĆ: Get-NetAdapter pozwala rozróżnić sprzętowe i wirtualne interfejsy
    # oraz preferować trwały PermanentAddress. Zachowujemy wbudowane adaptery
    # Ethernet/Wi-Fi i Bluetooth PAN. Zewnętrzne adaptery USB oraz interfejsy
    # systemowe, VPN i wirtualne są pomijane z czytelną informacją.
    foreach ($NetworkPart in @(Get-NetworkInventoryParts)) {
        $Parts.Add($NetworkPart)
    }

    # DŹWIĘK: zapisujemy jeden główny wewnętrzny kodek. Kontrolery Intel SST,
    # audio HDMI/DisplayPort, Bluetooth i zewnętrzne urządzenia USB nie tworzą
    # osobnych rekordów PHP. Samotny Realtek USB Audio wymaga potwierdzenia,
    # ponieważ w części laptopów jest to kodek podłączony wewnętrznie przez USB.
    foreach ($SoundPart in @(Get-SoundInventoryParts)) {
        $Parts.Add($SoundPart)
    }

    # GRAFIKA: AdapterRAM nie jest wiarygodnym rozmiarem VRAM, szczególnie dla
    # układów zintegrowanych, dlatego nie trafia do opisu PHP. Typowe układy są
    # klasyfikowane automatycznie, a niejednoznaczne wymagają wyboru użytkownika.
    # Wyjścia laptopa nadal są wpisywane ręcznie, ponieważ Windows nie przypisuje
    # ich wiarygodnie do konkretnego GPU.
    try {
        foreach ($Graphics in @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop)) {
            try {
                if (-not (Test-PhysicalGraphicsAdapter -Graphics $Graphics)) {
                    $SkippedName = [string](Get-OptionalPropertyValue -InputObject $Graphics -Name 'Caption')
                    Write-Host "Pominięto adapter graficzny: $SkippedName" -ForegroundColor DarkGray
                    continue
                }

                Write-GraphicsHealthWarning -Graphics $Graphics
                $Description = Get-GraphicsDescription -Graphics $Graphics
                $GraphicsKind = Resolve-GraphicsAdapterKind -Graphics $Graphics
                $GraphicsKindText = if ($GraphicsKind -eq 'Integrated') { 'zintegrowana' } else { 'dedykowana' }
                Write-Section -Title 'Wyjścia karty graficznej'
                Write-Host "Wykryta karta: $Description" -ForegroundColor Green
                Write-Host "Typ:           $GraphicsKindText"
                if ($GraphicsKind -eq 'Dedicated') {
                    Write-Host 'Pamięć VRAM nie została dodana: Win32_VideoController.AdapterRAM nie jest wystarczająco wiarygodnym źródłem.' -ForegroundColor DarkGray
                }
                $Connection = Read-TextValue `
                    -Prompt 'Wpisz połączenia/wyjścia graficzne, oddzielając je przecinkami (np. on board,HDMI,DisplayPort,USB-C)' `
                    -Default 'on board'
                $Parts.Add((New-HardwarePart -Type 'Graphic Card' -Description $Description -Connection $Connection))
            }
            catch {
                $Identity = [string](Get-OptionalPropertyValue -InputObject $Graphics -Name 'Caption')
                Write-Warning "Pominięto kartę graficzną '$Identity': $($_.Exception.Message)"
            }
        }
    }
    catch {
        Write-Warning "Nie udało się odczytać kart graficznych: $($_.Exception.Message)"
    }

    # BATERIA: powercfg dostarcza pojemność projektową i pełną, a Win32_Battery
    # bieżący stan, naładowanie i napięcie. Do PHP trafia wyłącznie prosty wpis
    # Internal Battery z celowo pustym polem sn. Brak baterii jest prawidłowy dla
    # komputerów stacjonarnych.
    foreach ($BatteryPart in @(Get-BatteryInventoryParts)) {
        $Parts.Add($BatteryPart)
    }

    if ($Parts.Count -eq 0) {
        throw 'Nie udało się wykryć żadnego podzespołu.'
    }

    # W Windows PowerShell 5.1 użycie @($Parts) dla List[object]
    # zawierającej PSCustomObject kończy się błędem "Argument types do not match".
    # ToArray() wykonuje jednoznaczną i zgodną konwersję.
    return $Parts.ToArray()
}

function Format-DiskPowerOnTime {
    param([AllowNull()]$Hours)

    if ($null -eq $Hours -or [string]::IsNullOrWhiteSpace([string]$Hours)) { return 'brak danych' }
    try { $NumericHours = [decimal]$Hours }
    catch { return 'brak danych' }
    if ($NumericHours -lt 0) { return 'brak danych' }

    $Culture = [Globalization.CultureInfo]::CurrentCulture
    $HoursText = $NumericHours.ToString('0', $Culture)
    $DaysText = ($NumericHours / 24).ToString('0.0', $Culture)
    return "$HoursText h ($DaysText dni)"
}

function Format-DiskDataAmount {
    param([AllowNull()]$Bytes)

    if ($null -eq $Bytes -or [string]::IsNullOrWhiteSpace([string]$Bytes)) { return 'brak danych' }
    try { $NumericBytes = [decimal]$Bytes }
    catch { return 'brak danych' }
    if ($NumericBytes -lt 0) { return 'brak danych' }

    $Culture = [Globalization.CultureInfo]::CurrentCulture
    if ($NumericBytes -ge 1000000000000) {
        return "$(($NumericBytes / 1000000000000).ToString('0.00', $Culture)) TB"
    }
    if ($NumericBytes -ge 1000000000) {
        return "$(($NumericBytes / 1000000000).ToString('0.00', $Culture)) GB"
    }
    if ($NumericBytes -ge 1000000) {
        return "$(($NumericBytes / 1000000).ToString('0.00', $Culture)) MB"
    }
    return "$($NumericBytes.ToString('0', $Culture)) B"
}

function Format-DiskWearLevel {
    param([AllowNull()]$WearPercent)

    if ($null -eq $WearPercent -or [string]::IsNullOrWhiteSpace([string]$WearPercent)) { return 'brak danych' }
    try { $NumericWear = [decimal]$WearPercent }
    catch { return 'brak danych' }
    if ($NumericWear -lt 0) { return 'brak danych' }
    return "$($NumericWear.ToString('0.##', [Globalization.CultureInfo]::CurrentCulture))%"
}

function Show-DiskHealthInformation {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Parts)

    foreach ($Disk in @($Parts | Where-Object Pt -EQ 'Hard Disk')) {
        $Health = [string](Get-OptionalPropertyValue -InputObject $Disk -Name 'DiskHealthStatus')
        if ([string]::IsNullOrWhiteSpace($Health)) { $Health = 'brak danych' }

        Write-Section -Title 'Stan dysku'
        Write-Host "Dysk:         $($Disk.Desc)"
        Write-Host "HealthStatus: $Health"
        Write-Host "Czas pracy:   $(Format-DiskPowerOnTime -Hours (Get-OptionalPropertyValue -InputObject $Disk -Name 'DiskPowerOnHours'))"
        Write-Host "Odczytano:    $(Format-DiskDataAmount -Bytes (Get-OptionalPropertyValue -InputObject $Disk -Name 'DiskBytesRead'))"
        Write-Host "Zapisano:     $(Format-DiskDataAmount -Bytes (Get-OptionalPropertyValue -InputObject $Disk -Name 'DiskBytesWritten'))"
        Write-Host "Wear level:   $(Format-DiskWearLevel -WearPercent (Get-OptionalPropertyValue -InputObject $Disk -Name 'DiskWearPercent'))"
    }
}

function Format-BatteryCapacity {
    param([AllowNull()]$CapacityMWh)

    if ($null -eq $CapacityMWh -or [string]::IsNullOrWhiteSpace([string]$CapacityMWh)) { return 'brak danych' }
    try { $CapacityWh = [double]$CapacityMWh / 1000 }
    catch { return 'brak danych' }
    if ($CapacityWh -lt 0) { return 'brak danych' }
    return "$($CapacityWh.ToString('0.000', [Globalization.CultureInfo]::CurrentCulture)) Wh"
}

function Format-BatteryPercent {
    param([AllowNull()]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return 'brak danych' }
    try { $Percent = [double]$Value }
    catch { return 'brak danych' }
    if ($Percent -lt 0) { return 'brak danych' }
    return "$($Percent.ToString('0.0', [Globalization.CultureInfo]::CurrentCulture))%"
}

function Format-BatteryVoltage {
    param([AllowNull()]$VoltageMv)

    if ($null -eq $VoltageMv -or [string]::IsNullOrWhiteSpace([string]$VoltageMv)) { return 'brak danych' }
    try { $VoltageV = [double]$VoltageMv / 1000 }
    catch { return 'brak danych' }
    if ($VoltageV -le 0) { return 'brak danych' }
    return "$($VoltageV.ToString('0.000', [Globalization.CultureInfo]::CurrentCulture)) V"
}

function Show-BatteryHealthInformation {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Parts)

    foreach ($Battery in @($Parts | Where-Object Pt -EQ 'Battery')) {
        $DeviceName = [string](Get-OptionalPropertyValue -InputObject $Battery -Name 'BatteryDeviceName')
        if ([string]::IsNullOrWhiteSpace($DeviceName)) { $DeviceName = 'Internal Battery' }
        $Manufacturer = [string](Get-OptionalPropertyValue -InputObject $Battery -Name 'BatteryManufacturer')
        if ([string]::IsNullOrWhiteSpace($Manufacturer)) { $Manufacturer = 'brak danych' }
        $Status = [string](Get-OptionalPropertyValue -InputObject $Battery -Name 'BatteryStatus')
        if ([string]::IsNullOrWhiteSpace($Status)) { $Status = 'brak danych' }
        $CycleCount = Get-OptionalPropertyValue -InputObject $Battery -Name 'BatteryCycleCount'
        $CycleText = if ($null -eq $CycleCount) { 'brak danych' } else { [string]$CycleCount }

        Write-Section -Title 'Stan baterii'
        Write-Host "Bateria:              $DeviceName"
        Write-Host "Producent:             $Manufacturer"
        Write-Host "Pojemność projektowa:  $(Format-BatteryCapacity -CapacityMWh (Get-OptionalPropertyValue -InputObject $Battery -Name 'BatteryDesignCapacityMWh'))"
        Write-Host "Pełna pojemność:       $(Format-BatteryCapacity -CapacityMWh (Get-OptionalPropertyValue -InputObject $Battery -Name 'BatteryFullChargeCapacityMWh'))"
        Write-Host "Kondycja:              $(Format-BatteryPercent -Value (Get-OptionalPropertyValue -InputObject $Battery -Name 'BatteryHealthPercent'))"
        Write-Host "Zużycie:               $(Format-BatteryPercent -Value (Get-OptionalPropertyValue -InputObject $Battery -Name 'BatteryWearPercent'))"
        Write-Host "Liczba cykli:          $CycleText"
        Write-Host "Stan urządzenia:       $Status"
        Write-Host "Poziom naładowania:    $(Format-BatteryPercent -Value (Get-OptionalPropertyValue -InputObject $Battery -Name 'BatteryChargePercent'))"
        Write-Host "Napięcie:              $(Format-BatteryVoltage -VoltageMv (Get-OptionalPropertyValue -InputObject $Battery -Name 'BatteryVoltageMv'))"
    }
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

    Show-DiskHealthInformation -Parts $Parts
    Show-BatteryHealthInformation -Parts $Parts

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
    $Connection = Read-TextValue -Prompt 'Połączenie (opcjonalnie)' -Default $ConnectionDefault -AllowEmpty
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
        if ($Part.Pt -eq 'Battery' -or -not [string]::IsNullOrWhiteSpace([string]$Part.Sn)) {
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
    $SupportUrl = Get-DellSupportUrl -Manufacturer $Inventory.Manufacturer -ServiceTag $Inventory.ServiceTag
    if (-not [string]::IsNullOrWhiteSpace($SupportUrl)) {
        $Lines.Add("#$SupportUrl")
    }
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

    $IdentifierSuffix = if ($Inventory.DeviceType -in @('laptop', 'tablet')) { '_laptop' } else { '' }
    Write-Section -Title 'Typ urządzenia'
    Write-Host "Typ z bazy modeli:  $($Inventory.DatabaseDeviceType)"
    Write-Host "Typ obudowy SMBIOS: $($Inventory.ChassisDescription)"
    $DetectedText = if ([string]::IsNullOrWhiteSpace([string]$Inventory.DetectedDeviceType)) {
        'Nieznany'
    } else {
        [string]$Inventory.DetectedDeviceType
    }
    Write-Host "Typ wykryty:         $DetectedText"
    Write-Host "Typ użyty w PHP:     $($Inventory.DeviceType)" -ForegroundColor Green
    Write-Host "Identyfikator PHP:   $($Inventory.ServiceTag)$IdentifierSuffix"
}

function Invoke-HardwareInventory {
    Confirm-InventoryEnvironment
    $System = Get-SystemOverview
    if ([string]::IsNullOrWhiteSpace($System.Model)) {
        throw 'Nie udało się odczytać modelu komputera.'
    }

    $ServiceTag = Resolve-ServiceTag -DetectedValue $System.ServiceTag
    Open-DellSupportPage -Manufacturer $System.Manufacturer -ServiceTag $ServiceTag
    Write-Host "Wykryty model: $($System.Model)" -ForegroundColor Green
    $MemoryInventory = Get-MemoryInventory
    $ModelEntry = Wait-ForKnownModel `
        -Model $System.Model `
        -DatabasePath $ModelDatabasePath `
        -MemoryInventory $MemoryInventory `
        -DetectedDeviceType $System.DetectedDeviceType
    $ResolvedDeviceType = Resolve-DeviceType `
        -DatabaseDeviceType ([string]$ModelEntry.deviceType) `
        -DetectedDeviceType $System.DetectedDeviceType `
        -ChassisDescription $System.ChassisDescription
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
            DatabaseDeviceType = [string]$ModelEntry.deviceType
            ChassisDescription = $System.ChassisDescription
            DetectedDeviceType = $System.DetectedDeviceType
            DeviceType    = $ResolvedDeviceType
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
