#+vet explicit-allocators

package karl2d

when ODIN_OS == .Windows || ODIN_OS == .Linux || ODIN_OS == .Darwin {
	AUDIO_INTERFACE :: AUDIO_INTERFACE_MINIAUDIO
} else when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
	AUDIO_INTERFACE :: AUDIO_INTERFACE_WEBAUDIO
} else {
	AUDIO_INTERFACE :: AUDIO_INTERFACE_NIL
}
