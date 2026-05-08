extends CanvasLayer

const TopScript = preload("res://scripts/top.gd")

var _p1_score_label: Label
var _p2_score_label: Label
var _message_label:  Label
var _boost_bars: Array[ProgressBar] = []

# Shape selection panel
var _shape_panel: PanelContainer

# ── Part-select state per player ───────────────────────────────────────────────
# Rows:  0=Profile  1=Blade  2=Track  3=Tip  4=Color
# Steps: 0=PROFILE  1=BLADE  2=TRACK  3=TIP  4=COLOR  5=DONE

const _ROW_PROFILE := 0
const _ROW_BLADE   := 1
const _ROW_TRACK   := 2
const _ROW_TIP     := 3
const _ROW_COLOR   := 4
const _ROW_COUNT   := 5

const _ROW_LABELS  := ["Profile", "Blade", "Track", "Tip", "Color"]

# Per-player references (index matches _ROW_*)
var _p1_val_labels:  Array[Label]       = []   # value text in each row
var _p2_val_labels:  Array[Label]       = []
var _p1_rows:        Array[HBoxContainer] = []
var _p2_rows:        Array[HBoxContainer] = []
var _p1_color_swatch: ColorRect
var _p2_color_swatch: ColorRect
var _p1_desc_label:   Label
var _p2_desc_label:   Label
var _p1_status_label: Label
var _p2_status_label: Label
var _p1_step_label:   Label
var _p2_step_label:   Label
var _p1_name_label:   Label
var _p2_name_label:   Label
var _panel_title_label: Label

const _COLOUR_ACTIVE := Color(1.0, 0.95, 0.4)       # yellow — currently choosing
const _COLOUR_LOCKED := Color(0.35, 0.80, 0.35)     # green  — confirmed
const _COLOUR_GREYED := Color(0.38, 0.38, 0.38)     # grey   — not yet reached

const _STEP_HINTS := [
	"Choose your save slot  (◄ ► to browse, Boost to load)",
	"Choose Blade",
	"Choose Track",
	"Choose Tip",
	"Choose Color  (Boost to confirm & save)",
	"",
]


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# ── Score panel — top centre ───────────────────────────────────────────────
	var score_panel := PanelContainer.new()
	score_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	score_panel.offset_top    =  10
	score_panel.offset_bottom =  60
	score_panel.offset_left   = -160
	score_panel.offset_right  =  160
	root.add_child(score_panel)

	var score_hbox := HBoxContainer.new()
	score_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	score_hbox.add_theme_constant_override("separation", 40)
	score_panel.add_child(score_hbox)

	_p1_score_label = _make_label("P1: 0", Color(0.4, 0.7, 1.0), 28)
	score_hbox.add_child(_p1_score_label)
	score_hbox.add_child(_make_label("—", Color(0.8, 0.8, 0.8), 28))
	_p2_score_label = _make_label("P2: 0", Color(1.0, 0.4, 0.4), 28)
	score_hbox.add_child(_p2_score_label)

	# ── Boost bars — bottom corners ────────────────────────────────────────────
	var p1_bar := _make_boost_bar(Color(0.4, 0.7, 1.0))
	p1_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	p1_bar.offset_bottom = -20; p1_bar.offset_left  = 20
	p1_bar.offset_top    = -50; p1_bar.offset_right = 220
	root.add_child(p1_bar)
	_boost_bars.append(p1_bar)

	var p2_bar := _make_boost_bar(Color(1.0, 0.4, 0.4))
	p2_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	p2_bar.offset_bottom = -20; p2_bar.offset_right = -20
	p2_bar.offset_top    = -50; p2_bar.offset_left  = -220
	root.add_child(p2_bar)
	_boost_bars.append(p2_bar)

	# ── Controls hint ──────────────────────────────────────────────────────────
	var ctrl := _make_label(
		"P1: WASD / L-Stick · Space/A boost   " +
		"P2: Arrows / L-Stick · Enter/A boost   |   " +
		"RMB: orbit   MMB: pan   Scroll: zoom   Tab/Start: dynamic cam",
		Color(0.6, 0.6, 0.6), 14)
	ctrl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	ctrl.offset_bottom = -6; ctrl.offset_top  = -28
	ctrl.offset_left   = -400; ctrl.offset_right = 400
	ctrl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(ctrl)

	# ── Centre message ─────────────────────────────────────────────────────────
	_message_label = _make_label("", Color(1.0, 0.9, 0.2), 52)
	_message_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_message_label.offset_left  = -400; _message_label.offset_right  = 400
	_message_label.offset_top   =  -40; _message_label.offset_bottom =  40
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	root.add_child(_message_label)

	# ── Part selection overlay ─────────────────────────────────────────────────
	_build_shape_panel(root)


