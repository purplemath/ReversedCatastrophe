class_name PauseMenu
extends CanvasLayer
## 暂停菜单（ESC）：继续 / 重新开始 / 返回标题。
## 对白播放或时间回溯进行中不允许暂停。

signal restart_requested
signal title_requested
signal editor_requested

var _root: Control
var _resume_btn: Button
var _active := false

# 防灾图鉴
var _gallery_panel: PanelContainer
var _gallery_list: VBoxContainer
var _gallery_prev_tag: Label
var _gallery_prev_title: Label
var _gallery_prev_lines: VBoxContainer
var _gallery_labels: Array = []
var _gallery_open := false
var _gallery_index := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_build()
	_set_menu_visible(false)

func is_active() -> bool:
	return _active

func _can_pause() -> bool:
	if RewindManager.rewinding:
		return false
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and (hud.is_dialogue_visible() or hud.is_card_visible()):
		return false
	return true

func pause_game() -> void:
	if _active or not _can_pause():
		return
	_active = true
	get_tree().paused = true
	_set_menu_visible(true)
	_resume_btn.grab_focus()

func resume_game() -> void:
	if not _active:
		return
	_active = false
	get_tree().paused = false
	_set_menu_visible(false)

func _unhandled_input(event: InputEvent) -> void:
	if _gallery_open:
		if event.is_action_pressed("ui_cancel"):
			_close_gallery()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_up"):
			_gallery_navigate(-1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_down"):
			_gallery_navigate(1)
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		if _active:
			resume_game()
		else:
			pause_game()
		get_viewport().set_input_as_handled()

func _set_menu_visible(on: bool) -> void:
	_root.visible = on

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(cc)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.12, 0.92)
	sb.border_color = Color(0.55, 0.75, 1.0, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 28.0
	sb.content_margin_right = 28.0
	sb.content_margin_top = 22.0
	sb.content_margin_bottom = 22.0
	panel.add_theme_stylebox_override("panel", sb)
	cc.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "已暂停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	vb.add_child(title)

	var hint := Label.new()
	hint.text = "按 ESC 返回游戏"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(1, 1, 1, 0.5)
	vb.add_child(hint)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
	vb.add_child(spacer)

	_resume_btn = _make_button("继续游戏")
	_resume_btn.pressed.connect(resume_game)
	vb.add_child(_resume_btn)

	var gallery_btn := _make_button("防灾图鉴")
	gallery_btn.pressed.connect(_open_gallery)
	vb.add_child(gallery_btn)

	var restart_btn := _make_button("重新开始")
	restart_btn.pressed.connect(func(): restart_requested.emit())
	vb.add_child(restart_btn)

	var title_btn := _make_button("返回标题")
	title_btn.pressed.connect(func(): title_requested.emit())
	vb.add_child(title_btn)

	if GameState.testing_level:
		var editor_btn := _make_button("返回编辑器")
		editor_btn.pressed.connect(func(): editor_requested.emit())
		vb.add_child(editor_btn)

	_build_gallery()

# ---------- 防灾图鉴 ----------

func gallery_status() -> Dictionary:
	var unlocked := 0
	for c in GameState.all_cards:
		if GameState.is_card_unlocked(str(c.get("id", ""))):
			unlocked += 1
	return {"open": _gallery_open, "total": GameState.all_cards.size(),
			"unlocked": unlocked, "index": _gallery_index}

func _open_gallery() -> void:
	_gallery_open = true
	_gallery_index = 0
	for i in GameState.all_cards.size():
		if GameState.is_card_unlocked(str(GameState.all_cards[i].get("id", ""))):
			_gallery_index = i
			break
	_build_gallery_list()
	_refresh_gallery()
	_gallery_panel.visible = true

func _close_gallery() -> void:
	_gallery_open = false
	_gallery_panel.visible = false

func _gallery_navigate(dir: int) -> void:
	var total := GameState.all_cards.size()
	if total == 0:
		return
	_gallery_index = (_gallery_index + dir + total) % total
	_refresh_gallery()

func _build_gallery_list() -> void:
	for child in _gallery_list.get_children():
		child.queue_free()
	_gallery_labels.clear()
	for c in GameState.all_cards:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 17)
		_gallery_list.add_child(l)
		_gallery_labels.append(l)

