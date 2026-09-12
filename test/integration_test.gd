extends Node
## 集成测试（headless 用）：完整驱动一局——
## 对白→游泳→回溯→存档点复活→涵洞穿越→平台乘载→双幸存者救援→水位倒计时→分支结局→图鉴→暂停。
## 运行：Godot --headless --path . res://test/integration_test.tscn

const SURVIVOR_SPAWNS: Array[Vector2] = [Vector2(1800.0, 1300.0), Vector2(2900.0, 1180.0)]

var main: Node2D
var frames := 0
var phase := 0
var _ride_start_x := 0.0
var _ride_max_dev := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # 暂停期间也要能驱动
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.town.player.died.connect(func(): print("SIGNAL died @", frames))

func _physics_process(_delta: float) -> void:
	frames += 1
	var p: Player = main.town.player
	match phase:
		0:
			if frames >= 10:
				for i in 8:
					main.hud._advance_dialogue()
				print("TEST intro done")
				phase = 1
		1:
			if frames == 20:
				Input.action_press("move_right")
				Input.action_press("move_up")
			if frames >= 130:
				Input.action_release("move_right")
				Input.action_release("move_up")
				phase = 2
		2:
			if not RewindManager.try_start_rewind():
				push_error("TEST manual rewind failed")
			phase = 3
		3:
			if frames >= 240:
				phase = 4
		4:
			# 存档点验证：水面存档 → 深处溺死 → 存档点满状态复活
			if frames == 250:
				p.global_position = Vector2(1000, 400)
				p._save_checkpoint()
			elif frames >= 251:
				p.global_position = Vector2(1000, 1200)
				p.oxygen = 0.0
				p.hp = 0.05
				phase = 5
		5:
			if p.alive and frames > 260:
				var dist := p.global_position.distance_to(Vector2(1000, 400))
				print("TEST respawn at ", p.global_position, " oxy=", p.oxygen)
				if dist > 60.0:
					push_error("TEST respawn not at checkpoint")
				if p.oxygen < 99.0:
					push_error("TEST oxygen not refilled")
				p.global_position = Vector2(2500, 1150)
				Input.action_press("move_right")
				phase = 6
			elif frames > 420:
				push_error("TEST respawn never happened")
				p.global_position = Vector2(2500, 1150)
				Input.action_press("move_right")
				phase = 6
		6:
			if p.global_position.x > 3400.0:
				Input.action_release("move_right")
				print("TEST tunnel passed @", frames, " ", p.global_position)
				phase = 7
			elif frames > 660:
				Input.action_release("move_right")
				push_error("TEST tunnel blocked")
				phase = 7
		7:
			# 平台乘载验证：站上第一个漂浮平台
			var debris := _first_platform()
			if debris == null:
				push_error("TEST no moving platform found")
				phase = 8
			else:
				p.global_position = debris.global_position + Vector2(0, -34)
				_ride_start_x = p.global_position.x
				phase = 71
		71:
			var dev := absf(p.global_position.x - _ride_start_x)
			if dev > _ride_max_dev:
				_ride_max_dev = dev
			if frames >= 660:
				print("TEST platform ride max_dev=", snappedf(_ride_max_dev, 1.0))
				if _ride_max_dev < 40.0:
					push_error("TEST platform did not carry player")
				phase = 8
		8:
			if frames == 690:
				for i in main.town.survivors.size():
					var s: Survivor = main.town.survivors[i]
					var d := s.global_position.distance_to(SURVIVOR_SPAWNS[i])
					print("TEST survivor", i, " drift=", snappedf(d, 0.1), " state=", s.state)
					if d > 90.0:
						push_error("TEST survivor displaced")
				phase = 9
		9:
			if frames == 700:
				p.global_position = Vector2(1735, 1300)
				Input.action_press("interact")
			if frames == 702:
				Input.action_release("interact")
				var s1: Survivor = main.town.survivors[0]
				if s1.state != Survivor.State.FOLLOWING:
					push_error("TEST interact S1 failed")
				phase = 10
		10:
			# 送达第一位 → 启动水位倒计时 + 首救对白
			if frames == 710:
				p.global_position = Vector2(4380, 470)
				main.town.survivors[0].global_position = Vector2(4050, 540)
			if GameState.rescued_count >= 1 and main.hud.is_dialogue_visible():
				for i in 3:
					main.hud._advance_dialogue()
				print("TEST S1 rescued, rising=", GameState.rising_active,
					" t=", snappedf(GameState.rising_timer, 1.0))
				if not GameState.rising_active:
					push_error("TEST rising timer not started")
				phase = 11
			elif frames > 950:
				push_error("TEST S1 delivery failed")
				phase = 99
		11:
			if main.hud.is_card_visible():
				main.hud._close_card()
				print("TEST card1 closed")
				phase = 12
			elif frames > 1000:
				push_error("TEST card1 never appeared")
				phase = 99
		12:
			# 倒计时进行中救援第二位
			if frames == 780:
				p.global_position = Vector2(2840, 1240)
				Input.action_press("interact")
			if frames == 782:
				Input.action_release("interact")
				var s2: Survivor = main.town.survivors[1]
				if s2.state != Survivor.State.FOLLOWING:
					push_error("TEST interact S2 failed")
				p.global_position = Vector2(4380, 470)
				s2.global_position = Vector2(4050, 540)
				phase = 13
		13:
			if GameState.rescued_count >= 2 and main.hud.is_card_visible():
				main.hud._close_card()
				print("TEST S2 rescued, rising=", GameState.rising_active)
				phase = 14
			elif frames > 1050:
				push_error("TEST S2 delivery/card failed")
				phase = 99
		14:
			if main.hud.is_dialogue_visible():  # 完美结局对白
				for i in 3:
					main.hud._advance_dialogue()
				if get_tree().paused:
					push_error("TEST still paused after epilogue")
				else:
					print("TEST epilogue done, rescued=", GameState.rescued_count,
						" lost=", GameState.lost_count)
				if GameState.rising_active:
					push_error("TEST rising still active after all rescued")
				# 结局3秒后会自动切换第二章（begin_chapter 清本章计数），先做最终断言
				if GameState.rescued_count == 2 and GameState.lost_count == 0 \
						and is_equal_approx(RewindManager.max_seconds, 20.0):
					print("TEST final state ok")
				else:
					push_error("TEST final state wrong")
				phase = 15
			elif frames > 1150:
				push_error("TEST epilogue never appeared")
				phase = 99
		15:
			if frames == 870:
				main.pause_menu.pause_game()
				main.pause_menu._open_gallery()
				var gs: Dictionary = main.pause_menu.gallery_status()
				print("TEST gallery=", gs)
				if gs.unlocked != 2:
					push_error("TEST gallery unlocked != 2")
				main.pause_menu._close_gallery()
				main.pause_menu.resume_game()
			if frames == 890:
				main.pause_menu.pause_game()
				if not get_tree().paused:
					push_error("TEST pause failed")
				main.pause_menu.resume_game()
				print("TEST pause/resume ok")
			if frames >= 920:
				print("TEST OK")
				get_tree().quit()
		99:
			if frames >= 1250:
				get_tree().quit()

func _first_platform() -> MovingDebris:
	for c in main.town.get_children():
		if c is MovingDebris:
			return c
	return null
