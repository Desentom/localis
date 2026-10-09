# Ручная установка CMake и NDK.
#
# Зачем вручную: новый `android` CLI версии 1.0 отдаёт «No url for ndk»
# на попытку поставить NDK или CMake — в его зеркале этих пакетов нет.
# Придётся качать напрямую с dl.google.com и раскладывать в SDK самому.
#
# Раскладка по правилам Android SDK:
#   $SDK/cmake/3.22.1/bin/cmake.exe
#   $SDK/ndk/28.2.13676358/ndk-build.cmd
#
# Идентификатор версии NDK обязателен: Flutter ищет конкретный
# (сейчас 28.2.13676358), а имя каталога после распаковки — android-ndk-r28c.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Sdk = 'W:\dev\android-sdk'
$dl = 'W:\dev\_downloads'

function Step($m) { Write-Host ''; Write-Host "==> $m" -ForegroundColor Cyan }

function Move-ArchivePayload {
    # Архивы Google раскладываются по-разному:
    #   CMake  — bin/, doc/, share/, source.properties прямо в корне (4 записи);
    #   NDK    — единственный каталог android-ndk-r28c/ и больше ничего.
    # Правило: если в корне ровно один объект и он каталог — полезная
    # нагрузка внутри него. Во всех остальных случаях корень сам и есть
    # полезная нагрузка, и мы переносим его целиком.
    param([string]$Tmp, [string]$Target)

    $top = @(Get-ChildItem -LiteralPath $Tmp)
    if ($top.Count -eq 0) { throw 'архив распаковался пустым' }

    if ($top.Count -eq 1 -and $top[0].PSIsContainer) {
        New-Item -ItemType Directory -Force -Path $Target | Out-Null
        Get-ChildItem -LiteralPath $top[0].FullName -Force |
            Move-Item -Destination $Target -Force
        return
    }

    New-Item -ItemType Directory -Force -Path $Target | Out-Null
    $top | Move-Item -Destination $Target -Force
}

# --- CMake -------------------------------------------------------------------
Step 'CMake 3.22.1'

$cmakeUrl = 'https://dl.google.com/android/repository/cmake-3.22.1-windows.zip'
$cmakeZip = Join-Path $dl 'cmake-3.22.1-windows.zip'
$cmakeTarget = Join-Path $Sdk 'cmake\3.22.1'

if (Test-Path (Join-Path $cmakeTarget 'bin\cmake.exe')) {
    Write-Host '    уже установлен' -ForegroundColor DarkGray
} else {
    if (-not (Test-Path $cmakeZip) -or (Get-Item $cmakeZip).Length -lt 16000000) {
        Write-Host '    качаю...'
        & curl.exe -L --fail --retry 4 --connect-timeout 30 -o $cmakeZip $cmakeUrl
        if ($LASTEXITCODE -ne 0) { throw 'не удалось скачать CMake' }
    }
    # tar.exe из Windows 10 распаковывает zip заметно быстрее Expand-Archive
    $tmp = Join-Path $dl '_cmake_tmp'
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    & tar.exe -xf $cmakeZip -C $tmp
    if ($LASTEXITCODE -ne 0) { throw 'распаковка CMake не удалась' }

    New-Item -ItemType Directory -Force -Path (Split-Path $cmakeTarget) | Out-Null
    if (Test-Path $cmakeTarget) { Remove-Item -Recurse -Force $cmakeTarget }
    Move-ArchivePayload -Tmp $tmp -Target $cmakeTarget
    Remove-Item -Recurse -Force $tmp
    Write-Host '    установлен' -ForegroundColor Green
}

# --- NDK ---------------------------------------------------------------------
Step 'NDK r28c (28.2.13676358)'

$ndkUrl = 'https://dl.google.com/android/repository/android-ndk-r28c-windows.zip'
$ndkZip = Join-Path $dl 'android-ndk-r28c-windows.zip'
$ndkVersion = '28.2.13676358'
$ndkTarget = Join-Path $Sdk "ndk\$ndkVersion"

if (Test-Path (Join-Path $ndkTarget 'ndk-build.cmd')) {
    Write-Host '    уже установлен' -ForegroundColor DarkGray
} else {
    if (-not (Test-Path $ndkZip) -or (Get-Item $ndkZip).Length -lt 700000000) {
        Write-Host '    качаю 748 МБ, это займёт около 10 минут...'
        & curl.exe -L --fail --retry 4 --connect-timeout 30 -C - -o $ndkZip $ndkUrl
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 33) { throw 'не удалось скачать NDK' }
    }
    Write-Host '    распаковываю, это ещё несколько минут...'
    $tmp = Join-Path $dl '_ndk_tmp'
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    & tar.exe -xf $ndkZip -C $tmp
    if ($LASTEXITCODE -ne 0) { throw 'распаковка NDK не удалась' }

    New-Item -ItemType Directory -Force -Path (Join-Path $Sdk 'ndk') | Out-Null
    if (Test-Path $ndkTarget) { Remove-Item -Recurse -Force $ndkTarget }
    Move-ArchivePayload -Tmp $tmp -Target $ndkTarget
    Remove-Item -Recurse -Force $tmp
    Write-Host '    установлен' -ForegroundColor Green
}

# --- Проверка ----------------------------------------------------------------
Step 'Проверка'
$checks = @(
    @{ Name = 'cmake'; Path = (Join-Path $cmakeTarget 'bin\cmake.exe') }
    @{ Name = 'ndk-build'; Path = (Join-Path $ndkTarget 'ndk-build.cmd') }
    @{ Name = 'ndk source.properties'; Path = (Join-Path $ndkTarget 'source.properties') }
)
$bad = 0
foreach ($c in $checks) {
    if (Test-Path $c.Path) {
        Write-Host ("    [OK] {0}" -f $c.Name) -ForegroundColor Green
    } else {
        Write-Host ("    [НЕТ] {0}" -f $c.Name) -ForegroundColor Red
        $bad++
    }
}

Write-Host ''
if ($bad -gt 0) {
    Write-Host 'Что-то не установилось.' -ForegroundColor Red
    exit 1
}
Write-Host 'CMake и NDK на месте.' -ForegroundColor Green
Write-Host ''
