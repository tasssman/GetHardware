# TODO — GetHardware

Lista problemów wykrytych podczas przeglądu skryptów. Składnia pliku PowerShell jest poprawna, ale poniższe punkty wpływają na bezpieczeństwo, spójność i jakość generowanych danych.

> **Warunek zmian i testów:** funkcje dotyczące ekranu należy rozwijać i testować lokalnie, wyłącznie na głównej matrycy laptopa, bez podłączonych dodatkowych monitorów oraz bez sesji zdalnej.

## Przegląd funkcji zbierających dane

### `Get-SystemOverview`

- [ ] Rozdzielić obsługę błędów poszczególnych źródeł CIM.
  - Błąd `Win32_BIOS` nie powinien przerywać całej funkcji.
  - Nieudany odczyt BIOS-u powinien zwrócić pusty Service Tag i uruchomić uzgodniony mechanizm ręcznego wpisania identyfikatora.
  - Określić, które dane są krytyczne, a które mogą pozostać puste i zostać uzupełnione ręcznie.

- [ ] Odczytywać rzeczywiste dane płyty głównej z `Win32_BaseBoard`.
  - Zebrać `Manufacturer`, `Product`, `Version` i `SerialNumber`.
  - Wyświetlić kod płyty użytkownikowi podczas weryfikacji.
  - Porównać odczytany produkt płyty z opisem `mainboard` w ręcznej bazie modeli.
  - Ustalić, czy i które dane płyty mają trafiać do PHP.

- [ ] Rozszerzyć informacje o procesorze.
  - Zebrać fizyczne rdzenie i logiczne procesory/wątki.
  - Rozważyć odczyt `CurrentClockSpeed`, `SocketDesignation`, `ProcessorId` i `Manufacturer`.
  - Do `xcCores` nadal zapisywać sumę fizycznych rdzeni, o ile format importu nie zostanie zmieniony.

- [ ] Ustalić jednoznaczne znaczenie pola `mhz`.
  - Zdecydować, czy zapisywać `MaxClockSpeed`, `CurrentClockSpeed`, czy taktowanie bazowe wynikające z nazwy/specyfikacji procesora.
  - Pamiętać, że `CurrentClockSpeed` zmienia się zależnie od obciążenia i trybu oszczędzania energii.
  - Wyjaśnić pochodzenie przykładowej wartości `1804` dla procesora i7-1185G7.

- [ ] Odczytywać typ obudowy z `Win32_SystemEnclosure.ChassisTypes`.
  - Użyć go jako dodatkowej kontroli `deviceType` z `hardware-models.json`.
  - Ostrzegać użytkownika, gdy automatycznie wykryty typ urządzenia jest sprzeczny z bazą modeli.

- [ ] Rozważyć dodatkowe dane diagnostyczne BIOS-u.
  - Możliwe pola: `BIOSVersion`, `ReleaseDate` i `SMBIOSBIOSVersion`.
  - Domyślnie wykorzystywać je tylko diagnostycznie, bez dodawania do PHP.

### Wykrywanie ekranu i matrycy

- [ ] Rozpoznawać i obsługiwać sesję zdalną.
  - Nie traktować rozdzielczości wirtualnego pulpitu RDP jako rozdzielczości fizycznej matrycy.
  - Przy sesji zdalnej zgłaszać, że dane ekranu są niewiarygodne i wymagają późniejszego lokalnego odczytu lub ręcznej korekty.

- [ ] Odczytywać natywną rozdzielczość matrycy zamiast rozdzielczości bieżącej sesji.
  - `System.Windows.Forms.Screen.Bounds` pozostawić co najwyżej jako wartość pomocniczą lub awaryjną.
  - Sprawdzić odczyt surowego EDID albo użycie Windows DisplayConfig API.
  - Nie wdrażać niesprawdzonej metody bez testu lokalnego na laptopie, bez dodatkowego monitora.

- [ ] Powiązać wszystkie dane z tym samym fizycznym ekranem.
  - Nie łączyć `Screen.AllScreens` i `WmiMonitorID` na podstawie pozycji na liście.
  - Użyć wspólnego identyfikatora urządzenia lub ścieżki wyświetlacza.
  - Uwzględniać wyłącznie aktywny fizyczny ekran podczas testu głównej matrycy.

