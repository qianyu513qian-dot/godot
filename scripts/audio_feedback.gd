extends Node
class_name AudioFeedback

const CUE_FILES: Dictionary = {
	"ui": "res://audio/ui_click.wav",
	"command": "res://audio/command.wav",
	"build": "res://audio/construction.wav",
	"train": "res://audio/training.wav",
	"hit": "res://audio/combat_hit.wav",
	"horde": "res://audio/horde.wav",
	"victory": "res://audio/victory.wav",
	"defeat": "res://audio/defeat.wav",
	"ambience": "res://audio/ambience.wav",
}
const CUE_BUS: Dictionary = {
	"ui": "UI", "command": "UI", "build": "SFX", "train": "SFX",
	"hit": "Combat", "horde": "Combat", "victory": "UI", "defeat": "Combat",
	"ambience": "Music",
}
const MIN_INTERVAL_MS: Dictionary = {
	"ui": 65, "command": 140, "build": 180, "train": 180,
	"hit": 125, "horde": 900, "victory": 1500, "defeat": 1500,
}
const VOICES_PER_CUE: int = 3

var _streams: Dictionary = {}
var _players: Dictionary = {}
var _next_voice: Dictionary = {}
var _last_played_ms: Dictionary = {}
var _ambience_player: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	if DisplayServer.get_name() == "headless":
		print("[AoELite3D] audio buses ready in headless mode; playback players skipped")
		return
	for cue in CUE_FILES:
		var stream: AudioStream = load(str(CUE_FILES[cue]))
		if stream == null:
			push_warning("Audio cue unavailable: %s" % str(CUE_FILES[cue]))
			continue
		if cue == "ambience" and stream is AudioStreamWAV:
			(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		_streams[cue] = stream
		var pool: Array[AudioStreamPlayer] = []
		var voice_count: int = 1 if cue == "ambience" else VOICES_PER_CUE
		for voice_index in voice_count:
			var player := AudioStreamPlayer.new()
			player.name = "%sVoice%d" % [str(cue).capitalize(), voice_index]
			player.bus = str(CUE_BUS.get(cue, "SFX"))
			player.stream = stream
			add_child(player)
			pool.append(player)
			if cue == "ambience":
				_ambience_player = player
		_players[cue] = pool
	print("[AoELite3D] audio feedback ready cues=%d buses=Master,Music,SFX,UI,Combat throttled=true" % _streams.size())

func _ensure_buses() -> void:
	for bus_name in ["Music", "SFX", "UI", "Combat"]:
		var index: int = AudioServer.get_bus_index(bus_name)
		if index < 0:
			AudioServer.add_bus()
			index = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "SFX" if bus_name in ["UI", "Combat"] else "Master")
		AudioServer.set_bus_mute(index, false)

func play_cue(cue: String) -> void:
	# Scene reloads can finish while a UI signal is still being emitted. Do not
	# try to play through pooled voices that belonged to the freed scene.
	if not is_inside_tree() or not _players.has(cue) or cue == "ambience":
		return
	var now: int = Time.get_ticks_msec()
	var last: int = int(_last_played_ms.get(cue, -1000000))
	if now - last < int(MIN_INTERVAL_MS.get(cue, 100)):
		return
	_last_played_ms[cue] = now
	var pool: Array = _players[cue]
	if pool.is_empty():
		return
	var voice_index: int = int(_next_voice.get(cue, 0)) % pool.size()
	_next_voice[cue] = voice_index + 1
	var player: AudioStreamPlayer = pool[voice_index]
	if not is_instance_valid(player) or not player.is_inside_tree():
		return
	player.stop()
	if not player.is_inside_tree():
		return
	player.play()

func start_ambience() -> void:
	if is_inside_tree() and is_instance_valid(_ambience_player) and _ambience_player.is_inside_tree() and not _ambience_player.playing:
		_ambience_player.play()

func stop_ambience() -> void:
	if is_inside_tree() and is_instance_valid(_ambience_player) and _ambience_player.is_inside_tree():
		_ambience_player.stop()
