extends Node
## 第二章「洪水之夜」专项测试：雨夜环境、开场倒计时、居民疏散、洪水灌入、A2 线索结局。
## 运行：Godot --headless --path . res://test/chapter2_test.tscn

var main: Node2D
var frames := 0
var phase := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ChapterManager.current = 2
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)

func _physics_process(_delta: float) -> void:
	frames += 1
	var p: Player = main.town.player
	match phase:
		0:
			if frames >= 10:
				var rain := false
				for c in main.town.get_children():
					if c is RainFx:
						rain = true
				print("TEST ch2 water_y=", main.town.water_y, " rain=", rain,
					" rising=", GameState.rising_active, " t=", snappedf(GameState.rising_timer, 1.0),
					" residents=", main.town.survivors.size())
				if not is_equal_approx(main.town.water_y, 1100.0):
					push_error("TEST ch2 water_y wrong")
				if not rain:
					push_error("TEST ch2 rain missing")
				if not GameState.rising_active:
					push_error("TEST ch2 rising not started")
				if main.town.survivors.size() != 3:
					push_error("TEST ch2 residents != 3")
				for i in 5:
					main.hud._advance_dialogue()  # 第二章开场白 5 句
				print("TEST ch2 intro done, paused=", get_tree().paused)
				phase = 1
		1:
			# 疏散第一位居民（旅馆门前）
			if frames == 30:
				p.global_position = Vector2(520, 1120)
				Input.action_press("interact")
			if frames == 32:
				Input.action_release("interact")
				var r0: Survivor = main.town.survivors[0]
				if r0.state != Survivor.State.FOLLOWING:
					push_error("TEST ch2 interact resident failed")
				p.global_position = Vector2(4380, 975)  # 高地台阶2 顶部
				r0.global_position = Vector2(4000, 1110)
				phase = 2
		2:
			if GameState.rescued_count >= 1 and main.hud.is_dialogue_visible():
				for i in 3:
					main.hud._advance_dialogue()
				print("TEST ch2 first evacuation done @", frames,
					" resident_pos=", main.town.survivors[0].global_position)
				phase = 3
			elif frames > 400:
				push_error("TEST ch2 evacuation failed @ resident="
					+ str(main.town.survivors[0].global_position))
				phase = 99
		3:
			if main.hud.is_card_visible():
				main.hud._close_card()
				GameState.rising_timer = 2.0  # 加速洪水
				phase = 4
			elif frames > 500:
				push_error("TEST ch2 card failed")
				phase = 99
		4:
			if GameState.lost_count >= 2:  # 其余两名居民未撤离 → 洪水后 LOST
				print("TEST ch2 flood timeout, lost=", GameState.lost_count,
					" surface=", main.town._water.surface_y)
				if GameState.lost_count != 2:
					push_error("TEST ch2 lost count wrong")
				phase = 5
			elif frames > 1000:
				push_error("TEST ch2 flood timeout never fired")
				phase = 99
		5:
			if main.hud.is_dialogue_visible():  # 第二章结局（含 A2 线索，4 句）
				for i in 4:
					main.hud._advance_dialogue()
				print("TEST ch2 epilogue done, rescued=", GameState.rescued_count,
					" lost=", GameState.lost_count, " paused=", get_tree().paused)
				if get_tree().paused:
					push_error("TEST ch2 still paused after epilogue")
				# 结局3秒后会自动切换第三章（场景切换会销毁测试节点），先断言再退出
				if GameState.rescued_count == 1 and GameState.lost_count == 2:
					print("TEST OK")
				else:
					push_error("TEST ch2 final state wrong")
				phase = 6
			elif frames > 1200:
				push_error("TEST ch2 epilogue never appeared")
				phase = 99
		6:
			if frames >= 450:
				get_tree().quit()
		99:
			if frames >= 1400:
				get_tree().quit()
