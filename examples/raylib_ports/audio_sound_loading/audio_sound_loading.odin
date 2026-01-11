// This is a port of https://www.raylib.com/examples/audio/loader.html?name=audio_sound_loading

package karl2d_audio_sound_loading

import k2 "../../.."

main :: proc() {
	k2.init(800, 450, "audio example - sound loading (raylib port)")

	fx_wav := k2.load_sound("sound.wav")
	fx_ogg := k2.load_sound("target.ogg")

	for k2.update() {
		if k2.key_went_down(.Space) {
			k2.play_sound(fx_wav)
		}
		if k2.key_went_down(.Enter) {
			k2.play_sound(fx_ogg)
		}

		k2.clear(k2.RL_WHITE)

		k2.draw_text("Press SPACE to PLAY the WAV sound!", {200, 180}, 20, k2.RL_LIGHTGRAY)
		k2.draw_text("Press ENTER to PLAY the OGG sound!", {200, 220}, 20, k2.RL_LIGHTGRAY)

		k2.present()
	}

	k2.destroy_sound(fx_wav)
	k2.destroy_sound(fx_ogg)
	k2.shutdown()
}
