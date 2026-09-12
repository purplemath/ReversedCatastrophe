extends Node
## 标题界面「删除存档」GUI 流程测试（真实根窗口环境）：
## 点击开始游戏 → 点击槽3 × → 进入确认态 → 再点 → 槽位清空。
## 测试前后备份/还原玩家真实存档（与 save_test 相同策略）。
const TITLE := preload("res://scenes/title_screen/title_screen.tscn")
const DUMMY_SAVE := '{"chapter": 3, "rescued_total": 1, "lost_total": 0, "unlocked_card_ids": ["ch3_rope"], "saved_at": "TEST-DELETE"}'

var title: Control
var _backup: Dictionary = {}
var frames := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _physics_process(_d: float) -> void:
	frames += 1
	if frames == 5:
		_setup()
	elif frames == 12 and is_instance_valid(title):
		_click(title._start_btn)
	elif frames == 20 and is_instance_valid(title):
		_click(title._del_buttons[2])  # 槽3 ×：第一次按 → 确认态
	elif frames == 23 and is_instance_valid(title):
		if title._del_buttons[2].text != "确认":
			push_error("DELETE-TEST first press did not arm confirm")
	elif frames == 26 and is_instance_valid(title):
		_click(title._del_buttons[2])  # 第二次按 → 删除
	elif frames == 34:
		_finish()
	if frames > 60:
		push_error("DELETE-TEST hung")
		_restore()
		get_tree().quit()

func _setup() -> void:
	for s in GameState.SLOT_COUNT:
		var p: String = GameState.slot_path(s + 1)
		if FileAccess.file_exists(p):
			_backup[p] = FileAccess.get_file_as_string(p)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var f := FileAccess.open(GameState.slot_path(3), FileAccess.WRITE)
	f.store_string(DUMMY_SAVE)
	f.close()
	title = TITLE.instantiate()
	get_tree().root.add_child.call_deferred(title)

func _click(btn: Button) -> void:
	var win_pos: Vector2 = get_viewport().get_final_transform() * btn.get_global_rect().get_center()
	var ev_move := InputEventMouseMotion.new()
	ev_move.position = win_pos
	ev_move.global_position = win_pos
	get_viewport().push_input(ev_move)
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

func _finish() -> void:
	var ok := true
	if not GameState.slot_info(3).get("empty", false):
		push_error("DELETE-TEST slot3 not deleted")
		ok = false
	if not title._slot_buttons[2].text.contains("空"):
		push_error("DELETE-TEST slot3 row text not refreshed: " + title._slot_buttons[2].text)
		ok = false
	if not title._del_buttons[2].disabled:
		push_error("DELETE-TEST slot3 del button should be disabled when empty")
		ok = false
	_restore()
	if ok:
		print("DELETE-TEST OK: ×两次确认删除存档，槽位已清空并刷新")
	else:
		print("DELETE-TEST FAIL")
	get_tree().quit()

func _restore() -> void:
	for p in _backup:
		var f := FileAccess.open(p, FileAccess.WRITE)
		if f != null:
			f.store_string(_backup[p])
	for s in GameState.SLOT_COUNT:
		var sp: String = GameState.slot_path(s + 1)
		if FileAccess.file_exists(sp) and not _backup.has(sp):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(sp))