- [ ] Poprawić rozpoznawanie matrycy wewnętrznej.
  - Nie rozpoznawać matrycy wyłącznie na podstawie pustego numeru seryjnego.
  - Wykorzystać typ wyjścia, np. `Internal`, `eDP` albo `LVDS`.
  - Ustalić zachowanie, gdy sterownik nie udostępnia typu połączenia.

- [ ] Odczytywać rzeczywisty typ połączenia ekranu.
  - Nie przypisywać każdemu monitorowi wartości `VGA,DVI,DP`.
  - Rozpoznawać co najmniej `HDMI`, `DisplayPort`, `USB-C`, `eDP`, `LVDS` i połączenie wewnętrzne.
  - Ustalić, czy do PHP dla matrycy nadal zapisywać uproszczone `on board`, a dokładny typ pokazywać tylko diagnostycznie.

- [ ] Rozszerzyć dane EDID używane do weryfikacji.
  - Odczytywać nazwę, numer seryjny, producenta, kod produktu, tydzień i rok produkcji.
  - Nadal zapisywać do PHP tylko pola wymagane przez istniejący format importu.

- [ ] Poprawić obliczanie i prezentację przekątnej.
  - Obliczać przekątną z fizycznej szerokości i wysokości EDID, jeśli są dostępne.
  - Ustalić zasady zaokrąglania do typowego oznaczenia handlowego, np. `13.9` do `14` cali.
  - Brak wymiarów oznaczać do ręcznej korekty, bez zgadywania na podstawie nazwy laptopa.

- [ ] Poprawić wykrywanie ekranu dotykowego.
  - Nie przypisywać globalnego wyniku `touchscreen` do wszystkich ekranów.
  - Jeśli nie da się powiązać urządzenia dotykowego z konkretnym panelem, dodawać `touch` wyłącznie do rozpoznanej matrycy wewnętrznej i oznaczyć wynik do zatwierdzenia.

- [ ] Rozdzielić obsługę błędów źródeł danych ekranu.
  - Błąd `WmiMonitorBasicDisplayParams` nie powinien blokować odczytu `WmiMonitorID` ani pozostałych dostępnych informacji.
  - Pokazywać użytkownikowi, których konkretnie danych nie udało się odczytać.
  - Pozwalać przejść do ręcznej edycji niepełnego wpisu matrycy.

### Pamięć RAM

- [ ] Poprawić rozpoznawanie pamięci lutowanej i wymiennej.
  - Obecne wyszukiwanie słów `onboard`, `on board` i `solder` w `DeviceLocator` oraz `BankLabel` jest tylko heurystyką.
  - Wykorzystać także `FormFactor`, `DeviceLocator`, `BankLabel` i dane konkretnego modelu.
  - Traktować automatyczne `soldered` jako wartość wymagającą potwierdzenia, jeśli SMBIOS nie dostarcza jednoznacznych danych.
  - Rozważyć dodanie do `hardware-models.json` pola opisującego układ lub sposób montażu RAM.

- [ ] Rozszerzyć mapowanie `SMBIOSMemoryType`.
  - Uwzględnić brakujące typy, m.in. DDR2 FB-DIMM, LPDDR, LPDDR2, LPDDR3 oraz HBM.
  - Dla nieznanego kodu wyświetlać kod liczbowy diagnostycznie zamiast całkowicie pomijać typ.

- [ ] Przetwarzać każdy moduł RAM niezależnie.
  - Błąd lub brak właściwości jednego wpisu SMBIOS nie powinien usuwać z wyniku wszystkich pozostałych modułów.
  - Pokazywać ostrzeżenie dotyczące konkretnego lokalizatora lub banku.

- [ ] Rozszerzyć dane RAM dostępne podczas weryfikacji.
  - Odczytywać `Manufacturer`, `PartNumber`, `SerialNumber`, `DeviceLocator`, `BankLabel` i `FormFactor`.
  - Pokazywać osobno `Speed` oraz `ConfiguredClockSpeed`.
  - Odczytywać `DataWidth` i `TotalWidth`, aby rozpoznać pamięć ECC, jeśli SMBIOS podaje wiarygodne wartości.
  - Rozważyć pokazanie `ConfiguredVoltage`, `MinVoltage` i `MaxVoltage` wyłącznie diagnostycznie.
  - Wyświetlać podsumowanie całkowitej pojemności i liczby wykrytych modułów.

