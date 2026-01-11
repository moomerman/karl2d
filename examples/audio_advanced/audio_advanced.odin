// Advanced Audio Example - Demonstrates all audio features
//
// This example shows:
// - Loading static and streaming audio
// - Volume, pan, and pitch control for music
// - Audio buses for grouping sounds with individual volume controls
// - Pause/resume functionality
// - Spatial audio with listener positioning
// - End callbacks
//
// This example works on both desktop and web platforms.
package karl2d_audio_advanced

import k2 "../.."
import "core:math"

// Embed audio files (works on both desktop and web)
CLICK_WAV :: #load("click.wav")
MUSIC_MP3 :: #load("music.mp3")

// Audio buses
main_bus: k2.Audio_Bus
music_bus: k2.Audio_Bus
sfx_bus: k2.Audio_Bus

// Bus volumes
main_bus_volume: f32 = 1.0
music_bus_volume: f32 = 0.7
sfx_bus_volume: f32 = 1.0

// Audio sources
music_source: k2.Audio_Source
click_source: k2.Audio_Source

// Playing instances
music_instance: k2.Audio_Instance

// Music control state
music_volume: f32 = 1.0
music_pan: f32 = 0.0
music_pitch: f32 = 1.0
music_paused: bool = false

// Spatial audio demo
listener_pos: k2.Vec2 = {400, 520}
spatial_source_pos: k2.Vec2 = {200, 520}

// Callback counter
sounds_finished: int = 0

// Selected bus for volume control (0=main, 1=music, 2=sfx)
selected_bus: int = 0

main :: proc() {
	init()
	for step() {}
	shutdown()
}

init :: proc() {
	k2.init(800, 700, "Audio Advanced Example")

	// Get main bus and create custom buses
	main_bus = k2.get_main_audio_bus()
	music_bus = k2.create_audio_bus("music")
	sfx_bus = k2.create_audio_bus("sfx")

	// Set initial bus volumes
	k2.set_audio_bus_volume(main_bus, main_bus_volume)
	k2.set_audio_bus_volume(music_bus, music_bus_volume)
	k2.set_audio_bus_volume(sfx_bus, sfx_bus_volume)

	// Load audio sources
	// Use .Stream for long music files to save memory
	music_source = k2.load_audio_from_bytes(MUSIC_MP3, .Stream)
	// Use .Static (default) for short sound effects
	click_source = k2.load_audio_from_bytes(CLICK_WAV, .Static)

	// Start playing music on loop
	music_instance = k2.play_audio(music_source, {bus = music_bus, loop = true})

	// Set initial listener position for spatial audio
	k2.set_audio_listener_position(listener_pos)
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	handle_input()
	draw_ui()

	return true
}

