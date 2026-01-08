#+build js
#+private file

package karl2d

import "base:runtime"
import "log"

@(private = "package")
AUDIO_WEBAUDIO :: Audio_Interface {
	state_size            = wa_state_size,
	init                  = wa_init,
	shutdown              = wa_shutdown,
	update                = wa_update,
	load_sound            = wa_load_sound,
	load_sound_from_bytes = wa_load_sound_from_bytes,
	destroy_sound         = wa_destroy_sound,
	play_sound            = wa_play_sound,
	play_music            = wa_play_music,
	play_music_from_bytes = wa_play_music_from_bytes,
	stop_music            = wa_stop_music,
	is_music_playing      = wa_is_music_playing,
	pause_music           = wa_pause_music,
	resume_music          = wa_resume_music,
	set_master_volume     = wa_set_master_volume,
	set_sound_volume      = wa_set_sound_volume,
	set_music_volume      = wa_set_music_volume,
	set_music_pan         = wa_set_music_pan,
	set_internal_state    = wa_set_internal_state,
}

// Foreign imports to JavaScript Web Audio helpers
foreign import karl2d_audio "karl2d_audio"

@(default_calling_convention = "contextless")
foreign karl2d_audio {
	_wa_init :: proc() -> bool ---
	_wa_shutdown :: proc() ---
	_wa_load_sound :: proc(data: [^]u8, len: int) -> u32 ---
	_wa_destroy_sound :: proc(handle: u32) ---
	_wa_play_sound :: proc(handle: u32) -> bool ---
	_wa_play_music_from_bytes :: proc(data: [^]u8, len: int, loop: bool, delay_seconds: f32) -> bool ---
	_wa_stop_music :: proc() ---
	_wa_is_music_playing :: proc() -> bool ---
	_wa_pause_music :: proc() ---
	_wa_resume_music :: proc() ---
	_wa_set_master_volume :: proc(volume: f32) ---
	_wa_set_sound_volume :: proc(volume: f32) ---
	_wa_set_music_volume :: proc(volume: f32) ---
	_wa_set_music_pan :: proc(pan: f32) ---
}

Webaudio_State :: struct {
	initialized: bool,
}

wa_state: ^Webaudio_State

wa_state_size :: proc() -> int {
	return size_of(Webaudio_State)
}

wa_init :: proc(state: rawptr) -> bool {
	wa_state = (^Webaudio_State)(state)

	if _wa_init() {
		wa_state.initialized = true
		return true
	}

	log.error("Failed to initialize Web Audio")
	return false
}

wa_shutdown :: proc() {
	if wa_state == nil || !wa_state.initialized do return

	_wa_shutdown()
	wa_state.initialized = false
}

wa_update :: proc() {
	// Web Audio handles cleanup automatically via JavaScript garbage collection
}

wa_load_sound :: proc(path: string) -> Sound_Handle {
	// File path-based loading is not supported on web
	// Use load_sound_from_bytes with #load instead
	log.warn(
		"load_sound with file path not supported on web. Use load_sound_from_bytes with #load.",
	)
	return Sound_Handle(0)
}

wa_load_sound_from_bytes :: proc(data: []u8) -> Sound_Handle {
	if wa_state == nil || !wa_state.initialized {
		log.error("Audio system not initialized")
		return Sound_Handle(0)
	}

	if len(data) == 0 {
		log.error("Cannot load sound from empty data")
		return Sound_Handle(0)
	}

	handle := _wa_load_sound(raw_data(data), len(data))
	return Sound_Handle(handle)
}

wa_destroy_sound :: proc(handle: Sound_Handle) {
	if wa_state == nil || !wa_state.initialized do return
	if handle == Sound_Handle(0) do return

	_wa_destroy_sound(u32(handle))
}

wa_play_sound :: proc(handle: Sound_Handle) -> bool {
	if wa_state == nil || !wa_state.initialized {
		log.error("Audio system not initialized")
		return false
	}

	if handle == Sound_Handle(0) {
		log.error("Invalid sound handle")
		return false
	}

	return _wa_play_sound(u32(handle))
}

wa_play_music :: proc(path: string, loop: bool, delay_seconds: f32) -> bool {
	// File path-based loading is not supported on web
	// Use play_music_from_bytes with #load instead
	log.warn(
		"play_music with file path not supported on web. Use play_music_from_bytes with #load.",
	)
	return false
}

wa_play_music_from_bytes :: proc(data: []u8, loop: bool, delay_seconds: f32) -> bool {
	if wa_state == nil || !wa_state.initialized {
		log.error("Audio system not initialized")
		return false
	}

	if len(data) == 0 {
		log.error("Cannot play music from empty data")
		return false
	}

	return _wa_play_music_from_bytes(raw_data(data), len(data), loop, delay_seconds)
}

wa_stop_music :: proc() {
	if wa_state == nil || !wa_state.initialized do return
	_wa_stop_music()
}

wa_is_music_playing :: proc() -> bool {
	if wa_state == nil || !wa_state.initialized do return false
	return _wa_is_music_playing()
}

wa_pause_music :: proc() {
	if wa_state == nil || !wa_state.initialized do return
	_wa_pause_music()
}

wa_resume_music :: proc() {
	if wa_state == nil || !wa_state.initialized do return
	_wa_resume_music()
}

wa_set_master_volume :: proc(volume: f32) {
	if wa_state == nil || !wa_state.initialized do return
	clamped := clamp(volume, 0.0, 1.0)
	_wa_set_master_volume(clamped)
}

wa_set_sound_volume :: proc(volume: f32) {
	if wa_state == nil || !wa_state.initialized do return
	clamped := clamp(volume, 0.0, 1.0)
	_wa_set_sound_volume(clamped)
}

wa_set_music_volume :: proc(volume: f32) {
	if wa_state == nil || !wa_state.initialized do return
	clamped := clamp(volume, 0.0, 1.0)
	_wa_set_music_volume(clamped)
}

wa_set_music_pan :: proc(pan: f32) {
	if wa_state == nil || !wa_state.initialized do return
	clamped := clamp(pan, -1.0, 1.0)
	_wa_set_music_pan(clamped)
}

wa_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	wa_state = (^Webaudio_State)(state)
}
