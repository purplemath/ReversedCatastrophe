extends Node
## 标题界面真实点击链路测试（真实环境复现版）：
## 把标题场景挂到根窗口（与 change_scene 相同），注入**窗口坐标系**的鼠标事件
## （push_input(ev, false)，引擎自动做窗口→画布变换），与操作系统投递事件的路径一致。
## autoload 的 CanvasLayer（如章节过场覆盖层）全程在位，能暴露"全屏控件截胡"类 bug。
## 判定：悬停命中必须是开始按钮本身（而非任何父容器），点击后面板弹出。
const TITLE := preload("res://scenes/title_screen/title_screen.tscn")

var title: Control
var frames := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _physics_process(_d: float) -> void:
	frames += 1
	if frames == 5 and title == null:
		title = TITLE.instantiate()
		get_tree().root.add_child.call_deferred(title)
	if frames == 14 and is_instance_valid(title):
		_click_at(title._start_btn)
	if frames == 30 and is_instance_valid(title):
		var ok: bool = title._slot_panel != null and title._slot_panel.visible
		if ok:
			print("CLICK-TEST OK: 真实鼠标事件链路正常，面板已弹出")
		else:
			push_error("CLICK-TEST FAIL: 点击开始游戏后面板未弹出")
		get_tree().quit()
	if frames > 90:
		push_error("CLICK-TEST hung")
		get_tree().quit()

func _click_at(btn: Button) -> void:
	var canvas_center: Vector2 = btn.get_global_rect().get_center()
	# 窗口坐标系：与 OS 投递给引擎的事件一致（push_input 默认按窗口坐标处理）
	var win_pos: Vector2 = get_viewport().get_final_transform() * canvas_center
	print("CLICK-TEST btn canvas=", canvas_center, " window=", win_pos,
		" final_scale=", get_viewport().get_final_transform().get_scale())
	var ev_move := InputEventMouseMotion.new()
	ev_move.position = win_pos
	ev_move.global_position = win_pos
	get_viewport().push_input(ev_move)
	var hovered: Control = get_viewport().gui_get_hovered_control()
	var hover_name: String = hovered.name if hovered else "-"
	print("CLICK-TEST hovered=", hovered, " btn_hovered=", btn.is_hovered())
	var ev_press := InputEventMouseButton.new()
	ev_press.button_index = MOUSE_BUTTON_LEFT
	ev_press.pressed = true
	ev_press.position = win_pos
	ev_press.global_position = win_pos
	get_viewport().push_input(ev_press)
	var ev_release := InputEventMouseButton.new()
	ev_release.button_index = MOUSE_BUTTON_LEFT
	ev_release.pressed = false
	ev_release.position = win_pos
	ev_release.global_position = win_pos
	get_viewport().push_input(ev_release)
	if hovered != btn:
		push_error("CLICK-TEST hover 没有命中开始按钮，被 %s 截胡" % hover_name)
		get_tree().quit()
