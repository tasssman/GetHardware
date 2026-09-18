# TODO — GetHardware

Lista problemów wykrytych podczas przeglądu skryptów. Składnia pliku PowerShell jest poprawna, ale poniższe punkty wpływają na bezpieczeństwo, spójność i jakość generowanych danych.

> **Warunek zmian i testów:** funkcje dotyczące ekranu należy rozwijać i testować lokalnie, wyłącznie na głównej matrycy laptopa, bez podłączonych dodatkowych monitorów oraz bez sesji zdalnej.

## Przegląd funkcji zbierających dane

### `Get-SystemOverview`

- [x] Rozdzielić obsługę błędów poszczególnych źródeł CIM.
  - Błąd `Win32_BIOS` nie powinien przerywać całej funkcji.
  - Nieudany odczyt BIOS-u powinien zwrócić pusty Service Tag i uruchomić uzgodniony mechanizm ręcznego wpisania identyfikatora.
  - Model i dane procesora są krytyczne; brak któregoś z nich zatrzymuje zapis z precyzyjnym komunikatem.
  - BIOS/Service Tag jest odzyskiwalny; brak odczytu uruchamia ręczne wpisanie identyfikatora.

- [x] Ujednolicić nazwę modelu dla różnych producentów.
  - Pobierać `Model`, `SystemFamily` i `SystemSKUNumber` z `Win32_ComputerSystem`, z danymi produktu i rejestru jako źródłami awaryjnymi.
  - Nie powtarzać `SystemFamily`, jeśli jest już zawarte w `Model`, np. `Latitude 5421`.
  - Dla różnych wartości używać formatu `SystemFamily (Model)`, np. `Yoga Slim 7 15ILL9 (83HM)`.
  - Dokładnie tą nazwą wyszukiwać istniejący wpis JSON i zapisywać pole PHP `model`.
  - Każdą propozycję nowego modelu oraz kompletny nowy wpis JSON zatwierdza użytkownik.

- [x] Odczytywać rzeczywiste dane płyty głównej z `Win32_BaseBoard`.
  - Zebrać `Manufacturer`, `Product`, `Version` i `SerialNumber`.
  - Wyświetlić kod płyty użytkownikowi podczas weryfikacji.
  - Porównać odczytany produkt płyty z awaryjnym opisem `baseboardFallback` w ręcznej bazie modeli.
  - Do PHP trafiają producent, produkt i wersja płyty połączone z wykrytym lub zatwierdzonym `memorySpec`.
  - Przy braku produktu skrypt proponuje `baseboardFallback` z JSON-u i pozwala go zatwierdzić lub zmienić.
  - Numer seryjny, status i pozostałe pola techniczne nie są wyświetlane ani zapisywane.

- [x] Ustalić zakres informacji o procesorze zapisywanych do PHP.
  - Do `proc` zapisywać nazwę procesora.
  - Do `xcCores` zapisywać sumę fizycznych rdzeni.
  - Nie zbierać liczby wątków, `CurrentClockSpeed`, `SocketDesignation`, `ProcessorId` ani producenta procesora, ponieważ nie są zapisywane w obecnym formacie PHP.

- [x] Ustalić jednoznaczne znaczenie pola `mhz`.
  - Najpierw odczytywać częstotliwość występującą po znaku `@` w nazwie procesora.
  - Przeliczać GHz na MHz, np. `3.00GHz` na `3000`.
  - Jeśli nazwa nie zawiera częstotliwości, używać `MaxClockSpeed`.
  - Nie używać zmiennego `CurrentClockSpeed` i nie odejmować sztucznie `1 MHz`.
  - Przykładowa wartość `1804` wynikała ze starego działania `MaxClockSpeed - 1` i nie była wiarygodną specyfikacją procesora.

- [x] Odczytywać typ obudowy z `Win32_SystemEnclosure.ChassisTypes`.
  - Używać go jako dodatkowej kontroli `deviceType` z `hardware-models.json`, bez automatycznej zmiany bazy.
  - Przy wiarygodnej sprzeczności pozwalać zachować typ z JSON albo użyć wykrytego typu tylko dla bieżącego urządzenia.
  - Dla wartości nieznanej lub niejednoznacznej zachowywać typ z JSON bez pytania.
  - W końcowym podsumowaniu pokazywać w osobnej sekcji typ z bazy, opis obudowy SMBIOS z kodem, typ wykryty, typ użyty w PHP oraz końcowy identyfikator `addComp()`.

