## Beatmap.gd
## Runtime beatmap data. Inner classes mirror osu! concepts so importing .osu later
## is a matter of writing a parser that fills these same structures.
class_name Beatmap
extends RefCounted

# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

class HitObject:
	var time_ms: int       ## When this note should be hit
	var column: int        ## Lane index (0-based, 0..key_count-1)
	var end_time_ms: int   ## >0 for hold notes; 0 for normal taps

	func _init(t: int, col: int, end: int = 0) -> void:
		time_ms = t
		column = col
		end_time_ms = end

class TimingPoint:
	var time_ms: int
	var bpm: float
	var meter: int         ## Numerator of time signature (beats per measure)

	func _init(t: int, b: float, m: int = 4) -> void:
		time_ms = t
		bpm = b
		meter = m

# ---------------------------------------------------------------------------
# Beatmap fields
# ---------------------------------------------------------------------------

var title: String = ""
var artist: String = ""
var difficulty_name: String = ""
var star_rating: float = -1.0
var audio_file: String = ""   ## absolute filesystem path or empty
var audio_lead_in_ms: int = 0
var key_count: int = 4

var hit_objects: Array[HitObject] = []
var timing_points: Array[TimingPoint] = []

# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

## Remaps all note columns to a different key count (e.g. 7K -> 4K).
func remap_to_key_count(target_keys: int) -> void:
	target_keys = maxi(1, target_keys)
	if key_count == target_keys:
		return

	for obj in hit_objects:
		obj.column = clampi(
			int(floor((float(obj.column) + 0.5) * float(target_keys) / float(key_count))),
			0,
			target_keys - 1
		)
	key_count = target_keys

# ---------------------------------------------------------------------------
# Factory: osu! beatmap importer (.osu)
# ---------------------------------------------------------------------------

## Parses an osu!mania .osu file from the local filesystem.
## Returns null when the file cannot be read.
static func load_from_osu_file(osu_path: String) -> Beatmap:
	if not FileAccess.file_exists(osu_path):
		push_warning("Beatmap file not found: %s" % osu_path)
		return null

	var file := FileAccess.open(osu_path, FileAccess.READ)
	if file == null:
		push_warning("Failed to open beatmap: %s" % osu_path)
		return null

	var bm := Beatmap.new()
	bm.title = osu_path.get_file().get_basename()
	bm.artist = "Unknown Artist"
	bm.difficulty_name = "Unknown"
	bm.key_count = 4

	var section := ""
	var audio_filename := ""
	var mode := 3

	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("//"):
			continue

		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2)
			continue

		match section:
			"General":
				var kv_g := _parse_key_value_line(line)
				if kv_g.is_empty():
					continue
				match kv_g[0]:
					"AudioFilename":
						audio_filename = kv_g[1]
					"AudioLeadIn":
						bm.audio_lead_in_ms = maxi(0, int(kv_g[1]))
					"Mode":
						mode = int(kv_g[1])
			"Metadata":
				var kv_m := _parse_key_value_line(line)
				if kv_m.is_empty():
					continue
				match kv_m[0]:
					"Title":
						bm.title = kv_m[1]
					"Artist":
						bm.artist = kv_m[1]
					"Version":
						bm.difficulty_name = kv_m[1]
			"Difficulty":
				var kv_d := _parse_key_value_line(line)
				if kv_d.is_empty():
					continue
				if kv_d[0] == "CircleSize":
					bm.key_count = maxi(1, int(round(float(kv_d[1]))))
			"TimingPoints":
				_parse_timing_point_line(line, bm)
			"HitObjects":
				_parse_hit_object_line(line, bm)

	# Keep support constrained to mania maps.
	if mode != 3:
		push_warning("Only osu!mania maps are supported (mode=%d)." % mode)
		return null

	if not audio_filename.is_empty():
		bm.audio_file = osu_path.get_base_dir().path_join(audio_filename.replace("\\", "/"))
	bm.star_rating = _extract_star_hint("%s %s" % [bm.difficulty_name, osu_path.get_file()])

	bm.hit_objects.sort_custom(func(a: HitObject, b: HitObject) -> bool:
		return a.time_ms < b.time_ms
	)
	bm.timing_points.sort_custom(func(a: TimingPoint, b: TimingPoint) -> bool:
		return a.time_ms < b.time_ms
	)

	return bm

## Parses an .osz archive and returns the first playable 4K osu!mania difficulty.
## Returns null if no valid 4K mania chart is found.
static func load_first_4k_mania_from_osz_file(osz_path: String) -> Beatmap:
	var maps := load_all_4k_mania_from_osz_file(osz_path)
	return maps[0] if not maps.is_empty() else null

