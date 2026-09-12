class_name Survivor
extends CharacterBody2D
## 幸存者NPC：被困踩水 → 被救起后跟随玩家 → 送达救生筏后获救。参与时间回溯。

signal state_changed(new_state: int)

enum State { TRAPPED, FOLLOWING, RESCUED, LOST }  # LOST=水位上涨时未能获救，回溯也无法挽回

const GRAVITY := 1500.0
const WATER_GRAVITY := 150.0
const WATER_DRAG := 3.0
const SWIM_ACCEL := 950.0
const SWIM_MAX := 210.0
const WALK_SPEED := 190.0
const JUMP_V := -400.0

var state := State.TRAPPED
var facing := 1

var _home := Vector2.ZERO
var _water: WaterBody
var _player: Player
var _stroke_cd := 0.0
var _leaping := false

func _ready() -> void:
	add_to_group("rewindables")
	add_to_group("interactables")
	add_to_group("survivor")
	set_meta("interact_label", "救起幸存者")
	_home = position
	_water = get_tree().get_first_node_in_group("water")

	var cs := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = 11.0
	cap.height = 38.0
	cs.shape = cap
	add_child(cs)

func set_state(s: int) -> void:
	state = s
	state_changed.emit(s)

func interact(player: Player) -> void:
	if state != State.TRAPPED:
		return
	_player = player
	remove_from_group("interactables")
	set_state(State.FOLLOWING)

func _physics_process(delta: float) -> void:
	if RewindManager.rewinding:
		return
	var in_water := _water != null and _water.is_underwater(global_position)
	match state:
		State.TRAPPED:
			_trapped(delta, in_water)
		State.FOLLOWING:
			_follow(delta, in_water)
		State.RESCUED, State.LOST:
			velocity = Vector2.ZERO
	move_and_slide()
	queue_redraw()

func _trapped(delta: float, in_water: bool) -> void:
	if in_water:
		# 原地踩水：向上下浮动的锚点弹簧收敛（不叠加重力，避免缓慢沉底）
		var anchor := _home + Vector2(0.0, sin(Time.get_ticks_msec() / 380.0) * 12.0)
		velocity += (anchor - global_position) * 6.0 * delta
		velocity = velocity.lerp(Vector2.ZERO, clampf(WATER_DRAG * delta, 0.0, 1.0))
	else:
		velocity.x = move_toward(velocity.x, 0.0, 800.0 * delta)
		velocity.y += GRAVITY * delta

func _follow(delta: float, in_water: bool) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_stroke_cd = maxf(0.0, _stroke_cd - delta)
	var target: Vector2 = _player.global_position + Vector2(-44.0 * _player.facing, -4.0)
	var dx := target.x - global_position.x
	facing = 1 if dx > 0.0 else -1
	if in_water:
		var to := target - global_position
		if not _leaping:
			if to.length() > 34.0:
				velocity += to.normalized() * SWIM_ACCEL * delta
			velocity += Vector2.DOWN * WATER_GRAVITY * delta
			velocity = velocity.lerp(Vector2.ZERO, clampf(WATER_DRAG * delta, 0.0, 1.0))
			velocity = velocity.limit_length(SWIM_MAX)
		# 目标明显高于自己且已贴近水面：蹬水跃出。
		# 跳跃期间豁免水中限幅/阻尼（否则 -420 会在下一帧被 limit_length 削回 210）
		var head_up := _water != null and not _water.is_underwater(global_position + Vector2(0, -12.0))
		if not _leaping and _stroke_cd <= 0.0 and to.y < -40.0 and absf(to.x) < 420.0 and head_up:
			velocity.y = -420.0
			_stroke_cd = 0.6
			_leaping = true
	else:
		_leaping = false
		if absf(dx) > 20.0:
			velocity.x = move_toward(velocity.x, signf(dx) * WALK_SPEED, 1500.0 * delta)
		else:
			velocity.x = move_toward(velocity.x, 0.0, 1500.0 * delta)
		velocity.y += GRAVITY * delta
		if is_on_floor() and is_on_wall() and absf(dx) > 40.0:
			velocity.y = JUMP_V

func capture_state() -> Dictionary:
	return {"pos": position, "vel": velocity, "facing": facing, "state": state}

func restore_state(s: Dictionary) -> void:
	if state == State.LOST:
		return  # 已失落的幸存者不受回溯影响（命运锁定）
	position = s["pos"]
	velocity = s["vel"]
	facing = s["facing"]
	state = s["state"]
	queue_redraw()

func _draw() -> void:
	var c := Color(0.45, 0.78, 0.55)
	# 头发
	draw_circle(Vector2(-2.0 * facing, -16.0), 8.0, Color(0.15, 0.35, 0.25))
	# 头
	draw_circle(Vector2(0, -12.0), 8.5, c)
	# 身体
	draw_rect(Rect2(-7.0, -3.0, 14.0, 18.0), Color(0.85, 0.72, 0.4))
	# 眼睛
	draw_circle(Vector2(3.5 * facing, -12.0), 1.8, Color(0.1, 0.1, 0.12))
	if state == State.TRAPPED:
		var f: Font = ThemeDB.fallback_font
		draw_circle(Vector2(0, -36.0), 12.0, Color(1.0, 0.85, 0.3, 0.35))
		draw_string(f, Vector2(-14.0, -28.0), "!", HORIZONTAL_ALIGNMENT_CENTER, 28.0, 30.0, Color(1.0, 0.9, 0.3))