- [ ] Filtrować niewiarygodne dane identyfikacyjne RAM.
  - Usuwać spacje z początku i końca producenta, numeru części i numeru seryjnego.
  - Traktować wartości puste, `00000000`, `FFFFFFFF` i typowe teksty zastępcze jako brak danych.

- [ ] Ustalić docelowy format opisu RAM w PHP.
  - Zdecydować, czy `desc` ma zawierać typ pamięci, np. `16GB 3733Mhz LPDDR4`, czy zachować krótszy format `16GB 3733Mhz`.
  - Zdecydować, czy producent i numer części mają być tylko widoczne w konsoli, czy również dodawane do `desc`.
  - Zdecydować, czy numer seryjny modułu RAM ma trafiać do opcjonalnego pola `sn`.
  - Zachować krótki i przewidywalny format wymagany przez istniejący import PHP.

### Dyski

- [ ] Zastąpić lub uzupełnić `Win32_DiskDrive` dokładniejszym źródłem danych.
  - Używać `Get-PhysicalDisk` albo `MSFT_PhysicalDisk` jako źródła podstawowego.
  - Pozostawić `Win32_DiskDrive` jako rozwiązanie awaryjne i źródło danych uzupełniających.
  - Korelować rekordy z obu źródeł po stabilnym identyfikatorze, numerze seryjnym albo identyfikatorze urządzenia, a nie pozycji na liście.

- [ ] Rozdzielić protokół, magistralę i format fizyczny dysku.
  - Nie zakładać bezwarunkowo, że każdy dysk NVMe ma format M.2.
  - Rozpoznawać `BusType`, np. NVMe, SATA, SAS i USB.
  - Rozpoznawać `MediaType`, np. SSD, HDD i SCM.
  - Traktować M.2 jako wartość wymagającą potwierdzenia, jeśli system udostępnia tylko informację o NVMe.

- [ ] Obsłużyć dyski zewnętrzne i nośniki wymienne.
  - Ustalić, czy dyski USB mają być automatycznie pomijane.
  - Nawet po pominięciu pokazywać użytkownikowi informację o wykrytym nośniku zewnętrznym.
  - Nie zapisywać przypadkowo pendrive'a lub dysku serwisowego jako części laptopa.
  - Rozważyć filtrowanie wirtualnych dysków i urządzeń Storage Spaces.

- [ ] Rozszerzyć dane dysku dostępne podczas weryfikacji.
  - Odczytywać `Manufacturer`, `Model`, `SerialNumber`, `FirmwareVersion`, `BusType`, `MediaType` i `PhysicalLocation`.
  - Pokazywać `HealthStatus` oraz `OperationalStatus` diagnostycznie.
  - Jeśli sterownik pozwala, odczytywać temperaturę, zużycie, czas pracy oraz liczniki błędów przez `Get-StorageReliabilityCounter`.
  - Brak liczników niezawodności traktować jako brak danych, a nie błąd całej inwentaryzacji.

- [ ] Przetwarzać każdy dysk niezależnie.
  - Błąd odczytu jednego nośnika nie powinien usuwać pozostałych dysków z wyniku.
  - W ostrzeżeniu wskazywać konkretny model albo identyfikator problematycznego urządzenia.

- [ ] Filtrować i normalizować identyfikatory dysków.
  - Usuwać zbędne spacje z modelu, producenta, firmware i numeru seryjnego.
  - Odrzucać puste numery seryjne i typowe wartości zastępcze.
  - Unikać powtarzania słów takich jak `NVMe` lub nazwy producenta, jeśli występują już w modelu.

- [ ] Ustalić docelowy format wpisu dysku w PHP.
  - Zachować typ części `Hard Disk`, jeśli wymaga tego istniejący importer.
  - Zdecydować, czy `SSD`, `HDD` albo `NVMe` ma być zawsze dodawane do `desc`.
  - Zdecydować, czy numer seryjny dysku ma trafiać do opcjonalnego pola `sn`.
  - Zdecydować, czy ostrzegać i blokować zapis, gdy `HealthStatus` nie jest `Healthy`.
  - Zachować pojemność dziesiętną, np. `256GB`, zgodną z oznaczeniem producenta.

