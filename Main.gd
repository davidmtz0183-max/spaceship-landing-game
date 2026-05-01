extends Node2D

# Planet Landing Simulator
# Godot 4.6 version. This is intentionally one main script so it is easier to open,
# read, and explain for the project.

const SCREEN_SIZE: Vector2 = Vector2(1152, 648)
const SHIP_RADIUS: float = 12.0
const PLANET_RADIUS: float = 90.0
const BLACK_HOLE_RADIUS: float = 42.0
const LANDING_PAD_ANGLE: float = -PI / 2.0
const LANDING_PAD_HALF_WIDTH: float = deg_to_rad(22.0)
const SAFE_LANDING_SPEED: float = 85.0
const SAFE_LANDING_ANGLE: float = deg_to_rad(38.0)
const THRUST_ACCEL: float = 230.0
const ROTATE_SPEED: float = 2.9
const BRAKE_DAMPING: float = 0.985
const FUEL_BURN_RATE: float = 18.0
const GRAVITY_PLANET: float = 820000.0
const GRAVITY_BLACK_HOLE: float = 760000.0
const LEADERBOARD_LIMIT: int = 5
const LEADERBOARD_FILE: String = "user://planet_landing_leaderboard.json"
const NAME_LETTERS: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

var ship_pos: Vector2 = Vector2(180, 235)
var ship_vel: Vector2 = Vector2(62, -12)
var ship_angle: float = 0.0
var fuel: float = 100.0
var score: int = 0
var best_score: int = 0
var time_alive: float = 0.0
var game_state: String = "title"
var message: String = ""
var acceleration: Vector2 = Vector2.ZERO
var trail: Array[Vector2] = []
var stars: Array[Vector2] = []
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var leaderboard: Array[Dictionary] = []
var current_name: String = "AAA"
var name_cursor: int = 0
var pending_score: int = 0
var pending_time: float = 0.0
var pending_result_text: String = ""

var planet_pos: Vector2 = Vector2(790, 395)
var black_hole_pos: Vector2 = Vector2(430, 160)

func _ready() -> void:
	rng.randomize()
	load_leaderboard()
	for i: int in range(145):
		stars.append(Vector2(rng.randf_range(0.0, SCREEN_SIZE.x), rng.randf_range(0.0, SCREEN_SIZE.y)))
	reset_game(false)
	set_process(true)

func reset_game(start_playing: bool = true) -> void:
	ship_pos = Vector2(175, 250)
	ship_vel = Vector2(62, -18)
	ship_angle = -0.08
	fuel = 100.0
	score = 0
	time_alive = 0.0
	acceleration = Vector2.ZERO
	trail.clear()
	message = ""
	if start_playing:
		game_state = "playing"
	else:
		game_state = "title"

func _process(delta: float) -> void:
	if Input.is_key_pressed(KEY_ESCAPE):
		get_tree().quit()

	if game_state == "title":
		if Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_SPACE):
			reset_game(true)
		queue_redraw()
		return

	if game_state == "name_entry":
		queue_redraw()
		return

	if game_state == "landed" or game_state == "crashed":
		if Input.is_key_pressed(KEY_R):
			reset_game(true)
		queue_redraw()
		return

	update_playing(delta)
	queue_redraw()

func update_playing(delta: float) -> void:
	time_alive += delta

	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		ship_angle -= ROTATE_SPEED * delta
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		ship_angle += ROTATE_SPEED * delta

	acceleration = Vector2.ZERO
	acceleration += gravity_from(planet_pos, GRAVITY_PLANET, 70.0)
	acceleration += gravity_from(black_hole_pos, GRAVITY_BLACK_HOLE, 45.0)

	if (Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_SPACE)) and fuel > 0.0:
		var thrust_dir: Vector2 = Vector2.RIGHT.rotated(ship_angle)
		acceleration += thrust_dir * THRUST_ACCEL
		fuel = maxf(0.0, fuel - FUEL_BURN_RATE * delta)

	ship_vel += acceleration * delta

	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		ship_vel *= pow(BRAKE_DAMPING, delta * 60.0)

	ship_pos += ship_vel * delta
	wrap_or_crash_boundary()

	trail.append(ship_pos)
	if trail.size() > 155:
		trail.pop_front()

	check_collisions()

	score = int(time_alive * 10.0 + (100.0 - ship_vel.length()) * 0.15 + fuel * 0.4)
	if score < int(time_alive * 10.0):
		score = int(time_alive * 10.0)

