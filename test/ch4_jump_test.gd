extends Node
## 第四章全路线真实测试（零传送）：模拟玩家操作（按住右 / 卡住自动跳），
## 从出生点 (370,1240) 走完整旱路：旅馆出门→水务站门→商店内（线索3区域）→
## 商店右门→高楼垫脚板→水道→装置旁。水路地图干涸后的通行性回归全靠它。
var main: Node2D
var frames := 0
var phase := 0
var started := false
var last_x := -9999.0
var last_progress := 0
var jump_cd := 0.0
var _jump_held := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ChapterManager.current = 4
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)

func _physics_process(delta: float) -> void:
	frames += 1
	if frames == 12:
		var guard := 0
		while get_tree().paused and guard < 12:
			main.hud._advance_dialogue()
			guard += 1
		started = true
		last_progress = frames
	if not started:
		return
	var p: Player = main.town.player
	Input.action_press("move_right")

	# 卡住检测：90 帧无水平进展 → 跳一下（0.8s 冷却）
	if p.global_position.x > last_x + 8.0:
		last_x = p.global_position.x
		last_progress = frames
	jump_cd -= delta
	if frames - last_progress > 90 and jump_cd <= 0.0 and p.is_on_floor():
		Input.action_press("jump")
		Input.action_release("jump")  # 同帧按下+释放（下一帧释放会丢 just_pressed 边沿）
		jump_cd = 0.8  # 秒（jump_cd 按秒递减，别写成帧数）
		print("JUMP f=%d y=%.0f" % [frames, p.global_position.y])

	if frames % 120 == 0:
		print("ROUTE f=%d pos=(%.0f,%.0f) floor=%s stuck=%d cd=%.0f" % [
			frames, p.global_position.x, p.global_position.y, p.is_on_floor(),
			frames - last_progress, jump_cd])

	# 到达装置附近即成功
	if p.global_position.x >= 2860.0 and p.global_position.y < 1310.0:
		Input.action_release("move_right")
		var dist: float = p.global_position.distance_to(Vector2(2950, 1270))
		if dist < 120.0:
			print("ROUTE-TEST OK: 出生点零传送走到装置 dist=%.0f f=%d" % [dist, frames])
		else:
			push_error("ROUTE-TEST FAIL: 位置异常 dist=%.0f pos=%s" % [dist, p.global_position])
		phase = 99
		get_tree().quit()
	if frames > 5400:
		Input.action_release("move_right")
		push_error("ROUTE-TEST FAIL: 卡死 pos=%s floor=%s" % [
			p.global_position, p.is_on_floor()])
		get_tree().quit()
