class_name Player
extends CharacterBody2D
## 主角小X：陆地平台跳跃 + 水中自由游泳，氧气机制，E 互动，长按 R 回溯。

signal oxygen_changed(value: float, max_value: float)
signal interact_prompt(text: String)
signal first_breath
signal died
signal checkpoint_saved
signal respawned
signal rope_result(success: bool, needed_pct: float)

const SPEED := 260.0
const ACCEL := 1800.0
const FRICTION := 2200.0
const GRAVITY := 1500.0
const JUMP_VELOCITY := -430.0
const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.12

const WATER_GRAVITY := 160.0
const WATER_DRAG := 3.2
const SWIM_ACCEL := 900.0
const SWIM_MAX_SPEED := 190.0
const STROKE_VELOCITY := -240.0
const BREACH_VELOCITY := -450.0  # 近水面时跳跃键蹬水出水（需跃上出水 25px+ 的台阶）
const STROKE_COOLDOWN := 0.45

# 救援绳索（第三章解锁）
const ROPE_RANGE := 800.0
const ROPE_SPEED := 1100.0
const ROPE_CHARGE_TIME := 1.0
const ROPE_WINDOW := 0.22

const HEAD_OFFSET := Vector2(0, -16)
const OXYGEN_MAX := 100.0
const OXYGEN_DRAIN := 5.0      # 满氧气约 20 秒
const OXYGEN_REFILL := 70.0
const HP_MAX := 100.0
const DROWN_DAMAGE := 30.0
const INTERACT_RADIUS := 90.0
const RESPAWN_DELAY := 0.9       # 溺水黑屏到回到存档点的间隔
const CHECKPOINT_MIN_MOVE := 400.0  # 存档点位移超过该距离才弹提示，避免水面扑腾刷屏

var oxygen := OXYGEN_MAX
var hp := HP_MAX
var facing := 1
var alive := true
var checkpoint_pos := Vector2.ZERO  # 最近一次浮出水面的位置（出生点为初始值）

# 绳索与搬运（第三章）
var rope_enabled := false
var rope_charging := false
var rope_charge := 0.0
var rope_needed := -1.0  # 蓄力中最近可救目标的所需力度（0~1，无目标 -1；HUD 画标记用）
var carried_bag = null

var _water: WaterBody
var _rope_line: Line2D
var _rope_state := ""  # ""/fly/reel
var _rope_tip := Vector2.ZERO
var _rope_victim: DrowningVictim = null
var _coyote := 0.0
var _jump_buffer := 0.0
var _stroke_cd := 0.0
var _head_under := false
var _in_water := false
var _breath_emitted := false
var _respawn_timer := 0.0
var _interact_target = null
var _last_prompt := "@@init@@"

func _ready() -> void:
	add_to_group("player")
	add_to_group("rewindables")
	_water = get_tree().get_first_node_in_group("water")
	checkpoint_pos = position

	var cs := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = 12.0
	cap.height = 42.0
	cs.shape = cap
	add_child(cs)

	var cam := Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 6.0
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = 4800
	cam.limit_bottom = 1600
	add_child(cam)

	_rope_line = Line2D.new()
	_rope_line.width = 3.0
	_rope_line.default_color = Color(0.95, 0.9, 0.75)
	_rope_line.z_index = 9
	_rope_line.visible = false
	add_child(_rope_line)

	queue_redraw()

func is_head_underwater() -> bool:
	return _head_under

func is_in_water() -> bool:
	return _in_water

func _physics_process(delta: float) -> void:
	queue_redraw()
	if RewindManager.rewinding:
		return
	_update_water_state()
	_update_oxygen(delta)
	if not alive:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
		move_and_slide()
		return
	if Input.is_action_pressed("rewind"):
		RewindManager.try_start_rewind()
	_update_movement(delta)
	move_and_slide()
	# 站在漂浮平台上时跟随其移动（手动乘载：加上平台本帧位移）
	if is_on_floor():
		var col := get_last_slide_collision()
		if col != null and col.get_collider() is MovingDebris:
			global_position += col.get_collider().current_velocity * delta
	_update_interaction()
	if rope_enabled:
		_update_rope(delta)

