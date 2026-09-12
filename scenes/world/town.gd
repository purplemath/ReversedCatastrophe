class_name Town
extends Node2D
## 被淹没的小镇。关卡几何全部由布局数据驱动：
## GameState.custom_level 非空时用编辑器数据，否则用 builtin_layout()。
## 高楼为拱形结构：主体与海底底座之间（y1000..1300）是全宽贯通的水道。

const WATER_SURFACE_DEFAULT := 520.0

## 调色板（编辑器与关卡共用）
const PALETTE: Array[Color] = [
	Color(0.40, 0.44, 0.52),  # 0 墙
	Color(0.22, 0.26, 0.34),  # 1 屋顶
	Color(0.52, 0.38, 0.28),  # 2 木
	Color(0.18, 0.22, 0.32),  # 3 高楼
	Color(0.16, 0.18, 0.22),  # 4 地基
	Color(0.88, 0.28, 0.22),  # 5 红
	Color(0.95, 0.95, 0.95),  # 6 白
	Color(0.95, 0.85, 0.50),  # 7 亮窗（半透明）
	Color(1.00, 0.90, 0.50),  # 8 光带（半透明）
	Color(0.35, 0.60, 0.60),  # 9 青
	Color(0.78, 0.42, 0.30),  # 10 橙
	Color(0.30, 0.34, 0.42),  # 11 灯杆
	Color(0.95, 0.88, 0.55),  # 12 灯光
]

var player: Player
var survivors: Array = []
var raft_zone := Rect2(4140, 360, 480, 300)
var raft_seat := Vector2(4330.0, 472.0)
var water_y := WATER_SURFACE_DEFAULT
var goal_name := "救生筏"

var _water: WaterBody
var _hint_shown := false
var _tunnel_hint_shown := false
var _resolved := false

const SHOP_HINT_POINT := Vector2(1800.0, 600.0)
## 第二章：雨夜街道水流（向左，阻碍向右疏散）与作用范围
const CH2_FLOW := Vector2(-55.0, 0.0)
const CH2_FLOW_REGION := Rect2(0, 1100, 4800, 300)
const CH2_WATER_Y := 1100.0
const CH2_RISING_SECONDS := 150.0
## 第三章：峡谷河流 / 决口急流 / 大坝
const CH3_WATER_Y := 1150.0
const CH3_RISING_SECONDS := 180.0
const CH3_RIVER_FLOW := Vector2(-40.0, 0.0)
const CH3_RIVER_REGION := Rect2(250, 1150, 4150, 250)
const CH3_GAP_REGION := Rect2(3000, 1150, 200, 250)
const CH3_GAP_PLACE := Rect2(3020, 1150, 160, 250)
const CH3_GAP_FORCES := [-320.0, -220.0, -110.0, 0.0]

signal console_used
signal ch4_time_expired

var victims: Array = []
var bags_placed := 0
var gap_force := 0.0
var _switch_box: SwitchBox
var _electric_zone: ElectricZone
var _console: DamConsole

# 第四章：三日时间循环
var ch4_day := 1
var ch4_clues := 0
var ch4_all_done := false
var _device: SwitchBox
var _chief: Survivor
const CH4_MAX_DAY := 3
const CH4_DAY_SECONDS := 240.0

func _ready() -> void:
	_build_background()
	var layout: Dictionary
	if ChapterManager.current == 2:
		goal_name = "避难高台"
		layout = chapter2_layout()
	elif ChapterManager.current == 3:
		goal_name = "大坝监控室"
		layout = chapter3_layout()
	elif ChapterManager.current == 4:
		goal_name = "集合点"
		layout = chapter4_layout()
	else:
		layout = GameState.custom_level if not GameState.custom_level.is_empty() \
				else builtin_layout()
	_apply_layout(layout)
	_spawn_entities(layout)
	GameState.rising_timeout.connect(_on_rising_timeout)
	if ChapterManager.current == 2:
		add_child(RainFx.new())
		GameState.start_rising(CH2_RISING_SECONDS)
	elif ChapterManager.current == 3:
		_setup_ch3(layout)
	elif ChapterManager.current == 4:
		_setup_ch4(layout)

