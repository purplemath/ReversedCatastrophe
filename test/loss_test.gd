extends Node
## 失落路线测试（headless 用）：只救第一位 → 水位倒计时超时 → 第二位永久 LOST → 遗憾结局对白。
## 运行：Godot --headless --path . res://test/loss_test.tscn

var main: Node2D
var frames := 0
var phase := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)

func _physics_process(_delta: float) -> void:
	frames += 1
	var p: Player = main.town.player
	match phase:
		0:
			if frames >= 10:
				for i in 8:
					main.hud._advance_dialogue()
				phase = 1
		1:
			if frames == 30:
				p.global_position = Vector2(1735, 1300)
				Input.action_press("interact")
			if frames == 32:
				Input.action_release("interact")
				p.global_position = Vector2(4380, 470)
				main.town.survivors[0].global_position = Vector2(4300, 505)
				phase = 2
		2:
			if GameState.rescued_count >= 1 and main.hud.is_dialogue_visible():
				for i in 3:
					main.hud._advance_dialogue()
				phase = 3
			elif frames > 200:
				push_error("TEST S1 delivery failed")
				phase = 99
		3:
			if main.hud.is_card_visible():
				main.hud._close_card()
				GameState.rising_timer = 3.0  # 加速倒计时：3 秒后超时
				phase = 4
			elif frames > 300:
				push_error("TEST card1 failed")
				phase = 99
		4:
			if GameState.lost_count >= 1:
				var s2: Survivor = main.town.survivors[1]
				print("TEST s2 state=", s2.state, " visible=", s2.visible,
					" lost=", GameState.lost_count)
				if s2.state != Survivor.State.LOST:
					push_error("TEST S2 not LOST")
				if s2.visible:
					push_error("TEST S2 should be hidden after lost")
				phase = 5
			elif frames > 800:
				push_error("TEST rising timeout never fired")
				phase = 99
		5:
			if main.hud.is_dialogue_visible():  # 遗憾结局分支
				for i in 3:
					main.hud._advance_dialogue()
				print("TEST lost-epilogue done, rescued=", GameState.rescued_count,
					" lost=", GameState.lost_count, " paused=", get_tree().paused)
				if GameState.lost_count != 1 or get_tree().paused:
					push_error("TEST lost epilogue state wrong")
				else:
					print("TEST OK")
				get_tree().quit()
			elif frames > 1100:
				push_error("TEST lost epilogue never appeared")
				get_tree().quit()
		99:
			if frames >= 1200:
				get_tree().quit()
