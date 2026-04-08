## HitJudge.gd
## Stateless judgement calculator. Pass a signed delta (note_time - input_time)
## and get back a Judgement enum value. Mirrors osu!mania OD 8 windows.
class_name HitJudge
extends RefCounted

enum Judgement {
	PERFECT = 0,  ## ±22.5 ms
	GREAT   = 1,  ## ±45 ms
	GOOD    = 2,  ## ±90 ms
	BAD     = 3,  ## ±135 ms
	MISS    = 4,  ## beyond window or key never pressed
}

## Absolute hit windows in ms (symmetric around 0).
const WINDOWS: Dictionary = {
	Judgement.PERFECT : 22.5,
	Judgement.GREAT   : 45.0,
	Judgement.GOOD    : 90.0,
	Judgement.BAD     : 135.0,
}

## Base score per judgement (multiply by combo bonus upstream).
const SCORE_VALUES: Dictionary = {
	Judgement.PERFECT : 300,
	Judgement.GREAT   : 200,
	Judgement.GOOD    : 100,
	Judgement.BAD     :  50,
	Judgement.MISS    :   0,
}

## delta_ms = note_time_ms - input_time_ms
## Positive  → player hit early.
## Negative  → player hit late.
static func judge(delta_ms: float) -> Judgement:
	var abs_delta := absf(delta_ms)
	if abs_delta <= WINDOWS[Judgement.PERFECT]:
		return Judgement.PERFECT
	elif abs_delta <= WINDOWS[Judgement.GREAT]:
		return Judgement.GREAT
	elif abs_delta <= WINDOWS[Judgement.GOOD]:
		return Judgement.GOOD
	elif abs_delta <= WINDOWS[Judgement.BAD]:
		return Judgement.BAD
	return Judgement.MISS

static func name_of(j: Judgement) -> String:
	match j:
		Judgement.PERFECT : return "PERFECT"
		Judgement.GREAT   : return "GREAT"
		Judgement.GOOD    : return "GOOD"
		Judgement.BAD     : return "BAD"
		_                 : return "MISS"

static func color_of(j: Judgement) -> Color:
	match j:
		Judgement.PERFECT : return Color(1.00, 0.90, 0.10)
		Judgement.GREAT   : return Color(0.10, 0.75, 1.00)
		Judgement.GOOD    : return Color(0.10, 1.00, 0.40)
		Judgement.BAD     : return Color(1.00, 0.55, 0.10)
		_                 : return Color(0.85, 0.20, 0.20)