### Karty sieciowe

- [ ] Zastąpić przestarzałe `Win32_NetworkAdapter` nowszym źródłem danych.
  - Używać `Get-NetAdapter -Name * -IncludeHidden` albo `MSFT_NetAdapter` jako źródła podstawowego.
  - Pozostawić `Win32_NetworkAdapter` jako rozwiązanie awaryjne.
  - Korelować dane z obu źródeł po `InterfaceIndex`, `PnPDeviceID`, GUID albo innym stabilnym identyfikatorze.

- [ ] Dokładniej klasyfikować adaptery sieciowe.
  - Rozróżniać Ethernet, Wi-Fi, Bluetooth PAN, USB Ethernet i urządzenia wbudowane.
  - Odfiltrować VPN, Hyper-V, loopback, WAN Miniport i pozostałe adaptery wirtualne.
  - Nie polegać wyłącznie na `PhysicalAdapter = true`.
  - Wykorzystać `PhysicalMediaType`, `HardwareInterface`, `Virtual`, `ConnectorPresent`, opis oraz `PnPDeviceID`.

- [ ] Ustalić sposób zapisywania rodzaju połączenia.
  - Rozpoznawać urządzenia wbudowane na podstawie magistrali PCI i zapisywać je jako `on board`.
  - Rozpoznawać adaptery USB na podstawie `PnPDeviceID`.
  - Zdecydować, czy `Realtek USB GbE` ma otrzymywać `conn'=>'USB'`, czy zgodnie ze starym formatem nadal `conn'=>'on board'`.

- [ ] Preferować trwały adres MAC.
  - Używać poprawnego `PermanentAddress`, jeśli sterownik go udostępnia.
  - Używać `MacAddress` jako wartości awaryjnej.
  - Normalizować adres do wielkich liter bez separatorów.
  - Wykrywać adres lokalnie administrowany i ostrzegać, że może być zmieniony lub losowy.
  - Odrzucać adresy puste, zerowe, broadcast i inne niewiarygodne wartości.

- [ ] Ustalić zachowanie przy braku pewnego adresu MAC.
  - Zdecydować, czy brak trwałego MAC ma tylko powodować ostrzeżenie i pominięcie `sn`, czy blokować zapis adaptera.
  - Nie zapisywać bez ostrzeżenia losowego adresu Wi-Fi jako sprzętowego numeru seryjnego.

- [ ] Ustalić zakres wykrywanych adapterów.
  - Zdecydować, czy zapisywać adaptery wyłączone, ale fizycznie zainstalowane.
  - Zachować Wi-Fi, Bluetooth PAN i fizyczne adaptery USB, jeśli nadal odpowiada to formatowi istniejącej bazy.
  - Pokazywać użytkownikowi przyczynę pominięcia każdego adaptera.

- [ ] Rozszerzyć dane dostępne podczas weryfikacji.
  - Pokazywać nazwę, opis interfejsu, typ fizyczny, magistralę, stan połączenia i szybkość łącza.
  - Pokazywać wersję, datę i nazwę pliku sterownika, jeśli są dostępne.
  - Dane dynamiczne, takie jak stan i szybkość bieżącego połączenia, wykorzystywać tylko diagnostycznie.
  - Zdecydować, czy informacje o sterowniku mają pozostać wyłącznie w konsoli.

- [ ] Przetwarzać każdy adapter niezależnie.
  - Błąd jednego adaptera nie powinien usuwać wszystkich kart sieciowych z wyniku.
  - W ostrzeżeniu wskazywać nazwę lub identyfikator problematycznego urządzenia.

- [ ] Zachować przewidywalny format PHP.
  - Pozostawić typ `Network Card`.
  - Zapisywać opis urządzenia w `desc`, sposób połączenia w `conn` oraz zatwierdzony MAC w opcjonalnym `sn`.
  - Unikać dodawania do `desc` dynamicznych danych, takich jak bieżąca szybkość połączenia.

### Karta dźwiękowa

- [ ] Klasyfikować wykryte urządzenia audio.
  - Rozróżniać wewnętrzny kodek, audio HDMI/DisplayPort, urządzenia USB, Bluetooth i audio stacji dokującej.
  - Wykorzystać `Caption`, `ProductName`, `Manufacturer` i `PNPDeviceID`.
  - Nie traktować każdego wpisu `Win32_SoundDevice` jako osobnej wewnętrznej karty dźwiękowej.

