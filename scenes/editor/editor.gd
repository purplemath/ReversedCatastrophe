extends Node2D
## 游戏内置地图编辑器：编辑墙体/装饰/文字/木箱/出生点/救援区与水面高度，
## 保存为 JSON（user://custom_level.json），可载入内置关卡微调，可一键试玩。

const LEVEL_PATH := "user://custom_level.json"
const GRID := 20.0
const WORLD := Rect2(0, 0, 4800, 1600)

const TOOLS := [
	["wall", "墙壁"], ["deco", "装饰"], ["crate", "木箱"], ["platform", "平台"],
	["player", "玩家点"], ["survivor", "幸存者"], ["text", "文字"], ["raft", "救援区"], ["delete", "删除"],
]

var level := {}
var tool := "wall"
var color_idx := 0

var cam: Camera2D
var content: Node2D
var ghost: ColorRect
var _drag_anchor := Vector2.ZERO
var _dragging := false
var _status: Label
var _text_input: LineEdit
var _water_spin: SpinBox

func _ready() -> void:
	cam = Camera2D.new()
	cam.position = Vector2(1600, 800)
	cam.zoom = Vector2(0.6, 0.6)
	add_child(cam)
	content = Node2D.new()
	add_child(content)
	ghost = ColorRect.new()
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.visible = false
	content.add_child(ghost)
	_build_ui()
	_load_level_file()  # 无存档时载入内置关卡
	_rebuild()

func _process(delta: float) -> void:
	var pan := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down"))
	cam.position += pan * 900.0 * delta / cam.zoom.x
	if tool in ["wall", "deco", "raft", "platform"] and not _dragging:
		var m := _snap(get_global_mouse_position())
		ghost.position = m
		ghost.size = Vector2(GRID, GRID)
		ghost.color = _tool_color(0.55)
		ghost.visible = WORLD.has_point(m)
	queue_redraw()

