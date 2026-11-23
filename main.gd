extends Node2D
## Snake. Everything (board, snake, food and text) is drawn in _draw(),
## which runs every frame, so there are no other nodes to manage.

const GRID := 20                 # board is GRID x GRID cells
const START_STEP := 0.16         # seconds per move at the start
const MIN_STEP := 0.06           # fastest it gets
const STEP_FASTER := 0.004       # each food makes moves this much quicker
const FOOD_POINTS := 10
const SWIPE_PX := 30.0           # finger travel that counts as a swipe
const RESTART_DELAY := 0.5       # ignore input right after dying, so a late swipe doesn't restart

const GOLD := Color("#ffd700")
const BOARD_COLOR := Color("#262626")
const GRID_COLOR := Color(1, 1, 1, 0.04)
const BODY_COLOR := Color("#5fbf3f")
const HEAD_COLOR := Color("#9be870")

# World record shared by everyone. The database rules only accept a higher number.
const RECORD_URL := "https://auuuuu-83d66-default-rtdb.europe-west1.firebasedatabase.app/records/snake.json"
const RECORD_REFRESH := 15.0     # seconds between record checks
const SAVE_PATH := "user://save.cfg"  # in a browser this lives in the site's local storage

enum State { READY, PLAYING, OVER }

var state := State.READY
var snake: Array[Vector2i] = []  # snake[0] is the head
var dir := Vector2i.RIGHT
var turns: Array[Vector2i] = []  # directions pressed but not used yet
var food := Vector2i.ZERO
var step_time := START_STEP
var step_left := 0.0
var score := 0
var best := 0
var new_best := false
var record := -1                 # -1 until loaded
var over_time := 0.0
var clock := 0.0                 # for the food pulse
var swipe_from := Vector2.ZERO
var swiping := false

var uploads_enabled := true
var record_request: HTTPRequest
var upload_request: HTTPRequest
var loading_record := false


func _ready() -> void:
	randomize()
	load_best()
	# Local test builds must never write fake scores to the shared record
	uploads_enabled = not is_local_test()

	record_request = HTTPRequest.new()
	add_child(record_request)
	record_request.request_completed.connect(_on_record_loaded)
	upload_request = HTTPRequest.new()
	add_child(upload_request)
	upload_request.request_completed.connect(_on_record_uploaded)

	var timer := Timer.new()
	timer.wait_time = RECORD_REFRESH
	timer.autostart = true
	add_child(timer)
	timer.timeout.connect(fetch_record)
	fetch_record()

	reset()


func reset() -> void:
	var mid := GRID / 2
	snake = [Vector2i(mid, mid), Vector2i(mid - 1, mid), Vector2i(mid - 2, mid)]
	dir = Vector2i.RIGHT
	turns.clear()
	step_time = START_STEP
	step_left = step_time
	score = 0
	new_best = false
	spawn_food()
	state = State.READY


func _process(delta: float) -> void:
	clock += delta
	if state == State.PLAYING:
		step_left -= delta
		while step_left <= 0.0 and state == State.PLAYING:
			step_left += step_time
			step()
	elif state == State.OVER:
		over_time += delta
	queue_redraw()


func step() -> void:
	if not turns.is_empty():
		dir = turns.pop_front()
	var head := snake[0] + dir
	var eating := head == food
	# The tail moves out of the way this step unless we're growing
	var body := snake if eating else snake.slice(0, snake.size() - 1)
	if head.x < 0 or head.y < 0 or head.x >= GRID or head.y >= GRID or body.has(head):
		game_over()
		return
	snake.push_front(head)
	if eating:
		score += FOOD_POINTS
		if score > best:
			best = score
			new_best = true
		step_time = max(MIN_STEP, step_time - STEP_FASTER)
		if not spawn_food():
			game_over()  # the board is full, you won
	else:
		snake.pop_back()


