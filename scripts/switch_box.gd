class_name SwitchBox
extends Node2D
## 第三章：配电箱断电闸。按住 E 累积进度，充满后电击区断电。

signal power_cut

const HOLD_SECONDS := 1.6
const RANGE := 110.0

var powered := true
var progress := 0.0
var action_label := "断电"  # 第四章复用为「拆除装置」

func _ready() -> void:
	add_to_group("interactables")
	set_meta("interact_label", "按住 E " + action_label)
	var r := ColorRect.new()
	r.position = Vector2(-14, -30)
	r.size = Vector2(28, 44)
	r.color = Color(0.45, 0.3, 0.3)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	_lamp = ColorRect.new()
	_lamp.position = Vector2(-5, -26)
	_lamp.size = Vector2(10, 10)
	_lamp.color = Color(1.0, 0.4, 0.3)
	_lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lamp)

var _lamp: ColorRect

## 第四章时间循环：新的一天装置重新布设
func rearm() -> void:
	powered = true
	progress = 0.0
	set_meta("interact_label", "按住 E " + action_label)
	_lamp.color = Color(1.0, 0.4, 0.3)

func interact(_player) -> void:
	pass  # 进度由 _physics_process 的按住检测驱动

func _physics_process(delta: float) -> void:
	if not powered:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if global_position.distance_to(player.global_position) < RANGE \
			and Input.is_action_pressed("interact"):
		progress += delta / HOLD_SECONDS
		set_meta("interact_label", "%s中 %d%%" % [action_label, int(progress * 100.0)])
		if progress >= 1.0:
			powered = false
			set_meta("interact_label", "已完成")
			power_cut.emit()
			_lamp.color = Color(0.3, 0.8, 0.4)
	else:
		progress = maxf(0.0, progress - delta * 2.0)
		if progress <= 0.0:
			set_meta("interact_label", "按住 E " + action_label)
