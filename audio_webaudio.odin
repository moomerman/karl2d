#+vet explicit-allocators
#+build js
#+private file

package karl2d

import "base:runtime"
import "log"

//------------------//
// WEBAUDIO BACKEND //
//------------------//

foreign import karl2d_audio_js "karl2d_audio_js"

@(default_calling_convention = "contextless")
foreign karl2d_audio_js {
	// Lifecycle
	_js_audio_init :: proc() -> u32 ---
	_js_audio_shutdown :: proc() ---

	// Source management
	_js_load_audio :: proc(data: [^]u8, len: int, is_stream: bool) -> u32 ---
	_js_destroy_audio :: proc(source: u32) ---
	_js_get_audio_duration :: proc(source: u32) -> f32 ---

	// Playback - returns instance handle
	_js_play_audio :: proc(source: u32, bus: u32, volume: f32, pan: f32, pitch: f32, loop: bool, delay: f32, is_spatial: bool, pos_x: f32, pos_y: f32, min_distance: f32, max_distance: f32, has_callback: bool) -> u32 ---
	_js_stop_audio :: proc(instance: u32) ---
	_js_pause_audio :: proc(instance: u32) ---
	_js_resume_audio :: proc(instance: u32) ---
	_js_stop_all_audio :: proc(bus: u32) ---

	// Live control
	_js_set_audio_volume :: proc(instance: u32, volume: f32) ---
	_js_set_audio_pan :: proc(instance: u32, pan: f32) ---
	_js_set_audio_pitch :: proc(instance: u32, pitch: f32) ---
	_js_set_audio_looping :: proc(instance: u32, loop: bool) ---
	_js_set_audio_position :: proc(instance: u32, x: f32, y: f32) ---

	// Queries
	_js_is_audio_playing :: proc(instance: u32) -> bool ---
	_js_is_audio_paused :: proc(instance: u32) -> bool ---
	_js_get_audio_time :: proc(instance: u32) -> f32 ---

	// Buses
	_js_create_audio_bus :: proc() -> u32 ---
	_js_destroy_audio_bus :: proc(bus: u32) ---
	_js_set_audio_bus_volume :: proc(bus: u32, volume: f32) ---
	_js_get_audio_bus_volume :: proc(bus: u32) -> f32 ---
	_js_set_audio_bus_muted :: proc(bus: u32, muted: bool) ---
	_js_is_audio_bus_muted :: proc(bus: u32) -> bool ---

	// Listener
	_js_set_listener_position :: proc(x: f32, y: f32) ---

	// Callback polling - returns instance handle of finished sound (0 if none)
	_js_poll_finished_callback :: proc() -> u32 ---
}

//----------------//
// INTERNAL STATE //
//----------------//

// We need to track callbacks on the Odin side since we can't easily
// call Odin procs from JavaScript
Webaudio_Callback_Entry :: struct {
	instance:  Audio_Instance,
	on_end:    Audio_End_Callback,
	user_data: rawptr,
}

WEBAUDIO_MAX_CALLBACKS :: 256

Webaudio_State :: struct {
	initialized:       bool,
	allocator:         runtime.Allocator,
	listener_position: Vec2,
	// Callback tracking - JS will tell us which instances finished
	callbacks:         [WEBAUDIO_MAX_CALLBACKS]Webaudio_Callback_Entry,
	callback_count:    int,
}

wa_state: ^Webaudio_State

