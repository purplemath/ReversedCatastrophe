class_name Hud
extends CanvasLayer
## 战斗界面：氧气/回溯能量条、救援计数、互动提示、对白框、死亡渐暗与回溯滤镜。

var _oxygen_bar: ProgressBar
var _energy_bar: ProgressBar
var _rescue_label: Label
var _prompt: Label
var _toast: Label
var _raft_arrow: Label
var _raft_goal := "救生筏"
var _checkpoint_label: Label
var _checkpoint_timer := 0.0
var _rising_label: Label
var _card_panel: PanelContainer
var _card_title: Label
var _card_tag: Label
var _card_lines: VBoxContainer
var _card_done := Callable()
var _dialogue_panel: PanelContainer
var _dialogue_label: Label
var _dialogue_hint: Label
var _death_fade: ColorRect
var _rewind_tint: ColorRect
var _water_tint: ColorRect
var _rope_bar: ProgressBar
var _rope_marker: ColorRect
var _rope_fill: StyleBoxFlat

var _dialogue_lines: PackedStringArray = []
var _dialogue_index := 0
var _dialogue_done := Callable()
var _death_target := 0.0
var _toast_timer := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	add_to_group("hud")
	_build()

	RewindManager.energy_changed.connect(set_energy)
	RewindManager.rewind_started.connect(func(): set_rewind_active(true))
	RewindManager.rewind_ended.connect(func(_a): set_rewind_active(false))
	GameState.rescued_changed.connect(func(n): set_rescued(n, GameState.time_shards))

func _process(delta: float) -> void:
	# 每帧刷新救出进度：读档恢复/换章 total 变化时不依赖信号
	set_rescued(GameState.rescued_count, GameState.time_shards)
	# 死亡渐暗平滑过渡
	var cur := _death_fade.color.a
	if !is_equal_approx(cur, _death_target):
		_death_fade.color.a = move_toward(cur, _death_target, delta * 2.5)
	if _toast.visible:
		_toast_timer -= delta
		_toast.modulate.a = clampf(_toast_timer, 0.0, 1.0)
		if _toast_timer <= 0.0:
			_toast.visible = false
	if _checkpoint_label.visible:
		_checkpoint_timer -= delta
		_checkpoint_label.modulate.a = clampf(_checkpoint_timer / 0.5, 0.0, 1.0)
		if _checkpoint_timer <= 0.0:
			_checkpoint_label.visible = false

# ---------- 对外接口 ----------

func set_oxygen(value: float, max_value: float) -> void:
	_oxygen_bar.max_value = max_value
	_oxygen_bar.value = value

func set_energy(value: float, max_value: float) -> void:
	_energy_bar.max_value = max_value
	_energy_bar.value = value

func set_rescued(count: int, shards: int) -> void:
	_rescue_label.text = "已救出人：%d/%d · 碎片 %d" % [count, GameState.total_survivors, shards]

func set_prompt(text: String) -> void:
	if text.is_empty():
		_prompt.visible = false
	else:
		_prompt.text = "按 E  %s" % text
		_prompt.visible = true

func show_toast(text: String, duration: float) -> void:
	_toast.text = text
	_toast.visible = true
	_toast.modulate.a = 1.0
	_toast_timer = duration

func flash_checkpoint() -> void:
	_checkpoint_label.visible = true
	_checkpoint_label.modulate.a = 1.0
	_checkpoint_timer = 1.4

## 水位上涨/洪水将至倒计时（顶部居中，少于30秒变红）
func set_rising(active: bool, seconds_left: float, prefix := "水位上涨") -> void:
	_rising_label.visible = active
	if active:
		var s := int(ceilf(seconds_left))
		_rising_label.text = "⚠ %s %d:%02d" % [prefix, s / 60, s % 60]
		_rising_label.add_theme_color_override("font_color",
				Color(1.0, 0.4, 0.35) if seconds_left < 30.0 else Color(1.0, 0.85, 0.5))

func set_raft_goal_name(goal: String) -> void:
	_raft_goal = goal

## 绳索蓄力条（第三章）。needed=目标所需力度（画白色标记），in_window=进入命中窗口（变绿）
func set_rope_charge(frac: float, show: bool, needed := -1.0, in_window := false) -> void:
	_rope_bar.visible = show
	_rope_marker.visible = show and needed >= 0.0
	if not show:
		return
	_rope_bar.value = frac * 100.0
	if needed >= 0.0:
		_rope_marker.position.x = needed * _rope_bar.size.x - 2.0
	_rope_fill.bg_color = Color(0.45, 0.95, 0.55) if in_window else Color(0.95, 0.9, 0.6)

func fade_to(alpha: float) -> void:
	_death_target = alpha

func set_rewind_active(on: bool) -> void:
	_rewind_tint.visible = on

func set_underwater(on: bool) -> void:
	_water_tint.color.a = 0.14 if on else 0.0