func _build_shape_panel(root: Control) -> void:
	_shape_panel = PanelContainer.new()
	_shape_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_shape_panel.offset_left   = -510
	_shape_panel.offset_right  =  510
	_shape_panel.offset_top    = -295
	_shape_panel.offset_bottom =  295
	_shape_panel.visible = false

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.04, 0.12, 0.95)
	bg.border_color = Color(0.35, 0.15, 0.9)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(10)
	_shape_panel.add_theme_stylebox_override("panel", bg)
	root.add_child(_shape_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shape_panel.add_child(vbox)

	# Title (stored so game_manager can update it during bot-config phase)
	_panel_title_label = _make_label("— BUILD YOUR TOP —", Color(1.0, 0.9, 0.3), 22)
	_panel_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_panel_title_label)

	# Two player columns
	var cols := HBoxContainer.new()
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.add_theme_constant_override("separation", 28)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(cols)

	cols.add_child(_build_player_select_panel(1))
	cols.add_child(_make_vseparator())
	cols.add_child(_build_player_select_panel(2))

	# Bottom hint
	var hint := _make_label(
		"◄ / ► to cycle   •   Boost / A to confirm each step   •   Profile slot saves your loadout",
		Color(0.55, 0.55, 0.55), 13)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)


func _build_player_select_panel(pid: int) -> VBoxContainer:
	var is_p1  := pid == 1
	var accent := Color(0.4, 0.7, 1.0) if is_p1 else Color(1.0, 0.4, 0.4)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	vbox.custom_minimum_size = Vector2(400, 0)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Player header (stored so we can relabel "BOT" in VS Bot mode)
	var name_lbl := _make_label("PLAYER %d" % pid, accent, 20)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)
	if is_p1: _p1_name_label = name_lbl
	else:     _p2_name_label = name_lbl

	# Current-step hint label
	var step_lbl := _make_label("Choose your save slot", Color(0.85, 0.85, 0.85), 13)
	step_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	step_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step_lbl.custom_minimum_size = Vector2(390, 0)
	vbox.add_child(step_lbl)

	var val_labels: Array[Label] = []
	var row_containers: Array[HBoxContainer] = []
	var color_swatch: ColorRect = null

	for i in range(_ROW_COUNT):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)

		# Key label ("Profile:", "Blade:", etc.)
		var key_lbl := _make_label("%s:" % _ROW_LABELS[i], Color(0.65, 0.65, 0.65), 15)
		key_lbl.custom_minimum_size = Vector2(62, 0)
		row.add_child(key_lbl)

		var arrow_l := _make_label("◄", Color(0.70, 0.70, 0.70), 17)
		row.add_child(arrow_l)

		# For the color row, insert a swatch box before the text.
		if i == _ROW_COLOR:
			var swatch := ColorRect.new()
			swatch.custom_minimum_size = Vector2(22, 22)
			swatch.color = Color.WHITE
			row.add_child(swatch)
			color_swatch = swatch

		var val_lbl := _make_label("—", accent, 19)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val_lbl.custom_minimum_size  = Vector2(160, 0)
		row.add_child(val_lbl)
		val_labels.append(val_lbl)

		var arrow_r := _make_label("►", Color(0.70, 0.70, 0.70), 17)
		row.add_child(arrow_r)

		row_containers.append(row)
		vbox.add_child(row)

	# Description — shows detail of the currently active row
	var desc_lbl := _make_label("", Color(0.62, 0.62, 0.62), 12)
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.custom_minimum_size = Vector2(390, 36)
	vbox.add_child(desc_lbl)

	# Ready / waiting status
	var status_lbl := _make_label("Waiting…", Color(0.6, 0.6, 0.6), 17)
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_lbl)

	# Store references
	if is_p1:
		_p1_val_labels   = val_labels
		_p1_rows         = row_containers
		_p1_color_swatch = color_swatch
		_p1_desc_label   = desc_lbl
		_p1_status_label = status_lbl
		_p1_step_label   = step_lbl
	else:
		_p2_val_labels   = val_labels
		_p2_rows         = row_containers
		_p2_color_swatch = color_swatch
		_p2_desc_label   = desc_lbl
		_p2_status_label = status_lbl
		_p2_step_label   = step_lbl

	return vbox


