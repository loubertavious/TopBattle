## DevConsole — toggled with F12 at any time.
##
## Controls:
##   Sound pool toggles  — enable / disable each of the five sound pools
##   Bowl colour         — live-recolours the arena floor shader
##   Sky colour          — changes background / ambient light colour
##
## GameSettings.bowl_mat and GameSettings.world_env are populated by
## game_manager when a match starts; controls are silently no-ops in the menu.

extends CanvasLayer

const _TOGGLE_KEY := KEY_F12

# Pool names paired with display labels (order matches the grid)
const _SOUND_POOLS: Array = [
	["Blade_Blade", "Blade vs Blade"],
	["Blade_Ring",  "Blade vs Ring"],
	["Blade_Track", "Blade vs Track"],
	["Blade_Wall",  "Blade vs Wall"],
	["Tip_Wall",    "Tip vs Wall"],
]

var _panel: PanelContainer
var _sound_checks: Dictionary = {}   # pool_key → CheckButton
var _bowl_picker: ColorPickerButton
var _sky_picker:  ColorPickerButton
var _rim_picker:  ColorPickerButton
var _wall_picker: ColorPickerButton
var _model_scale_spin:    SpinBox
var _model_y_offset_spin: SpinBox
var _pause_btn:            Button
var _master_vol_slider:    HSlider
var _clash_vol_slider:     HSlider
var _wall_vol_slider:      HSlider


func _ready() -> void:
	layer = 128   # render above everything
	# Keep the console running while the game is paused so adjustments still work.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_panel.visible = false


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == _TOGGLE_KEY and event.pressed and not event.echo:
		_panel.visible = not _panel.visible
		if _panel.visible:
			_refresh_pickers()   # sync colour buttons to current state
		else:
			# Auto-unpause when closing the console so the game can't get stuck frozen.
			if get_tree().paused:
				get_tree().paused  = false
				_pause_btn.text    = "⏸   PAUSE"
		get_viewport().set_input_as_handled()


