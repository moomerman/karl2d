#+build windows, linux, darwin
#+private file

package karl2d

import "base:intrinsics"
import "base:runtime"
import "core:c"
import "core:strings"
import "log"
import "vendor:miniaudio"

@(private = "package")
AUDIO_MINIAUDIO :: Audio_Interface {
	state_size            = ma_state_size,
	init                  = ma_init,
	shutdown              = ma_shutdown,
	update                = ma_update,
	load_sound            = ma_load_sound,
	load_sound_from_bytes = ma_load_sound_from_bytes,
	destroy_sound         = ma_destroy_sound,
	play_sound            = ma_play_sound,
	play_music            = ma_play_music,
	play_music_from_bytes = ma_play_music_from_bytes,
	stop_music            = ma_stop_music,
	is_music_playing      = ma_is_music_playing,
	set_master_volume     = ma_set_master_volume,
	set_sound_volume      = ma_set_sound_volume,
	set_music_volume      = ma_set_music_volume,
	set_internal_state    = ma_set_internal_state,
}

// Pre-loaded sound data - decoded once, can be played many times
Loaded_Sound :: struct {
	data:        []u8, // Decoded PCM data
	format:      miniaudio.format,
	channels:    u32,
	sample_rate: u32,
	frame_count: u64,
}

// Active playing sound instance (fire-and-forget)
Playing_Sound :: struct {
	sound:    miniaudio.sound,
	decoder:  miniaudio.audio_buffer,
	finished: b32, // Set to true by callback when sound ends (atomic)
	next:     ^Playing_Sound, // For linked list of active sounds
}

// Wrapper for music loaded from memory that needs to keep the decoder alive
Music_From_Memory :: struct {
	sound:   miniaudio.sound,
	decoder: miniaudio.decoder,
	data:    []u8, // Keep a copy of the data since decoder references it
}

Miniaudio_State :: struct {
	allocator:      runtime.Allocator,
	engine:         miniaudio.engine,
	sound_group:    miniaudio.sound_group,
	// Pre-loaded sounds (indexed by handle - 1)
	loaded_sounds:  [dynamic]^Loaded_Sound,
	// For file-based music
	music:          ^miniaudio.sound,
	// For memory-based music
	music_mem:      ^Music_From_Memory,
	// Linked list of active fire-and-forget sounds
	playing_sounds: ^Playing_Sound,
	// Stored volume levels (so we can apply them when music restarts)
	music_volume:   f32,
}

ma_state: ^Miniaudio_State

ma_state_size :: proc() -> int {
	return size_of(Miniaudio_State)
}

ma_init :: proc(state: rawptr) -> bool {
	ma_state = (^Miniaudio_State)(state)
	ma_state.allocator = context.allocator

	result := miniaudio.engine_init(nil, &ma_state.engine)
	if result != .SUCCESS {
		log.errorf("Failed to initialize audio engine: %v", result)
		return false
	}

	result = miniaudio.sound_group_init(&ma_state.engine, {}, nil, &ma_state.sound_group)
	if result != .SUCCESS {
		log.errorf("Failed to initialize sound group: %v", result)
		miniaudio.engine_uninit(&ma_state.engine)
		return false
	}

	ma_state.loaded_sounds = make([dynamic]^Loaded_Sound, ma_state.allocator)
	ma_state.music = nil
	ma_state.music_mem = nil
	ma_state.playing_sounds = nil
	ma_state.music_volume = 1.0
	return true
}

// Clean up finished sounds - called each frame from main thread
ma_update :: proc() {
	if ma_state == nil do return

	prev: ^Playing_Sound = nil
	curr := ma_state.playing_sounds

	for curr != nil {
		next := curr.next

		if intrinsics.atomic_load(&curr.finished) {
			// Remove from list
			if prev == nil {
				ma_state.playing_sounds = next
			} else {
				prev.next = next
			}

			// Clean up
			miniaudio.sound_uninit(&curr.sound)
			miniaudio.audio_buffer_uninit(&curr.decoder)
			free(curr, ma_state.allocator)
		} else {
			prev = curr
		}

		curr = next
	}
}

ma_shutdown :: proc() {
	if ma_state == nil do return

	ma_stop_music()

	// Clean up all playing sounds
	curr := ma_state.playing_sounds
	for curr != nil {
		next := curr.next
		miniaudio.sound_uninit(&curr.sound)
		miniaudio.audio_buffer_uninit(&curr.decoder)
		free(curr, ma_state.allocator)
		curr = next
	}
	ma_state.playing_sounds = nil

	// Clean up all loaded sounds
	for snd in ma_state.loaded_sounds {
		if snd != nil {
			delete(snd.data, ma_state.allocator)
			free(snd, ma_state.allocator)
		}
	}
	delete(ma_state.loaded_sounds)

	miniaudio.sound_group_uninit(&ma_state.sound_group)
	miniaudio.engine_uninit(&ma_state.engine)
}

