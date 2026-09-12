extends Node
## 全局游戏状态（自动加载）：获救人数、时间碎片、剧情层面的回溯权限、水位上涨倒计时。

signal rescued_changed(count: int)
signal shards_changed(count: int)
signal rescue_completed
signal rising_timeout
signal survivor_lost
signal all_resolved

const SHARDS_PER_RESCUE := 3
const REWIND_BONUS_SECONDS := 4.0
const RISING_SECONDS := 120.0

var rescued_count := 0
var time_shards := 0
var rewind_hours := 1.0  # 剧情设定中的回溯权限：1小时 → 2小时 → …
var total_survivors := 0
var lost_count := 0

# 跨章累计（计入存档）
var rescued_total := 0
var lost_total := 0

# 水位上涨倒计时（首次救援后启动，超时仍未获救的幸存者将永久失落）
var rising_timer := 0.0
var rising_active := false

# 编辑器相关：custom_level 非空时关卡按其构建；testing_level 为真表示从编辑器试玩
var custom_level: Dictionary = {}
var testing_level := false

# 救灾知识卡：卡池按顺序解锁，每次救援解锁下一张
var all_cards: Array = []
var unlocked_count := 0
var unlocked_card_ids: Array = []

func _physics_process(delta: float) -> void:
	if not rising_active:
		return
	rising_timer -= delta
	if rising_timer <= 0.0:
		rising_timer = 0.0
		rising_active = false
		rising_timeout.emit()

func start_rising(seconds: float = RISING_SECONDS) -> void:
	rising_timer = seconds
	rising_active = true

func unlock_next_card() -> Dictionary:
	if unlocked_count >= all_cards.size():
		return {}
	var card: Dictionary = all_cards[unlocked_count]
	unlocked_count += 1
	unlocked_card_ids.append(str(card.get("id", "")))
	return card

func is_card_unlocked(card_id: String) -> bool:
	return unlocked_card_ids.has(card_id)

func add_rescue() -> void:
	rescued_count += 1
	rescued_total += 1
	time_shards += SHARDS_PER_RESCUE
	rewind_hours *= 2.0
	RewindManager.increase_max(REWIND_BONUS_SECONDS)
	rescued_changed.emit(rescued_count)
	shards_changed.emit(time_shards)
	rescue_completed.emit()

## 进入新章节：清本章状态，保留累计统计与卡牌收集
func begin_chapter() -> void:
	rescued_count = 0
	lost_count = 0
	total_survivors = 0
	rising_timer = 0.0
	rising_active = false

func reset_run() -> void:
	rescued_count = 0
	time_shards = 0
	rewind_hours = 1.0
	unlocked_count = 0
	unlocked_card_ids.clear()
	total_survivors = 0
	lost_count = 0
	rescued_total = 0
	lost_total = 0
	rising_timer = 0.0
	rising_active = false

# ---------- 存档（三槽位） ----------

const SLOT_COUNT := 3
const LEGACY_SAVE_PATH := "user://save.json"

var active_slot := 1

func _ready() -> void:
	_load_cards()
	_migrate_legacy_save()

func slot_path(slot: int) -> String:
	return "user://save_slot_%d.json" % slot

func any_slot_occupied() -> bool:
	for s in SLOT_COUNT:
		if FileAccess.file_exists(slot_path(s + 1)):
			return true
	return false

## 兼容旧调用：任意槽位有档即视为可继续
func has_save() -> bool:
	return any_slot_occupied()

## 槽位摘要（标题界面展示用）
func slot_info(slot: int) -> Dictionary:
	if not FileAccess.file_exists(slot_path(slot)):
		return {"empty": true}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(slot_path(slot)))
	if parsed is not Dictionary:
		return {"empty": true}
	var chapter := int(parsed.get("chapter", 1))
	return {
		"empty": false,
		"chapter": chapter,
		"chapter_name": ChapterManager.chapter_title(chapter),
		"rescued_total": int(parsed.get("rescued_total", 0)),
		"lost_total": int(parsed.get("lost_total", 0)),
		"cards": parsed.get("unlocked_card_ids", []).size(),
		"saved_at": str(parsed.get("saved_at", "")),
	}

func save_game() -> void:
	var data := {
		"chapter": ChapterManager.current,
		"rescued_total": rescued_total,
		"lost_total": lost_total,
		"rewind_hours": rewind_hours,
		"unlocked_card_ids": unlocked_card_ids,
		"saved_at": Time.get_datetime_string_from_system().replace("T", " "),
	}
	var f := FileAccess.open(slot_path(active_slot), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))

func load_game(slot: int = active_slot) -> bool:
	if not FileAccess.file_exists(slot_path(slot)):
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(slot_path(slot)))
	if parsed is not Dictionary:
		return false
	active_slot = slot
	rescued_total = int(parsed.get("rescued_total", 0))
	lost_total = int(parsed.get("lost_total", 0))
	rewind_hours = float(parsed.get("rewind_hours", 1.0))
	unlocked_card_ids.clear()
	for cid in parsed.get("unlocked_card_ids", []):
		unlocked_card_ids.append(str(cid))
	unlocked_count = unlocked_card_ids.size()
	ChapterManager.current = int(parsed.get("chapter", 1))
	begin_chapter()
	return true

func delete_slot(slot: int) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(slot)))

## 旧版单存档（user://save.json）一次性迁移到槽 1
func _migrate_legacy_save() -> void:
	if not FileAccess.file_exists(LEGACY_SAVE_PATH):
		return
	if any_slot_occupied():
		return
	DirAccess.copy_absolute(ProjectSettings.globalize_path(LEGACY_SAVE_PATH),
			ProjectSettings.globalize_path(slot_path(1)))

func _load_cards() -> void:
	var f := FileAccess.open("res://data/knowledge_cards.json", FileAccess.READ)
	if f != null:
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary and parsed.has("cards"):
			all_cards = parsed["cards"]
