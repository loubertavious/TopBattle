extends Node3D

const TopScript        = preload("res://scripts/top.gd")
const ARENA_RADIUS     := 6.5
const BOWL_SPHERE_R    := 13.0

# ── Camera ─────────────────────────────────────────────────────────────────────
var _camera:        Camera3D
var _cam_azimuth:   float   = 0.4
var _cam_elevation: float   = 0.62
var _cam_dist:      float   = 20.0
var _cam_pivot:     Vector3 = Vector3.ZERO

# ── Demo tops ──────────────────────────────────────────────────────────────────
var _tops:           Array  = []
var _bot_timer:      float  = 0.0
var _respawn_timer:  float  = -1.0

# ── Menu UI ────────────────────────────────────────────────────────────────────
var _selected:       int          = 0
var _btn_nodes:      Array[Button] = []
const OPTIONS := ["2 PLAYER", "VS BOT", "QUIT"]


func _ready() -> void:
	_setup_environment()
	_setup_arena()
	_setup_camera()
	_spawn_demo_tops()
	_build_ui()


func _process(delta: float) -> void:
	_orbit_camera(delta)
	_update_bots(delta)
	_tick_respawn(delta)


# ── Input ──────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_W, KEY_UP:
				_move_selection(-1)
			KEY_S, KEY_DOWN:
				_move_selection(1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_confirm()

	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			11: _move_selection(-1)   # D-pad up
			12: _move_selection(1)    # D-pad down
			0:  _confirm()            # A / Cross


func _move_selection(dir: int) -> void:
	_selected = (_selected + dir + OPTIONS.size()) % OPTIONS.size()
	_refresh_buttons()


func _confirm() -> void:
	match _selected:
		0:
			GameSettings.vs_bot = false
			get_tree().change_scene_to_file("res://scenes/main.tscn")
		1:
			GameSettings.vs_bot = true
			get_tree().change_scene_to_file("res://scenes/main.tscn")
		2:
			get_tree().quit()


# ── UI ─────────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(root)

	# Gradient fade on the left so text is readable over the 3D scene.
	var fade := ColorRect.new()
	fade.color = Color(0.03, 0.02, 0.07, 0.72)
	fade.set_anchor(SIDE_LEFT,   0.0); fade.set_anchor(SIDE_RIGHT,  0.0)
	fade.set_anchor(SIDE_TOP,    0.0); fade.set_anchor(SIDE_BOTTOM, 1.0)
	fade.offset_right = 420
	root.add_child(fade)

	# Title
	var title := Label.new()
	title.text = "TOP BATTLE"
	title.add_theme_font_size_override("font_size", 58)
	title.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	title.position = Vector2(64, 148)
	root.add_child(title)

	# Option buttons — plain text, no background
	_btn_nodes.clear()
	var blank := StyleBoxEmpty.new()
	for i in range(OPTIONS.size()):
		var btn := Button.new()
		btn.text        = OPTIONS[i]
		btn.flat        = true
		btn.alignment   = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(320, 50)
		btn.position    = Vector2(64, 300 + i * 58)
		btn.add_theme_font_size_override("font_size", 32)
		btn.add_theme_stylebox_override("normal",   blank)
		btn.add_theme_stylebox_override("hover",    blank)
		btn.add_theme_stylebox_override("pressed",  blank)
		btn.add_theme_stylebox_override("focus",    blank)
		btn.add_theme_color_override("font_hover_color",   Color(1.0, 1.0, 1.0))
		btn.add_theme_color_override("font_pressed_color", Color(0.85, 0.85, 0.85))
		root.add_child(btn)
		_btn_nodes.append(btn)

		var idx := i   # capture for lambda
		btn.pressed.connect(func(): _selected = idx; _confirm())
		btn.mouse_entered.connect(func(): _selected = idx; _refresh_buttons())

	_refresh_buttons()

	# Hint
	var hint := Label.new()
	hint.text = "W / S  ·  ↑ / ↓  to navigate     Enter to select"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.38, 0.36, 0.46))
	hint.set_anchor(SIDE_TOP, 1.0); hint.set_anchor(SIDE_BOTTOM, 1.0)
	hint.offset_top = -32; hint.offset_left = 64
	root.add_child(hint)


