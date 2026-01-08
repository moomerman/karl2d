// This is a port of https://www.raylib.com/examples/audio/loader.html?name=audio_sound_loading

package karl2d_audio_sound_loading

import k2 "../../.."

main :: proc() {
	k2.init(800, 450, "audio example - music stream (raylib port)")

	volume: f32 = 0.5
	pan: f32 = 0.0
	time_played: f32 = 0.1 // TODO: implement time played
	pause: bool

	k2.set_music_volume(volume)
	k2.set_music_pan(pan)
	k2.play_music("country.mp3")

	for k2.update() {
		if k2.key_went_down(.Space) {
			k2.stop_music()
			k2.play_music("country.mp3")
		}
		if k2.key_went_down(.P) {
			pause = !pause
			if pause {
				k2.pause_music()
			} else {
				k2.resume_music()
			}
		}
		if k2.key_went_down(.Left) {
			pan = max(pan - 0.05, -1.0)
			k2.set_music_pan(pan)
		}
		if k2.key_went_down(.Right) {
			pan = min(pan + 0.05, 1.0)
			k2.set_music_pan(pan)
		}
		if k2.key_went_down(.Up) {
			volume = min(volume + 0.05, 1.0)
			k2.set_music_volume(volume)
		}
		if k2.key_went_down(.Down) {
			volume = max(volume - 0.05, 0.0)
			k2.set_music_volume(volume)
		}

		k2.clear(k2.RL_WHITE)

		k2.draw_text("MUSIC SHOULD BE PLAYING!", {255, 150}, 20, k2.RL_LIGHTGRAY)

		k2.draw_text("LEFT-RIGHT for PAN CONTROL", {320, 74}, 10, k2.RL_DARKBLUE)
		k2.draw_rect({300, 100, 200, 12}, k2.RL_LIGHTGRAY)
		k2.draw_rect_outline({300, 100, 200, 12}, 5, k2.RL_GRAY)
		k2.draw_rect({300 + (pan + 1.0) / 2.0 * 200 - 5, 92, 10, 28}, k2.RL_DARKGRAY)

		k2.draw_rect({200, 200, 400, 12}, k2.RL_LIGHTGRAY)
		k2.draw_rect({200, 200, (time_played * 400.0), 12}, k2.RL_MAROON)
		k2.draw_rect_outline({200, 200, 400, 12}, 5, k2.GRAY)

		k2.draw_text("PRESS SPACE TO RESTART MUSIC", {215, 250}, 20, k2.RL_LIGHTGRAY)
		k2.draw_text("PRESS P TO PAUSE/RESUME MUSIC", {208, 280}, 20, k2.RL_LIGHTGRAY)

		k2.draw_text("UP-DOWN for VOLUME CONTROL", {320, 334}, 10, k2.RL_DARKGREEN)
		k2.draw_rect({300, 360, 200, 12}, k2.RL_LIGHTGRAY)
		k2.draw_rect_outline({300, 360, 200, 12}, 5, k2.RL_GRAY)
		k2.draw_rect({300 + volume * 200 - 5, 352, 10, 28}, k2.RL_DARKGRAY)

		k2.present()
	}

	k2.stop_music()
	k2.shutdown()
}