func spawn_food() -> bool:
	var free: Array[Vector2i] = []
	for y in GRID:
		for x in GRID:
			var cell := Vector2i(x, y)
			if not snake.has(cell):
				free.append(cell)
	if free.is_empty():
		return false
	food = free.pick_random()
	return true


func game_over() -> void:
	state = State.OVER
	over_time = 0.0
	if new_best:
		save_best()
	if record >= 0 and score > record:
		upload_record(score)


# --- Input: arrows / WASD on a keyboard, swipes on a touch screen ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if state == State.OVER:
			try_restart()  # any key plays again
			return
		match event.keycode:
			KEY_UP, KEY_W: turn(Vector2i.UP)
			KEY_DOWN, KEY_S: turn(Vector2i.DOWN)
			KEY_LEFT, KEY_A: turn(Vector2i.LEFT)
			KEY_RIGHT, KEY_D: turn(Vector2i.RIGHT)
	elif event is InputEventScreenTouch:
		swiping = event.pressed
		swipe_from = event.position
		if event.pressed:
			try_restart()
	elif event is InputEventScreenDrag and swiping:
		var moved: Vector2 = event.position - swipe_from
		if moved.length() >= SWIPE_PX:
			# Keep the finger down and swipe again to make another turn
			swipe_from = event.position
			if abs(moved.x) > abs(moved.y):
				turn(Vector2i.RIGHT if moved.x > 0 else Vector2i.LEFT)
			else:
				turn(Vector2i.DOWN if moved.y > 0 else Vector2i.UP)


func turn(d: Vector2i) -> void:
	if state == State.OVER:
		try_restart()  # a swipe also plays again
		return
	# Compare with the last planned direction so quick double turns work
	var last: Vector2i = dir if turns.is_empty() else turns.back()
	if d == last or d == -last or turns.size() >= 3:
		return
	turns.append(d)
	if state == State.READY:
		state = State.PLAYING
		step_left = 0.0  # move right away


func try_restart() -> void:
	if state == State.OVER and over_time >= RESTART_DELAY:
		reset()


# --- Drawing ---

func _draw() -> void:
	var size := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	var top := 170.0
	var margin := 20.0
	var cell := floorf(minf(size.x - margin * 2, size.y - top - margin) / GRID)
	var board := cell * GRID
	var origin := Vector2(floorf((size.x - board) / 2), top + floorf((size.y - top - margin - board) / 2))

	# Header: title, score, your best on the left, world record on the right
	draw_string(font, Vector2(0, 60), "SNAKE", HORIZONTAL_ALIGNMENT_CENTER, size.x, 44, GOLD)
	draw_string(font, Vector2(0, 120), "Score  %d" % score, HORIZONTAL_ALIGNMENT_CENTER, size.x, 34, Color.WHITE)
	draw_string(font, Vector2(margin, 40), "Your best", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.7))
	draw_string(font, Vector2(margin, 72), str(best), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)
	draw_string(font, Vector2(0, 40), "World record", HORIZONTAL_ALIGNMENT_RIGHT, size.x - margin, 20, Color(GOLD, 0.8))
	draw_string(font, Vector2(0, 72), "–" if record < 0 else str(record),
		HORIZONTAL_ALIGNMENT_RIGHT, size.x - margin, 30, GOLD)

	# Board with faint grid lines and a gold frame
	draw_rect(Rect2(origin, Vector2(board, board)), BOARD_COLOR)
	for i in range(1, GRID):
		draw_line(origin + Vector2(i * cell, 0), origin + Vector2(i * cell, board), GRID_COLOR)
		draw_line(origin + Vector2(0, i * cell), origin + Vector2(board, i * cell), GRID_COLOR)
	draw_rect(Rect2(origin - Vector2(3, 3), Vector2(board + 6, board + 6)), GOLD, false, 3.0)

	# Food: a pulsing gold coin
	var pulse := 0.36 + 0.06 * sin(clock * 6.0)
	var food_center := origin + (Vector2(food) + Vector2(0.5, 0.5)) * cell
	draw_circle(food_center, cell * pulse, GOLD)
	draw_circle(food_center, cell * pulse * 0.55, Color("#e6b800"))

	# Snake: each segment is an inset square, joined to the next one so the body looks solid
	var inset := maxf(2.0, cell * 0.1)
	for i in snake.size():
		var color := HEAD_COLOR if i == 0 else BODY_COLOR
		var pos := origin + Vector2(snake[i]) * cell
		draw_rect(Rect2(pos + Vector2(inset, inset), Vector2(cell - inset * 2, cell - inset * 2)), color)
		if i + 1 < snake.size():
			var between := origin + (Vector2(snake[i]) + Vector2(snake[i + 1])) * 0.5 * cell
			draw_rect(Rect2(between + Vector2(inset, inset), Vector2(cell - inset * 2, cell - inset * 2)), BODY_COLOR)
	draw_eyes(origin, cell)

	# Messages on top of the board
	var center_y := origin.y + board / 2
	if state == State.READY:
		draw_banner(origin, board, center_y, ["Swipe or press an arrow", "to start"], [30, 30], [Color.WHITE, Color.WHITE])
	elif state == State.OVER:
		var lines := ["GAME OVER", "Score %d" % score]
		var sizes := [52, 32]
		var colors := [GOLD, Color.WHITE]
		if new_best:
			lines.append("New personal best!")
			sizes.append(26)
			colors.append(GOLD)
		if over_time >= RESTART_DELAY:
			lines.append("Tap or press a key")
			sizes.append(24)
			colors.append(Color(1, 1, 1, 0.7))
		draw_banner(origin, board, center_y, lines, sizes, colors)


