extends Node
## 第四章「逆转的天灾」专项测试：三线索、装置拆除、站长疏散、时间回卷、最终抉择、结局+尾声。
## 运行：Godot --headless --path . res://test/chapter4_test.tscn

var main: Node2D
var frames := 0
var phase := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ChapterManager.current = 4
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)

func _press_e() -> void:
	Input.action_press("interact")

func _release_e() -> void:
	Input.action_release("interact")

func _physics_process(_d: float) -> void:
	frames += 1
	var p: Player = main.town.player
	match phase:
		0:
			if frames >= 10:
				var clues := 0
				for c in main.town.get_children():
					if c is ClueSpot:
						clues += 1
				print("TEST ch4 water=", main.town.water_y, " survivors=", main.town.survivors.size(),
					" clues=", clues, " device_on=", main.town._device.powered,
					" rising=", GameState.rising_active, " day=", main.town.ch4_day)
				if not is_equal_approx(main.town.water_y, 1600.0):
					push_error("TEST ch4 water_y wrong")
				if main.town.survivors.size() != 1:
					push_error("TEST ch4 chief missing")
				if clues != 3:
					push_error("TEST ch4 clues != 3")
				if not main.town._device.powered:
					push_error("TEST ch4 device not armed")
				if not GameState.rising_active:
					push_error("TEST ch4 day timer not running")
				for i in 5:
					main.hud._advance_dialogue()
				phase = 1
		1:
			# 线索1（水务站）
			if frames == 30:
				p.global_position = Vector2(1050, 1330)
				_press_e()
			if frames == 32:
				_release_e()
				if main.town.ch4_clues != 1:
					push_error("TEST clue1 not collected")
				GameState.rising_timer = 1.0  # 触发时间回卷
				phase = 2
		2:
			# 回卷：day+1，装置重布，玩家回出生点，站长仍待岗
			if main.town.ch4_day == 2:
				print("TEST loop reset ok, player=", p.global_position,
					" device_on=", main.town._device.powered)
				if p.global_position.distance_to(Vector2(370, 1240)) > 60.0:
					push_error("TEST player not reset to spawn")
				if not main.town._device.powered:
					push_error("TEST device not rearmed")
				if main.town.survivors[0].state != Survivor.State.TRAPPED:
					push_error("TEST chief state wrong after loop")
				if main.town.ch4_clues != 1:
					push_error("TEST clues lost after loop")
				phase = 3
			elif frames > 300:
				push_error("TEST loop never triggered")
				phase = 99
		3:
			# 线索2（旅馆前台）与线索3（商店）
			if frames == 130:
				p.global_position = Vector2(520, 1290)
				_press_e()
			elif frames == 132:
				_release_e()
			elif frames == 150:
				p.global_position = Vector2(1800, 1300)
				_press_e()
			elif frames == 152:
				_release_e()
				print("TEST clues=", main.town.ch4_clues)
				if main.town.ch4_clues != 3:
					push_error("TEST clues != 3")
				phase = 4
		4:
			# 按住 E 拆除装置（2秒以上）
			if frames == 200:
				p.global_position = Vector2(2930, 1270)
				_press_e()
			if frames == 400:
				_release_e()
				if main.town._device.powered:
					push_error("TEST device not disarmed")
				else:
					print("TEST device disarmed")
				phase = 5
		5:
			# 劝说站长 → 带到集合点（站在站长正上方，避开桌面线索点的交互半径）
			if frames == 430:
				p.global_position = Vector2(1100, 1345)
				_press_e()
			if frames == 432:
				_release_e()
				if main.town.survivors[0].state != Survivor.State.FOLLOWING:
					push_error("TEST chief not following")
				p.global_position = Vector2(4380, 1330)
				main.town.survivors[0].global_position = Vector2(4050, 1330)
				phase = 6
		6:
			# 送达 → 首救对白（1句）→ 知识卡
			if GameState.rescued_count >= 1 and main.hud.is_dialogue_visible():
				main.hud._advance_dialogue()
				phase = 7
			elif frames > 900:
				push_error("TEST chief delivery failed")
				phase = 99
		7:
			if main.hud.is_card_visible():
				main.hud._close_card()
				phase = 8
			elif frames > 1000:
				push_error("TEST card failed")
				phase = 99
		8:
			# 三目标完成 → 最终抉择对白（3句）
			if main.hud.is_dialogue_visible():
				for i in 3:
					main.hud._advance_dialogue()
				if not main._choice_pending:
					push_error("TEST choice not pending")
				phase = 9
			elif frames > 1100:
				push_error("TEST choice dialogue never appeared")
				phase = 99
		9:
			# 直接调用抉择（等价按1）→ 结局A（完美逆转，4句）
			main.choose_ending(1)
			if main.hud.is_dialogue_visible():
				for i in 4:
					main.hud._advance_dialogue()
				phase = 10
			elif frames > 1200:
				push_error("TEST ending never appeared")
				phase = 99
		10:
			# 尾声（3句）→ 解除暂停
			if main.hud.is_dialogue_visible():
				for i in 3:
					main.hud._advance_dialogue()
				print("TEST ch4 ending done, paused=", get_tree().paused,
					" rescued_total=", GameState.rescued_total)
				if get_tree().paused:
					push_error("TEST still paused after epilogue")
				if GameState.rescued_total < 1:
					push_error("TEST rescued_total wrong")
				print("TEST OK")
				phase = 11
			elif frames > 1300:
				push_error("TEST epilogue never appeared")
				phase = 99
		11:
			# 在 8 秒自动返回标题前退出（场景切换会销毁测试节点）
			if frames >= 1400:
				get_tree().quit()
		99:
			if frames >= 1400:
				get_tree().quit()