@(private = "package")
AUDIO_INTERFACE_WEBAUDIO :: Audio_Interface {
	state_size                  = webaudio_state_size,
	init                        = webaudio_init,
	shutdown                    = webaudio_shutdown,
	update                      = webaudio_update,
	load_audio                  = webaudio_load_audio,
	load_audio_from_bytes       = webaudio_load_audio_from_bytes,
	destroy_audio               = webaudio_destroy_audio,
	get_audio_duration          = webaudio_get_audio_duration,
	play_audio                  = webaudio_play_audio,
	stop_audio                  = webaudio_stop_audio,
	pause_audio                 = webaudio_pause_audio,
	resume_audio                = webaudio_resume_audio,
	stop_all_audio              = webaudio_stop_all_audio,
	set_audio_volume            = webaudio_set_audio_volume,
	set_audio_pan               = webaudio_set_audio_pan,
	set_audio_pitch             = webaudio_set_audio_pitch,
	set_audio_looping           = webaudio_set_audio_looping,
	set_audio_position          = webaudio_set_audio_position,
	is_audio_playing            = webaudio_is_audio_playing,
	is_audio_paused             = webaudio_is_audio_paused,
	get_audio_time              = webaudio_get_audio_time,
	create_audio_bus            = webaudio_create_audio_bus,
	destroy_audio_bus           = webaudio_destroy_audio_bus,
	get_main_audio_bus          = webaudio_get_main_audio_bus,
	set_audio_bus_volume        = webaudio_set_audio_bus_volume,
	get_audio_bus_volume        = webaudio_get_audio_bus_volume,
	set_audio_bus_muted         = webaudio_set_audio_bus_muted,
	is_audio_bus_muted          = webaudio_is_audio_bus_muted,
	set_audio_listener_position = webaudio_set_audio_listener_position,
	get_audio_listener_position = webaudio_get_audio_listener_position,
	set_internal_state          = webaudio_set_internal_state,
}

//--------------------------//
// LIFECYCLE IMPLEMENTATION //
//--------------------------//

webaudio_state_size :: proc() -> int {
	return size_of(Webaudio_State)
}

webaudio_init :: proc(state_ptr: rawptr, allocator: runtime.Allocator) -> bool {
	wa_state = (^Webaudio_State)(state_ptr)
	wa_state.allocator = allocator

	result := _js_audio_init()
	if result != 0 {
		wa_state.initialized = true
		return true
	}

	log.error("audio: Failed to initialize Web Audio")
	wa_state = nil
	return false
}

webaudio_shutdown :: proc() {
	if wa_state == nil do return

	_js_audio_shutdown()
	wa_state = nil
}

webaudio_update :: proc() {
	if wa_state == nil do return
	if !wa_state.initialized do return

	// Poll for finished callbacks from JavaScript
	// Only poll ONCE per frame - no loop needed
	finished_handle := _js_poll_finished_callback()
	if finished_handle == 0 do return

	// Find and dispatch the callback
	instance := Audio_Instance(finished_handle)
	for i := 0; i < wa_state.callback_count; i += 1 {
		if wa_state.callbacks[i].instance == instance {
			// Dispatch callback
			if wa_state.callbacks[i].on_end != nil {
				wa_state.callbacks[i].on_end(instance, wa_state.callbacks[i].user_data)
			}
			// Remove from list by swapping with last
			wa_state.callback_count -= 1
			if i < wa_state.callback_count {
				wa_state.callbacks[i] = wa_state.callbacks[wa_state.callback_count]
			}
			break
		}
	}
}

webaudio_set_internal_state :: proc(state_ptr: rawptr) {
	wa_state = (^Webaudio_State)(state_ptr)
}

//----------------------------------//
// SOURCE MANAGEMENT IMPLEMENTATION //
//----------------------------------//

webaudio_load_audio :: proc(path: string, type: Audio_Source_Type) -> Audio_Source {
	// File path loading not supported on web
	log.warn(
		"audio: load_audio with file path not supported on web. Use load_audio_from_bytes with #load.",
	)
	return AUDIO_SOURCE_NONE
}

webaudio_load_audio_from_bytes :: proc(data: []u8, type: Audio_Source_Type) -> Audio_Source {
	if wa_state == nil || !wa_state.initialized {
		log.error("audio: System not initialized")
		return AUDIO_SOURCE_NONE
	}

	if len(data) == 0 {
		log.error("audio: Cannot load from empty data")
		return AUDIO_SOURCE_NONE
	}

	handle := _js_load_audio(raw_data(data), len(data), type == .Stream)
	if handle == 0 {
		return AUDIO_SOURCE_NONE
	}

	return Audio_Source(handle)
}

webaudio_destroy_audio :: proc(source: Audio_Source) {
	if wa_state == nil || !wa_state.initialized do return
	if source == AUDIO_SOURCE_NONE do return

	_js_destroy_audio(u32(source))
}

