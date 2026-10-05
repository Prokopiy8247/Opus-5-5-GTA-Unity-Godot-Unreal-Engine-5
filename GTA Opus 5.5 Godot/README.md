# Vesper Bay — GTA-подобная песочница на Godot

Оригинальная одиночная игра без миссий и сюжетной кампании: открытый остров примерно 600×600 метров,
пешее исследование, машины, мотоцикл, лодка, самолёты, вертолёты, оружие, полиция и свободные активности.

## Скачать и играть без Godot

- [Windows x86-64 — скачать ZIP](https://github.com/Prokopiy8247/Opus-5-5-GTA-Unity-Godot-Unreal-Engine-5/releases/download/godot-v1.0.0/VesperBay-Windows-x86_64.zip)
- [macOS Apple Silicon / Intel — скачать ZIP](https://github.com/Prokopiy8247/Opus-5-5-GTA-Unity-Godot-Unreal-Engine-5/releases/download/godot-v1.0.0/VesperBay-macOS-universal.zip)

Пошаговые инструкции: [Windows](RUN_WINDOWS.md) · [macOS](RUN_MACOS.md).

## Быстрое управление

WASD — движение · Shift — бег · Space — прыжок · мышь — обзор · ПКМ — прицел · ЛКМ — огонь ·
R — перезарядка · Tab — оружие · F — сесть/выйти/угнать транспорт · E — взаимодействие ·
V — камера · M — карта · F1 — тестовое меню · F5/F9 — быстрое сохранение/загрузка.

Полная таблица управления и техническая документация находятся в [DEVELOPMENT.md](DEVELOPMENT.md).
Статус всех функций — в [FEATURE_MATRIX.md](FEATURE_MATRIX.md), итоговый отчёт — в
[OPUS_5.5_FINAL_REPORT.md](OPUS_5.5_FINAL_REPORT.md).

## Запуск исходников

1. Установите Godot 4.7.2.
2. В Project Manager нажмите **Import** и выберите этот `project.godot`.
3. Дождитесь первого импорта ресурсов и нажмите **F5**.

Главная сцена уже назначена. Мастер-файл всех оригинальных 3D-ассетов — `GodotOpus5.5GTA.blend`;
экспортированные GLB находятся в `gta/generated/models/`.

Исходный промпт создания проекта сохранён в
`Claude_Opus_5.5_Godot_GTA_BlenderMCP_Prompt.md`.

## Сборка

На Windows:

```powershell
.\tools\build_release.ps1 -GodotPath "C:\path\to\Godot_v4.7.2-stable_win64_console.exe"
```

В Bash:

```bash
GODOT=/path/to/godot tools/build_release.sh
```

Нужны официальные export templates Godot 4.7.2. Результаты появятся в `build/windows/` и
`build/macos/`.