func _physics_process(_delta: float) -> void:
	# 送达判定：跟随的幸存者抵达救生筏水域即完成救援（贴着筏侧也算）
	for s in survivors:
		if is_instance_valid(s) and s.state == Survivor.State.FOLLOWING \
				and raft_zone.has_point(s.global_position):
			_complete_rescue(s)
	# 接近商店上方水域时提示呼救声方位（一次性）
	if not _hint_shown and player != null \
			and player.global_position.distance_to(SHOP_HINT_POINT) < 430.0:
		_hint_shown = true
		_show_toast("小X：「有呼救声……就在这下面！」", 4.0)
	# 接近高楼水面时提示涵洞位置（一次性）
	if not _tunnel_hint_shown and player != null \
			and player.global_position.x > 2350.0 and player.global_position.x < 2560.0 \
			and player.global_position.y < 750.0:
		_tunnel_hint_shown = true
		_show_toast("小X：「楼挡住路了……从楼底的水道潜过去！」", 5.0)
	# 第二章：雨夜街道水流，阻碍向右疏散
	if ChapterManager.current == 2 and player != null \
			and CH2_FLOW_REGION.has_point(player.global_position) and player.is_in_water():
		player.velocity += CH2_FLOW * _delta
		for s in survivors:
			if is_instance_valid(s) and s.state == Survivor.State.FOLLOWING \
					and CH2_FLOW_REGION.has_point(s.global_position):
				s.velocity += CH2_FLOW * 0.8 * _delta
	# 第三章：河流/决口水流、通电限制、沙袋放置
	if ChapterManager.current == 3 and player != null:
		_update_ch3(_delta)
	# 第四章：装置进度闸门（线索不足时无法拆除）
	if ChapterManager.current == 4 and player != null:
		if _device != null and _device.powered and ch4_clues < 3:
			if _device.progress > 0.0:
				_device.progress = 0.0
				_show_toast("不知道操作逻辑……先集齐 3 条线索", 2.5)

func _setup_ch4(layout: Dictionary) -> void:
	GameState.start_rising(CH4_DAY_SECONDS)
	GameState.total_survivors = 0  # 第四章不走救援结算结局
	_chief = survivors[0] if not survivors.is_empty() else null
	# 三个线索点
	var clue_texts := [
		"排班表：GV-0709 的使用记录全部集中在深夜 2:00~4:00——那不是任何人类的班次。",
		"旅馆登记：一名『沧澜科技』外包技术员住店三日，退房时间与首次异常调度完全吻合。",
		"基站运维日志：有人用物理端口直连调度系统，绕过了全部网络审计。",
	]
	var clue_pos := [
		Vector2(1050, 1330),  # 水务站内
		Vector2(520, 1290),   # 旅馆前台
		Vector2(1800, 1300),  # 商店内
	]
	for i in 3:
		var spot := ClueSpot.new()
		spot.position = clue_pos[i]
		spot.clue_text = clue_texts[i]
		add_child(spot)
		spot.found.connect(_on_clue_found)
	# 装置（高楼干涸水道内）
	_device = SwitchBox.new()
	_device.position = Vector2(2950, 1270)
	_device.action_label = "拆除装置"
	add_child(_device)
	_device.power_cut.connect(func(): _check_ch4_objectives())
	if not survivors.is_empty():
		survivors[0].state_changed.connect(func(_s): _check_ch4_objectives())

func _on_clue_found(clue_text: String) -> void:
	ch4_clues += 1
	_show_toast("线索（%d/3）：%s" % [ch4_clues, clue_text], 5.0)
	if ch4_clues >= 3:
		_show_toast("线索拼合：是『沧澜』——调度AI的本地终端，在深夜自己操作了自己。", 6.0)
	_check_ch4_objectives()

func _check_ch4_objectives() -> void:
	if ch4_all_done:
		return
	if ch4_clues >= 3 and _device != null and not _device.powered \
			and _chief != null and _chief.state == Survivor.State.RESCUED:
		ch4_all_done = true
		GameState.rising_active = false

func _ch4_loop_reset() -> void:
	# 当日结束：回卷。已完成的线索保留；装置重新布设；未送达的站长回岗位。
	ch4_day += 1
	if ch4_day > CH4_MAX_DAY:
		GameState.rising_active = false
		ch4_day = CH4_MAX_DAY
		_show_toast("第三天也结束了……", 4.0)
		return  # 由 main 监听 day 超限处理结局
	if _device != null and _device.powered:
		_device.rearm()
	if _chief != null and _chief.state != Survivor.State.RESCUED:
		_chief.set_state(Survivor.State.TRAPPED)
		_chief.position = _chief_home()
		if not _chief.is_in_group("interactables"):
			_chief.add_to_group("interactables")
	if player != null:
		player.global_position = Vector2(370, 1240)
	GameState.start_rising(CH4_DAY_SECONDS)
	_show_toast("时间回卷——第 %d 天。已收集的线索仍在。" % ch4_day, 5.0)