- [ ] Ustalić zakres urządzeń audio zapisywanych do PHP.
  - Zdecydować, czy audio HDMI/DisplayPort ma być pomijane.
  - Zdecydować, czy urządzenia USB i Bluetooth mają być pomijane.
  - Zdecydować, czy automatycznie dodawać wyłącznie główny wewnętrzny kodek.
  - Pokazywać użytkownikowi listę urządzeń pominiętych wraz z przyczyną.

- [ ] Poprawić ustalanie rodzaju połączenia.
  - Zapisywać `on board` wyłącznie dla rozpoznanego wewnętrznego kodeka.
  - Rozpoznawać co najmniej `HDMI/DisplayPort`, `USB` i `Bluetooth`.
  - Nie przypisywać wartości `on board` wszystkim urządzeniom audio.

- [ ] Rozszerzyć dane urządzenia audio dostępne podczas weryfikacji.
  - Odczytywać `Caption`, `Description`, `Manufacturer`, `ProductName`, `PNPDeviceID`, `Status` i `ConfigManagerErrorCode`.
  - Powiązać urządzenie z `Win32_PnPSignedDriver`.
  - Pokazywać wersję i datę sterownika, dostawcę, nazwę INF oraz status podpisu cyfrowego.
  - Dane sterownika wykorzystywać diagnostycznie, bez dodawania ich do PHP.

- [ ] Walidować stan urządzeń audio.
  - Ostrzegać, gdy `ConfigManagerErrorCode` jest inny niż `0` albo `Status` nie wskazuje poprawnego działania.
  - Ostrzegać przy ogólnym sterowniku lub nazwie `High Definition Audio Device`.
  - Ostrzegać, jeśli w laptopie nie znaleziono żadnego wewnętrznego kodeka.
  - Zdecydować, czy brak sprawnego wewnętrznego audio ma blokować zapis, czy tylko wymagać potwierdzenia.

- [ ] Przetwarzać każde urządzenie audio niezależnie.
  - Błąd pojedynczego wpisu nie powinien usuwać wszystkich urządzeń audio z wyniku.
  - W ostrzeżeniu wskazywać nazwę albo identyfikator problematycznego urządzenia.

- [ ] Rozważyć pomocniczy odczyt endpointów przez MMDevice API.
  - Używać go wyłącznie diagnostycznie do pokazania głośników, mikrofonów, słuchawek i wyjść HDMI.
  - Nie tworzyć automatycznie osobnego wpisu PHP dla każdego endpointu należącego do tego samego kodeka.

- [ ] Zachować prosty format głównego kodeka w PHP.
  - Pozostawić typ `Sound Card`.
  - Dla rozpoznanego kodeka wewnętrznego zapisywać krótki opis, np. `Realtek Audio`, oraz `conn'=>'on board'`.

### Karta graficzna

- [ ] Zastąpić albo uzupełnić `Win32_VideoController` dokładniejszym źródłem danych o pamięci GPU.
  - Nie traktować `AdapterRAM` jako wiarygodnej ilości pamięci dla współczesnych kart graficznych.
  - Uwzględnić ograniczenie 32-bitowego pola `AdapterRAM`, szczególnie dla kart mających więcej niż 4 GB VRAM.
  - Rozważyć użycie DXGI do odczytu 64-bitowych wartości pamięci dedykowanej, dedykowanej pamięci systemowej i pamięci współdzielonej.
  - Pozostawić `Win32_VideoController` jako źródło pomocnicze lub awaryjne.

- [ ] Poprawnie prezentować pamięć grafiki zintegrowanej.
  - Nie przedstawiać wartości takiej jak `1024MB` jako rzeczywistego VRAM układu zintegrowanego, jeśli jest to tylko pamięć współdzielona albo wartość raportowana przez sterownik.
  - Dla zintegrowanego GPU domyślnie pomijać liczbę MB w `desc` albo jednoznacznie oznaczać pamięć jako współdzieloną.
  - Dla dedykowanego GPU dodawać do `desc` ilość rzeczywistej pamięci dedykowanej, jeśli została wiarygodnie odczytana przez DXGI.

