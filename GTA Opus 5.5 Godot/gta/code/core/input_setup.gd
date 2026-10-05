class_name InputSetup
## Registers every gameplay input action at runtime (keyboard/mouse + basic gamepad).
## Keeping the map in code makes it reproducible and avoids hand-editing project.godot.

const KEYS := {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"sprint": [KEY_SHIFT],
	"jump": [KEY_SPACE],
	"crouch": [KEY_CTRL, KEY_C],
	"enter_vehicle": [KEY_F],
	"interact": [KEY_E],
	"reload": [KEY_R],
	"weapon_wheel": [KEY_TAB],
	"map": [KEY_M],
	"pause": [KEY_ESCAPE],
	"camera_toggle": [KEY_V],
	"horn": [KEY_H],
	"cover": [KEY_Q],
	"headlights": [KEY_L],
	"siren": [KEY_G],
	"radio_next": [KEY_PERIOD],
	"radio_prev": [KEY_COMMA],
	"phone": [KEY_UP, KEY_P],
	"debug_menu": [KEY_F1, KEY_QUOTELEFT],
	"quick_save": [KEY_F5],
	"quick_load": [KEY_F9],
	"roll_left": [KEY_Q],
	"roll_right": [KEY_E],
	"look_back": [KEY_X],
	"slot_1": [KEY_1], "slot_2": [KEY_2], "slot_3": [KEY_3], "slot_4": [KEY_4], "slot_5": [KEY_5],
	"slot_6": [KEY_6], "slot_7": [KEY_7], "slot_8": [KEY_8], "slot_9": [KEY_9],
	"ui_phone_up": [KEY_UP], "ui_phone_down": [KEY_DOWN],
	"toggle_hud": [KEY_F2],
	"photo": [KEY_F12],
}

const MOUSE := {
	"fire": [MOUSE_BUTTON_LEFT],
	"aim": [MOUSE_BUTTON_RIGHT],
	"weapon_next": [MOUSE_BUTTON_WHEEL_DOWN],
	"weapon_prev": [MOUSE_BUTTON_WHEEL_UP],
}

const PAD_BUTTONS := {
	"jump": [JOY_BUTTON_A],
	"enter_vehicle": [JOY_BUTTON_Y],
	"interact": [JOY_BUTTON_DPAD_RIGHT],
	"reload": [JOY_BUTTON_B],
	"crouch": [JOY_BUTTON_LEFT_STICK],
	"sprint": [JOY_BUTTON_X],
	"weapon_wheel": [JOY_BUTTON_LEFT_SHOULDER],
	"cover": [JOY_BUTTON_RIGHT_SHOULDER],
	"pause": [JOY_BUTTON_START],
	"map": [JOY_BUTTON_BACK],
	"camera_toggle": [JOY_BUTTON_RIGHT_STICK],
	"phone": [JOY_BUTTON_DPAD_UP],
	"horn": [JOY_BUTTON_LEFT_STICK],
}

const PAD_AXES := {
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0],
	"move_back": [JOY_AXIS_LEFT_Y, 1.0],
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"fire": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
	"aim": [JOY_AXIS_TRIGGER_LEFT, 1.0],
}


static func setup() -> void:
	for action in KEYS:
		_ensure(action)
		for k in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	for action in MOUSE:
		_ensure(action)
		for b in MOUSE[action]:
			var ev := InputEventMouseButton.new()
			ev.button_index = b
			InputMap.action_add_event(action, ev)
	for action in PAD_BUTTONS:
		_ensure(action)
		for b in PAD_BUTTONS[action]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = b
			InputMap.action_add_event(action, ev)
	for action in PAD_AXES:
		_ensure(action)
		var ev := InputEventJoypadMotion.new()
		ev.axis = PAD_AXES[action][0]
		ev.axis_value = PAD_AXES[action][1]
		InputMap.action_add_event(action, ev)


static func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)