// Load a sound from a file path - decodes once, returns handle for playback
ma_load_sound :: proc(path: string) -> Sound_Handle {
	if ma_state == nil {
		log.error("Audio system not initialized")
		return Sound_Handle(0)
	}

	cpath := strings.clone_to_cstring(path, context.temp_allocator)

	// Use decoder to load and decode the file - configure to output f32 at engine sample rate
	engine_sample_rate := miniaudio.engine_get_sample_rate(&ma_state.engine)
	decoder_config := miniaudio.decoder_config_init(.f32, 0, engine_sample_rate)
	decoder: miniaudio.decoder

	result := miniaudio.decoder_init_file(cpath, &decoder_config, &decoder)
	if result != .SUCCESS {
		log.errorf("Failed to load sound file '%s': %v", path, result)
		return Sound_Handle(0)
	}
	defer miniaudio.decoder_uninit(&decoder)

	return ma_load_sound_from_decoder(&decoder)
}

// Load a sound from raw bytes - decodes once, returns handle for playback
ma_load_sound_from_bytes :: proc(data: []u8) -> Sound_Handle {
	if ma_state == nil {
		log.error("Audio system not initialized")
		return Sound_Handle(0)
	}

	if len(data) == 0 {
		log.error("Cannot load sound from empty data")
		return Sound_Handle(0)
	}

	// Use decoder to decode the data - configure to output f32 at engine sample rate
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
		log.errorf("Failed to decode sound from memory: %v", result)
		return Sound_Handle(0)
	}
	defer miniaudio.decoder_uninit(&decoder)

	return ma_load_sound_from_decoder(&decoder)
}

// Helper to load sound data from an initialized decoder
ma_load_sound_from_decoder :: proc(decoder: ^miniaudio.decoder) -> Sound_Handle {
	// Get the length of the audio
	frame_count: u64
	result := miniaudio.decoder_get_length_in_pcm_frames(decoder, &frame_count)
	if result != .SUCCESS || frame_count == 0 {
		// For formats that don't support length query, read in chunks
		frame_count = 0
		chunk_size :: 4096
		chunks: [dynamic][]u8
		defer {
			for chunk in chunks {
				delete(chunk, ma_state.allocator)
			}
			delete(chunks)
		}

		channels := decoder.outputChannels
		bytes_per_frame := channels * size_of(f32)

		for {
			chunk := make([]u8, chunk_size * int(bytes_per_frame), ma_state.allocator)
			frames_read: u64
			miniaudio.decoder_read_pcm_frames(decoder, raw_data(chunk), chunk_size, &frames_read)

			if frames_read == 0 {
				delete(chunk, ma_state.allocator)
				break
			}

			frame_count += frames_read
			if frames_read < chunk_size {
				// Shrink last chunk
				append(&chunks, chunk[:frames_read * u64(bytes_per_frame)])
			} else {
				append(&chunks, chunk)
			}
		}

		// Combine all chunks
		total_bytes := int(frame_count) * int(bytes_per_frame)
		pcm_data := make([]u8, total_bytes, ma_state.allocator)
		offset := 0
		for chunk in chunks {
			copy(pcm_data[offset:], chunk)
			offset += len(chunk)
		}

		// Create the loaded sound
		loaded := new(Loaded_Sound, ma_state.allocator)
		loaded.data = pcm_data
		loaded.format = .f32
		loaded.channels = channels
		loaded.sample_rate = decoder.outputSampleRate
		loaded.frame_count = frame_count

		// Add to loaded sounds array and return handle
		append(&ma_state.loaded_sounds, loaded)
		return Sound_Handle(len(ma_state.loaded_sounds))
	}

	// Allocate buffer for decoded PCM data (f32 format)
	channels := decoder.outputChannels
	bytes_per_frame := channels * size_of(f32)
	total_bytes := int(frame_count) * int(bytes_per_frame)

	pcm_data := make([]u8, total_bytes, ma_state.allocator)

	// Read all frames
	frames_read: u64
	result = miniaudio.decoder_read_pcm_frames(
		decoder,
		raw_data(pcm_data),
		frame_count,
		&frames_read,
	)
	if result != .SUCCESS {
		log.errorf("Failed to read PCM frames: %v", result)
		delete(pcm_data, ma_state.allocator)
		return Sound_Handle(0)
	}

	// Create the loaded sound
	loaded := new(Loaded_Sound, ma_state.allocator)
	loaded.data = pcm_data
	loaded.format = .f32
	loaded.channels = channels
	loaded.sample_rate = decoder.outputSampleRate
	loaded.frame_count = frames_read

	// Add to loaded sounds array and return handle
	append(&ma_state.loaded_sounds, loaded)
	return Sound_Handle(len(ma_state.loaded_sounds))
}

