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
	["clash_blade", "Clash — Blade"],
	["clash_ring",  "Clash — Ring"],
	["clash_body",  "Clash — Body"],
	["wall_blade",  "Wall — Blade"],
	["wall_tip",    "Wall — Tip"],
]

var _panel: PanelContainer
var _sound_checks: Dictionary = {}   # pool_key → CheckButton
var _bowl_picker: ColorPickerButton
var _sky_picker:  ColorPickerButton
var _rim_picker:  ColorPickerButton
var _wall_picker: ColorPickerButton


func _ready() -> void:
	layer = 128   # render above everything
	_build_ui()
	_panel.visible = false


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == _TOGGLE_KEY and event.pressed and not event.echo:
		_panel.visible = not _panel.visible
		if _panel.visible:
			_refresh_pickers()   # sync colour buttons to current state
		get_viewport().set_input_as_handled()


# ── Build ───────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_right  = -14
	_panel.offset_top    =  14
	_panel.offset_left   = -430
	_panel.offset_bottom =  590

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

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(root_vbox)

	# ── Title bar ──────────────────────────────────────────────────────────────
	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root_vbox.add_child(title_row)

	var title := _make_label("🔧  DEV CONSOLE", Color(1.0, 0.88, 0.30), 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	var hint := _make_label("F12", Color(0.45, 0.45, 0.52), 12)
	title_row.add_child(hint)

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
	_bowl_picker.color               = Color(0.45, 0.03, 0.04)   # shader default
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
	_sky_picker.color               = Color(0.06, 0.03, 0.18)   # env default
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
	_rim_picker.color               = Color(0.97, 0.62, 0.65)   # matches ring_light default
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
	_wall_picker.color               = Color(0.45, 0.03, 0.04)   # matches seg_mat default
	_wall_picker.custom_minimum_size = Vector2(80, 30)
	_wall_picker.color_changed.connect(_on_wall_color_changed)
	wall_row.add_child(_wall_picker)

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


func _make_separator() -> HSeparator:
	var sep   := HSeparator.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.35, 0.18, 0.80, 0.35)
	style.content_margin_top    = 1
	style.content_margin_bottom = 1
	sep.add_theme_stylebox_override("separator", style)
	return sep