### Wykrywanie ekranu i matrycy

- [ ] Rozpoznawać i obsługiwać sesję zdalną.
  - Nie traktować rozdzielczości wirtualnego pulpitu RDP jako rozdzielczości fizycznej matrycy.
  - Przy sesji zdalnej zgłaszać, że dane ekranu są niewiarygodne i wymagają późniejszego lokalnego odczytu lub ręcznej korekty.

- [x] Odczytywać natywną rozdzielczość matrycy zamiast rozdzielczości bieżącej sesji.
  - Używać największego trybu zgłoszonego przez `WmiMonitorListedSupportedSourceModes`.
  - Nie używać `System.Windows.Forms.Screen.Bounds`, ponieważ opisuje bieżącą sesję.
  - Metoda została sprawdzona lokalnie na głównej matrycy NCP002B bez dodatkowego monitora: `1920x1080`.

- [x] Powiązać wszystkie dane z tym samym fizycznym ekranem.
  - Nie łączyć `Screen.AllScreens` i `WmiMonitorID` na podstawie pozycji na liście.
  - Użyć wspólnego identyfikatora urządzenia lub ścieżki wyświetlacza.
  - Uwzględniać wyłącznie aktywny fizyczny ekran podczas testu głównej matrycy.

- [x] Poprawić rozpoznawanie matrycy wewnętrznej.
  - Nie rozpoznawać matrycy wyłącznie na podstawie pustego numeru seryjnego.
  - Wykorzystać typ wyjścia, np. `Internal`, `eDP` albo `LVDS`.
  - Gdy sterownik nie udostępnia typu połączenia, nie zgadywać na podstawie numeru seryjnego; ostrzec użytkownika i pozostawić wpis do ręcznej korekty w istniejącym edytorze listy.

- [x] Poprawić obliczanie i prezentację przekątnej.
  - Obliczać przekątną z fizycznej szerokości i wysokości EDID, jeśli są dostępne.
  - Dopasowywać wynik do typowych przekątnych `10.1`, `11.6`, `12.5`, `13.3`, `14`, `15.6`, `16`, `17.3` i `18` cali z tolerancją `0.35` cala.
  - Wynik poza tolerancją zachowywać z jednym miejscem po kropce do zatwierdzenia przez użytkownika.
  - Brak wymiarów oznaczać do ręcznej korekty, bez zgadywania na podstawie nazwy laptopa.

- [x] Poprawić wykrywanie ekranu dotykowego.
  - Nie przypisywać globalnego wyniku `touchscreen` do wszystkich ekranów.
  - Szukać niezależnego od języka identyfikatora HID `HID_DEVICE_UP:000D_U:0004` i dodawać `touch` wyłącznie do rozpoznanej matrycy wewnętrznej.
  - Brak urządzenia HID oznacza brak dopisku `touch`; cały wpis nadal podlega zatwierdzeniu w edytorze listy.

- [x] Rozdzielić obsługę błędów źródeł danych ekranu.
  - Błąd `WmiMonitorBasicDisplayParams` nie powinien blokować odczytu `WmiMonitorID` ani pozostałych dostępnych informacji.
  - Pokazywać użytkownikowi, których konkretnie danych nie udało się odczytać.
  - Pozwalać przejść do ręcznej edycji niepełnego wpisu matrycy.

### Pamięć RAM

- [ ] Ujednolicić znaczenie i prezentację szybkości pamięci RAM (`MHz` a `MT/s`).
  - SMBIOS raportuje pole `Speed` jako szybkość transmisji w `MT/s`, mimo że istniejąca baza i format PHP opisują te wartości jako `MHz`.
  - Przykład: Lenovo z pamięcią LPDDR5X-8533 zwraca `8533`; nie jest to częstotliwość zegara 8533 MHz, lecz szybkość transmisji 8533 MT/s (około 4266,5 MHz zegara).
  - Nie stosować automatycznie dzielenia przez dwa, dopóki nie zostanie uzgodnione, czy baza ma przechowywać rzeczywiste taktowanie, czy zwyczajową szybkość DDR opisaną jako MHz. Zmiana globalna przekształciłaby również DDR4-3200 na 1600 MHz i wymagałaby migracji lub warstwy zgodności dla istniejącej bazy.
  - Do czasu podjęcia decyzji pozostawić obecne działanie bez zmian.

