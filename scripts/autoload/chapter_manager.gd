extends Node
## 章节管理器（自动加载）：章节注册表、回溯过场（黑屏+章节标题）、线性章节推进。

signal chapter_started(chapter_id: int)

const CHAPTERS := {
	1: {"name": "水下一小时", "time": "洪水之后 · 此刻", "implemented": true},
	2: {"name": "洪水之夜", "time": "洪水之前 6 小时", "implemented": true},
	3: {"name": "灾变的链条", "time": "洪水之前 3 天", "implemented": true},
	4: {"name": "逆转的天灾", "time": "洪水之前 3 周", "implemented": true},
}

const GAME_SCENE := "res://scenes/main.tscn"

var current := 1

var _overlay: CanvasLayer
var _fade: ColorRect
var _title_label: Label
var _subtitle_label: Label
var _phase := ""  # "": 空闲 / "out": 渐黑 / "hold": 停留 / "in": 渐显
var _t := 0.0
var _pending_scene := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_overlay()

func is_implemented(chapter_id: int) -> bool:
	return CHAPTERS.has(chapter_id) and CHAPTERS[chapter_id].implemented

func chapter_title(chapter_id: int) -> String:
	if CHAPTERS.has(chapter_id):
		return "第%s章 · %s" % [chap_num(chapter_id), CHAPTERS[chapter_id].name]
	return "未知章节"

func chap_num(chapter_id: int) -> String:
	return ["〇", "一", "二", "三", "四", "五"][clampi(chapter_id, 0, 5)]

## 结算后推进：下一章已实现则过场切换，否则提示开发中
func request_next() -> void:
	var next := current + 1
	if is_implemented(next):
		transition_to(next)
		return
	var next_name := "后续章节"
	if CHAPTERS.has(next):
		next_name = str(CHAPTERS[next].get("name", next_name))
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.show_toast("—— 下一章《%s》· 敬请期待 ——" % next_name, 5.0)
	else:
		print("NEXT CHAPTER NOT IMPLEMENTED: ", next)

## 回溯过场：渐黑 → 章节标题 → 场景切换 → 渐显
func transition_to(chapter_id: int) -> void:
	if _phase != "":
		return
	current = chapter_id
	GameState.begin_chapter()
	GameState.save_game()
	_title_label.text = chapter_title(chapter_id)
	_subtitle_label.text = str(CHAPTERS[chapter_id].time)
	_phase = "out"
	_t = 0.0
	_pending_scene = GAME_SCENE

func _process(delta: float) -> void:
	if _phase == "":
		return
	_t += delta
	match _phase:
		"out":
			var a := minf(_t / 0.8, 1.0)
			_fade.color.a = a
			if a >= 1.0:
				_phase = "hold"
				_t = 0.0
		"hold":
			_title_label.modulate.a = minf(_t / 0.6, 1.0)
			_subtitle_label.modulate.a = minf(maxf(_t - 0.4, 0.0) / 0.6, 1.0)
			if _t >= 2.2:
				if _pending_scene != "":
					get_tree().change_scene_to_file(_pending_scene)
					_pending_scene = ""
				_phase = "in"
				_t = 0.0
		"in":
			var a := maxf(1.0 - _t / 0.8, 0.0)
			_fade.color.a = a
			if a <= 0.0:
				_phase = ""
				_title_label.modulate.a = 0.0
				_subtitle_label.modulate.a = 0.0
				chapter_started.emit(current)

func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 30
	add_child(_overlay)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_fade)
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	# 全屏容器必须放行鼠标，否则会拦下所有 GUI 点击（章节文字无需交互）
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(vb)
	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 44)
	_title_label.add_theme_color_override("font_color", Color(0.9, 0.97, 1.0))
	_title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_title_label.add_theme_constant_override("outline_size", 8)
	_title_label.modulate.a = 0.0
	vb.add_child(_title_label)
	_subtitle_label = Label.new()
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", 20)
	_subtitle_label.modulate = Color(1, 1, 1, 0.7)
	_subtitle_label.modulate.a = 0.0
	vb.add_child(_subtitle_label)
