class_name DamConsole
extends Node2D
## 第三章：大坝监控台。所有落水者获救/失联后解锁，读取调度记录触发章节结局。

signal used

var unlocked := false
var _screen: ColorRect

func _ready() -> void:
	add_to_group("interactables")
	set_meta("interact_label", "监控台（锁定）")
	var r := ColorRect.new()
	r.position = Vector2(-30, -40)
	r.size = Vector2(60, 46)
	r.color = Color(0.25, 0.3, 0.38)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	_screen = ColorRect.new()
	_screen.position = Vector2(-24, -34)
	_screen.size = Vector2(48, 22)
	_screen.color = Color(0.2, 0.7, 0.5)
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen)

func set_unlocked(on: bool) -> void:
	unlocked = on
	set_meta("interact_label", "读取调度记录" if on else "监控台（锁定）")
	_screen.color = Color(0.9, 0.5, 0.3) if on else Color(0.2, 0.7, 0.5)

func interact(_player) -> void:
	if unlocked:
		used.emit()
	else:
		var hud := get_tree().get_first_node_in_group("hud")
		if hud != null:
			hud.show_toast("监控台锁定中——先处理完河中所有被困者", 3.0)