- [x] Po opracowaniu odczytu RAM uzupełnić sposób budowania pola `mainb`.
  - Połączyć rzeczywiste dane płyty z `Win32_BaseBoard` z opisem obsługiwanej konfiguracji pamięci RAM.
  - Zachować format zbliżony do `Latitude 7420 (DDR3L 1600MHz x2, max8GB)`.
  - Typ, znamionowa szybkość i liczba gniazd są odczytywane automatycznie, gdy dane SMBIOS są jednoznaczne.
  - `MaxCapacity` i `MaxCapacityEx` zachowywać wyłącznie diagnostycznie, ponieważ mogą opisywać teoretyczny limit kontrolera zamiast limitu zatwierdzonego dla konkretnego modelu.
  - Maksymalna pojemność musi pochodzić z ręcznie zweryfikowanego `memorySpec` w JSON i mieć zapis `max...GB`.
  - Jeśli `memorySpec` nie zawiera `max...GB`, ostrzec użytkownika, wymusić wpisanie pełnej wartości i zapytać, czy zapisać ją w JSON.
  - Przy różnicy typu, szybkości lub liczby gniazd względem `memorySpec` użytkownik wybiera wartość dla PHP i decyduje, czy zaktualizować JSON; automatyczny odczyt nie zastępuje ręcznie zweryfikowanego maksimum.
  - Nie mylić aktualnie zainstalowanej pamięci z maksymalną pamięcią obsługiwaną przez płytę główną.
  - [x] W komunikatach rozróżniać brak odczytu modułów RAM od braku pełnej konfiguracji pamięci obsługiwanej przez płytę główną.

- [x] Poprawić rozpoznawanie pamięci lutowanej i wymiennej.
  - Obecne wyszukiwanie słów `onboard`, `on board` i `solder` w `DeviceLocator` oraz `BankLabel` jest tylko heurystyką.
  - Wykorzystać także `FormFactor`, `DeviceLocator`, `BankLabel` i dane konkretnego modelu.
  - Grupować rekordy pamięci lutowanej w jeden wpis i nie interpretować `MemoryDevices` jako liczby slotów.
  - Dla modułów niewlutowanych zapisywać uzgodnione `conn'=>'on board'`.
  - Niejednoznaczne lub mieszane dane kierować do interaktywnego wyboru `memorySpec`.

- [x] Rozszerzyć mapowanie `SMBIOSMemoryType`.
  - Uwzględnić brakujące typy, m.in. DDR2 FB-DIMM, LPDDR, LPDDR2, LPDDR3 oraz HBM.
  - Uwzględniono DDR, DDR2, DDR3, FB-DIMM, DDR4, LPDDR–LPDDR5, HBM–HBM3 i DDR5.
  - Nieznanego kodu nie dodawać do PHP; użytkownik może poprawić gotowy wpis RAM w interaktywnym przeglądzie.

- [x] Przetwarzać każdy moduł RAM niezależnie.
  - Błąd lub brak właściwości jednego wpisu SMBIOS nie powinien usuwać z wyniku wszystkich pozostałych modułów.
  - Pokazywać ostrzeżenie dotyczące konkretnego lokalizatora lub banku.

- [x] Ustalić zakres danych RAM używanych w PHP.
  - Używać `Capacity`, `Speed`, `SMBIOSMemoryType`, `DeviceLocator`, `BankLabel`, `FormFactor` i poprawnego `SerialNumber`.
  - `Speed` jest wartością podstawową, a `ConfiguredClockSpeed` wyłącznie wartością awaryjną.
  - Nie dodawać do PHP identyfikatora producenta JEDEC, numeru części, napięć ani pozostałych danych diagnostycznych.

