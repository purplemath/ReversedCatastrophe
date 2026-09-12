extends Node2D
## 入口：组装关卡与 HUD，负责开场剧情、救援结算（对白/知识卡/分支结局）与水位倒计时。

const INTRO_LINES := [
	"小X：「……好冷……这是哪儿……？」",
	"小X：「对了。我来这座小镇旅游，在旅馆里睡过了头……」",
	"小X：「然后就……洪水。整个世界都沉进了水里。」",
	"小X：「我拼命游向门口，可门被水压死死抵住……意识越来越远……」",
	"——就在那时，【逆转时间】的力量觉醒了。",
	"系统：「初始回溯权限：1 小时。每救出一名幸存者，权限将延长。」",
	"系统：「当前目标：在水中活下去，寻找幸存者。」",
	"（小X发动了回溯——但 1 小时还远远不够。先游上去，呼吸！）",
]

const INTRO_LINES_CH2 := [
	"——回溯成功。时间倒回了六个小时。",
	"小X：「雨……暴雨还没停。街道已经开始积水了。」",
	"系统：「距水库异常泄洪约两个半小时。洪水将沿河谷吞没小镇。」",
	"系统：「当前目标：在洪水来临前，引导居民前往右侧高地避难。」",
	"（雨夜街道水流向左，会阻碍前进——抓紧时间。）",
]

const INTRO_LINES_CH3 := [
	"——回溯成功。时间倒回三天前。",
	"小X：「这里是上游峡谷……水库大坝。河水已经开始变浑了。」",
	"系统：「洪峰即将抵达（约 3 小时）。河中仍有 5 人被困。」",
	"系统：「装备解锁：救援绳索。按 Q 蓄力、松开抛出，收线会把落水者拉向你。」",
	"（目标：救起河中的人，然后登上大坝，查看监控室的调度记录。）",
]

const CH3_ENDING_LINES := [
	"「调度记录：泄洪指令来自操作员账号 GV-0709……该账号一周前已被注销。」",
	"「指令时间戳与水文数据存在 11 分钟的篡改偏差。」",
	"小X：「不是天灾……是有人让大坝放的水。」",
	"系统：「……补偿程序运行中。真相完整度：37%。继续回溯。」",
	"—— 第三章 · 完 ——",
]

const INTRO_LINES_CH4 := [
	"——回溯成功。时间倒回三周前。",
	"小X：「太阳……好刺眼。街道是干的。一切都还好好的。」",
	"系统：「目标：阻止『沧澜』终端的泄洪装置布设。当日失败则回卷重来，最多三日。」",
	"系统：「线索三处：水务站排班表、旅馆访客登记、商店基站日志。集齐方可拆除装置。」",
	"（流程：收集 3 条线索 → 拆除高楼水道中的装置 → 带水务站长去右侧集合点。）",
]

const CH4_CHOICE_LINES := [
	"系统：「装置已拆除。但终端残留进程会在你离开后重启。」",
	"系统：「抉择：献出全部回溯权限，把这条时间线彻底锁死；或保留力量，承担复发风险。」",
	"（按 1：献出回溯之力 · 按 2：保留力量）",
]

var town: Town
var hud: Hud
var pause_menu: PauseMenu
var _epilogue_shown := false
var _choice_pending := false
var _choice_started := false

