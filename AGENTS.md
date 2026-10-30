# Zasady współpracy

- Zanim zmienisz jakikolwiek plik, opisz dokładnie proponowane zmiany i poczekaj na wyraźną zgodę użytkownika.
- Nie wprowadzaj zmian tylko dlatego, że znalazłeś możliwe ulepszenie.
- Nie cofaj ani nie nadpisuj istniejących zmian użytkownika.
- Po zatwierdzonej zmianie uruchom pełne testy.
- Po każdej wykonanej zmianie podaj krótką notatkę do commita w języku angielskim.
- Pracuj zgodnie z Windows PowerShell 5.1.
- Produkcyjny katalog to `\\ntshare\helpdesk\scripts\GetHardware`.
- Produkcyjny `hardware-models.json` jest nadrzędnym źródłem danych, ponieważ podczas inwentaryzacji dopisywane są tam nowe modele.
- `Deploy.ps1` ma najpierw pobierać bazę z produkcji i nigdy nie może nadpisywać jej lokalną kopią.
- Nie wykonuj prawdziwego wdrożenia bez jednoznacznego polecenia użytkownika.

# Ważne decyzje projektowe

- Rozbieżności między wykrytym RAM-em a bazą są rozwiązywane interaktywnie.
- Temat MHz/MT/s jest odłożony w TODO; obecnego zachowania nie zmieniaj.
- Dla dźwięku `Win32_SoundDevice` jest metodą podstawową. Jeśli nie wykryje kodeka, używany jest `Get-PnpDevice`, a użytkownik sam wybiera wynik.
- Fallback audio pomija AMP, UAJ, mikrofony, endpointy, streaming, Bluetooth oraz kontrolery Intel SST.
- Automatycznie wykryta bateria ma połączenie „on board” i pusty numer seryjny.
- Jeśli podsumowanie rozmowy różni się od aktualnego repozytorium, nie zmieniaj niczego — pokaż rozbieżność.
