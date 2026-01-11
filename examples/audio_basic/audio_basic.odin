// A minimal example showing how to load and play audio with Karl2D.
//
// Press SPACE to play a click sound.
//
package karl2d_audio_basic

import k2 "../.."

CLICK_WAV :: #load("click.wav")

sound: k2.Audio_Source

main :: proc() {
	k2.init(800, 600, "Basic Audio Example")
	defer k2.shutdown()

	sound = k2.load_audio_from_bytes(CLICK_WAV)
	defer k2.destroy_audio(sound)

	for k2.update() {
		if k2.key_went_down(.Space) {
			k2.play_audio(sound)
		}

		k2.clear(k2.DARK_BLUE)
		k2.draw_text("Press SPACE to play sound", {50, 50}, 32, k2.WHITE)
		k2.present()
	}
}