- [x] Filtrować niewiarygodne dane identyfikacyjne RAM.
  - Usuwać spacje z początku i końca producenta, numeru części i numeru seryjnego.
  - Traktować wartości puste, `00000000`, `FFFFFFFF` i typowe teksty zastępcze jako brak danych.

- [x] Ustalić docelowy format opisu RAM w PHP.
  - Używać formatu `16GB 3200MHz DDR4`.
  - Każdy moduł wymienny zapisywać osobno z `conn'=>'on board'` i poprawnym numerem seryjnym w `sn`.
  - Rekordy pamięci lutowanej grupować według typu i szybkości, zapisywać z `conn'=>'soldered'` oraz bez wspólnego numeru seryjnego.
  - Zachować krótki i przewidywalny format wymagany przez istniejący import PHP.

### Dyski

- [x] Zastąpić lub uzupełnić `Win32_DiskDrive` dokładniejszym źródłem danych.
  - Używać `Get-PhysicalDisk` albo `MSFT_PhysicalDisk` jako źródła podstawowego.
  - Pozostawić `Win32_DiskDrive` jako rozwiązanie awaryjne i źródło danych uzupełniających.
  - Nie łączyć rekordów na podstawie pozycji: `Win32_DiskDrive` jest używane tylko wtedy, gdy źródło podstawowe nie zwróci żadnych dysków.

- [x] Rozdzielić protokół, magistralę i format fizyczny dysku.
  - Nie zakładać bezwarunkowo, że każdy dysk NVMe ma format M.2.
  - Rozpoznawać `BusType`, np. NVMe, SATA, SAS i USB.
  - Rozpoznawać `MediaType`, np. SSD, HDD i SCM.
  - Format odczytywać przez `IOCTL_STORAGE_QUERY_PROPERTY`; gdy sterownik zwraca `Unknown`, poprosić użytkownika o zatwierdzenie podpowiedzi wynikającej z `BusType`.
  - Dla NVMe z nieznanym formatem proponować `M.2`, ale nie zapisywać go bez zatwierdzenia.

- [x] Rozszerzyć dane dysku dostępne podczas weryfikacji.
  - Odczytywać `Manufacturer`, `Model`, `SerialNumber`, `FirmwareVersion`, `BusType`, `MediaType` i `PhysicalLocation`.
  - Pokazywać `HealthStatus` oraz `OperationalStatus` diagnostycznie.
  - Jeśli sterownik pozwala, odczytywać temperaturę, zużycie, czas pracy oraz liczniki błędów przez `Get-StorageReliabilityCounter`.
  - Brak liczników niezawodności traktować jako brak danych, a nie błąd całej inwentaryzacji.
  - [x] Przed główną tabelą podzespołów pokazywać dla każdego dysku osobną sekcję z nazwą, `HealthStatus`, czasem pracy, łączną ilością odczytanych i zapisanych danych oraz poziomem zużycia.
  - [x] Dla NVMe odczytywać standardowy dziennik SMART/Health bezpośrednio przez `IOCTL_STORAGE_QUERY_PROPERTY`, ponieważ `Get-StorageReliabilityCounter` nie zawsze udostępnia liczniki danych i czasu pracy.
  - [x] Przeliczać `DataUnitRead` i `DataUnitWritten` zgodnie ze specyfikacją NVMe: jedna jednostka licznika odpowiada 1000 bloków po 512 bajtów.
  - [x] Używać `Get-StorageReliabilityCounter` jako źródła awaryjnego dla czasu pracy i zużycia; niedostępne wartości wyświetlać jako `brak danych`, nigdy jako sztuczne zero.
  - [x] Danych diagnostycznych SMART nie zapisywać w PHP.

- [x] Przetwarzać każdy dysk niezależnie.
  - Błąd odczytu jednego nośnika nie powinien usuwać pozostałych dysków z wyniku.
  - W ostrzeżeniu wskazywać konkretny model albo identyfikator problematycznego urządzenia.

- [x] Filtrować i normalizować identyfikatory dysków.
  - Usuwać zbędne spacje z modelu, producenta, firmware i numeru seryjnego.
  - Odrzucać puste numery seryjne i typowe wartości zastępcze.
  - Unikać powtarzania słów takich jak `NVMe` lub nazwy producenta, jeśli występują już w modelu.

