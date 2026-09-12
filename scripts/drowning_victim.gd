class_name DrowningVictim
extends CharacterBody2D
## 第三章：激流中的落水者。用救援绳（Q 蓄力抛出）拉向玩家即为获救。
## 状态：0=挣扎待救（原地扑腾） 1=被绳索拉拽中 2=已获救 3=被冲走(LOST)。

signal saved_signal
signal washed_away

const WATER_GRAVITY := 150.0
const WATER_DRAG := 3.0

var state := 0
var home := Vector2.ZERO
var ropable := true  # 电击区通电时为 false（绳索无法靠近）
var _pull_target: Node2D = null

func _ready() -> void:
	add_to_group("rewindables")
	add_to_group("victims")
	home = position
	var cs := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = 10.0
	cap.height = 34.0
	cs.shape = cap
	add_child(cs)

func grab(target: Node2D) -> void:
	if state == 0 and ropable:
		state = 1
		_pull_target = target

func _physics_process(delta: float) -> void:
	if RewindManager.rewinding:
		return
	match state:
		0:
			# 原地扑腾挣扎
			var anchor := home + Vector2(sin(Time.get_ticks_msec() / 300.0) * 10.0, 0)
			velocity += (anchor - global_position) * 5.0 * delta
			velocity += Vector2.DOWN * WATER_GRAVITY * delta
			velocity = velocity.lerp(Vector2.ZERO, clampf(WATER_DRAG * delta, 0.0, 1.0))
			move_and_slide()
		1:
			# 被绳索拉向玩家
			if _pull_target == null or not is_instance_valid(_pull_target):
				state = 0
				return
			velocity = Vector2.ZERO
			global_position = global_position.lerp(_pull_target.global_position, 7.0 * delta)
			if global_position.distance_to(_pull_target.global_position) < 42.0:
				state = 2
				saved_signal.emit()
		_:
			velocity = Vector2.ZERO
	queue_redraw()

func capture_state() -> Dictionary:
	return {"pos": position, "state": state, "home": home}

func restore_state(s: Dictionary) -> void:
	if state >= 2:
		return  # 已获救/被冲走：命运锁定，回溯不可逆
	position = s["pos"]
	state = s["state"]
	home = s["home"]

func _draw() -> void:
	match state:
		0:
			var c := Color(0.9, 0.72, 0.45)
			draw_circle(Vector2(0, -8), 8.0, c)
			draw_rect(Rect2(-6, 0, 12, 14), c)
			var f: Font = ThemeDB.fallback_font
			draw_string(f, Vector2(-14, -24), "救命", HORIZONTAL_ALIGNMENT_CENTER, 30.0, 13, Color(1.0, 0.85, 0.4))
			if not ropable:
				draw_circle(Vector2(0, -46), 9.0, Color(1.0, 0.5, 0.2, 0.5))
		1:
			draw_circle(Vector2(0, -8), 8.0, Color(0.9, 0.72, 0.45))
			draw_rect(Rect2(-6, 0, 12, 14), Color(0.9, 0.72, 0.45))