- [ ] Klasyfikować i filtrować adaptery graficzne.
  - Zachować osobny wpis dla każdego fizycznego GPU, np. Intel oraz NVIDIA/AMD w laptopie hybrydowym.
  - Odfiltrować adaptery zdalne, programowe oraz `Microsoft Basic Display Adapter`, ale pokazywać użytkownikowi informację o ich pominięciu.
  - Nie uznawać obecności kilku kontrolerów za błąd.
  - Ostrożnie rozpoznawać grafikę zintegrowaną i dedykowaną; nie opierać klasyfikacji wyłącznie na nazwie lub ilości raportowanej pamięci.

- [ ] Poprawić ustalanie rodzaju połączenia karty graficznej.
  - Nie przypisywać każdej karcie stałej wartości `on board,HDMI`.
  - Uwzględnić, że złącza HDMI, DisplayPort i USB-C są cechą całego laptopa, płyty lub stacji dokującej i nie zawsze można je jednoznacznie przypisać do konkretnego GPU.
  - Uwzględnić wewnętrzne połączenie matrycy, np. eDP, oraz konfiguracje hybrydowe, w których dedykowany GPU renderuje obraz przekazywany przez GPU zintegrowany.
  - Do czasu wiarygodnego ustalania złączy używać bezpiecznego `conn'=>'on board'` i pozostawić możliwość ręcznej korekty.

- [ ] Rozszerzyć dane GPU dostępne podczas weryfikacji.
  - Pokazywać nazwę adaptera, `PNPDeviceID`, procesor graficzny, wersję i datę sterownika.
  - Pokazywać pamięć dedykowaną i współdzieloną jako osobne wartości diagnostyczne.
  - Pokazywać `Status` oraz `ConfigManagerErrorCode` i ostrzegać o niesprawnym urządzeniu.
  - Bieżącą rozdzielczość i częstotliwość odświeżania wykorzystywać tylko diagnostycznie, szczególnie podczas sesji zdalnej.

- [ ] Przetwarzać każdy adapter graficzny niezależnie.
  - Błąd jednego adaptera nie powinien usuwać pozostałych kart graficznych z wyniku.
  - W ostrzeżeniu wskazywać nazwę albo identyfikator problematycznego urządzenia.

- [ ] Ustalić docelowy format wpisu GPU w PHP.
  - Pozostawić typ `Graphic Card`.
  - Dla grafiki zintegrowanej preferować krótki opis bez mylącej ilości pamięci, np. `Intel(R) Iris(R) Xe Graphics`.
  - Dla grafiki dedykowanej używać formatu takiego jak `4096MB NVIDIA GeForce RTX 3050`, jeśli ilość VRAM została wiarygodnie odczytana.
  - Dane sterownika, identyfikatory i pamięć współdzieloną pozostawić wyłącznie w diagnostyce konsolowej.

### Bateria

- [ ] Rozszerzyć źródła danych o baterii.
  - Pozostawić `Win32_Battery` jako podstawowe lub awaryjne źródło prostych informacji.
  - Uzupełnić dane klasami baterii z przestrzeni `root\wmi`.
  - Rozważyć użycie `powercfg /batteryreport /xml` jako dodatkowego źródła charakterystyki i historii baterii.
  - Korelować wpisy różnych źródeł po stabilnym identyfikatorze lub nazwie instancji, a nie pozycji na liście.

- [ ] Rozszerzyć dane baterii dostępne podczas weryfikacji.
  - Odczytywać producenta, nazwę lub model, numer seryjny i rodzaj chemii ogniwa.
  - Pokazywać pojemność projektową oraz aktualną pojemność po pełnym naładowaniu.
  - Odczytywać liczbę cykli ładowania, jeśli sterownik i firmware ją udostępniają.
  - Pokazywać napięcie projektowe, bieżący poziom naładowania, stan baterii oraz zgłoszone błędy.
  - Brak pojedynczej wartości traktować jako brak danych, a nie błąd całego odczytu baterii.

