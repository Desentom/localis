<#
.SYNOPSIS
    Проверяет каталог моделей: размеры по HTTP и контрольные суммы.

.DESCRIPTION
    Зачем это нужно. Ссылки на GGUF-файлы умирают, репозитории на Hugging Face
    переименовывают файлы, а размер меняется после переквантизации. Приложение
    со ссылкой на несуществующий файл падает у пользователя на экране загрузки —
    и это самая дорогая ошибка из возможных, потому что до неё человек ещё
    ничего не оценил.

    Скрипт делает две вещи:
      1. Без ключей — HEAD-запросы, сверка размера с каталогом в коде.
      2. С ключом -Download — скачивает файлы и считает sha256, выдавая
         готовые строки для вставки в ModelSpec.

.EXAMPLE
    .\tool\verify_models.ps1
    Проверить размеры, ничего не скачивая.

.EXAMPLE
    .\tool\verify_models.ps1 -Download -OutDir D:\models
    Скачать всё (≈6 ГБ) и получить контрольные суммы.
#>
[CmdletBinding()]
param(
    [switch] $Download,
    [string] $OutDir = "$PSScriptRoot\..\.model-cache"
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # иначе PowerShell тормозит на больших файлах

$SpecFile = Join-Path $PSScriptRoot '..\lib\data\model_spec.dart'

if (-not (Test-Path $SpecFile)) {
    throw "Не найден $SpecFile"
}

# --- Разбор каталога --------------------------------------------------------
# Каждая модель объявлена как `= ModelSpec(` ... `)`. Режем файл по этому
# маркеру и читаем поля поимённо — так скрипт не сломается от перестановки
# полей или появления нового.
$source = Get-Content $SpecFile -Raw -Encoding UTF8

$blocks = $source -split '=\s*ModelSpec\('
$entries = @()

foreach ($block in $blocks) {
    $urlMatch = [regex]::Match($block, "url:\s*'(?<v>https://huggingface\.co/[^']+)'")
    if (-not $urlMatch.Success) { continue }

    $fileMatch = [regex]::Match($block, "fileName:\s*'(?<v>[^']+)'")
    $bytesMatch = [regex]::Match($block, "bytes:\s*(?<v>\d+)")
    $idMatch = [regex]::Match($block, "id:\s*'(?<v>[^']+)'")

    $entries += [pscustomobject]@{
        Id     = if ($idMatch.Success) { $idMatch.Groups['v'].Value } else { '?' }
        Url    = $urlMatch.Groups['v'].Value
        File   = if ($fileMatch.Success) { $fileMatch.Groups['v'].Value } else { '?' }
        Bytes  = if ($bytesMatch.Success) { [int64]$bytesMatch.Groups['v'].Value } else { -1 }
        Sha256 = ''
    }
}

if ($entries.Count -eq 0) {
    throw 'Не удалось разобрать каталог. Проверь формат ModelSpec в model_spec.dart.'
}

Write-Host ''
Write-Host '  Localis — проверка каталога моделей' -ForegroundColor Cyan
Write-Host '  ------------------------------------' -ForegroundColor Cyan
Write-Host ''

$problems = 0
$rows = @()

foreach ($m in $entries) {
    $url = $m.Url
    $file = $m.File

    try {
        # HEAD, а не Range-запрос: Windows PowerShell 5.1 не умеет
        # отдавать произвольный заголовок Range в Invoke-WebRequest
        # (падает с невнятной ошибкой про параметр "name").
        # HEAD достаточно — размер файла лежит в Content-Length.
        $resp = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 60
        $length = $resp.Headers['Content-Length']
        $actual = if ($length) { [int64]$length } else { -1 }
    } catch {
        Write-Host ("  [СБОЙ] {0}" -f $file) -ForegroundColor Red
        Write-Host ("         {0}" -f $_.Exception.Message) -ForegroundColor DarkRed
        $problems++
        continue
    }

    $expected = $m.Bytes
    $status = 'OK'
    $color = 'Green'
    if ($expected -ge 0 -and $actual -ge 0 -and $expected -ne $actual) {
        $status = "РАЗМЕР ИЗМЕНИЛСЯ: в коде $expected"
        $color = 'Yellow'
        $problems++
    }

    Write-Host ("  [{0}] {1,-38} {2,10} Б" -f $status, $file, $actual) -ForegroundColor $color

    $rows += [pscustomobject]@{
        File     = $file
        Url      = $url
        Size     = $actual
        Expected = $expected
        Sha256   = ''
    }
}

if (-not $Download) {
    Write-Host ''
    if ($problems -gt 0) {
        Write-Host "  Найдено расхождений: $problems. Обновите bytes в model_spec.dart." -ForegroundColor Yellow
    } else {
        Write-Host '  Все размеры сходятся с кодом.' -ForegroundColor Green
    }
    Write-Host '  Чтобы получить sha256, запустите с -Download (около 6 ГБ трафика).' -ForegroundColor DarkGray
    Write-Host ''
    exit 0
}

# --- Скачивание и подсчёт контрольных сумм ---------------------------------
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Write-Host ''
Write-Host '  Скачивание моделей для подсчёта sha256...' -ForegroundColor Cyan

$shaLines = @()

foreach ($row in $rows) {
    $dest = Join-Path $OutDir $row.File
    if (-not (Test-Path $dest) -or (Get-Item $dest).Length -ne $row.Size) {
        Write-Host ("  → {0}" -f $row.File) -ForegroundColor DarkGray
        try {
            Invoke-WebRequest -Uri $row.Url -OutFile $dest -TimeoutSec 3600
        } catch {
            Write-Host ("     не удалось скачать: {0}" -f $_.Exception.Message) -ForegroundColor Red
            $problems++
            continue
        }
    } else {
        Write-Host ("  = {0} (уже на диске)" -f $row.File) -ForegroundColor DarkGray
    }

    $hash = (Get-FileHash -Path $dest -Algorithm SHA256).Hash.ToLowerInvariant()
    $shaLines += ("    sha256: '{0}'," -f $hash)
    Write-Host ("    sha256: {0}" -f $hash) -ForegroundColor Green
}

Write-Host ''
Write-Host '  Вставьте эти строки в соответствующие ModelSpec:' -ForegroundColor Cyan
Write-Host ''
$shaLines | ForEach-Object { Write-Host $_ }
Write-Host ''

if ($problems -gt 0) {
    Write-Host "  Расхождений: $problems — исправьте перед выпуском." -ForegroundColor Yellow
} else {
    Write-Host '  Готово. Модели можно выпускать.' -ForegroundColor Green
}
Write-Host ''