func _update_rope(delta: float) -> void:
	if _rope_state == "":
		_rope_line.visible = rope_charging
		if Input.is_action_just_pressed("rope"):
			rope_charging = true
			rope_charge = 0.0
		elif Input.is_action_pressed("rope") and rope_charging:
			rope_charge = minf(1.0, rope_charge + delta / ROPE_CHARGE_TIME)
		elif rope_charging and not Input.is_action_pressed("rope"):
			rope_charging = false
			try_throw_rope(rope_charge)
		if rope_charging:
			# 蓄力方向与距离预览
			var t := _nearest_victim()
			var d := ROPE_RANGE * rope_charge
			var dir := Vector2(facing, -0.15).normalized()
			if t != null:
				dir = (t.global_position - global_position).normalized()
				rope_needed = clampf(global_position.distance_to(
						t.global_position) / ROPE_RANGE, 0.1, 1.0)
			else:
				rope_needed = -1.0
			_rope_line.points = PackedVector2Array([Vector2.ZERO, dir * d])
		else:
			rope_needed = -1.0
		return
	# 飞行 / 收线
	_rope_line.visible = true
	if _rope_state == "fly" and _rope_victim != null and is_instance_valid(_rope_victim):
		_rope_tip = _rope_tip.lerp(_rope_victim.global_position, 16.0 * delta)
		if _rope_tip.distance_to(_rope_victim.global_position) < 26.0:
			_rope_victim.grab(self)
			if _rope_victim.state == 1:
				_rope_state = "reel"
			else:
				_reset_rope()  # 抓取失败（如通电水域）
	elif _rope_state == "reel" and _rope_victim != null and is_instance_valid(_rope_victim):
		_rope_tip = _rope_victim.global_position
		if _rope_victim.state >= 2:
			_reset_rope()
	else:
		_reset_rope()
	_rope_line.points = PackedVector2Array([Vector2.ZERO, to_local(_rope_tip)])

func try_throw_rope(charge: float) -> bool:
	var v := _nearest_victim()
	if v == null:
		rope_result.emit(false, -1.0)
		return false
	var needed := clampf(global_position.distance_to(v.global_position) / ROPE_RANGE, 0.1, 1.0)
	if absf(charge - needed) <= ROPE_WINDOW:
		_rope_victim = v
		_rope_tip = global_position
		_rope_state = "fly"
		return true
	rope_result.emit(false, needed)
	return false

func _nearest_victim() -> DrowningVictim:
	var best: DrowningVictim = null
	var bd := ROPE_RANGE
	for n in get_tree().get_nodes_in_group("victims"):
		if n is DrowningVictim and n.state == 0 and n.ropable:
			var d := global_position.distance_to(n.global_position)
			if d < bd:
				bd = d
				best = n
	return best

func _reset_rope() -> void:
	_rope_state = ""
	_rope_victim = null
	_rope_line.visible = false

func hurt(amount: float) -> void:
	if not alive:
		return
	hp -= amount
	if hp <= 0.0:
		_die()

func _update_water_state() -> void:
	if _water == null:
		return
	var was_under := _head_under
	var was_in_water := _in_water
	_in_water = _water.is_underwater(global_position)
	_head_under = _water.is_underwater(global_position + HEAD_OFFSET)
	if was_in_water == false and _in_water:
		Sfx.play("splash")
	if was_under and not _head_under:
		# 刚浮出水面：首次换气提示 + 自动存档
		if not _breath_emitted:
			_breath_emitted = true
			first_breath.emit()
		_save_checkpoint()

func _update_oxygen(delta: float) -> void:
	if _head_under:
		oxygen = maxf(0.0, oxygen - OXYGEN_DRAIN * delta)
		if oxygen <= 0.0:
			hp = maxf(0.0, hp - DROWN_DAMAGE * delta)
			if hp <= 0.0 and alive:
				_die()
	else:
		oxygen = minf(OXYGEN_MAX, oxygen + OXYGEN_REFILL * delta)
		hp = minf(HP_MAX, hp + DROWN_DAMAGE * 0.7 * delta)
	oxygen_changed.emit(oxygen, OXYGEN_MAX)

