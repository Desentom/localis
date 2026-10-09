<#
.SYNOPSIS
    Расширяет файл подкачки за счёт диска W:.

.DESCRIPTION
    Зачем. Машина имеет 6 ГБ ОЗУ, а компиляция llama.cpp запускает
    6 процессов clang параллельно (4 ядра + 2) и требует около 3,6 ГБ
    только на себя. Текущий файл подкачки — 4 ГБ на диске C:, где
    свободно 4,4 ГБ, и он заполнен на 83%. Места там нет, а на W:
    свободно 33 ГБ.

    Увеличение файла подкачки Windows применяет ТОЛЬКО при перезагрузке.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tool\setup_pagefile.ps1
    Из обычного окна PowerShell скрипт попросит повысить права сам.
#>

$ErrorActionPreference = 'Stop'
$resultFile = Join-Path $PSScriptRoot 'pagefile.result.txt'
if (Test-Path $resultFile) { Remove-Item $resultFile -Force }

# Изменение файла подкачки — привилегированная операция. Если прав нет,
# перезапускаем себя с повышенными правами и ждём результат.
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host 'Нужны права администратора. Перезапускаю с повышенными...'
    Write-Host 'Нажмите «Да» в запросе контроля учётных записей.'
    Start-Process -FilePath 'powershell.exe' `
        -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSScriptRoot\setup_pagefile.ps1`"" `
        -Verb RunAs -Wait
    # Родительский процесс просто ждёт, пока дочерний запишет отчёт.
    for ($i = 0; $i -lt 60; $i++) {
        if (Test-Path $resultFile) { break }
        Start-Sleep -Seconds 1
    }
    if (Test-Path $resultFile) { Get-Content $resultFile }
    else { Write-Host 'Не дождались результата elevated-процесса.' -ForegroundColor Yellow }
    exit 0
}

$lines = @()
try {
    $cs = Get-CimInstance Win32_ComputerSystem
    if ($cs.AutomaticManagedPagefile) {
        Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $false } | Out-Null
        $lines += 'Автоматическое управление подкачкой выключено.'
    } else {
        $lines += 'Автоматическое управление уже выключено.'
    }

    $settings = Get-CimInstance Win32_PageFileSetting
    $onW = $settings | Where-Object { $_.Name -like 'W:*' }

    if ($onW) {
        Set-CimInstance -InputObject $onW -Property @{
            InitialSize = [uint32]16384
            MaximumSize = [uint32]32768
        } | Out-Null
        $lines += 'Параметры файла подкачки на W: обновлены.'
    } else {
        New-CimInstance -ClassName Win32_PageFileSetting -Property @{
            Name         = 'W:\pagefile.sys'
            InitialSize  = [uint32]16384
            MaximumSize  = [uint32]32768
        } | Out-Null
        $lines += 'Создан файл подкачки на W: (16 ГБ, максимум 32 ГБ).'
    }

    # Страховка: без подкачки на системном томе Windows при сбое загрузки
    # уходит в аварийный режим, который мы чинить уже не будем.
    if (-not (Get-CimInstance Win32_PageFileSetting | Where-Object { $_.Name -like 'C:*' })) {
        New-CimInstance -ClassName Win32_PageFileSetting -Property @{
            Name         = 'C:\pagefile.sys'
            InitialSize  = [uint32]1024
            MaximumSize  = [uint32]2048
        } | Out-Null
        $lines += 'На C: добавлена страховочная подкачка 1 ГБ.'
    }

    $lines += ''
    $lines += 'Итоговая конфигурация:'
    Get-CimInstance Win32_PageFileSetting | ForEach-Object {
        $lines += ('  {0,-18} {1,6} МБ ... максимум {2,6} МБ' -f $_.Name, $_.InitialSize, $_.MaximumSize)
    }
    $lines += ''
    $lines += 'ПЕРЕЗАГРУЗИТЕ КОМПЬЮТЕР — настройки применится только при старте.'
    $lines | Set-Content -Path $resultFile -Encoding UTF8
}
catch {
    $lines += "ОШИБКА: $($_.Exception.Message)"
    $lines | Set-Content -Path $resultFile -Encoding UTF8
}