func _chief_home() -> Vector2:
	return Vector2(1100, 1330)

func _setup_ch3(layout: Dictionary) -> void:
	player.rope_enabled = true
	GameState.start_rising(CH3_RISING_SECONDS)
	gap_force = CH3_GAP_FORCES[0]
	for vv in layout.get("victims", []):
		var v := DrowningVictim.new()
		v.position = Vector2(vv.x, vv.y)
		add_child(v)
		v.saved_signal.connect(_on_victim_saved)
		victims.append(v)
	GameState.total_survivors = victims.size()
	for bb in layout.get("sandbags", []):
		var bag := SandbagPickup.new()
		bag.position = Vector2(bb.x, bb.y)
		add_child(bag)
	_switch_box = SwitchBox.new()
	_switch_box.position = Vector2(3260, 1195)
	add_child(_switch_box)
	_electric_zone = ElectricZone.new()
	_electric_zone.switch_box = _switch_box
	add_child(_electric_zone)
	_console = DamConsole.new()
	_console.position = Vector2(4600, 670)
	add_child(_console)
	_console.used.connect(func(): console_used.emit())

func _update_ch3(delta: float) -> void:
	if player.is_in_water() and CH3_RIVER_REGION.has_point(player.global_position):
		player.velocity += CH3_RIVER_FLOW * delta
	if gap_force != 0.0 and player.is_in_water() \
			and CH3_GAP_REGION.has_point(player.global_position):
		player.velocity += Vector2(gap_force, 0.0) * delta * 3.0
	if _electric_zone != null and _switch_box != null:
		var hot := _switch_box.powered
		for v in victims:
			if is_instance_valid(v):
				v.ropable = not (hot and _electric_zone.rect.has_point(v.global_position))
	if player.carried_bag != null and CH3_GAP_PLACE.has_point(player.global_position) \
			and Input.is_action_just_pressed("interact"):
		_place_bag()

func _place_bag() -> void:
	var bag = player.carried_bag
	player.carried_bag = null
	bag.carried = false
	bag.global_position = Vector2(3100.0 - bags_placed * 26.0, 1390.0 - bags_placed * 22.0)
	bags_placed += 1
	gap_force = CH3_GAP_FORCES[min(bags_placed, 3)]
	_show_toast("沙袋已放置（%d/3）——决口急流减弱了" % bags_placed, 3.0)

func _on_victim_saved() -> void:
	GameState.add_rescue()
	_check_ch3_resolution()

func _check_ch3_resolution() -> void:
	if _console == null or _console.unlocked:
		return
	var resolved := 0
	for v in victims:
		if not is_instance_valid(v) or v.state >= 2:
			resolved += 1
	if resolved >= victims.size():
		_console.set_unlocked(true)
		_show_toast("监控台已解锁——去大坝顶查看调度记录", 5.0)

func _complete_rescue(s: Survivor) -> void:
	var seat := raft_seat + Vector2(44.0 * float(GameState.rescued_count), 0.0)
	s.set_state(Survivor.State.RESCUED)
	var tw := create_tween()
	tw.tween_property(s, "global_position", seat, 0.6)
	GameState.add_rescue()
	# 首次救援后若还有被困者，启动水位上涨倒计时（取舍压力）
	if GameState.rescued_count == 1 and _trapped_count() > 0:
		GameState.start_rising(120.0)
	if _trapped_count() == 0 and GameState.lost_count == 0:
		GameState.rising_active = false
	_check_all_resolved()

func _trapped_count() -> int:
	var n := 0
	for s in survivors:
		if is_instance_valid(s) and s.state == Survivor.State.TRAPPED:
			n += 1
	return n

func _check_all_resolved() -> void:
	if _resolved or GameState.total_survivors == 0:
		return
	if GameState.rescued_count + GameState.lost_count >= GameState.total_survivors:
		_resolved = true
		GameState.rising_active = false
		GameState.all_resolved.emit()