## Parses an .osz archive and returns all playable 4K osu!mania difficulties.
static func load_all_4k_mania_from_osz_file(osz_path: String) -> Array[Beatmap]:
	if not FileAccess.file_exists(osz_path):
		push_warning("Beatmap archive not found: %s" % osz_path)
		return []

	var zip := ZIPReader.new()
	var err := zip.open(osz_path)
	if err != OK:
		push_warning("Failed to open .osz archive: %s (error %d)" % [osz_path, err])
		return []

	var extract_dir := _make_osz_extract_dir(osz_path)
	var extract_root_abs := ProjectSettings.globalize_path(extract_dir)
	var mk_err := DirAccess.make_dir_recursive_absolute(extract_root_abs)
	if mk_err != OK:
		zip.close()
		push_warning("Failed to create extraction directory: %s" % extract_root_abs)
		return []

	var osu_paths: Array[String] = []
	for zip_rel_path in zip.get_files():
		if zip_rel_path.ends_with("/"):
			continue

		var safe_rel_path := _sanitize_zip_rel_path(zip_rel_path)
		if safe_rel_path.is_empty():
			continue

		var out_path := extract_dir.path_join(safe_rel_path)
		var out_abs_dir := ProjectSettings.globalize_path(out_path.get_base_dir())
		DirAccess.make_dir_recursive_absolute(out_abs_dir)

		var out_file := FileAccess.open(out_path, FileAccess.WRITE)
		if out_file == null:
			continue
		out_file.store_buffer(zip.read_file(zip_rel_path))

		if out_path.get_extension().to_lower() == "osu":
			osu_paths.append(out_path)

	zip.close()
	osu_paths.sort()

	var maps: Array[Beatmap] = []
	for osu_path in osu_paths:
		var bm := load_from_osu_file(osu_path)
		if bm == null:
			continue
		if bm.key_count != 4:
			continue
		if bm.hit_objects.is_empty():
			continue
		maps.append(bm)

	maps.sort_custom(func(a: Beatmap, b: Beatmap) -> bool:
		if a.star_rating >= 0.0 and b.star_rating >= 0.0 and a.star_rating != b.star_rating:
			return a.star_rating < b.star_rating
		if a.star_rating >= 0.0 and b.star_rating < 0.0:
			return true
		if a.star_rating < 0.0 and b.star_rating >= 0.0:
			return false
		return a.difficulty_name.nocasecmp_to(b.difficulty_name) < 0
	)
	return maps

static func _make_osz_extract_dir(osz_path: String) -> String:
	var base := osz_path.get_file().get_basename()
	base = base.replace(" ", "_")
	base = base.replace("/", "_")
	base = base.replace("\\", "_")
	base = base.replace(":", "_")
	base = base.replace("..", "_")
	var unique := "%s_%d" % [base, Time.get_ticks_msec()]
	return "user://imports/%s" % unique

static func _sanitize_zip_rel_path(rel_path: String) -> String:
	var normalized := rel_path.replace("\\", "/")
	if normalized.begins_with("/") or normalized.find("..") != -1:
		return ""
	return normalized.strip_edges()

static func _extract_star_hint(text: String) -> float:
	var re := RegEx.new()
	var err := re.compile("([0-9]+(?:\\.[0-9]+)?)\\s*[*★☆]")
	if err != OK:
		return -1.0
	var m := re.search(text)
	if m == null:
		return -1.0
	return float(m.get_string(1))

static func _parse_key_value_line(line: String) -> PackedStringArray:
	var idx := line.find(":")
	if idx < 0:
		return PackedStringArray()
	return PackedStringArray([
		line.substr(0, idx).strip_edges(),
		line.substr(idx + 1).strip_edges()
	])

static func _parse_timing_point_line(line: String, bm: Beatmap) -> void:
	var parts := line.split(",")
	if parts.size() < 2:
		return

	var time_ms := int(round(float(parts[0])))
	var beat_len := float(parts[1])
	if beat_len <= 0.0:
		return

	var meter := 4
	if parts.size() > 2:
		meter = maxi(1, int(parts[2]))

	bm.timing_points.append(
		TimingPoint.new(time_ms, 60000.0 / beat_len, meter)
	)

static func _parse_hit_object_line(line: String, bm: Beatmap) -> void:
	var parts := line.split(",")
	if parts.size() < 5:
		return

	var x := int(parts[0])
	var time_ms := int(parts[2])
	var type_flags := int(parts[3])
	var column := clampi(
		int(floor(float(x) * float(bm.key_count) / 512.0)),
		0,
		bm.key_count - 1
	)

	var end_time_ms := 0
	# Mania LN format in object params: "endTime:hitSample..."
	if (type_flags & 128) != 0 and parts.size() > 5:
		var params := parts[5].split(":")
		if not params.is_empty():
			end_time_ms = int(params[0])

	bm.hit_objects.append(HitObject.new(time_ms, column, end_time_ms))

# ---------------------------------------------------------------------------
# Factory: built-in test beatmap (no audio file required)
# ---------------------------------------------------------------------------

static func create_test_beatmap() -> Beatmap:
	var bm := Beatmap.new()
	bm.title  = "Test Track"
	bm.artist = "Built-in"
	bm.key_count = 4

	# Single timing point: 128 BPM → 468.75 ms / beat
	var beat := 468
	bm.timing_points.append(TimingPoint.new(0, 128.0))

	# Notes start at 1500 ms so the player can read the approach.
	# Pattern: two 8-bar phrases with increasing density.
	var t := 1500

	# Phrase 1 — quarter notes, columns walk right then left
	var phrase1 := [0, 1, 2, 3, 3, 2, 1, 0]
	for col in phrase1:
		bm.hit_objects.append(HitObject.new(t, col))
		t += beat

	# Phrase 2 — eighth notes (half beat), ascending runs + chords
	var phrase2_cols := [0, 2, 1, 3, 0, 3, 1, 2, 0, 1, 2, 3, 3, 2, 1, 0]
	for col in phrase2_cols:
		bm.hit_objects.append(HitObject.new(t, col))
		t += beat / 2

	# Phrase 3 — burst: four 16th-note runs
	for _run in range(4):
		for col in [0, 1, 2, 3]:
			bm.hit_objects.append(HitObject.new(t, col))
			t += beat / 4

	# Final chord to cap it off
	for col in [0, 1, 2, 3]:
		bm.hit_objects.append(HitObject.new(t, col))

	# Ensure sorted by time (already is, but good practice for future parsers)
	bm.hit_objects.sort_custom(func(a: HitObject, b: HitObject) -> bool:
		return a.time_ms < b.time_ms)

	return bm
