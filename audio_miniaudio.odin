#+vet explicit-allocators
#+build windows, linux, darwin
#+private file

package karl2d

import "base:intrinsics"
import "base:runtime"
import "core:c"
import "core:strings"
import "log"
import "vendor:miniaudio"

//--------------------------//
// MINIAUDIO AUDIO BACKEND  //
//--------------------------//

@(private = "package")
AUDIO_INTERFACE_MINIAUDIO :: Audio_Interface {
	state_size                  = miniaudio_state_size,
	init                        = miniaudio_init,
	shutdown                    = miniaudio_shutdown,
	update                      = miniaudio_update,
	load_audio                  = miniaudio_load_audio,
	load_audio_from_bytes       = miniaudio_load_audio_from_bytes,
	destroy_audio               = miniaudio_destroy_audio,
	get_audio_duration          = miniaudio_get_audio_duration,
	play_audio                  = miniaudio_play_audio,
	stop_audio                  = miniaudio_stop_audio,
	pause_audio                 = miniaudio_pause_audio,
	resume_audio                = miniaudio_resume_audio,
	stop_all_audio              = miniaudio_stop_all_audio,
	set_audio_volume            = miniaudio_set_audio_volume,
	set_audio_pan               = miniaudio_set_audio_pan,
	set_audio_pitch             = miniaudio_set_audio_pitch,
	set_audio_looping           = miniaudio_set_audio_looping,
	set_audio_position          = miniaudio_set_audio_position,
	is_audio_playing            = miniaudio_is_audio_playing,
	is_audio_paused             = miniaudio_is_audio_paused,
	get_audio_time              = miniaudio_get_audio_time,
	create_audio_bus            = miniaudio_create_audio_bus,
	destroy_audio_bus           = miniaudio_destroy_audio_bus,
	get_main_audio_bus          = miniaudio_get_main_audio_bus,
	set_audio_bus_volume        = miniaudio_set_audio_bus_volume,
	get_audio_bus_volume        = miniaudio_get_audio_bus_volume,
	set_audio_bus_muted         = miniaudio_set_audio_bus_muted,
	is_audio_bus_muted          = miniaudio_is_audio_bus_muted,
	set_audio_listener_position = miniaudio_set_audio_listener_position,
	get_audio_listener_position = miniaudio_get_audio_listener_position,
	set_internal_state          = miniaudio_set_internal_state,
}

//----------------//
// INTERNAL TYPES //
//----------------//

// Loaded_Source stores audio data - either pre-decoded (static) or streaming info
Miniaudio_Loaded_Source :: struct {
	type:        Audio_Source_Type,
	duration:    f32, // Cached duration in seconds (calculated at load time)
	// For Static sources: pre-decoded PCM data
	data:        []u8,
	format:      miniaudio.format,
	channels:    u32,
	sample_rate: u32,
	frame_count: u64,
	// For Stream sources: we store the original bytes (if loaded from memory)
	// File path streaming doesn't need stored data - miniaudio handles it
	stream_data: []u8, // Copy of original data for streaming from memory
	path:        string, // File path for streaming from file
}

// Miniaudio_Audio_Bus_Data stores data for a user-created bus
Miniaudio_Audio_Bus_Data :: struct {
	handle:      Audio_Bus,
	name:        string,
	sound_group: miniaudio.sound_group,
	volume:      f32, // Stored so we can restore after unmute
	muted:       bool,
}

// Miniaudio_Pending_Callback stores callback info to dispatch on main thread
Miniaudio_Pending_Callback :: struct {
	instance:  Audio_Instance,
	on_end:    Audio_End_Callback,
	user_data: rawptr,
}

// Thread-safe callback queue (fixed size ring buffer)
// Audio thread writes, main thread reads
MINIAUDIO_CALLBACK_QUEUE_SIZE :: 256

Miniaudio_Callback_Queue :: struct {
	callbacks:   [MINIAUDIO_CALLBACK_QUEUE_SIZE]Miniaudio_Pending_Callback,
	write_index: u32, // Written by audio thread (atomic)
	read_index:  u32, // Written by main thread (atomic)
}

// Miniaudio_Playing_Instance represents an actively playing sound
Miniaudio_Playing_Instance :: struct {
	handle:      Audio_Instance, // The handle returned to the user
	source:      Audio_Source, // Which source this is playing
	source_type: Audio_Source_Type,
	bus:         Audio_Bus, // Which bus this instance is playing on
	sound:       miniaudio.sound,
	// For Static: audio buffer from pre-decoded data
	buffer:      miniaudio.audio_buffer,
	// For Stream from memory: decoder that references the data
	decoder:     miniaudio.decoder,
	has_decoder: bool, // Whether decoder needs cleanup
	paused:      bool, // Whether the instance is paused (vs stopped)
	is_spatial:  bool, // Whether this instance uses spatial audio
	finished:    b32, // Set atomically by callback when sound ends
	on_end:      Audio_End_Callback,
	user_data:   rawptr,
}

