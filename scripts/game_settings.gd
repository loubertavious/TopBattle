extends Node

# Shared game settings passed between scenes.
var vs_bot: bool = false

const SAVE_PATH     := "user://profiles.cfg"
const PROFILE_SLOTS := 4

# 16 preset colours available for top customisation.
# Each entry is [Color, display_name].
const PRESET_COLORS: Array = [
	[Color(0.95, 0.18, 0.18), "Red"],
	[Color(0.98, 0.48, 0.06), "Orange"],
	[Color(0.97, 0.88, 0.08), "Yellow"],
	[Color(0.40, 0.90, 0.15), "Lime"],
	[Color(0.12, 0.82, 0.28), "Green"],
	[Color(0.05, 0.88, 0.72), "Teal"],
	[Color(0.08, 0.72, 0.98), "Sky"],
	[Color(0.12, 0.45, 0.98), "Blue"],
	[Color(0.38, 0.18, 0.98), "Indigo"],
	[Color(0.72, 0.08, 0.98), "Violet"],
	[Color(0.98, 0.08, 0.62), "Pink"],
	[Color(0.98, 0.08, 0.35), "Rose"],
	[Color(0.98, 0.82, 0.20), "Gold"],
	[Color(0.90, 0.90, 0.90), "White"],
	[Color(0.55, 0.55, 0.55), "Silver"],
	[Color(0.04, 0.04, 0.10), "Obsidian"],
]


func color_count() -> int:
	return PRESET_COLORS.size()


func get_color(idx: int) -> Color:
	return PRESET_COLORS[idx % PRESET_COLORS.size()][0]


func get_color_name(idx: int) -> String:
	return PRESET_COLORS[idx % PRESET_COLORS.size()][1]


# ── Profile save / load ─────────────────────────────────────────────────────────
# Profiles are stored in user://profiles.cfg as ConfigFile sections.
# Section name format: "p{player}_slot{slot}"  (player=1|2, slot=0..3)

func save_profile(player: int, slot: int,
		blade: int, track: int, tip: int, color_idx: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)          # silently ignored if file doesn't exist yet
	var section := "p%d_slot%d" % [player, slot]
	cfg.set_value(section, "blade",     blade)
	cfg.set_value(section, "track",     track)
	cfg.set_value(section, "tip",       tip)
	cfg.set_value(section, "color_idx", color_idx)
	cfg.save(SAVE_PATH)


# Returns a Dictionary with keys blade/track/tip/color_idx, or {} if slot is empty.
func load_profile(player: int, slot: int) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return {}
	var section := "p%d_slot%d" % [player, slot]
	if not cfg.has_section(section):
		return {}
	return {
		"blade":     cfg.get_value(section, "blade",     0),
		"track":     cfg.get_value(section, "track",     0),
		"tip":       cfg.get_value(section, "tip",       0),
		"color_idx": cfg.get_value(section, "color_idx", 0),
	}


func profile_exists(player: int, slot: int) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return false
	return cfg.has_section("p%d_slot%d" % [player, slot])
