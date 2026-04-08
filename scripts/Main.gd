## Main.gd
## Root scene script. Builds menu/game UI, imports osu beatmaps, and drives gameplay.
extends Node2D

# ---------------------------------------------------------------------------
# Layout constants
# ---------------------------------------------------------------------------
const VIEWPORT_W: float = 1280.0
const VIEWPORT_H: float = 720.0
const LANE_WIDTH: float = 110.0
const DEFAULT_SCROLL_SPEED: float = 0.55
const LANE_KEYS: Array[int] = [KEY_F, KEY_T, KEY_H, KEY_G]

const MENU_MUSIC_PATH: String = "res://assets/audio/Chrome Broth.wav"
const LIBRARY_SAVE_PATH: String = "user://imported_beatmaps.json"
const WEB_IMPORT_DIR: String = "user://web_imports"

# ---------------------------------------------------------------------------
# Game systems
# ---------------------------------------------------------------------------
var _clock: AudioClock
var _music: AudioStreamPlayer
var _menu_music: AudioStreamPlayer
var _leaderboard_service
var _field: NoteField
var _beatmap: Beatmap

# ---------------------------------------------------------------------------
# Scene references
# ---------------------------------------------------------------------------
var _game_root: Node2D
var _menu_layer: CanvasLayer
var _game_ui: CanvasLayer

var _score_label: Label
var _combo_label: Label
var _judge_label: Label
var _debug_label: Label
var _key_hint_label: Label

var _menu_title_label: Label
var _menu_map_label: RichTextLabel
var _menu_status_label: Label
var _leaderboard_hint_label: Label
var _library_count_label: Label
var _library_status_label: Label
var _library_list: VBoxContainer
var _difficulty_select: OptionButton
var _offset_spin: SpinBox
var _scroll_speed_spin: SpinBox
var _mouse_sensitivity_spin: SpinBox
var _start_button: Button
var _file_dialog: FileDialog

# ---------------------------------------------------------------------------
# Runtime state
# ---------------------------------------------------------------------------
enum State { MENU, COUNTDOWN, PLAYING }
var _state: State = State.MENU

var _score: int = 0
var _combo: int = 0
var _song_finish_ms: float = 0.0
var _imported_4k_maps: Array[Beatmap] = []
var _library_entries: Array[Dictionary] = []
var _user_audio_offset_ms: float = 0.0
var _user_scroll_speed: float = DEFAULT_SCROLL_SPEED
var _user_mouse_sensitivity: float = 1.0
var _recovery_until_ms: float = 0.0
var _web_import_callback: Variant = null
var _web_bridge_ready: bool = false

var _judge_display_secs: float = 0.0
const JUDGE_SHOW_DURATION: float = 0.55

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	_build_scene()
	_setup_web_import_bridge()
	_load_library_from_disk()
	if OS.has_feature("web"):
		_set_menu_status("Import an osu!mania .osu/.osz (4K only). Saved charts appear in the right-side library.\nWeb: click Import to pick local files, or drag and drop files onto the page.")
	else:
		_set_menu_status("Import an osu!mania .osu/.osz (4K only). Saved charts appear in the right-side library.")
	_update_menu_map_label()
	_enter_menu()
	_start_menu_music()

func _build_scene() -> void:
	# Shared audio players
	_music = AudioStreamPlayer.new()
	_music.name = "GameplayMusic"
	add_child(_music)

	_menu_music = AudioStreamPlayer.new()
	_menu_music.name = "MenuMusic"
	add_child(_menu_music)

	_clock = AudioClock.new()
	_clock.music_player = _music
	add_child(_clock)

	_leaderboard_service = preload("res://scripts/LeaderboardService.gd").new()
	add_child(_leaderboard_service)

	# Gameplay world
	_game_root = Node2D.new()
	_game_root.visible = false
	add_child(_game_root)

	var bg := ColorRect.new()
	bg.size = Vector2(VIEWPORT_W, VIEWPORT_H)
	bg.color = Color(0.04, 0.04, 0.07)
	_game_root.add_child(bg)

	_build_game_ui()
	_build_menu_ui()

func _build_game_ui() -> void:
	_game_ui = CanvasLayer.new()
	_game_ui.visible = false
	add_child(_game_ui)

	_score_label = _make_label(_game_ui, Vector2(20.0, 16.0), 26)
	_score_label.text = "Score: 0"

	_combo_label = _make_label(_game_ui, Vector2(20.0, 54.0), 38)
	_combo_label.modulate = Color(0.8, 0.9, 1.0)

	_judge_label = _make_label(_game_ui,
		Vector2(VIEWPORT_W / 2.0 - 110.0, VIEWPORT_H - 210.0), 40)
	_judge_label.text = ""

	_key_hint_label = _make_label(_game_ui, Vector2(0.0, VIEWPORT_H - 95.0), 17)
	_key_hint_label.text = ""
	_key_hint_label.modulate = Color(0.6, 0.6, 0.7)

	_debug_label = _make_label(_game_ui, Vector2(VIEWPORT_W - 310.0, 16.0), 13)
	_debug_label.modulate = Color(0.55, 0.55, 0.65)