// Backend state
Miniaudio_State :: struct {
	allocator:         runtime.Allocator,
	engine:            miniaudio.engine,
	main_sound_group:  miniaudio.sound_group,
	main_bus_volume:   f32,
	main_bus_muted:    bool,

	// User-created buses (indexed by handle - 2, since 1 is main bus)
	buses:             [dynamic]^Miniaudio_Audio_Bus_Data,
	next_bus_id:       u32, // Starts at 2 (1 is reserved for main bus)

	// Thread-safe callback queue for dispatching on main thread
	callback_queue:    Miniaudio_Callback_Queue,

	// Listener position for spatial audio (2D, z=0)
	listener_position: Vec2,

	// Sources are stored in a dynamic array, indexed by (handle - 1)
	sources:           [dynamic]^Miniaudio_Loaded_Source,

	// Active playing instances - stored in dynamic array
	// We use a simple array and mark finished instances for cleanup
	instances:         [dynamic]^Miniaudio_Playing_Instance,
	next_instance_id:  u32, // For generating unique instance handles
}

ma_state: ^Miniaudio_State

//--------------------------//
// LIFECYCLE IMPLEMENTATION //
//--------------------------//

miniaudio_state_size :: proc() -> int {
	return size_of(Miniaudio_State)
}

miniaudio_init :: proc(state_ptr: rawptr, allocator: runtime.Allocator) -> bool {
	ma_state = (^Miniaudio_State)(state_ptr)
	ma_state.allocator = allocator

	result := miniaudio.engine_init(nil, &ma_state.engine)
	if result != .SUCCESS {
		log.errorf("audio: Failed to initialize miniaudio engine: %v", result)
		ma_state = nil
		return false
	}

	result = miniaudio.sound_group_init(&ma_state.engine, {}, nil, &ma_state.main_sound_group)
	if result != .SUCCESS {
		log.errorf("audio: Failed to initialize main sound group: %v", result)
		miniaudio.engine_uninit(&ma_state.engine)
		ma_state = nil
		return false
	}

	ma_state.sources = make([dynamic]^Miniaudio_Loaded_Source, allocator)
	ma_state.instances = make([dynamic]^Miniaudio_Playing_Instance, allocator)
	ma_state.buses = make([dynamic]^Miniaudio_Audio_Bus_Data, allocator)
	ma_state.next_instance_id = 1
	ma_state.next_bus_id = 2 // 1 is reserved for main bus
	ma_state.main_bus_volume = 1.0
	ma_state.main_bus_muted = false

	return true
}

miniaudio_shutdown :: proc() {
	if ma_state == nil do return

	// Stop and clean up all playing instances
	for inst in ma_state.instances {
		if inst != nil {
			miniaudio.sound_uninit(&inst.sound)
			if inst.source_type == .Static {
				miniaudio.audio_buffer_uninit(&inst.buffer)
			} else if inst.has_decoder {
				miniaudio.decoder_uninit(&inst.decoder)
			}
			free(inst, ma_state.allocator)
		}
	}
	delete(ma_state.instances)

	// Clean up all user-created buses
	for bus in ma_state.buses {
		if bus != nil {
			miniaudio.sound_group_uninit(&bus.sound_group)
			if len(bus.name) > 0 {
				delete(bus.name, ma_state.allocator)
			}
			free(bus, ma_state.allocator)
		}
	}
	delete(ma_state.buses)

	// Clean up all loaded sources
	for src in ma_state.sources {
		if src != nil {
			if src.type == .Static {
				delete(src.data, ma_state.allocator)
			} else {
				if len(src.stream_data) > 0 {
					delete(src.stream_data, ma_state.allocator)
				}
				if len(src.path) > 0 {
					delete(src.path, ma_state.allocator)
				}
			}
			free(src, ma_state.allocator)
		}
	}
	delete(ma_state.sources)

	miniaudio.sound_group_uninit(&ma_state.main_sound_group)
	miniaudio.engine_uninit(&ma_state.engine)

	ma_state = nil
}

