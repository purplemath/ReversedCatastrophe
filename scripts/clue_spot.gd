class_name ClueSpot
extends Node2D
## 第四章：调查线索点。E 查看，内容计入拼图（集齐 3 条才能拆除装置）。

signal found(clue_text: String)

var collected := false

func _ready() -> void:
	add_to_group("interactables")
	set_meta("interact_label", "查看线索")
	_rebuild()

func interact(_player) -> void:
	if collected:
		return
	collected = true
	set_meta("interact_label", "已查看")
	found.emit(clue_text)
	_rebuild()

func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	var c := Color(1.0, 0.9, 0.4) if not collected else Color(0.5, 0.5, 0.5, 0.6)
	var r := ColorRect.new()
	r.position = Vector2(-10, -14)
	r.size = Vector2(20, 28)
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	var beam := ColorRect.new()
	beam.position = Vector2(-10, -30)
	beam.size = Vector2(20, 14)
	beam.color = Color(c.r, c.g, c.b, 0.5)
	beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(beam)

var clue_text := ""
