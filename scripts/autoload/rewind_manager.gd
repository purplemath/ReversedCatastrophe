extends Node
## 局部时间回溯管理器（Braid 式倒带，自动加载）。
## 约定：需要参与回溯的节点加入 "rewindables" 分组，并实现：
##   capture_state() -> Dictionary   每物理帧采集快照
##   restore_state(d: Dictionary)    回放快照
## 可选实现 on_rewind_start() / on_rewind_end()（如刚体在倒带期间冻结）。

signal rewind_started
signal rewind_ended(was_auto: bool)
signal energy_changed(value: float, max_value: float)

const REWIND_GROUP := "rewindables"
const DEFAULT_MAX_SECONDS := 12.0
const REWIND_SPEED := 2.0        # 手动回溯倒放倍速
const AUTO_REWIND_SPEED := 4.0   # 溺水死亡自动回溯倍速
const AUTO_REWIND_SECONDS := 3.0
const ENERGY_REGEN := 0.6        # 静止时每秒恢复的能量（以可回溯秒数计）

var rewinding := false
var auto_rewinding := false
var max_seconds := DEFAULT_MAX_SECONDS
var energy := DEFAULT_MAX_SECONDS

var _frames: Array = []
var _auto_steps_left := 0
var _physics_fps := 60.0


func _ready() -> void:
	_physics_fps = float(Engine.physics_ticks_per_second)
	energy = max_seconds


func increase_max(seconds: float) -> void:
	max_seconds += seconds
	energy = max_seconds  # 升级时回满
	energy_changed.emit(energy, max_seconds)


func reset() -> void:
	rewinding = false
	auto_rewinding = false
	max_seconds = DEFAULT_MAX_SECONDS
	energy = DEFAULT_MAX_SECONDS
	_frames.clear()
	_auto_steps_left = 0


func clear_history() -> void:
	_frames.clear()


func history_frames() -> int:
	return _frames.size()


func _physics_process(delta: float) -> void:
	if rewinding:
		var speed := AUTO_REWIND_SPEED if auto_rewinding else REWIND_SPEED
		for _i in int(speed):
			if not _step_rewind():
				break
		if auto_rewinding and _auto_steps_left <= 0:
			_finish(true)
	else:
		_capture_frame()
		if energy < max_seconds:
			energy = minf(max_seconds, energy + ENERGY_REGEN * delta)
	energy_changed.emit(energy, max_seconds)


func try_start_rewind() -> bool:
	if rewinding or _frames.size() < 2 or energy <= 0.3:
		return false
	_begin(false)
	return true


func begin_auto_rewind(seconds: float = AUTO_REWIND_SECONDS) -> void:
	if rewinding:
		return
	_auto_steps_left = int(seconds * _physics_fps)
	_begin(true)


func _begin(is_auto: bool) -> void:
	rewinding = true
	auto_rewinding = is_auto
	for node in get_tree().get_nodes_in_group(REWIND_GROUP):
		if is_instance_valid(node) and node.has_method("on_rewind_start"):
			node.on_rewind_start()
	rewind_started.emit()


func _finish(was_auto: bool) -> void:
	rewinding = false
	auto_rewinding = false
	for node in get_tree().get_nodes_in_group(REWIND_GROUP):
		if is_instance_valid(node) and node.has_method("on_rewind_end"):
			node.on_rewind_end()
	rewind_ended.emit(was_auto)


func _capture_frame() -> void:
	var frame: Dictionary = {}
	for node in get_tree().get_nodes_in_group(REWIND_GROUP):
		if is_instance_valid(node) and node.has_method("capture_state"):
			frame[node.get_instance_id()] = node.capture_state()
	_frames.append(frame)
	var cap := int(round(max_seconds * _physics_fps))
	while _frames.size() > cap:
		_frames.pop_front()


func _step_rewind() -> bool:
	if _frames.is_empty():
		_finish(auto_rewinding)
		return false
	var frame: Dictionary = _frames.pop_back()
	for id in frame:
		var node = instance_from_id(id)
		if is_instance_valid(node):
			node.restore_state(frame[id])
	if auto_rewinding:
		_auto_steps_left -= 1
	else:
		energy = maxf(0.0, energy - 1.0 / _physics_fps)
		if energy <= 0.0:
			_finish(false)
			return false
	return true
