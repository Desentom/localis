<#
.SYNOPSIS
    Готовит сборку к публикации: APK, контрольную сумму и текст релиза.

.DESCRIPTION
    Скрипт не заливает ничего в интернет сам — это сделано намеренно.
    Загрузка на GitHub требует авторизации, а значит токен, который
    не должен валяться в командах и истории. Здесь только подготовка,
    дальше решение за человеком.

    Порядок работы:
      1. flutter analyze + flutter test — не публикуем сломанное;
      2. сборка APK;
      3. проверка, что внутри есть libllama.so (иначе движок не собрался
         и приложение упадёт при первом вопросе);
      4. sha256 — его публикуют вместе с файлом, чтобы тестировщики
         могли проверить, что скачали не битый файл.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tool\release.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tool\release.ps1 -SkipTests
    Пропустить проверки. Только для повторной пересборки того же кода.
#>
[CmdletBinding()]
param(
    [string] $Version = '',
    [switch] $SkipTests
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Root = Split-Path $PSScriptRoot -Parent
$ReleaseDir = Join-Path $Root 'release'

function Step($m) { Write-Host ''; Write-Host "==> $m" -ForegroundColor Cyan }
function Ok($m) { Write-Host "    $m" -ForegroundColor Green }
function Warn($m) { Write-Host "    $m" -ForegroundColor Yellow }

if (-not $Version) {
    $pubspec = Get-Content (Join-Path $Root 'pubspec.yaml') -Raw
    $Version = ([regex]::Match($pubspec, '(?m)^version:\s*(?<v>[\d.]+\+\d+)')).Groups['v'].Value
}
if (-not $Version) { throw 'не удалось прочитать версию из pubspec.yaml' }
$Tag = "v$($Version -replace '\+.*$','')"

# --- 1. Проверки ------------------------------------------------------------
if (-not $SkipTests) {
    Step 'Проверки кода'

    Push-Location $Root
    try {
        # Здесь та же причина, что и при сборке: stderr от Flutter не
        # должен ронять скрипт, важны только коды возврата.
        $strict = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            Write-Host '    flutter analyze...'
            $analyze = & flutter analyze --no-pub 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0 -or $analyze -notmatch 'No issues found') {
                Write-Host $analyze
                throw 'анализатор нашёл замечания — публиковать нельзя'
            }
            Ok 'анализатор чист'

            Write-Host '    flutter test...'
            & flutter test --no-pub 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'тесты не прошли — публиковать нельзя' }
            Ok 'тесты прошли'
        } finally {
            $ErrorActionPreference = $strict
        }
    } finally {
        Pop-Location
    }
} else {
    Warn 'проверки пропущены (-SkipTests)'
}

# --- 2. Сборка --------------------------------------------------------------
Step "Сборка $Tag"

Push-Location $Root
try {
    # --target-platform android-arm64: все современные телефоны на ARM64,
    # а сборка остальных архитектур втрое дольше и заметно больше.
    #
    # $ErrorActionPreference = 'Stop' на время вызова снимаем: Flutter и
    # Gradle пишут предупреждения в stderr, PowerShell считает их ошибками
    # и рвёт скрипт на ровном месте. Так и случилось — предупреждение
    # «Gradle Plugin version 8.11.1 will soon be dropped» остановило релиз
    # после успешной сборки. Предупреждение — не повод отменять релиз, а
    # код возврата — повод.
    $strict = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & flutter build apk --release --target-platform android-arm64 2>&1 |
            Select-String -Pattern 'Built|Error|error:|FAILURE|warning:' | Out-String | Write-Host
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $strict
    }
    if ($code -ne 0) { throw "сборка не удалась, код возврата $code" }
    Ok 'APK собран'
} finally {
    Pop-Location
}

$apk = Join-Path $Root 'build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path $apk)) {
    # Отладочная сборка тоже годится для первого теста с друзьями.
    $apk = Join-Path $Root 'build\app\outputs\flutter-apk\app-debug.apk'
    if (-not (Test-Path $apk)) { throw 'APK не найден после сборки' }
    Warn 'найдена debug-сборка — для релиза нужна подпись своим ключом'
}

# --- 3. Проверка содержимого ------------------------------------------------
Step 'Проверка содержимого APK'

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($apk)
try {
    $names = @($zip.Entries | ForEach-Object { $_.FullName })
    $critical = @(
        'lib/arm64-v8a/libllama.so',
        'lib/arm64-v8a/libggml-cpu.so',
        'lib/arm64-v8a/libflutter.so'
    )
    foreach ($c in $critical) {
        if ($names -contains $c) { Ok $c } else { throw "в APK нет $c — движок собрался не полностью" }
    }
} finally {
    $zip.Dispose()
}

# --- 4. Контрольная сумма и подготовка --------------------------------------
Step 'Подготовка релиза'

New-Item -ItemType Directory -Force -Path $ReleaseDir | Out-Null
$name = "localis-$($Tag)-arm64.apk"
$target = Join-Path $ReleaseDir $name
Copy-Item $apk $target -Force

$hash = (Get-FileHash $target -Algorithm SHA256).Hash.ToLower()
$size = [math]::Round((Get-Item $target).Length / 1MB, 1)

@"
## Проверка файла

Скачали APK и хотите убедиться, что файл не повреждён при передаче:

``````powershell
Get-FileHash .\localis-$Tag-arm64.apk -Algorithm SHA256
``````

Ожидаемый хэш:

``````
$hash
``````

Размер: $size МБ
"@ | Set-Content -Path (Join-Path $ReleaseDir 'SHA256.txt') -Encoding UTF8

Ok "файл:      $name"
Ok "размер:    $size МБ"
Ok "sha256:    $hash"

Write-Host ''
Write-Host 'Что дальше:' -ForegroundColor Cyan
Write-Host "  1. Создайте репозиторий на github.com (пустой, без README)"
Write-Host "  2. Выполните:"
Write-Host "       git remote add origin https://github.com/<ваш-ник>/<название>.git"
Write-Host "       git push -u origin main"
Write-Host "  3. На странице репозитория: Releases -> Create a new release"
Write-Host "     тег: $Tag, название: Localis $Tag"
Write-Host "     прикрепите файл:"
Write-Host "       $target"
Write-Host ''
Write-Host 'НЕ коммитьте APK в репозиторий — только как вложение в релиз.'
Write-Host 'Бинарник в истории раздувает клоны навсегда.'
Write-Host ''
