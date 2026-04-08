## NoteField.gd
## Four central fields, each lane-key controlled. Notes are orbs that spawn from
## random screen edges and home toward their lane's field node.
class_name NoteField
extends Node2D

# ---------------------------------------------------------------------------
# Config (set before setup)
# ---------------------------------------------------------------------------
var lane_width: float = 100.0   ## retained for Main compatibility
var field_height: float = 600.0 ## retained for Main compatibility
var hit_line_y: float = 560.0   ## retained for Main compatibility
var scroll_speed: float = 0.55  ## used as speed multiplier

var field_size: Vector2 = Vector2(920.0, 620.0)
const TARGET_RADIUS: float = 34.0
const GRAZE_RADIUS: float = 54.0
const HOVER_RADIUS: float = 128.0
const NOTE_HITBOX_RADIUS: float = 22.0
const NOTE_BASE_TRAVEL_SPEED: float = 320.0
const NOTE_BASE_TURN_RATE: float = 8.0
const MIN_SPAWN_GAP_MS: int = 500
const OFFSCREEN_SPAWN_MARGIN: float = 90.0
const SPAWN_TRAVEL_FUDGE_MS: int = 70

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal note_hit(column: int, delta_ms: float)
signal note_missed(column: int)
signal note_grazed(column: int, delta_ms: float)

# ---------------------------------------------------------------------------
# Runtime state
# ---------------------------------------------------------------------------
var _beatmap: Beatmap
var _spawn_index: int = 0
var _active_notes: Array[Note] = []
var _notes_node: Node2D
var _arena_rect: Rect2 = Rect2(Vector2.ZERO, field_size)
var _arena_center: Vector2 = field_size * 0.5
var _target_centers: Array[Vector2] = []
var _target_active: Array[bool] = [false, false, false, false]
var _last_spawned_time_ms: int = -1000000000

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
func setup() -> void:
	randomize()
	_notes_node = Node2D.new()
	_notes_node.name = "Notes"
	add_child(_notes_node)
	_recompute_layout()

func _recompute_layout() -> void:
	_arena_rect = Rect2(Vector2.ZERO, field_size)
	_arena_center = field_size * 0.5

	var radius := minf(field_size.x, field_size.y) * 0.23
	_target_centers.clear()
	# lane->field mapping: 0=left, 1=top, 2=right, 3=bottom
	_target_centers.append(_arena_center + Vector2(-radius, 0.0))
	_target_centers.append(_arena_center + Vector2(0.0, -radius))
	_target_centers.append(_arena_center + Vector2(radius, 0.0))
	_target_centers.append(_arena_center + Vector2(0.0, radius))

	queue_redraw()

func lane_count() -> int:
	return _beatmap.key_count if _beatmap else 4

func is_chart_complete() -> bool:
	if _beatmap == null:
		return false
	return _spawn_index >= _beatmap.hit_objects.size() and _active_notes.is_empty()

# ---------------------------------------------------------------------------
# Beatmap loading
# ---------------------------------------------------------------------------
func load_beatmap(bm: Beatmap) -> void:
	_beatmap = bm
	_spawn_index = 0
	_last_spawned_time_ms = -1000000000
	for i in _target_active.size():
		_target_active[i] = false
	for n in _active_notes:
		n.queue_free()
	_active_notes.clear()
	_recompute_layout()

# ---------------------------------------------------------------------------
# Per-frame update
# ---------------------------------------------------------------------------
func tick(song_pos_ms: float) -> void:
	if _beatmap == null:
		return
	_spawn_pending(song_pos_ms)
	_update_particles(song_pos_ms)
	queue_redraw()

func _spawn_pending(song_pos_ms: float) -> void:
	while _spawn_index < _beatmap.hit_objects.size():
		var first_obj: Beatmap.HitObject = _beatmap.hit_objects[_spawn_index]

		# Group all notes with the same timestamp, then spawn exactly one random lane.
		var grouped_time_ms := first_obj.time_ms
		var group_start := _spawn_index
		var group_end := group_start + 1
		while group_end < _beatmap.hit_objects.size():
			var next_obj: Beatmap.HitObject = _beatmap.hit_objects[group_end]
			if next_obj.time_ms != grouped_time_ms:
				break
			group_end += 1

		var chosen_index := randi_range(group_start, group_end - 1)
		var chosen_obj: Beatmap.HitObject = _beatmap.hit_objects[chosen_index]

		# Keep minimum spacing tied to chart timing, not visual overlap.
		if chosen_obj.time_ms - _last_spawned_time_ms < MIN_SPAWN_GAP_MS:
			_spawn_index = group_end
			continue

		var target := clampi(chosen_obj.column, 0, 3)
		var target_pos := _target_centers[target]
		var start_pos := _spawn_point_for_obj(chosen_obj, target)
		var speed := _current_travel_speed()
		var travel_ms := int(ceil(start_pos.distance_to(target_pos) / maxf(speed, 1.0) * 1000.0)) + SPAWN_TRAVEL_FUDGE_MS
		var spawn_time_ms := chosen_obj.time_ms - travel_ms
		if song_pos_ms < float(spawn_time_ms):
			break

		_spawn_particle(chosen_obj, start_pos, speed)
		_last_spawned_time_ms = chosen_obj.time_ms
		_spawn_index = group_end