miniaudio_update :: proc() {
	if ma_state == nil do return

	// Dispatch queued callbacks (from audio thread)
	for {
		read_idx := intrinsics.atomic_load(&ma_state.callback_queue.read_index)
		write_idx := intrinsics.atomic_load(&ma_state.callback_queue.write_index)

		// Queue empty?
		if read_idx == write_idx {
			break
		}

		// Get callback and advance read index
		cb := ma_state.callback_queue.callbacks[read_idx]
		next_read := (read_idx + 1) % MINIAUDIO_CALLBACK_QUEUE_SIZE
		intrinsics.atomic_store(&ma_state.callback_queue.read_index, next_read)

		// Dispatch callback on main thread
		if cb.on_end != nil {
			cb.on_end(cb.instance, cb.user_data)
		}
	}

	// Clean up finished instances
	// We iterate backwards so we can remove elements safely
	#reverse for inst, i in ma_state.instances {
		if inst == nil do continue

		if intrinsics.atomic_load(&inst.finished) {
			miniaudio.sound_uninit(&inst.sound)
			if inst.source_type == .Static {
				miniaudio.audio_buffer_uninit(&inst.buffer)
			} else if inst.has_decoder {
				miniaudio.decoder_uninit(&inst.decoder)
			}
			free(inst, ma_state.allocator)
			ma_state.instances[i] = nil
		}
	}
}

miniaudio_set_internal_state :: proc(state_ptr: rawptr) {
	ma_state = (^Miniaudio_State)(state_ptr)
}

//--------------------------------//
// SOURCE MANAGEMENT IMPLEMENTATION //
//--------------------------------//

miniaudio_load_audio :: proc(path: string, type: Audio_Source_Type) -> Audio_Source {
	if ma_state == nil {
		log.error("audio: System not initialized")
		return AUDIO_SOURCE_NONE
	}

	if type == .Stream {
		// For streaming from file, we just store the path
		// miniaudio will handle streaming when we play
		source := new(Miniaudio_Loaded_Source, ma_state.allocator)
		source.type = .Stream
		source.path = strings.clone(path, ma_state.allocator)

		// Calculate duration at load time (so get_audio_duration is cheap)
		cpath := strings.clone_to_cstring(path, context.temp_allocator)
		decoder: miniaudio.decoder
		if miniaudio.decoder_init_file(cpath, nil, &decoder) == .SUCCESS {
			length: u64
			if miniaudio.decoder_get_length_in_pcm_frames(&decoder, &length) == .SUCCESS {
				source.duration = f32(length) / f32(decoder.outputSampleRate)
			}
			miniaudio.decoder_uninit(&decoder)
		}

		append(&ma_state.sources, source)
		return Audio_Source(len(ma_state.sources))
	}

	// Static: decode the entire file into memory
	cpath := strings.clone_to_cstring(path, context.temp_allocator)

	// Configure decoder to output f32 at engine sample rate
	engine_sample_rate := miniaudio.engine_get_sample_rate(&ma_state.engine)
	decoder_config := miniaudio.decoder_config_init(.f32, 0, engine_sample_rate)
	decoder: miniaudio.decoder

	result := miniaudio.decoder_init_file(cpath, &decoder_config, &decoder)
	if result != .SUCCESS {
		log.errorf("audio: Failed to load '%s': %v", path, result)
		return AUDIO_SOURCE_NONE
	}
	defer miniaudio.decoder_uninit(&decoder)

	return miniaudio_load_from_decoder(&decoder, .Static)
}

miniaudio_load_audio_from_bytes :: proc(data: []u8, type: Audio_Source_Type) -> Audio_Source {
	if ma_state == nil {
		log.error("audio: System not initialized")
		return AUDIO_SOURCE_NONE
	}

	if len(data) == 0 {
		log.error("audio: Cannot load from empty data")
		return AUDIO_SOURCE_NONE
	}

	if type == .Stream {
		// For streaming from memory, we need to keep a copy of the data
		// The decoder will reference it during playback
		source := new(Miniaudio_Loaded_Source, ma_state.allocator)
		source.type = .Stream
		source.stream_data = make([]u8, len(data), ma_state.allocator)
		copy(source.stream_data, data)

		// Calculate duration at load time (so get_audio_duration is cheap)
		decoder: miniaudio.decoder
		if miniaudio.decoder_init_memory(
			   raw_data(source.stream_data),
			   c.size_t(len(source.stream_data)),
			   nil,
			   &decoder,
		   ) ==
		   .SUCCESS {
			length: u64
			if miniaudio.decoder_get_length_in_pcm_frames(&decoder, &length) == .SUCCESS {
				source.duration = f32(length) / f32(decoder.outputSampleRate)
			}
			miniaudio.decoder_uninit(&decoder)
		}

		append(&ma_state.sources, source)
		return Audio_Source(len(ma_state.sources))
	}

	// Static: decode the entire data into PCM
	engine_sample_rate := miniaudio.engine_get_sample_rate(&ma_state.engine)
	decoder_config := miniaudio.decoder_config_init(.f32, 0, engine_sample_rate)
	decoder: miniaudio.decoder

	result := miniaudio.decoder_init_memory(
		raw_data(data),
		c.size_t(len(data)),
		&decoder_config,
		&decoder,
	)
	if result != .SUCCESS {
		log.errorf("audio: Failed to decode from memory: %v", result)
		return AUDIO_SOURCE_NONE
	}
	defer miniaudio.decoder_uninit(&decoder)

	return miniaudio_load_from_decoder(&decoder, .Static)
}

