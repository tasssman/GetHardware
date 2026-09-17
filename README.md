# GetHardware

Interaktywny skrypt Windows PowerShell 5.1 odczytujący informacje o sprzęcie i zapisujący je w plikach PHP przeznaczonych do importu do istniejącej bazy.

Aktualna wersja skryptu: `v1.0.0`. Numer wersji jest wyświetlany jako pierwszy komunikat po uruchomieniu. Nazwa pliku pozostaje stała niezależnie od wersji.

## Wymagania

- Windows PowerShell 5.1;
- dostęp do poleceń CIM/WMI;
- możliwość odczytu urządzeń PnP;
- pliki `Get-HardwareInventory.ps1` i `hardware-models.json` w tym samym katalogu.

## Uruchomienie

Na inwentaryzowanym laptopie otwórz Windows PowerShell i wklej poniższe polecenie w jednej linii. Zastąp `DOMENA\uzytkownik` właściwą nazwą konta domenowego:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force; $Credential=Get-Credential -Message 'Podaj konto domenowe' -UserName 'DOMENA\uzytkownik'; New-PSDrive -Name GH -PSProvider FileSystem -Root '\\ntshare\helpdesk\scripts\GetHardware' -Credential $Credential -ErrorAction Stop | Out-Null; try { & 'GH:\Get-HardwareInventory.ps1' } finally { Remove-PSDrive -Name GH -Force -ErrorAction SilentlyContinue }
```

Polecenie zezwala na wykonywanie skryptów wyłącznie w bieżącym oknie PowerShell, bez trwałej zmiany polityki komputera. Hasło jest podawane w bezpiecznym oknie i nie należy wpisywać go bezpośrednio w poleceniu. Skrypt oraz pliki bazy są odczytywane z udziału sieciowego, wyniki trafiają do `\\ntshare\helpdesk\scripts\GetHardware\output`, a tymczasowy dysk `GH:` jest automatycznie odłączany po zakończeniu pracy.

Jeśli `MachinePolicy` albo `UserPolicy` widoczne w `Get-ExecutionPolicy -List` są wymuszone administracyjnie, ustawienie dla zakresu `Process` może ich nie zastąpić. W takim przypadku potrzebny jest podpisany skrypt albo zmiana polityki przez administratora.

Skrypt nie przyjmuje nazwy spisu jako parametru. Przy pierwszym uruchomieniu prosi o jej wpisanie. Przy kolejnych uruchomieniach wyświetla istniejące spisy i opcję utworzenia nowego.

## Przebieg

1. Potwierdzenie odłączenia dodatkowych monitorów, sesji pulpitu zdalnego, stacji dokujących i zewnętrznych urządzeń USB.
2. Odczyt modelu, Service Tagu, procesora, płyty głównej i pozostałych podzespołów.
3. Dla urządzenia Dell wyświetlenie adresu strony wsparcia bez automatycznego otwierania przeglądarki.
4. Sprawdzenie modelu w `hardware-models.json`.
5. Wybór istniejącego spisu albo utworzenie nowego.
6. Odczyt wspólnego pola `bought` z istniejącego spisu albo pytanie o nie dla nowego spisu.
7. Przegląd, edycja, dodawanie lub usuwanie wykrytych podzespołów.
8. Wprowadzenie gwarancji, ceny, etykiety Windows, pomieszczenia i notatki.
9. Wyświetlenie podsumowania i zapis po zatwierdzeniu.

Nieznany model uruchamia interaktywny kreator wpisu. Skrypt automatycznie uzupełnia nazwę modelu, awaryjny opis płyty, wykrytą konfigurację pamięci i typ urządzenia. Użytkownik podaje zweryfikowaną maksymalną pojemność RAM, `powerMaxW`, `powerW` oraz `other`, a wpis trafia do JSON-u dopiero po pokazaniu podsumowania i zatwierdzeniu. Jeśli bazy nie można zapisać lub jest niepoprawna, nadal można poprawić ją ręcznie i wczytać ponownie bez rozpoczynania pracy od początku.

### Identyfikacja modelu

Skrypt pobiera producenta, `Model`, `SystemFamily` i `SystemSKUNumber` z `Win32_ComputerSystem`. Dane z `Win32_ComputerSystemProduct` oraz klucza `HKLM:\HARDWARE\DESCRIPTION\System\BIOS` są źródłami awaryjnymi dla pustych lub zastępczych wartości.

Nazwa używana do dokładnego wyszukania wpisu w `hardware-models.json` oraz później w polu PHP `model` jest budowana z `SystemFamily` i `Model`. Jeśli `Model` zawiera już nazwę rodziny, nie jest ona powtarzana: `Latitude` i `Latitude 5421` dają `Latitude 5421`. Gdy wartości są różne, kod modelu jest dodawany w nawiasie: `Yoga Slim 7 15ILL9` i `83HM` dają `Yoga Slim 7 15ILL9 (83HM)`.

Istniejący wpis w JSON-ie jest traktowany jako poprawny i musi dokładnie odpowiadać zbudowanej nazwie. Przy braku wpisu skrypt pokazuje producenta, rodzinę, model systemowy, SKU oraz proponowaną nazwę. Użytkownik musi zaakceptować propozycję, a następnie kompletny nowy wpis JSON przed jego zapisaniem. Struktura `hardware-models.json` nie została rozszerzona o dodatkowe pola identyfikacyjne.

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

Odczyt zainstalowanych modułów RAM jest niezależny od ustalania konfiguracji pamięci obsługiwanej przez płytę główną. Jeśli moduły zostały wykryte, ale nie udało się ustalić np. liczby gniazd dla `memorySpec`, skrypt wyraźnie informuje, że problem dotyczy tylko opisu pola `mainb`. Dopiero brak wpisów zainstalowanej pamięci powoduje ostrzeżenie o konieczności ręcznego dodania RAM-u w edytorze podzespołów.

Przy dodawaniu nieznanego modelu `baseboardFallback` otrzymuje nazwę komputera, a `deviceType` jest pobierany z jednoznacznego wyniku `Win32_SystemEnclosure.ChassisTypes`. Jeśli typu nie można ustalić, skrypt prosi o jego wybór. Maksymalna pojemność w `memorySpec` zawsze wymaga ręcznego potwierdzenia na podstawie dokumentacji producenta; wartość `MaxCapacity`/`MaxCapacityEx` z SMBIOS nie jest używana jako limit konkretnego modelu.

Moduły wymienne są zapisywane osobno jako `16GB 3200MHz DDR4`, z `conn'=>'on board'` i poprawnym numerem seryjnym. Rekordy pamięci lutowanej są grupowane w jeden wpis z `conn'=>'soldered'`. Wartości zastępcze, takie jak `00000000`, nie trafiają do `sn`.

## Walidacja danych ręcznych

W formularzach tekst w nawiasach kwadratowych, np. `[A216]`, jest rzeczywistą wartością domyślną zatwierdzaną klawiszem Enter. Tekst po `np.` jest wyłącznie przykładem. Pola, które mogą pozostać puste, są oznaczone jako opcjonalne i nie pokazują pustych nawiasów `[]`.

- `bought`: `YYYY-MM-DD`, wspólne dla całego spisu;
- `warr`: `YYYY-MM-DD+N`, np. `2021-05-20+3`;
- `cenan`: kwota PLN z dwiema cyframi po przecinku, np. `1414,08`;
- `label`: interaktywny wybór `W10P`, `W11P` albo wpisanie dowolnej niepustej etykiety;
- `room`: domyślnie `A216`;
- `note`: domyślny szablon `SCC:;REFURBISHED;`.

## Testy

Testy nie odczytują prawdziwego sprzętu. Sprawdzają bazę modeli, walidację podstawowych danych, generowanie PHP, kolejność rekordów, zastępowanie rekordu i kodowanie bez BOM:

```powershell
.\tests\Test-GetHardwareInventory.ps1
```

Automatyczny odczyt sprzętu należy sprawdzić na docelowym laptopie. Dane zwracane przez WMI, szczególnie pamięć karty graficznej, rodzaj osadzenia RAM i powiązanie rozdzielczości z ekranem EDID, mogą wymagać ręcznej korekty w interaktywnym przeglądzie.