- [x] Ustalić docelowy format wpisu dysku w PHP.
  - Zachować typ części `Hard Disk`, jeśli wymaga tego istniejący importer.
  - Do `desc` dodawać pojemność dziesiętną, `BusType`, `MediaType` i oczyszczony model bez powtórzeń.
  - Poprawny numer seryjny zapisywać w opcjonalnym polu `sn`; normalizować format NVMe z grupami rozdzielonymi znakami `_`.
  - Gdy `HealthStatus` nie jest `Healthy`, ostrzegać użytkownika; wpis nadal trafia do istniejącego przeglądu podzespołów.
  - Zachować pojemność dziesiętną, np. `256GB`, zgodną z oznaczeniem producenta.

### Karty sieciowe

- [x] Zastąpić przestarzałe `Win32_NetworkAdapter` nowszym źródłem danych.
  - Używać `Get-NetAdapter -Name * -IncludeHidden` albo `MSFT_NetAdapter` jako źródła podstawowego.
  - Pozostawić `Win32_NetworkAdapter` jako rozwiązanie awaryjne.
  - Korelować dane z obu źródeł po `InterfaceIndex`, `PnPDeviceID`, GUID albo innym stabilnym identyfikatorze.

- [x] Dokładniej klasyfikować adaptery sieciowe.
  - Rozróżniać Ethernet, Wi-Fi, Bluetooth PAN, USB Ethernet i urządzenia wbudowane.
  - Odfiltrować VPN, Hyper-V, loopback, WAN Miniport i pozostałe adaptery wirtualne.
  - Nie polegać wyłącznie na `PhysicalAdapter = true`.
  - Wykorzystać `PhysicalMediaType`, `HardwareInterface`, `Virtual`, `ConnectorPresent`, opis oraz `PnPDeviceID`.

- [x] Ustalić sposób zapisywania rodzaju połączenia.
  - Rozpoznawać urządzenia wbudowane na podstawie magistrali PCI i zapisywać je jako `on board`.
  - Rozpoznawać adaptery USB na podstawie `PnPDeviceID` i nie dodawać ich do PHP.
  - Adapter taki jak `Realtek USB GbE` jest urządzeniem zewnętrznym i ma zostać pominięty zamiast otrzymywać `conn'=>'USB'` albo `conn'=>'on board'`.

- [x] Preferować trwały adres MAC.
  - Używać poprawnego `PermanentAddress`, jeśli sterownik go udostępnia.
  - Używać `MacAddress` jako wartości awaryjnej.
  - Normalizować adres do wielkich liter bez separatorów.
  - Wykrywać adres lokalnie administrowany i ostrzegać, że może być zmieniony lub losowy.
  - Odrzucać adresy puste, zerowe, broadcast i inne niewiarygodne wartości.

- [x] Ustalić zachowanie przy braku pewnego adresu MAC.
  - Brak trwałego i bieżącego poprawnego MAC powoduje ostrzeżenie oraz pominięcie `sn`, ale nie usuwa fizycznego adaptera.
  - Nie zapisywać bez ostrzeżenia losowego adresu Wi-Fi jako sprzętowego numeru seryjnego.

- [x] Ustalić zakres wykrywanych adapterów.
  - Zapisywać adaptery wyłączone lub odłączone, jeśli są fizycznie zainstalowane; bieżący `Status` nie decyduje o uwzględnieniu.
  - Zachować wbudowane Wi-Fi i Bluetooth PAN; pomijać fizyczne adaptery USB.
  - Pokazywać użytkownikowi przyczynę pominięcia każdego adaptera.

- [x] Przetwarzać każdy adapter niezależnie.
  - Błąd jednego adaptera nie powinien usuwać wszystkich kart sieciowych z wyniku.
  - W ostrzeżeniu wskazywać nazwę lub identyfikator problematycznego urządzenia.

- [x] Zachować przewidywalny format PHP.
  - Pozostawić typ `Network Card`.
  - Zapisywać opis urządzenia w `desc`, sposób połączenia w `conn` oraz zatwierdzony MAC w opcjonalnym `sn`.
  - Unikać dodawania do `desc` dynamicznych danych, takich jak bieżąca szybkość połączenia.