func _refresh_buttons() -> void:
	for i in range(_btn_nodes.size()):
		var btn := _btn_nodes[i]
		if i == _selected:
			btn.text = "▶   " + OPTIONS[i]
			btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		else:
			btn.text = "     " + OPTIONS[i]
			btn.add_theme_color_override("font_color", Color(0.38, 0.36, 0.46))


# ── Camera ─────────────────────────────────────────────────────────────────────
func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = 56.0
	add_child(_camera)
	_apply_camera()


func _orbit_camera(delta: float) -> void:
	_cam_azimuth += delta * 0.10   # gentle slow orbit

	# Smoothly follow midpoint of the two tops.
	var target := Vector3.ZERO
	var alive: Array[Vector3] = []
	for top in _tops:
		if top.is_alive:
			alive.append(top.global_position)
	if alive.size() == 2:
		target = Vector3((alive[0].x + alive[1].x) * 0.5,
						  0.0,
						 (alive[0].z + alive[1].z) * 0.5)
	elif alive.size() == 1:
		target = Vector3(alive[0].x, 0.0, alive[0].z)

	var k := 1.0 - exp(-1.8 * delta)
	_cam_pivot = _cam_pivot.lerp(target, k)
	_apply_camera()


func _apply_camera() -> void:
	var offset := Vector3(
		cos(_cam_elevation) * sin(_cam_azimuth),
		sin(_cam_elevation),
		cos(_cam_elevation) * cos(_cam_azimuth)
	) * _cam_dist
	_camera.global_position = _cam_pivot + offset
	_camera.look_at(_cam_pivot, Vector3.UP)


# ── Demo tops ──────────────────────────────────────────────────────────────────
func _spawn_demo_tops() -> void:
	for top in _tops:
		if is_instance_valid(top):
			top.queue_free()
	_tops.clear()

	var bc := TopScript.blade_count()
	var tc := TopScript.track_count()
	var pc := TopScript.tip_count()

	# Cool hue for left top, warm hue for right top.
	var c1 := Color.from_hsv(randf_range(0.55, 0.72), 0.80, 0.92)
	var c2 := Color.from_hsv(randf_range(0.00, 0.12), 0.85, 0.95)

	var t1 := _make_top(1, c1, randi()%bc, randi()%tc, randi()%pc, Vector3(-3.2, 1.6,  0.5))
	var t2 := _make_top(2, c2, randi()%bc, randi()%tc, randi()%pc, Vector3( 3.2, 1.6, -0.5))
	_tops.append(t1)
	_tops.append(t2)


func _make_top(pid: int, color: Color, blade: int, track: int, tip: int,
		pos: Vector3) -> RigidBody3D:
	var top := RigidBody3D.new()
	top.set_script(TopScript)
	top.set("player_id",     pid)
	top.set("top_color",     color)
	top.set("blade_type",    blade)
	top.set("track_type",    track)
	top.set("tip_type",      tip)
	top.set("bot_controlled", true)
	top.position = pos
	add_child(top)
	top.start_spinning()
	return top


func _update_bots(delta: float) -> void:
	_bot_timer -= delta
	if _bot_timer > 0.0 or _tops.size() < 2:
		return
	_bot_timer = 0.09

	for i in range(_tops.size()):
		var me    : RigidBody3D = _tops[i]
		var other : RigidBody3D = _tops[1 - i]
		if not me.is_alive or not other.is_alive:
			continue

		var to_other := other.global_position - me.global_position
		var dist     := to_other.length()
		var dir      := Vector2(to_other.x, to_other.z).normalized()

		# Steer back to centre near the rim.
		var rim_offset := Vector2(-me.global_position.x, -me.global_position.z)
		if rim_offset.length() > 4.5:
			dir = dir.lerp(rim_offset.normalized(), 0.55).normalized()

		me.set("_bot_move_dir", dir)

		# Boost when charging in or when spin is low.
		var cd:       float = me.get("_boost_cooldown")
		var spin:     float = me.get("current_spin")
		var max_spin: float = me.get("initial_spin")
		if cd <= 0.0 and (dist < 4.0 or spin < max_spin * 0.55):
			me.set("_bot_boost_request", true)


