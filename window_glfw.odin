#+build darwin
#+private file

package karl2d

import "base:runtime"
import "vendor:glfw"

@(private = "package")
WINDOW_INTERFACE_GLFW :: Window_Interface {
	state_size            = glfw_state_size,
	init                  = glfw_init,
	shutdown              = glfw_shutdown,
	window_handle         = glfw_window_handle,
	process_events        = glfw_process_events,
	get_events            = glfw_get_events,
	get_width             = glfw_get_width,
	get_height            = glfw_get_height,
	clear_events          = glfw_clear_events,
	set_position          = glfw_set_position,
	set_size              = glfw_set_size,
	get_window_scale      = glfw_get_window_scale,
	set_window_mode       = glfw_set_window_mode,
	is_gamepad_active     = glfw_is_gamepad_active,
	get_gamepad_axis      = glfw_get_gamepad_axis,
	set_gamepad_vibration = glfw_set_gamepad_vibration,
	set_internal_state    = glfw_set_internal_state,
}

GLFW_State :: struct {
	allocator:          runtime.Allocator,
	window:             glfw.WindowHandle,
	width:              int,
	height:             int,
	windowed_width:     int,
	windowed_height:    int,
	windowed_pos_x:     int,
	windowed_pos_y:     int,
	window_mode:        Window_Mode,
	events:             [dynamic]Window_Event,
	prev_gamepad_state: [MAX_GAMEPADS]glfw.GamepadState,
}

s: ^GLFW_State

glfw_state_size :: proc() -> int {
	return size_of(GLFW_State)
}

glfw_init :: proc(
	window_state: rawptr,
	window_width: int,
	window_height: int,
	window_title: string,
	init_options: Init_Options,
	allocator: runtime.Allocator,
) {
	s = (^GLFW_State)(window_state)
	s.allocator = allocator
	s.windowed_width = window_width
	s.windowed_height = window_height
	s.events = make([dynamic]Window_Event, allocator)

	if !glfw.Init() {
		return
	}

	// Request OpenGL 3.3 Core Profile
	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 3)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, 1) // Required on macOS

	// Set resizable based on window mode
	resizable: i32 = init_options.window_mode == .Windowed_Resizable ? 1 : 0
	glfw.WindowHint(glfw.RESIZABLE, resizable)

	s.window = glfw.CreateWindow(
		i32(window_width),
		i32(window_height),
		frame_cstring(window_title),
		nil,
		nil,
	)

	if s.window == nil {
		glfw.Terminate()
		return
	}

	glfw.MakeContextCurrent(s.window)
	glfw.SwapInterval(1) // Enable vsync

	// Set up callbacks
	glfw.SetWindowUserPointer(s.window, s)
	glfw.SetKeyCallback(s.window, glfw_key_callback)
	glfw.SetMouseButtonCallback(s.window, glfw_mouse_button_callback)
	glfw.SetCursorPosCallback(s.window, glfw_cursor_pos_callback)
	glfw.SetScrollCallback(s.window, glfw_scroll_callback)
	glfw.SetFramebufferSizeCallback(s.window, glfw_framebuffer_size_callback)
	glfw.SetWindowFocusCallback(s.window, glfw_window_focus_callback)
	glfw.SetWindowCloseCallback(s.window, glfw_window_close_callback)

	// Get actual framebuffer size (may differ from window size on retina displays)
	fb_width, fb_height := glfw.GetFramebufferSize(s.window)
	s.width = int(fb_width)
	s.height = int(fb_height)

	glfw_set_window_mode(init_options.window_mode)
}

glfw_shutdown :: proc() {
	delete(s.events)
	if s.window != nil {
		glfw.DestroyWindow(s.window)
	}
	glfw.Terminate()
}

glfw_window_handle :: proc() -> Window_Handle {
	return Window_Handle(s.window)
}

