extends Node
## 音效播放器（自动加载）：预加载 assets/sfx 下的 WAV，Sfx.play("名字") 即可。

const SFX_NAMES := ["splash", "checkpoint", "rescue", "rewind", "card", "drown"]

var _players: Dictionary = {}  # name -> Array[AudioStreamPlayer]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for sfx_name in SFX_NAMES:
		var path := "res://assets/sfx/%s.wav" % sfx_name
		if not ResourceLoader.exists(path):
			continue
		var stream: AudioStream = load(path)
		var pool: Array[AudioStreamPlayer] = []
		for i in 3:
			var p := AudioStreamPlayer.new()
			p.stream = stream
			p.volume_db = -6.0
			add_child(p)
			pool.append(p)
		_players[sfx_name] = pool

func play(sfx_name: String) -> void:
	var pool: Array = _players.get(sfx_name, [])
	if pool.is_empty():
		return
	for p in pool:
		if not p.playing:
			p.play()
			return
	pool[0].play()
