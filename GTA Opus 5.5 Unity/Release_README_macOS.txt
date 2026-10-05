PORT HALCYON — macOS

1. Распакуйте TAR.GZ двойным щелчком.
2. Control-клик по Port Halcyon.app -> Open/Открыть.
3. Если Gatekeeper продолжает блокировать неподписанную сборку, откройте
   Terminal, введите команду ниже, поставьте пробел, перетащите приложение
   в окно Terminal и нажмите Enter:

   xattr -dr com.apple.quarantine "/path/to/Port Halcyon.app"

Сборка универсальная: Intel x86_64 + Apple Silicon arm64. Она не подписана
Apple Developer ID и не notarized.

F1 — меню быстрого тестирования, Esc — пауза, WASD/мышь — движение/камера.
Официальные релизы:
https://github.com/Prokopiy8247/Opus-5-5-GTA-Unity-Godot-Unreal-Engine-5/releases
