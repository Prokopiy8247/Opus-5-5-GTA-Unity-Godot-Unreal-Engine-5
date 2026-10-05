# Подробный запуск Port Halcyon

## Windows: готовая игра

Готовая сборка находится не в Git-истории, а в GitHub Releases — так репозиторий остаётся небольшим.

1. Перейдите на страницу [Releases](https://github.com/Prokopiy8247/Opus-5-5-GTA-Unity-Godot-Unreal-Engine-5/releases/latest).
2. В разделе Assets скачайте `Port-Halcyon-Windows-x64.zip`.
3. Нажмите на архив правой кнопкой → **Extract All / Извлечь всё**.
4. Откройте распакованную папку и запустите `Play Port Halcyon.bat`.
5. Если Windows SmartScreen покажет предупреждение для неподписанного независимого приложения, проверьте, что архив скачан именно из Releases этого репозитория. Затем выберите **More info → Run anyway**, только если доверяете репозиторию.

Сборка не требует Unreal Editor. Размер распакованной версии около 1,1 ГБ. Первый запуск может кратковременно подтормаживать при создании графического кэша.

## Windows: запуск исходного проекта

1. Установите Unreal Engine 5.8.x через Epic Games Launcher.
2. Установите Visual Studio с workload **Game development with C++**.
3. Запустите `Open Project - Windows.bat`.
4. Если UE предложит пересобрать модули — согласитесь.
5. Откройте карту `/Game/GTA/Maps/PortHalcyon` и нажмите Play.

Самостоятельную Windows-сборку создаёт `Build Game - Windows.ps1`. Результат появляется в `Builds/Windows`.

## macOS: исходный проект

Нужны Unreal Engine 5.8.x, Xcode и свободное место под кэши. Готовый Windows EXE через Wine не является поддерживаемым способом запуска.

1. Установите Epic Games Launcher, Unreal Engine 5.8.x и Xcode.
2. Один раз откройте Xcode и примите лицензию/установку компонентов.
3. Клонируйте репозиторий на диск с файловой системой APFS.
4. В Finder нажмите `Open Project - macOS.command` правой кнопкой и выберите **Open**.
5. Скрипт найдёт UE 5.8, откроет `.uproject` и позволит движку собрать C++-модуль.

Для самостоятельного приложения дважды запустите `Build Game - macOS.command`. После успешной сборки откройте `Builds/Mac/Unreal_Opus5_5_GTA.app`. Приложение не подписывается и не нотариализируется автоматически; для распространения другим пользователям Apple потребуются Developer ID, codesign и notarization.

## Если Unreal Engine установлен нестандартно

Перед запуском скрипта задайте путь к движку:

Windows PowerShell:

```powershell
./Build Game - Windows.ps1 -EngineDir "D:\Epic Games\UE_5.8"
```

macOS Terminal:

```bash
export UE_ENGINE_DIR="/Users/Shared/Epic Games/UE_5.8"
./Open\ Project\ -\ macOS.command
```

## Быстрая демонстрация

После появления персонажа нажмите **F1**. Меню позволяет телепортироваться по районам, создать любой реализованный транспорт и оружие, менять время, погоду и уровень розыска.
