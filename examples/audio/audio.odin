// Audio example that works on both desktop and WASM.
//
// Uses #load to embed audio files at compile time, which is required for web builds
// and also works on desktop.
//
// Controls:
//   SPACE      - Play sound effect
//   M          - Toggle music on/off
//   Up/Down    - Master volume (±10%)
//   Left/Right - Music volume (±10%)
//   Q/E        - Sound volume (±10%)
//
// Build for desktop: odin run examples/audio
// Build for web: odin run build_web -- examples/audio
package audio

import k2 "../.."

// Embed audio files at compile time
BACKGROUND_MUSIC :: #load("background.mp3")
SOUND_EFFECT :: #load("splat.wav")

// Sound handle for pre-loaded sound effect
splat_sound: k2.Sound

// Volume levels (0.0 to 1.0)
master_volume: f32 = 0.5
music_volume: f32 = 0.5
sound_volume: f32 = 0.5

// Track if music should be playing
music_enabled: bool = true

main :: proc() {
	init()
	for step() {}
	shutdown()
}

init :: proc() {
	k2.init(800, 600, "Audio Example")

	k2.set_master_volume(master_volume)
	k2.set_music_volume(music_volume)
	k2.set_sound_volume(sound_volume)

	splat_sound = k2.load_sound_from_bytes(SOUND_EFFECT)

	k2.play_music_from_bytes(BACKGROUND_MUSIC, loop = true)
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	if k2.key_went_down(.Space) {
		k2.play_sound(splat_sound)
	}

	if k2.key_went_down(.M) {
		music_enabled = !music_enabled
		if music_enabled {
			k2.play_music_from_bytes(BACKGROUND_MUSIC, loop = true)
		} else {
			k2.stop_music()
		}
	}

	// Master volume: Up/Down
	if k2.key_went_down(.Up) {
		master_volume = min(master_volume + 0.1, 1.0)
		k2.set_master_volume(master_volume)
	}
	if k2.key_went_down(.Down) {
		master_volume = max(master_volume - 0.1, 0.0)
		k2.set_master_volume(master_volume)
	}

	// Music volume: Left/Right
	if k2.key_went_down(.Right) {
		music_volume = min(music_volume + 0.1, 1.0)
		k2.set_music_volume(music_volume)
	}
	if k2.key_went_down(.Left) {
		music_volume = max(music_volume - 0.1, 0.0)
		k2.set_music_volume(music_volume)
	}

	// Sound volume: Q/E
	if k2.key_went_down(.E) {
		sound_volume = min(sound_volume + 0.1, 1.0)
		k2.set_sound_volume(sound_volume)
	}
	if k2.key_went_down(.Q) {
		sound_volume = max(sound_volume - 0.1, 0.0)
		k2.set_sound_volume(sound_volume)
	}

	// Draw
	k2.clear(k2.LIGHT_BLUE)

	k2.draw_text("Audio Example", {50, 50}, 48, k2.DARK_BLUE)

	// Controls help
	k2.draw_text("Controls:", {50, 120}, 24, k2.DARK_BLUE)
	k2.draw_text("SPACE - Play sound effect", {70, 150}, 20, k2.DARK_GRAY)
	k2.draw_text("M - Toggle music on/off", {70, 175}, 20, k2.DARK_GRAY)
	k2.draw_text("Up/Down - Master volume", {70, 200}, 20, k2.DARK_GRAY)
	k2.draw_text("Left/Right - Music volume", {70, 225}, 20, k2.DARK_GRAY)
	k2.draw_text("Q/E - Sound volume", {70, 250}, 20, k2.DARK_GRAY)

	// Volume displays using simple bars
	y: f32 = 300
	draw_volume_bar("Master:", master_volume, {50, y})
	draw_volume_bar("Music: ", music_volume, {50, y + 35})
	draw_volume_bar("Sound: ", sound_volume, {50, y + 70})

	// Music status
	if k2.is_music_playing() {
		k2.draw_text("Music: Playing", {50, 420}, 24, k2.DARK_GREEN)
	} else {
		k2.draw_text("Music: Stopped", {50, 420}, 24, k2.ORANGE)
	}

	// Browser autoplay notice (web only)
	when !k2.FILESYSTEM_SUPPORTED {
		k2.draw_text(
			"Click anywhere if audio doesn't start (browser autoplay policy)",
			{50, 460},
			18,
			k2.GRAY,
		)
	}

	k2.present()

	return true
}

// Draw a volume bar with label (no fmt.tprintf to avoid potential WASM issues)
draw_volume_bar :: proc(label: string, volume: f32, pos: k2.Vec2) {
	bar_width: f32 = 200
	bar_height: f32 = 20
	filled_width := bar_width * volume

	// Label
	k2.draw_text(label, pos, 20, k2.DARK_BLUE)

	// Background bar
	bar_x := pos.x + 80
	k2.draw_rect({bar_x, pos.y, bar_width, bar_height}, k2.GRAY)

	// Filled portion
	if filled_width > 0 {
		k2.draw_rect({bar_x, pos.y, filled_width, bar_height}, k2.DARK_GREEN)
	}
}

shutdown :: proc() {
	k2.destroy_sound(splat_sound)
	k2.shutdown()
}