glfw_process_events :: proc() {
	glfw.PollEvents()

	// Poll gamepads
	for gamepad in 0 ..< MAX_GAMEPADS {
		if glfw.JoystickIsGamepad(i32(gamepad)) {
			state: glfw.GamepadState
			if glfw.GetGamepadState(i32(gamepad), &state) {
				prev := &s.prev_gamepad_state[gamepad]

				// Check button changes
				for btn_idx in 0 ..< 15 {
					curr_pressed := state.buttons[btn_idx] == glfw.PRESS
					prev_pressed := prev.buttons[btn_idx] == glfw.PRESS

					if curr_pressed && !prev_pressed {
						if btn := glfw_gamepad_button_map(btn_idx); btn != nil {
							append(
								&s.events,
								Window_Event_Gamepad_Button_Went_Down {
									gamepad = gamepad,
									button = btn.?,
								},
							)
						}
					} else if !curr_pressed && prev_pressed {
						if btn := glfw_gamepad_button_map(btn_idx); btn != nil {
							append(
								&s.events,
								Window_Event_Gamepad_Button_Went_Up {
									gamepad = gamepad,
									button = btn.?,
								},
							)
						}
					}
				}

				prev^ = state
			}
		}
	}
}

glfw_gamepad_button_map :: proc(btn_idx: int) -> Maybe(Gamepad_Button) {
	switch btn_idx {
	case glfw.GAMEPAD_BUTTON_A:
		return .Right_Face_Down
	case glfw.GAMEPAD_BUTTON_B:
		return .Right_Face_Right
	case glfw.GAMEPAD_BUTTON_X:
		return .Right_Face_Left
	case glfw.GAMEPAD_BUTTON_Y:
		return .Right_Face_Up
	case glfw.GAMEPAD_BUTTON_LEFT_BUMPER:
		return .Left_Shoulder
	case glfw.GAMEPAD_BUTTON_RIGHT_BUMPER:
		return .Right_Shoulder
	case glfw.GAMEPAD_BUTTON_BACK:
		return .Middle_Face_Left
	case glfw.GAMEPAD_BUTTON_START:
		return .Middle_Face_Right
	case glfw.GAMEPAD_BUTTON_GUIDE:
		return .Middle_Face_Middle
	case glfw.GAMEPAD_BUTTON_LEFT_THUMB:
		return .Left_Stick_Press
	case glfw.GAMEPAD_BUTTON_RIGHT_THUMB:
		return .Right_Stick_Press
	case glfw.GAMEPAD_BUTTON_DPAD_UP:
		return .Left_Face_Up
	case glfw.GAMEPAD_BUTTON_DPAD_RIGHT:
		return .Left_Face_Right
	case glfw.GAMEPAD_BUTTON_DPAD_DOWN:
		return .Left_Face_Down
	case glfw.GAMEPAD_BUTTON_DPAD_LEFT:
		return .Left_Face_Left
	}
	return nil
}

glfw_get_events :: proc() -> []Window_Event {
	return s.events[:]
}

glfw_get_width :: proc() -> int {
	return s.width
}

glfw_get_height :: proc() -> int {
	return s.height
}

glfw_clear_events :: proc() {
	runtime.clear(&s.events)
}

glfw_set_position :: proc(x: int, y: int) {
	glfw.SetWindowPos(s.window, i32(x), i32(y))
}

glfw_set_size :: proc(w, h: int) {
	glfw.SetWindowSize(s.window, i32(w), i32(h))
}

glfw_get_window_scale :: proc() -> f32 {
	xscale, _ := glfw.GetWindowContentScale(s.window)
	return xscale
}