func _build_menu_ui() -> void:
	_menu_layer = CanvasLayer.new()
	add_child(_menu_layer)

	var bg := ColorRect.new()
	bg.size = Vector2(VIEWPORT_W, VIEWPORT_H)
	bg.color = Color(0.03, 0.04, 0.06, 0.97)
	_menu_layer.add_child(bg)

	var accent := ColorRect.new()
	accent.size = Vector2(VIEWPORT_W * 0.80, VIEWPORT_H * 0.50)
	accent.position = Vector2(-40.0, -20.0)
	accent.color = Color(0.13, 0.28, 0.34, 0.22)
	_menu_layer.add_child(accent)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 26)
	root.add_theme_constant_override("margin_right", 26)
	root.add_theme_constant_override("margin_top", 20)
	root.add_theme_constant_override("margin_bottom", 22)
	_menu_layer.add_child(root)

	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	root.add_child(columns)

	var left_col := VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.size_flags_stretch_ratio = 1.75
	left_col.add_theme_constant_override("separation", 12)
	columns.add_child(left_col)

	var heading_row := VBoxContainer.new()
	heading_row.add_theme_constant_override("separation", 2)
	left_col.add_child(heading_row)

	_menu_title_label = Label.new()
	_menu_title_label.text = "rhythmgame"
	_menu_title_label.add_theme_font_size_override("font_size", 48)
	heading_row.add_child(_menu_title_label)

	var subtitle := Label.new()
	subtitle.text = "osu!mania 4K importer"
	subtitle.modulate = Color(0.72, 0.82, 0.90)
	subtitle.add_theme_font_size_override("font_size", 18)
	heading_row.add_child(subtitle)

	var leaderboard_card := PanelContainer.new()
	leaderboard_card.custom_minimum_size = Vector2(0.0, 168.0)
	leaderboard_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leaderboard_card.add_theme_stylebox_override("panel",
		_make_card_style(Color(0.07, 0.10, 0.14, 0.95), Color(0.29, 0.42, 0.52, 0.9)))
	left_col.add_child(leaderboard_card)

	var leaderboard_pad := MarginContainer.new()
	leaderboard_pad.add_theme_constant_override("margin_left", 16)
	leaderboard_pad.add_theme_constant_override("margin_right", 16)
	leaderboard_pad.add_theme_constant_override("margin_top", 14)
	leaderboard_pad.add_theme_constant_override("margin_bottom", 14)
	leaderboard_card.add_child(leaderboard_pad)

	var leaderboard_v := VBoxContainer.new()
	leaderboard_v.add_theme_constant_override("separation", 8)
	leaderboard_pad.add_child(leaderboard_v)

	var leaderboard_title := Label.new()
	leaderboard_title.text = "Future Leaderboard Space"
	leaderboard_title.add_theme_font_size_override("font_size", 28)
	leaderboard_v.add_child(leaderboard_title)

	_leaderboard_hint_label = Label.new()
	_leaderboard_hint_label.text = "Reserved top-left panel for map ranking and personal best scores."
	_leaderboard_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_leaderboard_hint_label.modulate = Color(0.74, 0.82, 0.90)
	leaderboard_v.add_child(_leaderboard_hint_label)

	var map_card := PanelContainer.new()
	map_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_card.custom_minimum_size = Vector2(0.0, 220.0)
	map_card.add_theme_stylebox_override("panel",
		_make_card_style(Color(0.08, 0.09, 0.12, 0.95), Color(0.20, 0.28, 0.38, 0.9)))
	left_col.add_child(map_card)

	var map_pad := MarginContainer.new()
	map_pad.add_theme_constant_override("margin_left", 16)
	map_pad.add_theme_constant_override("margin_right", 16)
	map_pad.add_theme_constant_override("margin_top", 14)
	map_pad.add_theme_constant_override("margin_bottom", 14)
	map_card.add_child(map_pad)

	var map_v := VBoxContainer.new()
	map_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_v.add_theme_constant_override("separation", 10)
	map_pad.add_child(map_v)

	_menu_map_label = RichTextLabel.new()
	_menu_map_label.scroll_active = true
	_menu_map_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_menu_map_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_map_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_menu_map_label.custom_minimum_size = Vector2(0.0, 140.0)
	_menu_map_label.bbcode_enabled = false
	map_v.add_child(_menu_map_label)

	_menu_status_label = Label.new()
	_menu_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_menu_status_label.modulate = Color(0.77, 0.90, 1.0)
	_menu_status_label.custom_minimum_size = Vector2(0.0, 42.0)
	map_v.add_child(_menu_status_label)

	var controls_card := PanelContainer.new()
	controls_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_card.add_theme_stylebox_override("panel",
		_make_card_style(Color(0.07, 0.08, 0.11, 0.95), Color(0.22, 0.30, 0.39, 0.9)))
	left_col.add_child(controls_card)

	var controls_pad := MarginContainer.new()
	controls_pad.add_theme_constant_override("margin_left", 16)
	controls_pad.add_theme_constant_override("margin_right", 16)
	controls_pad.add_theme_constant_override("margin_top", 14)
	controls_pad.add_theme_constant_override("margin_bottom", 14)
	controls_card.add_child(controls_pad)

	var controls_v := VBoxContainer.new()
	controls_v.add_theme_constant_override("separation", 11)
	controls_pad.add_child(controls_v)

	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 10)
	controls_v.add_child(diff_row)

	var diff_lbl := Label.new()
	diff_lbl.text = "Difficulty"
	diff_lbl.custom_minimum_size = Vector2(90.0, 34.0)
	diff_row.add_child(diff_lbl)

	_difficulty_select = OptionButton.new()
	_difficulty_select.custom_minimum_size = Vector2(490.0, 34.0)
	_difficulty_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_difficulty_select.disabled = true
	_difficulty_select.item_selected.connect(_on_difficulty_selected)
	diff_row.add_child(_difficulty_select)

	var settings_row := HBoxContainer.new()
	settings_row.add_theme_constant_override("separation", 14)
	controls_v.add_child(settings_row)

	var offset_lbl := Label.new()
	offset_lbl.text = "Audio Offset (ms)"
	offset_lbl.custom_minimum_size = Vector2(130.0, 34.0)
	settings_row.add_child(offset_lbl)

	_offset_spin = SpinBox.new()
	_offset_spin.min_value = -300.0
	_offset_spin.max_value = 300.0
	_offset_spin.step = 1.0
	_offset_spin.value = _user_audio_offset_ms
	_offset_spin.custom_minimum_size = Vector2(90.0, 34.0)
	_offset_spin.value_changed.connect(_on_audio_offset_changed)
	settings_row.add_child(_offset_spin)

	var speed_lbl := Label.new()
	speed_lbl.text = "Scroll Speed"
	speed_lbl.custom_minimum_size = Vector2(100.0, 34.0)
	settings_row.add_child(speed_lbl)

	_scroll_speed_spin = SpinBox.new()
	_scroll_speed_spin.min_value = 0.20
	_scroll_speed_spin.max_value = 2.00
	_scroll_speed_spin.step = 0.01
	_scroll_speed_spin.value = _user_scroll_speed
	_scroll_speed_spin.custom_minimum_size = Vector2(90.0, 34.0)
	_scroll_speed_spin.value_changed.connect(_on_scroll_speed_changed)
	settings_row.add_child(_scroll_speed_spin)

	var mouse_lbl := Label.new()
	mouse_lbl.text = "Mouse Sens."
	mouse_lbl.custom_minimum_size = Vector2(94.0, 34.0)
	settings_row.add_child(mouse_lbl)

	_mouse_sensitivity_spin = SpinBox.new()
	_mouse_sensitivity_spin.min_value = 0.50
	_mouse_sensitivity_spin.max_value = 2.50
	_mouse_sensitivity_spin.step = 0.05
	_mouse_sensitivity_spin.value = _user_mouse_sensitivity
	_mouse_sensitivity_spin.custom_minimum_size = Vector2(90.0, 34.0)
	_mouse_sensitivity_spin.value_changed.connect(_on_mouse_sensitivity_changed)
	settings_row.add_child(_mouse_sensitivity_spin)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	controls_v.add_child(buttons)

	var import_btn := Button.new()
	import_btn.text = "Import .osu/.osz"
	import_btn.custom_minimum_size = Vector2(180.0, 42.0)
	import_btn.pressed.connect(_on_import_pressed)
	buttons.add_child(import_btn)

	_start_button = Button.new()
	_start_button.text = "Start"
	_start_button.custom_minimum_size = Vector2(180.0, 42.0)
	_start_button.disabled = true
	_start_button.pressed.connect(_on_start_pressed)
	buttons.add_child(_start_button)

	var library_card := PanelContainer.new()
	library_card.custom_minimum_size = Vector2(360.0, 0.0)
	library_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	library_card.size_flags_horizontal = Control.SIZE_FILL
	library_card.add_theme_stylebox_override("panel",
		_make_card_style(Color(0.07, 0.09, 0.12, 0.96), Color(0.25, 0.37, 0.46, 0.90)))
	columns.add_child(library_card)

	var library_pad := MarginContainer.new()
	library_pad.add_theme_constant_override("margin_left", 14)
	library_pad.add_theme_constant_override("margin_right", 14)
	library_pad.add_theme_constant_override("margin_top", 14)
	library_pad.add_theme_constant_override("margin_bottom", 14)
	library_card.add_child(library_pad)

	var library_v := VBoxContainer.new()
	library_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	library_v.add_theme_constant_override("separation", 10)
	library_pad.add_child(library_v)

	var library_title := Label.new()
	library_title.text = "Imported Beatmaps"
	library_title.add_theme_font_size_override("font_size", 26)
	library_v.add_child(library_title)

	_library_count_label = Label.new()
	_library_count_label.modulate = Color(0.75, 0.86, 0.94)
	_library_count_label.text = "0 charts"
	library_v.add_child(_library_count_label)

	_library_status_label = Label.new()
	_library_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_library_status_label.custom_minimum_size = Vector2(0.0, 40.0)
	_library_status_label.modulate = Color(0.78, 0.90, 0.98)
	_library_status_label.text = "Select a saved chart to load it."
	library_v.add_child(_library_status_label)

	var library_scroll := ScrollContainer.new()
	library_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	library_v.add_child(library_scroll)

	_library_list = VBoxContainer.new()
	_library_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_library_list.add_theme_constant_override("separation", 8)
	library_scroll.add_child(_library_list)

	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = PackedStringArray([
		"*.osz ; osu beatmap set archive",
		"*.osu ; osu beatmap difficulty"
	])
	_file_dialog.file_selected.connect(_on_map_file_selected)
	add_child(_file_dialog)

