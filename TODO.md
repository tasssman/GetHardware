# TODO — GetHardware

Lista problemów wykrytych podczas przeglądu skryptów. Składnia pliku PowerShell jest poprawna, ale poniższe punkty wpływają na bezpieczeństwo, spójność i jakość generowanych danych.

## Priorytet wysoki

- [x] Ujednolicić sposób uruchamiania skryptu.
  - Plik BAT uruchamiający inną kopię PS1 z udziału sieciowego został usunięty.
  - Skrypt będzie uruchamiany bezpośrednio z konsoli Windows PowerShell.
  - Lokalny plik PS1 w repozytorium jest źródłem prawdy.

- [ ] Bezpiecznie kodować wartości umieszczane w generowanym PHP.
  - Apostrof, ukośnik lub znak nowej linii w nazwie urządzenia może zepsuć składnię pliku.
  - Dodać funkcję kodującą tekst jako poprawny literał PHP albo generować dane w bezpiecznym formacie, np. JSON.
  - Zweryfikować wygenerowany kod przed jego zapisaniem do pliku zbiorczego.

- [ ] Zabezpieczyć zapis do `BI_ONE.php`.
  - Zapobiegać wielokrotnemu dopisywaniu tego samego Service Tagu.
  - Zastosować blokadę pliku lub zapis atomowy, jeżeli skrypt może być uruchamiany równocześnie na wielu komputerach.
  - Nie dopisywać rekordu, jeśli zbieranie danych zakończyło się częściowym błędem.

- [ ] Dodać walidację danych wejściowych i obsługę błędów.
  - Sprawdzać, czy Service Tag, model i dane procesora zostały poprawnie odczytane.
  - Dodać kontrolowane `ErrorAction` oraz czytelny komunikat końcowy.
  - Rozważyć `Set-StrictMode`.

## Priorytet średni

- [ ] Usunąć zduplikowaną regułę `Vostro 3400`.
  - Obie gałęzie `switch` są wykonywane, przez co powstaje osiem wartości, a kod wykorzystuje tylko pierwsze cztery.
  - Ustalić właściwe wartości mocy i opisu pamięci.

- [ ] Poprawić wykrywanie monitorów i matrycy.
  - Obecnie rozdzielczość ostatniego wykrytego ekranu jest przypisywana wszystkim monitorom.
  - Nie klasyfikować urządzenia jako `Monitor` lub `Matrix` wyłącznie na podstawie długości numeru seryjnego.
  - Powiązać rozdzielczość, nazwę i numer seryjny z tym samym ekranem.
  - Wiarygodniej wykrywać ekran dotykowy.

- [ ] Poprawić rozpoznawanie laptopów, tabletów i urządzeń 2-w-1.
  - Warunek `PCSystemType -eq 2` może pominąć tablety i urządzenia konwertowalne.
  - Zweryfikować wartości `PCSystemType`/`PCSystemTypeEx` i sposób dodawania sufiksu `_laptop`.

- [ ] Poprawić zbieranie danych o podzespołach.
  - Nie oznaczać każdego dysku jako `M.2`; wykorzystać rzeczywisty typ magistrali/interfejsu.
  - Nie oznaczać każdego modułu RAM jako `on board`; wykorzystać informacje o slocie i typie pamięci.
  - Nie przypisywać każdej karcie graficznej połączenia `on board,HDMI`.
  - Odfiltrować Bluetooth, WAN i inne adaptery, jeśli nie powinny być rejestrowane jako karty sieciowe.
  - Zweryfikować wiarygodność `AdapterRAM` dla współczesnych kart graficznych.
  - Dla komputerów wieloprocesorowych prawidłowo zsumować lub opisać rdzenie.

- [ ] Usunąć sztuczne pomniejszanie `MaxClockSpeed` o 1 MHz.
  - Ustalić, czy było to obejście konkretnego problemu z formatem danych.

- [ ] Zweryfikować ręczną tabelę modeli.
  - Sprawdzić parametry płyty głównej, pamięci, zasilacza i poboru mocy.
  - Szczególnie przejrzeć wpisy wyglądające na skopiowane pomiędzy różnymi modelami.
  - Rozważyć przeniesienie tabeli do osobnego pliku CSV/JSON, aby łatwiej ją utrzymywać.

## Priorytet niższy / porządki

- [ ] Uporządkować pola wymagające ręcznego uzupełnienia.
  - Data zakupu jest wpisana na stałe dla całego uruchomienia.
  - `warr`, cena, licencja, pokój i notatka zawierają `QQ_POPRAW`.
  - Każdy opis ekranu jest bezwarunkowo oznaczany `QQ_POPRAW`.
  - Rozważyć parametry skryptu lub interaktywny formularz z walidacją.

- [ ] Zweryfikować algorytm wyliczania przekątnej matrycy.
  - Obecnie przekątna jest zgadywana na podstawie cyfry występującej w nazwie modelu.
  - Dla nierozpoznanych modeli pozostawić wartość pustą albo oznaczyć ją do ręcznej weryfikacji.

- [ ] Uporządkować kod i nazewnictwo.
  - Zmienne `$monitorInfo`, `$ram`, `$disk`, `$network`, `$sound`, `$graphics` i `$battery` służą tylko do efektów ubocznych pętli.
  - Usunąć nieużywany kod i stare komentarze albo opisać ich przeznaczenie.
  - Poprawić literówki w komentarzach oraz ujednolicić wcięcia i nazwy pól.

- [ ] Dodać dokumentację i testy.
  - Utworzyć README opisujące wymagania, sposób uruchomienia, format wyniku oraz znaczenie pól.
  - Dodać testy funkcji formatujących i generowania PHP z zamockowanymi danymi sprzętowymi.
  - Dodać przypadki testowe dla nieznanego modelu, pustego Service Tagu, kilku monitorów i znaków specjalnych.

- [ ] Rozpocząć śledzenie projektu w Git.
  - Repozytorium nie ma jeszcze commitów, a pliki robocze są nieśledzone.
  - Ustalić, czy plik `.bak` ma pozostać w repozytorium.