## 护送幸存者期间指向救援目标的屏幕边缘箭头：1=右 -1=左 0=隐藏（在屏内）
func set_raft_arrow(dir: int) -> void:
	if dir > 0:
		_raft_arrow.text = "%s →" % _raft_goal
		_raft_arrow.position = Vector2(1040, 280)
		_raft_arrow.visible = true
	elif dir < 0:
		_raft_arrow.text = "← %s" % _raft_goal
		_raft_arrow.position = Vector2(60, 280)
		_raft_arrow.visible = true
	else:
		_raft_arrow.visible = false

func play_dialogue(lines: Array, on_done: Callable = Callable()) -> void:
	_dialogue_lines = PackedStringArray(lines)
	_dialogue_index = 0
	_dialogue_done = on_done
	_dialogue_panel.visible = true
	_dialogue_label.text = _dialogue_lines[0]

# ---------- 内部 ----------

func is_dialogue_visible() -> bool:
	return _dialogue_panel.visible

func is_card_visible() -> bool:
	return _card_panel.visible

## 展示救灾知识卡（救援奖励），关闭时回调
func show_card(card: Dictionary, on_done: Callable = Callable()) -> void:
	Sfx.play("card")
	_card_title.text = str(card.get("title", "救灾知识"))
	_card_tag.text = str(card.get("tag", "知识"))
	for child in _card_lines.get_children():
		child.queue_free()
	for line in card.get("lines", []):
		var l := Label.new()
		l.text = "· " + str(line)
		l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		l.add_theme_font_size_override("font_size", 17)
		l.custom_minimum_size = Vector2(500, 0)
		_card_lines.add_child(l)
	_card_done = on_done
	_card_panel.visible = true

func _close_card() -> void:
	if not _card_panel.visible:
		return
	_card_panel.visible = false
	var cb := _card_done
	_card_done = Callable()
	if cb.is_valid():
		cb.call()

func _unhandled_input(event: InputEvent) -> void:
	if _card_panel.visible:
		if event.is_action_pressed("interact") or event.is_action_pressed("jump") \
				or event.is_action_pressed("ui_accept"):
			_close_card()
			get_viewport().set_input_as_handled()
		return
	if not _dialogue_panel.visible:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("jump") \
			or event.is_action_pressed("ui_accept"):
		_advance_dialogue()
		get_viewport().set_input_as_handled()

func _advance_dialogue() -> void:
	_dialogue_index += 1
	if _dialogue_index >= _dialogue_lines.size():
		_dialogue_panel.visible = false
		var cb := _dialogue_done
		_dialogue_done = Callable()
		if cb.is_valid():
			cb.call()
	else:
		_dialogue_label.text = _dialogue_lines[_dialogue_index]