handle_input :: proc() {
	// === BUS SELECTION (1/2/3) ===
	if k2.key_went_down(.N1) do selected_bus = 0
	if k2.key_went_down(.N2) do selected_bus = 1
	if k2.key_went_down(.N3) do selected_bus = 2

	// === BUS VOLUME CONTROL (Z/X while bus selected) ===
	bus_volume_delta: f32 = 0.0
	if k2.key_is_held(.Z) do bus_volume_delta = -0.01
	if k2.key_is_held(.X) do bus_volume_delta = 0.01

	if bus_volume_delta != 0 {
		switch selected_bus {
		case 0:
			main_bus_volume = clamp(main_bus_volume + bus_volume_delta, 0.0, 1.5)
			k2.set_audio_bus_volume(main_bus, main_bus_volume)
		case 1:
			music_bus_volume = clamp(music_bus_volume + bus_volume_delta, 0.0, 1.5)
			k2.set_audio_bus_volume(music_bus, music_bus_volume)
		case 2:
			sfx_bus_volume = clamp(sfx_bus_volume + bus_volume_delta, 0.0, 1.5)
			k2.set_audio_bus_volume(sfx_bus, sfx_bus_volume)
		}
	}

	// === BUS MUTE TOGGLE (M) ===
	if k2.key_went_down(.M) {
		bus: k2.Audio_Bus
		switch selected_bus {
		case 0:
			bus = main_bus
		case 1:
			bus = music_bus
		case 2:
			bus = sfx_bus
		}
		muted := k2.is_audio_bus_muted(bus)
		k2.set_audio_bus_muted(bus, !muted)
	}

	// === PLAY CLICK SOUND (Space) ===
	if k2.key_went_down(.Space) {
		k2.play_audio(
			click_source,
			{bus = sfx_bus, on_end = on_sound_end, user_data = &sounds_finished},
		)
	}

	// === MUSIC CONTROLS ===
	// Pause/resume music (P)
	if k2.key_went_down(.P) {
		if music_paused {
			k2.resume_audio(music_instance)
			music_paused = false
		} else {
			k2.pause_audio(music_instance)
			music_paused = true
		}
	}

	// Volume control (Up/Down)
	if k2.key_is_held(.Up) {
		music_volume = min(music_volume + 0.01, 1.5)
		k2.set_audio_volume(music_instance, music_volume)
	}
	if k2.key_is_held(.Down) {
		music_volume = max(music_volume - 0.01, 0.0)
		k2.set_audio_volume(music_instance, music_volume)
	}

	// Pan control (Left/Right)
	if k2.key_is_held(.Left) {
		music_pan = max(music_pan - 0.02, -1.0)
		k2.set_audio_pan(music_instance, music_pan)
	}
	if k2.key_is_held(.Right) {
		music_pan = min(music_pan + 0.02, 1.0)
		k2.set_audio_pan(music_instance, music_pan)
	}

	// Pitch control (Q/E)
	if k2.key_is_held(.Q) {
		music_pitch = max(music_pitch - 0.01, 0.25)
		k2.set_audio_pitch(music_instance, music_pitch)
	}
	if k2.key_is_held(.E) {
		music_pitch = min(music_pitch + 0.01, 2.0)
		k2.set_audio_pitch(music_instance, music_pitch)
	}

	// === MOVE LISTENER (WASD) ===
	move_speed: f32 = 3.0
	if k2.key_is_held(.W) do listener_pos.y -= move_speed
	if k2.key_is_held(.S) do listener_pos.y += move_speed
	if k2.key_is_held(.A) do listener_pos.x -= move_speed
	if k2.key_is_held(.D) do listener_pos.x += move_speed
	listener_pos.x = clamp(listener_pos.x, 50, 750)
	listener_pos.y = clamp(listener_pos.y, 420, 620)
	k2.set_audio_listener_position(listener_pos)

	// === PLAY SPATIAL SOUND (F) ===
	if k2.key_went_down(.F) {
		k2.play_audio(
			click_source,
			{
				bus = sfx_bus,
				spatial = k2.Audio_Spatial_Params {
					position = spatial_source_pos,
					min_distance = 50,
					max_distance = 300,
				},
				on_end = on_sound_end,
				user_data = &sounds_finished,
			},
		)
	}
}

draw_ui :: proc() {
	k2.clear({30, 40, 60, 255})

	k2.draw_text("Audio Advanced Example", {50, 20}, 28, k2.WHITE)

	// === BUS VOLUME CONTROLS ===
	k2.draw_text(
		"Bus Controls (1/2/3 to select, Z/X to adjust, M to mute):",
		{50, 60},
		18,
		k2.LIGHT_BLUE,
	)

	bus_y: f32 = 85
	draw_bus_control("Main Bus", main_bus, main_bus_volume, {70, bus_y}, selected_bus == 0)
	draw_bus_control("Music Bus", music_bus, music_bus_volume, {70, bus_y + 22}, selected_bus == 1)
	draw_bus_control("SFX Bus", sfx_bus, sfx_bus_volume, {70, bus_y + 44}, selected_bus == 2)

	// === MUSIC CONTROLS ===
	k2.draw_text(
		"Music Controls (Up/Down, Left/Right, Q/E, P=pause):",
		{50, 175},
		18,
		k2.LIGHT_BLUE,
	)

	ctrl_y: f32 = 200

	// Music state
	if music_paused {
		k2.draw_text("Status: PAUSED", {70, ctrl_y}, 16, k2.ORANGE)
	} else {
		k2.draw_text("Status: PLAYING", {70, ctrl_y}, 16, k2.GREEN)
	}

	draw_progress_bar("Volume:", music_volume / 1.5, {70, ctrl_y + 25})
	draw_progress_bar("Pan:", (music_pan + 1) / 2, {70, ctrl_y + 47})
	draw_progress_bar("Pitch:", (music_pitch - 0.25) / 1.75, {70, ctrl_y + 69})

	// === PLAY CONTROLS ===
	k2.draw_text("Press SPACE to play click sound", {400, 200}, 16, k2.GRAY)
	k2.draw_text("Callbacks:", {400, 225}, 16, k2.WHITE)
	draw_number(sounds_finished, {480, 225}, k2.LIGHT_GREEN)

	// === SPATIAL AUDIO DEMO ===
	k2.draw_text("Spatial Audio (WASD to move listener, F to play):", {50, 390}, 18, k2.LIGHT_BLUE)
	k2.draw_rect({50, 415, 700, 220}, {40, 50, 70, 255})
	k2.draw_rect_outline({50, 415, 700, 220}, 2, k2.GRAY)

	// Draw spatial source position
	k2.draw_circle(spatial_source_pos, 12, k2.RED)
	k2.draw_text("SRC", {spatial_source_pos.x - 12, spatial_source_pos.y - 30}, 14, k2.RED)

	// Draw listener position
	k2.draw_circle(listener_pos, 12, k2.GREEN)
	k2.draw_text("YOU", {listener_pos.x - 12, listener_pos.y - 30}, 14, k2.GREEN)

	// Distance rings around source (min and max distance)
	draw_circle_outline(spatial_source_pos, 50, {100, 100, 100, 255})
	draw_circle_outline(spatial_source_pos, 300, {60, 60, 60, 255})

	// Instructions
	k2.draw_text("Inner ring = full volume, Outer ring = silent", {400, 430}, 14, k2.GRAY)

	k2.present()
}