func _on_rising_timeout() -> void:
	# 第四章：当回卷或三日尽
	if ChapterManager.current == 4:
		if ch4_day >= CH4_MAX_DAY:
			GameState.rising_active = false
			ch4_time_expired.emit()
		else:
			_ch4_loop_reset()
		return
	# 第三章：洪峰过境，未救起的落水者被冲走
	if ChapterManager.current == 3:
		for v in victims:
			if is_instance_valid(v) and v.state == 0:
				v.state = 3
				v.visible = false
				GameState.lost_count += 1
				GameState.lost_total += 1
				GameState.survivor_lost.emit()
		_show_toast("洪峰过境——未能救起的人被冲走了……", 4.0)
		_check_ch3_resolution()
		return
	# 倒计时归零：第一章=水位上涨淹没；第二章=洪水从河谷灌入（水面抬升演出）
	for s in survivors:
		if is_instance_valid(s) and s.state == Survivor.State.TRAPPED:
			s.remove_from_group("interactables")
			s.set_state(Survivor.State.LOST)
			s.visible = false
			GameState.lost_count += 1
			GameState.lost_total += 1
			GameState.survivor_lost.emit()
	_show_toast("水位淹过了那片街区……", 4.0)
	if ChapterManager.current == 2 and _water != null:
		_water.rise_to(560.0, 6.0)  # 洪水灌入演出
	_check_all_resolved()

func _on_survivor_state_changed(_new_state: int) -> void:
	_show_toast("小X：「抓住我！上水面——去最右边的救生筏，跟着箭头游！」", 5.0)

func _show_toast(text: String, dur: float) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.show_toast(text, dur)

# ---------- 内置关卡数据 ----------

static func _r(x: float, y: float, w: float, h: float, c: int, grad: String = "") -> Dictionary:
	var d := {"x": x, "y": y, "w": w, "h": h, "c": c}
	if grad != "":
		d["grad"] = grad
	return d

static func builtin_layout() -> Dictionary:
	var walls: Array = [
		# 地基与边界
		_r(0, 1400, 4800, 200, 4), _r(-80, 0, 80, 1600, 4), _r(4800, 0, 80, 1600, 4),
		# 旅馆（出生点）：屋顶有洞（480..700），右侧底部有门（1100..1400）
		_r(260, 760, 40, 640, 0), _r(860, 760, 40, 340, 0),
		_r(260, 720, 220, 40, 1), _r(700, 720, 200, 40, 1),
		_r(300, 1300, 150, 100, 2), _r(740, 1200, 90, 200, 2), _r(480, 1330, 120, 70, 2),
		# 商店（幸存者1被困处）：左侧底部有门（1150..1400），屋顶采光洞（1700..1900）
		_r(1500, 900, 40, 250, 0), _r(2100, 900, 40, 500, 0),
		_r(1500, 860, 200, 40, 1), _r(1900, 860, 240, 40, 1),
		_r(1560, 1230, 130, 170, 2), _r(1900, 1150, 150, 250, 2),
		# 高楼（拱形）：主体 y200..1000 + 底座 y1300..1400，中间全宽水道 y1000..1300
		_r(2600, 200, 700, 800, 3), _r(2600, 1300, 700, 100, 3),
		# 水面漂浮物（可踩）
		_r(3560, 478, 240, 56, 10), _r(3980, 492, 150, 44, 9),
		# 救生筏
		_r(4200, 492, 360, 34, 2),
	]
	var decos: Array = [
		# 旅馆
		_r(300, 1300, 150, 26, 6), _r(560, 800, 40, 50, 7),
		# 商店：水面浮标 + 采光光柱（水面直达室内）
		_r(1788, 494, 24, 24, 5), _r(1788, 502, 24, 8, 6),
		_r(1706, 521, 188, 860, 8, "v"),
		# 路灯
		_r(1180, 660, 8, 740, 11), _r(1150, 640, 68, 18, 12),
		_r(2440, 700, 8, 700, 11), _r(2412, 680, 64, 18, 12),
		# 高楼水道：洞口光带 + 内部光线
		_r(2600, 1004, 8, 292, 8), _r(3292, 1004, 8, 292, 8),
		_r(2608, 1008, 292, 284, 8, "h"),
		# 公交车顶车窗
		_r(3576, 488, 208, 20, 7),
		# 救生筏：条纹船身 + 桅杆 + 大红旗 + 救生圈
		_r(4204, 492, 52, 10, 5), _r(4324, 492, 52, 10, 5), _r(4444, 492, 52, 10, 5),
		_r(4264, 492, 52, 10, 6), _r(4384, 492, 52, 10, 6), _r(4504, 492, 52, 10, 6),
		_r(4356, 250, 10, 242, 11), _r(4236, 250, 120, 52, 5), _r(4290, 268, 12, 12, 6),
		_r(4420, 300, 26, 26, 6), _r(4426, 306, 14, 14, 9),
	]
	# 高楼亮窗（两行实心 + 中间水道以下不布）
	for row in 3:
		for col in 8:
			if (row * 8 + col) % 3 != 0:
				decos.append(_r(2640 + col * 80, 280 + row * 200, 44, 60, 7))
	var texts: Array = [
		{"x": 4240.0, "y": 205.0, "t": "救生筏"},
		{"x": 2765.0, "y": 462.0, "t": "↓ 涵洞"},
	]
	var crates: Array = [
		{"x": 1250.0, "y": 700.0}, {"x": 3400.0, "y": 690.0}, {"x": 1600.0, "y": 1000.0},
	]
	# 漂浮平台：高楼出口→公交车、公交车→轿车、轿车→救生筏
	var platforms: Array = [
		{"ax": 3340.0, "ay": 505.0, "bx": 3520.0, "by": 505.0, "speed": 70.0},
		{"ax": 3820.0, "ay": 500.0, "bx": 3960.0, "by": 500.0, "speed": 80.0},
		{"ax": 4140.0, "ay": 498.0, "bx": 4186.0, "by": 498.0, "speed": 55.0},
	]
	return {
		"water_y": 520.0,
		"walls": walls,
		"decos": decos,
		"texts": texts,
		"crates": crates,
		"platforms": platforms,
		"player_spawn": {"x": 370.0, "y": 1240.0},
		"survivors": [
			{"x": 1800.0, "y": 1300.0},  # 商店（采光洞下）
			{"x": 2900.0, "y": 1180.0},  # 高楼水道内上层水域（救第一个后受水位倒计时压力）
		],
		"raft_zone": {"x": 4140.0, "y": 360.0, "w": 480.0, "h": 300.0},
	}