// Helper to load static audio from an initialized decoder
miniaudio_load_from_decoder :: proc(
	decoder: ^miniaudio.decoder,
	type: Audio_Source_Type,
) -> Audio_Source {
	channels := decoder.outputChannels
	bytes_per_frame := channels * size_of(f32)

	// Try to get the length
	frame_count: u64
	result := miniaudio.decoder_get_length_in_pcm_frames(decoder, &frame_count)

	pcm_data: []u8

	if result != .SUCCESS || frame_count == 0 {
		// For formats that don't support length query, read in chunks
		CHUNK_SIZE :: 4096
		chunks: [dynamic][]u8
		defer {
			for chunk in chunks {
				delete(chunk, ma_state.allocator)
			}
			delete(chunks)
		}

		frame_count = 0
		for {
			chunk := make([]u8, CHUNK_SIZE * int(bytes_per_frame), ma_state.allocator)
			frames_read: u64
			miniaudio.decoder_read_pcm_frames(decoder, raw_data(chunk), CHUNK_SIZE, &frames_read)

			if frames_read == 0 {
				delete(chunk, ma_state.allocator)
				break
			}

			frame_count += frames_read
			if frames_read < CHUNK_SIZE {
				append(&chunks, chunk[:frames_read * u64(bytes_per_frame)])
			} else {
				append(&chunks, chunk)
			}
		}

		// Combine all chunks
		total_bytes := int(frame_count) * int(bytes_per_frame)
		pcm_data = make([]u8, total_bytes, ma_state.allocator)
		offset := 0
		for chunk in chunks {
			copy(pcm_data[offset:], chunk)
			offset += len(chunk)
		}
	} else {
		// Known length - allocate and read directly
		total_bytes := int(frame_count) * int(bytes_per_frame)
		pcm_data = make([]u8, total_bytes, ma_state.allocator)

		frames_read: u64
		result = miniaudio.decoder_read_pcm_frames(
			decoder,
			raw_data(pcm_data),
			frame_count,
			&frames_read,
		)
		if result != .SUCCESS {
			log.errorf("audio: Failed to read PCM frames: %v", result)
			delete(pcm_data, ma_state.allocator)
			return AUDIO_SOURCE_NONE
		}
		frame_count = frames_read
	}

	// Create the source
	source := new(Miniaudio_Loaded_Source, ma_state.allocator)
	source.type = type
	source.data = pcm_data
	source.format = .f32
	source.channels = channels
	source.sample_rate = decoder.outputSampleRate
	source.frame_count = frame_count
	source.duration = f32(frame_count) / f32(decoder.outputSampleRate)

	// Add to sources array and return handle
	append(&ma_state.sources, source)
	return Audio_Source(len(ma_state.sources))
}

miniaudio_destroy_audio :: proc(source: Audio_Source) {
	if ma_state == nil do return
	if source == AUDIO_SOURCE_NONE do return

	idx := int(source) - 1
	if idx < 0 || idx >= len(ma_state.sources) do return

	src := ma_state.sources[idx]
	if src == nil do return

	// Clean up based on source type
	if src.type == .Static {
		delete(src.data, ma_state.allocator)
	} else {
		// Stream source
		if len(src.stream_data) > 0 {
			delete(src.stream_data, ma_state.allocator)
		}
		if len(src.path) > 0 {
			delete(src.path, ma_state.allocator)
		}
	}
	free(src, ma_state.allocator)
	ma_state.sources[idx] = nil
}