func _draw() -> void:
	var view := Rect2(cam.get_screen_center_position() - get_viewport_rect().size / cam.zoom / 2.0,
			get_viewport_rect().size / cam.zoom)
	var grid_color := Color(1, 1, 1, 0.10)
	var x := floorf(view.position.x / 100.0) * 100.0
	while x <= view.end.x:
		if x >= WORLD.position.x and x <= WORLD.end.x:
			draw_line(Vector2(x, maxf(view.position.y, WORLD.position.y)),
					Vector2(x, minf(view.end.y, WORLD.end.y)), grid_color)
		x += 100.0
	var y := floorf(view.position.y / 100.0) * 100.0
	while y <= view.end.y:
		if y >= WORLD.position.y and y <= WORLD.end.y:
			draw_line(Vector2(maxf(view.position.x, WORLD.position.x), y),
					Vector2(minf(view.end.x, WORLD.end.x), y), grid_color)
		y += 100.0
	draw_rect(WORLD, Color(1, 0.9, 0.5, 0.8), false, 2.0)
	var wy := float(level.get("water_y", 520.0))
	draw_line(Vector2(0, wy), Vector2(WORLD.end.x, wy), Color(0.3, 0.6, 1.0, 0.9), 2.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			cam.zoom = (cam.zoom * 1.1).clamp(Vector2(0.2, 0.2), Vector2(3, 3))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			cam.zoom = (cam.zoom / 1.1).clamp(Vector2(0.2, 0.2), Vector2(3, 3))
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press()
			else:
				_release()

func _press() -> void:
	var m := _snap(get_global_mouse_position())
	match tool:
		"wall", "deco", "raft", "platform":
			_drag_anchor = m
			_dragging = true
			ghost.position = m
			ghost.size = Vector2.ZERO
			ghost.color = _tool_color(0.4)
			ghost.visible = true
		"crate":
			level["crates"].append({"x": m.x, "y": m.y})
			_rebuild()
		"player":
			level["player_spawn"] = {"x": m.x, "y": m.y}
			_rebuild()
		"survivor":
			level["survivors"].append({"x": m.x, "y": m.y})
			_rebuild()
		"text":
			var t := _text_input.text.strip_edges()
			if t.is_empty():
				t = "标记"
				_text_input.text = t
			level["texts"].append({"x": m.x, "y": m.y, "t": t})
			_rebuild()
		"delete":
			_delete_at()

func _release() -> void:
	if not _dragging:
		return
	_dragging = false
	ghost.visible = false
	var m := _snap(get_global_mouse_position())
	var rect := Rect2(minf(_drag_anchor.x, m.x), minf(_drag_anchor.y, m.y),
			absf(m.x - _drag_anchor.x), absf(m.y - _drag_anchor.y))
	if rect.size.x < GRID or rect.size.y < GRID:
		# 平台工具用两点距离判断（水平往返可以拖得很扁）
		if not (tool == "platform" and rect.size.x >= GRID * 4.0):
			return
	if tool == "raft":
		level["raft_zone"] = {"x": rect.position.x, "y": rect.position.y,
				"w": rect.size.x, "h": rect.size.y}
	elif tool == "platform":
		level["platforms"].append({"ax": _drag_anchor.x, "ay": _drag_anchor.y,
				"bx": m.x, "by": m.y, "speed": 70.0})
	elif tool == "deco":
		var d := {"x": rect.position.x, "y": rect.position.y,
				"w": rect.size.x, "h": rect.size.y, "c": color_idx}
		if color_idx == 8:
			d["grad"] = "v"
		level["decos"].append(d)
	else:
		level["walls"].append({"x": rect.position.x, "y": rect.position.y,
				"w": rect.size.x, "h": rect.size.y, "c": color_idx})
	_rebuild()

func _delete_at() -> void:
	var pt := get_global_mouse_position()
	for i in range(level["walls"].size() - 1, -1, -1):
		var w = level["walls"][i]
		if Rect2(w.x, w.y, w.w, w.h).has_point(pt):
			level["walls"].remove_at(i)
			_rebuild()
			return
	for i in range(level["decos"].size() - 1, -1, -1):
		var d = level["decos"][i]
		if Rect2(d.x, d.y, d.w, d.h).has_point(pt):
			level["decos"].remove_at(i)
			_rebuild()
			return
	for i in range(level["crates"].size() - 1, -1, -1):
		var c = level["crates"][i]
		if Vector2(c.x, c.y).distance_to(pt) < 48.0:
			level["crates"].remove_at(i)
			_rebuild()
			return
	for i in range(level["platforms"].size() - 1, -1, -1):
		var pf = level["platforms"][i]
		if Vector2(pf.ax, pf.ay).distance_to(pt) < 56.0 or Vector2(pf.bx, pf.by).distance_to(pt) < 56.0:
			level["platforms"].remove_at(i)
			_rebuild()
			return
	for i in range(level["survivors"].size() - 1, -1, -1):
		var sv = level["survivors"][i]
		if Vector2(sv.x, sv.y).distance_to(pt) < 48.0:
			level["survivors"].remove_at(i)
			_rebuild()
			return
	for i in range(level["texts"].size() - 1, -1, -1):
		var t = level["texts"][i]
		if Vector2(t.x, t.y).distance_to(pt) < 80.0:
			level["texts"].remove_at(i)
			_rebuild()
			return

# ---------- 存档 ----------

func _save_level() -> void:
	var f := FileAccess.open(LEVEL_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(level, "\t"))
	_set_status("已保存 → " + LEVEL_PATH)

func _load_level_file() -> void:
	if FileAccess.file_exists(LEVEL_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(LEVEL_PATH))
		if parsed is Dictionary and not parsed.is_empty():
			level = _normalized(parsed)
			_set_status("已读取存档")
			_sync_water_spin()
			return
	level = Town.builtin_layout()
	_set_status("已载入内置关卡")
	_sync_water_spin()

func _load_builtin() -> void:
	level = Town.builtin_layout()
	_sync_water_spin()
	_rebuild()
	_set_status("已载入内置关卡")

func _load_saved() -> void:
	_load_level_file()
	_rebuild()

func _normalized(d: Dictionary) -> Dictionary:
	for key in ["walls", "decos", "texts", "crates", "platforms", "survivors"]:
		if not d.has(key):
			d[key] = []
	if d["survivors"].is_empty() and d.has("survivor_spawn"):
		d["survivors"] = [d["survivor_spawn"]]  # 兼容旧版单幸存者存档
	if not d.has("player_spawn"):
		d["player_spawn"] = {"x": 370.0, "y": 1240.0}
	if not d.has("raft_zone"):
		d["raft_zone"] = {"x": 4140.0, "y": 360.0, "w": 480.0, "h": 300.0}
	if not d.has("water_y"):
		d["water_y"] = 520.0
	return d

func _on_water_changed(v: float) -> void:
	if level.is_empty():
		return
	level["water_y"] = v
	_rebuild()

func _sync_water_spin() -> void:
	_water_spin.set_value_no_signal(float(level.get("water_y", 520.0)))

func _test_run() -> void:
	GameState.custom_level = level
	GameState.testing_level = true
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _back_to_title() -> void:
	GameState.testing_level = false
	GameState.custom_level = {}
	get_tree().change_scene_to_file("res://scenes/title_screen/title_screen.tscn")

# ---------- 渲染 ----------

func _rebuild() -> void:
	if level.is_empty():
		return
	for child in content.get_children():
		if child != ghost:
			child.queue_free()
	for w in level["walls"]:
		content.add_child(_rect_visual(Rect2(w.x, w.y, w.w, w.h),
				Town.PALETTE[int(w.c) % Town.PALETTE.size()], 1.0))
	for d in level["decos"]:
		content.add_child(_rect_visual(Rect2(d.x, d.y, d.w, d.h),
				Town.PALETTE[int(d.c) % Town.PALETTE.size()], 0.85))
	for c in level["crates"]:
		content.add_child(_rect_visual(Rect2(c.x - 32.0, c.y - 32.0, 64.0, 64.0),
				Color(0.62, 0.45, 0.28), 1.0))
	for pf in level["platforms"]:
		# 平台本体（A 点）+ 巡逻线 A→B
		content.add_child(_rect_visual(Rect2(pf.ax - 60.0, pf.ay - 13.0, 120.0, 26.0),
				Color(0.55, 0.42, 0.30), 1.0))
		var pdx := float(pf.bx) - float(pf.ax)
		var pdy := float(pf.by) - float(pf.ay)
		var plen := Vector2(pdx, pdy).length()
		if plen > 1.0:
			var pline := _rect_visual(Rect2(pf.ax, pf.ay - 2.0, plen, 4.0),
					Color(1.0, 0.9, 0.5, 0.7), 1.0)
			pline.rotation = Vector2(pdx, pdy).angle()
			content.add_child(pline)
	for t in level["texts"]:
		var l := Label.new()
		l.text = str(t.t)
		l.position = Vector2(t.x, t.y)
		l.add_theme_font_size_override("font_size", 28)
		l.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", 8)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(l)
	var ps: Dictionary = level["player_spawn"]
	content.add_child(_marker(Vector2(ps.x, ps.y), Color(0.4, 0.9, 1.0), "玩家"))
	for sv in level["survivors"]:
		content.add_child(_marker(Vector2(sv.x, sv.y), Color(0.45, 0.78, 0.55), "幸存者"))
	var rz: Dictionary = level["raft_zone"]
	content.add_child(_rect_visual(Rect2(rz.x, rz.y, rz.w, rz.h), Color(1.0, 0.9, 0.3, 0.25), 1.0))
	var wy := float(level["water_y"])
	content.add_child(_rect_visual(Rect2(0, wy, WORLD.size.x, WORLD.end.y - wy),
			Color(0.18, 0.42, 0.68, 0.25), 1.0))
	content.move_child(ghost, content.get_child_count() - 1)
	_set_status("")

func _rect_visual(rect: Rect2, color: Color, a: float) -> ColorRect:
	var r := ColorRect.new()
	r.position = rect.position
	r.size = rect.size
	r.color = Color(color.r, color.g, color.b, color.a * a)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _marker(pos: Vector2, color: Color, text: String) -> Node2D:
	var n := Node2D.new()
	n.position = pos
	var r := ColorRect.new()
	r.position = Vector2(-14, -28)
	r.size = Vector2(28, 56)
	r.color = Color(color.r, color.g, color.b, 0.9)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.add_child(r)
	var l := Label.new()
	l.text = text
	l.position = Vector2(-20, -56)
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.add_child(l)
	return n

func _snap(p: Vector2) -> Vector2:
	return Vector2(snappedf(p.x, GRID), snappedf(p.y, GRID))

func _tool_color(a: float) -> Color:
	var c := Town.PALETTE[color_idx % Town.PALETTE.size()]
	return Color(c.r, c.g, c.b, a)

func _set_status(extra: String) -> void:
	if _status == null:
		return
	_status.text = "墙 %d · 饰 %d · 平台 %d · 幸存者 %d · 箱 %d  |  %s" % [level.get("walls", []).size(),
			level.get("decos", []).size(), level.get("platforms", []).size(),
			level.get("survivors", []).size(), level.get("crates", []).size(), extra]

# ---------- UI ----------

func _on_tool_selected(on: bool, tool_id: String) -> void:
	if on:
		tool = tool_id

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.12, 0.9)
	sb.border_color = Color(0.55, 0.75, 1.0, 0.5)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", sb)
	ui.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	# 工具行
	var tools_row := HBoxContainer.new()
	tools_row.add_theme_constant_override("separation", 6)
	vb.add_child(tools_row)
	var group := ButtonGroup.new()
	for t in TOOLS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.button_group = group
		b.add_theme_font_size_override("font_size", 14)
		b.toggled.connect(_on_tool_selected.bind(t[0]))
		if t[0] == "wall":
			b.set_pressed_no_signal(true)
		tools_row.add_child(b)

	# 调色板行
	var pal_row := HBoxContainer.new()
	pal_row.add_theme_constant_override("separation", 4)
	vb.add_child(pal_row)
	for i in Town.PALETTE.size():
		var pb := Button.new()
		pb.custom_minimum_size = Vector2(30, 26)
		pb.tooltip_text = "颜色 %d" % i
		var st := StyleBoxFlat.new()
		st.bg_color = Town.PALETTE[i]
		st.set_corner_radius_all(4)
		pb.add_theme_stylebox_override("normal", st)
		pb.add_theme_stylebox_override("hover", st)
		pb.add_theme_stylebox_override("pressed", st)
		pb.pressed.connect(_on_palette_selected.bind(i))
		pal_row.add_child(pb)

	# 参数行：水面高度 + 文字内容
	var param_row := HBoxContainer.new()
	param_row.add_theme_constant_override("separation", 8)
	vb.add_child(param_row)
	var wl := Label.new()
	wl.text = "水面Y"
	wl.add_theme_font_size_override("font_size", 14)
	param_row.add_child(wl)
	_water_spin = SpinBox.new()
	_water_spin.min_value = 100
	_water_spin.max_value = 1400
	_water_spin.step = 20
	_water_spin.value = 520
	_water_spin.value_changed.connect(_on_water_changed)
	param_row.add_child(_water_spin)
	var tl := Label.new()
	tl.text = " 文字"
	tl.add_theme_font_size_override("font_size", 14)
	param_row.add_child(tl)
	_text_input = LineEdit.new()
	_text_input.custom_minimum_size = Vector2(140, 28)
	_text_input.placeholder_text = "文字内容"
	_text_input.text = "标记"
	param_row.add_child(_text_input)

	# 操作行
	var act_row := HBoxContainer.new()
	act_row.add_theme_constant_override("separation", 6)
	vb.add_child(act_row)
	var actions: Array = [
		["载入内置", _load_builtin], ["读取存档", _load_saved],
		["保存", _save_level], ["试玩", _test_run], ["返回标题", _back_to_title],
	]
	for a in actions:
		var ab := Button.new()
		ab.text = a[0]
		ab.add_theme_font_size_override("font_size", 14)
		ab.pressed.connect(a[1])
		act_row.add_child(ab)

	# 状态与提示
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.modulate = Color(1, 1, 1, 0.8)
	vb.add_child(_status)
	var hint := Label.new()
	hint.text = "左键 放置/拖拽 · 删除工具点击 · WASD/方向键 平移 · 滚轮 缩放 · 网格 20px"
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(1, 1, 1, 0.5)
	vb.add_child(hint)

func _on_palette_selected(idx: int) -> void:
	color_idx = idx