func _make_card_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	return sb

static func _make_label(parent: Node, pos: Vector2, font_size: int) -> Label:
	var lbl := Label.new()
	lbl.position = pos
	lbl.add_theme_font_size_override("font_size", font_size)
	parent.add_child(lbl)
	return lbl

# ---------------------------------------------------------------------------
# Menu flow
# ---------------------------------------------------------------------------
func _enter_menu() -> void:
	_state = State.MENU
	_music.stop()
	_game_root.visible = false
	_game_ui.visible = false
	_menu_layer.visible = true

	if _menu_music.stream != null and not _menu_music.playing:
		_menu_music.play()

func _start_menu_music() -> void:
	var stream := _load_audio_stream_from_path(MENU_MUSIC_PATH)
	if stream == null:
		_set_menu_status(
			"Menu audio not found or unsupported:\n%s" % MENU_MUSIC_PATH
		)
		return

	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD

	_menu_music.stream = stream
	_menu_music.volume_db = -5.0
	_menu_music.play()

func _load_library_from_disk() -> void:
	_library_entries.clear()
	if not FileAccess.file_exists(LIBRARY_SAVE_PATH):
		_rebuild_library_ui()
		return

	var file := FileAccess.open(LIBRARY_SAVE_PATH, FileAccess.READ)
	if file == null:
		_rebuild_library_ui()
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	var dropped_missing := false
	if parsed is Array:
		for item in parsed:
			if not (item is Dictionary):
				continue
			var entry := item as Dictionary
			var source_path := String(entry.get("source_path", ""))
			if source_path.is_empty() or not FileAccess.file_exists(source_path):
				dropped_missing = true
				continue
			if not entry.has("source_type") or not entry.has("difficulty_name"):
				continue
			_library_entries.append(entry)

	if dropped_missing:
		_save_library_to_disk()
	_rebuild_library_ui()