### Karta dźwiękowa

- [x] Klasyfikować wykryte urządzenia audio.
  - Rozróżniać wewnętrzny kodek, audio HDMI/DisplayPort, urządzenia USB, Bluetooth i audio stacji dokującej.
  - Wykorzystać `Caption`, `ProductName`, `Manufacturer` i `PNPDeviceID`.
  - Nie traktować każdego wpisu `Win32_SoundDevice` jako osobnej wewnętrznej karty dźwiękowej.

- [x] Ustalić zakres urządzeń audio zapisywanych do PHP.
  - Pomijać audio HDMI/DisplayPort.
  - [x] Zewnętrzne karty dźwiękowe USB mają być odłączone przed inwentaryzacją i pomijane, jeśli mimo to zostaną wykryte.
  - Pomijać urządzenia audio Bluetooth.
  - Automatycznie dodawać wyłącznie główny wewnętrzny kodek.
  - Pokazywać użytkownikowi listę urządzeń pominiętych wraz z przyczyną.

- [x] Poprawić ustalanie rodzaju połączenia.
  - Zapisywać `on board` wyłącznie dla rozpoznanego wewnętrznego kodeka.
  - Rozpoznawać i pomijać `HDMI/DisplayPort`, zewnętrzne `USB` oraz `Bluetooth`.
  - Nie przypisywać wartości `on board` wszystkim urządzeniom audio.
  - Pomijać kontrolery Intel Smart Sound Technology, ponieważ nie są osobnymi kartami dźwiękowymi.
  - Gdy jedynym kandydatem jest `Realtek USB Audio`, pytać użytkownika, czy jest to wewnętrzny kodek laptopa.

- [x] Walidować stan urządzeń audio.
  - [x] Ostrzegać, gdy `ConfigManagerErrorCode` jest inny niż `0` albo `Status` nie wskazuje poprawnego działania.
  - Ostrzegać przy ogólnym sterowniku lub nazwie `High Definition Audio Device`.
  - [x] Ostrzegać, jeśli w laptopie nie znaleziono żadnego wewnętrznego kodeka.
  - Zdecydować, czy brak sprawnego wewnętrznego audio ma blokować zapis, czy tylko wymagać potwierdzenia.

- [x] Przetwarzać każde urządzenie audio niezależnie.
  - Błąd pojedynczego wpisu nie powinien usuwać wszystkich urządzeń audio z wyniku.
  - W ostrzeżeniu wskazywać nazwę albo identyfikator problematycznego urządzenia.

- [x] Zachować prosty format głównego kodeka w PHP.
  - Pozostawić typ `Sound Card`.
  - Dla rozpoznanego kodeka wewnętrznego zapisywać krótki opis, np. `Realtek Audio`, oraz `conn'=>'on board'`.

### Karta graficzna

- [x] Zastąpić albo uzupełnić `Win32_VideoController` dokładniejszym źródłem danych o pamięci GPU.
  - Nie traktować `AdapterRAM` jako wiarygodnej ilości pamięci dla współczesnych kart graficznych.
  - Uwzględnić ograniczenie 32-bitowego pola `AdapterRAM`, szczególnie dla kart mających więcej niż 4 GB VRAM.
  - Rozważyć użycie DXGI do odczytu 64-bitowych wartości pamięci dedykowanej, dedykowanej pamięci systemowej i pamięci współdzielonej.
  - Dla dedykowanego GPU dodawać do `desc` ilość rzeczywistej pamięci dedykowanej dopiero wtedy, gdy została wiarygodnie odczytana przez DXGI.
  - Pozostawić `Win32_VideoController` jako źródło pomocnicze lub awaryjne.

- [x] Poprawnie prezentować pamięć grafiki zintegrowanej.
  - Nie przedstawiać wartości takiej jak `1024MB` jako rzeczywistego VRAM układu zintegrowanego, jeśli jest to tylko pamięć współdzielona albo wartość raportowana przez sterownik.
  - Dla zintegrowanego GPU pomijać liczbę MB w `desc`.