func _build() -> void:
	_water_tint = _full_rect(Color(0.04, 0.12, 0.28, 0.0))
	add_child(_water_tint)
	_rewind_tint = _full_rect(Color(0.6, 0.4, 0.9, 0.10))
	_rewind_tint.visible = false
	add_child(_rewind_tint)
	_death_fade = _full_rect(Color(0, 0, 0, 0.0))
	add_child(_death_fade)

	# 左上：氧气 / 回溯能量
	var oxy_label := _make_label("氧气", Vector2(24, 20))
	add_child(oxy_label)
	_oxygen_bar = _make_bar(Vector2(80, 22), Color(0.45, 0.85, 1.0))
	add_child(_oxygen_bar)

	var energy_label := _make_label("回溯", Vector2(24, 52))
	add_child(energy_label)
	_energy_bar = _make_bar(Vector2(80, 54), Color(0.75, 0.55, 1.0))
	add_child(_energy_bar)

	# 右上：救援计数
	_rescue_label = _make_label("已救出人：0/0 · 碎片 0", Vector2(870, 20))
	_rescue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_rescue_label.size = Vector2(390, 26)
	add_child(_rescue_label)

	# 互动提示
	_prompt = _make_label("", Vector2(390, 560))
	_prompt.size = Vector2(500, 30)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	_prompt.visible = false
	add_child(_prompt)

	# 顶部居中提示条
	_toast = _make_label("", Vector2(240, 96))
	_toast.size = Vector2(800, 30)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	_toast.visible = false
	add_child(_toast)

	# 护送期间的救生筏方向箭头
	_raft_arrow = _make_label("", Vector2(1040, 280))
	_raft_arrow.add_theme_font_size_override("font_size", 24)
	_raft_arrow.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	_raft_arrow.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_raft_arrow.add_theme_constant_override("outline_size", 6)
	_raft_arrow.visible = false
	add_child(_raft_arrow)

	# 存档点提示
	_checkpoint_label = _make_label("✓ 已存档", Vector2(575, 128))
	_checkpoint_label.size = Vector2(130, 26)
	_checkpoint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_checkpoint_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.65))
	_checkpoint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_checkpoint_label.add_theme_constant_override("outline_size", 5)
	_checkpoint_label.visible = false
	add_child(_checkpoint_label)

	# 水位上涨倒计时
	_rising_label = _make_label("⚠ 水位上涨", Vector2(540, 52))
	_rising_label.size = Vector2(200, 30)
	_rising_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rising_label.add_theme_font_size_override("font_size", 20)
	_rising_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_rising_label.add_theme_constant_override("outline_size", 6)
	_rising_label.visible = false
	add_child(_rising_label)

	# 绳索蓄力条
	_rope_bar = ProgressBar.new()
	_rope_bar.position = Vector2(540, 616)
	_rope_bar.size = Vector2(200, 14)
	_rope_bar.min_value = 0.0
	_rope_bar.max_value = 100.0
	_rope_bar.show_percentage = false
	var rbg := StyleBoxFlat.new()
	rbg.bg_color = Color(0.08, 0.1, 0.16, 0.75)
	rbg.set_corner_radius_all(5)
	var rfill := StyleBoxFlat.new()
	rfill.bg_color = Color(0.95, 0.9, 0.6)
	rfill.set_corner_radius_all(5)
	_rope_bar.add_theme_stylebox_override("background", rbg)
	_rope_fill = rfill
	_rope_bar.add_theme_stylebox_override("fill", rfill)
	_rope_bar.visible = false
	add_child(_rope_bar)
	# 命中窗口标记：松手时机指示（比条略高以便看清）
	_rope_marker = ColorRect.new()
	_rope_marker.color = Color(1.0, 1.0, 1.0, 0.95)
	_rope_marker.size = Vector2(4, 20)
	_rope_marker.position = Vector2(-2, -3)
	_rope_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rope_marker.visible = false
	_rope_bar.add_child(_rope_marker)

	# 底部对白框
	_dialogue_panel = PanelContainer.new()
	_dialogue_panel.position = Vector2(250, 540)
	_dialogue_panel.size = Vector2(780, 150)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.12, 0.85)
	sb.border_color = Color(0.55, 0.75, 1.0, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 22.0
	sb.content_margin_right = 22.0
	sb.content_margin_top = 16.0
	sb.content_margin_bottom = 12.0
	_dialogue_panel.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	_dialogue_label = Label.new()
	_dialogue_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_dialogue_label.add_theme_font_size_override("font_size", 20)
	_dialogue_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_dialogue_label)
	_dialogue_hint = Label.new()
	_dialogue_hint.text = "E / 空格 ▸"
	_dialogue_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dialogue_hint.modulate = Color(1, 1, 1, 0.5)
	_dialogue_hint.add_theme_font_size_override("font_size", 14)
	vb.add_child(_dialogue_hint)
	_dialogue_panel.add_child(vb)
	_dialogue_panel.visible = false
	add_child(_dialogue_panel)

	# 救灾知识卡（救援奖励弹窗）
	_card_panel = PanelContainer.new()
	_card_panel.position = Vector2(330, 140)
	_card_panel.size = Vector2(620, 440)
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.07, 0.09, 0.06, 0.94)
	csb.border_color = Color(0.95, 0.85, 0.5, 0.8)
	csb.set_border_width_all(2)
	csb.set_corner_radius_all(14)
	csb.content_margin_left = 30.0
	csb.content_margin_right = 30.0
	csb.content_margin_top = 24.0
	csb.content_margin_bottom = 18.0
	_card_panel.add_theme_stylebox_override("panel", csb)
	var cvb := VBoxContainer.new()
	cvb.add_theme_constant_override("separation", 14)
	_card_panel.add_child(cvb)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	cvb.add_child(header)
	_card_tag = Label.new()
	_card_tag.text = "自救"
	_card_tag.add_theme_font_size_override("font_size", 15)
	_card_tag.add_theme_color_override("font_color", Color(0.2, 0.35, 0.2))
	_card_tag.add_theme_color_override("font_outline_color", Color(0.95, 0.85, 0.5, 0.9))
	_card_tag.add_theme_constant_override("outline_size", 4)
	header.add_child(_card_tag)
	_card_title = Label.new()
	_card_title.text = "救灾知识卡"
	_card_title.add_theme_font_size_override("font_size", 26)
	_card_title.add_theme_color_override("font_color", Color(0.98, 0.93, 0.75))
	header.add_child(_card_title)
	_card_lines = VBoxContainer.new()
	_card_lines.add_theme_constant_override("separation", 16)
	_card_lines.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cvb.add_child(_card_lines)
	var card_hint := Label.new()
	card_hint.text = "已收录入防灾手册 · E 收下"
	card_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	card_hint.add_theme_font_size_override("font_size", 13)
	card_hint.modulate = Color(1, 1, 1, 0.5)
	cvb.add_child(card_hint)
	_card_panel.visible = false
	add_child(_card_panel)

func _full_rect(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _make_label(text: String, pos: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", 16)
	return l

func _make_bar(pos: Vector2, fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = pos
	bar.size = Vector2(220, 16)
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.1, 0.16, 0.75)
	bg.set_corner_radius_all(5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	return bar
