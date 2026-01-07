package karl2d

CONFIG_AUDIO_NAME :: #config(KARL2D_AUDIO, "")

when ODIN_OS == .Windows {
	DEFAULT_AUDIO_NAME :: "miniaudio"
	AVAILABLE_AUDIOS :: "miniaudio, nil"
} else when ODIN_OS == .Linux {
	DEFAULT_AUDIO_NAME :: "miniaudio"
	AVAILABLE_AUDIOS :: "miniaudio, nil"
} else when ODIN_OS == .Darwin {
	DEFAULT_AUDIO_NAME :: "miniaudio"
	AVAILABLE_AUDIOS :: "miniaudio, nil"
} else when ODIN_OS == .JS {
	DEFAULT_AUDIO_NAME :: "webaudio"
	AVAILABLE_AUDIOS :: "webaudio, nil"
} else {
	DEFAULT_AUDIO_NAME :: "nil"
	AVAILABLE_AUDIOS :: "nil"
}

when CONFIG_AUDIO_NAME == "" {
	AUDIO_NAME :: DEFAULT_AUDIO_NAME
} else {
	AUDIO_NAME :: CONFIG_AUDIO_NAME
}

when AUDIO_NAME == "miniaudio" {
	AUDIO :: AUDIO_MINIAUDIO
} else when AUDIO_NAME == "webaudio" {
	AUDIO :: AUDIO_WEBAUDIO
} else when AUDIO_NAME == "nil" {
	AUDIO :: AUDIO_NIL
} else {
	#panic(
		"'" +
		AUDIO_NAME +
		"' is not a valid value for 'KARL2D_AUDIO' on Operating System " +
		ODIN_OS_STRING +
		". Available backends are: " +
		AVAILABLE_AUDIOS,
	)
}