func _tick_respawn(delta: float) -> void:
	# If any top has died, count down then respawn both with fresh random parts.
	for top in _tops:
		if not top.is_alive and _respawn_timer < 0.0:
			_respawn_timer = 2.2

	if _respawn_timer >= 0.0:
		_respawn_timer -= delta
		if _respawn_timer < 0.0:
			_spawn_demo_tops()


# ── Environment ────────────────────────────────────────────────────────────────
func _pick_random_sky() -> Texture2D:
	var dir := DirAccess.open("res://assets/")
	if not dir:
		return null
	var files: Array[String] = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir():
			var low := f.to_lower()
			if low.ends_with(".exr") or low.ends_with(".hdr"):
				files.append("res://assets/" + f)
		f = dir.get_next()
	dir.list_dir_end()
	if files.is_empty():
		return null
	files.shuffle()
	return load(files[0]) as Texture2D


func _setup_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.light_energy     = 1.4
	sun.shadow_enabled   = true
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, -150.0, 0.0)
	fill.light_energy     = 0.35
	fill.light_color      = Color(0.435, 0.037, 0.086)
	add_child(fill)

	var env_node := WorldEnvironment.new()
	var env      := Environment.new()

	var sky_tex := _pick_random_sky()
	if sky_tex:
		var sky_mat          := PanoramaSkyMaterial.new()
		sky_mat.panorama     = sky_tex
		var sky              := Sky.new()
		sky.sky_material     = sky_mat
		env.background_mode  = Environment.BG_SKY
		env.sky              = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 0.5
	else:
		env.background_mode      = Environment.BG_COLOR
		env.background_color     = Color(0.05, 0.03, 0.10)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color  = Color(0.22, 0.16, 0.34)
		env.ambient_light_energy = 0.6

	env.glow_enabled     = true
	env.glow_intensity   = 0.7
	env.glow_bloom       = 0.18
	env_node.environment = env
	add_child(env_node)