func _spawn_particle(obj: Beatmap.HitObject, start_pos: Vector2, speed: float) -> void:
	var note := Note.new()
	var target := clampi(obj.column, 0, 3)
	var target_pos := _target_centers[target]
	var to_target := target_pos - start_pos
	var initial_vel := to_target.normalized() * speed

	note.setup_particle(start_pos, initial_vel, float(obj.time_ms), target)
	_notes_node.add_child(note)
	_active_notes.append(note)

func _current_travel_speed() -> float:
	return NOTE_BASE_TRAVEL_SPEED * maxf(scroll_speed, 0.10)

func _spawn_point_for_obj(obj: Beatmap.HitObject, target: int) -> Vector2:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(obj.time_ms) * 73856093 + (target + 1) * 19349663
	var side := rng.randi_range(0, 3)
	match side:
		0:
			return Vector2(_arena_rect.position.x - OFFSCREEN_SPAWN_MARGIN, rng.randf_range(_arena_rect.position.y, _arena_rect.end.y))
		1:
			return Vector2(_arena_rect.end.x + OFFSCREEN_SPAWN_MARGIN, rng.randf_range(_arena_rect.position.y, _arena_rect.end.y))
		2:
			return Vector2(rng.randf_range(_arena_rect.position.x, _arena_rect.end.x), _arena_rect.position.y - OFFSCREEN_SPAWN_MARGIN)
		_:
			return Vector2(rng.randf_range(_arena_rect.position.x, _arena_rect.end.x), _arena_rect.end.y + OFFSCREEN_SPAWN_MARGIN)

func _update_particles(song_pos_ms: float) -> void:
	var to_remove: Array[Note] = []
	var delta_s := maxf(get_process_delta_time(), 0.001)

	for note in _active_notes:
		if note.hit or note.missed:
			to_remove.append(note)
			continue

		# Notes only ever resolve against their assigned target center.
		var target_pos := _target_centers[note.target_id]
		var turn_rate := NOTE_BASE_TURN_RATE
		if _target_active[note.target_id]:
			turn_rate *= 1.9
		var travel_speed := _current_travel_speed()
		note.update_motion(delta_s, target_pos, _arena_rect, turn_rate, travel_speed)

		var dist := note.position.distance_to(target_pos)
		var signed_delta := note.hit_time_ms - song_pos_ms

		# All notes resolve against one shared hitbox size, centered on their own target node.
		if dist <= NOTE_HITBOX_RADIUS:
			if _target_active[note.target_id]:
				note.hit = true
				note_hit.emit(note.target_id, signed_delta)
			else:
				note.missed = true
				note_missed.emit(note.target_id)
			to_remove.append(note)
			continue

	for note in to_remove:
		_active_notes.erase(note)
		note.queue_free()

# ---------------------------------------------------------------------------
# Input-driven interactions
# ---------------------------------------------------------------------------
func try_hit(column: int, song_pos_ms: float) -> void:
	pass

func update_hover_zone(mouse_local: Vector2) -> void:
	var hovered := -1
	var best_dist := INF

	for i in _target_centers.size():
		var dist := mouse_local.distance_to(_target_centers[i])
		if dist <= HOVER_RADIUS and dist < best_dist:
			hovered = i
			best_dist = dist

	for i in _target_active.size():
		_target_active[i] = (i == hovered)
	queue_redraw()

func set_field_active(column: int, active: bool) -> void:
	if column < 0 or column >= _target_active.size():
		return
	_target_active[column] = active
	queue_redraw()

func is_field_active(column: int) -> bool:
	if column < 0 or column >= _target_active.size():
		return false
	return _target_active[column]

func get_active_field_summary() -> String:
	var active: Array[String] = []
	if _target_active[0]:
		active.append("F")
	if _target_active[1]:
		active.append("T")
	if _target_active[2]:
		active.append("H")
	if _target_active[3]:
		active.append("G")
	return "+".join(active) if not active.is_empty() else "none"

func flash_receptor(_column: int) -> void:
	pass

# ---------------------------------------------------------------------------
# Visuals
# ---------------------------------------------------------------------------
func _draw() -> void:
	draw_rect(_arena_rect, Color(0.04, 0.05, 0.08), true)
	draw_rect(_arena_rect, Color(0.31, 0.38, 0.50, 0.58), false, 2.0)

	for i in _target_centers.size():
		var core_color := Color(0.58, 0.72, 0.92, 0.42)
		if i == 1:
			core_color = Color(0.97, 0.68, 0.48, 0.42)
		elif i == 2:
			core_color = Color(0.64, 0.96, 0.68, 0.42)
		elif i == 3:
			core_color = Color(0.86, 0.68, 0.98, 0.42)

		if _target_active[i]:
			core_color = Color(core_color.r, core_color.g, core_color.b, 0.85)

		draw_circle(_target_centers[i], GRAZE_RADIUS, Color(core_color.r, core_color.g, core_color.b, 0.12))
		draw_circle(_target_centers[i], TARGET_RADIUS, core_color)
		draw_arc(_target_centers[i], TARGET_RADIUS + 6.0, 0.0, TAU, 48, Color(0.95, 0.98, 1.0, 0.9), 2.0)