func _save_library_to_disk() -> void:
	var file := FileAccess.open(LIBRARY_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Failed to save beatmap library: %s" % LIBRARY_SAVE_PATH)
		return
	file.store_string(JSON.stringify(_library_entries))

func _add_maps_to_library(maps: Array[Beatmap], source_type: String, source_path: String) -> void:
	if source_path.is_empty():
		return

	for bm in maps:
		var entry: Dictionary = {
			"source_type": source_type,
			"source_path": source_path,
			"title": bm.title,
			"artist": bm.artist,
			"difficulty_name": bm.difficulty_name,
			"star_rating": bm.star_rating,
			"notes": bm.hit_objects.size(),
		}
		var key := _library_entry_key(entry)
		for i in range(_library_entries.size() - 1, -1, -1):
			if _library_entry_key(_library_entries[i]) == key:
				_library_entries.remove_at(i)
		_library_entries.push_front(entry)

	_save_library_to_disk()
	_rebuild_library_ui()

func _library_entry_key(entry: Dictionary) -> String:
	return "%s|%s|%s|%s" % [
		String(entry.get("source_type", "")),
		String(entry.get("source_path", "")),
		String(entry.get("title", "")),
		String(entry.get("difficulty_name", ""))
	]

func _rebuild_library_ui() -> void:
	if _library_list == null or _library_count_label == null or _library_status_label == null:
		return

	for child in _library_list.get_children():
		child.queue_free()

	_library_count_label.text = "%d charts" % _library_entries.size()
	if _library_entries.is_empty():
		var empty := Label.new()
		empty.text = "No imported beatmaps yet.\nUse Import to add .osu or .osz files."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.modulate = Color(0.66, 0.77, 0.86)
		_library_list.add_child(empty)
		return

	for i in _library_entries.size():
		var entry := _library_entries[i]
		var btn := Button.new()
		btn.text = _library_entry_text(entry)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0.0, 64.0)
		btn.pressed.connect(_on_library_entry_pressed.bind(i))
		_library_list.add_child(btn)

