# GetHardware

Interaktywny skrypt Windows PowerShell 5.1 odczytujący informacje o sprzęcie i zapisujący je w plikach PHP przeznaczonych do importu do istniejącej bazy.

## Wymagania

- Windows PowerShell 5.1;
- dostęp do poleceń CIM/WMI;
- możliwość odczytu urządzeń PnP;
- pliki `Get-HardwareInventory.ps1` i `hardware-models.json` w tym samym katalogu.

## Uruchomienie

Otwórz Windows PowerShell w katalogu projektu i uruchom:

```powershell
.\Get-HardwareInventory.ps1
```

Skrypt nie przyjmuje nazwy spisu jako parametru. Przy pierwszym uruchomieniu prosi o jej wpisanie. Przy kolejnych uruchomieniach wyświetla istniejące spisy i opcję utworzenia nowego.

## Przebieg

1. Odczyt modelu, Service Tagu, procesora i pozostałych podzespołów.
2. Sprawdzenie modelu w `hardware-models.json`.
3. Wybór istniejącego spisu albo utworzenie nowego.
4. Odczyt wspólnego pola `bought` z istniejącego spisu albo pytanie o nie dla nowego spisu.
5. Przegląd, edycja, dodawanie lub usuwanie wykrytych podzespołów.
6. Wprowadzenie gwarancji, ceny, etykiety Windows, pomieszczenia i notatki.
7. Wyświetlenie podsumowania i zapis po zatwierdzeniu.

Nieznany model zatrzymuje przebieg. Po ręcznym dodaniu modelu do JSON-u można nacisnąć Enter, aby skrypt ponownie wczytał bazę bez rozpoczynania pracy od początku.

## Pliki wynikowe

Wyniki trafiają zawsze do katalogu `output` obok uruchomionego skryptu:

```text
output\
└── BI_ONE\
    ├── .gethardware.lock
    ├── 13QJ7D3.php
    ├── 8ABC123.php
    └── BI_ONE.php
```

- plik nazwany Service Tagiem zawiera jedno urządzenie;
- plik nazwany tak jak spis zawiera wszystkie urządzenia w kolejności ich dodania;
- `.gethardware.lock` chroni spis przed jednoczesnym zapisem przez dwa uruchomienia skryptu;
- pliki PHP są kodowane jako UTF-8 bez BOM.

W pliku zbiorczym rekordy są otoczone komentarzami `GET-HARDWARE-BEGIN` i `GET-HARDWARE-END`. Pozwala to zastąpić istniejący Service Tag bez zmiany jego pozycji. Komentarze są prawidłowymi komentarzami PHP i nie wpływają na import.

## Ręczna baza modeli

`hardware-models.json` jest listą obiektów:

```json
{
  "model": "Latitude 7420",
  "mainboard": "Latitude 7420 (DDR3L 1600MHz x2, max8GB)",
  "powerMaxW": 65,
  "powerW": 45,
  "other": "no Eth; zasilacz USB-C",
  "deviceType": "laptop"
}
```

Wszystkie pola są wymagane, a nazwa modelu musi być unikalna. Skrypt waliduje JSON przy wczytywaniu, ale nigdy nie zmienia go automatycznie.

## Walidacja danych ręcznych

- `bought`: `YYYY-MM-DD`, wspólne dla całego spisu;
- `warr`: `YYYY-MM-DD+N`, np. `2021-05-20+3`;
- `cenan`: kwota PLN z dwiema cyframi po przecinku, np. `1414,08`;
- `label`: interaktywny wybór `W10P` lub `W11P`;
- `room`: domyślnie `A216`;
- `note`: domyślny szablon `SCC:;REFURBISHED;`.

## Testy

Testy nie odczytują prawdziwego sprzętu. Sprawdzają bazę modeli, walidację podstawowych danych, generowanie PHP, kolejność rekordów, zastępowanie rekordu i kodowanie bez BOM:

```powershell
.\tests\Test-GetHardwareInventory.ps1
```

Automatyczny odczyt sprzętu należy sprawdzić na docelowym laptopie. Dane zwracane przez WMI, szczególnie pamięć karty graficznej, rodzaj osadzenia RAM i powiązanie rozdzielczości z ekranem EDID, mogą wymagać ręcznej korekty w interaktywnym przeglądzie.
