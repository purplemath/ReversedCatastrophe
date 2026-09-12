extends Node
## 第三章抛绳救援真实输入测试：Input.action_press("rope") 按住精确帧数再松开，
## 验证 蓄力→抛出→收线→获救 整条真实输入链路（chapter3_test 是直接调 try_throw_rope）。
var main: Node2D
var frames := 0
var phase := 0
var hold_frames := 0
var pressed_at := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ChapterManager.current = 3
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)

func _physics_process(_d: float) -> void:
	frames += 1
	var p: Player = main.town.player
	match phase:
		0:
			if frames == 12:
				for i in 5:
					main.hud._advance_dialogue()
			if frames == 20:
				p.global_position = Vector2(600, 1200)  # victim0 (900,1180) 距离约300
				var v: DrowningVictim = main.town.victims[0]
				var needed := clampf(p.global_position.distance_to(
						v.global_position) / p.ROPE_RANGE, 0.1, 1.0)
				hold_frames = int(round(needed * 60.0))  # 精确蓄力帧数
				print("ROPE dist=%.0f needed=%.2f hold=%d帧" % [
					p.global_position.distance_to(v.global_position), needed, hold_frames])
				Input.action_press("rope")
				pressed_at = frames
				phase = 1
		1:  # 按住中：确认蓄力在涨
			if p.rope_charge <= 0.0 and frames > pressed_at + 2:
				push_error("ROPE-TEST FAIL: 蓄力没有累积 (charge=%.2f)" % p.rope_charge)
				phase = 99
			if frames == pressed_at + hold_frames:
				Input.action_release("rope")
				phase = 2  # 等2帧再判定（测试节点先于 player 执行）
		2:  # 等待收线完成
			if frames == pressed_at + hold_frames + 2:
				print("ROPE released charge=%.2f state=%s" % [p.rope_charge, p._rope_state])
				if p._rope_state != "fly":
					push_error("ROPE-TEST FAIL: 松开后绳索未飞出 state=%s charge=%.2f" % [
						p._rope_state, p.rope_charge])
					phase = 99
			if GameState.rescued_count >= 1:
				print("ROPE-TEST OK: 真实输入链路获救成功，v0.state=%d" % main.town.victims[0].state)
				phase = 3
			elif frames > pressed_at + 400:
				push_error("ROPE-TEST FAIL: 绳索未拉回获救 v0.state=%d rope_state=%s" % [
					main.town.victims[0].state, p._rope_state])
				phase = 99
		3:
			if frames >= pressed_at + 420:
				get_tree().quit()
		99:
			if frames >= pressed_at + 430:
				get_tree().quit()
	if frames > 900:
		get_tree().quit()
