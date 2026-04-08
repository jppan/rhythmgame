## LeaderboardService.gd
## Lightweight scaffold for future online leaderboard support.
## Keeps map key generation and backend wiring in one place.
class_name LeaderboardService
extends Node

signal config_changed()

var api_base_url: String = ""
var api_token: String = ""

func configure(base_url: String, token: String = "") -> void:
	api_base_url = base_url.strip_edges()
	api_token = token.strip_edges()
	config_changed.emit()

func backend_enabled() -> bool:
	return not api_base_url.is_empty()

func map_key_for_beatmap(bm) -> String:
	if bm == null:
		return ""
	return "%s|%s|%s|%.2f" % [
		bm.artist.strip_edges(),
		bm.title.strip_edges(),
		bm.difficulty_name.strip_edges(),
		maxf(0.0, bm.star_rating)
	]

func status_text_for_beatmap(bm) -> String:
	if bm == null:
		return "Reserved top-left panel for map ranking and personal best scores."
	var map_key := map_key_for_beatmap(bm)
	if backend_enabled():
		return (
			"Leaderboard backend ready.\n" +
			"Map Key: %s\n" % map_key +
			"(Fetch/submit endpoints can be connected next.)"
		)
	return (
		"Leaderboard backend not configured yet.\n" +
		"Map Key: %s\n" % map_key +
		"Set an API base URL in LeaderboardService.configure(...) when backend is ready."
	)