func _refresh_gallery() -> void:
	for i in GameState.all_cards.size():
		var card: Dictionary = GameState.all_cards[i]
		var unlocked := GameState.is_card_unlocked(str(card.get("id", "")))
		var l: Label = _gallery_labels[i]
		if i == _gallery_index:
			l.text = ("▶ " if unlocked else "▶ ？？？")
		else:
			l.text = str(card.get("title", "？？？")) if unlocked else "　？？？"
		l.add_theme_color_override("font_color",
				Color(1, 0.95, 0.7) if i == _gallery_index else (Color(0.9, 0.93, 1.0) if unlocked else Color(1, 1, 1, 0.35)))
	var cur: Dictionary = GameState.all_cards[_gallery_index] if GameState.all_cards.size() > 0 else {}
	var cur_unlocked := not cur.is_empty() and GameState.is_card_unlocked(str(cur.get("id", "")))
	for child in _gallery_prev_lines.get_children():
		child.queue_free()
	if cur_unlocked:
		_gallery_prev_tag.text = str(cur.get("tag", "知识"))
		_gallery_prev_title.text = str(cur.get("title", ""))
		for line in cur.get("lines", []):
			var ll := Label.new()
			ll.text = "· " + str(line)
			ll.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
			ll.add_theme_font_size_override("font_size", 15)
			ll.custom_minimum_size = Vector2(340, 0)
			_gallery_prev_lines.add_child(ll)
	else:
		_gallery_prev_tag.text = "未解锁"
		_gallery_prev_title.text = "？？？"
		var hint := Label.new()
		hint.text = "救出幸存者即可解锁新的防灾知识。"
		hint.add_theme_font_size_override("font_size", 15)
		hint.modulate = Color(1, 1, 1, 0.5)
		_gallery_prev_lines.add_child(hint)

func _build_gallery() -> void:
	_gallery_panel = PanelContainer.new()
	_gallery_panel.position = Vector2(280, 130)
	_gallery_panel.size = Vector2(720, 440)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.1, 0.95)
	sb.border_color = Color(0.95, 0.85, 0.5, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 24.0
	sb.content_margin_right = 24.0
	sb.content_margin_top = 20.0
	sb.content_margin_bottom = 16.0
	_gallery_panel.add_theme_stylebox_override("panel", sb)
	_gallery_panel.visible = false
	_root.add_child(_gallery_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_gallery_panel.add_child(vb)
	var title := Label.new()
	title.text = "防灾图鉴"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.98, 0.93, 0.75))
	vb.add_child(title)
	var hint := Label.new()
	hint.text = "↑↓ 选择 · ESC 返回　　每救出一名幸存者解锁一张知识卡"
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(1, 1, 1, 0.5)
	vb.add_child(hint)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(body)

	var list_panel := PanelContainer.new()
	var lsb := StyleBoxFlat.new()
	lsb.bg_color = Color(0.08, 0.1, 0.16, 0.7)
	lsb.set_corner_radius_all(8)
	lsb.content_margin_left = 14.0
	lsb.content_margin_right = 14.0
	lsb.content_margin_top = 12.0
	lsb.content_margin_bottom = 12.0
	list_panel.add_theme_stylebox_override("panel", lsb)
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(list_panel)
	_gallery_list = VBoxContainer.new()
	_gallery_list.add_theme_constant_override("separation", 8)
	list_panel.add_child(_gallery_list)

	var prev_panel := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.08, 0.1, 0.16, 0.7)
	psb.set_corner_radius_all(8)
	psb.content_margin_left = 16.0
	psb.content_margin_right = 16.0
	psb.content_margin_top = 12.0
	psb.content_margin_bottom = 12.0
	prev_panel.add_theme_stylebox_override("panel", psb)
	prev_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prev_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(prev_panel)
	var pvb := VBoxContainer.new()
	pvb.add_theme_constant_override("separation", 10)
	prev_panel.add_child(pvb)
	_gallery_prev_tag = Label.new()
	_gallery_prev_tag.add_theme_font_size_override("font_size", 14)
	_gallery_prev_tag.modulate = Color(1, 1, 1, 0.6)
	pvb.add_child(_gallery_prev_tag)
	_gallery_prev_title = Label.new()
	_gallery_prev_title.add_theme_font_size_override("font_size", 22)
	_gallery_prev_title.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	pvb.add_child(_gallery_prev_title)
	_gallery_prev_lines = VBoxContainer.new()
	_gallery_prev_lines.add_theme_constant_override("separation", 12)
	_gallery_prev_lines.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pvb.add_child(_gallery_prev_lines)

func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 46)
	b.focus_mode = Control.FOCUS_ALL
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.12, 0.20, 0.85)
	normal.set_corner_radius_all(8)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.14, 0.22, 0.36, 0.95)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.10, 0.16, 0.28, 1.0)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_color_override("font_color", Color(0.88, 0.93, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_focus_color", Color(1, 1, 1))
	return b