miniaudio_get_audio_duration :: proc(source: Audio_Source) -> f32 {
	if ma_state == nil do return 0
	if source == AUDIO_SOURCE_NONE do return 0

	idx := int(source) - 1
	if idx < 0 || idx >= len(ma_state.sources) do return 0

	src := ma_state.sources[idx]
	if src == nil do return 0

	// Duration is cached at load time for all source types
	return src.duration
}

//-------------------------//
// PLAYBACK IMPLEMENTATION //
//-------------------------//

miniaudio_play_audio :: proc(source: Audio_Source, params: Audio_Play_Params) -> Audio_Instance {
	if ma_state == nil {
		log.error("audio: System not initialized")
		return AUDIO_INSTANCE_NONE
	}

	if source == AUDIO_SOURCE_NONE {
		log.error("audio: Invalid source handle")
		return AUDIO_INSTANCE_NONE
	}

	idx := int(source) - 1
	if idx < 0 || idx >= len(ma_state.sources) {
		log.error("audio: Source handle out of range")
		return AUDIO_INSTANCE_NONE
	}

	src := ma_state.sources[idx]
	if src == nil {
		log.error("audio: Source has been destroyed")
		return AUDIO_INSTANCE_NONE
	}

	// Create a new playing instance
	inst := new(Miniaudio_Playing_Instance, ma_state.allocator)
	inst.source = source
	inst.source_type = src.type
	inst.bus = params.bus
	inst.on_end = params.on_end
	inst.user_data = params.user_data

	// Generate unique handle
	inst.handle = Audio_Instance(ma_state.next_instance_id)
	ma_state.next_instance_id += 1

	// Determine which sound group to use
	sound_group: ^miniaudio.sound_group
	if params.bus == AUDIO_BUS_NONE || params.bus == Audio_Bus(1) {
		sound_group = &ma_state.main_sound_group
	} else {
		bus := miniaudio_find_bus(params.bus)
		if bus != nil {
			sound_group = &bus.sound_group
		} else {
			sound_group = &ma_state.main_sound_group
		}
	}

	result: miniaudio.result

	if src.type == .Static {
		// Static source: create audio buffer from pre-decoded PCM data
		buffer_config := miniaudio.audio_buffer_config_init(
			src.format,
			src.channels,
			src.frame_count,
			raw_data(src.data),
			nil,
		)

		result = miniaudio.audio_buffer_init(&buffer_config, &inst.buffer)
		if result != .SUCCESS {
			log.errorf("audio: Failed to create audio buffer: %v", result)
			free(inst, ma_state.allocator)
			return AUDIO_INSTANCE_NONE
		}

		// Create a sound from the audio buffer
		result = miniaudio.sound_init_from_data_source(
			&ma_state.engine,
			cast(^miniaudio.data_source)&inst.buffer,
			{},
			sound_group,
			&inst.sound,
		)
		if result != .SUCCESS {
			log.errorf("audio: Failed to create sound: %v", result)
			miniaudio.audio_buffer_uninit(&inst.buffer)
			free(inst, ma_state.allocator)
			return AUDIO_INSTANCE_NONE
		}
	} else {
		// Stream source: create decoder and sound
		if len(src.path) > 0 {
			// Stream from file
			cpath := strings.clone_to_cstring(src.path, context.temp_allocator)
			result = miniaudio.sound_init_from_file(
				&ma_state.engine,
				cpath,
				{.STREAM},
				sound_group,
				nil,
				&inst.sound,
			)
			if result != .SUCCESS {
				log.errorf("audio: Failed to stream from file '%s': %v", src.path, result)
				free(inst, ma_state.allocator)
				return AUDIO_INSTANCE_NONE
			}
		} else if len(src.stream_data) > 0 {
			// Stream from memory - need a decoder
			decoder_config := miniaudio.decoder_config_init_default()
			result = miniaudio.decoder_init_memory(
				raw_data(src.stream_data),
				c.size_t(len(src.stream_data)),
				&decoder_config,
				&inst.decoder,
			)
			if result != .SUCCESS {
				log.errorf("audio: Failed to init decoder from memory: %v", result)
				free(inst, ma_state.allocator)
				return AUDIO_INSTANCE_NONE
			}
			inst.has_decoder = true

			// Create sound from decoder
			result = miniaudio.sound_init_from_data_source(
				&ma_state.engine,
				cast(^miniaudio.data_source)&inst.decoder,
				{.STREAM},
				sound_group,
				&inst.sound,
			)
			if result != .SUCCESS {
				log.errorf("audio: Failed to create sound from decoder: %v", result)
				miniaudio.decoder_uninit(&inst.decoder)
				free(inst, ma_state.allocator)
				return AUDIO_INSTANCE_NONE
			}
		} else {
			log.error("audio: Stream source has no data")
			free(inst, ma_state.allocator)
			return AUDIO_INSTANCE_NONE
		}
	}

	// Apply parameters
	miniaudio.sound_set_volume(&inst.sound, params.volume)
	miniaudio.sound_set_pan(&inst.sound, params.pan)
	miniaudio.sound_set_pitch(&inst.sound, params.pitch)
	miniaudio.sound_set_looping(&inst.sound, b32(params.loop))

	// Handle spatial audio
	if spatial_params, has_spatial := params.spatial.?; has_spatial {
		inst.is_spatial = true
		miniaudio.sound_set_spatialization_enabled(&inst.sound, true)
		miniaudio.sound_set_position(
			&inst.sound,
			spatial_params.position.x,
			spatial_params.position.y,
			0,
		)
		miniaudio.sound_set_min_distance(&inst.sound, spatial_params.min_distance)
		miniaudio.sound_set_max_distance(&inst.sound, spatial_params.max_distance)
		// Use linear attenuation so volume reaches zero at max_distance
		miniaudio.sound_set_attenuation_model(&inst.sound, .linear)
	} else {
		// Explicitly disable spatialization for non-spatial sounds
		miniaudio.sound_set_spatialization_enabled(&inst.sound, false)
	}

	// Set callback to mark sound as finished
	miniaudio.sound_set_end_callback(&inst.sound, miniaudio_instance_end_callback, inst)

	// Handle delayed playback
	if params.delay > 0 {
		engine_time := miniaudio.engine_get_time_in_milliseconds(&ma_state.engine)
		start_time := engine_time + u64(params.delay * 1000)
		miniaudio.sound_set_start_time_in_milliseconds(&inst.sound, start_time)
	}

	// Start playback
	result = miniaudio.sound_start(&inst.sound)
	if result != .SUCCESS {
		log.errorf("audio: Failed to start sound: %v", result)
		miniaudio.sound_uninit(&inst.sound)
		if src.type == .Static {
			miniaudio.audio_buffer_uninit(&inst.buffer)
		} else if inst.has_decoder {
			miniaudio.decoder_uninit(&inst.decoder)
		}
		free(inst, ma_state.allocator)
		return AUDIO_INSTANCE_NONE
	}

	// Add to instances list
	append(&ma_state.instances, inst)

	return inst.handle
}