// Destroy a loaded sound and free its resources
ma_destroy_sound :: proc(handle: Sound_Handle) {
	if ma_state == nil do return
	if handle == Sound_Handle(0) do return

	idx := int(handle) - 1
	if idx < 0 || idx >= len(ma_state.loaded_sounds) do return

	loaded := ma_state.loaded_sounds[idx]
	if loaded == nil do return

	delete(loaded.data, ma_state.allocator)
	free(loaded, ma_state.allocator)
	ma_state.loaded_sounds[idx] = nil
}

// Play a pre-loaded sound (fire and forget)
ma_play_sound :: proc(handle: Sound_Handle) -> bool {
	if ma_state == nil {
		log.error("Audio system not initialized")
		return false
	}

	if handle == Sound_Handle(0) {
		log.error("Invalid sound handle")
		return false
	}

	idx := int(handle) - 1
	if idx < 0 || idx >= len(ma_state.loaded_sounds) {
		log.error("Sound handle out of range")
		return false
	}

	loaded := ma_state.loaded_sounds[idx]
	if loaded == nil {
		log.error("Sound has been destroyed")
		return false
	}

	// Create a playing sound instance
	playing := new(Playing_Sound, ma_state.allocator)

	// Create an audio buffer from the pre-decoded PCM data
	buffer_config := miniaudio.audio_buffer_config_init(
		loaded.format,
		loaded.channels,
		loaded.frame_count,
		raw_data(loaded.data),
		nil,
	)

	result := miniaudio.audio_buffer_init(&buffer_config, &playing.decoder)
	if result != .SUCCESS {
		log.errorf("Failed to create audio buffer: %v", result)
		free(playing, ma_state.allocator)
		return false
	}

	// Create a sound from the audio buffer
	result = miniaudio.sound_init_from_data_source(
		&ma_state.engine,
		cast(^miniaudio.data_source)&playing.decoder,
		{},
		&ma_state.sound_group,
		&playing.sound,
	)

	if result != .SUCCESS {
		log.errorf("Failed to create sound from buffer: %v", result)
		miniaudio.audio_buffer_uninit(&playing.decoder)
		free(playing, ma_state.allocator)
		return false
	}

	// Set callback to mark sound as finished
	miniaudio.sound_set_end_callback(&playing.sound, ma_playing_sound_end_callback, playing)

	result = miniaudio.sound_start(&playing.sound)
	if result != .SUCCESS {
		log.errorf("Failed to start sound: %v", result)
		miniaudio.sound_uninit(&playing.sound)
		miniaudio.audio_buffer_uninit(&playing.decoder)
		free(playing, ma_state.allocator)
		return false
	}

	// Add to linked list of playing sounds
	playing.next = ma_state.playing_sounds
	ma_state.playing_sounds = playing

	return true
}

// Callback just marks sound as finished - cleanup happens on main thread
ma_playing_sound_end_callback :: proc "c" (user_data: rawptr, snd: ^miniaudio.sound) {
	playing := cast(^Playing_Sound)user_data
	intrinsics.atomic_store(&playing.finished, true)
}

ma_play_music :: proc(path: string, loop: bool, delay_seconds: f32) -> bool {
	if ma_state == nil {
		log.error("Audio system not initialized")
		return false
	}

	ma_stop_music()

	ma_state.music = new(miniaudio.sound, ma_state.allocator)

	cpath := strings.clone_to_cstring(path, context.temp_allocator)

	result := miniaudio.sound_init_from_file(
		&ma_state.engine,
		cpath,
		{},
		nil, // music goes directly to engine, not through sound_group
		nil,
		ma_state.music,
	)
	if result != .SUCCESS {
		log.errorf("Failed to load music file '%s': %v", path, result)
		free(ma_state.music, ma_state.allocator)
		ma_state.music = nil
		return false
	}

	miniaudio.sound_set_looping(ma_state.music, b32(loop))
	miniaudio.sound_set_volume(ma_state.music, ma_state.music_volume)

	if delay_seconds > 0 {
		engine_time := miniaudio.engine_get_time_in_milliseconds(&ma_state.engine)
		start_time := engine_time + u64(delay_seconds * 1000)
		miniaudio.sound_set_start_time_in_milliseconds(ma_state.music, start_time)
	}

	result = miniaudio.sound_start(ma_state.music)
	if result != .SUCCESS {
		log.errorf("Failed to start music: %v", result)
		miniaudio.sound_uninit(ma_state.music)
		free(ma_state.music, ma_state.allocator)
		ma_state.music = nil
		return false
	}

	return true
}

