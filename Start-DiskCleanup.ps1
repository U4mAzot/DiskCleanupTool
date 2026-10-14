<#
.SYNOPSIS
    Czyści pliki tymczasowe, pamięć podręczną przeglądarek i kosz, pokazując ile miejsca odzyskano.

.DESCRIPTION
    Skrypt sprawdza rozmiar typowych "śmieci" na dysku, usuwa je i wyświetla
    podsumowanie: ile miejsca zajmowała każda lokalizacja i ile wolnego miejsca
    przybyło na dysku systemowym.

    Czyszczone lokalizacje:
      - pliki tymczasowe użytkownika (%TEMP%)
      - pliki tymczasowe Windows (C:\Windows\Temp) - tylko jako administrator
      - pamięć podręczna Chrome, Edge i Firefox - pomijana, jeśli przeglądarka jest uruchomiona
      - Kosz

    Pliki aktualnie używane przez programy są pomijane (nie powodują błędu).
    Z przełącznikiem -WhatIf skrypt tylko pokazuje, ile miejsca można odzyskać.

.PARAMETER SkipBrowsers
    Nie czyści pamięci podręcznej przeglądarek.

.PARAMETER SkipRecycleBin
    Nie opróżnia Kosza.

.EXAMPLE
    .\Start-DiskCleanup.ps1 -WhatIf

.EXAMPLE
    .\Start-DiskCleanup.ps1 -SkipRecycleBin
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$SkipBrowsers,
    [switch]$SkipRecycleBin
)

# Moduł CIM wczytujemy z wyłączonym -WhatIf, inaczej wypisuje komunikaty o tworzeniu aliasów
$whatIf = $WhatIfPreference; $WhatIfPreference = $false
Import-Module CimCmdlets
$WhatIfPreference = $whatIf

function Test-IsAdmin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-FolderSize([string[]]$Paths) {
    $sum = 0
    foreach ($path in $Paths) {
        $measure = Get-ChildItem -Path $path -Recurse -Force -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum
        if ($measure.Sum) { $sum += $measure.Sum }
    }
    $sum
}

function Get-RecycleBinSize {
    $sum = 0
    $shell = New-Object -ComObject Shell.Application
    foreach ($item in $shell.NameSpace(10).Items()) {
        $sum += $item.Size
    }
    $sum
}

function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N1} MB' -f ($Bytes / 1MB) }
    return '{0:N0} KB' -f ($Bytes / 1KB)
}

function Get-SystemDriveFreeSpace {
    (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'").FreeSpace
}

# --- Lista lokalizacji do wyczyszczenia --------------------------------------
$isAdmin = Test-IsAdmin
$targets = @(
    [pscustomobject]@{ Name = 'Pliki tymczasowe użytkownika'; Paths = @($env:TEMP); Process = $null; RequiresAdmin = $false }
    [pscustomobject]@{ Name = 'Pliki tymczasowe Windows';     Paths = @("$env:windir\Temp"); Process = $null; RequiresAdmin = $true }
)

if (-not $SkipBrowsers) {
    $targets += [pscustomobject]@{
        Name = 'Cache Google Chrome'; Process = 'chrome'; RequiresAdmin = $false
        Paths = @("$env:LOCALAPPDATA\Google\Chrome\User Data\*\Cache", "$env:LOCALAPPDATA\Google\Chrome\User Data\*\Code Cache")
    }
    $targets += [pscustomobject]@{
        Name = 'Cache Microsoft Edge'; Process = 'msedge'; RequiresAdmin = $false
        Paths = @("$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\Cache", "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\Code Cache")
    }
    $targets += [pscustomobject]@{
        Name = 'Cache Mozilla Firefox'; Process = 'firefox'; RequiresAdmin = $false
        Paths = @("$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2")
    }
}

# --- Czyszczenie --------------------------------------------------------------
$freeBefore = Get-SystemDriveFreeSpace
$summary = @()

Write-Host "`n=== Czyszczenie dysku: $env:COMPUTERNAME ===`n" -ForegroundColor Cyan

foreach ($target in $targets) {
    $existingPaths = @($target.Paths | Where-Object { Test-Path $_ } | ForEach-Object { (Resolve-Path $_).Path })

    if ($existingPaths.Count -eq 0) {
        continue  # program nie jest zainstalowany / folder nie istnieje
    }

    $sizeBefore = Get-FolderSize $existingPaths
    $status = ''

    if ($target.RequiresAdmin -and -not $isAdmin) {
        $status = 'Pominięto (wymaga administratora)'
    } elseif ($target.Process -and (Get-Process -Name $target.Process -ErrorAction SilentlyContinue)) {
        $status = 'Pominięto (zamknij przeglądarkę)'
    } elseif ($PSCmdlet.ShouldProcess($target.Name, "Usunięcie plików ($(Format-Size $sizeBefore))")) {
        foreach ($path in $existingPaths) {
            Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
        $status = 'Wyczyszczono'
    } else {
        $status = 'Podgląd (WhatIf)'
    }

    $removed = 0
    if ($status -eq 'Wyczyszczono') {
        $removed = [math]::Max(0, $sizeBefore - (Get-FolderSize $existingPaths))
    }

    $summary += [pscustomobject]@{
        Lokalizacja = $target.Name
        Rozmiar     = Format-Size $sizeBefore
        Usunięto    = Format-Size $removed
        Status      = $status
        _Bytes      = $sizeBefore
    }
}

if (-not $SkipRecycleBin) {
    $binSize = Get-RecycleBinSize
    $status = 'Podgląd (WhatIf)'

    if ($binSize -eq 0) {
        $status = 'Pusty'
    } elseif ($PSCmdlet.ShouldProcess('Kosz', "Opróżnienie ($(Format-Size $binSize))")) {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        $status = 'Wyczyszczono'
    }

    $summary += [pscustomobject]@{
        Lokalizacja = 'Kosz'
        Rozmiar     = Format-Size $binSize
        Usunięto    = if ($status -eq 'Wyczyszczono') { Format-Size $binSize } else { Format-Size 0 }
        Status      = $status
        _Bytes      = $binSize
    }
}

# --- Podsumowanie ---------------------------------------------------------------
$summary | Format-Table Lokalizacja, Rozmiar, Usunięto, Status -AutoSize

$freeAfter = Get-SystemDriveFreeSpace
$total = ($summary | Where-Object Status -eq 'Podgląd (WhatIf)' | Measure-Object -Property _Bytes -Sum).Sum

if ($WhatIfPreference) {
    Write-Host "Można odzyskać około: $(Format-Size $total)" -ForegroundColor Yellow
    Write-Host 'Uruchom skrypt bez -WhatIf, aby wyczyścić dysk.'
} else {
    $gained = [math]::Max(0, $freeAfter - $freeBefore)
    Write-Host "Wolne miejsce na dysku $($env:SystemDrive) $(Format-Size $freeBefore) -> $(Format-Size $freeAfter)" -ForegroundColor Green
    Write-Host "Odzyskano: $(Format-Size $gained)" -ForegroundColor Green
}

if (-not $isAdmin) {
    Write-Host "`nWskazówka: uruchom jako administrator, aby wyczyścić także pliki tymczasowe Windows." -ForegroundColor DarkGray
}