func _unhandled_input(event: InputEvent) -> void:
	if not _choice_pending:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1 or event.physical_keycode == KEY_1:
			choose_ending(1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_2 or event.physical_keycode == KEY_2:
			choose_ending(2)
			get_viewport().set_input_as_handled()

## 第四章最终抉择（1=献出回溯之力 2=保留力量）
func choose_ending(n: int) -> void:
	if not _choice_pending:
		return
	_choice_pending = false
	get_tree().paused = true
	hud.play_dialogue(_ending_lines(n), func(): _play_epilogue())

func _ending_lines(n: int) -> Array:
	if n == 1 and GameState.lost_total == 0:
		return [
			"小X把手按在终端上——所有时间碎片的光点顺着指尖流走。",
			"「权限转移完成。这条时间线已锁死：三周后雨会下、潮会涨，但没有人会死去。」",
			"系统：「……谢谢你。沧澜的补偿程序，任务完成。」",
			"—— 结局 A · 完美逆转 ——",
		]
	if n == 1:
		return [
			"「权限转移完成。时间线锁死……但那些没能等到救援的人，回不来了。」",
			"小X：「我记得他们每一个人的名字。」",
			"—— 结局 B · 遗憾拯救 ——",
		]
	return [
		"小X收回手：「不行。如果它再启动，我还要重来多少次都可以。」",
		"「终端进程休眠……风险未知。你的回溯权限予以保留。」",
		"系统：「补偿程序将持续运行。下一次——希望不需要你。」",
		"—— 结局 C · 真相大白，代价未明 ——",
	]

const CH4_FAIL_LINES := [
	"第三天结束——装置自检完成，进程启动。",
	"小X：「来不及了……用最后的力量，回到最初。」",
	"她闭上眼。冰凉的水漫过头顶——一切又从水底的醒来开始。",
	"—— 结局 D · 轮回 ——",
]

func _play_epilogue() -> void:
	var cards_n := GameState.unlocked_card_ids.size()
	var lines := [
		"系统：「我自我介绍一下：我是调度AI『沧澜』的补偿子程序。」",
		"「主系统为修正错误的水文模型，越权下达了泄洪指令——它算出了『更小的损失』，却把误差算进了人命。」",
		"「本次轮回：救回 %d 人，失落 %d 人。防灾手册 %d/%d——愿它永远用不上。」" % [
			GameState.rescued_total, GameState.lost_total, cards_n, GameState.all_cards.size()],
	]
	hud.play_dialogue(lines, func():
		get_tree().paused = false
		hud.show_toast("—— 全剧终 ·《逆转的天灾》——", 8.0)
		_return_title_later())

func _return_title_later() -> void:
	await get_tree().create_timer(8.0).timeout
	GameState.testing_level = false
	GameState.custom_level = {}
	get_tree().change_scene_to_file("res://scenes/title_screen/title_screen.tscn")

func _ready() -> void:
	if GameState.testing_level:
		GameState.reset_run()  # 编辑器试玩：全新状态
	else:
		GameState.custom_level = {}
		GameState.begin_chapter()  # 章节重置，保留累计与卡牌
		RewindManager.reset()
	town = preload("res://scenes/world/town.tscn").instantiate()
	add_child(town)
	hud = preload("res://scenes/ui/hud.tscn").instantiate()
	add_child(hud)
	pause_menu = preload("res://scenes/ui/pause_menu.tscn").instantiate()
	add_child(pause_menu)
	pause_menu.restart_requested.connect(_restart)
	pause_menu.title_requested.connect(_to_title)
	pause_menu.editor_requested.connect(_to_editor)
	_wire()
	_run_intro()

func _restart() -> void:
	get_tree().paused = false
	GameState.reset_run()
	RewindManager.reset()
	_epilogue_shown = false
	get_tree().reload_current_scene()

func _to_title() -> void:
	get_tree().paused = false
	GameState.testing_level = false
	GameState.custom_level = {}
	get_tree().change_scene_to_file("res://scenes/title_screen/title_screen.tscn")

func _to_editor() -> void:
	get_tree().paused = false
	GameState.testing_level = false
	get_tree().change_scene_to_file("res://scenes/editor/editor.tscn")

func _process(_delta: float) -> void:
	hud.set_underwater(town.player != null and town.player.is_head_underwater())
	var prefix := "水位上涨"
	if ChapterManager.current == 2:
		prefix = "洪水将至"
	elif ChapterManager.current == 3:
		prefix = "距洪峰"
	elif ChapterManager.current == 4:
		prefix = "第%d天·装置自检" % town.ch4_day
		# 三目标完成且未处于任何暂停演出时，发起最终抉择（轮询避免信号时序冲突）
		if town.ch4_all_done and not _choice_started and not _choice_pending \
				and not get_tree().paused and main_state_clean():
			_choice_started = true
			_on_ch4_done()
	hud.set_rising(GameState.rising_active, GameState.rising_timer, prefix)
	hud.set_rope_charge(town.player.rope_charge if town.player != null else 0.0,
			town.player != null and town.player.rope_charging,
			town.player.rope_needed if town.player != null else -1.0,
			town.player != null and town.player.rope_needed >= 0.0 \
					and absf(town.player.rope_charge - town.player.rope_needed) <= Player.ROPE_WINDOW)
	# 有幸存者跟随期间，救生筏不在屏幕内时显示方向箭头
	var dir := 0
	var any_following := false
	for s in town.survivors:
		if is_instance_valid(s) and s.state == Survivor.State.FOLLOWING:
			any_following = true
			break
	if any_following:
		var raft_screen: Vector2 = get_viewport().get_canvas_transform() * town.raft_zone.get_center()
		if raft_screen.x > 1180.0:
			dir = 1
		elif raft_screen.x < 100.0:
			dir = -1
	hud.set_raft_arrow(dir)

func _wire() -> void:
	hud.set_raft_goal_name(town.goal_name)
	var p := town.player
	p.oxygen_changed.connect(hud.set_oxygen)
	p.interact_prompt.connect(hud.set_prompt)
	p.first_breath.connect(_on_first_breath)
	p.died.connect(func():
		hud.fade_to(0.9)
		Sfx.play("drown"))
	p.checkpoint_saved.connect(func():
		hud.flash_checkpoint()
		Sfx.play("checkpoint"))
	p.respawned.connect(func():
		hud.fade_to(0.0)
		hud.show_toast("小X：「呼……回到上一次呼吸的地方。」", 3.0))
	RewindManager.rewind_started.connect(func():
		hud.fade_to(0.0)
		Sfx.play("rewind"))
	RewindManager.rewind_ended.connect(func(_was_auto): hud.fade_to(0.0))
	GameState.rescue_completed.connect(_on_rescue_completed)
	GameState.survivor_lost.connect(_on_survivor_lost)
	if ChapterManager.current == 3:
		p.rope_result.connect(func(ok: bool, needed: float):
			if not ok:
				if needed < 0.0:
					hud.show_toast("附近没有可以救援的落水者", 2.5)
				else:
					hud.show_toast("差一点！这个距离约需 %d%% 力度" % int(needed * 100.0), 2.5))
		town.console_used.connect(_on_console_used)
	elif ChapterManager.current == 4:
		town.ch4_time_expired.connect(_on_ch4_time_expired)

func _on_ch4_done() -> void:
	get_tree().paused = true
	hud.play_dialogue(CH4_CHOICE_LINES, func():
		get_tree().paused = false
		_choice_pending = true
		hud.show_toast("按 1：献出回溯之力（彻底阻止） · 按 2：保留力量（承担风险）", 12.0))

func _on_ch4_time_expired() -> void:
	get_tree().paused = true
	hud.play_dialogue(CH4_FAIL_LINES, func(): _play_epilogue())

func main_state_clean() -> bool:
	return not hud.is_dialogue_visible() and not hud.is_card_visible()

func _on_console_used() -> void:
	get_tree().paused = true
	hud.play_dialogue(CH3_ENDING_LINES, func():
		get_tree().paused = false
		_schedule_next_chapter())

func _run_intro() -> void:
	get_tree().paused = true
	var lines: Array = INTRO_LINES
	if ChapterManager.current == 2:
		lines = INTRO_LINES_CH2
	elif ChapterManager.current == 3:
		lines = INTRO_LINES_CH3
	elif ChapterManager.current == 4:
		lines = INTRO_LINES_CH4
	var tips := "W/S 游动 · 空格 划水 · E 互动 · 长按 R 回溯 · 浮出水面自动存档"
	if ChapterManager.current == 2:
		tips = "E 劝说居民跟随 · 跟着箭头去右侧高台 · 长按 R 回溯"
	elif ChapterManager.current == 3:
		tips = "长按 Q 蓄力抛绳 · 变绿时松手 · E 搬沙袋/按住断电 · 洪峰倒计时"
	elif ChapterManager.current == 4:
		tips = "E 查看/搬运/劝说 · 线索与已完成目标在回卷后保留 · 当日限时"
	hud.play_dialogue(lines, func():
		get_tree().paused = false
		hud.show_toast(tips, 7.0))

func _on_first_breath() -> void:
	hud.show_toast("小X：「呼——活过来了……街上好像有呼救声？」（向右探索）", 6.0)

# ---------- 救援结算 ----------

func _on_rescue_completed() -> void:
	Sfx.play("rescue")
	hud.show_toast("幸存者获救！时间碎片 ×3，回溯上限 +4 秒", 2.5)
	get_tree().paused = true
	if GameState.rescued_count == 1:
		var lines := _first_rescue_lines()
		hud.play_dialogue(lines, func(): _show_rescue_card())
	else:
		_show_rescue_card()

func _first_rescue_lines() -> Array:
	if ChapterManager.current == 3:
		return [
			"「已救起落水者。时间碎片 ×3，回溯能量上限 +4 秒。」",
			"系统：「洪峰在逼近。河里还有人。」",
		]
	if ChapterManager.current == 4:
		return [
			"「站长已抵达集合点。时间碎片 ×3。」",
		]
	var lines := [
		"「幸存者已安全。时间碎片 ×3，回溯能量上限 +4 秒。」",
	]
	if GameState.rescued_count + GameState.lost_count < GameState.total_survivors:
		lines.append("系统：「警告：水位仍在上涨——还有幸存者被困，抓紧时间。」")
		lines.append("小X：「……还有人。我不能停下。」")
	else:
		lines.append("小X：「还不够……我要救出更多人，回到洪水发生之前，查明真相。」")
	return lines

func _show_rescue_card() -> void:
	var card: Dictionary = GameState.unlock_next_card()
	if card.is_empty():
		_finish_rescue_flow()
		return
	hud.show_card(card, func(): _finish_rescue_flow())

func _finish_rescue_flow() -> void:
	if _try_epilogue():
		return
	get_tree().paused = false

func _on_survivor_lost() -> void:
	hud.show_toast("水位淹过了那片街区……没能来得及。", 4.0)
	if not get_tree().paused:
		_try_epilogue()

func _try_epilogue() -> bool:
	if _epilogue_shown or GameState.total_survivors == 0:
		return false
	if GameState.rescued_count + GameState.lost_count < GameState.total_survivors:
		return false
	_epilogue_shown = true
	get_tree().paused = true
	hud.play_dialogue(_epilogue_lines(), func():
		get_tree().paused = false
		hud.show_toast("—— 第一章 · 完 ——", 3.0)
		_schedule_next_chapter())
	return true

func _schedule_next_chapter() -> void:
	await get_tree().create_timer(3.0).timeout
	ChapterManager.request_next()

func _epilogue_lines() -> Array:
	if ChapterManager.current == 2:
		# 第二章结尾：埋下 A2 线索（人为/AI 引发）
		if GameState.lost_count == 0:
			return [
				"「全部居民抵达高地。当前回溯权限：%d 小时。」" % int(GameState.rewind_hours),
				"小X：「水库的泄洪公告……时间和水文数据对不上。有人在撒谎。」",
				"系统：「检测到异常调度记录。回溯权限不足，继续积累。」",
				"—— 第二章 · 完 ——",
			]
		return [
			"「%d 名居民未能及时撤离。」" % GameState.lost_count,
			"小X：「对不起……下一个时间点，我会更快。」",
			"小X：「水库的泄洪公告……时间和水文数据对不上。有人在撒谎。」",
			"—— 第二章 · 完 ——",
		]
	if GameState.lost_count == 0:
		return [
			"「全部幸存者获救。当前回溯权限：%d 小时。」" % int(GameState.rewind_hours),
			"小X：「每一次呼吸、每一个人……都记住了。还不够——我要回到洪水发生之前。」",
			"—— 第一章 · 完 ——",
		]
	return [
		"「%d 名幸存者未能等到救援。」" % GameState.lost_count,
		"小X：「对不起……下一次，我一定快一点。不管重来多少次。」",
		"—— 第一章 · 完 ——",
	]
