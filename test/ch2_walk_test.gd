extends Node
## 第二章真实走路测试：模拟玩家操作（按住右 / 自动上浮 / 卡住自动下潜 / 周期蹬水），
## 从出生点 (370,1240) 一路走到避难高台 raft_zone。
## chapter2_test 是传送式测试，测不到"路是否真的走得通"——本测试补上这一环。
var main: Node2D
var frames := 0
var started := false
var mode := 0  # 0=游/走 1=下潜
var mode_until := 0
var last_x := -9999.0
var last_progress_frame := 0
var jump_cd := 0.0
var _jump_held := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ChapterManager.current = 2
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)

func _physics_process(delta: float) -> void:
	frames += 1
	if frames == 12:
		for i in 5:
			main.hud._advance_dialogue()  # 跳过开场白（暂停树）
		GameState.rising_timer = 999.0  # 排除洪水倒计时干扰，专注可通行性
		started = true
		last_progress_frame = frames
	if not started:
		return
	var p: Player = main.town.player
	Input.action_press("move_right")

	# 卡住检测：120 物理帧(2s) x 进展 < 12px → 下潜 72 帧(1.2s) 试试水底
	if p.global_position.x > last_x + 12.0:
		last_x = p.global_position.x
		last_progress_frame = frames
	if mode == 0 and frames - last_progress_frame > 120:
		mode = 1
		mode_until = frames + 72
		print("WALK stuck@x=%.0f → dive" % p.global_position.x)
	if mode == 1 and frames >= mode_until:
		mode = 0
		last_progress_frame = frames
	if mode == 1:
		Input.action_press("move_down")
		Input.action_release("move_up")
	else:
		Input.action_release("move_down")
		if p.is_in_water():
			Input.action_press("move_up")
		else:
			Input.action_release("move_up")

	# 水中周期按跳：头出水=蹬水跃出（登台阶/筏），头在水下=划水上浮
	jump_cd -= delta
	if p.is_in_water() and jump_cd <= 0.0 and mode == 0:
		Input.action_press("jump")
		_jump_held = true
		jump_cd = 0.5
	elif _jump_held:
		Input.action_release("jump")
		_jump_held = false

	if frames % 60 == 0:
		print("WALK f=%d pos=(%.0f,%.0f) water=%s floor=%s oxy=%.0f vx=%.0f mode=%d" % [
			frames, p.global_position.x, p.global_position.y, p.is_in_water(),
			p.is_on_floor(), p.oxygen, p.velocity.x, mode])

	if main.town.raft_zone.has_point(p.global_position) and p.is_on_floor():
		Input.action_release("move_right")
		Input.action_release("move_up")
		Input.action_release("move_down")
		print("WALK-TEST OK: %d 帧走到避难高台 pos=%s" % [frames, p.global_position])
		get_tree().quit()
	if frames > 5400:  # 90 秒物理时
		Input.action_release("move_right")
		Input.action_release("move_up")
		Input.action_release("move_down")
		push_error("WALK-TEST FAIL: 卡在 pos=%s water=%s oxy=%.0f" % [
			p.global_position, p.is_in_water(), p.oxygen])
		get_tree().quit()