webaudio_get_audio_duration :: proc(source: Audio_Source) -> f32 {
	if wa_state == nil || !wa_state.initialized do return 0
	if source == AUDIO_SOURCE_NONE do return 0

	return _js_get_audio_duration(u32(source))
}

//-------------------------//
// PLAYBACK IMPLEMENTATION //
//-------------------------//

webaudio_play_audio :: proc(source: Audio_Source, params: Audio_Play_Params) -> Audio_Instance {
	if wa_state == nil || !wa_state.initialized {
		log.error("audio: System not initialized")
		return AUDIO_INSTANCE_NONE
	}

	if source == AUDIO_SOURCE_NONE {
		log.error("audio: Invalid source handle")
		return AUDIO_INSTANCE_NONE
	}

	// Extract spatial params if present
	is_spatial := false
	pos_x: f32 = 0
	pos_y: f32 = 0
	min_distance: f32 = 100
	max_distance: f32 = 1000

	if spatial, has_spatial := params.spatial.?; has_spatial {
		is_spatial = true
		pos_x = spatial.position.x
		pos_y = spatial.position.y
		min_distance = spatial.min_distance
		max_distance = spatial.max_distance
	}

	has_callback := params.on_end != nil

	handle := _js_play_audio(
		u32(source),
		u32(params.bus),
		params.volume,
		params.pan,
		params.pitch,
		params.loop,
		params.delay,
		is_spatial,
		pos_x,
		pos_y,
		min_distance,
		max_distance,
		has_callback,
	)

	if handle == 0 {
		return AUDIO_INSTANCE_NONE
	}

	instance := Audio_Instance(handle)

	// Register callback if provided
	if params.on_end != nil && wa_state.callback_count < WEBAUDIO_MAX_CALLBACKS {
		wa_state.callbacks[wa_state.callback_count] = Webaudio_Callback_Entry {
			instance  = instance,
			on_end    = params.on_end,
			user_data = params.user_data,
		}
		wa_state.callback_count += 1
	}

	return instance
}

webaudio_stop_audio :: proc(instance: Audio_Instance) {
	if wa_state == nil || !wa_state.initialized do return
	if instance == AUDIO_INSTANCE_NONE do return

	_js_stop_audio(u32(instance))

	// Remove callback entry if present
	for i := 0; i < wa_state.callback_count; i += 1 {
		if wa_state.callbacks[i].instance == instance {
			wa_state.callback_count -= 1
			if i < wa_state.callback_count {
				wa_state.callbacks[i] = wa_state.callbacks[wa_state.callback_count]
			}
			break
		}
	}
}

webaudio_pause_audio :: proc(instance: Audio_Instance) {
	if wa_state == nil || !wa_state.initialized do return
	if instance == AUDIO_INSTANCE_NONE do return

	_js_pause_audio(u32(instance))
}

webaudio_resume_audio :: proc(instance: Audio_Instance) {
	if wa_state == nil || !wa_state.initialized do return
	if instance == AUDIO_INSTANCE_NONE do return

	_js_resume_audio(u32(instance))
}

webaudio_stop_all_audio :: proc(bus: Audio_Bus) {
	if wa_state == nil || !wa_state.initialized do return

	_js_stop_all_audio(u32(bus))

	// Clear all callbacks (simplification - could be smarter about filtering by bus)
	if bus == AUDIO_BUS_NONE {
		wa_state.callback_count = 0
	}
}

//-----------------------------//
// LIVE CONTROL IMPLEMENTATION //
//-----------------------------//

webaudio_set_audio_volume :: proc(instance: Audio_Instance, volume: f32) {
	if wa_state == nil || !wa_state.initialized do return
	if instance == AUDIO_INSTANCE_NONE do return

	_js_set_audio_volume(u32(instance), volume)
}

webaudio_set_audio_pan :: proc(instance: Audio_Instance, pan: f32) {
	if wa_state == nil || !wa_state.initialized do return
	if instance == AUDIO_INSTANCE_NONE do return

	_js_set_audio_pan(u32(instance), pan)
}

webaudio_set_audio_pitch :: proc(instance: Audio_Instance, pitch: f32) {
	if wa_state == nil || !wa_state.initialized do return
	if instance == AUDIO_INSTANCE_NONE do return

	_js_set_audio_pitch(u32(instance), pitch)
}

