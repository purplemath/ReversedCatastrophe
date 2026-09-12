class_name MovingDebris
extends AnimatableBody2D
## 随水流在 A/B 两点间往返的漂浮残骸（可站立的移动平台）。参与时间回溯。

var point_a := Vector2.ZERO
var point_b := Vector2.ZERO
var speed := 70.0
var width := 120.0
var height := 26.0

var _progress := 0.0  # 0..1，沿 A→B 的位置比例
var _dir := 1.0
var current_velocity := Vector2.ZERO  # 供站立者同步 platform_velocity

func _ready() -> void:
	add_to_group("rewindables")
	add_to_group("platforms")
	sync_to_physics = true
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width, height)
	cs.shape = shape
	add_child(cs)
	var vis := ColorRect.new()
	vis.position = Vector2(-width * 0.5, -height * 0.5)
	vis.size = Vector2(width, height)
	vis.color = Color(0.55, 0.42, 0.30)
	vis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vis)
	var stripe := ColorRect.new()
	stripe.position = Vector2(-width * 0.5, -height * 0.5)
	stripe.size = Vector2(width, 6.0)
	stripe.color = Color(0.85, 0.75, 0.5, 0.8)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stripe)

func _physics_process(delta: float) -> void:
	if RewindManager.rewinding:
		current_velocity = Vector2.ZERO
		return
	var length := point_a.distance_to(point_b)
	if length < 1.0:
		current_velocity = Vector2.ZERO
		return
	_progress += _dir * speed * delta / length
	if _progress >= 1.0:
		_progress = 1.0
		_dir = -1.0
	elif _progress <= 0.0:
		_progress = 0.0
		_dir = 1.0
	var new_pos := point_a.lerp(point_b, _progress)
	current_velocity = (new_pos - global_position) / maxf(delta, 0.0001)
	global_position = new_pos

func capture_state() -> Dictionary:
	return {"pos": global_position, "progress": _progress, "dir": _dir}

func restore_state(s: Dictionary) -> void:
	global_position = s["pos"]
	_progress = s["progress"]
	_dir = s["dir"]