- [ ] Obliczać i prezentować kondycję baterii.
  - Obliczać kondycję jako `FullChargeCapacity / DesignCapacity * 100%`.
  - Obliczać zużycie jako `100% - kondycja`.
  - Wykonywać obliczenia tylko wtedy, gdy obie pojemności są wiarygodne i pojemność projektowa jest większa od zera.
  - Ostrzegać, gdy kondycja spadnie poniżej 80%, ale nie blokować z tego powodu zapisu inwentaryzacji.
  - Nie traktować bieżącego poziomu naładowania jako kondycji baterii.

- [ ] Obsłużyć wiele baterii i urządzenia niebędące baterią laptopa.
  - Zachować osobny wpis dla każdej fizycznej baterii w laptopach z dwoma akumulatorami.
  - Przetwarzać każdą baterię niezależnie, aby błąd jednej nie usuwał pozostałych z wyniku.
  - Rozpoznać i nie zapisywać przypadkowo baterii urządzenia UPS jako wewnętrznej baterii laptopa.
  - Brak baterii pozostawić jako prawidłowy wynik dla komputera stacjonarnego.

- [ ] Walidować dane identyfikacyjne baterii.
  - Usuwać zbędne spacje z producenta, modelu i numeru seryjnego.
  - Odrzucać puste numery seryjne oraz typowe wartości zastępcze.
  - Pokazywać użytkownikowi źródło danych i informację, gdy numer seryjny nie jest wiarygodny.

- [ ] Ustalić docelowy format wpisu baterii w PHP.
  - Pozostawić typ `Battery` i prosty opis, np. `Internal Battery`.
  - Dane o pojemności, kondycji, liczbie cykli i bieżącym naładowaniu pozostawić wyłącznie w diagnostyce konsolowej.
  - Zapisywać numer seryjny w opcjonalnym polu `sn`, jeśli został wiarygodnie odczytany.
  - Nie dodawać pola `sn`, gdy numer jest pusty albo niewiarygodny.

## Priorytet wysoki

- [x] Ujednolicić sposób uruchamiania skryptu.
  - Plik BAT uruchamiający inną kopię PS1 z udziału sieciowego został usunięty.
  - Skrypt będzie uruchamiany bezpośrednio z konsoli Windows PowerShell.
  - Lokalny plik PS1 w repozytorium jest źródłem prawdy.

- [x] Bezpiecznie kodować wartości umieszczane w generowanym PHP.
  - Apostrof, ukośnik lub znak nowej linii w nazwie urządzenia może zepsuć składnię pliku.
  - Dodać funkcję kodującą tekst jako poprawny literał PHP albo generować dane w bezpiecznym formacie, np. JSON.
  - Zweryfikować wygenerowany kod przed jego zapisaniem do pliku zbiorczego.

- [x] Zabezpieczyć zapis do pliku zbiorczego.
  - Zapobiegać wielokrotnemu dopisywaniu tego samego Service Tagu.
  - Zastosować blokadę pliku lub zapis atomowy, jeżeli skrypt może być uruchamiany równocześnie na wielu komputerach.
  - Nie dopisywać rekordu, jeśli zbieranie danych zakończyło się częściowym błędem.

- [x] Dodać walidację danych wejściowych i obsługę błędów.
  - Sprawdzać, czy Service Tag, model i dane procesora zostały poprawnie odczytane.
  - Dodać kontrolowane `ErrorAction` oraz czytelny komunikat końcowy.
  - Rozważyć `Set-StrictMode`.

## Priorytet średni

- [x] Usunąć zduplikowaną regułę `Vostro 3400`.
  - Obie gałęzie `switch` są wykonywane, przez co powstaje osiem wartości, a kod wykorzystuje tylko pierwsze cztery.
  - Do JSON przeniesiono późniejszy wpis: 65 W / 55 W, `max16GB x2 DDR4`; wartości nadal wymagają weryfikacji merytorycznej.

- [ ] Poprawić wykrywanie monitorów i matrycy.
  - Obecnie rozdzielczość ostatniego wykrytego ekranu jest przypisywana wszystkim monitorom.
  - Nie klasyfikować urządzenia jako `Monitor` lub `Matrix` wyłącznie na podstawie długości numeru seryjnego.
  - Powiązać rozdzielczość, nazwę i numer seryjny z tym samym ekranem.
  - Wiarygodniej wykrywać ekran dotykowy.
  - [ ] Przetestować możliwość zebrania danych o monitorze bez jego podłączenia.

