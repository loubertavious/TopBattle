extends Node3D

const TopScript = preload("res://scripts/top.gd")

const ARENA_RADIUS := 6.5
const BOWL_SPHERE_RADIUS := 19.0  # larger = shallower bowl
const ROUNDS_TO_WIN := 3

# Part-selection step indices (sequential Blade → Track → Tip → Color).
const STEP_PROFILE := 0   # choose a save-slot; confirming auto-loads its settings
const STEP_BLADE   := 1
const STEP_TRACK   := 2
const STEP_TIP     := 3
const STEP_COLOR   := 4   # confirming auto-saves to the chosen slot
const STEP_DONE    := 5

var _tops: Array[RigidBody3D] = []
var _hud: CanvasLayer
var _camera: Camera3D
var _scores := {1: 0, 2: 0}
var _round_active := false
var _countdown_timer := 0.0
var _restart_timer := 0.0
var _state := "selecting"  # selecting | countdown | fighting | result

# Camera — orbit / zoom / pan
const CAM_DIST_MIN    := 3.0
const CAM_DIST_MAX    := 55.0
const CAM_ZOOM_STEP   := 1.5    # metres per scroll tick
const CAM_ORBIT_SPEED := 0.006  # radians per pixel (RMB drag)
const CAM_PAN_SPEED   := 0.007  # pivot world units per pixel (MMB drag, scales with dist)

var _cam_dist:      float   = 23.5
var _cam_azimuth:   float   = 0.0    # horizontal orbit angle (radians)
var _cam_elevation: float   = 0.95   # vertical orbit angle  (radians, ~54° above horizon)
var _cam_pivot:     Vector3 = Vector3.ZERO  # point being orbited
var _rmb_down: bool = false
var _mmb_down: bool = false

# Dynamic camera
var _dynamic_cam:   bool  = true
var _dyn_msg_timer: float = 0.0    # seconds until the "Dynamic Cam ON/OFF" toast clears

# Part selection state — each player selects Blade → Track → Tip sequentially.
# _pX_step: 0 = choosing blade, 1 = choosing track, 2 = choosing tip, 3 = done.
var _p1_profile: int = 0; var _p1_blade: int = 0; var _p1_track: int = 0
var _p1_tip: int = 0;    var _p1_color_idx: int = 7; var _p1_step: int = 0   # 7 = Blue
var _p2_profile: int = 0; var _p2_blade: int = 0; var _p2_track: int = 0
var _p2_tip: int = 0;    var _p2_color_idx: int = 0; var _p2_step: int = 0   # 0 = Red

# True when the just-finished result was a full match win (not a mid-match round).
# Controls whether the restart timer leads to part selection or the next round.
var _match_over: bool = false

# Bot
var _vs_bot:          bool  = false
var _bot_think_timer: float = 0.0


func _ready() -> void:
	_vs_bot = GameSettings.vs_bot
	_setup_environment()
	_setup_arena()
	_setup_camera()
	_setup_hud()
	_start_selecting()


func _process(delta: float) -> void:
	_update_camera(delta)
	match _state:
		"selecting":
			_handle_shape_input()
		"countdown":
			_countdown_timer -= delta
			if _countdown_timer > 0.0:
				_hud.show_message("Fight in %d…" % ceili(_countdown_timer))
			else:
				_hud.hide_message()
				_begin_round()
		"fighting":
			_update_boost_bars()
			if _vs_bot:
				_update_bot(delta)
			# Clear the dynamic-cam toast once its timer expires.
			if _dyn_msg_timer > 0.0:
				_dyn_msg_timer -= delta
				if _dyn_msg_timer <= 0.0:
					_hud.hide_message()
		"result":
			_restart_timer -= delta
			if _restart_timer <= 0.0:
				if _match_over:
					_start_selecting()   # full match ended — go back to part picker
				else:
					_start_next_round()  # mid-match — reuse parts, skip picker


func _handle_shape_input() -> void:
	var changed := false

	if _vs_bot:
		# ── VS Bot: P1 configures their top first, then the bot's top ─────────
		if _p1_step < STEP_DONE:
			changed = _advance_selection(1, _p1_step, changed)
		elif _p2_step < STEP_DONE:
			# P1's inputs now drive the bot column.
			changed = _advance_selection(2, _p2_step, changed)
	else:
		# ── 2-Player: both configure simultaneously ────────────────────────────
		if _p1_step < STEP_DONE:
			changed = _advance_selection(1, _p1_step, changed)
		if _p2_step < STEP_DONE:
			changed = _advance_selection(2, _p2_step, changed)

	if changed:
		_hud.update_part_select(
			_p1_profile, _p1_blade, _p1_track, _p1_tip, _p1_color_idx, _p1_step,
			_p2_profile, _p2_blade, _p2_track, _p2_tip, _p2_color_idx, _p2_step)

	if _p1_step >= STEP_DONE and _p2_step >= STEP_DONE:
		_hud.hide_shape_select()
		_start_countdown()