func _make_vseparator() -> VSeparator:
	var sep := VSeparator.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.35, 0.15, 0.9, 0.5)
	style.content_margin_left  = 1
	style.content_margin_right = 1
	sep.add_theme_stylebox_override("separator", style)
	return sep


# ── Public API ─────────────────────────────────────────────────────────────────

func update_scores(p1: int, p2: int) -> void:
	_p1_score_label.text = "P1: %d" % p1
	_p2_score_label.text = "P2: %d" % p2


func show_message(text: String) -> void:
	_message_label.text = text


func hide_message() -> void:
	_message_label.text = ""


func update_boost_bars(p1_frac: float, p2_frac: float) -> void:
	if _boost_bars.size() >= 2:
		_boost_bars[0].value = p1_frac * 100.0
		_boost_bars[1].value = p2_frac * 100.0


func show_part_select(
		p1_profile: int, p1_blade: int, p1_track: int, p1_tip: int, p1_color_idx: int, p1_step: int,
		p2_profile: int, p2_blade: int, p2_track: int, p2_tip: int, p2_color_idx: int, p2_step: int) -> void:
	_shape_panel.visible = true
	update_part_select(
		p1_profile, p1_blade, p1_track, p1_tip, p1_color_idx, p1_step,
		p2_profile, p2_blade, p2_track, p2_tip, p2_color_idx, p2_step)


# step values: 0=Profile  1=Blade  2=Track  3=Tip  4=Color  5=Done
func update_part_select(
		p1_profile: int, p1_blade: int, p1_track: int, p1_tip: int, p1_color_idx: int, p1_step: int,
		p2_profile: int, p2_blade: int, p2_track: int, p2_tip: int, p2_color_idx: int, p2_step: int) -> void:
	_refresh_player(
		1,
		_p1_val_labels, _p1_rows, _p1_color_swatch,
		_p1_desc_label, _p1_status_label, _p1_step_label,
		p1_profile, p1_blade, p1_track, p1_tip, p1_color_idx, p1_step)
	_refresh_player(
		2,
		_p2_val_labels, _p2_rows, _p2_color_swatch,
		_p2_desc_label, _p2_status_label, _p2_step_label,
		p2_profile, p2_blade, p2_track, p2_tip, p2_color_idx, p2_step)


func set_panel_title(text: String) -> void:
	if _panel_title_label:
		_panel_title_label.text = text


# Call once when a selection session starts so column headers reflect the mode.
# In VS Bot mode P2 is labelled "BOT"; in 2-player mode it's "PLAYER 2".
func setup_mode(vs_bot: bool) -> void:
	if _p2_name_label:
		if vs_bot:
			_p2_name_label.text = "BOT"
			_p2_name_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.15))
		else:
			_p2_name_label.text = "PLAYER 2"
			_p2_name_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))


