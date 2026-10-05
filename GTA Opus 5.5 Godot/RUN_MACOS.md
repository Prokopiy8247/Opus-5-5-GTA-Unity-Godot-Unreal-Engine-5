# Запуск Vesper Bay на macOS

Сборка универсальная: она предназначена для Mac с Apple Silicon и Intel.

1. Скачайте [VesperBay-macOS-universal.zip](https://github.com/Prokopiy8247/Opus-5-5-GTA-Unity-Godot-Unreal-Engine-5/releases/download/godot-v1.0.0/VesperBay-macOS-universal.zip).
2. Дважды нажмите ZIP, чтобы распаковать его.
3. Нажмите правой кнопкой по `VesperBay.app` → **Открыть** → ещё раз **Открыть**.

Сборка не нотарифицирована Apple, поэтому обычный двойной щелчок может показать предупреждение.
Если кнопки **Открыть** нет: откройте **System Settings → Privacy & Security**, найдите сообщение о
`VesperBay.app` и нажмите **Open Anyway**.

Если macOS всё равно блокирует приложение, откройте Terminal и выполните команду, перетащив
`VesperBay.app` из Finder в окно Terminal после пробела:

```bash
xattr -dr com.apple.quarantine /path/to/VesperBay.app
```

Затем снова откройте приложение. Устанавливать Godot не нужно.

## Основное управление

- WASD — движение, Shift — бег, Space — прыжок, мышь — камера.
- Правая кнопка мыши — прицел, левая — огонь, R — перезарядка, Tab — оружие.
- F — сесть/выйти из транспорта, E — взаимодействие, V — смена камеры.
- M — карта, F1 — тестовое меню, F5/F9 — быстрое сохранение/загрузка.

На компактной клавиатуре Mac для F-клавиш может потребоваться удерживать **Fn**.