func gravity_from(source: Vector2, strength: float, min_distance: float) -> Vector2:
	var offset: Vector2 = source - ship_pos
	var dist_sq: float = maxf(offset.length_squared(), min_distance * min_distance)
	return offset.normalized() * (strength / dist_sq)

func wrap_or_crash_boundary() -> void:
	if ship_pos.x < 20.0 or ship_pos.x > SCREEN_SIZE.x - 20.0 or ship_pos.y < 20.0 or ship_pos.y > SCREEN_SIZE.y - 20.0:
		ship_vel *= -0.45
		ship_pos.x = clampf(ship_pos.x, 20.0, SCREEN_SIZE.x - 20.0)
		ship_pos.y = clampf(ship_pos.y, 20.0, SCREEN_SIZE.y - 20.0)

func check_collisions() -> void:
	var planet_distance: float = ship_pos.distance_to(planet_pos)
	var black_hole_distance: float = ship_pos.distance_to(black_hole_pos)

	if black_hole_distance < BLACK_HOLE_RADIUS + SHIP_RADIUS:
		crash("The ship was pulled into the black hole.")
		return

	if planet_distance <= PLANET_RADIUS + SHIP_RADIUS:
		var angle_to_ship: float = (ship_pos - planet_pos).angle()
		var angle_error: float = absf(angle_difference(angle_to_ship, LANDING_PAD_ANGLE))
		var ship_upright_error: float = absf(angle_difference(ship_angle, LANDING_PAD_ANGLE))
		var safe_speed: bool = ship_vel.length() <= SAFE_LANDING_SPEED
		var on_pad: bool = angle_error <= LANDING_PAD_HALF_WIDTH
		var angle_ok: bool = ship_upright_error <= SAFE_LANDING_ANGLE

		if on_pad and safe_speed and angle_ok:
			finish_run("landed", "SAFE LANDING! Final Score: " + str(score))
		else:
			var reason: String = "Crashed. "
			if not on_pad:
				reason += "You missed the landing pad. "
			if not safe_speed:
				reason += "Speed was too high. "
			if not angle_ok:
				reason += "Ship angle was unsafe. "
			crash(reason)

func crash(reason: String) -> void:
	finish_run("crashed", reason + "\nFinal Score: " + str(score))

func finish_run(result_state: String, result_text: String) -> void:
	best_score = maxi(best_score, score)
	if is_high_score(score):
		game_state = "name_entry"
		pending_score = score
		pending_time = time_alive
		pending_result_text = result_text
		current_name = "AAA"
		name_cursor = 0
	else:
		game_state = result_state
		message = result_text + "\nPress R to restart."

func is_high_score(new_score: int) -> bool:
	if leaderboard.size() < LEADERBOARD_LIMIT:
		return true
	var lowest_score: int = int(leaderboard[leaderboard.size() - 1].get("score", 0))
	return new_score > lowest_score

func save_current_score() -> void:
	leaderboard.append({"name": current_name, "score": pending_score, "time": pending_time})
	leaderboard.sort_custom(compare_scores)
	while leaderboard.size() > LEADERBOARD_LIMIT:
		leaderboard.remove_at(leaderboard.size() - 1)
	save_leaderboard()
	game_state = "landed"
	message = pending_result_text + "\nScore saved as " + current_name + ". Press R to restart."

func compare_scores(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("score", 0)) > int(b.get("score", 0))

func load_leaderboard() -> void:
	leaderboard.clear()
	if not FileAccess.file_exists(LEADERBOARD_FILE):
		return
	var file: FileAccess = FileAccess.open(LEADERBOARD_FILE, FileAccess.READ)
	if file == null:
		return
	var text: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_ARRAY:
		return
	var parsed_array: Array = parsed
	for item: Variant in parsed_array:
		if typeof(item) == TYPE_DICTIONARY:
			var entry: Dictionary = item
			leaderboard.append({"name": str(entry.get("name", "AAA")).substr(0, 3), "score": int(entry.get("score", 0)), "time": float(entry.get("time", 0.0))})
	leaderboard.sort_custom(compare_scores)
	while leaderboard.size() > LEADERBOARD_LIMIT:
		leaderboard.remove_at(leaderboard.size() - 1)
	if leaderboard.size() > 0:
		best_score = int(leaderboard[0].get("score", 0))

