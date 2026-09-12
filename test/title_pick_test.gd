extends Node
## 标题界面点击链路测试：开始游戏 → 存档面板应弹出。
var title: Control
var frames := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _physics_process(_d: float) -> void:
	frames += 1
	if frames == 5:
		title = load("res://scenes/title_screen/title_screen.tscn").instantiate()
		get_parent().add_child(title)
		print("TEST title built, slot_panel=", title._slot_panel,
			" buttons=", title._slot_buttons.size())
	if frames == 10:
		title._open_slot_picker()
		print("TEST picker open: visible=", title._slot_panel.visible,
			" btn0=", title._slot_buttons[0].text)
		if not title._slot_panel.visible:
			push_error("TEST picker did not open")
		var del_state_ok := true
		for i in title._del_buttons.size():
			if title._del_buttons[i].disabled != GameState.slot_info(i + 1).empty:
				del_state_ok = false
		print("TEST del_buttons=", title._del_buttons.size(), " state_ok=", del_state_ok)
		if not del_state_ok:
			push_error("TEST del button disabled-state mismatch")
	if frames == 15:
		print("TEST OK")
		get_tree().quit()
	if frames > 60:
		push_error("TEST hung")
		get_tree().quit()
