extends Control
## 标题界面：开始游戏 / 地图编辑器（占位）/ 退出游戏。

const GAME_SCENE := "res://scenes/main.tscn"
const WATER_LINE_Y := 396.0

var _wave: Line2D
var _time := 0.0
var _start_btn: Button

# 存档位选择
var _slot_panel: Control
var _slot_title: Label
var _slot_buttons: Array[Button] = []
var _del_buttons: Array[Button] = []
var _del_confirm_slot := 0  # 正在等待二次确认删除的槽位（0=无）

func _unhandled_input(event: InputEvent) -> void:
	if _slot_panel != null and _slot_panel.visible and event.is_action_pressed("ui_cancel"):
		_close_slot_picker()
		get_viewport().set_input_as_handled()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_start_btn.grab_focus()

func _process(delta: float) -> void:
	_time += delta
	var pts := PackedVector2Array()
	var x := 0.0
	while x <= size.x:
		pts.append(Vector2(x, WATER_LINE_Y + sin((x + _time * 60.0) / 90.0 * TAU) * 8.0))
		x += 32.0
	_wave.points = pts

func _start_game() -> void:
	_open_slot_picker()

## 从选定槽位开始（fresh=true 新游戏并覆盖，否则续档）
func _start_with_slot(slot: int, fresh: bool) -> void:
	_close_slot_picker()
	GameState.testing_level = false
	GameState.custom_level = {}
	RewindManager.reset()
	GameState.active_slot = slot
	if fresh or not GameState.load_game(slot):
		GameState.reset_run()
		ChapterManager.current = 1
	GameState.save_game()
	get_tree().change_scene_to_file(GAME_SCENE)

func _open_slot_picker() -> void:
	_slot_title.text = "选择存档位"
	_refresh_slot_buttons()
	_slot_panel.visible = true
	for b in _slot_buttons:
		if b.disabled:
			continue
		b.grab_focus()
		break

func _close_slot_picker() -> void:
	_slot_panel.visible = false
	_reset_del_confirm()

func _refresh_slot_buttons() -> void:
	_reset_del_confirm()
	for i in _slot_buttons.size():
		var slot := i + 1
		var info: Dictionary = GameState.slot_info(slot)
		var b := _slot_buttons[i]
		_del_buttons[i].disabled = info.empty
		b.disabled = false
		if info.empty:
			b.text = "槽位 %d · 空（开始新游戏）" % slot
		else:
			b.disabled = false
			b.text = "槽位 %d · %s ｜ 救 %d 失 %d ｜ 手册 %d/%d ｜ %s" % [
				slot, info.get("chapter_name", ""), info.get("rescued_total", 0),
				info.get("lost_total", 0), info.get("cards", 0),
				GameState.all_cards.size(), info.get("saved_at", "")]

func _on_slot_pressed(slot: int) -> void:
	_reset_del_confirm()
	# 现代存档位惯例：空档=新开游戏；已有进度=读档继续。想覆盖请先用 × 删除
	_start_with_slot(slot, GameState.slot_info(slot).empty)

## 删除存档：× 按两次确认（第一次进入确认态，再按执行删除）
func _on_delete_pressed(slot: int) -> void:
	if GameState.slot_info(slot).empty:
		return
	if _del_confirm_slot != slot:
		_del_confirm_slot = slot
		_del_buttons[slot - 1].text = "确认"
		_style_del_button(_del_buttons[slot - 1], true)
		return
	GameState.delete_slot(slot)
	_refresh_slot_buttons()

func _reset_del_confirm() -> void:
	_del_confirm_slot = 0
	for d in _del_buttons:
		d.text = "×"
		_style_del_button(d, false)

func _style_del_button(d: Button, confirm: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.38, 0.10, 0.12, 0.95) if confirm else Color(0.08, 0.12, 0.20, 0.85)
	sb.set_corner_radius_all(8)
	d.add_theme_stylebox_override("normal", sb)
	d.add_theme_stylebox_override("hover", sb.duplicate())
	d.add_theme_stylebox_override("pressed", sb.duplicate())
	d.add_theme_stylebox_override("disabled", sb.duplicate())
	d.add_theme_color_override("font_color",
			Color(1.0, 0.72, 0.72) if confirm else Color(0.85, 0.90, 1.0))

func _quit_game() -> void:
	get_tree().quit()

func _open_editor() -> void:
	GameState.testing_level = false
	get_tree().change_scene_to_file("res://scenes/editor/editor.tscn")

