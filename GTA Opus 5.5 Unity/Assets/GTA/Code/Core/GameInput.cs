using System.Collections.Generic;
using UnityEngine;
using UnityEngine.InputSystem;

namespace Halcyon
{
    /// <summary>
    /// Thin facade over the Input System device API (the project uses the new Input System only).
    /// Gameplay queries return neutral values while a menu owns the input (UIOpen).
    /// </summary>
    public static class GameInput
    {
        public static bool UIOpen;
        public static float MouseSensitivity = 0.11f;
        public static bool InvertY;

        // ---- simulated input, driven only by the -autotest smoke run (exercises the real gameplay input path)
        public static Vector2 SimMove;
        public static bool SimAim, SimFire;
        static readonly HashSet<Key> simHeld = new HashSet<Key>();
        static readonly Dictionary<Key, int> simDown = new Dictionary<Key, int>();
        static int simFireDownFrame = -1;
        /// <summary>Hold or release a simulated key.</summary>
        public static void SimHold(Key k, bool on) { if (on) simHeld.Add(k); else simHeld.Remove(k); }
        /// <summary>Simulated key press, seen as "pressed this frame" by the next frame's Update.</summary>
        public static void SimPress(Key k) { simDown[k] = Time.frameCount + 1; }
        public static void SimFirePress() { simFireDownFrame = Time.frameCount + 1; }
        public static void SimReset() { SimMove = Vector2.zero; SimAim = SimFire = false; simHeld.Clear(); simDown.Clear(); simFireDownFrame = -1; }
        static bool SimIsDown(Key k) => simDown.TryGetValue(k, out var f) && f == Time.frameCount;

        static Keyboard K => Keyboard.current;
        static Mouse Ms => Mouse.current;
        static Gamepad G => Gamepad.current;

        public static Vector2 Move
        {
            get
            {
                if (UIOpen) return Vector2.zero;
                var v = Vector2.zero;
                if (K != null)
                {
                    if (K.wKey.isPressed) v.y += 1;
                    if (K.sKey.isPressed) v.y -= 1;
                    if (K.dKey.isPressed) v.x += 1;
                    if (K.aKey.isPressed) v.x -= 1;
                }
                if (G != null)
                {
                    var s = G.leftStick.ReadValue();
                    if (s.sqrMagnitude > v.sqrMagnitude) v = s;
                }
                if (SimMove.sqrMagnitude > v.sqrMagnitude) v = SimMove;
                return Vector2.ClampMagnitude(v, 1f);
            }
        }

        /// <summary>Camera look delta in degrees for this frame.</summary>
        public static Vector2 Look
        {
            get
            {
                if (UIOpen) return Vector2.zero;
                var d = Vector2.zero;
                if (Ms != null) d = Ms.delta.ReadValue() * MouseSensitivity;
                if (G != null) d += G.rightStick.ReadValue() * 160f * Time.unscaledDeltaTime;
                if (InvertY) d.y = -d.y;
                return d;
            }
        }

        public static bool Held(Key k) => !UIOpen && ((K != null && K[k].isPressed) || simHeld.Contains(k));
        public static bool Down(Key k) => !UIOpen && ((K != null && K[k].wasPressedThisFrame) || SimIsDown(k));
        public static bool Up(Key k) => !UIOpen && K != null && K[k].wasReleasedThisFrame;
        /// <summary>Key press that also works while a menu is open (menu toggles).</summary>
        public static bool DownRaw(Key k) => (K != null && K[k].wasPressedThisFrame) || SimIsDown(k);
        public static bool HeldRaw(Key k) => K != null && K[k].isPressed;

        public static bool Fire => !UIOpen && ((Ms != null && Ms.leftButton.isPressed) || (G != null && G.rightTrigger.isPressed) || SimFire);
        public static bool FireDown => !UIOpen && ((Ms != null && Ms.leftButton.wasPressedThisFrame) || (G != null && G.rightTrigger.wasPressedThisFrame) || simFireDownFrame == Time.frameCount);
        public static bool FireUp => !UIOpen && ((Ms != null && Ms.leftButton.wasReleasedThisFrame) || (G != null && G.rightTrigger.wasReleasedThisFrame));
        public static bool Aim => !UIOpen && ((Ms != null && Ms.rightButton.isPressed) || (G != null && G.leftTrigger.isPressed) || SimAim);
        public static bool AimDown => !UIOpen && ((Ms != null && Ms.rightButton.wasPressedThisFrame) || (G != null && G.leftTrigger.wasPressedThisFrame));
        public static float Scroll => UIOpen || Ms == null ? 0f : Ms.scroll.ReadValue().y;

        public static bool Sprint => Held(Key.LeftShift) || (G != null && !UIOpen && G.leftStickButton.isPressed);
        public static bool JumpDown => Down(Key.Space) || (G != null && !UIOpen && G.buttonSouth.wasPressedThisFrame);
        public static bool JumpHeld => Held(Key.Space) || (G != null && !UIOpen && G.buttonSouth.isPressed);
        public static bool EnterVehicleDown => Down(Key.F) || (G != null && !UIOpen && G.buttonNorth.wasPressedThisFrame);
        public static bool InteractDown => Down(Key.E) || (G != null && !UIOpen && G.buttonWest.wasPressedThisFrame);
        public static bool ReloadDown => Down(Key.R) || (G != null && !UIOpen && G.buttonEast.wasPressedThisFrame);
        public static bool CrouchDown => Down(Key.C) || Down(Key.LeftCtrl) || (G != null && !UIOpen && G.rightStickButton.wasPressedThisFrame);
        public static bool CoverDown => Down(Key.Q) || (G != null && !UIOpen && G.rightShoulder.wasPressedThisFrame);

        public static Vector2 MousePosition => Ms != null ? Ms.position.ReadValue() : Vector2.zero;
        public static bool MouseLeftDownRaw => Ms != null && Ms.leftButton.wasPressedThisFrame;
        public static bool MouseRightDownRaw => Ms != null && Ms.rightButton.wasPressedThisFrame;

        public static void LockCursor(bool locked)
        {
            Cursor.lockState = locked ? CursorLockMode.Locked : CursorLockMode.None;
            Cursor.visible = !locked;
        }
    }
}