func _library_entry_text(entry: Dictionary) -> String:
	var title := String(entry.get("title", "Unknown"))
	var artist := String(entry.get("artist", "Unknown"))
	var diff := String(entry.get("difficulty_name", "Unknown"))
	var source_path := String(entry.get("source_path", ""))
	var source_name := source_path.get_file()
	var star_val := float(entry.get("star_rating", -1.0))
	var star_text := "  %.2f*" % star_val if star_val >= 0.0 else ""
	return "%s - %s [%s%s]\n%s" % [artist, title, diff, star_text, source_name]

func _on_library_entry_pressed(index: int) -> void:
	if index < 0 or index >= _library_entries.size():
		return

	var entry := _library_entries[index]
	var source_type := String(entry.get("source_type", ""))
	var source_path := String(entry.get("source_path", ""))
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		_set_library_status("Saved source file is missing:\n%s" % source_path)
		return

	if source_type == "osu":
		var bm := Beatmap.load_from_osu_file(source_path)
		if bm == null or bm.key_count != LANE_KEYS.size() or bm.hit_objects.is_empty():
			_set_library_status("Saved map failed to load as playable 4K:\n%s" % source_path)
			return
		var single: Array[Beatmap] = [bm]
		_set_imported_maps(single)
	elif source_type == "osz":
		var maps := Beatmap.load_all_4k_mania_from_osz_file(source_path)
		if maps.is_empty():
			_set_library_status("No playable 4K difficulties in saved archive:\n%s" % source_path)
			return
		_set_imported_maps(maps)
		var selected_idx := _find_map_index_from_entry(maps, entry)
		if selected_idx >= 0:
			_difficulty_select.select(selected_idx)
			_set_selected_difficulty(selected_idx)
	else:
		_set_library_status("Unknown saved source type for:\n%s" % source_path)
		return

	_set_library_status("Loaded from library:\n%s" % source_path)

func _set_library_status(msg: String) -> void:
	if _library_status_label == null:
		return
	_library_status_label.text = msg

func _find_map_index_from_entry(maps: Array[Beatmap], entry: Dictionary) -> int:
	var target_title := String(entry.get("title", ""))
	var target_diff := String(entry.get("difficulty_name", ""))
	var target_star := float(entry.get("star_rating", -1.0))
	for i in maps.size():
		var bm := maps[i]
		if bm.title != target_title or bm.difficulty_name != target_diff:
			continue
		if target_star >= 0.0 and bm.star_rating >= 0.0:
			if absf(bm.star_rating - target_star) < 0.01:
				return i
			continue
		return i
	return -1

func _on_import_pressed() -> void:
	if OS.has_feature("web"):
		_open_web_import_picker()
		return
	_file_dialog.popup_centered_ratio(0.82)

func _setup_web_import_bridge() -> void:
	if not OS.has_feature("web"):
		return

	_web_import_callback = JavaScriptBridge.create_callback(_on_web_file_from_browser)
	var window := JavaScriptBridge.get_interface("window")
	if window == null:
		return

	window.godotRhythmImportCallback = _web_import_callback
	JavaScriptBridge.eval("""
		(function () {
			if (!window.godotRhythmImportCallback || window.__rhythmgameWebImportReady) {
				return;
			}
			window.__rhythmgameWebImportReady = true;

			const sendFile = async (file) => {
				if (!file) return;
				const name = String(file.name || "");
				const lower = name.toLowerCase();
				if (!(lower.endsWith(".osu") || lower.endsWith(".osz"))) {
					return;
				}
				const buffer = await file.arrayBuffer();
				const bytes = new Uint8Array(buffer);
				let binary = "";
				const chunk = 0x8000;
				for (let i = 0; i < bytes.length; i += chunk) {
					binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
				}
				const b64 = btoa(binary);
				window.godotRhythmImportCallback(name, b64);
			};

			const sendAll = async (fileList) => {
				for (const file of fileList) {
					await sendFile(file);
				}
			};

			window.rhythmgameOpenImportPicker = () => {
				const input = document.createElement("input");
				input.type = "file";
				input.accept = ".osu,.osz";
				input.multiple = true;
				input.onchange = () => {
					if (input.files && input.files.length > 0) {
						sendAll(input.files);
					}
				};
				input.click();
			};

			const prevent = (e) => {
				e.preventDefault();
				e.stopPropagation();
			};
			window.addEventListener("dragenter", prevent);
			window.addEventListener("dragover", prevent);
			window.addEventListener("drop", (e) => {
				prevent(e);
				if (e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files.length > 0) {
					sendAll(e.dataTransfer.files);
				}
			});
		})();
	""", true)

	_web_bridge_ready = true