# Handles one player's selection step.
# In VS Bot, pid=2 is driven by P1's inputs after P1 finishes.
func _advance_selection(pid: int, step: int, changed: bool) -> bool:
	# Input source: always P1 keys in bot mode when driving bot column.
	var src := pid if not (_vs_bot and pid == 2) else 1
	var left  := Input.is_action_just_pressed("p%d_left"  % src)
	var right := Input.is_action_just_pressed("p%d_right" % src)
	var boost := Input.is_action_just_pressed("p%d_boost" % src)

	if left or right:
		var dir := -1 if left else 1
		match step:
			STEP_PROFILE:
				if pid == 1: _p1_profile   = (_p1_profile   + dir + GameSettings.PROFILE_SLOTS) % GameSettings.PROFILE_SLOTS
				else:        _p2_profile   = (_p2_profile   + dir + GameSettings.PROFILE_SLOTS) % GameSettings.PROFILE_SLOTS
			STEP_BLADE:
				if pid == 1: _p1_blade     = (_p1_blade     + dir + TopScript.blade_count())    % TopScript.blade_count()
				else:        _p2_blade     = (_p2_blade     + dir + TopScript.blade_count())    % TopScript.blade_count()
			STEP_TRACK:
				if pid == 1: _p1_track     = (_p1_track     + dir + TopScript.track_count())    % TopScript.track_count()
				else:        _p2_track     = (_p2_track     + dir + TopScript.track_count())    % TopScript.track_count()
			STEP_TIP:
				if pid == 1: _p1_tip       = (_p1_tip       + dir + TopScript.tip_count())      % TopScript.tip_count()
				else:        _p2_tip       = (_p2_tip       + dir + TopScript.tip_count())      % TopScript.tip_count()
			STEP_COLOR:
				if pid == 1: _p1_color_idx = (_p1_color_idx + dir + GameSettings.color_count()) % GameSettings.color_count()
				else:        _p2_color_idx = (_p2_color_idx + dir + GameSettings.color_count()) % GameSettings.color_count()
		changed = true

	if boost:
		var profile   := _p1_profile   if pid == 1 else _p2_profile
		var color_idx := _p1_color_idx if pid == 1 else _p2_color_idx
		var blade     := _p1_blade     if pid == 1 else _p2_blade
		var track     := _p1_track     if pid == 1 else _p2_track
		var tip       := _p1_tip       if pid == 1 else _p2_tip

		if step == STEP_PROFILE:
			var prof := GameSettings.load_profile(pid, profile)
			if prof.size() > 0:
				if pid == 1:
					_p1_blade = prof.blade; _p1_track = prof.track
					_p1_tip   = prof.tip;   _p1_color_idx = prof.color_idx
				else:
					_p2_blade = prof.blade; _p2_track = prof.track
					_p2_tip   = prof.tip;   _p2_color_idx = prof.color_idx
		elif step == STEP_COLOR:
			GameSettings.save_profile(pid, profile, blade, track, tip, color_idx)

		if pid == 1:
			_p1_step += 1
			# In bot mode, switching to bot-config phase after P1 is done.
			if _vs_bot and _p1_step == STEP_DONE:
				_hud.set_panel_title("— BUILD THE BOT'S TOP —")
		else:
			_p2_step += 1
		changed = true

	return changed


# ── Setup helpers ──────────────────────────────────────────────────────────────

# Returns a randomly chosen sky texture from res://assets/, or null if none found.
# Supports .exr and .hdr — just drop files in the folder, no code changes needed.
# Returns a randomly chosen floor texture from res://assets/floors/, or null.
# Supports .png .jpg .jpeg .webp — drop files in the folder, no code changes needed.
func _pick_random_floor() -> Texture2D:
	var dir := DirAccess.open("res://assets/floors/")
	if not dir:
		return null
	var files: Array[String] = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir():
			var low := f.to_lower()
			if low.ends_with(".png") or low.ends_with(".jpg") \
					or low.ends_with(".jpeg") or low.ends_with(".webp") \
					or low.ends_with(".exr"):
				files.append("res://assets/floors/" + f)
		f = dir.get_next()
	dir.list_dir_end()
	if files.is_empty():
		return null
	files.shuffle()
	return load(files[0]) as Texture2D


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
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, -150.0, 0.0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.435, 0.037, 0.086, 1.0)
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
		# Fallback if texture hasn't been imported yet
		env.background_mode       = Environment.BG_COLOR
		env.background_color      = Color(0.03, 0.02, 0.10)
		env.ambient_light_source  = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color   = Color(0.06, 0.03, 0.18)
		env.ambient_light_energy  = 0.6

	env.glow_enabled   = true
	env.glow_intensity = 0.6
	env.glow_bloom     = 0.15
	env_node.environment = env
	add_child(env_node)
	GameSettings.world_env = env_node   # expose for dev console


func _setup_arena() -> void:
	# ── Swap this call to change stadiums ─────────────────────────────────────
	_build_stadium_classic()