func _build() -> void:
	# 天空渐变
	var sky := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.68, 0.85, 0.95))
	grad.set_color(1, Color(0.05, 0.20, 0.40))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	sky.texture = tex
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)

	# 远山剪影
	for r in [Rect2(-100, 300, 700, 200), Rect2(400, 260, 600, 240),
			Rect2(950, 310, 600, 190), Rect2(1500, 280, 500, 220)]:
		var m := ColorRect.new()
		m.position = r.position
		m.size = r.size
		m.color = Color(0.40, 0.53, 0.70, 0.9)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(m)

	# 下半屏水面
	var water := ColorRect.new()
	water.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	water.anchor_top = WATER_LINE_Y / 720.0
	water.offset_top = 0
	water.color = Color(0.09, 0.23, 0.42)
	water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(water)

	_wave = Line2D.new()
	_wave.width = 4.0
	_wave.default_color = Color(0.85, 0.95, 1.0, 0.9)
	add_child(_wave)

	# 居中菜单
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	cc.add_child(vb)

	var title := Label.new()
	title.text = "逆转的天灾"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.97, 0.99, 1.0))
	vb.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Reversed Catastrophe · test"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.modulate = Color(1, 1, 1, 0.65)
	vb.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 36)
	vb.add_child(spacer)

	_start_btn = _make_button("开始游戏")
	_start_btn.pressed.connect(_start_game)
	vb.add_child(_start_btn)

	var editor_btn := _make_button("地图编辑器")
	editor_btn.pressed.connect(_open_editor)
	vb.add_child(editor_btn)

	var quit_btn := _make_button("退出游戏")
	quit_btn.pressed.connect(_quit_game)
	vb.add_child(quit_btn)

	var editor_hint := Label.new()
	editor_hint.text = "在编辑器中微调关卡：保存后可试玩"
	editor_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	editor_hint.add_theme_font_size_override("font_size", 13)
	editor_hint.modulate = Color(1, 1, 1, 0.45)
	vb.add_child(editor_hint)

	# 左下版本号 / 右下制作人员
	var version := Label.new()
	version.text = "版本号：0.5"
	version.add_theme_font_size_override("font_size", 14)
	version.modulate = Color(1, 1, 1, 0.55)
	version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT,
			Control.PRESET_MODE_MINSIZE, 16)
	add_child(version)
	var credits := Label.new()
	credits.text = "策划：紫数；程序：GLM、紫数、新月"
	credits.add_theme_font_size_override("font_size", 14)
	credits.modulate = Color(1, 1, 1, 0.55)
	credits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	credits.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT,
			Control.PRESET_MODE_MINSIZE, 16)
	add_child(credits)

	_build_slot_picker()

func _build_slot_picker() -> void:
	_slot_panel = Control.new()
	_slot_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slot_panel.visible = false
	add_child(_slot_panel)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slot_panel.add_child(dim)

	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slot_panel.add_child(cc)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.12, 0.95)
	sb.border_color = Color(0.55, 0.75, 1.0, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 28.0
	sb.content_margin_right = 28.0
	sb.content_margin_top = 22.0
	sb.content_margin_bottom = 18.0
	panel.add_theme_stylebox_override("panel", sb)
	cc.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	_slot_title = Label.new()
	_slot_title.text = "选择存档位"
	_slot_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slot_title.add_theme_font_size_override("font_size", 22)
	_slot_title.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	vb.add_child(_slot_title)
	for i in GameState.SLOT_COUNT:
		var slot := i + 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(656, 46)
		b.focus_mode = Control.FOCUS_ALL
		b.add_theme_font_size_override("font_size", 16)
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0.08, 0.12, 0.20, 0.85)
		normal.set_corner_radius_all(8)
		normal.content_margin_left = 14.0
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("hover", normal.duplicate())
		b.add_theme_stylebox_override("pressed", normal.duplicate())
		b.add_theme_stylebox_override("disabled", normal.duplicate())
		b.pressed.connect(_on_slot_pressed.bind(slot))
		row.add_child(b)
		_slot_buttons.append(b)
		var del := Button.new()
		del.text = "×"
		del.custom_minimum_size = Vector2(46, 46)
		del.focus_mode = Control.FOCUS_ALL
		del.add_theme_font_size_override("font_size", 16)
		del.pressed.connect(_on_delete_pressed.bind(slot))
		_style_del_button(del, false)
		row.add_child(del)
		_del_buttons.append(del)
		vb.add_child(row)
	var hint := Label.new()
	hint.text = "空档位=新游戏 · 已有进度=继续 · × 删除（按两次确认） · ESC 返回"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(1, 1, 1, 0.5)
	vb.add_child(hint)

func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 48)
	b.focus_mode = Control.FOCUS_ALL
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.12, 0.20, 0.85)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 12.0
	normal.content_margin_right = 12.0
	var hover := normal.duplicate()
	hover.bg_color = Color(0.14, 0.22, 0.36, 0.95)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.10, 0.16, 0.28, 1.0)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", Color(0.88, 0.93, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(0.75, 0.9, 1.0))
	b.add_theme_color_override("font_focus_color", Color(1, 1, 1))
	return b
