class_name ProcAudio
extends Node

## Synthesised placeholder audio, generated sample by sample.
##
## No WAV or OGG files are needed to run the project. Every cue is a short
## additive burst pushed into an AudioStreamGenerator. To swap in real audio
## later, replace the body of a `play_*` method with a stream play call — the
## call sites elsewhere do not change.

const SAMPLE_RATE := 22050.0
const BUFFER_LENGTH := 0.4

enum Wave { SINE, SQUARE, TRIANGLE }

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback


func _ready() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = SAMPLE_RATE
	generator.buffer_length = BUFFER_LENGTH

	_player = AudioStreamPlayer.new()
	_player.stream = generator
	_player.volume_db = -12.0
	add_child(_player)
	_player.play()

	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback


## A short "speech blip", one per line of dialogue, in the Animal Crossing
## tradition. Pitch is derived from the speaker's id so each character has a
## recognisable voice without any recorded audio.
func play_speech_blip(speaker_id: StringName) -> void:
	var pitch: float = 180.0 + float(abs(str(speaker_id).hash()) % 220)
	_push_tone(pitch, 0.07, Wave.SQUARE, 0.18)


## Confirmation click for UI interactions.
func play_click() -> void:
	_push_tone(880.0, 0.03, Wave.SQUARE, 0.12)


## Marks the passing of an in-game hour.
func play_hour_chime() -> void:
	_push_tone(523.25, 0.16, Wave.SINE, 0.16)


## Marks a new day, a lower and longer version of the hour chime.
func play_day_chime() -> void:
	_push_tone(261.63, 0.34, Wave.TRIANGLE, 0.22)


## Warns that someone has broken from their routine to hunt another NPC.
func play_alarm() -> void:
	_push_tone(140.0, 0.22, Wave.TRIANGLE, 0.2)


## Writes one enveloped tone into the generator buffer.
##
## The envelope matters: a raw sine that starts and stops at full amplitude
## clicks audibly at both ends.
func _push_tone(frequency: float, duration: float, wave: Wave, volume: float) -> void:
	if _playback == null:
		return

	var total: int = int(SAMPLE_RATE * duration)
	var available: int = _playback.get_frames_available()
	if available <= 0:
		return
	total = mini(total, available)

	for i in total:
		var t: float = float(i) / SAMPLE_RATE
		var phase: float = fmod(frequency * t, 1.0)
		var sample: float = _wave_sample(wave, phase)

		# Fast attack, exponential decay.
		var progress: float = float(i) / float(maxi(total, 1))
		var envelope: float = minf(progress * 12.0, 1.0) * pow(1.0 - progress, 1.6)

		var value: float = sample * envelope * volume
		_playback.push_frame(Vector2(value, value))


static func _wave_sample(wave: Wave, phase: float) -> float:
	match wave:
		Wave.SQUARE:
			return 1.0 if phase < 0.5 else -1.0
		Wave.TRIANGLE:
			return 4.0 * absf(phase - 0.5) - 1.0
		_:
			return sin(phase * TAU)
