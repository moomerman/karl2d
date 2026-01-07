// Web Audio API helpers for Karl2D WASM builds
// This file provides audio functionality that can be called from Odin/WASM

const karl2dAudio = {
  audioContext: null,
  masterGain: null,
  soundGain: null,
  musicGain: null,
  currentMusic: null,
  currentMusicSource: null,
  initialized: false,

  // Pre-loaded sounds storage (handle -> AudioBuffer)
  loadedSounds: new Map(),
  nextSoundHandle: 1,

  // Initialize the audio system
  init: function () {
    if (this.initialized) return true

    try {
      this.audioContext = new (window.AudioContext ||
        window.webkitAudioContext)()

      // Create gain nodes for volume control
      this.masterGain = this.audioContext.createGain()
      this.masterGain.connect(this.audioContext.destination)

      this.soundGain = this.audioContext.createGain()
      this.soundGain.connect(this.masterGain)

      this.musicGain = this.audioContext.createGain()
      this.musicGain.connect(this.masterGain)

      this.initialized = true

      // Resume audio context on user interaction (required by browsers)
      const resumeAudio = () => {
        if (this.audioContext.state === "suspended") {
          this.audioContext.resume()
        }
      }
      document.addEventListener("click", resumeAudio, { once: false })
      document.addEventListener("keydown", resumeAudio, { once: false })
      document.addEventListener("touchstart", resumeAudio, { once: false })

      return true
    } catch (e) {
      console.error("Failed to initialize Web Audio:", e)
      return false
    }
  },

  // Shutdown the audio system
  shutdown: function () {
    if (!this.initialized) return

    this.stopMusic()
    this.loadedSounds.clear()
    this.nextSoundHandle = 1

    if (this.audioContext) {
      this.audioContext.close()
      this.audioContext = null
    }

    this.initialized = false
  },

  // Decode audio data from a Uint8Array
  decodeAudioData: async function (data) {
    if (!this.initialized) return null

    try {
      // Create a copy of the data as an ArrayBuffer
      const arrayBuffer = data.buffer.slice(
        data.byteOffset,
        data.byteOffset + data.byteLength,
      )
      const audioBuffer = await this.audioContext.decodeAudioData(arrayBuffer)
      return audioBuffer
    } catch (e) {
      console.error("Failed to decode audio data:", e)
      return null
    }
  },

  // Load a sound from bytes - decodes once, returns handle for playback
  loadSound: async function (data) {
    if (!this.initialized) return 0

    // Resume context if suspended
    if (this.audioContext.state === "suspended") {
      await this.audioContext.resume()
    }

    try {
      const audioBuffer = await this.decodeAudioData(data)
      if (!audioBuffer) return 0

      const handle = this.nextSoundHandle++
      this.loadedSounds.set(handle, audioBuffer)
      return handle
    } catch (e) {
      console.error("Failed to load sound:", e)
      return 0
    }
  },

  // Destroy a loaded sound and free its resources
  destroySound: function (handle) {
    this.loadedSounds.delete(handle)
  },

  // Play a pre-loaded sound by handle (instant, no decode needed)
  playSound: function (handle) {
    if (!this.initialized) return false

    const audioBuffer = this.loadedSounds.get(handle)
    if (!audioBuffer) {
      console.error("Sound handle not found:", handle)
      return false
    }

    // Resume context if suspended
    if (this.audioContext.state === "suspended") {
      this.audioContext.resume()
    }

    try {
      const source = this.audioContext.createBufferSource()
      source.buffer = audioBuffer
      source.connect(this.soundGain)
      source.start(0)
      return true
    } catch (e) {
      console.error("Failed to play sound:", e)
      return false
    }
  },

  // Play music (single track, can loop)
  playMusic: async function (data, loop, delaySeconds) {
    if (!this.initialized) return false

    // Resume context if suspended
    if (this.audioContext.state === "suspended") {
      await this.audioContext.resume()
    }

    // Stop any currently playing music
    this.stopMusic()

    try {
      const audioBuffer = await this.decodeAudioData(data)
      if (!audioBuffer) return false

      this.currentMusic = audioBuffer
      this.currentMusicSource = this.audioContext.createBufferSource()
      this.currentMusicSource.buffer = audioBuffer
      this.currentMusicSource.loop = loop
      this.currentMusicSource.connect(this.musicGain)

      const startTime = this.audioContext.currentTime + (delaySeconds || 0)
      this.currentMusicSource.start(startTime)

      // Clean up when music ends (if not looping)
      this.currentMusicSource.onended = () => {
        if (!this.currentMusicSource?.loop) {
          this.currentMusic = null
          this.currentMusicSource = null
        }
      }

      return true
    } catch (e) {
      console.error("Failed to play music:", e)
      return false
    }
  },

  // Stop the currently playing music
  stopMusic: function () {
    if (this.currentMusicSource) {
      try {
        this.currentMusicSource.stop()
      } catch (e) {
        // Ignore errors if already stopped
      }
      this.currentMusicSource = null
    }
    this.currentMusic = null
  },

  // Check if music is currently playing
  isMusicPlaying: function () {
    if (!this.currentMusicSource) return false

    // Check if the audio context is running and we have an active source
    return (
      this.audioContext &&
      this.audioContext.state === "running" &&
      this.currentMusicSource !== null
    )
  },

  // Set master volume (0.0 to 1.0)
  setMasterVolume: function (volume) {
    if (!this.initialized || !this.masterGain) return
    this.masterGain.gain.value = Math.max(0, Math.min(1, volume))
  },

  // Set sound effects volume (0.0 to 1.0)
  setSoundVolume: function (volume) {
    if (!this.initialized || !this.soundGain) return
    this.soundGain.gain.value = Math.max(0, Math.min(1, volume))
  },

  // Set music volume (0.0 to 1.0)
  setMusicVolume: function (volume) {
    if (!this.initialized || !this.musicGain) return
    this.musicGain.gain.value = Math.max(0, Math.min(1, volume))
  },
}

// Make it globally available
window.karl2dAudio = karl2dAudio