glfw_set_window_mode :: proc(window_mode: Window_Mode) {
	if window_mode == s.window_mode && s.window_mode != .Windowed {
		return
	}

	s.window_mode = window_mode

	switch window_mode {
	case .Windowed, .Windowed_Resizable:
		// Exit fullscreen if needed
		monitor := glfw.GetWindowMonitor(s.window)
		if monitor != nil {
			// Was fullscreen, restore windowed
			glfw.SetWindowMonitor(
				s.window,
				nil,
				i32(s.windowed_pos_x),
				i32(s.windowed_pos_y),
				i32(s.windowed_width),
				i32(s.windowed_height),
				0,
			)
		}

		resizable: i32 = window_mode == .Windowed_Resizable ? 1 : 0
		glfw.SetWindowAttrib(s.window, glfw.RESIZABLE, resizable)

	case .Borderless_Fullscreen:
		// Save current position
		x, y := glfw.GetWindowPos(s.window)
		s.windowed_pos_x = int(x)
		s.windowed_pos_y = int(y)

		monitor := glfw.GetPrimaryMonitor()
		if monitor != nil {
			mode := glfw.GetVideoMode(monitor)
			if mode != nil {
				glfw.SetWindowMonitor(
					s.window,
					monitor,
					0,
					0,
					mode.width,
					mode.height,
					mode.refresh_rate,
				)
			}
		}
	}
}

glfw_is_gamepad_active :: proc(gamepad: int) -> bool {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return false
	}
	return bool(glfw.JoystickIsGamepad(i32(gamepad)))
}

glfw_get_gamepad_axis :: proc(gamepad: int, axis: Gamepad_Axis) -> f32 {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return 0
	}

	state: glfw.GamepadState
	if glfw.GetGamepadState(i32(gamepad), &state) {
		switch axis {
		case .Left_Stick_X:
			return state.axes[glfw.GAMEPAD_AXIS_LEFT_X]
		case .Left_Stick_Y:
			return state.axes[glfw.GAMEPAD_AXIS_LEFT_Y]
		case .Right_Stick_X:
			return state.axes[glfw.GAMEPAD_AXIS_RIGHT_X]
		case .Right_Stick_Y:
			return state.axes[glfw.GAMEPAD_AXIS_RIGHT_Y]
		case .Left_Trigger:
			return (state.axes[glfw.GAMEPAD_AXIS_LEFT_TRIGGER] + 1) / 2
		case .Right_Trigger:
			return (state.axes[glfw.GAMEPAD_AXIS_RIGHT_TRIGGER] + 1) / 2
		}
	}

	return 0
}

glfw_set_gamepad_vibration :: proc(gamepad: int, left: f32, right: f32) {
	// GLFW doesn't support gamepad vibration
}

glfw_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^GLFW_State)(state)
}

// GLFW Callbacks

glfw_key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	context = runtime.default_context()
	context.allocator = s.allocator

	if action == glfw.REPEAT {
		return
	}

	k2_key := glfw_key_map(key)
	if k2_key == .None {
		return
	}

	if action == glfw.PRESS {
		append(&s.events, Window_Event_Key_Went_Down{key = k2_key})
	} else if action == glfw.RELEASE {
		append(&s.events, Window_Event_Key_Went_Up{key = k2_key})
	}
}

glfw_mouse_button_callback :: proc "c" (window: glfw.WindowHandle, button, action, mods: i32) {
	context = runtime.default_context()
	context.allocator = s.allocator

	btn: Mouse_Button
	switch button {
	case glfw.MOUSE_BUTTON_LEFT:
		btn = .Left
	case glfw.MOUSE_BUTTON_RIGHT:
		btn = .Right
	case glfw.MOUSE_BUTTON_MIDDLE:
		btn = .Middle
	case:
		return
	}

	if action == glfw.PRESS {
		append(&s.events, Window_Event_Mouse_Button_Went_Down{button = btn})
	} else if action == glfw.RELEASE {
		append(&s.events, Window_Event_Mouse_Button_Went_Up{button = btn})
	}
}