# ── Classic Bowl stadium ───────────────────────────────────────────────────────
# Spherical-section bowl.  Physics collision is a high-res ConcavePolygonShape3D
# so gravity naturally pulls tops toward the centre — no artificial force needed.
# Using 64 segments × 28 rings keeps triangle edges < 0.7° apart, small enough
# that the tops' rounded SphereMesh tip never snags on an edge.
func _build_stadium_classic() -> void:
	# Visual bowl
	var bowl_mesh := _create_bowl_mesh(ARENA_RADIUS, BOWL_SPHERE_RADIUS, 48, 20)
	# Grid shader — lines are computed from world-space XZ so they stay straight
	# across the curved bowl surface.  A varying carries world position from
	# vertex() to fragment() since fragment() has no direct world-pos builtin.
	var bowl_shader := Shader.new()
	bowl_shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4      base_color    : source_color = vec4(0.45, 0.03, 0.04, 1.0);
uniform sampler2D floor_texture : source_color, hint_default_white;
uniform bool      has_texture   = false;
uniform float     texture_scale : hint_range(0.1, 8.0, 0.1) = 2.0;
uniform float     texture_blend : hint_range(0.0, 1.0, 0.05) = 0.6;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = base_color.rgb;
	if (has_texture) {
		vec3 tex_col = texture(floor_texture, world_pos.xz / texture_scale * 0.5 + 0.5).rgb;
		col = mix(col, tex_col, texture_blend);
	}
	ALBEDO    = col;
	ROUGHNESS = 0.82;
	METALLIC  = 0.12;
}
"""
	var bowl_mat := ShaderMaterial.new()
	bowl_mat.shader = bowl_shader
	bowl_mat.set_shader_parameter("arena_radius", ARENA_RADIUS)

	var floor_tex := _pick_random_floor()
	if floor_tex:
		bowl_mat.set_shader_parameter("floor_texture", floor_tex)
		bowl_mat.set_shader_parameter("has_texture", true)

	bowl_mesh.surface_set_material(0, bowl_mat)
	GameSettings.bowl_mat = bowl_mat   # expose for dev console
	var bowl_inst := MeshInstance3D.new()
	bowl_inst.mesh = bowl_mesh
	add_child(bowl_inst)

	# Physics bowl — higher resolution than the visual mesh to minimise ghost collisions.
	# backface_collision = true makes both sides of every triangle solid, so the winding
	# order of the generated faces doesn't matter and tops can't fall through.
	var bowl_body := StaticBody3D.new()
	bowl_body.name = "BowlCollision"
	var bowl_col := CollisionShape3D.new()
	var bowl_shape := ConcavePolygonShape3D.new()
	bowl_shape.backface_collision = true
	bowl_shape.set_faces(_create_bowl_faces(ARENA_RADIUS, BOWL_SPHERE_RADIUS, 64, 28))
	bowl_col.shape = bowl_shape
	bowl_body.add_child(bowl_col)
	var bowl_phys := PhysicsMaterial.new()
	bowl_phys.friction = 0.55
	bowl_phys.bounce   = 0.03
	bowl_body.physics_material_override = bowl_phys
	add_child(bowl_body)

	# Flat floor at bowl centre — guaranteed solid surface under the spawn points.
	# Acts as a safety net if any triangle edge is missed by the concave shape.
	var floor_body := StaticBody3D.new()
	floor_body.name = "ArenaFloor"
	var floor_col := CollisionShape3D.new()
	var floor_shape := CylinderShape3D.new()
	floor_shape.radius = ARENA_RADIUS * 0.5   # covers only the flat centre zone
	floor_shape.height = 0.1
	floor_col.shape = floor_shape
	floor_body.add_child(floor_col)
	floor_body.position.y = -0.05
	add_child(floor_body)

	# Segmented knockout rim — 4 wall panels with 4 open gaps between them.
	# Tops knocked hard enough fly through a gap and fall below y = -1 → KO.
	var rim_y := BOWL_SPHERE_RADIUS - sqrt(BOWL_SPHERE_RADIUS * BOWL_SPHERE_RADIUS - ARENA_RADIUS * ARENA_RADIUS)
	_build_segmented_rim(rim_y)


func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = 58.0
	add_child(_camera)
	_update_camera(0.0)   # place immediately so first frame is correct


# Builds a bowl mesh — the inner surface of a sphere section.
# center is y=0, rim rises to BOWL_SPHERE_RADIUS - sqrt(R²-ARENA_RADIUS²).
func _create_bowl_mesh(arena_r: float, sphere_r: float, segs: int, rings: int) -> ArrayMesh:
	var verts   := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs     := PackedVector2Array()
	var indices := PackedInt32Array()

	for ring in range(rings + 1):
		var t   := float(ring) / rings
		var r   := t * arena_r
		# y on a sphere of radius sphere_r centred at (0, sphere_r, 0)
		var y   := sphere_r - sqrt(sphere_r * sphere_r - r * r)

		for seg in range(segs + 1):
			var angle := float(seg) / segs * TAU
			var x     := cos(angle) * r
			var z     := sin(angle) * r
			verts.append(Vector3(x, y, z))
			# inward-facing normal (toward bowl centre above)
			var n := Vector3(x, y - sphere_r, z).normalized()
			normals.append(-n)
			uvs.append(Vector2(float(seg) / segs, t))

	for ring in range(rings):
		for seg in range(segs):
			var a := ring * (segs + 1) + seg
			var b := a + 1
			var c := a + segs + 1
			var d := c + 1
			indices.append(a); indices.append(c); indices.append(b)
			indices.append(b); indices.append(c); indices.append(d)

	var arr := Array()
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX]  = verts
	arr[Mesh.ARRAY_NORMAL]  = normals
	arr[Mesh.ARRAY_TEX_UV]  = uvs
	arr[Mesh.ARRAY_INDEX]   = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


# Returns a PackedVector3Array of raw triangle faces for ConcavePolygonShape3D.
# Each set of three consecutive vertices is one triangle.
func _create_bowl_faces(arena_r: float, sphere_r: float, segs: int, rings: int) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for ring in range(rings):
		var t0 := float(ring)       / rings
		var t1 := float(ring + 1)  / rings
		var r0 := t0 * arena_r
		var r1 := t1 * arena_r
		var y0 := sphere_r - sqrt(sphere_r * sphere_r - r0 * r0)
		var y1 := sphere_r - sqrt(sphere_r * sphere_r - r1 * r1)
		for seg in range(segs):
			var a0 := float(seg)      / segs * TAU
			var a1 := float(seg + 1) / segs * TAU
			var v00 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var v10 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var v01 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var v11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			# Triangle 1
			faces.append(v00); faces.append(v01); faces.append(v10)
			# Triangle 2
			faces.append(v10); faces.append(v01); faces.append(v11)
	return faces


func _input(event: InputEvent) -> void:
	# Tab / gamepad Start → toggle dynamic camera (works any time).
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_TAB:
			_toggle_dynamic_cam()
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == 6:   # Start / Menu on any pad
			_toggle_dynamic_cam()
		elif event.button_index == 11 and _state == "fighting":  # D-pad up — fighting only
			_toggle_dynamic_cam()                                 # (outside fighting it moves tops)

	# Manual camera controls are suppressed while dynamic cam is active.
	if _dynamic_cam:
		return

	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_cam_dist = clampf(_cam_dist - CAM_ZOOM_STEP, CAM_DIST_MIN, CAM_DIST_MAX)
			MOUSE_BUTTON_WHEEL_DOWN:
				_cam_dist = clampf(_cam_dist + CAM_ZOOM_STEP, CAM_DIST_MIN, CAM_DIST_MAX)
			MOUSE_BUTTON_RIGHT:
				_rmb_down = event.pressed
			MOUSE_BUTTON_MIDDLE:
				_mmb_down = event.pressed

	if event is InputEventMouseMotion:
		if _rmb_down:
			# Orbit — horizontal drag rotates azimuth, vertical drag changes elevation.
			# Elevation is clamped so we never flip past straight-up or straight-down.
			_cam_azimuth   -= event.relative.x * CAM_ORBIT_SPEED
			_cam_elevation -= event.relative.y * CAM_ORBIT_SPEED
			_cam_elevation  = clampf(_cam_elevation, -1.50, 1.50)  # ±~86°

		elif _mmb_down:
			# Pan — slide the pivot point in the camera's local XZ plane.
			var right := Vector3(cos(_cam_azimuth), 0.0, -sin(_cam_azimuth))
			var fwd   := Vector3(sin(_cam_azimuth), 0.0,  cos(_cam_azimuth))
			var speed := _cam_dist * CAM_PAN_SPEED
			_cam_pivot -= right * event.relative.x * speed
			_cam_pivot -= fwd   * event.relative.y * speed


func _toggle_dynamic_cam() -> void:
	_dynamic_cam   = not _dynamic_cam
	_dyn_msg_timer = 1.8
	_hud.show_message("Dynamic Camera  %s" % ("ON" if _dynamic_cam else "OFF"))


func _update_camera(delta: float) -> void:
	if not is_instance_valid(_camera):
		return
	if _dynamic_cam:
		_update_dynamic_camera(delta)
		return
	# Manual mode — convert spherical coordinates to a world-space camera position.
	var offset := Vector3(
		cos(_cam_elevation) * sin(_cam_azimuth),
		sin(_cam_elevation),
		cos(_cam_elevation) * cos(_cam_azimuth)
	) * _cam_dist
	_camera.global_position = _cam_pivot + offset
	# look_at needs a non-degenerate up vector; when nearly vertical use forward as hint.
	var up := Vector3.UP if abs(_cam_elevation) < 1.50 \
		else Vector3(sin(_cam_azimuth + 0.01), 0.0, cos(_cam_azimuth + 0.01))
	_camera.look_at(_cam_pivot, up)


# ── Dynamic camera ─────────────────────────────────────────────────────────────
# Orbits the arena slowly, pivoting on the midpoint between the two tops.
# As the tops close in on each other the camera lowers and zooms in for drama;
# when they are far apart it pulls back and rises to keep both in frame.
func _update_dynamic_camera(delta: float) -> void:
	const SMOOTH      : float = 1.2    # exponential smoothing rate (higher = snappier)
	const DIST_CLOSE  : float = 5.0    # distance when tops are nearly touching
	const DIST_FAR    : float = 16.0   # distance when tops are at opposite ends
	const ELEV_CLOSE  : float = 0.50   # elevation (rad) when close — low, cinematic
	const ELEV_FAR    : float = 1.05   # elevation (rad) when far  — overhead overview

	# Collect positions of alive tops.
	var positions: Array[Vector3] = []
	for top in _tops:
		if top.is_alive:
			positions.append(top.global_position)

	# Target pivot: midpoint between the tops, snapped to arena-floor height.
	var target_pivot := Vector3.ZERO
	var separation   := ARENA_RADIUS * 2.0   # default: treat as far apart

	match positions.size():
		2:
			target_pivot = Vector3(
				(positions[0].x + positions[1].x) * 0.5,
				0.0,
				(positions[0].z + positions[1].z) * 0.5)
			separation = positions[0].distance_to(positions[1])
		1:
			target_pivot = Vector3(positions[0].x, 0.0, positions[0].z)

	# t = 0 when tops are touching, t = 1 when they are as far apart as the arena.
	var t := clampf(separation / (ARENA_RADIUS * 2.0), 0.0, 1.0)

	var target_dist : float = DIST_CLOSE + (DIST_FAR  - DIST_CLOSE) * t
	var target_elev : float = ELEV_CLOSE + (ELEV_FAR  - ELEV_CLOSE) * t

	# Exponential smooth — frame-rate independent, no lerp() Variant ambiguity.
	var k := 1.0 - exp(-SMOOTH * delta)
	_cam_pivot.x   += (target_pivot.x - _cam_pivot.x)   * k
	_cam_pivot.y   += (target_pivot.y - _cam_pivot.y)   * k
	_cam_pivot.z   += (target_pivot.z - _cam_pivot.z)   * k
	_cam_dist      += (target_dist    - _cam_dist)      * k
	_cam_elevation += (target_elev    - _cam_elevation) * k

	# Azimuth is fixed — no auto-orbit so the view stays oriented.

	# Apply spherical position.
	var offset := Vector3(
		cos(_cam_elevation) * sin(_cam_azimuth),
		sin(_cam_elevation),
		cos(_cam_elevation) * cos(_cam_azimuth)
	) * _cam_dist
	_camera.global_position = _cam_pivot + offset
	_camera.look_at(_cam_pivot, Vector3.UP)


func _setup_hud() -> void:
	var hud_scene := preload("res://scripts/hud.gd")
	_hud = CanvasLayer.new()
	_hud.set_script(hud_scene)
	add_child(_hud)


# ── Round flow ─────────────────────────────────────────────────────────────────

func _start_selecting() -> void:
	_state = "selecting"
	_p1_profile = 0; _p1_blade = 0; _p1_track = 0; _p1_tip = 0; _p1_color_idx = 7; _p1_step = 0
	_p2_profile = 0; _p2_blade = 0; _p2_track = 0; _p2_tip = 0; _p2_color_idx = 0; _p2_step = 0
	for top in _tops:
		top.queue_free()
	_tops.clear()
	_hud.update_scores(_scores[1], _scores[2])
	_hud.set_panel_title("— BUILD YOUR TOP —")
	_hud.setup_mode(_vs_bot)
	_hud.show_part_select(
		_p1_profile, _p1_blade, _p1_track, _p1_tip, _p1_color_idx, _p1_step,
		_p2_profile, _p2_blade, _p2_track, _p2_tip, _p2_color_idx, _p2_step)


func _start_countdown() -> void:
	_state = "countdown"
	_countdown_timer = 3.0
	_spawn_tops()
	_hud.update_scores(_scores[1], _scores[2])
	_hud.update_player_colors(
		GameSettings.get_color(_p1_color_idx),
		GameSettings.get_color(_p2_color_idx))
	_hud.show_message("Fight in 3…")


func _begin_round() -> void:
	_state = "fighting"
	_round_active = true
	for top in _tops:
		# Unfreeze first so the physics body is active, then start spinning.
		top.freeze = false
		top.start_spinning()


func _spawn_tops() -> void:
	for top in _tops:
		top.queue_free()
	_tops.clear()

	var t1 := RigidBody3D.new()
	t1.set_script(TopScript)
	t1.set("player_id", 1)
	t1.set("top_color", GameSettings.get_color(_p1_color_idx))
	t1.set("blade_type", _p1_blade)
	t1.set("track_type", _p1_track)
	t1.set("tip_type",   _p1_tip)
	# Spawn at floor level so there's no fall.  freeze = true keeps the top
	# completely motionless (no gravity, no rotation) until the round begins.
	t1.position = Vector3(-3.5, 1.60, 0.0)
	t1.freeze = true
	t1.connect("top_died", _on_top_died)
	add_child(t1)
	_tops.append(t1)

	var t2 := RigidBody3D.new()
	t2.set_script(TopScript)
	t2.set("player_id", 2)
	t2.set("top_color",      GameSettings.get_color(_p2_color_idx))
	t2.set("blade_type",     _p2_blade)
	t2.set("track_type",     _p2_track)
	t2.set("tip_type",       _p2_tip)
	t2.set("bot_controlled", _vs_bot)
	t2.position = Vector3(3.5, 1.6, 0.0)
	t2.freeze = true
	t2.connect("top_died", _on_top_died)
	add_child(t2)
	_tops.append(t2)


# ── Bot AI ─────────────────────────────────────────────────────────────────────
func _update_bot(delta: float) -> void:
	if _tops.size() < 2:
		return

	var bot_top:   RigidBody3D = null
	var human_top: RigidBody3D = null
	for top in _tops:
		if top.get("bot_controlled"):
			bot_top   = top
		else:
			human_top = top

	if not bot_top or not human_top:
		return
	if not bot_top.is_alive or not human_top.is_alive:
		return

	# Throttle decisions to 12 Hz so the bot feels like a player, not a robot.
	_bot_think_timer -= delta
	if _bot_think_timer > 0.0:
		return
	_bot_think_timer = 0.083

	var bot_pos   : Vector3 = bot_top.global_position
	var human_pos : Vector3 = human_top.global_position
	var to_human  : Vector3 = human_pos - bot_pos
	var dist      : float   = to_human.length()

	# Primary direction: charge the opponent.
	var move_dir := Vector2(to_human.x, to_human.z).normalized()

	# Secondary: pull back toward centre when close to the rim (avoids self-KO).
	var to_center   := Vector2(-bot_pos.x, -bot_pos.z)
	var rim_dist    := to_center.length()
	if rim_dist > 4.5:
		move_dir = move_dir.lerp(to_center.normalized(), 0.55).normalized()

	bot_top.set("_bot_move_dir", move_dir)

	# Boost when charging close, or to recover spin when running low.
	var cd       : float = bot_top.get("_boost_cooldown")
	var spin     : float = bot_top.get("current_spin")
	var max_spin : float = bot_top.get("initial_spin")
	if cd <= 0.0:
		if dist < 3.5 or spin < max_spin * 0.60:
			bot_top.set("_bot_boost_request", true)


func _start_next_round() -> void:
	# Reuse the same parts — skip the selection screen entirely.
	_hud.hide_message()
	_start_countdown()


func _on_top_died(loser_id: int) -> void:
	if not _round_active:
		return
	_round_active = false
	_state = "result"

	var winner := 2 if loser_id == 1 else 1
	_scores[winner] += 1
	_hud.update_scores(_scores[1], _scores[2])

	var color_name := "Blue" if winner == 1 else "Red"
	if _scores[winner] >= ROUNDS_TO_WIN:
		_match_over = true
		_hud.show_message("P%d (%s) WINS THE MATCH!" % [winner, color_name])
		_restart_timer = 3.5
		await get_tree().create_timer(3.5).timeout
		_scores = {1: 0, 2: 0}
		_hud.update_scores(0, 0)
	else:
		_match_over = false
		_hud.show_message("P%d (%s) wins the round!" % [winner, color_name])
		_restart_timer = 2.0


# ── Segmented knockout rim ─────────────────────────────────────────────────────
# Builds NUM_SEGS curved wall panels around the bowl lip, leaving GAP_DEG-wide
# openings between each panel.  Tops exit through the gaps when knocked out.
# Visual: true arc ArrayMesh (ARC_STEPS subdivisions) so the wall follows the
# circle exactly.  Physics: PHY_STEPS BoxShape3D children per StaticBody3D,
# staggered along the arc — max inward error < 3 cm at PHY_STEPS = 5.
func _build_segmented_rim(rim_y: float) -> void:
	const NUM_SEGS  : int   = 4      # solid wall panels (one per quadrant)
	const GAP_DEG   : float = 34.0   # angular gap width in degrees
	const SEG_DEG   : float = 90.0 - GAP_DEG  # solid arc per panel = 56°
	const ARC_STEPS : int   = 10     # visual mesh subdivisions per panel
	const PHY_STEPS : int   = 5      # physics-box count per panel

	var wall_r := ARENA_RADIUS + 0.15
	var wall_h := 0.50
	var wall_d := 0.30
	var wall_y := rim_y + wall_h * 0.5

	# Decorative torus around the bowl lip so the rim boundary is always visible.
	var torus_inst := MeshInstance3D.new()
	var torus_mesh := TorusMesh.new()
	torus_mesh.inner_radius  = ARENA_RADIUS - 0.1
	torus_mesh.outer_radius  = ARENA_RADIUS + 0.1
	torus_mesh.rings         = 64
	torus_mesh.ring_segments = 10
	var torus_mat := StandardMaterial3D.new()
	torus_mat.albedo_color               = Color(0.44, 0.28, 0.29)
	torus_mat.emission_enabled           = true
	torus_mat.emission                   = Color(0.97, 0.62, 0.65)
	torus_mat.emission_energy_multiplier = 3.0
	torus_mat.metallic                   = 0.7
	torus_mat.roughness                  = 0.15
	torus_mesh.material   = torus_mat
	torus_inst.mesh       = torus_mesh
	torus_inst.position.y = rim_y
	add_child(torus_inst)
	GameSettings.rim_mat = torus_mat   # expose for dev console

	# Ambient glow from the rim plane.
	var ring_light := OmniLight3D.new()
	ring_light.light_energy = 1.2
	ring_light.light_color  = Color(0.97, 0.62, 0.65)
	ring_light.omni_range   = 16.0
	ring_light.position     = Vector3(0.0, rim_y, 0.0)
	add_child(ring_light)
	GameSettings.rim_light = ring_light   # expose for dev console

	# Shared material — CULL_DISABLED so both sides of each arc face render
	# without needing to verify per-face winding order.
	var seg_mat := StandardMaterial3D.new()
	seg_mat.albedo_color               = Color(0.20, 0.01, 0.02)
	seg_mat.emission_enabled           = true
	seg_mat.emission                   = Color(0.45, 0.03, 0.04)
	seg_mat.emission_energy_multiplier = 2.2
	seg_mat.metallic                   = 0.80
	seg_mat.roughness                  = 0.18
	seg_mat.cull_mode                  = BaseMaterial3D.CULL_DISABLED
	GameSettings.wall_mat = seg_mat   # expose for dev console

	# Bouncier physics so tops ricochet rather than stick to the wall.
	var seg_phys := PhysicsMaterial.new()
	seg_phys.bounce   = 0.45
	seg_phys.friction = 0.20

	for i in range(NUM_SEGS):
		# Panel i is centred at i*90°; gaps sit at the 45° diagonals.
		var mid_angle := deg_to_rad(i * 90.0)
		var half_seg  := deg_to_rad(SEG_DEG * 0.5)
		var a_start   := mid_angle - half_seg
		var a_end     := mid_angle + half_seg

		# ── Curved visual arc mesh ───────────────────────────────────────────────
		var seg_inst := MeshInstance3D.new()
		seg_inst.mesh = _make_arc_wall_mesh(
			a_start, a_end, wall_r, wall_h, wall_d, wall_y, ARC_STEPS)
		seg_inst.set_surface_override_material(0, seg_mat)
		add_child(seg_inst)

		# ── Physics: StaticBody3D with PHY_STEPS staggered box children ─────────
		var seg_body := StaticBody3D.new()
		seg_body.name                      = "RimSeg%d" % i
		seg_body.physics_material_override = seg_phys

		for j in range(PHY_STEPS):
			# Centre the sub-box at the midpoint of its sub-arc slice.
			var t: float     = (float(j) + 0.5) / float(PHY_STEPS)
			var angle: float = lerp(a_start, a_end, t)
			var sub_arc   := (a_end - a_start) / float(PHY_STEPS)
			# Chord of the sub-arc + 2 % overlap to eliminate seam gaps.
			var sub_chord := 2.0 * wall_r * sin(sub_arc * 0.5) * 1.02

			var radial    := Vector3(cos(angle), 0.0, sin(angle))
			var tangent   := Vector3(-sin(angle), 0.0, cos(angle))
			var sub_basis := Basis(tangent, Vector3.UP, radial)
			var sub_pos   := Vector3(cos(angle) * wall_r, wall_y, sin(angle) * wall_r)

			var sub_col   := CollisionShape3D.new()
			var sub_shape := BoxShape3D.new()
			sub_shape.size    = Vector3(sub_chord, wall_h, wall_d)
			sub_col.shape     = sub_shape
			sub_col.transform = Transform3D(sub_basis, sub_pos)
			seg_body.add_child(sub_col)

		add_child(seg_body)


# Builds a curved arc-wall ArrayMesh spanning angles [a_start, a_end] at radius r.
# Faces: inner (arena-facing), outer, top cap, bottom cap, and two end caps.
#   r_in  = r - d/2  →  inner curved surface (arena side)
#   r_out = r + d/2  →  outer curved surface
func _make_arc_wall_mesh(a_start: float, a_end: float, r: float, h: float,
		d: float, center_y: float, steps: int) -> ArrayMesh:
	var r_in  := r - d * 0.5
	var r_out := r + d * 0.5
	var y_bot := center_y - h * 0.5
	var y_top := center_y + h * 0.5

	var verts   := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var vi      := 0   # running vertex-index counter

	for s in range(steps):
		var a0: float = lerp(a_start, a_end, float(s)     / float(steps))
		var a1: float = lerp(a_start, a_end, float(s + 1) / float(steps))
		var c0  := cos(a0);  var sz0 := sin(a0)
		var c1  := cos(a1);  var sz1 := sin(a1)

		# ── Inner face — normals toward centre ───────────────────────────────
		verts.append(Vector3(c0 * r_in, y_bot, sz0 * r_in))
		verts.append(Vector3(c0 * r_in, y_top, sz0 * r_in))
		verts.append(Vector3(c1 * r_in, y_bot, sz1 * r_in))
		verts.append(Vector3(c1 * r_in, y_top, sz1 * r_in))
		normals.append(Vector3(-c0, 0.0, -sz0).normalized())
		normals.append(Vector3(-c0, 0.0, -sz0).normalized())
		normals.append(Vector3(-c1, 0.0, -sz1).normalized())
		normals.append(Vector3(-c1, 0.0, -sz1).normalized())
		indices.append(vi+0); indices.append(vi+1); indices.append(vi+3)
		indices.append(vi+0); indices.append(vi+3); indices.append(vi+2)
		vi += 4

		# ── Outer face — normals away from centre ────────────────────────────
		verts.append(Vector3(c0 * r_out, y_bot, sz0 * r_out))
		verts.append(Vector3(c0 * r_out, y_top, sz0 * r_out))
		verts.append(Vector3(c1 * r_out, y_bot, sz1 * r_out))
		verts.append(Vector3(c1 * r_out, y_top, sz1 * r_out))
		normals.append(Vector3(c0, 0.0, sz0).normalized())
		normals.append(Vector3(c0, 0.0, sz0).normalized())
		normals.append(Vector3(c1, 0.0, sz1).normalized())
		normals.append(Vector3(c1, 0.0, sz1).normalized())
		indices.append(vi+0); indices.append(vi+3); indices.append(vi+1)
		indices.append(vi+0); indices.append(vi+2); indices.append(vi+3)
		vi += 4

		# ── Top horizontal cap — normals up ──────────────────────────────────
		verts.append(Vector3(c0 * r_in,  y_top, sz0 * r_in))
		verts.append(Vector3(c0 * r_out, y_top, sz0 * r_out))
		verts.append(Vector3(c1 * r_in,  y_top, sz1 * r_in))
		verts.append(Vector3(c1 * r_out, y_top, sz1 * r_out))
		normals.append(Vector3.UP); normals.append(Vector3.UP)
		normals.append(Vector3.UP); normals.append(Vector3.UP)
		indices.append(vi+0); indices.append(vi+1); indices.append(vi+3)
		indices.append(vi+0); indices.append(vi+3); indices.append(vi+2)
		vi += 4

		# ── Bottom horizontal cap — normals down ─────────────────────────────
		verts.append(Vector3(c0 * r_in,  y_bot, sz0 * r_in))
		verts.append(Vector3(c0 * r_out, y_bot, sz0 * r_out))
		verts.append(Vector3(c1 * r_in,  y_bot, sz1 * r_in))
		verts.append(Vector3(c1 * r_out, y_bot, sz1 * r_out))
		normals.append(Vector3.DOWN); normals.append(Vector3.DOWN)
		normals.append(Vector3.DOWN); normals.append(Vector3.DOWN)
		indices.append(vi+0); indices.append(vi+3); indices.append(vi+1)
		indices.append(vi+0); indices.append(vi+2); indices.append(vi+3)
		vi += 4

	# ── End caps — flat faces that close each side of the arc ─────────────────
	# Start cap: outward normal = CW tangent at a_start = (sin, 0, -cos).
	var cs := cos(a_start);  var ss := sin(a_start)
	var n_s := Vector3(ss, 0.0, -cs)
	verts.append(Vector3(cs * r_in,  y_bot, ss * r_in))
	verts.append(Vector3(cs * r_in,  y_top, ss * r_in))
	verts.append(Vector3(cs * r_out, y_bot, ss * r_out))
	verts.append(Vector3(cs * r_out, y_top, ss * r_out))
	normals.append(n_s); normals.append(n_s)
	normals.append(n_s); normals.append(n_s)
	indices.append(vi+0); indices.append(vi+3); indices.append(vi+1)
	indices.append(vi+0); indices.append(vi+2); indices.append(vi+3)
	vi += 4

	# End cap: outward normal = CCW tangent at a_end = (-sin, 0, cos).
	var ce := cos(a_end);  var se := sin(a_end)
	var n_e := Vector3(-se, 0.0, ce)
	verts.append(Vector3(ce * r_in,  y_bot, se * r_in))
	verts.append(Vector3(ce * r_in,  y_top, se * r_in))
	verts.append(Vector3(ce * r_out, y_bot, se * r_out))
	verts.append(Vector3(ce * r_out, y_top, se * r_out))
	normals.append(n_e); normals.append(n_e)
	normals.append(n_e); normals.append(n_e)
	indices.append(vi+0); indices.append(vi+1); indices.append(vi+3)
	indices.append(vi+0); indices.append(vi+3); indices.append(vi+2)
	vi += 4

	var arr := Array()
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX]  = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


func _update_boost_bars() -> void:
	var p1_frac := 1.0
	var p2_frac := 1.0
	for top in _tops:
		if not top.is_alive:
			continue
		var cd: float       = top.get("_boost_cooldown")
		var track_idx: int  = top.get("track_type")
		var cd_max: float   = TopScript.get_tracks()[track_idx].boost_cooldown
		var frac := 1.0 - clampf(cd / cd_max, 0.0, 1.0)
		if top.get("player_id") == 1:
			p1_frac = frac
		else:
			p2_frac = frac
	_hud.update_boost_bars(p1_frac, p2_frac)