func hide_shape_select() -> void:
	_shape_panel.visible = false


# ── Internal refresh ───────────────────────────────────────────────────────────

func _refresh_player(
		pid: int,
		val_labels: Array[Label],
		rows: Array[HBoxContainer],
		color_swatch: ColorRect,
		desc_lbl: Label,
		status_lbl: Label,
		step_lbl: Label,
		profile_idx: int, blade_idx: int, track_idx: int,
		tip_idx: int, color_idx: int, step: int) -> void:

	# ── Compose value text for each row ─────────────────────────────────────────
	var saved := GameSettings.profile_exists(pid, profile_idx)
	var slot_text := "Slot %d%s" % [profile_idx + 1, "  ✓" if saved else ""]

	var row_values := [
		slot_text,
		TopScript.blade_name(blade_idx),
		TopScript.track_name(track_idx),
		TopScript.tip_name(tip_idx),
		GameSettings.get_color_name(color_idx),
	]

	# ── Update each row's label and arrow visibility ─────────────────────────────
	for i in range(_ROW_COUNT):
		var lbl := val_labels[i]
		lbl.text = row_values[i]

		var row_color: Color
		if i < step:
			row_color = _COLOUR_LOCKED   # confirmed
		elif i == step:
			row_color = _COLOUR_ACTIVE   # currently choosing
		else:
			row_color = _COLOUR_GREYED   # not yet reached

		lbl.add_theme_color_override("font_color", row_color)

		# Show arrows only on the active row.
		var row := rows[i]
		for ci in range(row.get_child_count()):
			var child := row.get_child(ci)
			if child is Label:
				var t: String = (child as Label).text
				if t == "◄" or t == "►":
					child.modulate.a = 1.0 if i == step else 0.2

	# ── Color swatch ────────────────────────────────────────────────────────────
	if color_swatch:
		color_swatch.color = GameSettings.get_color(color_idx)
		# Dim swatch when the color row isn't yet reached.
		color_swatch.modulate.a = 1.0 if step >= _ROW_COLOR else 0.3

	# ── Step hint label ──────────────────────────────────────────────────────────
	step_lbl.text = _STEP_HINTS[mini(step, _STEP_HINTS.size() - 1)]

	# ── Description label ────────────────────────────────────────────────────────
	match step:
		_ROW_PROFILE:
			# Show what's stored in the selected slot.
			var prof := GameSettings.load_profile(pid, profile_idx)
			if prof.size() > 0:
				desc_lbl.text = "Saved: %s / %s / %s  ·  %s" % [
					TopScript.blade_name(prof.blade),
					TopScript.track_name(prof.track),
					TopScript.tip_name(prof.tip),
					GameSettings.get_color_name(prof.color_idx),
				]
			else:
				desc_lbl.text = "(empty — will use current defaults)"
		_ROW_BLADE:
			desc_lbl.text = TopScript.blade_desc(blade_idx)
		_ROW_TRACK:
			desc_lbl.text = TopScript.track_desc(track_idx)
		_ROW_TIP:
			desc_lbl.text = TopScript.tip_desc(tip_idx)
		_ROW_COLOR:
			desc_lbl.text = "Your top's tint colour.  Confirming saves to Slot %d." % (profile_idx + 1)
		_:
			desc_lbl.text = ""

	# ── Status label ─────────────────────────────────────────────────────────────
	if step >= 5:   # STEP_DONE
		status_lbl.text = "✓  Ready!"
		status_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	else:
		status_lbl.text = "Waiting…"
		status_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))


# ── Helpers ────────────────────────────────────────────────────────────────────

func _make_label(text: String, color: Color, size: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", size)
	return lbl


func _make_boost_bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(200, 20)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", style)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.15, 0.15, 0.15, 0.8)
	bg_style.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg_style)
	return bar
