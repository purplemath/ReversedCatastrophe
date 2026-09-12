extends Node
## 第三章「灾变的链条」专项测试：抛绳救援、沙袋堵流、断电闸、洪峰冲走、监控台真相。
## 运行：Godot --headless --path . res://test/chapter3_test.tscn

var main: Node2D
var frames := 0
var phase := 0
var _cut_checked := false

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
			if frames >= 10:
				var bag_count := 0
				for c in main.town.get_children():
					if c is SandbagPickup:
						bag_count += 1
				print("TEST ch3 water=", main.town.water_y, " victims=", main.town.victims.size(),
					" bags=", bag_count, " rope=", p.rope_enabled, " rising=", GameState.rising_active)
				if not is_equal_approx(main.town.water_y, 1150.0):
					push_error("TEST ch3 water_y wrong")
				if main.town.victims.size() != 5:
					push_error("TEST ch3 victims != 5")
				if bag_count != 3:
					push_error("TEST ch3 bags != 3")
				if not p.rope_enabled:
					push_error("TEST ch3 rope not enabled")
				if not GameState.rising_active:
					push_error("TEST ch3 rising not active")
				if main.town.victims[3].ropable:
					push_error("TEST ch3 electric victim ropable while powered")
				for i in 5:
					main.hud._advance_dialogue()
				phase = 1
		1:
			# 抛绳救起第一位（距约300px，需要约38%蓄力）
			if frames == 30:
				p.global_position = Vector2(600, 1200)
				if not p.try_throw_rope(0.38):
					push_error("TEST rope throw A rejected")
			if GameState.rescued_count >= 1 and main.hud.is_dialogue_visible():
				for i in 2:
					main.hud._advance_dialogue()  # 第三章首救对白 2 句
				print("TEST rope rescue A ok, hist=", RewindManager.history_frames())
				phase = 2
			elif frames > 300:
				push_error("TEST rope A never rescued")
				phase = 99
		2:
			if main.hud.is_card_visible():
				main.hud._close_card()
				phase = 3
			elif frames > 400:
				push_error("TEST card A fail")
				phase = 99
		3:
			# 三个沙袋搬到决口（每个：到袋子旁按E → 到决口按E）
			if frames == 100:
				p.global_position = Vector2(600, 1210)
				Input.action_press("interact")
			elif frames == 102:
				Input.action_release("interact")
				if p.carried_bag == null:
					push_error("TEST bag1 not carried")
				p.global_position = Vector2(3060, 1300)
			elif frames == 112:
				Input.action_press("interact")
			elif frames == 114:
				Input.action_release("interact")
				if main.town.bags_placed != 1:
					push_error("TEST bag1 not placed")
				p.global_position = Vector2(1600, 1200)
			elif frames == 130:
				Input.action_press("interact")
			elif frames == 132:
				Input.action_release("interact")
				p.global_position = Vector2(3060, 1300)
			elif frames == 142:
				Input.action_press("interact")
			elif frames == 144:
				Input.action_release("interact")
				p.global_position = Vector2(2920, 1210)
			elif frames == 162:
				Input.action_press("interact")
			elif frames == 164:
				Input.action_release("interact")
				p.global_position = Vector2(3060, 1300)
			elif frames == 174:
				Input.action_press("interact")
			elif frames == 176:
				Input.action_release("interact")
				print("TEST bags placed=", main.town.bags_placed, " gap_force=", main.town.gap_force)
				if main.town.bags_placed != 3 or main.town.gap_force != 0.0:
					push_error("TEST sandbags incomplete")
				phase = 4
		4:
			# 按住 E 断电（1.6 秒）
			if frames == 200:
				p.global_position = Vector2(3260, 1219)
				Input.action_press("interact")
			if frames == 205 and not _cut_checked:
				_cut_checked = true
				if main.town._switch_box.powered:
					pass  # 仍在充能，正常
			if frames == 310:
				Input.action_release("interact")
				if main.town._switch_box.powered:
					push_error("TEST power still on")
				else:
					print("TEST power cut ok")
				if not main.town.victims[3].ropable:
					push_error("TEST victim still not ropable after power cut")
				phase = 5
		5:
			# 抛绳救起中段落水者（岩石上近距离）
			if frames == 330:
				p.global_position = Vector2(2300, 1229)
				if not p.try_throw_rope(0.1):
					push_error("TEST rope throw B rejected")
			if GameState.rescued_count >= 2 and main.hud.is_card_visible():
				main.hud._close_card()
				print("TEST rope rescue B ok")
				phase = 6
			elif frames > 600:
				push_error("TEST rope B failed")
				phase = 99
		6:
			# 加速洪峰 → 剩余两人被冲走 → 监控台解锁
			if frames == 340:
				GameState.rising_timer = 1.0
			if GameState.lost_count >= 2:
				print("TEST flood washed away, lost=", GameState.lost_count,
					" v3.state=", main.town.victims[3].state, " console=", main.town._console.unlocked)
				if main.town.victims[3].state != 3:
					push_error("TEST victim not washed")
				if not main.town._console.unlocked:
					push_error("TEST console not unlocked")
				phase = 7
			elif frames > 900:
				push_error("TEST flood timeout never fired")
				phase = 99
		7:
			if frames == 700:
				p.global_position = Vector2(4600, 670)
				Input.action_press("interact")
			if frames == 702:
				Input.action_release("interact")
			if main.hud.is_dialogue_visible():
				for i in 5:
					main.hud._advance_dialogue()  # 监控台真相 5 句
				print("TEST ch3 ending done, rescued=", GameState.rescued_count,
					" lost=", GameState.lost_count, " paused=", get_tree().paused)
				if get_tree().paused:
					push_error("TEST still paused after ending")
				# 结局3秒后会自动切换第四章（场景切换销毁测试节点），先断言再退出
				# A区两名落水者只救了1个（900处），1250处与C区两名被冲走
				if GameState.rescued_count == 2 and GameState.lost_count == 3:
					print("TEST OK")
				else:
					push_error("TEST ch3 final state wrong")
				phase = 8
			elif frames > 1100:
				push_error("TEST console ending never appeared")
				phase = 99
		8:
			if frames >= 760:
				get_tree().quit()
		99:
			if frames >= 1200:
				get_tree().quit()