glfw_cursor_pos_callback :: proc "c" (window: glfw.WindowHandle, xpos, ypos: f64) {
	context = runtime.default_context()
	context.allocator = s.allocator

	// Scale cursor position by content scale for retina displays
	xscale, yscale := glfw.GetWindowContentScale(window)
	append(&s.events, Window_Event_Mouse_Move{position = {f32(xpos) * xscale, f32(ypos) * yscale}})
}

glfw_scroll_callback :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
	context = runtime.default_context()
	context.allocator = s.allocator

	append(&s.events, Window_Event_Mouse_Wheel{delta = f32(yoffset)})
}

glfw_framebuffer_size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	context = runtime.default_context()
	context.allocator = s.allocator

	s.width = int(width)
	s.height = int(height)

	if s.window_mode == .Windowed || s.window_mode == .Windowed_Resizable {
		// Store logical window size
		win_w, win_h := glfw.GetWindowSize(window)
		s.windowed_width = int(win_w)
		s.windowed_height = int(win_h)
	}

	append(&s.events, Window_Event_Resize{width = int(width), height = int(height)})
}

glfw_window_focus_callback :: proc "c" (window: glfw.WindowHandle, focused: i32) {
	context = runtime.default_context()
	context.allocator = s.allocator

	if focused != 0 {
		append(&s.events, Window_Event_Focused{})
	} else {
		append(&s.events, Window_Event_Unfocused{})
	}
}

glfw_window_close_callback :: proc "c" (window: glfw.WindowHandle) {
	context = runtime.default_context()
	context.allocator = s.allocator

	append(&s.events, Window_Event_Close_Wanted{})
	glfw.SetWindowShouldClose(window, false) // Let karl2d handle closing
}