miniaudio_instance_end_callback :: proc "c" (user_data: rawptr, snd: ^miniaudio.sound) {
	inst := cast(^Miniaudio_Playing_Instance)user_data

	// If there's a callback, queue it for main thread dispatch
	if inst.on_end != nil {
		miniaudio_queue_callback(inst.handle, inst.on_end, inst.user_data)
	}

	intrinsics.atomic_store(&inst.finished, true)
}

// Queue a callback for dispatch on the main thread (called from audio thread)
miniaudio_queue_callback :: proc "c" (
	instance: Audio_Instance,
	on_end: Audio_End_Callback,
	user_data: rawptr,
) {
	// Simple ring buffer write
	// Note: we don't check for overflow - if queue is full, callback is dropped
	// This is acceptable for most games (256 simultaneous sound endings is a lot)
	write_idx := intrinsics.atomic_load(&ma_state.callback_queue.write_index)
	next_write := (write_idx + 1) % MINIAUDIO_CALLBACK_QUEUE_SIZE

	// Check if queue is full (write would catch up to read)
	read_idx := intrinsics.atomic_load(&ma_state.callback_queue.read_index)
	if next_write == read_idx {
		// Queue full, drop callback
		return
	}

	ma_state.callback_queue.callbacks[write_idx] = Miniaudio_Pending_Callback {
		instance  = instance,
		on_end    = on_end,
		user_data = user_data,
	}

	intrinsics.atomic_store(&ma_state.callback_queue.write_index, next_write)
}

// Helper to find an instance by handle
miniaudio_find_instance :: proc(handle: Audio_Instance) -> ^Miniaudio_Playing_Instance {
	if handle == AUDIO_INSTANCE_NONE do return nil

	for inst in ma_state.instances {
		if inst != nil && inst.handle == handle {
			return inst
		}
	}
	return nil
}

miniaudio_stop_audio :: proc(instance: Audio_Instance) {
	if ma_state == nil do return

	inst := miniaudio_find_instance(instance)
	if inst == nil do return

	miniaudio.sound_stop(&inst.sound)
	inst.paused = false
	intrinsics.atomic_store(&inst.finished, true)
}

