extends CanvasLayer

const TopScript = preload("res://scripts/top.gd")

var _p1_score_label: Label
var _p2_score_label: Label
var _message_label: Label
var _boost_bars: Array[ProgressBar] = []

# Shape selection panel nodes
var _shape_panel: PanelContainer
var _p1_shape_label: Label
var _p2_shape_label: Label
var _p1_desc_label: Label
var _p2_desc_label: Label
var _p1_status_label: Label
var _p2_status_label: Label


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# ── Score panel — top centre ───────────────────────────────────────────────
	var score_panel := PanelContainer.new()
	score_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	score_panel.offset_top = 10
	score_panel.offset_bottom = 60
	score_panel.offset_left = -160
	score_panel.offset_right = 160
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
	p1_bar.offset_bottom = -20; p1_bar.offset_left = 20
	p1_bar.offset_top = -50;   p1_bar.offset_right = 220
	root.add_child(p1_bar)
	_boost_bars.append(p1_bar)

	var p2_bar := _make_boost_bar(Color(1.0, 0.4, 0.4))
	p2_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	p2_bar.offset_bottom = -20; p2_bar.offset_right = -20
	p2_bar.offset_top = -50;   p2_bar.offset_left = -220
	root.add_child(p2_bar)
	_boost_bars.append(p2_bar)

	# ── Controls hint ──────────────────────────────────────────────────────────
	var ctrl := _make_label(
		"P1: WASD / L-Stick · Space/A boost   P2: Arrows / L-Stick · Enter/A boost   |   RMB: orbit   MMB: pan   Scroll: zoom   Tab/Start: dynamic cam",
		Color(0.6, 0.6, 0.6), 14
	)
	ctrl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	ctrl.offset_bottom = -6; ctrl.offset_top = -28
	ctrl.offset_left = -400; ctrl.offset_right = 400
	ctrl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(ctrl)

	# ── Centre message ─────────────────────────────────────────────────────────
	_message_label = _make_label("", Color(1.0, 0.9, 0.2), 52)
	_message_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_message_label.offset_left = -400; _message_label.offset_right = 400
	_message_label.offset_top = -40;   _message_label.offset_bottom = 40
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	root.add_child(_message_label)

	# ── Shape selection overlay ────────────────────────────────────────────────
	_build_shape_panel(root)


func _build_shape_panel(root: Control) -> void:
	_shape_panel = PanelContainer.new()
	_shape_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_shape_panel.offset_left  = -460; _shape_panel.offset_right  = 460
	_shape_panel.offset_top   = -200; _shape_panel.offset_bottom = 200
	_shape_panel.visible = false

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.04, 0.12, 0.95)
	bg.border_color = Color(0.35, 0.15, 0.9)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(10)
	_shape_panel.add_theme_stylebox_override("panel", bg)
	root.add_child(_shape_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shape_panel.add_child(vbox)

	# Title
	var title := _make_label("— CHOOSE YOUR TOP —", Color(1.0, 0.9, 0.3), 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Two player columns
	var cols := HBoxContainer.new()
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.add_theme_constant_override("separation", 40)
	vbox.add_child(cols)

	var p1_panel := _build_player_select_panel(1)
	var p2_panel := _build_player_select_panel(2)
	cols.add_child(p1_panel)
	cols.add_child(_make_vseparator())
	cols.add_child(p2_panel)

	# Bottom hint
	var hint := _make_label("Both players confirm to start!", Color(0.7, 0.7, 0.7), 15)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)


func _build_player_select_panel(pid: int) -> VBoxContainer:
	var is_p1 := pid == 1
	var accent := Color(0.4, 0.7, 1.0) if is_p1 else Color(1.0, 0.4, 0.4)
	var col_key := "A / D" if is_p1 else "← / →"
	var confirm_key := "SPACE" if is_p1 else "ENTER"

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	vbox.custom_minimum_size = Vector2(360, 0)

	# Player name header
	var name_lbl := _make_label("PLAYER %d" % pid, accent, 20)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)

	# Shape selector row  ◄  NAME  ►
	var sel_hbox := HBoxContainer.new()
	sel_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	sel_hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(sel_hbox)

	sel_hbox.add_child(_make_label("◄", Color(0.8, 0.8, 0.8), 22))

	var shape_lbl := _make_label("Round", accent, 28)
	shape_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shape_lbl.custom_minimum_size = Vector2(220, 0)
	sel_hbox.add_child(shape_lbl)

	sel_hbox.add_child(_make_label("►", Color(0.8, 0.8, 0.8), 22))

	# Description
	var desc_lbl := _make_label(TopScript.type_desc(0), Color(0.7, 0.7, 0.7), 13)
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.custom_minimum_size = Vector2(340, 36)
	vbox.add_child(desc_lbl)

	# Controls hint
	var ctrl_lbl := _make_label(
		"%s to change  •  %s to confirm" % [col_key, confirm_key],
		Color(0.55, 0.55, 0.55), 13
	)
	ctrl_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(ctrl_lbl)

	# Confirm status
	var status_lbl := _make_label("Waiting…", Color(0.6, 0.6, 0.6), 18)
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_lbl)

	# Store references
	if is_p1:
		_p1_shape_label  = shape_lbl
		_p1_desc_label   = desc_lbl
		_p1_status_label = status_lbl
	else:
		_p2_shape_label  = shape_lbl
		_p2_desc_label   = desc_lbl
		_p2_status_label = status_lbl

	return vbox


func _make_vseparator() -> VSeparator:
	var sep := VSeparator.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.35, 0.15, 0.9, 0.5)
	style.content_margin_left = 1
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


func show_shape_select(p1_shape: int, p2_shape: int) -> void:
	_shape_panel.visible = true
	update_shape_select(p1_shape, p2_shape, false, false)


func update_shape_select(p1_shape: int, p2_shape: int, p1_ok: bool, p2_ok: bool) -> void:
	_p1_shape_label.text = TopScript.type_name(p1_shape)
	_p2_shape_label.text = TopScript.type_name(p2_shape)
	_p1_desc_label.text  = TopScript.type_desc(p1_shape)
	_p2_desc_label.text  = TopScript.type_desc(p2_shape)

	if p1_ok:
		_p1_status_label.text = "✓  Ready!"
		_p1_status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	else:
		_p1_status_label.text = "Waiting…"
		_p1_status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))

	if p2_ok:
		_p2_status_label.text = "✓  Ready!"
		_p2_status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	else:
		_p2_status_label.text = "Waiting…"
		_p2_status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))


func hide_shape_select() -> void:
	_shape_panel.visible = false


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
