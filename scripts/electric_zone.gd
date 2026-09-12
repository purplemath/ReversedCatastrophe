class_name ElectricZone
extends Node2D
## 第三章：通电水域（由配电箱控制）。玩家在水中接触会持续受伤。

const DAMAGE := 70.0

var rect := Rect2(3350, 1150, 400, 250)
var switch_box: SwitchBox

func _ready() -> void:
	z_index = 5

func _physics_process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player != null and switch_box != null and switch_box.powered \
			and rect.has_point(player.global_position) and player.is_in_water():
		player.hurt(DAMAGE * delta)
	queue_redraw()

func _draw() -> void:
	var on := switch_box != null and switch_box.powered
	draw_rect(rect, Color(1.0, 0.55, 0.25, 0.22 if on else 0.05))
	if on:
		var f: Font = ThemeDB.fallback_font
		draw_string(f, rect.position + Vector2(20, 40), "⚠ 带电水域",
				HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, 22, Color(1.0, 0.6, 0.3))
		var t := Time.get_ticks_msec() / 120.0
		for i in 4:
			var x := rect.position.x + 60.0 + i * 100.0 + fmod(t, 10.0) * 6.0
			draw_line(Vector2(x, rect.position.y + 10.0), Vector2(x + 12.0, rect.position.y + 50.0),
					Color(1.0, 0.9, 0.4, 0.5), 2.0)
