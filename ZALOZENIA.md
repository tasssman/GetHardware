# Założenia projektu GetHardware

Dokument zawiera uzgodnione wymagania dla nowej wersji skryptu. Będzie uzupełniany w miarę podejmowania kolejnych decyzji.

## Uruchamianie

- Skrypt jest uruchamiany bezpośrednio z konsoli Windows PowerShell.
- Projekt nie używa pliku BAT.
- Docelowa nazwa nowego skryptu to `Get-HardwareInventory.ps1`.
- Interfejs jest konsolowy i interaktywny, w stylu projektu `windows11-unattend-install`:
  - numerowane listy wyboru;
  - ponawianie pytania po podaniu nieprawidłowej wartości;
  - potwierdzenia `Y/N` dla istotnych decyzji;
  - czytelne komunikaty, ostrzeżenia i możliwość anulowania bez zapisania niepełnych danych.
- Nazwa spisu nie jest przekazywana jako parametr skryptu.
- Na początku pracy z urządzeniem skrypt automatycznie odczytuje Service Tag/numer seryjny z BIOS-u.
- Jeśli odczyt się nie powiedzie albo zwróci pustą lub niewiarygodną wartość, skrypt zgłasza problem i dopiero wtedy prosi użytkownika o ręczne podanie identyfikatora.
- Przed użyciem automatycznie odczytany lub ręcznie podany identyfikator jest normalizowany i walidowany.

## Baza modeli

- Baza znanych modeli jest utrzymywana ręcznie.
- Dane modeli będą oddzielone od logiki skryptu i zapisane w pliku `hardware-models.json`.
- Skrypt wczytuje oraz waliduje bazę i nigdy nie zmienia jej bez decyzji użytkownika.
- Wyjątkiem jest interaktywnie zatwierdzona aktualizacja pola `memorySpec`: przy różnicy między SMBIOS i JSON-em użytkownik może zapisać wykrytą albo własną wartość w bazie.
- Jeśli wykrytego modelu nie ma w bazie, skrypt zatrzymuje dalsze przetwarzanie i prosi o ręczne dopisanie modelu do `hardware-models.json`.
- Po potwierdzeniu przez użytkownika skrypt ponownie wczytuje bazę i kontynuuje dopiero wtedy, gdy model został poprawnie dodany.

## Spisy i pliki wynikowe

- Każde zinwentaryzowane urządzenie jest zapisywane w osobnym pliku PHP nazwanym jego Service Tagiem/numerem seryjnym, np. `13QJ7D3.php`.
- Równolegle jest utrzymywany jeden plik zbiorczy PHP zawierający kolejne urządzenia należące do danego spisu.
- Przy pierwszym uruchomieniu, gdy nie istnieje jeszcze żaden spis, skrypt prosi o podanie jego nazwy.
- Jeżeli istnieją już spisy, skrypt wyświetla ich numerowaną listę i pozwala:
  - wybrać istniejący spis;
  - utworzyć nowy spis i nadać mu nazwę.
- Nazwa spisu nie jest wpisana na stałe w kodzie i nie wymaga edytowania skryptu.
- Skrypt sprawdza nazwę spisu pod kątem niedozwolonych znaków.
- Ponowne wykrycie Service Tagu już istniejącego w wybranym spisie wymaga decyzji użytkownika i nie może bezwarunkowo utworzyć duplikatu.
- Dla istniejącego Service Tagu skrypt pozwala:
  - zastąpić istniejący rekord bez zmiany jego miejsca w kolejności spisu;
  - pominąć zapis;
  - anulować operację.

## Lokalizacja wyników

- Wszystkie dane wynikowe są zapisywane pod katalogiem, w którym znajduje się uruchomiony skrypt (`$PSScriptRoot`).
- Docelowa struktura nie zawiera dodatkowego katalogu `devices`:

  ```text
  <katalog skryptu>\
  └── output\
      └── BI_ONE\
          ├── 13QJ7D3.php
          ├── 8ABC123.php
          └── BI_ONE.php
  ```