# ── Arena ──────────────────────────────────────────────────────────────────────
func _setup_arena() -> void:
	# Visual bowl
	var bowl_mesh := _create_bowl_mesh(ARENA_RADIUS, BOWL_SPHERE_R, 48, 20)
	var bowl_mat  := StandardMaterial3D.new()
	bowl_mat.albedo_color             = Color(0.08, 0.10, 0.07)
	bowl_mat.emission_enabled         = true
	bowl_mat.emission                 = Color(0.06, 0.14, 0.05)
	bowl_mat.emission_energy_multiplier = 0.8
	bowl_mat.roughness                = 0.85
	bowl_mat.metallic                 = 0.10
	bowl_mesh.surface_set_material(0, bowl_mat)
	var bowl_inst := MeshInstance3D.new()
	bowl_inst.mesh = bowl_mesh
	add_child(bowl_inst)

	# Physics bowl
	var bowl_body  := StaticBody3D.new()
	var bowl_col   := CollisionShape3D.new()
	var bowl_shape := ConcavePolygonShape3D.new()
	bowl_shape.backface_collision = true
	bowl_shape.set_faces(_create_bowl_faces(ARENA_RADIUS, BOWL_SPHERE_R, 64, 28))
	bowl_col.shape = bowl_shape
	bowl_body.add_child(bowl_col)
	var bowl_phys := PhysicsMaterial.new()
	bowl_phys.friction = 0.55
	bowl_phys.bounce   = 0.03
	bowl_body.physics_material_override = bowl_phys
	add_child(bowl_body)

	# Safety floor
	var floor_body  := StaticBody3D.new()
	var floor_col   := CollisionShape3D.new()
	var floor_shape := CylinderShape3D.new()
	floor_shape.radius = ARENA_RADIUS * 0.5
	floor_shape.height = 0.1
	floor_col.shape    = floor_shape
	floor_body.position.y = -0.05
	floor_body.add_child(floor_col)
	add_child(floor_body)

	# Rim glow ring
	var rim_y := BOWL_SPHERE_R - sqrt(BOWL_SPHERE_R * BOWL_SPHERE_R - ARENA_RADIUS * ARENA_RADIUS)
	var torus_inst := MeshInstance3D.new()
	var torus_mesh := TorusMesh.new()
	torus_mesh.inner_radius  = ARENA_RADIUS - 0.1
	torus_mesh.outer_radius  = ARENA_RADIUS + 0.1
	torus_mesh.rings         = 64
	torus_mesh.ring_segments = 10
	var torus_mat := StandardMaterial3D.new()
	torus_mat.albedo_color               = Color(0.008, 0.008, 0.009)
	torus_mat.emission_enabled           = true
	torus_mat.emission                   = Color(0.30, 0.30, 0.30)
	torus_mat.emission_energy_multiplier = 3.0
	torus_mat.metallic                   = 0.7
	torus_mat.roughness                  = 0.15
	torus_mesh.material  = torus_mat
	torus_inst.mesh      = torus_mesh
	torus_inst.position.y = rim_y
	add_child(torus_inst)

	var ring_light := OmniLight3D.new()
	ring_light.light_energy = 1.0
	ring_light.light_color  = Color(0.5, 0.3, 1.0)
	ring_light.omni_range   = 16.0
	ring_light.position     = Vector3(0.0, rim_y, 0.0)
	add_child(ring_light)


# ── Bowl mesh helpers (identical to game_manager) ──────────────────────────────
func _create_bowl_mesh(arena_r: float, sphere_r: float, segs: int, rings: int) -> ArrayMesh:
	var verts   := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs     := PackedVector2Array()
	var indices := PackedInt32Array()
	for ring in range(rings + 1):
		var t   := float(ring) / rings
		var r   := t * arena_r
		var y   := sphere_r - sqrt(sphere_r * sphere_r - r * r)
		for seg in range(segs + 1):
			var angle := float(seg) / segs * TAU
			var x := cos(angle) * r
			var z := sin(angle) * r
			verts.append(Vector3(x, y, z))
			normals.append(-Vector3(x, y - sphere_r, z).normalized())
			uvs.append(Vector2(float(seg) / segs, t))
	for ring in range(rings):
		for seg in range(segs):
			var a := ring * (segs + 1) + seg
			var b := a + 1
			var c := a + segs + 1
			var d := c + 1
			indices.append(a); indices.append(c); indices.append(b)
			indices.append(b); indices.append(c); indices.append(d)
	var arr := Array(); arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX]  = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


func _create_bowl_faces(arena_r: float, sphere_r: float, segs: int, rings: int) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for ring in range(rings):
		var t0 := float(ring)      / rings
		var t1 := float(ring + 1) / rings
		var r0 := t0 * arena_r;  var r1 := t1 * arena_r
		var y0 := sphere_r - sqrt(sphere_r * sphere_r - r0 * r0)
		var y1 := sphere_r - sqrt(sphere_r * sphere_r - r1 * r1)
		for seg in range(segs):
			var a0 := float(seg)      / segs * TAU
			var a1 := float(seg + 1) / segs * TAU
			var v00 := Vector3(cos(a0)*r0, y0, sin(a0)*r0)
			var v10 := Vector3(cos(a1)*r0, y0, sin(a1)*r0)
			var v01 := Vector3(cos(a0)*r1, y1, sin(a0)*r1)
			var v11 := Vector3(cos(a1)*r1, y1, sin(a1)*r1)
			faces.append(v00); faces.append(v01); faces.append(v10)
			faces.append(v10); faces.append(v01); faces.append(v11)
	return faces
