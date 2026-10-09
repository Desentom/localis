<#
.SYNOPSIS
    Ставит тулчейн для сборки Localis на диск W:.

.DESCRIPTION
    Раскладывает скачанные архивы, принимает лицензии Android SDK, ставит
    нужные пакеты и прописывает переменные окружения пользователя.

    Скрипт идемпотентен: каждый шаг проверяет, не сделано ли уже, поэтому его
    безопасно запускать повторно после обрыва.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tool\setup_env.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tool\setup_env.ps1 -SkipNdk
    Без NDK. Сборка, скорее всего, пройдёт, но приложение нельзя будет
    отправить в Play из-за требования к 16 КБ страницам памяти.
#>
[CmdletBinding()]
param(
    [switch] $SkipNdk
)

$ErrorActionPreference = 'Stop'

$DevRoot = 'W:\dev'
$Downloads = Join-Path $DevRoot '_downloads'

$JdkDir = Join-Path $DevRoot 'jdk-17'
$FlutterDir = Join-Path $DevRoot 'flutter'
$SdkDir = Join-Path $DevRoot 'android-sdk'
$CmdlineDir = Join-Path $SdkDir 'cmdline-tools\latest'

function Step($msg) {
    Write-Host ''
    Write-Host "==> $msg" -ForegroundColor Cyan
}

function Ok($msg) {
    Write-Host "    $msg" -ForegroundColor Green
}

function Skip($msg) {
    Write-Host "    $msg" -ForegroundColor DarkGray
}

# --- 1. JDK 17 ---------------------------------------------------------------
Step 'JDK 17'

$jdkZip = Join-Path $Downloads 'jdk17.zip'
if (-not (Test-Path $jdkZip)) { throw "Нет архива $jdkZip — сначала запустите get.ps1" }

if (Test-Path (Join-Path $JdkDir 'bin\java.exe')) {
    Skip 'уже распакован'
} else {
    $tmp = Join-Path $DevRoot '_jdk_tmp'
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    Expand-Archive -Path $jdkZip -DestinationPath $tmp -Force
    # Внутри архива один каталог с произвольным именем версии.
    $inner = Get-ChildItem -Directory $tmp | Select-Object -First 1
    if (Test-Path $JdkDir) { Remove-Item -Recurse -Force $JdkDir }
    Move-Item $inner.FullName $JdkDir
    Remove-Item -Recurse -Force $tmp
    Ok "установлен в $JdkDir"
}

# --- 2. Flutter SDK ----------------------------------------------------------
Step 'Flutter SDK'

$flutterZip = Join-Path $Downloads 'flutter.zip'
if (-not (Test-Path $flutterZip)) { throw "Нет архива $flutterZip — сначала запустите get.ps1" }

if (Test-Path (Join-Path $FlutterDir 'bin\flutter.bat')) {
    Skip 'уже распакован'
} else {
    if (Test-Path $FlutterDir) { Remove-Item -Recurse -Force $FlutterDir }
    New-Item -ItemType Directory -Force -Path $DevRoot | Out-Null
    Expand-Archive -Path $flutterZip -DestinationPath $DevRoot -Force
    Ok "установлен в $FlutterDir"
}

# --- 3. Android command line tools ------------------------------------------
Step 'Android command line tools'

$cltZip = Join-Path $Downloads 'cmdline-tools.zip'
if (-not (Test-Path $cltZip)) { throw "Нет архива $cltZip — сначала запустите get.ps1" }

$sdkmanager = Join-Path $CmdlineDir 'bin\sdkmanager.bat'
if (Test-Path $sdkmanager) {
    Skip 'уже распакован'
} else {
    $tmp = Join-Path $DevRoot '_clt_tmp'
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    Expand-Archive -Path $cltZip -DestinationPath $tmp -Force
    # В архиве лежит каталог cmdline-tools, а sdkmanager ждёт путь
    # cmdline-tools\latest\bin — ровно это он и проверяет при запуске.
    $inner = Join-Path $tmp 'cmdline-tools'
    if (-not (Test-Path $inner)) { throw 'Структура архива cmdline-tools неожиданна' }
    New-Item -ItemType Directory -Force -Path (Join-Path $SdkDir 'cmdline-tools') | Out-Null
    if (Test-Path $CmdlineDir) { Remove-Item -Recurse -Force $CmdlineDir }
    Move-Item $inner $CmdlineDir
    Remove-Item -Recurse -Force $tmp
    Ok "установлен в $CmdlineDir"
}

# --- 4. Пакеты SDK -----------------------------------------------------------
Step 'Пакеты Android SDK'

$env:JAVA_HOME = $JdkDir
$env:ANDROID_HOME = $SdkDir
$env:ANDROID_SDK_ROOT = $SdkDir
$env:PATH = "$JdkDir\bin;$CmdlineDir\bin;$env:PATH"

