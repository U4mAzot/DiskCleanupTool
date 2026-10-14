# DiskCleanupTool - czyszczenie dysku

Skrypt PowerShell do szybkiego zwalniania miejsca na dysku przy zgłoszeniach typu
„brak miejsca na dysku C:” albo „komputer zwolnił”. Przed czyszczeniem pokazuje,
ile miejsca zajmuje każda lokalizacja, a po czyszczeniu ile miejsca odzyskano.

## Co czyści

| Lokalizacja | Ścieżka | Uwagi |
|-------------|---------|-------|
| Pliki tymczasowe użytkownika | `%TEMP%` | |
| Pliki tymczasowe Windows | `C:\Windows\Temp` | wymaga administratora |
| Cache Chrome | `%LOCALAPPDATA%\Google\Chrome\User Data\*\Cache` | pomijany, gdy Chrome jest otwarty |
| Cache Edge | `%LOCALAPPDATA%\Microsoft\Edge\User Data\*\Cache` | pomijany, gdy Edge jest otwarty |
| Cache Firefox | `%LOCALAPPDATA%\Mozilla\Firefox\Profiles\*\cache2` | pomijany, gdy Firefox jest otwarty |
| Kosz | | |

Skrypt **nie usuwa** dokumentów, haseł, zakładek ani historii przeglądarki,
tylko pliki tymczasowe i pamięć podręczną. Pliki używane przez programy są
bezpiecznie pomijane.

## Użycie

```powershell
# Podgląd: ile miejsca można odzyskać (nic nie jest usuwane)
.\Start-DiskCleanup.ps1 -WhatIf

# Czyszczenie (najlepiej jako administrator)
.\Start-DiskCleanup.ps1

# Bez opróżniania Kosza i bez cache przeglądarek
.\Start-DiskCleanup.ps1 -SkipRecycleBin -SkipBrowsers
```

## Przykładowy wynik

```
=== Czyszczenie dysku: PC-01 ===

Lokalizacja                  Rozmiar  Usunięto Status
-----------                  -------  -------- ------
Pliki tymczasowe użytkownika 1,24 GB  1,19 GB  Wyczyszczono
Pliki tymczasowe Windows     312,5 MB 298,0 MB Wyczyszczono
Cache Google Chrome          645,2 MB 0 KB     Pominięto (zamknij przeglądarkę)
Cache Microsoft Edge         210,8 MB 205,3 MB Wyczyszczono
Kosz                         2,03 GB  2,03 GB  Wyczyszczono

Wolne miejsce na dysku C: 8,41 GB -> 12,13 GB
Odzyskano: 3,72 GB
```

## Wymagania

- Windows 10 / 11, PowerShell 5.1+
- Uprawnienia administratora do czyszczenia `C:\Windows\Temp` (reszta działa bez nich)

## Wykorzystane umiejętności

- Operacje na systemie plików i obsługa plików zablokowanych
- `SupportsShouldProcess` / `-WhatIf`, czyli bezpieczny podgląd zmian
- Obiekty COM (`Shell.Application`) do odczytu rozmiaru Kosza
- Sprawdzanie uruchomionych procesów przed czyszczeniem