- `BI_ONE` jest przykładową nazwą spisu; katalog spisu i plik zbiorczy otrzymują tę samą nazwę.

## Format PHP

- Plik urządzenia zawiera tablicę `$partsLapt`, tablicę `$C`, wywołanie `addComp()` oraz komentarz z adresem strony serwisowej Dell.
- Pole `sn` podzespołu jest opcjonalne.
- Identyfikator laptopa przekazywany do `addComp()` ma postać `<ServiceTag>_laptop`.
- Uzgodnione wywołanie ma trzy argumenty:

  ```php
  addComp('13QJ7D3_laptop',$C,$partsLapt);
  ```

- Wartości tekstowe muszą być kodowane tak, aby nie mogły uszkodzić składni generowanego PHP.

## Dane wprowadzane ręcznie

- `bought`:
  - użytkownik podaje datę w formacie `rok-miesiąc-dzień` (`YYYY-MM-DD`);
  - wszystkie urządzenia należące do jednego spisu mają tę samą wartość;
  - dla nowego spisu skrypt pyta o datę;
  - dla istniejącego spisu skrypt odczytuje istniejącą wartość i nie pyta o nią ponownie;
  - niespójne wartości w istniejącym spisie są błędem wymagającym wyjaśnienia.
- `warr`:
  - użytkownik samodzielnie sprawdza dane gwarancji i wpisuje wartość podczas obsługi każdego urządzenia;
  - pole jest obowiązkowe i ma format `YYYY-MM-DD+N`;
  - data oznacza początek gwarancji, a `N` liczbę pełnych lat gwarancji;
  - przykładowa wartość: `2021-05-20+3`;
  - skrypt sprawdza poprawność daty oraz dodatnią, całkowitą liczbę lat.
- `cenan`:
  - użytkownik podaje cenę w PLN;
  - separatorem części dziesiętnej jest przecinek, np. `1414,08`;
  - do PHP trafia sama wartość bez symbolu waluty.
- `label`:
  - użytkownik wybiera z numerowanej listy co najmniej `W10P` albo `W11P`.
- `room`:
  - wartość jest podawana interaktywnie;
  - domyślna podpowiedź to `A216`, akceptowana pustym Enterem.
- `note`:
  - wartość jest podawana interaktywnie;
  - podpowiedź ma postać `SCC:;REFURBISHED;` i pozwala użytkownikowi uzupełnić numer SCC.

## Przegląd wykrytych podzespołów

- Po automatycznym odczycie skrypt wyświetla listę podzespołów i udostępnia opcje:
  1. zaakceptuj listę;
  2. edytuj wybrany element;
  3. dodaj element;
  4. usuń element;
  5. odczytaj sprzęt ponownie;
  6. anuluj.
- Listy i formularze ponawiają pytanie po otrzymaniu nieprawidłowej wartości.
- Przed końcowym zapisem skrypt pokazuje pełne podsumowanie danych.

## Czytelność kodu

- Kod odpowiedzialny za automatyczne wyszukiwanie sprzętu ma być dobrze skomentowany, wyraźnie wydzielony i spójny.
- Poszczególne sekcje wykrywania (ekrany, RAM, dyski, sieć, dźwięk, grafika i bateria) powinny być łatwe do odnalezienia i modyfikowania.
- Komentarze mają wyjaśniać źródło oraz ograniczenia odczytywanych danych, a nie jedynie powtarzać nazwę polecenia.

## Do dalszego ustalenia

- Plik zbiorczy oznacza każdy rekord komentarzami `GET-HARDWARE-BEGIN` i `GET-HARDWARE-END`.
- Znaczniki umożliwiają zastąpienie urządzenia bez zmiany jego pozycji w spisie.
- Zapis jest wykonywany przez pliki tymczasowe pod blokadą `.gethardware.lock`.