shutdown :: proc() {
	k2.stop_audio(music_instance)
	k2.destroy_audio(music_source)
	k2.destroy_audio(click_source)
	k2.destroy_audio_bus(music_bus)
	k2.destroy_audio_bus(sfx_bus)
	k2.shutdown()
}

// Callback when sound finishes playing
on_sound_end :: proc(instance: k2.Audio_Instance, user_data: rawptr) {
	counter := cast(^int)user_data
	counter^ += 1
}

// Helper: Draw bus control with selection indicator
draw_bus_control :: proc(
	label: string,
	bus: k2.Audio_Bus,
	volume: f32,
	pos: k2.Vec2,
	selected: bool,
) {
	selector_color: k2.Color = selected ? k2.YELLOW : k2.DARK_GRAY
	k2.draw_text(selected ? ">" : " ", {pos.x - 15, pos.y}, 16, selector_color)

	label_color: k2.Color = selected ? k2.WHITE : k2.GRAY
	bar_color: k2.Color = selected ? k2.GREEN : {100, 150, 100, 255}
	draw_progress_bar(label, volume / 1.5, pos, 85, label_color, bar_color)

	// Muted indicator
	if k2.is_audio_bus_muted(bus) {
		k2.draw_text("MUTED", {pos.x + 85 + 100 + 10, pos.y}, 14, k2.RED)
	}
}

// Helper: Draw a horizontal progress bar
draw_progress_bar :: proc(
	label: string,
	value: f32,
	pos: k2.Vec2,
	label_width: f32 = 60,
	label_color: k2.Color = k2.WHITE,
	bar_color: k2.Color = k2.GREEN,
) {
	k2.draw_text(label, pos, 16, label_color)
	bar_x := pos.x + label_width
	bar_width: f32 = 100
	bar_height: f32 = 14
	k2.draw_rect({bar_x, pos.y, bar_width, bar_height}, k2.DARK_GRAY)
	filled := bar_width * clamp(value, 0, 1)
	if filled > 0 {
		k2.draw_rect({bar_x, pos.y, filled, bar_height}, bar_color)
	}
}

// Helper: Draw a number as text
draw_number :: proc(n: int, pos: k2.Vec2, color: k2.Color) {
	@(static) buf: [16]u8
	i := 0
	num := n
	if num == 0 {
		buf[0] = '0'
		i = 1
	} else {
		if num < 0 {
			buf[i] = '-'
			i += 1
			num = -num
		}
		temp := num
		digit_count := 0
		for temp > 0 {
			digit_count += 1
			temp /= 10
		}
		j := i + digit_count - 1
		for num > 0 {
			buf[j] = u8('0' + num % 10)
			j -= 1
			num /= 10
		}
		i += digit_count
	}
	k2.draw_text(string(buf[:i]), pos, 16, color)
}

// Helper: Draw circle outline
draw_circle_outline :: proc(center: k2.Vec2, radius: f32, color: k2.Color) {
	segments := 32
	for i := 0; i < segments; i += 1 {
		angle1 := f32(i) / f32(segments) * math.TAU
		angle2 := f32(i + 1) / f32(segments) * math.TAU
		p1 := k2.Vec2{center.x + math.cos(angle1) * radius, center.y + math.sin(angle1) * radius}
		p2 := k2.Vec2{center.x + math.cos(angle2) * radius, center.y + math.sin(angle2) * radius}
		k2.draw_line(p1, p2, 1, color)
	}
}