func save_leaderboard() -> void:
	var file: FileAccess = FileAccess.open(LEADERBOARD_FILE, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(leaderboard))

func angle_difference(a: float, b: float) -> float:
	return atan2(sin(a - b), cos(a - b))

func _unhandled_input(event: InputEvent) -> void:
	if game_state != "name_entry":
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event
		if not key_event.pressed or key_event.echo:
			return
		if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER:
			save_current_score()
			queue_redraw()
			return
		if key_event.keycode == KEY_LEFT:
			name_cursor = maxi(0, name_cursor - 1)
			queue_redraw()
			return
		if key_event.keycode == KEY_RIGHT:
			name_cursor = mini(2, name_cursor + 1)
			queue_redraw()
			return
		if key_event.keycode == KEY_UP:
			change_name_letter(1)
			queue_redraw()
			return
		if key_event.keycode == KEY_DOWN:
			change_name_letter(-1)
			queue_redraw()
			return
		if key_event.keycode >= KEY_A and key_event.keycode <= KEY_Z:
			var letter_index: int = int(key_event.keycode) - int(KEY_A)
			set_name_letter(NAME_LETTERS.substr(letter_index, 1))
			name_cursor = mini(2, name_cursor + 1)
			queue_redraw()

func change_name_letter(direction: int) -> void:
	var current_letter: String = current_name.substr(name_cursor, 1)
	var letter_index: int = NAME_LETTERS.find(current_letter)
	if letter_index < 0:
		letter_index = 0
	letter_index = (letter_index + direction + NAME_LETTERS.length()) % NAME_LETTERS.length()
	set_name_letter(NAME_LETTERS.substr(letter_index, 1))

func set_name_letter(letter: String) -> void:
	current_name = current_name.substr(0, name_cursor) + letter + current_name.substr(name_cursor + 1, 2 - name_cursor)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN_SIZE), Color(0.025, 0.035, 0.09))
	draw_stars()
	draw_gravity_fields()
	draw_planet()
	draw_black_hole()
	draw_trail()
	draw_ship()
	draw_hud()

	if game_state == "title":
		draw_center_text("PLANET LANDING SIMULATOR", 168.0, 34, Color(0.9, 0.95, 1.0))
		draw_center_text("Use A/D to rotate, W or Space for thrust, S to brake", 218.0, 19, Color(0.85, 0.9, 1.0))
		draw_center_text("Land slowly on the green pad. Avoid the black hole.", 251.0, 19, Color(0.85, 0.9, 1.0))
		draw_center_text("Press Enter or Space to start", 303.0, 23, Color(0.4, 1.0, 0.65))
		draw_leaderboard(Vector2(425.0, 350.0), true)
	elif game_state == "name_entry":
		draw_overlay(Color(0.0, 0.0, 0.0, 0.68))
		draw_name_entry()
	elif game_state == "landed":
		draw_overlay(Color(0.0, 0.25, 0.08, 0.55))
		draw_multiline_center(message, 205.0, 26, Color(0.65, 1.0, 0.72))
		draw_leaderboard(Vector2(425.0, 340.0), false)
	elif game_state == "crashed":
		draw_overlay(Color(0.26, 0.02, 0.02, 0.58))
		draw_multiline_center(message, 175.0, 24, Color(1.0, 0.73, 0.67))
		draw_leaderboard(Vector2(425.0, 360.0), false)

func draw_stars() -> void:
	for i: int in range(stars.size()):
		var s: Vector2 = stars[i]
		var shade: float = 0.45 + float(i % 7) * 0.07
		draw_circle(s, 1.0 + float(i % 3) * 0.35, Color(shade, shade, shade + 0.1, 0.9))

func draw_gravity_fields() -> void:
	draw_arc(planet_pos, PLANET_RADIUS + 45.0, 0.0, TAU, 96, Color(0.2, 0.45, 1.0, 0.17), 2.0)
	draw_arc(planet_pos, PLANET_RADIUS + 85.0, 0.0, TAU, 96, Color(0.2, 0.45, 1.0, 0.10), 2.0)
	draw_arc(black_hole_pos, BLACK_HOLE_RADIUS + 45.0, 0.0, TAU, 96, Color(0.8, 0.1, 1.0, 0.18), 2.0)
	draw_arc(black_hole_pos, BLACK_HOLE_RADIUS + 85.0, 0.0, TAU, 96, Color(0.8, 0.1, 1.0, 0.10), 2.0)

