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

1. Potwierdzenie odłączenia dodatkowych monitorów, sesji pulpitu zdalnego, stacji dokujących i zewnętrznych urządzeń USB.
2. Odczyt modelu, Service Tagu, procesora, płyty głównej i pozostałych podzespołów.
3. Sprawdzenie modelu w `hardware-models.json`.
4. Wybór istniejącego spisu albo utworzenie nowego.
5. Odczyt wspólnego pola `bought` z istniejącego spisu albo pytanie o nie dla nowego spisu.
6. Przegląd, edycja, dodawanie lub usuwanie wykrytych podzespołów.
7. Wprowadzenie gwarancji, ceny, etykiety Windows, pomieszczenia i notatki.
8. Wyświetlenie podsumowania i zapis po zatwierdzeniu.

Nieznany model uruchamia interaktywny kreator wpisu. Skrypt automatycznie uzupełnia nazwę modelu, awaryjny opis płyty, wykrytą konfigurację pamięci i typ urządzenia. Użytkownik podaje zweryfikowaną maksymalną pojemność RAM, `powerMaxW`, `powerW` oraz `other`, a wpis trafia do JSON-u dopiero po pokazaniu podsumowania i zatwierdzeniu. Jeśli bazy nie można zapisać lub jest niepoprawna, nadal można poprawić ją ręcznie i wczytać ponownie bez rozpoczynania pracy od początku.

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
  "baseboardFallback": "Latitude 7420",
  "memorySpec": "DDR3L 1600MHz x2, max8GB",
  "powerMaxW": 65,
  "powerW": 45,
  "other": "no Eth; zasilacz USB-C",
  "deviceType": "laptop"
}
```

Wszystkie pola są wymagane, a nazwa modelu musi być unikalna. `baseboardFallback` jest proponowany użytkownikowi tylko wtedy, gdy `Win32_BaseBoard` nie zwróci modelu płyty. `memorySpec` jest dołączany do wykrytej lub zatwierdzonej płyty w nawiasie.

Skrypt automatycznie buduje propozycję `memorySpec` z danych SMBIOS. Jeżeli jest ona zgodna z JSON-em, nie zadaje dodatkowych pytań. Przy różnicy użytkownik może użyć wartości wykrytej, zachować wartość z bazy albo wpisać własną. Aktualizacja `memorySpec` w JSON-ie następuje tylko po jednoznacznym wyborze użytkownika i jest wykonywana przez zweryfikowany plik tymczasowy.

Przy dodawaniu nieznanego modelu `baseboardFallback` otrzymuje nazwę komputera, a `deviceType` jest pobierany z jednoznacznego wyniku `Win32_SystemEnclosure.ChassisTypes`. Jeśli typu nie można ustalić, skrypt prosi o jego wybór. Maksymalna pojemność w `memorySpec` zawsze wymaga ręcznego potwierdzenia na podstawie dokumentacji producenta; wartość `MaxCapacity`/`MaxCapacityEx` z SMBIOS nie jest używana jako limit konkretnego modelu.

Moduły wymienne są zapisywane osobno jako `16GB 3200MHz DDR4`, z `conn'=>'on board'` i poprawnym numerem seryjnym. Rekordy pamięci lutowanej są grupowane w jeden wpis z `conn'=>'soldered'`. Wartości zastępcze, takie jak `00000000`, nie trafiają do `sn`.

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