func draw_eyes(origin: Vector2, cell: float) -> void:
	var center := origin + (Vector2(snake[0]) + Vector2(0.5, 0.5)) * cell
	var forward := Vector2(dir) * cell * 0.15
	var side := Vector2(-dir.y, dir.x) * cell * 0.2
	for s in [-1, 1]:
		draw_circle(center + forward + side * s, cell * 0.09, Color.BLACK)


func draw_banner(origin: Vector2, board: float, center_y: float, lines: Array, sizes: Array, colors: Array) -> void:
	var height := 0.0
	for s in sizes:
		height += s * 1.4
	draw_rect(Rect2(Vector2(origin.x, center_y - height / 2 - 20), Vector2(board, height + 40)), Color(0, 0, 0, 0.75))
	var y := center_y - height / 2
	var font := ThemeDB.fallback_font
	for i in lines.size():
		y += sizes[i] * 1.4
		draw_string(font, Vector2(origin.x, y - sizes[i] * 0.4), lines[i], HORIZONTAL_ALIGNMENT_CENTER, board, sizes[i], colors[i])


# --- Personal best, saved on this device ---

func load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best = int(cfg.get_value("score", "best", 0))


func save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("score", "best", best)
	cfg.save(SAVE_PATH)


# --- World record in Firebase (plain REST calls) ---

func is_local_test() -> bool:
	if not OS.has_feature("web"):
		return true  # runs from the editor or a desktop build
	var host := str(JavaScriptBridge.eval("location.hostname"))
	return host in ["localhost", "127.0.0.1", ""]


func fetch_record() -> void:
	if loading_record:
		return
	loading_record = true
	if record_request.request(RECORD_URL) != OK:
		loading_record = false


func _on_record_loaded(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	loading_record = false
	if code != 200:
		return
	var value = JSON.parse_string(body.get_string_from_utf8())
	var remote := int(value) if value is float else 0  # null means nobody has played yet
	record = max(record, remote)


func upload_record(value: int) -> void:
	record = value  # show it straight away; the next check corrects it if someone beat us
	if not uploads_enabled:
		return
	upload_request.cancel_request()
	upload_request.request(RECORD_URL, ["Content-Type: application/json"], HTTPClient.METHOD_PUT, str(value))


func _on_record_uploaded(_result: int, _code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	fetch_record()
