#+private file

package karl2d

import "log"

@(private = "package")
AUDIO_NIL :: Audio_Interface {
	state_size            = abnil_state_size,
	init                  = abnil_init,
	shutdown              = abnil_shutdown,
	update                = abnil_update,
	load_sound            = abnil_load_sound,
	load_sound_from_bytes = abnil_load_sound_from_bytes,
	destroy_sound         = abnil_destroy_sound,
	play_sound            = abnil_play_sound,
	play_music            = abnil_play_music,
	play_music_from_bytes = abnil_play_music_from_bytes,
	stop_music            = abnil_stop_music,
	is_music_playing      = abnil_is_music_playing,
	set_master_volume     = abnil_set_master_volume,
	set_sound_volume      = abnil_set_sound_volume,
	set_music_volume      = abnil_set_music_volume,
	set_internal_state    = abnil_set_internal_state,
}

abnil_state_size :: proc() -> int {
	return 0
}

abnil_init :: proc(state: rawptr) -> bool {
	log.info("Audio Backend nil init")
	return true
}

abnil_shutdown :: proc() {
	log.info("Audio Backend nil shutdown")
}

abnil_update :: proc() {
}

abnil_load_sound :: proc(path: string) -> Sound_Handle {
	return Sound_Handle(1) // Return a dummy handle
}

abnil_load_sound_from_bytes :: proc(data: []u8) -> Sound_Handle {
	return Sound_Handle(1) // Return a dummy handle
}

abnil_destroy_sound :: proc(handle: Sound_Handle) {
}

abnil_play_sound :: proc(handle: Sound_Handle) -> bool {
	return true
}

abnil_play_music :: proc(path: string, loop: bool, delay_seconds: f32) -> bool {
	return true
}

abnil_play_music_from_bytes :: proc(data: []u8, loop: bool, delay_seconds: f32) -> bool {
	return true
}

abnil_stop_music :: proc() {
}

abnil_is_music_playing :: proc() -> bool {
	return false
}

abnil_set_master_volume :: proc(volume: f32) {
}

abnil_set_sound_volume :: proc(volume: f32) {
}

abnil_set_music_volume :: proc(volume: f32) {
}

abnil_set_internal_state :: proc(state: rawptr) {
}
