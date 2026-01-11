#+vet explicit-allocators
#+private file

package karl2d

import "base:runtime"

@(private = "package")
AUDIO_INTERFACE_NIL :: Audio_Interface {
	state_size                  = nil_state_size,
	init                        = nil_init,
	shutdown                    = nil_shutdown,
	update                      = nil_update,
	load_audio                  = nil_load_audio,
	load_audio_from_bytes       = nil_load_audio_from_bytes,
	destroy_audio               = nil_destroy_audio,
	get_audio_duration          = nil_get_audio_duration,
	play_audio                  = nil_play_audio,
	stop_audio                  = nil_stop_audio,
	pause_audio                 = nil_pause_audio,
	resume_audio                = nil_resume_audio,
	stop_all_audio              = nil_stop_all_audio,
	set_audio_volume            = nil_set_audio_volume,
	set_audio_pan               = nil_set_audio_pan,
	set_audio_pitch             = nil_set_audio_pitch,
	set_audio_looping           = nil_set_audio_looping,
	set_audio_position          = nil_set_audio_position,
	is_audio_playing            = nil_is_audio_playing,
	is_audio_paused             = nil_is_audio_paused,
	get_audio_time              = nil_get_audio_time,
	create_audio_bus            = nil_create_audio_bus,
	destroy_audio_bus           = nil_destroy_audio_bus,
	get_main_audio_bus          = nil_get_main_audio_bus,
	set_audio_bus_volume        = nil_set_audio_bus_volume,
	get_audio_bus_volume        = nil_get_audio_bus_volume,
	set_audio_bus_muted         = nil_set_audio_bus_muted,
	is_audio_bus_muted          = nil_is_audio_bus_muted,
	set_audio_listener_position = nil_set_audio_listener_position,
	get_audio_listener_position = nil_get_audio_listener_position,
	set_internal_state          = nil_set_internal_state,
}

nil_state_size :: proc() -> int {
	return 0
}

nil_init :: proc(state: rawptr, allocator: runtime.Allocator) -> bool {
	return true
}

nil_shutdown :: proc() {}

nil_update :: proc() {}

nil_load_audio :: proc(path: string, type: Audio_Source_Type) -> Audio_Source {
	return AUDIO_SOURCE_NONE
}

nil_load_audio_from_bytes :: proc(data: []u8, type: Audio_Source_Type) -> Audio_Source {
	return AUDIO_SOURCE_NONE
}

nil_destroy_audio :: proc(source: Audio_Source) {}

nil_get_audio_duration :: proc(source: Audio_Source) -> f32 {
	return 0
}

nil_play_audio :: proc(source: Audio_Source, params: Audio_Play_Params) -> Audio_Instance {
	return AUDIO_INSTANCE_NONE
}

nil_stop_audio :: proc(instance: Audio_Instance) {}

nil_pause_audio :: proc(instance: Audio_Instance) {}

nil_resume_audio :: proc(instance: Audio_Instance) {}

nil_stop_all_audio :: proc(bus: Audio_Bus) {}

nil_set_audio_volume :: proc(instance: Audio_Instance, volume: f32) {}

nil_set_audio_pan :: proc(instance: Audio_Instance, pan: f32) {}

nil_set_audio_pitch :: proc(instance: Audio_Instance, pitch: f32) {}

nil_set_audio_looping :: proc(instance: Audio_Instance, loop: bool) {}

nil_set_audio_position :: proc(instance: Audio_Instance, position: Vec2) {}

nil_is_audio_playing :: proc(instance: Audio_Instance) -> bool {
	return false
}

nil_is_audio_paused :: proc(instance: Audio_Instance) -> bool {
	return false
}

nil_get_audio_time :: proc(instance: Audio_Instance) -> f32 {
	return 0
}

nil_create_audio_bus :: proc(name: string) -> Audio_Bus {
	return AUDIO_BUS_NONE
}

nil_destroy_audio_bus :: proc(bus: Audio_Bus) {}

nil_get_main_audio_bus :: proc() -> Audio_Bus {
	return AUDIO_BUS_NONE
}

nil_set_audio_bus_volume :: proc(bus: Audio_Bus, volume: f32) {}

nil_get_audio_bus_volume :: proc(bus: Audio_Bus) -> f32 {
	return 1.0
}

nil_set_audio_bus_muted :: proc(bus: Audio_Bus, muted: bool) {}

nil_is_audio_bus_muted :: proc(bus: Audio_Bus) -> bool {
	return false
}

nil_set_audio_listener_position :: proc(position: Vec2) {}

nil_get_audio_listener_position :: proc() -> Vec2 {
	return {0, 0}
}

nil_set_internal_state :: proc(state: rawptr) {}