func _open_web_import_picker() -> void:
	if not _web_bridge_ready:
		_set_menu_status("Web file picker not initialized yet.")
		return
	JavaScriptBridge.eval("""
		if (window.rhythmgameOpenImportPicker) {
			window.rhythmgameOpenImportPicker();
		}
	""", true)

func _on_web_file_from_browser(args: Array) -> void:
	if args.size() < 2:
		return

	var file_name := String(args[0])
	var b64 := String(args[1])
	if file_name.is_empty() or b64.is_empty():
		return

	var ext := file_name.get_extension().to_lower()
	if ext != "osu" and ext != "osz":
		return

	var data := Marshalls.base64_to_raw(b64)
	if data.is_empty():
		_set_menu_status("Failed to read web file: %s" % file_name)
		return

	var saved_path := _save_web_import_file(file_name, data)
	if saved_path.is_empty():
		_set_menu_status("Failed to store imported file in browser storage:\n%s" % file_name)
		return

	_on_map_file_selected(saved_path)

func _save_web_import_file(file_name: String, data: PackedByteArray) -> String:
	var web_import_abs := ProjectSettings.globalize_path(WEB_IMPORT_DIR)
	var mk_err := DirAccess.make_dir_recursive_absolute(web_import_abs)
	if mk_err != OK:
		return ""

	var safe_name := file_name.get_file()
	safe_name = safe_name.replace("/", "_")
	safe_name = safe_name.replace("\\", "_")
	safe_name = safe_name.replace(":", "_")
	safe_name = safe_name.replace("..", "_")
	safe_name = safe_name.strip_edges()
	if safe_name.is_empty():
		safe_name = "import.%s" % file_name.get_extension().to_lower()

	var out_path := WEB_IMPORT_DIR.path_join("%d_%s" % [Time.get_ticks_usec(), safe_name])
	var out_file := FileAccess.open(out_path, FileAccess.WRITE)
	if out_file == null:
		return ""
	out_file.store_buffer(data)
	return out_path

func _on_map_file_selected(path: String) -> void:
	var ext := path.get_extension().to_lower()

	if ext == "osz":
		var maps := Beatmap.load_all_4k_mania_from_osz_file(path)
		if maps.is_empty():
			_set_menu_status(
				"No playable 4K osu!mania difficulty found in archive:\n%s" % path
			)
			_clear_imported_maps()
			return
		_set_imported_maps(maps)
		_add_maps_to_library(maps, "osz", path)
		if maps.size() == 1:
			_set_menu_status("Imported 1 playable 4K difficulty:\n%s" % path)
		else:
			_set_menu_status(
				"Imported %d playable 4K difficulties. Select one, then press Start.\n%s"
				% [maps.size(), path]
			)
	elif ext == "osu":
		var imported := Beatmap.load_from_osu_file(path)
		if imported == null:
			_set_menu_status("Failed to import .osu beatmap:\n%s" % path)
			_clear_imported_maps()
			return
		if imported.key_count != LANE_KEYS.size():
			_set_menu_status(
				"Only 4K maps are supported. This map is %dK:\n%s" % [
					imported.key_count,
					path
				]
			)
			_clear_imported_maps()
			return
		if imported.hit_objects.is_empty():
			_set_menu_status("Imported file has no hit objects:\n%s" % path)
			_clear_imported_maps()
			return
		var single_map: Array[Beatmap] = [imported]
		_set_imported_maps(single_map)
		_add_maps_to_library(single_map, "osu", path)
		_set_menu_status("Imported 4K osu!mania beatmap:\n%s" % path)
	else:
		_set_menu_status("Unsupported file type:\n%s" % path)
		_clear_imported_maps()
		return

func _set_imported_maps(maps: Array[Beatmap]) -> void:
	_imported_4k_maps = maps
	_difficulty_select.clear()
	for i in maps.size():
		var bm := maps[i]
		_difficulty_select.add_item(_difficulty_label_for(bm), i)

	_difficulty_select.disabled = maps.is_empty()
	_start_button.disabled = maps.is_empty()

	if maps.is_empty():
		_beatmap = null
		_update_menu_map_label()
		return

	_difficulty_select.select(0)
	_set_selected_difficulty(0)

func _clear_imported_maps() -> void:
	var empty_maps: Array[Beatmap] = []
	_set_imported_maps(empty_maps)

func _on_difficulty_selected(idx: int) -> void:
	_set_selected_difficulty(idx)

func _set_selected_difficulty(idx: int) -> void:
	if idx < 0 or idx >= _imported_4k_maps.size():
		return
	_beatmap = _imported_4k_maps[idx]
	_update_menu_map_label()