- [x] Poprawić rozpoznawanie laptopów, tabletów i urządzeń 2-w-1.
  - Warunek `PCSystemType -eq 2` może pominąć tablety i urządzenia konwertowalne.
  - Zweryfikować wartości `PCSystemType`/`PCSystemTypeEx` i sposób dodawania sufiksu `_laptop`.

- [ ] Poprawić zbieranie danych o podzespołach.
  - Nie oznaczać każdego dysku jako `M.2`; wykorzystać rzeczywisty typ magistrali/interfejsu.
  - Nie oznaczać każdego modułu RAM jako `on board`; wykorzystać informacje o slocie i typie pamięci.
  - Nie przypisywać każdej karcie graficznej połączenia `on board,HDMI`.
  - Odfiltrować Bluetooth, WAN i inne adaptery, jeśli nie powinny być rejestrowane jako karty sieciowe.
  - Zweryfikować wiarygodność `AdapterRAM` dla współczesnych kart graficznych.
  - Dla komputerów wieloprocesorowych prawidłowo zsumować lub opisać rdzenie.

- [x] Usunąć sztuczne pomniejszanie `MaxClockSpeed` o 1 MHz.
  - Ustalić, czy było to obejście konkretnego problemu z formatem danych.

- [ ] Zweryfikować ręczną tabelę modeli.
  - Sprawdzić parametry płyty głównej, pamięci, zasilacza i poboru mocy.
  - Szczególnie przejrzeć wpisy wyglądające na skopiowane pomiędzy różnymi modelami.
  - [x] Przenieść tabelę do osobnego pliku JSON, aby łatwiej ją utrzymywać.

## Priorytet niższy / porządki

- [ ] Otwierać stronę wsparcia Dell dla zinwentaryzowanego urządzenia.
  - Po odczytaniu numeru seryjnego (Service Tagu) otworzyć domyślną przeglądarkę bezpośrednio na stronie urządzenia w serwisie Dell.

- [ ] Umożliwić wpisanie dowolnej etykiety systemu.
  - Oprócz wyboru `W10P` lub `W11P` pozwolić użytkownikowi podać inną wartość etykiety.

- [ ] Ujednolicić podpowiedzi i wartości domyślne w polach formularza.
  - Wartość pokazana jako podpowiedź, np. dla pola pomieszczenia, powinna być faktyczną wartością domyślną zatwierdzaną klawiszem Enter.

- [x] Uporządkować pola wymagające ręcznego uzupełnienia.
  - Data zakupu jest wpisana na stałe dla całego uruchomienia.
  - `warr`, cena, licencja, pokój i notatka zawierają `QQ_POPRAW`.
  - Każdy opis ekranu jest bezwarunkowo oznaczany `QQ_POPRAW`.
  - Rozważyć parametry skryptu lub interaktywny formularz z walidacją.

- [x] Zweryfikować algorytm wyliczania przekątnej matrycy.
  - Obecnie przekątna jest zgadywana na podstawie cyfry występującej w nazwie modelu.
  - Dla nierozpoznanych modeli pozostawić wartość pustą albo oznaczyć ją do ręcznej weryfikacji.

- [x] Uporządkować kod i nazewnictwo w nowym skrypcie.
  - Zmienne `$monitorInfo`, `$ram`, `$disk`, `$network`, `$sound`, `$graphics` i `$battery` służą tylko do efektów ubocznych pętli.
  - Usunąć nieużywany kod i stare komentarze albo opisać ich przeznaczenie.
  - Poprawić literówki w komentarzach oraz ujednolicić wcięcia i nazwy pól.

- [x] Dodać dokumentację i testy pierwszej wersji.
  - Utworzyć README opisujące wymagania, sposób uruchomienia, format wyniku oraz znaczenie pól.
  - Dodać testy funkcji formatujących i generowania PHP z zamockowanymi danymi sprzętowymi.
  - Dodać przypadki testowe dla nieznanego modelu, pustego Service Tagu, kilku monitorów i znaków specjalnych.

- [x] Rozpocząć śledzenie projektu w Git.
  - Repozytorium zawiera pierwszy commit.
  - Nowa implementacja i dokumentacja wymagają dodania do kolejnego commitu po próbie na docelowym laptopie.
