class_name SandbagPickup
extends Node2D
## 第三章：可搬运的沙袋。E 拾起后跟随玩家，搬到决口区按 E 放置（共 3 个堵住急流）。

var carried := false

func _ready() -> void:
	add_to_group("interactables")
	set_meta("interact_label", "搬起沙袋")
	_make_visual(Color(0.72, 0.62, 0.42))

func interact(player) -> void:
	if carried or player.carried_bag != null:
		return
	carried = true
	remove_from_group("interactables")
	player.carried_bag = self

func _process(delta: float) -> void:
	if carried:
		var player := get_tree().get_first_node_in_group("player")
		if player != null:
			global_position = global_position.lerp(
					player.global_position + Vector2(14.0 * player.facing, -46.0), 12.0 * delta)

func _make_visual(c: Color) -> void:
	var r := ColorRect.new()
	r.position = Vector2(-16, -12)
	r.size = Vector2(32, 24)
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	var r2 := ColorRect.new()
	r2.position = Vector2(-12, -18)
	r2.size = Vector2(24, 10)
	r2.color = Color(c.r * 0.9, c.g * 0.9, c.b * 0.9)
	r2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r2)
