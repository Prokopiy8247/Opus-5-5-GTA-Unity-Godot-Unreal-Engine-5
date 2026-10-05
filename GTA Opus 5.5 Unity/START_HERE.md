# Как запустить Port Halcyon

## Windows

Скачайте `Port-Halcyon-Windows-x64.zip` со страницы [последнего релиза](https://github.com/Prokopiy8247/Opus-5-5-GTA-Unity-Godot-Unreal-Engine-5/releases/latest), нажмите правой кнопкой → «Извлечь всё», затем откройте `PortHalcyon.exe`.

Если игра не запускается:

- убедитесь, что рядом с `PortHalcyon.exe` есть `PortHalcyon_Data`, `UnityPlayer.dll` и `MonoBleedingEdge`;
- не переносите из распакованной папки один `.exe` отдельно;
- при предупреждении SmartScreen выберите «Подробнее» → «Выполнить в любом случае»;
- обновите драйвер видеокарты и попробуйте параметр `-force-d3d11` в ярлыке игры.

Сохранения находятся в стандартной пользовательской папке Unity и не лежат рядом с игрой.

## macOS

Скачайте `Port-Halcyon-macOS-Universal.tar.gz` со страницы [последнего релиза](https://github.com/Prokopiy8247/Opus-5-5-GTA-Unity-Godot-Unreal-Engine-5/releases/latest). Откройте архив двойным щелчком, затем запускайте `Port Halcyon.app`.

Сборка подходит для Intel и Apple Silicon. Она не имеет платной подписи Apple Developer ID и нотариального заверения. При первом запуске:

1. Control-клик по `Port Halcyon.app` → «Открыть».
2. Если кнопки «Открыть» нет, зайдите в System Settings → Privacy & Security и разрешите запуск приложения.
3. Если появляется сообщение о повреждённом приложении, выполните в Terminal:

   ```bash
   xattr -dr com.apple.quarantine "/путь/к/Port Halcyon.app"
   ```

   Путь не нужно печатать вручную: после пробела перетащите приложение из Finder в Terminal.

## Первый запуск

Игра сразу открывает свободный режим у дома персонажа. Миссий и сюжетной кампании нет. Нажмите **F1**, чтобы открыть меню быстрого тестирования: там есть телепорты по районам, создание транспорта и оружия, время, погода и уровень розыска.

Рекомендуется клавиатура и мышь. Основное управление приведено в [README.md](README.md), полное — в [DEVELOPMENT.md](DEVELOPMENT.md).

## Для разработчиков

Откройте именно эту папку как Unity-проект в Unity 6000.6.0f1. Стартовая сцена: `Assets/GTA/Scenes/PortHalcyon.unity`.

Командная сборка на Windows:

```powershell
& "C:\Program Files\Unity\Hub\Editor\6000.6.0f1\Editor\Unity.exe" `
  -batchmode -nographics -quit -projectPath . `
  -executeMethod Halcyon.EditorTools.Pipeline.BuildDesktopPlayers `
  -logFile Builds/build-desktop.log
```

Отдельные методы: `BuildWindows` и `BuildMacOS`. macOS-сборка требует установленного через Unity Hub модуля Mac Build Support.