webaudio_set_audio_looping :: proc(instance: Audio_Instance, loop: bool) {
	if wa_state == nil || !wa_state.initialized do return
	if instance == AUDIO_INSTANCE_NONE do return

	_js_set_audio_looping(u32(instance), loop)
}

webaudio_set_audio_position :: proc(instance: Audio_Instance, position: Vec2) {
	if wa_state == nil || !wa_state.initialized do return
	if instance == AUDIO_INSTANCE_NONE do return

	_js_set_audio_position(u32(instance), position.x, position.y)
}

//----------------------//
// QUERY IMPLEMENTATION //
//----------------------//

webaudio_is_audio_playing :: proc(instance: Audio_Instance) -> bool {
	if wa_state == nil || !wa_state.initialized do return false
	if instance == AUDIO_INSTANCE_NONE do return false

	return _js_is_audio_playing(u32(instance))
}

webaudio_is_audio_paused :: proc(instance: Audio_Instance) -> bool {
	if wa_state == nil || !wa_state.initialized do return false
	if instance == AUDIO_INSTANCE_NONE do return false

	return _js_is_audio_paused(u32(instance))
}

webaudio_get_audio_time :: proc(instance: Audio_Instance) -> f32 {
	if wa_state == nil || !wa_state.initialized do return 0
	if instance == AUDIO_INSTANCE_NONE do return 0

	return _js_get_audio_time(u32(instance))
}

//--------------------//
// BUS IMPLEMENTATION //
//--------------------//

webaudio_create_audio_bus :: proc(name: string) -> Audio_Bus {
	if wa_state == nil || !wa_state.initialized {
		log.error("audio: System not initialized")
		return AUDIO_BUS_NONE
	}

	handle := _js_create_audio_bus()
	if handle == 0 {
		return AUDIO_BUS_NONE
	}

	return Audio_Bus(handle)
}

webaudio_destroy_audio_bus :: proc(bus: Audio_Bus) {
	if wa_state == nil || !wa_state.initialized do return
	if bus == AUDIO_BUS_NONE do return
	if bus == Audio_Bus(1) do return // Can't destroy main bus

	_js_destroy_audio_bus(u32(bus))
}

webaudio_get_main_audio_bus :: proc() -> Audio_Bus {
	return Audio_Bus(1)
}

webaudio_set_audio_bus_volume :: proc(bus: Audio_Bus, volume: f32) {
	if wa_state == nil || !wa_state.initialized do return

	// Treat AUDIO_BUS_NONE as main bus
	bus_handle := bus == AUDIO_BUS_NONE ? Audio_Bus(1) : bus
	_js_set_audio_bus_volume(u32(bus_handle), volume)
}

webaudio_get_audio_bus_volume :: proc(bus: Audio_Bus) -> f32 {
	if wa_state == nil || !wa_state.initialized do return 1.0

	bus_handle := bus == AUDIO_BUS_NONE ? Audio_Bus(1) : bus
	return _js_get_audio_bus_volume(u32(bus_handle))
}

webaudio_set_audio_bus_muted :: proc(bus: Audio_Bus, muted: bool) {
	if wa_state == nil || !wa_state.initialized do return

	bus_handle := bus == AUDIO_BUS_NONE ? Audio_Bus(1) : bus
	_js_set_audio_bus_muted(u32(bus_handle), muted)
}

webaudio_is_audio_bus_muted :: proc(bus: Audio_Bus) -> bool {
	if wa_state == nil || !wa_state.initialized do return false

	bus_handle := bus == AUDIO_BUS_NONE ? Audio_Bus(1) : bus
	return _js_is_audio_bus_muted(u32(bus_handle))
}

//-------------------------//
// LISTENER IMPLEMENTATION //
//-------------------------//

webaudio_set_audio_listener_position :: proc(position: Vec2) {
	if wa_state == nil || !wa_state.initialized do return

	wa_state.listener_position = position
	_js_set_listener_position(position.x, position.y)
}

webaudio_get_audio_listener_position :: proc() -> Vec2 {
	if wa_state == nil do return {0, 0}
	return wa_state.listener_position
}