- [x] Filtrować fizyczne adaptery graficzne.
  - Zachować osobny wpis dla każdego fizycznego GPU, np. Intel oraz NVIDIA/AMD w laptopie hybrydowym.
  - Odfiltrować adaptery zdalne, programowe oraz `Microsoft Basic Display Adapter`, ale pokazywać użytkownikowi informację o ich pominięciu.
  - Nie uznawać obecności kilku kontrolerów za błąd.

- [x] Klasyfikować fizyczne adaptery jako zintegrowane lub dedykowane.
  - Rozpoznawać typowe rodziny Intel UHD/Iris/HD, AMD Radeon Graphics/Vega oraz dedykowane NVIDIA i AMD Radeon RX/Pro.
  - Nie używać `AdapterRAM` do klasyfikacji; przy niejednoznacznym urządzeniu pytać użytkownika o typ karty.

- [x] Poprawić ustalanie rodzaju połączenia karty graficznej.
  - Nie przypisywać każdej karcie stałej wartości `on board,HDMI`.
  - Uwzględnić, że złącza HDMI, DisplayPort i USB-C są cechą całego laptopa, płyty lub stacji dokującej i nie zawsze można je jednoznacznie przypisać do konkretnego GPU.
  - Po wykryciu każdej fizycznej karty pytać użytkownika o połączenia/wyjścia, z podpowiedzią `on board` oraz przykładami `HDMI`, `DisplayPort` i `USB-C`.
  - Zapisywać odpowiedź bezpośrednio w polu `conn`; nie próbować automatycznie wyliczać wszystkich gniazd maszyny.

- [x] Przetwarzać każdy adapter graficzny niezależnie.
  - Błąd jednego adaptera nie powinien usuwać pozostałych kart graficznych z wyniku.
  - W ostrzeżeniu wskazywać nazwę albo identyfikator problematycznego urządzenia.

- [x] Ustalić docelowy format wpisu GPU w PHP.
  - Pozostawić typ `Graphic Card`.
  - [x] Dla grafiki zintegrowanej używać krótkiego opisu bez mylącej ilości pamięci, np. `Intel(R) Iris(R) Xe Graphics`.
  - Dla grafiki dedykowanej używać formatu takiego jak `4096MB NVIDIA GeForce RTX 3050`, jeśli ilość VRAM została wiarygodnie odczytana.
  - Dane sterownika, identyfikatory i pamięć współdzieloną pozostawić wyłącznie w diagnostyce konsolowej.

### Bateria

- [x] Rozszerzyć źródła danych o baterii.
  - [x] Pozostawić `Win32_Battery` jako źródło bieżącego stanu, poziomu naładowania, napięcia i awaryjnego opisu.
  - Uzupełnić dane klasami baterii z przestrzeni `root\wmi`.
  - [x] Używać `powercfg /batteryreport /xml` jako podstawowego źródła modelu, producenta, pojemności i liczby cykli.
  - [x] Korelować raport `powercfg` z `Win32_Battery` po identyfikatorze/nazwie baterii; pozycję stosować tylko dla jednoznacznego zestawu zawierającego po jednym rekordzie.

- [X] Rozszerzyć dane baterii dostępne podczas weryfikacji.
  - [x] Odczytywać i pokazywać producenta oraz nazwę lub model; numer seryjny celowo ignorować, ponieważ jest skanowany osobno z etykiety baterii.
  - [x] Pokazywać pojemność projektową oraz aktualną pojemność po pełnym naładowaniu.
  - [x] Odczytywać liczbę cykli ładowania, jeśli sterownik i firmware ją udostępniają; wartość `0` traktować jako brak danych.
  - [x] Pokazywać napięcie projektowe, bieżący poziom naładowania oraz stan baterii.
  - [x] Brak pojedynczej wartości traktować jako `brak danych`, a nie błąd całego odczytu baterii.

- [x] Obliczać i prezentować kondycję baterii.
  - Obliczać kondycję jako `FullChargeCapacity / DesignCapacity * 100%`.
  - Obliczać zużycie jako `100% - kondycja`.
  - Wykonywać obliczenia tylko wtedy, gdy obie pojemności są wiarygodne i pojemność projektowa jest większa od zera.
  - Ostrzegać, gdy kondycja spadnie poniżej 80%, ale nie blokować z tego powodu zapisu inwentaryzacji.
  - Nie traktować bieżącego poziomu naładowania jako kondycji baterii.