miniaudio_pause_audio :: proc(instance: Audio_Instance) {
	if ma_state == nil do return

	inst := miniaudio_find_instance(instance)
	if inst == nil do return

	miniaudio.sound_stop(&inst.sound)
	inst.paused = true
}

miniaudio_resume_audio :: proc(instance: Audio_Instance) {
	if ma_state == nil do return

	inst := miniaudio_find_instance(instance)
	if inst == nil do return

	if inst.paused {
		miniaudio.sound_start(&inst.sound)
		inst.paused = false
	}
}

miniaudio_stop_all_audio :: proc(bus: Audio_Bus) {
	if ma_state == nil do return

	for inst in ma_state.instances {
		if inst == nil do continue
		if intrinsics.atomic_load(&inst.finished) do continue

		// Filter by bus if specified
		if bus != AUDIO_BUS_NONE {
			// If a specific bus is given, only stop sounds on that bus
			if inst.bus != bus do continue
		}

		miniaudio.sound_stop(&inst.sound)
		inst.paused = false
		intrinsics.atomic_store(&inst.finished, true)
	}
}

//-----------------------------//
// LIVE CONTROL IMPLEMENTATION //
//-----------------------------//

miniaudio_set_audio_volume :: proc(instance: Audio_Instance, volume: f32) {
	if ma_state == nil do return

	inst := miniaudio_find_instance(instance)
	if inst == nil do return

	miniaudio.sound_set_volume(&inst.sound, volume)
}

miniaudio_set_audio_pan :: proc(instance: Audio_Instance, pan: f32) {
	if ma_state == nil do return

	inst := miniaudio_find_instance(instance)
	if inst == nil do return

	miniaudio.sound_set_pan(&inst.sound, pan)
}

miniaudio_set_audio_pitch :: proc(instance: Audio_Instance, pitch: f32) {
	if ma_state == nil do return

	inst := miniaudio_find_instance(instance)
	if inst == nil do return

	miniaudio.sound_set_pitch(&inst.sound, pitch)
}

miniaudio_set_audio_looping :: proc(instance: Audio_Instance, loop: bool) {
	if ma_state == nil do return

	inst := miniaudio_find_instance(instance)
	if inst == nil do return

	miniaudio.sound_set_looping(&inst.sound, b32(loop))
}

miniaudio_set_audio_position :: proc(instance: Audio_Instance, position: Vec2) {
	if ma_state == nil do return

	inst := miniaudio_find_instance(instance)
	if inst == nil do return

	// Only update position for spatial sounds
	if inst.is_spatial {
		miniaudio.sound_set_position(&inst.sound, position.x, position.y, 0)
	}
}

//----------------------//
// QUERY IMPLEMENTATION //
//----------------------//

miniaudio_is_audio_playing :: proc(instance: Audio_Instance) -> bool {
	if ma_state == nil do return false

	inst := miniaudio_find_instance(instance)
	if inst == nil do return false

	return bool(miniaudio.sound_is_playing(&inst.sound))
}

miniaudio_is_audio_paused :: proc(instance: Audio_Instance) -> bool {
	if ma_state == nil do return false

	inst := miniaudio_find_instance(instance)
	if inst == nil do return false

	return inst.paused
}

miniaudio_get_audio_time :: proc(instance: Audio_Instance) -> f32 {
	if ma_state == nil do return 0

	inst := miniaudio_find_instance(instance)
	if inst == nil do return 0

	cursor: u64
	if miniaudio.sound_get_cursor_in_pcm_frames(&inst.sound, &cursor) == .SUCCESS {
		// miniaudio resamples everything to engine sample rate
		engine_sample_rate := miniaudio.engine_get_sample_rate(&ma_state.engine)
		if engine_sample_rate > 0 {
			return f32(cursor) / f32(engine_sample_rate)
		}
	}
	return 0
}

//--------------------//
// BUS IMPLEMENTATION //
//--------------------//

// Helper to find a bus by handle
miniaudio_find_bus :: proc(handle: Audio_Bus) -> ^Miniaudio_Audio_Bus_Data {
	if handle == AUDIO_BUS_NONE do return nil
	if handle == Audio_Bus(1) do return nil // Main bus is not in the array

	for bus in ma_state.buses {
		if bus != nil && bus.handle == handle {
			return bus
		}
	}
	return nil
}