# Google объявил sdkmanager устаревшим: в новых cmdline-tools (23.0) это
# прокладка, которая подтягивает отдельный бинарник `android.exe` и передаёт
# ему вызов, но код возврата у неё всегда ненулевой. Ставим пакеты новым
# инструментом — он официальный и работает предсказуемо.
$android = Join-Path $CmdlineDir 'bin\android.exe'
if (-not (Test-Path $android)) {
    throw "Не найден новый Android CLI: $android"
}

# Обёртка для нативных команд. Нужна из-за особенности Windows PowerShell 5.1:
# при $ErrorActionPreference = 'Stop' ЛЮБОЙ вывод в stderr от нативной команды
# превращается в фатальную ошибку. Android CLI пишет в stderr информационные
# сообщения, и скрипт без этого падал на ровном месте.
function Invoke-Native {
    param([string]$Exe, [string[]]$NativeArgs, [switch]$Quiet)

    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $Exe @NativeArgs 2>&1
        $code = $LASTEXITCODE
        if (-not $Quiet) {
            $output | Where-Object { $_ } | ForEach-Object { Write-Host "      $_" }
        }
        return $code
    } finally {
        $ErrorActionPreference = $saved
    }
}

# Инициализация окружения нового CLI: создаёт каталоги и принимает лицензии.
Write-Host '    инициализирую Android CLI...'
Invoke-Native -Exe $android -NativeArgs @('--sdk=' + $SdkDir, 'init') -Quiet | Out-Null
Ok 'инициализация завершена'

$packages = @(
    'platform-tools'
    'platforms;android-35'
    'build-tools;35.0.0'
)

if (-not $SkipNdk) {
    # Нужен r27 или новее: Google Play с ноября 2025 не принимает
    # бинарные библиотеки, собранные под 4 КБ страницы памяти.
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $listing = & $android --sdk=$SdkDir sdk list 2>&1
    } finally {
        $ErrorActionPreference = $saved
    }
    $ndkLine = $listing |
        Select-String -Pattern 'ndk;27\.' |
        Select-Object -First 1
    if ($ndkLine) {
        $ndk = ([regex]::Match($ndkLine.ToString(), 'ndk;27\.[0-9.]+')).Value
        if ($ndk) {
            $packages += $ndk
            Ok "выбран NDK: $ndk"
        }
    }
    if (-not ($packages -match '^ndk;')) {
        Write-Host '    NDK 27.x не найден в списке — ставлю фиксированную версию' -ForegroundColor Yellow
        $packages += 'ndk;27.0.12077973'
    }
} else {
    Write-Host '    NDK пропущен (-SkipNdk)' -ForegroundColor Yellow
}

foreach ($pkg in $packages) {
    Write-Host "    ставлю $pkg ..."
    $code = Invoke-Native -Exe $android -NativeArgs @('--sdk=' + $SdkDir, 'sdk', 'install', $pkg) -Quiet
    if ($code -ne 0) {
        throw "Не удалось установить пакет $pkg (код $code)"
    }
    # Проверяем результат на диске. Новый android CLI способен вернуть код 0,
    # фактически ничего не установив — а build.gradle потом падает с
    # «Android SDK not found», и непонятно где искать причину.
    $expected = switch -Regex ($pkg) {
        '^platform-tools$'          { Join-Path $SdkDir 'platform-tools\adb.exe' }
        '^platforms;'               { Join-Path $SdkDir ('platforms\' + ($pkg -split ';')[1] + '\android.jar') }
        '^build-tools;'             { Join-Path $SdkDir ('build-tools\' + ($pkg -split ';')[1] + '\aapt2.exe') }
        '^ndk;'                     { Join-Path $SdkDir 'ndk' }
        default                     { $null }
    }
    if ($expected -and -not (Test-Path $expected)) {
        throw ("Пакет {0} отмечен как установленный, но {1} не найден" -f $pkg, $expected)
    }
    Ok $pkg
}

# --- 5. Переменные окружения -------------------------------------------------
Step 'Переменные окружения (для текущего пользователя)'

[Environment]::SetEnvironmentVariable('JAVA_HOME', $JdkDir, 'User')
[Environment]::SetEnvironmentVariable('ANDROID_HOME', $SdkDir, 'User')
[Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT', $SdkDir, 'User')
# Точка с запятой в конце не нужна, путь разделён ';' как и положено.
[Environment]::SetEnvironmentVariable(
    'PATH',
    "$JdkDir\bin;$CmdlineDir\bin;$FlutterDir\bin;$SdkDir\platform-tools",
    'User'
)
Ok 'JAVA_HOME, ANDROID_HOME, ANDROID_SDK_ROOT, PATH'

Write-Host ''
Write-Host 'ГОТОВО. Перезапустите терминал, чтобы подхватились переменные.' -ForegroundColor Green
Write-Host ''
Write-Host 'Проверка:'
Write-Host "  flutter doctor -v"
Write-Host "  cd W:\localis; flutter pub get; flutter analyze"
Write-Host ''