func _on_audio_offset_changed(value: float) -> void:
	_user_audio_offset_ms = value
	if _state == State.PLAYING and _beatmap != null:
		_clock.offset_ms = float(_beatmap.audio_lead_in_ms) + _user_audio_offset_ms
	_update_menu_map_label()

func _on_scroll_speed_changed(value: float) -> void:
	_user_scroll_speed = value
	if _field != null:
		_field.scroll_speed = _user_scroll_speed
	_update_menu_map_label()

func _on_mouse_sensitivity_changed(value: float) -> void:
	_user_mouse_sensitivity = value
	_update_menu_map_label()

func _difficulty_label_for(bm: Beatmap) -> String:
	var diff := bm.difficulty_name if not bm.difficulty_name.is_empty() else "Unknown"
	var star := (" %.2f*" % bm.star_rating) if bm.star_rating >= 0.0 else ""
	return "%s [%s%s]" % [bm.title, diff, star]

func _on_start_pressed() -> void:
	if _beatmap == null:
		return
	_start_song()

func _update_menu_map_label() -> void:
	if _beatmap == null:
		_menu_map_label.text = "No beatmap imported yet."
		_update_leaderboard_hint()
		return

	_menu_map_label.text = (
		"Title: %s\n" % _beatmap.title +
		"Artist: %s\n" % _beatmap.artist +
		"Difficulty: %s\n" % _beatmap.difficulty_name +
		("Stars: %.2f\n" % _beatmap.star_rating if _beatmap.star_rating >= 0.0 else "") +
		"Audio Offset (User): %.0f ms\n" % _user_audio_offset_ms +
		"Scroll Speed: %.2f\n" % _user_scroll_speed +
		"Mouse Sensitivity: %.2f\n" % _user_mouse_sensitivity +
		"Keys: %d\n" % _beatmap.key_count +
		"Audio Lead-In: %d ms\n" % _beatmap.audio_lead_in_ms +
		"Notes: %d\n" % _beatmap.hit_objects.size() +
		"Audio: %s" % (_beatmap.audio_file if not _beatmap.audio_file.is_empty() else "(none)")
	)
	_update_leaderboard_hint()

func _update_leaderboard_hint() -> void:
	if _leaderboard_hint_label == null or _leaderboard_service == null:
		return
	_leaderboard_hint_label.text = _leaderboard_service.status_text_for_beatmap(_beatmap)

func _set_menu_status(msg: String) -> void:
	_menu_status_label.text = msg

# ---------------------------------------------------------------------------
# Gameplay flow
# ---------------------------------------------------------------------------
func _start_song() -> void:
	if _beatmap == null:
		return

	_state = State.COUNTDOWN
	_menu_layer.visible = false
	_game_root.visible = true
	_game_ui.visible = true
	_menu_music.stop()

	_reset_score()
	_build_playfield(_beatmap)
	_field.load_beatmap(_beatmap)
	_song_finish_ms = _estimate_song_finish_ms(_beatmap)
	_clock.offset_ms = float(_beatmap.audio_lead_in_ms) + _user_audio_offset_ms

	var has_song_audio := _load_gameplay_audio(_beatmap.audio_file)

	_judge_label.text = "Get Ready!"
	_judge_label.modulate = Color(0.92, 0.92, 0.92)
	await get_tree().create_timer(1.2).timeout

	_judge_label.text = ""
	if has_song_audio:
		_music.play()
	else:
		_clock.start_fallback()

	_state = State.PLAYING

func _build_playfield(bm: Beatmap) -> void:
	if _field != null:
		_field.queue_free()

	var field_top_y := 60.0
	var field_h := VIEWPORT_H - field_top_y - 28.0
	var field_w := minf(VIEWPORT_W - 120.0, field_h * 1.45)
	var field_x := (VIEWPORT_W - field_w) / 2.0

	_field = NoteField.new()
	_field.field_size = Vector2(field_w, field_h)
	_field.scroll_speed = _user_scroll_speed
	_field.position = Vector2(field_x, field_top_y)
	_game_root.add_child(_field)
	_field.setup()
	_field.note_hit.connect(_on_note_hit)
	_field.note_grazed.connect(_on_note_grazed)
	_field.note_missed.connect(_on_note_missed)

	_key_hint_label.position = Vector2(field_x - 4.0, VIEWPORT_H - 95.0)
	_key_hint_label.text = "Move mouse over a zone to activate it. Active zone auto-hits touching orbs. Esc = menu"

func _load_gameplay_audio(audio_path: String) -> bool:
	_music.stop()
	_music.stream = null
	if audio_path.is_empty():
		return false

	var stream := _load_audio_stream_from_path(audio_path)
	if stream == null:
		push_warning("Failed to load beatmap audio: %s" % audio_path)
		return false

	_music.stream = stream
	_music.volume_db = 0.0
	return true