ma_play_music_from_bytes :: proc(data: []u8, loop: bool, delay_seconds: f32) -> bool {
	if ma_state == nil {
		log.error("Audio system not initialized")
		return false
	}

	if len(data) == 0 {
		log.error("Cannot play music from empty data")
		return false
	}

	ma_stop_music()

	// Allocate our wrapper struct
	ma_state.music_mem = new(Music_From_Memory, ma_state.allocator)

	// Copy the data since the decoder will reference it
	ma_state.music_mem.data = make([]u8, len(data), ma_state.allocator)
	copy(ma_state.music_mem.data, data)

	// Initialize decoder from memory
	decoder_config := miniaudio.decoder_config_init_default()
	result := miniaudio.decoder_init_memory(
		raw_data(ma_state.music_mem.data),
		c.size_t(len(ma_state.music_mem.data)),
		&decoder_config,
		&ma_state.music_mem.decoder,
	)
	if result != .SUCCESS {
		log.errorf("Failed to initialize decoder from memory: %v", result)
		delete(ma_state.music_mem.data, ma_state.allocator)
		free(ma_state.music_mem, ma_state.allocator)
		ma_state.music_mem = nil
		return false
	}

	// Create sound from decoder data source
	// Cast decoder directly - ds is at offset 0
	result = miniaudio.sound_init_from_data_source(
		&ma_state.engine,
		cast(^miniaudio.data_source)&ma_state.music_mem.decoder,
		{}, // Don't decode fully - stream it for music
		nil, // music goes directly to engine
		&ma_state.music_mem.sound,
	)
	if result != .SUCCESS {
		log.errorf("Failed to create music from memory: %v", result)
		miniaudio.decoder_uninit(&ma_state.music_mem.decoder)
		delete(ma_state.music_mem.data, ma_state.allocator)
		free(ma_state.music_mem, ma_state.allocator)
		ma_state.music_mem = nil
		return false
	}

	miniaudio.sound_set_looping(&ma_state.music_mem.sound, b32(loop))
	miniaudio.sound_set_volume(&ma_state.music_mem.sound, ma_state.music_volume)

	if delay_seconds > 0 {
		engine_time := miniaudio.engine_get_time_in_milliseconds(&ma_state.engine)
		start_time := engine_time + u64(delay_seconds * 1000)
		miniaudio.sound_set_start_time_in_milliseconds(&ma_state.music_mem.sound, start_time)
	}

	result = miniaudio.sound_start(&ma_state.music_mem.sound)
	if result != .SUCCESS {
		log.errorf("Failed to start music from memory: %v", result)
		miniaudio.sound_uninit(&ma_state.music_mem.sound)
		miniaudio.decoder_uninit(&ma_state.music_mem.decoder)
		delete(ma_state.music_mem.data, ma_state.allocator)
		free(ma_state.music_mem, ma_state.allocator)
		ma_state.music_mem = nil
		return false
	}

	return true
}

ma_stop_music :: proc() {
	if ma_state == nil do return

	// Stop file-based music
	if ma_state.music != nil {
		miniaudio.sound_stop(ma_state.music)
		miniaudio.sound_uninit(ma_state.music)
		free(ma_state.music, ma_state.allocator)
		ma_state.music = nil
	}

	// Stop memory-based music
	if ma_state.music_mem != nil {
		miniaudio.sound_stop(&ma_state.music_mem.sound)
		miniaudio.sound_uninit(&ma_state.music_mem.sound)
		miniaudio.decoder_uninit(&ma_state.music_mem.decoder)
		delete(ma_state.music_mem.data, ma_state.allocator)
		free(ma_state.music_mem, ma_state.allocator)
		ma_state.music_mem = nil
	}
}

ma_is_music_playing :: proc() -> bool {
	if ma_state == nil do return false

	if ma_state.music != nil {
		return bool(miniaudio.sound_is_playing(ma_state.music))
	}

	if ma_state.music_mem != nil {
		return bool(miniaudio.sound_is_playing(&ma_state.music_mem.sound))
	}

	return false
}

ma_set_master_volume :: proc(volume: f32) {
	if ma_state == nil do return
	clamped := clamp(volume, 0.0, 1.0)
	miniaudio.engine_set_volume(&ma_state.engine, clamped)
}

ma_set_sound_volume :: proc(volume: f32) {
	if ma_state == nil do return
	clamped := clamp(volume, 0.0, 1.0)
	miniaudio.sound_group_set_volume(&ma_state.sound_group, clamped)
}

ma_set_music_volume :: proc(volume: f32) {
	if ma_state == nil do return
	clamped := clamp(volume, 0.0, 1.0)

	// Store the volume so we can apply it when music restarts
	ma_state.music_volume = clamped

	if ma_state.music != nil {
		miniaudio.sound_set_volume(ma_state.music, clamped)
	}

	if ma_state.music_mem != nil {
		miniaudio.sound_set_volume(&ma_state.music_mem.sound, clamped)
	}
}

ma_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	ma_state = (^Miniaudio_State)(state)
}