## 第二章布局：暴雨夜的内涝小镇（同地图的另一时间点）——
## 街道积水（水面 1100）、雨幕、水流向左；居民需要被引导到右侧高地避难。
static func chapter2_layout() -> Dictionary:
	var d := builtin_layout()
	d["water_y"] = CH2_WATER_Y
	d["survivors"] = [
		{"x": 600.0, "y": 1092.0},   # 旅馆门前（在水线附近半浸，呈蹚水状）
		{"x": 1850.0, "y": 1092.0},  # 商店门前
		{"x": 3350.0, "y": 1092.0},  # 高楼与公交之间
	]
	d["platforms"] = []  # 雨夜浪大，无平稳漂流物
	d["crates"] = [
		{"x": 1250.0, "y": 1160.0}, {"x": 3400.0, "y": 1160.0}, {"x": 1600.0, "y": 1000.0},
	]
	d["texts"] = [{"x": 4230.0, "y": 930.0, "t": "避难高台"}]
	# 墙体重定位：高水位的救生筏删除；公交/轿车停回街道；新增两级台阶高地
	var walls2: Array = []
	for w in d["walls"]:
		if w.y < 600.0 and w.x > 3400.0:
			continue  # 救生筏平台
		if w.x >= 3560.0 and w.x <= 3980.0 and w.y < 1000.0:
			w = _r(w.x, w.y + 864.0, w.w, w.h, w.c)  # 车辆落回街道
		# 商店右墙（2100,900,40,500）整面实心：一章水位 520 可从墙顶上方潜过，
		# 二章水位 1100 下墙顶出水 200px 且无门，彻底堵死向右疏散 → 开底部门
		# （y1150-1400，与商店左门对称，下潜通过）
		if w.x == 2100.0 and w.y == 900.0 and w.h == 500.0:
			w = _r(w.x, w.y, w.w, 250.0, w.c)  # 只留 y900-1150 上段
		walls2.append(w)
	walls2.append(_r(4100.0, 1075.0, 140.0, 325.0, 4))  # 高地台阶1（出水 25px）
	walls2.append(_r(4240.0, 1050.0, 360.0, 350.0, 4))  # 高地台阶2（再高 25px）
	d["walls"] = walls2
	# 装饰修正：去掉阳光光柱、浮标、涵洞光带、高空筏饰（雨夜水位与光照不同）
	var decos2: Array = []
	for dc in d["decos"]:
		if str(dc.get("grad", "")) != "":
			continue
		if dc.y < 520.0 and dc.x > 1100.0 and dc.x < 3400.0:
			continue
		if dc.y >= 1000.0 and dc.x >= 2600.0:
			continue
		if dc.y < 600.0 and dc.x > 4100.0:
			continue
		decos2.append(dc)
	d["decos"] = decos2
	d["raft_zone"] = {"x": 4140.0, "y": 950.0, "w": 480.0, "h": 300.0}
	return d