func _estimate_song_finish_ms(bm: Beatmap) -> float:
	var last_obj_ms := 0.0
	for obj in bm.hit_objects:
		last_obj_ms = maxf(last_obj_ms, float(maxi(obj.time_ms, obj.end_time_ms)))
	return last_obj_ms + 700.0

func _reset_score() -> void:
	_score = 0
	_combo = 0
	_recovery_until_ms = 0.0
	_score_label.text = "Score: 0"
	_combo_label.text = ""
	_debug_label.text = ""

func _load_audio_stream_from_path(path: String) -> AudioStream:
	if path.is_empty():
		return null

	if path.begins_with("res://"):
		var loaded_res := ResourceLoader.load(path)
		if loaded_res is AudioStream:
			return loaded_res as AudioStream

	var ext := path.get_extension().to_lower()
	match ext:
		"wav", "wave":
			return AudioStreamWAV.load_from_file(path)
		"ogg", "oga":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			return AudioStreamMP3.load_from_file(path)
		_:
			var loaded := ResourceLoader.load(path)
			if loaded is AudioStream:
				return loaded as AudioStream
	return null

# ---------------------------------------------------------------------------
# Per-frame
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if _state != State.PLAYING:
		return

	var song_pos := _clock.get_song_position_ms()
	if _field != null:
		_field.update_hover_zone(_sensitive_mouse_local_for_field())
		_field.tick(song_pos)

	if _field != null and _field.is_chart_complete() and song_pos >= _song_finish_ms:
		_set_menu_status("Finished: %s - %s" % [_beatmap.artist, _beatmap.title])
		_enter_menu()
		return

	if _judge_display_secs > 0.0:
		_judge_display_secs -= delta
		if _judge_display_secs <= 0.0:
			_judge_label.text = ""

	_debug_label.text = (
		"song pos : %.1f ms\n" % song_pos +
		"active fields : %s\n" % (_field.get_active_field_summary() if _field != null else "none") +
		("recovery : %.0f ms\n" % maxf(0.0, _recovery_until_ms - song_pos) if song_pos < _recovery_until_ms else "") +
		"output latency : %.1f ms\n" % (AudioServer.get_output_latency() * 1000.0) +
		"since last mix : %.1f ms" % (AudioServer.get_time_since_last_mix() * 1000.0)
	)

func _sensitive_mouse_local_for_field() -> Vector2:
	if _field == null:
		return Vector2.ZERO
	var raw_local := _field.to_local(get_global_mouse_position())
	var center := _field.field_size * 0.5
	return center + (raw_local - center) * _user_mouse_sensitivity

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if _state != State.PLAYING:
		return
	if not (event is InputEventKey):
		return

	var kev := event as InputEventKey
	if kev.echo:
		return

	if kev.pressed and kev.keycode == KEY_ESCAPE:
		_set_menu_status("Returned to menu.")
		_enter_menu()
		return


# ---------------------------------------------------------------------------
# Judgement callbacks
# ---------------------------------------------------------------------------
func _on_note_hit(_column: int, _delta_ms: float) -> void:
	# Binary field logic: a "hit" signal means the note reached the red hitbox while
	# its matching zone was active, so always score it as a successful hit.
	var j := HitJudge.Judgement.PERFECT
	var recovering := _clock.get_song_position_ms() < _recovery_until_ms

	if recovering and j <= HitJudge.Judgement.GOOD:
		_recovery_until_ms = 0.0
		_combo = max(1, _combo + 1)
		_score += int(HitJudge.SCORE_VALUES[j] * 1.20)
		_show_text_judge("RECOVER", Color(0.60, 1.0, 0.74))
	else:
		_score += HitJudge.SCORE_VALUES[j] * (1 + _combo / 10)
		_combo += 1
		_show_judge(j)

	_score_label.text = "Score: %d" % _score
	_combo_label.text = "%dx" % _combo

func _on_note_grazed(_column: int, _delta_ms: float) -> void:
	_score += 25
	_combo = maxi(_combo - 1, 0)
	_score_label.text = "Score: %d" % _score
	_combo_label.text = "%dx" % _combo if _combo > 0 else ""
	_show_text_judge("GRAZE", Color(0.73, 0.86, 1.0))

func _on_note_missed(_column: int) -> void:
	_combo = 0
	_recovery_until_ms = _clock.get_song_position_ms() + 1700.0
	_combo_label.text = ""
	_show_judge(HitJudge.Judgement.MISS)

func _show_judge(j: HitJudge.Judgement) -> void:
	_judge_label.text = HitJudge.name_of(j)
	_judge_label.modulate = HitJudge.color_of(j)
	_judge_display_secs = JUDGE_SHOW_DURATION

func _show_text_judge(text: String, color: Color) -> void:
	_judge_label.text = text
	_judge_label.modulate = color
	_judge_display_secs = JUDGE_SHOW_DURATION