func draw_planet() -> void:
	draw_circle(planet_pos, PLANET_RADIUS, Color(0.05, 0.22, 0.75))
	draw_circle(planet_pos + Vector2(-20.0, -18.0), PLANET_RADIUS * 0.72, Color(0.04, 0.31, 0.95, 0.9))
	draw_circle(planet_pos + Vector2(18.0, 25.0), 28.0, Color(0.12, 0.55, 0.25, 0.75))
	draw_circle(planet_pos + Vector2(-34.0, -8.0), 21.0, Color(0.12, 0.55, 0.25, 0.7))
	draw_arc(planet_pos, PLANET_RADIUS + 5.0, LANDING_PAD_ANGLE - LANDING_PAD_HALF_WIDTH, LANDING_PAD_ANGLE + LANDING_PAD_HALF_WIDTH, 20, Color(0.2, 1.0, 0.25), 10.0)
	draw_string(ThemeDB.fallback_font, planet_pos + Vector2(-43.0, PLANET_RADIUS + 36.0), "LANDING PAD", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(0.55, 1.0, 0.55))

func draw_black_hole() -> void:
	draw_circle(black_hole_pos, BLACK_HOLE_RADIUS + 12.0, Color(0.48, 0.1, 0.75, 0.65))
	draw_circle(black_hole_pos, BLACK_HOLE_RADIUS, Color(0.01, 0.0, 0.02))
	draw_arc(black_hole_pos, BLACK_HOLE_RADIUS + 18.0, 0.0, TAU, 90, Color(0.8, 0.35, 1.0, 0.75), 4.0)
	draw_string(ThemeDB.fallback_font, black_hole_pos + Vector2(-43.0, -62.0), "BLACK HOLE", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(0.95, 0.7, 1.0))

func draw_trail() -> void:
	if trail.size() < 2:
		return
	for i: int in range(1, trail.size()):
		var alpha: float = float(i) / float(trail.size())
		draw_line(trail[i - 1], trail[i], Color(0.6, 0.82, 1.0, alpha * 0.55), 2.0)


func draw_name_entry() -> void:
	draw_multiline_center(pending_result_text, 140.0, 24, Color(0.85, 1.0, 0.9))
	draw_center_text("NEW HIGH SCORE!", 240.0, 34, Color(1.0, 0.86, 0.25))
	draw_center_text("Enter your 3-character name", 286.0, 20, Color(0.9, 0.95, 1.0))
	var font: Font = ThemeDB.fallback_font
	var start_x: float = SCREEN_SIZE.x / 2.0 - 75.0
	for i: int in range(3):
		var letter: String = current_name.substr(i, 1)
		var x: float = start_x + float(i) * 50.0
		draw_string(font, Vector2(x, 358.0), letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 42, Color.WHITE)
		if i == name_cursor:
			draw_line(Vector2(x, 368.0), Vector2(x + 28.0, 368.0), Color(0.4, 1.0, 0.65), 4.0)
	draw_center_text("Type letters or use Arrow Keys. Press Enter to save.", 415.0, 18, Color(0.75, 0.85, 1.0))
	draw_leaderboard(Vector2(425.0, 460.0), false)

func draw_leaderboard(top_left: Vector2, title_big: bool) -> void:
	var font: Font = ThemeDB.fallback_font
	var title_size: int = 22
	if title_big:
		title_size = 24
	draw_rect(Rect2(top_left.x, top_left.y, 302.0, 160.0), Color(0.0, 0.0, 0.0, 0.42))
	draw_rect(Rect2(top_left.x, top_left.y, 302.0, 160.0), Color(0.6, 0.75, 1.0, 0.45), false, 2.0)
	draw_string(font, top_left + Vector2(78.0, 30.0), "HIGH SCORES", HORIZONTAL_ALIGNMENT_LEFT, -1.0, title_size, Color(1.0, 0.9, 0.35))
	if leaderboard.is_empty():
		draw_string(font, top_left + Vector2(48.0, 86.0), "No scores yet", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color(0.85, 0.9, 1.0))
		return
	for i: int in range(leaderboard.size()):
		var entry: Dictionary = leaderboard[i]
		var row_y: float = top_left.y + 60.0 + float(i) * 20.0
		var row: String = str(i + 1) + ". " + str(entry.get("name", "AAA")) + "   " + str(int(entry.get("score", 0))) + "   " + format_time(float(entry.get("time", 0.0)))
		draw_string(font, Vector2(top_left.x + 32.0, row_y), row, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color.WHITE)