miniaudio_create_audio_bus :: proc(name: string) -> Audio_Bus {
	if ma_state == nil {
		log.error("audio: System not initialized")
		return AUDIO_BUS_NONE
	}

	bus := new(Miniaudio_Audio_Bus_Data, ma_state.allocator)
	bus.handle = Audio_Bus(ma_state.next_bus_id)
	ma_state.next_bus_id += 1
	bus.volume = 1.0
	bus.muted = false

	if len(name) > 0 {
		bus.name = strings.clone(name, ma_state.allocator)
	}

	// Create sound group parented to main sound group
	result := miniaudio.sound_group_init(
		&ma_state.engine,
		{},
		&ma_state.main_sound_group,
		&bus.sound_group,
	)
	if result != .SUCCESS {
		log.errorf("audio: Failed to create bus '%s': %v", name, result)
		if len(bus.name) > 0 {
			delete(bus.name, ma_state.allocator)
		}
		free(bus, ma_state.allocator)
		return AUDIO_BUS_NONE
	}

	append(&ma_state.buses, bus)
	return bus.handle
}

miniaudio_destroy_audio_bus :: proc(bus_handle: Audio_Bus) {
	if ma_state == nil do return
	if bus_handle == AUDIO_BUS_NONE do return
	if bus_handle == Audio_Bus(1) do return // Can't destroy main bus

	for &bus, i in ma_state.buses {
		if bus != nil && bus.handle == bus_handle {
			miniaudio.sound_group_uninit(&bus.sound_group)
			if len(bus.name) > 0 {
				delete(bus.name, ma_state.allocator)
			}
			free(bus, ma_state.allocator)
			ma_state.buses[i] = nil
			return
		}
	}
}

miniaudio_get_main_audio_bus :: proc() -> Audio_Bus {
	return Audio_Bus(1)
}

miniaudio_set_audio_bus_volume :: proc(bus_handle: Audio_Bus, volume: f32) {
	if ma_state == nil do return

	// Main bus (handle 1 or NONE means main)
	if bus_handle == Audio_Bus(1) || bus_handle == AUDIO_BUS_NONE {
		ma_state.main_bus_volume = volume
		if !ma_state.main_bus_muted {
			miniaudio.sound_group_set_volume(&ma_state.main_sound_group, volume)
		}
		return
	}

	// User-created bus
	bus := miniaudio_find_bus(bus_handle)
	if bus == nil do return

	bus.volume = volume
	if !bus.muted {
		miniaudio.sound_group_set_volume(&bus.sound_group, volume)
	}
}

miniaudio_get_audio_bus_volume :: proc(bus_handle: Audio_Bus) -> f32 {
	if ma_state == nil do return 1.0

	// Main bus
	if bus_handle == Audio_Bus(1) || bus_handle == AUDIO_BUS_NONE {
		return ma_state.main_bus_volume
	}

	// User-created bus
	bus := miniaudio_find_bus(bus_handle)
	if bus == nil do return 1.0

	return bus.volume
}

miniaudio_set_audio_bus_muted :: proc(bus_handle: Audio_Bus, muted: bool) {
	if ma_state == nil do return

	// Main bus
	if bus_handle == Audio_Bus(1) || bus_handle == AUDIO_BUS_NONE {
		ma_state.main_bus_muted = muted
		if muted {
			miniaudio.sound_group_set_volume(&ma_state.main_sound_group, 0)
		} else {
			miniaudio.sound_group_set_volume(&ma_state.main_sound_group, ma_state.main_bus_volume)
		}
		return
	}

	// User-created bus
	bus := miniaudio_find_bus(bus_handle)
	if bus == nil do return

	bus.muted = muted
	if muted {
		miniaudio.sound_group_set_volume(&bus.sound_group, 0)
	} else {
		miniaudio.sound_group_set_volume(&bus.sound_group, bus.volume)
	}
}

miniaudio_is_audio_bus_muted :: proc(bus_handle: Audio_Bus) -> bool {
	if ma_state == nil do return false

	// Main bus
	if bus_handle == Audio_Bus(1) || bus_handle == AUDIO_BUS_NONE {
		return ma_state.main_bus_muted
	}

	// User-created bus
	bus := miniaudio_find_bus(bus_handle)
	if bus == nil do return false

	return bus.muted
}

//-------------------------//
// LISTENER IMPLEMENTATION //
//-------------------------//

miniaudio_set_audio_listener_position :: proc(position: Vec2) {
	if ma_state == nil do return

	ma_state.listener_position = position
	// Set listener position in miniaudio (z=0 for 2D)
	miniaudio.engine_listener_set_position(&ma_state.engine, 0, position.x, position.y, 0)
}

miniaudio_get_audio_listener_position :: proc() -> Vec2 {
	if ma_state == nil do return {0, 0}
	return ma_state.listener_position
}
