extends Node
## 编辑器与关卡数据专项测试（headless 用）。
## 运行：Godot --headless --path . res://test/editor_test.tscn

const TUNNEL_LANE := Rect2(2600, 1000, 700, 300)  # 高楼拱形水道：内部不得有任何墙

func _ready() -> void:
	var layout: Dictionary = Town.builtin_layout()

	# 1) 内置关卡数据规模合理
	if layout.walls.size() < 20:
		push_error("TEST builtin walls too few: %d" % layout.walls.size())
	if layout.platforms.size() < 2:
		push_error("TEST builtin platforms missing")
	if layout.survivors.size() != 2:
		push_error("TEST builtin survivors != 2")
	print("TEST builtin walls=", layout.walls.size(), " decos=", layout.decos.size(),
		" platforms=", layout.platforms.size(), " survivors=", layout.survivors.size())

	# 2) 拱形水道几何断言：泳道内不允许存在任何墙体（防止再次出现封死涵洞）
	for w in layout.walls:
		var wr := Rect2(w.x, w.y, w.w, w.h)
		if wr.intersects(TUNNEL_LANE):
			push_error("TEST wall intersects tunnel lane: " + str(wr))
	print("TEST tunnel lane clear check done")

	# 3) 水道左右开口：x=2600 与 x=3300 两个立面在 y1000..1300 范围内无墙
	for w in layout.walls:
		var wr2 := Rect2(w.x, w.y, w.w, w.h)
		if wr2.position.x < 2600.0 and wr2.end.x > 2600.0 and wr2.position.y < 1300.0 and wr2.end.y > 1000.0:
			push_error("TEST left tunnel face blocked: " + str(wr2))
		if wr2.position.x < 3300.0 and wr2.end.x > 3300.0 and wr2.position.y < 1300.0 and wr2.end.y > 1000.0:
			push_error("TEST right tunnel face blocked: " + str(wr2))
	print("TEST tunnel faces open check done")

	# 4) 编辑器实例化 + 存取回环
	var editor: Node = load("res://scenes/editor/editor.tscn").instantiate()
	add_child(editor)
	var walls0: int = editor.level.walls.size()
	editor.level.walls.append({"x": 100.0, "y": 100.0, "w": 200.0, "h": 80.0, "c": 0})
	editor._save_level()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(editor.LEVEL_PATH))
	if parsed == null or parsed.walls.size() != walls0 + 1:
		push_error("TEST save/parse roundtrip failed")
	else:
		print("TEST save/parse ok, walls=", parsed.walls.size())
	editor._load_level_file()
	if editor.level.walls.size() != walls0 + 1:
		push_error("TEST reload from file failed")
	else:
		print("TEST reload ok")
	# 清理测试存档，避免影响后续运行
	DirAccess.remove_absolute(ProjectSettings.globalize_path(editor.LEVEL_PATH))

	# 5) 自定义关卡应用到 Town：墙/平台/幸存者数量与数据一致
	GameState.custom_level = editor.level
	var town: Town = load("res://scenes/world/town.tscn").instantiate()
	add_child(town)
	var body_count := 0
	var debris_count := 0
	var survivor_count := 0
	for c in town.get_children():
		if c is StaticBody2D and not (c is MovingDebris):  # AnimatableBody2D 继承自 StaticBody2D，需排除
			body_count += 1
		if c is MovingDebris:
			debris_count += 1
		if c is Survivor:
			survivor_count += 1
	if body_count != editor.level.walls.size():
		push_error("TEST town bodies=%d != walls=%d" % [body_count, editor.level.walls.size()])
	if debris_count != editor.level.platforms.size():
		push_error("TEST town debris=%d != platforms=%d" % [debris_count, editor.level.platforms.size()])
	if survivor_count != editor.level.survivors.size():
		push_error("TEST town survivors=%d != data=%d" % [survivor_count, editor.level.survivors.size()])
	print("TEST town applied custom level: bodies=", body_count, " debris=", debris_count,
		" survivors=", survivor_count)
	GameState.custom_level = {}

	print("TEST OK")
	get_tree().quit()