glfw_key_map :: proc(glfw_key: i32) -> Keyboard_Key {
	switch glfw_key {
	case glfw.KEY_SPACE:
		return .Space
	case glfw.KEY_APOSTROPHE:
		return .Apostrophe
	case glfw.KEY_COMMA:
		return .Comma
	case glfw.KEY_MINUS:
		return .Minus
	case glfw.KEY_PERIOD:
		return .Period
	case glfw.KEY_SLASH:
		return .Slash
	case glfw.KEY_0:
		return .N0
	case glfw.KEY_1:
		return .N1
	case glfw.KEY_2:
		return .N2
	case glfw.KEY_3:
		return .N3
	case glfw.KEY_4:
		return .N4
	case glfw.KEY_5:
		return .N5
	case glfw.KEY_6:
		return .N6
	case glfw.KEY_7:
		return .N7
	case glfw.KEY_8:
		return .N8
	case glfw.KEY_9:
		return .N9
	case glfw.KEY_SEMICOLON:
		return .Semicolon
	case glfw.KEY_EQUAL:
		return .Equal
	case glfw.KEY_A:
		return .A
	case glfw.KEY_B:
		return .B
	case glfw.KEY_C:
		return .C
	case glfw.KEY_D:
		return .D
	case glfw.KEY_E:
		return .E
	case glfw.KEY_F:
		return .F
	case glfw.KEY_G:
		return .G
	case glfw.KEY_H:
		return .H
	case glfw.KEY_I:
		return .I
	case glfw.KEY_J:
		return .J
	case glfw.KEY_K:
		return .K
	case glfw.KEY_L:
		return .L
	case glfw.KEY_M:
		return .M
	case glfw.KEY_N:
		return .N
	case glfw.KEY_O:
		return .O
	case glfw.KEY_P:
		return .P
	case glfw.KEY_Q:
		return .Q
	case glfw.KEY_R:
		return .R
	case glfw.KEY_S:
		return .S
	case glfw.KEY_T:
		return .T
	case glfw.KEY_U:
		return .U
	case glfw.KEY_V:
		return .V
	case glfw.KEY_W:
		return .W
	case glfw.KEY_X:
		return .X
	case glfw.KEY_Y:
		return .Y
	case glfw.KEY_Z:
		return .Z
	case glfw.KEY_LEFT_BRACKET:
		return .Left_Bracket
	case glfw.KEY_BACKSLASH:
		return .Backslash
	case glfw.KEY_RIGHT_BRACKET:
		return .Right_Bracket
	case glfw.KEY_GRAVE_ACCENT:
		return .Backtick
	case glfw.KEY_ESCAPE:
		return .Escape
	case glfw.KEY_ENTER:
		return .Enter
	case glfw.KEY_TAB:
		return .Tab
	case glfw.KEY_BACKSPACE:
		return .Backspace
	case glfw.KEY_INSERT:
		return .Insert
	case glfw.KEY_DELETE:
		return .Delete
	case glfw.KEY_RIGHT:
		return .Right
	case glfw.KEY_LEFT:
		return .Left
	case glfw.KEY_DOWN:
		return .Down
	case glfw.KEY_UP:
		return .Up
	case glfw.KEY_PAGE_UP:
		return .Page_Up
	case glfw.KEY_PAGE_DOWN:
		return .Page_Down
	case glfw.KEY_HOME:
		return .Home
	case glfw.KEY_END:
		return .End
	case glfw.KEY_CAPS_LOCK:
		return .Caps_Lock
	case glfw.KEY_SCROLL_LOCK:
		return .Scroll_Lock
	case glfw.KEY_NUM_LOCK:
		return .Num_Lock
	case glfw.KEY_PRINT_SCREEN:
		return .Print_Screen
	case glfw.KEY_PAUSE:
		return .Pause
	case glfw.KEY_F1:
		return .F1
	case glfw.KEY_F2:
		return .F2
	case glfw.KEY_F3:
		return .F3
	case glfw.KEY_F4:
		return .F4
	case glfw.KEY_F5:
		return .F5
	case glfw.KEY_F6:
		return .F6
	case glfw.KEY_F7:
		return .F7
	case glfw.KEY_F8:
		return .F8
	case glfw.KEY_F9:
		return .F9
	case glfw.KEY_F10:
		return .F10
	case glfw.KEY_F11:
		return .F11
	case glfw.KEY_F12:
		return .F12
	case glfw.KEY_KP_0:
		return .NP_0
	case glfw.KEY_KP_1:
		return .NP_1
	case glfw.KEY_KP_2:
		return .NP_2
	case glfw.KEY_KP_3:
		return .NP_3
	case glfw.KEY_KP_4:
		return .NP_4
	case glfw.KEY_KP_5:
		return .NP_5
	case glfw.KEY_KP_6:
		return .NP_6
	case glfw.KEY_KP_7:
		return .NP_7
	case glfw.KEY_KP_8:
		return .NP_8
	case glfw.KEY_KP_9:
		return .NP_9
	case glfw.KEY_KP_DECIMAL:
		return .NP_Decimal
	case glfw.KEY_KP_DIVIDE:
		return .NP_Divide
	case glfw.KEY_KP_MULTIPLY:
		return .NP_Multiply
	case glfw.KEY_KP_SUBTRACT:
		return .NP_Subtract
	case glfw.KEY_KP_ADD:
		return .NP_Add
	case glfw.KEY_KP_ENTER:
		return .NP_Enter
	case glfw.KEY_KP_EQUAL:
		return .NP_Equal
	case glfw.KEY_LEFT_SHIFT:
		return .Left_Shift
	case glfw.KEY_LEFT_CONTROL:
		return .Left_Control
	case glfw.KEY_LEFT_ALT:
		return .Left_Alt
	case glfw.KEY_LEFT_SUPER:
		return .Left_Super
	case glfw.KEY_RIGHT_SHIFT:
		return .Right_Shift
	case glfw.KEY_RIGHT_CONTROL:
		return .Right_Control
	case glfw.KEY_RIGHT_ALT:
		return .Right_Alt
	case glfw.KEY_RIGHT_SUPER:
		return .Right_Super
	case glfw.KEY_MENU:
		return .Menu
	}
	return .None
}