func draw_ship() -> void:
	var forward: Vector2 = Vector2.RIGHT.rotated(ship_angle)
	var right: Vector2 = Vector2.DOWN.rotated(ship_angle)
	var p1: Vector2 = ship_pos + forward * 20.0
	var p2: Vector2 = ship_pos - forward * 16.0 + right * 11.0
	var p3: Vector2 = ship_pos - forward * 16.0 - right * 11.0
	var color: Color = Color(0.92, 0.95, 1.0)
	if game_state == "crashed":
		color = Color(1.0, 0.36, 0.24)
	draw_colored_polygon(PackedVector2Array([p1, p2, p3]), color)
	draw_polyline(PackedVector2Array([p1, p2, p3, p1]), Color(0.15, 0.2, 0.28), 2.0)
	if game_state == "playing" and (Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_SPACE)) and fuel > 0.0:
		var flame1: Vector2 = ship_pos - forward * 18.0
		var flame2: Vector2 = ship_pos - forward * 34.0 + right * 6.0
		var flame3: Vector2 = ship_pos - forward * 34.0 - right * 6.0
		draw_colored_polygon(PackedVector2Array([flame1, flame2, flame3]), Color(1.0, 0.55, 0.12))

func draw_hud() -> void:
	var speed: float = ship_vel.length()
	var altitude: float = maxf(0.0, ship_pos.distance_to(planet_pos) - PLANET_RADIUS)
	var acc: float = acceleration.length()
	draw_rect(Rect2(16.0, 16.0, 314.0, 154.0), Color(0.0, 0.0, 0.0, 0.38))
	draw_rect(Rect2(16.0, 16.0, 314.0, 154.0), Color(0.4, 0.55, 0.9, 0.55), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(31.0, 43.0), "Score: " + str(score) + "     Best: " + str(best_score), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(31.0, 68.0), "Time: " + format_time(time_alive), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(31.0, 93.0), "Speed: " + str(round(speed)) + " px/s", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, speed_color(speed))
	draw_string(ThemeDB.fallback_font, Vector2(31.0, 118.0), "Altitude: " + str(round(altitude)) + " px", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(31.0, 143.0), "Acceleration: " + str(round(acc)) + " px/s^2", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color.WHITE)
	draw_rect(Rect2(860.0, 24.0, 245.0, 24.0), Color(0.05, 0.05, 0.08, 0.78))
	draw_rect(Rect2(863.0, 27.0, 239.0 * fuel / 100.0, 18.0), Color(0.95, 0.78, 0.20))
	draw_rect(Rect2(860.0, 24.0, 245.0, 24.0), Color(0.95, 0.95, 1.0, 0.6), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(930.0, 43.0), "Fuel " + str(round(fuel)) + "%", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(770.0, 625.0), "Goal: land on green pad under " + str(SAFE_LANDING_SPEED) + " px/s | R restart | Esc quit", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(0.8, 0.88, 1.0))

func speed_color(speed: float) -> Color:
	if speed <= SAFE_LANDING_SPEED:
		return Color(0.55, 1.0, 0.55)
	if speed <= SAFE_LANDING_SPEED * 1.6:
		return Color(1.0, 0.88, 0.35)
	return Color(1.0, 0.45, 0.32)

func draw_overlay(color: Color) -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN_SIZE), color)

func draw_center_text(text: String, y: float, size: int, color: Color) -> void:
	var font: Font = ThemeDB.fallback_font
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size)
	draw_string(font, Vector2((SCREEN_SIZE.x - text_size.x) / 2.0, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)

func draw_multiline_center(text: String, y: float, size: int, color: Color) -> void:
	var lines: PackedStringArray = text.split("\n")
	for i: int in range(lines.size()):
		draw_center_text(lines[i], y + float(i) * float(size + 12), size, color)

func format_time(seconds: float) -> String:
	var total: int = int(seconds)
	var mins: int = int(total / 60)
	var secs: int = total % 60
	return "%02d:%02d" % [mins, secs]
