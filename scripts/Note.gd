## Note.gd
## Particle note orb that homes toward one of the four central fields.
class_name Note
extends Node2D

var hit_time_ms: float = 0.0
var target_id: int = 0

var velocity: Vector2 = Vector2.ZERO
var radius: float = 9.0

var hit: bool = false
var missed: bool = false
var grazed: bool = false

var _color: Color = Color(0.35, 0.80, 1.00)

func setup_particle(start_pos: Vector2, initial_velocity: Vector2, note_time_ms: float, target: int) -> void:
	position = start_pos
	velocity = initial_velocity
	hit_time_ms = note_time_ms
	target_id = target
	_color = _color_for_target(target_id)
	queue_redraw()

func update_motion(delta_s: float, target_pos: Vector2, arena_rect: Rect2, turn_rate: float, travel_speed: float) -> void:
	var to_target := target_pos - position
	var desired_dir := to_target.normalized()
	var current_dir := velocity.normalized()
	if current_dir.length_squared() < 0.0001:
		current_dir = desired_dir if desired_dir.length_squared() > 0.0001 else Vector2.RIGHT

	# Constant-speed steering: direction changes over time, magnitude stays fixed.
	var steer_t := clampf(turn_rate * delta_s, 0.0, 1.0)
	var move_dir := current_dir.lerp(desired_dir, steer_t).normalized()
	if move_dir.length_squared() < 0.0001:
		move_dir = current_dir
	velocity = move_dir * travel_speed
	position += velocity * delta_s

	# Soft boundary bounce so particles stay in play.
	var min_x := arena_rect.position.x + radius
	var max_x := arena_rect.end.x - radius
	var min_y := arena_rect.position.y + radius
	var max_y := arena_rect.end.y - radius

	if position.x < min_x:
		position.x = min_x
		velocity.x = absf(velocity.x)
	elif position.x > max_x:
		position.x = max_x
		velocity.x = -absf(velocity.x)

	if position.y < min_y:
		position.y = min_y
		velocity.y = absf(velocity.y)
	elif position.y > max_y:
		position.y = max_y
		velocity.y = -absf(velocity.y)

	if velocity.length_squared() > 0.0001:
		velocity = velocity.normalized() * travel_speed
	else:
		velocity = Vector2.RIGHT * travel_speed

	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, _color)
	draw_circle(Vector2.ZERO, radius + 2.0, Color(_color.r, _color.g, _color.b, 0.28))

func _color_for_target(target: int) -> Color:
	match target:
		0:
			return Color(0.42, 0.85, 1.00)
		1:
			return Color(1.00, 0.62, 0.44)
		2:
			return Color(0.55, 1.00, 0.62)
		_:
			return Color(0.95, 0.74, 1.00)
