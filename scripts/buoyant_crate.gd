class_name BuoyantCrate
extends RigidBody2D
## 漂浮木箱：受 WaterBody 浮力作用，参与时间回溯（倒带期间冻结）。

const SIZE := 64.0

func _ready() -> void:
	add_to_group("rewindables")
	set_meta("half_height", SIZE * 0.5)
	mass = 1.0
	freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(SIZE, SIZE)
	cs.shape = shape
	add_child(cs)
	var vis := ColorRect.new()
	vis.position = Vector2(-SIZE * 0.5, -SIZE * 0.5)
	vis.size = Vector2(SIZE, SIZE)
	vis.color = Color(0.62, 0.45, 0.28)
	vis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vis)

func capture_state() -> Dictionary:
	return {"pos": position, "rot": rotation, "lv": linear_velocity, "av": angular_velocity}

func restore_state(s: Dictionary) -> void:
	position = s["pos"]
	rotation = s["rot"]
	linear_velocity = s["lv"]
	angular_velocity = s["av"]

func on_rewind_start() -> void:
	freeze = true

func on_rewind_end() -> void:
	freeze = false
