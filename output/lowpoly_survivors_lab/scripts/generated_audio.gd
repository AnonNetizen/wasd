class_name GeneratedLabAudio
extends Node
## Small deterministic synthesized cues. No external audio files are used.

const MIX_RATE: int = 22_050
const PLAYER_COUNT: int = 8

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_streams = {
		&"laser": _make_tone(760.0, 310.0, 0.09, 0.26, 0.18),
		&"hit": _make_tone(180.0, 92.0, 0.075, 0.19, 0.46),
		&"upgrade": _make_tone(420.0, 980.0, 0.34, 0.28, 0.08),
		&"alarm": _make_tone(540.0, 330.0, 0.62, 0.25, 0.12),
		&"victory": _make_tone(480.0, 1_200.0, 0.72, 0.30, 0.04),
		&"defeat": _make_tone(300.0, 72.0, 0.78, 0.27, 0.20),
		&"click": _make_tone(620.0, 520.0, 0.045, 0.13, 0.04),
	}
	for index in range(PLAYER_COUNT):
		var player := AudioStreamPlayer.new()
		player.name = "CuePlayer%d" % (index + 1)
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_players.append(player)


func play_cue(cue: StringName) -> void:
	if not _streams.has(cue):
		return
	var player := _available_player()
	player.stream = _streams[cue] as AudioStream
	player.play()


func _available_player() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	return _players.front()


func _make_tone(
	start_frequency: float,
	end_frequency: float,
	duration: float,
	volume: float,
	texture: float
) -> AudioStreamWAV:
	var sample_count: int = ceili(duration * float(MIX_RATE))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for index in range(sample_count):
		var progress := float(index) / maxf(1.0, float(sample_count - 1))
		var frequency := lerpf(start_frequency, end_frequency, progress)
		phase += TAU * frequency / float(MIX_RATE)
		var attack := clampf(progress / 0.045, 0.0, 1.0)
		var release := pow(1.0 - progress, 1.65)
		var harmonic := sin(phase * 2.07 + sin(progress * 31.0) * 0.12)
		var wave := lerpf(sin(phase), harmonic, texture)
		var sample := clampi(roundi(wave * attack * release * volume * 32_767.0), -32_767, 32_767)
		data.encode_s16(index * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