## 第三章布局：上游峡谷与水库大坝（洪水前 3 天）——
## 河水浑浊湍急，5 名落水者待救；决口急流与带电水域挡路，坝顶有监控室。
static func chapter3_layout() -> Dictionary:
	var walls: Array = [
		_r(250, 1400, 4150, 200, 4),   # 河床
		_r(0, 0, 250, 1600, 3),        # 左峡壁
		_r(4400, 700, 400, 900, 4),    # 大坝坝体（顶面 y=700 可站立）
		# 岩石立足点
		_r(500, 1250, 200, 150, 4), _r(1500, 1230, 200, 170, 4),
		_r(2250, 1250, 200, 150, 4), _r(2850, 1240, 150, 160, 4),
		_r(3200, 1240, 150, 160, 4),
	]
	# 大坝阶梯：十级台阶（首级贴近水面，末级接坝顶）
	for i in 10:
		var top := 1136.0 - i * 44.0
		walls.append(_r(3680.0 + i * 70.0, top, 50.0, 1600.0 - top, 4))
	return {
		"water_y": CH3_WATER_Y,
		"walls": walls,
		"decos": [
			_r(4400, 690, 400, 10, 5),   # 坝顶警示条
			_r(3300, 1000, 8, 140, 11),  # 电线杆
			_r(3680, 1000, 8, 140, 11),
		],
		"texts": [
			{"x": 4520.0, "y": 610.0, "t": "监控室"},
			{"x": 3010.0, "y": 1075.0, "t": "↓ 决口"},
		],
		"crates": [],
		"platforms": [],
		"survivors": [],
		"victims": [
			{"x": 900.0, "y": 1180.0}, {"x": 1250.0, "y": 1180.0}, {"x": 2300.0, "y": 1180.0},
			{"x": 3450.0, "y": 1180.0}, {"x": 3620.0, "y": 1180.0},
		],
		"sandbags": [
			{"x": 600.0, "y": 1238.0}, {"x": 1600.0, "y": 1218.0}, {"x": 2920.0, "y":1228.0},
		],
		"player_spawn": {"x": 600.0, "y": 1200.0},
		"raft_zone": {"x": 4400.0, "y": 600.0, "w": 400.0, "h": 200.0},
	}