# ── Build ───────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_right  = -14
	_panel.offset_top    =  14
	_panel.offset_left   = -430
	_panel.offset_bottom =  760

	var chrome := StyleBoxFlat.new()
	chrome.bg_color     = Color(0.05, 0.04, 0.12, 0.97)
	chrome.border_color = Color(0.45, 0.20, 0.95, 0.85)
	chrome.set_border_width_all(2)
	chrome.set_corner_radius_all(12)
	chrome.shadow_color = Color(0.3, 0.1, 0.8, 0.35)
	chrome.shadow_size  = 12
	chrome.content_margin_left   = 16
	chrome.content_margin_right  = 16
	chrome.content_margin_top    = 12
	chrome.content_margin_bottom = 16
	_panel.add_theme_stylebox_override("panel", chrome)
	add_child(_panel)

	# ScrollContainer lets the panel overflow its fixed height.
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)

	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(root_vbox)

	# ── Title bar ──────────────────────────────────────────────────────────────
	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root_vbox.add_child(title_row)

	var title := _make_label("🔧  DEV CONSOLE", Color(1.0, 0.88, 0.30), 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	var hint := _make_label("F12", Color(0.45, 0.45, 0.52), 12)
	title_row.add_child(hint)

	# ── Pause button ───────────────────────────────────────────────────────────
	_pause_btn = Button.new()
	_pause_btn.text = "⏸   PAUSE"
	_pause_btn.add_theme_font_size_override("font_size", 13)
	_pause_btn.add_theme_color_override("font_color", Color(0.20, 0.90, 0.55))
	_pause_btn.pressed.connect(_on_pause_toggled)
	root_vbox.add_child(_pause_btn)

	root_vbox.add_child(_make_separator())

	# ── Sound toggles ──────────────────────────────────────────────────────────
	root_vbox.add_child(_make_section_label("SOUNDS"))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	root_vbox.add_child(grid)

	for entry in _SOUND_POOLS:
		var key: String   = entry[0]
		var label: String = entry[1]
		var btn           := _make_check(label, GameSettings.sound_enabled.get(key, true))
		btn.toggled.connect(_on_sound_toggled.bind(key))
		grid.add_child(btn)
		_sound_checks[key] = btn

	root_vbox.add_child(_make_separator())

	# ── Volume sliders ─────────────────────────────────────────────────────────
	root_vbox.add_child(_make_section_label("VOLUME"))

	_master_vol_slider = _make_vol_row(root_vbox, "Master",
		GameSettings.master_volume * 100.0)
	_master_vol_slider.value_changed.connect(_on_master_volume_changed)

	_clash_vol_slider = _make_vol_row(root_vbox, "Clash  (dB offset)",
		GameSettings.clash_volume_db, -20.0, 20.0, 0.5)
	_clash_vol_slider.value_changed.connect(_on_clash_volume_changed)

	_wall_vol_slider = _make_vol_row(root_vbox, "Wall  (dB offset)",
		GameSettings.wall_volume_db, -20.0, 20.0, 0.5)
	_wall_vol_slider.value_changed.connect(_on_wall_volume_changed)

	root_vbox.add_child(_make_separator())

	# ── Bowl colour ────────────────────────────────────────────────────────────
	root_vbox.add_child(_make_section_label("BOWL COLOUR"))

	var bowl_row := HBoxContainer.new()
	bowl_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	bowl_row.add_theme_constant_override("separation", 10)
	root_vbox.add_child(bowl_row)

	var bowl_lbl := _make_label("Base colour", Color(0.70, 0.70, 0.78), 13)
	bowl_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bowl_row.add_child(bowl_lbl)

	_bowl_picker = ColorPickerButton.new()
	_bowl_picker.color               = Color(0.08, 0.08, 0.10)   # shader default
	_bowl_picker.custom_minimum_size = Vector2(80, 30)
	_bowl_picker.color_changed.connect(_on_bowl_color_changed)
	bowl_row.add_child(_bowl_picker)

	root_vbox.add_child(_make_separator())

	# ── Sky / ambient colour ───────────────────────────────────────────────────
	root_vbox.add_child(_make_section_label("SKY / AMBIENT"))

	var sky_row := HBoxContainer.new()
	sky_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	sky_row.add_theme_constant_override("separation", 10)
	root_vbox.add_child(sky_row)

	var sky_lbl := _make_label("Ambient tint", Color(0.70, 0.70, 0.78), 13)
	sky_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sky_row.add_child(sky_lbl)

	_sky_picker = ColorPickerButton.new()
	_sky_picker.color               = Color(0.12, 0.12, 0.14)   # env default
	_sky_picker.custom_minimum_size = Vector2(80, 30)
	_sky_picker.color_changed.connect(_on_sky_color_changed)
	sky_row.add_child(_sky_picker)

	var sky_note := _make_label(
		"Changes ambient light tint.\nOverrides sky texture ambient when a texture is loaded.",
		Color(0.38, 0.38, 0.45), 11)
	sky_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_vbox.add_child(sky_note)

	root_vbox.add_child(_make_separator())

	# ── Rim (torus + glow light) colour ───────────────────────────────────────
	root_vbox.add_child(_make_section_label("RIM COLOUR"))

	var rim_row := HBoxContainer.new()
	rim_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	rim_row.add_theme_constant_override("separation", 10)
	root_vbox.add_child(rim_row)

	var rim_lbl := _make_label("Perimeter glow", Color(0.70, 0.70, 0.78), 13)
	rim_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rim_row.add_child(rim_lbl)

	_rim_picker = ColorPickerButton.new()
	_rim_picker.color               = Color(0.65, 0.65, 0.70)   # matches ring_light default
	_rim_picker.custom_minimum_size = Vector2(80, 30)
	_rim_picker.color_changed.connect(_on_rim_color_changed)
	rim_row.add_child(_rim_picker)

	root_vbox.add_child(_make_separator())

	# ── Wall (arc panels) colour ───────────────────────────────────────────────
	root_vbox.add_child(_make_section_label("WALL COLOUR"))

	var wall_row := HBoxContainer.new()
	wall_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	wall_row.add_theme_constant_override("separation", 10)
	root_vbox.add_child(wall_row)

	var wall_lbl := _make_label("Panel emission", Color(0.70, 0.70, 0.78), 13)
	wall_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wall_row.add_child(wall_lbl)

	_wall_picker = ColorPickerButton.new()
	_wall_picker.color               = Color(0.28, 0.28, 0.32)   # matches seg_mat default
	_wall_picker.custom_minimum_size = Vector2(80, 30)
	_wall_picker.color_changed.connect(_on_wall_color_changed)
	wall_row.add_child(_wall_picker)

	root_vbox.add_child(_make_separator())

	# ── Model import scale ─────────────────────────────────────────────────────
	root_vbox.add_child(_make_section_label("MODEL SCALE"))

	var scale_row := HBoxContainer.new()
	scale_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	scale_row.add_theme_constant_override("separation", 10)
	root_vbox.add_child(scale_row)

	var scale_lbl := _make_label("Import scale", Color(0.70, 0.70, 0.78), 13)
	scale_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_row.add_child(scale_lbl)

	_model_scale_spin = SpinBox.new()
	_model_scale_spin.min_value    = 0.001
	_model_scale_spin.max_value    = 2.0
	_model_scale_spin.step         = 0.001
	_model_scale_spin.value        = GameSettings.model_import_scale   # default 0.018
	_model_scale_spin.custom_minimum_size = Vector2(110, 30)
	_model_scale_spin.value_changed.connect(_on_model_scale_changed)
	scale_row.add_child(_model_scale_spin)

	var y_row := HBoxContainer.new()
	y_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	y_row.add_theme_constant_override("separation", 10)
	root_vbox.add_child(y_row)

	var y_lbl := _make_label("Y offset", Color(0.70, 0.70, 0.78), 13)
	y_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	y_row.add_child(y_lbl)

	_model_y_offset_spin = SpinBox.new()
	_model_y_offset_spin.min_value    = -5.0
	_model_y_offset_spin.max_value    =  5.0
	_model_y_offset_spin.step         =  0.001
	_model_y_offset_spin.value        = GameSettings.model_y_offset   # default -0.25
	_model_y_offset_spin.custom_minimum_size = Vector2(110, 30)
	_model_y_offset_spin.value_changed.connect(_on_model_y_offset_changed)
	y_row.add_child(_model_y_offset_spin)

	var scale_note := _make_label(
		"1.0 = metres  •  0.01 = centimetres\nTakes effect on next round.",
		Color(0.38, 0.38, 0.45), 11)
	scale_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_vbox.add_child(scale_note)

	root_vbox.add_child(_make_separator())

	# ── Footer ─────────────────────────────────────────────────────────────────
	var footer := _make_label(
		"Changes apply live. Sound toggles persist per session.\nClose:  F12",
		Color(0.38, 0.38, 0.45), 11)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_vbox.add_child(footer)


# ── Callbacks ───────────────────────────────────────────────────────────────────

func _on_sound_toggled(pressed: bool, pool_key: String) -> void:
	GameSettings.sound_enabled[pool_key] = pressed


func _on_bowl_color_changed(color: Color) -> void:
	if GameSettings.bowl_mat:
		GameSettings.bowl_mat.set_shader_parameter("base_color", color)


func _on_sky_color_changed(color: Color) -> void:
	if not GameSettings.world_env:
		return
	var env := GameSettings.world_env.environment
	if env.background_mode == Environment.BG_COLOR:
		# No sky texture — update both background and ambient.
		env.background_color    = color.darkened(0.3)
		env.ambient_light_color = color
	else:
		# Panorama sky — only tweak ambient tint so the texture still shows.
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color  = color
		env.ambient_light_energy = 0.6


func _on_rim_color_changed(color: Color) -> void:
	# Torus ring: albedo is a dark version of the chosen colour; emission is the colour itself.
	if GameSettings.rim_mat:
		GameSettings.rim_mat.albedo_color = color.darkened(0.55)
		GameSettings.rim_mat.emission     = color
	# Ring light tints the whole bowl in that colour.
	if GameSettings.rim_light:
		GameSettings.rim_light.light_color = color


func _on_wall_color_changed(color: Color) -> void:
	# Arc wall panels: same albedo/emission split as the rim.
	if GameSettings.wall_mat:
		GameSettings.wall_mat.albedo_color = color.darkened(0.55)
		GameSettings.wall_mat.emission     = color


func _on_model_scale_changed(value: float) -> void:
	GameSettings.model_import_scale = value
	_apply_live_model_adjustments()


func _on_model_y_offset_changed(value: float) -> void:
	GameSettings.model_y_offset = value
	_apply_live_model_adjustments()


func _on_master_volume_changed(value: float) -> void:
	GameSettings.master_volume = value / 100.0
	AudioServer.set_bus_volume_db(0, linear_to_db(GameSettings.master_volume))


func _on_clash_volume_changed(value: float) -> void:
	GameSettings.clash_volume_db = value


func _on_wall_volume_changed(value: float) -> void:
	GameSettings.wall_volume_db = value


func _on_pause_toggled() -> void:
	get_tree().paused = not get_tree().paused
	if get_tree().paused:
		_pause_btn.text = "▶   RESUME"
		_pause_btn.add_theme_color_override("font_color", Color(1.0, 0.55, 0.15))
	else:
		_pause_btn.text = "⏸   PAUSE"
		_pause_btn.add_theme_color_override("font_color", Color(0.20, 0.90, 0.55))


# Pushes current scale + Y offset to all live top models immediately.
func _apply_live_model_adjustments() -> void:
	for top in GameSettings.live_tops:
		if is_instance_valid(top) and top.has_method("apply_model_adjustments"):
			top.apply_model_adjustments()


# Syncs colour pickers to current live values when console opens.
func _refresh_pickers() -> void:
	# Bowl colour
	if GameSettings.bowl_mat:
		var c = GameSettings.bowl_mat.get_shader_parameter("base_color")
		if c is Color:
			_bowl_picker.color = c

	# Sky / ambient colour
	if GameSettings.world_env:
		var env := GameSettings.world_env.environment
		_sky_picker.color = env.ambient_light_color

	# Rim colour — read from the ring light (most visible indicator)
	if GameSettings.rim_light:
		_rim_picker.color = GameSettings.rim_light.light_color
	elif GameSettings.rim_mat:
		_rim_picker.color = GameSettings.rim_mat.emission

	# Wall colour — read from the shared seg_mat emission
	if GameSettings.wall_mat:
		_wall_picker.color = GameSettings.wall_mat.emission

	# Model scale / offset
	if _model_scale_spin:
		_model_scale_spin.value = GameSettings.model_import_scale
	if _model_y_offset_spin:
		_model_y_offset_spin.value = GameSettings.model_y_offset

	# Volume sliders
	if _master_vol_slider:
		_master_vol_slider.value = GameSettings.master_volume * 100.0
	if _clash_vol_slider:
		_clash_vol_slider.value = GameSettings.clash_volume_db
	if _wall_vol_slider:
		_wall_vol_slider.value = GameSettings.wall_volume_db

	# Sync checkboxes in case sound_enabled was changed externally
	for key in _sound_checks:
		(_sound_checks[key] as CheckButton).button_pressed = \
			GameSettings.sound_enabled.get(key, true)


# ── Helpers ─────────────────────────────────────────────────────────────────────

func _make_label(text: String, color: Color, size: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", size)
	return lbl


func _make_section_label(text: String) -> Label:
	var lbl := _make_label(text, Color(0.55, 0.55, 0.65), 12)
	lbl.uppercase = true
	return lbl


func _make_check(label: String, initial: bool) -> CheckButton:
	var btn := CheckButton.new()
	btn.text           = label
	btn.button_pressed = initial
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color(0.80, 0.80, 0.88))
	return btn


# Adds a labelled HSlider row to parent and returns the slider.
# min/max default to 0–100 for the master (percentage); pass explicit range for dB offsets.
func _make_vol_row(parent: Control, label_text: String, initial: float,
		min_val: float = 0.0, max_val: float = 100.0, step: float = 1.0) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var lbl := _make_label(label_text, Color(0.70, 0.70, 0.78), 13)
	lbl.custom_minimum_size = Vector2(130, 0)
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value              = min_val
	slider.max_value              = max_val
	slider.step                   = step
	slider.value                  = initial
	slider.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size    = Vector2(0, 24)
	row.add_child(slider)

	var val_lbl := _make_label("%d" % int(initial), Color(0.55, 0.85, 0.55), 12)
	val_lbl.custom_minimum_size = Vector2(36, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val_lbl)

	# Keep the value label in sync with the slider.
	slider.value_changed.connect(func(v: float) -> void:
		val_lbl.text = "%d" % int(v))

	return slider


func _make_separator() -> HSeparator:
	var sep   := HSeparator.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.35, 0.18, 0.80, 0.35)
	style.content_margin_top    = 1
	style.content_margin_bottom = 1
	sep.add_theme_stylebox_override("separator", style)
	return sep
