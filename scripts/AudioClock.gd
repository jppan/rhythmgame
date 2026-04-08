## AudioClock.gd
## Master timing source. Prefer the audio DSP clock when a stream is playing;
## fall back to Time.get_ticks_msec() during testing or before audio starts.
## Always call get_song_position_ms() — never use wall clock directly in game logic.
class_name AudioClock
extends Node

var music_player: AudioStreamPlayer

## Calibration offset in ms. Positive = shift notes earlier (audio is late).
var offset_ms: float = 0.0

var _fallback_start_ticks: int = 0
var _using_fallback: bool = false

## Call this to start the fallback wall-clock timer (used when no audio stream is loaded).
func start_fallback() -> void:
	_using_fallback = true
	_fallback_start_ticks = Time.get_ticks_msec()

## Returns the current song position in milliseconds, audio-clock-anchored.
func get_song_position_ms() -> float:
	if music_player != null and music_player.playing and music_player.stream != null:
		# Godot's authoritative audio-sync pattern:
		#   get_playback_position() = last audio callback position (chunky, ~5-10ms steps)
		#   + get_time_since_last_mix()  = wall time elapsed since that callback (smooth fill)
		#   - get_output_latency()       = subtract hardware buffer depth
		var pos: float = music_player.get_playback_position()
		pos += AudioServer.get_time_since_last_mix()
		pos -= AudioServer.get_output_latency()
		return pos * 1000.0 + offset_ms

	if _using_fallback:
		return float(Time.get_ticks_msec() - _fallback_start_ticks) + offset_ms

	return 0.0

func is_running() -> bool:
	if music_player != null and music_player.playing:
		return true
	return _using_fallback