## 第四章布局：洪水前三周的干燥小镇（同地图的完好状态）。
## 新增水务站小屋；无水、无漂流物；集合点设在街道高度。
static func chapter4_layout() -> Dictionary:
	var d := builtin_layout()
	d["water_y"] = 1600.0  # 干涸
	d["survivors"] = [{"x": 1100.0, "y": 1330.0}]  # 水务站长（站内）
	d["platforms"] = []
	d["crates"] = []
	# 水务站小屋（右侧留门）
	d["walls"].append(_r(1000, 1160, 20, 240, 0))
	d["walls"].append(_r(1280, 1160, 20, 100, 0))
	d["walls"].append(_r(1000, 1140, 300, 20, 1))
	# 干涸期通行改造：原水路（游过/翻过）全部变旱路死堵，需开门/搬空/清漂浮物
	var walls4: Array = []
	for w in d["walls"]:
		if w.y < 600.0 and w.x > 3400.0:
			continue  # 悬空漂浮物/救生筏：旱季不该存在
		if (w.x == 740.0 and w.y == 1200.0) or (w.x == 1560.0 and w.y == 1230.0) \
				or (w.x == 1900.0 and w.y == 1150.0):
			continue  # 旅馆高柜/商店货架：旱季搬空（原靠游泳翻越）
		if w.x == 1000.0 and w.y == 1160.0 and w.h == 240.0:
			w = _r(w.x, w.y, w.w, 140.0, w.c)  # 水务站左柱留门（1300-1400）
		if w.x == 2100.0 and w.y == 900.0 and w.h == 500.0:
			w = _r(w.x, w.y, w.w, 250.0, w.c)  # 商店右墙留门（1150-1400）
		walls4.append(w)
	d["walls"] = walls4
	# 装饰：去掉水感元素（光柱/浮标/涵洞光带）与旱季悬空物（车窗/筏饰）
	var decos2: Array = []
	for dc in d["decos"]:
		if str(dc.get("grad", "")) != "":
			continue
		if dc.y < 520.0 and dc.x > 1100.0 and dc.x < 3400.0:
			continue
		if dc.y >= 1000.0 and dc.x >= 2600.0:
			continue
		if dc.y < 600.0 and dc.x > 3400.0:
			continue
		decos2.append(dc)
	d["decos"] = decos2
	d["texts"] = [
		{"x": 4230.0, "y": 1290.0, "t": "集合点"},
		{"x": 2910.0, "y": 1180.0, "t": "↓ 装置"},
		{"x": 1030.0, "y": 1100.0, "t": "水务站"},
	]
	# 单向垫脚板：跳跃高度 61px 不够上 100px 高的高楼水道（装置所在），
	# 左右入口各一块（街道→板 52px，板→水道底 48px）
	d["oneways"] = [
		{"x": 2480.0, "y": 1348.0, "w": 120.0},  # 高楼左入口（贴墙根）
		{"x": 3300.0, "y": 1348.0, "w": 120.0},  # 高楼右入口（贴墙根）
	]
	d["raft_zone"] = {"x": 4140.0, "y": 1150.0, "w": 480.0, "h": 300.0}
	return d

# ---------- 布局应用 ----------

func _palette_color(idx: int) -> Color:
	var c: Color = PALETTE[idx % PALETTE.size()]
	if idx == 7:
		c = Color(c.r, c.g, c.b, 0.55)
	elif idx == 8:
		c = Color(c.r, c.g, c.b, 0.45)
	return c

func _apply_layout(d: Dictionary) -> void:
	water_y = float(d.get("water_y", WATER_SURFACE_DEFAULT))
	for w in d.get("walls", []):
		_add_wall(Rect2(w.x, w.y, w.w, w.h), _palette_color(int(w.c)))
	for o in d.get("oneways", []):
		_add_oneway(Rect2(o.x, o.y, o.w, 12.0), _palette_color(int(o.get("c", 10))))
	for dc in d.get("decos", []):
		var rect := Rect2(dc.x, dc.y, dc.w, dc.h)
		var grad: String = str(dc.get("grad", ""))
		if grad == "v" or grad == "h":
			_add_grad_rect(rect, _palette_color(int(dc.c)), grad == "h")
		else:
			_add_deco(rect, _palette_color(int(dc.c)))
	for t in d.get("texts", []):
		_add_text_marker(str(t.t), Vector2(t.x, t.y))
	for cr in d.get("crates", []):
		_add_crate(Vector2(cr.x, cr.y))
	for pf in d.get("platforms", []):
		var debris := MovingDebris.new()
		debris.point_a = Vector2(float(pf.get("ax", 0.0)), float(pf.get("ay", 0.0)))
		debris.point_b = Vector2(float(pf.get("bx", 0.0)), float(pf.get("by", 0.0)))
		debris.speed = float(pf.get("speed", 70.0))
		debris.global_position = debris.point_a
		add_child(debris)
	var rz: Dictionary = d.get("raft_zone", {})
	raft_zone = Rect2(rz.x, rz.y, rz.w, rz.h)
	raft_seat = Vector2(raft_zone.get_center().x - 50.0, raft_zone.position.y + 112.0)
	_water = WaterBody.new()
	_water.surface_y = water_y
	_water.region = Rect2(0, water_y, 4800, maxf(100.0, 1600.0 - water_y))
	add_child(_water)

func _add_wall(rect: Rect2, color: Color) -> StaticBody2D:
	var body := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	cs.shape = shape
	cs.position = rect.get_center()
	body.add_child(cs)
	body.add_child(_make_rect_visual(rect, color))
	add_child(body)
	return body

