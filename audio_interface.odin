#+vet explicit-allocators

package karl2d

import "base:runtime"

Audio_Interface :: struct #all_or_none {
	state_size:                  proc() -> int,
	init:                        proc(state: rawptr, allocator: runtime.Allocator) -> bool,
	shutdown:                    proc(),
	update:                      proc(),

	// Source management
	load_audio:                  proc(path: string, type: Audio_Source_Type) -> Audio_Source,
	load_audio_from_bytes:       proc(data: []u8, type: Audio_Source_Type) -> Audio_Source,
	destroy_audio:               proc(source: Audio_Source),
	get_audio_duration:          proc(source: Audio_Source) -> f32,

	// Playback
	play_audio:                  proc(
		source: Audio_Source,
		params: Audio_Play_Params,
	) -> Audio_Instance,
	stop_audio:                  proc(instance: Audio_Instance),
	pause_audio:                 proc(instance: Audio_Instance),
	resume_audio:                proc(instance: Audio_Instance),
	stop_all_audio:              proc(bus: Audio_Bus),

	// Live control
	set_audio_volume:            proc(instance: Audio_Instance, volume: f32),
	set_audio_pan:               proc(instance: Audio_Instance, pan: f32),
	set_audio_pitch:             proc(instance: Audio_Instance, pitch: f32),
	set_audio_looping:           proc(instance: Audio_Instance, loop: bool),
	set_audio_position:          proc(instance: Audio_Instance, position: Vec2),

	// Queries
	is_audio_playing:            proc(instance: Audio_Instance) -> bool,
	is_audio_paused:             proc(instance: Audio_Instance) -> bool,
	get_audio_time:              proc(instance: Audio_Instance) -> f32,

	// Buses
	create_audio_bus:            proc(name: string) -> Audio_Bus,
	destroy_audio_bus:           proc(bus: Audio_Bus),
	get_main_audio_bus:          proc() -> Audio_Bus,
	set_audio_bus_volume:        proc(bus: Audio_Bus, volume: f32),
	get_audio_bus_volume:        proc(bus: Audio_Bus) -> f32,
	set_audio_bus_muted:         proc(bus: Audio_Bus, muted: bool),
	is_audio_bus_muted:          proc(bus: Audio_Bus) -> bool,

	// Listener
	set_audio_listener_position: proc(position: Vec2),
	get_audio_listener_position: proc() -> Vec2,
	set_internal_state:          proc(state: rawptr),
}

//-------------//
// AUDIO TYPES //
//-------------//

// Audio_Source is a handle to a loaded audio asset.
// Can be played multiple times simultaneously.
Audio_Source :: distinct u64
AUDIO_SOURCE_NONE :: Audio_Source(0)

// Audio_Instance is a handle to a currently playing instance.
// Used to control playback (pause, volume, etc.)
Audio_Instance :: distinct u64
AUDIO_INSTANCE_NONE :: Audio_Instance(0)

// Audio_Bus is a handle to an audio bus for grouping and volume control.
Audio_Bus :: distinct u64
AUDIO_BUS_NONE :: Audio_Bus(0)

// Audio_Source_Type determines how the audio is loaded.
Audio_Source_Type :: enum {
	Static, // Pre-decode into memory (best for short sounds)
	Stream, // Stream from disk/memory (best for long music)
}

// Audio_End_Callback is called when an audio instance finishes playing.
Audio_End_Callback :: proc(instance: Audio_Instance, user_data: rawptr)

// Audio_Spatial_Params controls 2D positional audio.
Audio_Spatial_Params :: struct {
	position:     Vec2, // Position of the sound in world space
	min_distance: f32, // Distance at which sound is at full volume
	max_distance: f32, // Distance at which sound is inaudible
}

DEFAULT_AUDIO_SPATIAL_PARAMS :: Audio_Spatial_Params {
	position     = {0, 0},
	min_distance = 100,
	max_distance = 1000,
}

// Audio_Play_Params controls how an audio source is played.
Audio_Play_Params :: struct {
	bus:       Audio_Bus, // Which bus to play on (AUDIO_BUS_NONE = main bus)
	volume:    f32, // Volume multiplier (0.0 to 1.0+)
	pan:       f32, // Stereo pan (-1.0 = left, 0.0 = center, 1.0 = right)
	pitch:     f32, // Pitch multiplier (1.0 = normal, 2.0 = octave up)
	loop:      bool, // Whether to loop the audio
	delay:     f32, // Delay in seconds before playback starts
	spatial:   Maybe(Audio_Spatial_Params), // Optional spatial audio
	on_end:    Audio_End_Callback, // Callback when audio ends
	user_data: rawptr, // User data passed to callback
}

// Default play parameters - use this as a starting point for custom params.
default_audio_play_params :: proc() -> Audio_Play_Params {
	return Audio_Play_Params {
		bus = AUDIO_BUS_NONE,
		volume = 1.0,
		pan = 0.0,
		pitch = 1.0,
		loop = false,
		delay = 0.0,
		spatial = nil,
		on_end = nil,
		user_data = nil,
	}
}