func _update_movement(delta: float) -> void:
	var dir := Input.get_axis("move_left", "move_right")
	if dir != 0.0:
		facing = 1 if dir > 0.0 else -1
	if _in_water:
		var swim := Vector2(dir, Input.get_axis("move_up", "move_down"))
		velocity += swim * SWIM_ACCEL * delta
		velocity += Vector2.DOWN * WATER_GRAVITY * delta
		velocity = velocity.lerp(Vector2.ZERO, clampf(WATER_DRAG * delta, 0.0, 1.0))
		# 蹬水/划水的向上冲量豁免限幅：limit_length 会逐帧削掉跳跃冲量，
		# 导致登不上出水 25px 的台阶/筏（ROADMAP 工程坑 6）
		if velocity.length() > SWIM_MAX_SPEED and velocity.y > -SWIM_MAX_SPEED:
			velocity = velocity.limit_length(SWIM_MAX_SPEED)
		_stroke_cd = maxf(0.0, _stroke_cd - delta)
		if Input.is_action_just_pressed("jump") and _stroke_cd <= 0.0:
			# 头已在水面之上：蹬水跃出，方便登上筏/箱子；否则普通划水
			velocity.y = BREACH_VELOCITY if not _head_under else STROKE_VELOCITY
			_stroke_cd = STROKE_COOLDOWN
	else:
		if dir != 0.0:
			velocity.x = move_toward(velocity.x, dir * SPEED, ACCEL * delta)
		else:
			velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		velocity.y += GRAVITY * delta
		_coyote = COYOTE_TIME if is_on_floor() else maxf(0.0, _coyote - delta)
		if Input.is_action_just_pressed("jump"):
			_jump_buffer = JUMP_BUFFER
		else:
			_jump_buffer = maxf(0.0, _jump_buffer - delta)
		if _jump_buffer > 0.0 and _coyote > 0.0:
			velocity.y = JUMP_VELOCITY
			_jump_buffer = 0.0
			_coyote = 0.0

func _update_interaction() -> void:
	var best = null
	var best_d := INTERACT_RADIUS
	for n in get_tree().get_nodes_in_group("interactables"):
		if is_instance_valid(n) and n.has_method("interact"):
			var d := global_position.distance_to(n.global_position)
			if d < best_d:
				best = n
				best_d = d
	_interact_target = best
	var label := ""
	if best != null:
		label = str(best.get_meta("interact_label", "互动"))
	elif rope_enabled:
		var v := _nearest_victim()
		if v != null:
			label = "长按 Q 蓄力抛绳 · 蓄力条到标记处松手"
	if label != _last_prompt:
		_last_prompt = label
		interact_prompt.emit(label)
	if best != null and Input.is_action_just_pressed("interact"):
		best.interact(self)

func _die() -> void:
	alive = false
	velocity = Vector2.ZERO
	_respawn_timer = RESPAWN_DELAY
	died.emit()

func _save_checkpoint() -> void:
	var moved := global_position.distance_to(checkpoint_pos) >= CHECKPOINT_MIN_MOVE
	checkpoint_pos = global_position
	if moved:
		checkpoint_saved.emit()

func _respawn() -> void:
	# 溺水死亡：不倒带，直接回到最近一次浮出水面的位置，满状态复活
	position = checkpoint_pos
	velocity = Vector2.ZERO
	oxygen = OXYGEN_MAX
	hp = HP_MAX
	alive = true
	RewindManager.clear_history()  # 防止复活后立刻长按R又倒回溺死点
	# 正在跟随的幸存者一起带回，避免她被留在墙后
	for n in get_tree().get_nodes_in_group("survivor"):
		if n.state == Survivor.State.FOLLOWING:
			n.global_position = checkpoint_pos + Vector2(-48.0, 0.0)
			n.velocity = Vector2.ZERO
	respawned.emit()

func capture_state() -> Dictionary:
	return {"pos": position, "vel": velocity, "facing": facing, "oxygen": oxygen, "hp": hp, "alive": alive}

func restore_state(s: Dictionary) -> void:
	position = s["pos"]
	velocity = s["vel"]
	facing = s["facing"]
	oxygen = s["oxygen"]
	hp = s["hp"]
	alive = s["alive"]
	queue_redraw()

func _draw() -> void:
	var skin := Color(0.96, 0.66, 0.58) if alive else Color(0.55, 0.45, 0.45)
	# 头发
	draw_circle(Vector2(-2.0 * facing, -16.0), 9.0, Color(0.25, 0.22, 0.3))
	# 头
	draw_circle(Vector2(0, -12.0), 9.0, skin)
	# 身体
	var cloth := Color(0.35, 0.55, 0.85) if alive else Color(0.4, 0.4, 0.45)
	draw_rect(Rect2(-8.0, -2.0, 16.0, 18.0), cloth)
	# 红围巾（标志色）
	draw_rect(Rect2(-7.0, -3.0, 14.0, 4.0), Color(0.9, 0.35, 0.4))
	# 眼睛
	draw_circle(Vector2(4.0 * facing, -12.0), 2.0, Color(0.1, 0.1, 0.12))