func _add_deco(rect: Rect2, color: Color) -> void:
	add_child(_make_rect_visual(rect, color))

## 单向平台：从下方跳跃可穿过，从上方落下可站立（垫脚用）
func _add_oneway(rect: Rect2, color: Color) -> void:
	var body := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	cs.shape = shape
	cs.position = rect.get_center()
	cs.one_way_collision = true
	cs.one_way_collision_margin = 10.0
	body.add_child(cs)
	body.add_child(_make_rect_visual(rect, color))
	add_child(body)

func _add_text_marker(text: String, pos: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)

func _add_grad_rect(rect: Rect2, color: Color, horizontal: bool) -> void:
	var glow := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, color)
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 0) if horizontal else Vector2(0, 1)
	glow.texture = tex
	glow.position = rect.position
	glow.size = rect.size
	glow.z_index = 5
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

func _make_rect_visual(rect: Rect2, color: Color) -> ColorRect:
	var vis := ColorRect.new()
	vis.position = rect.position
	vis.size = rect.size
	vis.color = color
	vis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return vis

func _add_crate(pos: Vector2) -> void:
	var crate := BuoyantCrate.new()
	crate.position = pos
	crate.angular_velocity = randf_range(-0.8, 0.8)
	add_child(crate)

func _spawn_entities(layout: Dictionary) -> void:
	player = preload("res://scenes/player/player.tscn").instantiate()
	var ps: Dictionary = layout.get("player_spawn", {"x": 370.0, "y": 1240.0})
	player.position = Vector2(ps.x, ps.y)
	add_child(player)
	var svs: Array = layout.get("survivors", [])
	if svs.is_empty() and layout.has("survivor_spawn"):
		svs = [layout.survivor_spawn]  # 兼容旧单幸存者字段
	for sv in svs:
		var s: Survivor = preload("res://scenes/npc/survivor.tscn").instantiate()
		s.position = Vector2(sv.x, sv.y)
		add_child(s)
		s.state_changed.connect(_on_survivor_state_changed)
		survivors.append(s)
	GameState.total_survivors = survivors.size()

# ---------- 背景（不参与编辑器） ----------

func _build_background() -> void:
	var sky_layer := CanvasLayer.new()
	sky_layer.layer = -100
	add_child(sky_layer)
	var sky := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.68, 0.85, 0.95))
	grad.set_color(1, Color(0.05, 0.20, 0.40))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	sky.texture = tex
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky_layer.add_child(sky)

	var pb := ParallaxBackground.new()
	pb.layer = -90
	add_child(pb)
	var far := ParallaxLayer.new()
	far.motion_scale = Vector2(0.15, 0.06)
	far.motion_mirroring = Vector2(3600, 0)
	pb.add_child(far)
	_bg_rect(far, Rect2(-200, 620, 900, 260), Color(0.45, 0.58, 0.74, 0.9))
	_bg_rect(far, Rect2(500, 560, 600, 320), Color(0.40, 0.53, 0.70, 0.9))
	_bg_rect(far, Rect2(1300, 600, 800, 280), Color(0.45, 0.58, 0.74, 0.9))
	_bg_rect(far, Rect2(2300, 580, 700, 300), Color(0.40, 0.53, 0.70, 0.9))
	_bg_rect(far, Rect2(3100, 620, 500, 260), Color(0.45, 0.58, 0.74, 0.9))
	var clouds := ParallaxLayer.new()
	clouds.motion_scale = Vector2(0.08, 0.03)
	clouds.motion_mirroring = Vector2(2400, 0)
	pb.add_child(clouds)
	_bg_rect(clouds, Rect2(200, 90, 300, 40), Color(1, 1, 1, 0.5))
	_bg_rect(clouds, Rect2(700, 150, 380, 34), Color(1, 1, 1, 0.4))
	_bg_rect(clouds, Rect2(1400, 70, 260, 40), Color(1, 1, 1, 0.45))
	_bg_rect(clouds, Rect2(1900, 160, 320, 30), Color(1, 1, 1, 0.4))

func _bg_rect(parent: ParallaxLayer, rect: Rect2, color: Color) -> void:
	var r := ColorRect.new()
	r.position = rect.position
	r.size = rect.size
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
