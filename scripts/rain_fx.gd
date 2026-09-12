class_name RainFx
extends Node2D
## 雨幕效果：代码绘制的斜落雨线，无需贴图。覆盖整个世界区域。

const COUNT := 240
const WORLD := Rect2(0, 0, 4800, 1600)

var _drops: Array[Vector2] = []  # 位置
var _speeds: Array[float] = []

func _ready() -> void:
	z_index = 8
	for i in COUNT:
		_drop_spawn(true)

func _drop_spawn(anywhere: bool) -> void:
	var x := randf_range(WORLD.position.x, WORLD.end.x)
	var y := randf_range(WORLD.position.y, WORLD.end.y) if anywhere \
			else randf_range(-80.0, 0.0)
	_drops.append(Vector2(x, y))
	_speeds.append(randf_range(900.0, 1300.0))

func _process(delta: float) -> void:
	for i in _drops.size():
		_drops[i].y += _speeds[i] * delta
		_drops[i].x -= _speeds[i] * 0.18 * delta  # 风向左偏
		if _drops[i].y > WORLD.end.y:
			_drops[i] = Vector2(randf_range(WORLD.position.x, WORLD.end.x), -60.0)
			_speeds[i] = randf_range(900.0, 1300.0)
	queue_redraw()

func _draw() -> void:
	var c := Color(0.75, 0.85, 1.0, 0.45)
	for d in _drops:
		draw_line(d, d + Vector2(-3.0, -16.0), c, 1.4)
