package karl2d

Sound_Handle :: distinct u32

Audio_Interface :: struct #all_or_none {
	state_size:            proc() -> int,
	init:                  proc(state: rawptr) -> bool,
	shutdown:              proc(),
	update:                proc(),

	// Sound effects - load once, play many times
	load_sound:            proc(path: string) -> Sound_Handle,
	load_sound_from_bytes: proc(data: []u8) -> Sound_Handle,
	destroy_sound:         proc(handle: Sound_Handle),
	play_sound:            proc(handle: Sound_Handle) -> bool,

	// Music (single track, streamed, loopable)
	play_music:            proc(path: string, loop: bool, delay_seconds: f32) -> bool,
	play_music_from_bytes: proc(data: []u8, loop: bool, delay_seconds: f32) -> bool,
	stop_music:            proc(),
	is_music_playing:      proc() -> bool,
	pause_music:           proc(),
	resume_music:          proc(),

	// Volume and pan controls
	set_master_volume:     proc(volume: f32),
	set_sound_volume:      proc(volume: f32),
	set_music_volume:      proc(volume: f32),
	set_music_pan:         proc(pan: f32), // -1.0 = left, 0.0 = center, 1.0
	set_internal_state:    proc(state: rawptr),
}