- [x] Walidować dane identyfikacyjne baterii.
  - Usuwać zbędne spacje z producenta, modelu i numeru seryjnego.
  - Odrzucać puste numery seryjne oraz typowe wartości zastępcze.
  - [x] Nie wyświetlać ani nie zapisywać automatycznie wykrytego numeru seryjnego; użytkownik skanuje go bezpośrednio z baterii.

- [x] Ustalić docelowy format wpisu baterii w PHP.
  - Pozostawić typ `Battery` i prosty opis, np. `Internal Battery`.
  - Dane o pojemności, kondycji, liczbie cykli i bieżącym naładowaniu pozostawić wyłącznie w diagnostyce konsolowej.
  - Pole `sn` zawsze dodawać, ale pozostawiać je puste: `'sn'=>''`.

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

- [x] Poprawić rozpoznawanie laptopów, tabletów i urządzeń 2-w-1.
  - Warunek `PCSystemType -eq 2` może pominąć tablety i urządzenia konwertowalne.
  - Zweryfikować wartości `PCSystemType`/`PCSystemTypeEx` i sposób dodawania sufiksu `_laptop`.

- [x] Usunąć sztuczne pomniejszanie `MaxClockSpeed` o 1 MHz.
  - Ustalić, czy było to obejście konkretnego problemu z formatem danych.

- [x] Zweryfikować ręczną tabelę modeli.
  - Sprawdzić parametry płyty głównej, pamięci, zasilacza i poboru mocy.
  - Szczególnie przejrzeć wpisy wyglądające na skopiowane pomiędzy różnymi modelami.
  - [x] Obsłużyć sytuację, gdy wykrytego modelu laptopa nie ma w pliku `hardware-models.json`.
    - Automatycznie uzupełniać `model`, `baseboardFallback`, wykrytą część `memorySpec` oraz jednoznaczny `deviceType`.
    - Pytać o zweryfikowaną maksymalną pojemność RAM, `powerMaxW`, `powerW` i `other`.
    - Przed zapisem pokazywać kompletny wpis i wymagać jego zatwierdzenia.
  - [x] Przenieść tabelę do osobnego pliku JSON, aby łatwiej ją utrzymywać.

## Priorytet niższy / porządki

- [x] Po uruchomieniu skryptu wyświetlać użytkownikowi główne założenia.
  1. Laptop nie może mieć podłączonych dodatkowych monitorów — stacjonarnych ani zdalnych.
  2. Przed rozpoczęciem inwentaryzacji należy odłączyć urządzenia USB, w szczególności zewnętrzne karty sieciowe, karty dźwiękowe, dyski, pendrive'y i stacje dokujące.
  3. Dalszy odczyt rozpoczyna się dopiero po potwierdzeniu przygotowania sprzętu; użytkownik może bezpiecznie anulować działanie.

- [x] Pokazywać stronę wsparcia Dell dla zinwentaryzowanego urządzenia.
  - Po odczytaniu numeru seryjnego (Service Tagu) wyświetlić w konsoli adres strony urządzenia w serwisie Dell.
  - Nie otwierać automatycznie domyślnej przeglądarki.
  - Strony oraz komentarza w PHP nie generować dla urządzeń innych producentów.

- [x] Umożliwić wpisanie dowolnej etykiety systemu.
  - Oprócz wyboru `W10P` lub `W11P` pozwolić użytkownikowi podać inną wartość etykiety.
  - Własna etykieta nie może być pusta; przy ponownej edycji aktualna wartość jest podpowiedzią.

- [x] Ujednolicić podpowiedzi i wartości domyślne w polach formularza.
  - Wartość pokazana jako podpowiedź, np. dla pola pomieszczenia, powinna być faktyczną wartością domyślną zatwierdzaną klawiszem Enter.
  - Nawiasy kwadratowe `[wartość]` oznaczają faktyczną, niepustą wartość domyślną, a `(np. wartość)` jedynie przykład.
  - Puste pola nie pokazują mylącego `[]` i są oznaczane jako opcjonalne.

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
