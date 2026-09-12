class_name WaterBody
extends Area2D
## 水体：提供水面高度查询与浸水判断，对刚体施加浮力与水阻。

@export var surface_y := 520.0
@export var region := Rect2(0, 520, 4800, 1080)
@export var wave_amplitude := 6.0
@export var wave_length := 90.0
@export var wave_speed := 60.0

const BUOYANCY := 2300.0  # 与默认重力 980 平衡，约 43% 浸没时悬浮

var _wave_line: Line2D
var _time := 0.0

func _ready() -> void:
	add_to_group("water")
	monitoring = true
	monitorable = true
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = region.size
	shape.shape = rect
	shape.position = region.get_center()
	add_child(shape)

	var overlay := ColorRect.new()
	overlay.color = Color(0.18, 0.42, 0.68, 0.38)
	overlay.position = region.position
	overlay.size = region.size
	overlay.z_index = 4
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	_wave_line = Line2D.new()
	_wave_line.width = 4.0
	_wave_line.default_color = Color(0.85, 0.95, 1.0, 0.9)
	_wave_line.z_index = 6
	add_child(_wave_line)

func _process(delta: float) -> void:
	_time += delta
	var pts := PackedVector2Array()
	var x := region.position.x
	while x <= region.end.x:
		var y := surface_y + sin((x + _time * wave_speed) / wave_length * TAU) * wave_amplitude
		pts.append(Vector2(x, y))
		x += 48.0
	_wave_line.points = pts

func _physics_process(delta: float) -> void:
	for body in get_overlapping_bodies():
		if body is RigidBody2D and not body.freeze:
			var half := float(body.get_meta("half_height", 32.0))
			var frac := clampf((body.global_position.y + half - surface_y) / (2.0 * half), 0.0, 1.0)
			if frac > 0.0:
				body.apply_central_force(Vector2.UP * body.mass * BUOYANCY * frac)
				body.linear_velocity = body.linear_velocity.lerp(Vector2.ZERO, clampf(2.2 * delta, 0.0, 1.0))
				body.angular_velocity *= 1.0 - clampf(2.0 * delta, 0.0, 1.0)

func is_underwater(point: Vector2) -> bool:
	return region.has_point(point) and point.y > surface_y

func get_visual_surface_y(x: float) -> float:
	return surface_y + sin((x + _time * wave_speed) / wave_length * TAU) * wave_amplitude

## 洪水上涨演出：在 seconds 内把水面从当前高度抬升到 target_y
func rise_to(target_y: float, seconds: float) -> void:
	var tw := create_tween()
	tw.tween_method(_set_surface, surface_y, target_y, seconds)

func _set_surface(y: float) -> void:
	surface_y = y
	region = Rect2(region.position.x, y, region.size.x, region.end.y - y)
	for c in get_children():
		if c is ColorRect:
			c.position = Vector2(region.position.x, y)
			c.size = region.size
