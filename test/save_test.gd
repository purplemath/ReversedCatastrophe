extends Node
## 多槽位存档测试（headless 用）。测试前后备份/还原玩家真实存档。
## 运行：Godot --headless --path . res://test/save_test.tscn

var _backup: Dictionary = {}  # path -> 内容

func _ready() -> void:
	_backup_all()
	_run_tests()
	_restore_all()
	print("TEST OK")
	get_tree().quit()

func _backup_all() -> void:
	var paths: Array = [GameState.LEGACY_SAVE_PATH]
	for s in GameState.SLOT_COUNT:
		paths.append(GameState.slot_path(s + 1))
	for p in paths:
		if FileAccess.file_exists(p):
			_backup[p] = FileAccess.get_file_as_string(p)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

func _restore_all() -> void:
	for p in _backup:
		var f := FileAccess.open(p, FileAccess.WRITE)
		if f != null:
			f.store_string(_backup[p])
	for s in GameState.SLOT_COUNT:
		var sp := GameState.slot_path(s + 1)
		if FileAccess.file_exists(sp) and not _backup.has(sp):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(sp))

func _run_tests() -> void:
	if GameState.any_slot_occupied():
		push_error("TEST slots should be empty")
	if not GameState.slot_info(1).get("empty", false):
		push_error("TEST slot1 should be empty")
	print("TEST empty state ok")

	var legacy := FileAccess.open(GameState.LEGACY_SAVE_PATH, FileAccess.WRITE)
	legacy.store_string(JSON.stringify({"chapter": 2, "rescued_total": 3,
			"lost_total": 1, "rewind_hours": 2.0, "unlocked_card_ids": ["flood_cpr"]}))
	legacy.close()
	GameState._migrate_legacy_save()
	var info1: Dictionary = GameState.slot_info(1)
	if info1.get("empty", true) or info1.get("chapter", 0) != 2:
		push_error("TEST legacy migration failed")
	else:
		print("TEST legacy migration ok")

	GameState.delete_slot(1)  # 迁移测试后清掉槽1，再测槽2

	GameState.reset_run()
	GameState.rescued_total = 5
	GameState.lost_total = 2
	GameState.rewind_hours = 8.0
	GameState.unlocked_card_ids = ["flood_high_ground", "flood_manhole"]
	GameState.unlocked_count = 2
	ChapterManager.current = 1
	GameState.active_slot = 2
	GameState.save_game()
	var info: Dictionary = GameState.slot_info(2)
	print("TEST slot2 info=", info)
	if info.get("empty", true):
		push_error("TEST slot2 not saved")
	elif not str(info.get("chapter_name", "")).contains("一"):
		push_error("TEST slot2 chapter name wrong")
	GameState.reset_run()
	if not GameState.load_game(2):
		push_error("TEST load slot2 failed")
	if GameState.rescued_total != 5 or GameState.lost_total != 2 \
			or GameState.unlocked_card_ids.size() != 2 or GameState.active_slot != 2:
		push_error("TEST slot2 roundtrip wrong")
	else:
		print("TEST slot2 roundtrip ok")

	if GameState.load_game(3):
		push_error("TEST empty slot3 loaded")

	# 删除存档回环：写槽3 → 摘要非空 → 删除 → 摘要为空
	var f3 := FileAccess.open(GameState.slot_path(3), FileAccess.WRITE)
	f3.store_string(JSON.stringify({"chapter": 3, "rescued_total": 1,
			"lost_total": 0, "unlocked_card_ids": ["ch3_rope"],
			"saved_at": "TEST-DELETE"}))
	f3.close()
	if GameState.slot_info(3).get("empty", true):
		push_error("TEST delete-precondition failed (slot3 not saved)")
	GameState.delete_slot(3)
	if not GameState.slot_info(3).get("empty", false):
		push_error("TEST delete_slot did not clear slot3")
	else:
		print("TEST delete slot roundtrip ok")

	GameState.rescued_count = 3
	GameState.begin_chapter()
	if GameState.rescued_count != 0 or GameState.rescued_total != 5:
		push_error("TEST begin_chapter cleared cumulative")

	ChapterManager.current = 4
	ChapterManager.request_next()
	if ChapterManager.current != 4:
		push_error("TEST request_next switched to unimplemented chapter")
	else:
		print("TEST chapter gate ok")
	ChapterManager.current = 1
