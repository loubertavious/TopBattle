extends Node3D

const TopScript = preload("res://scripts/top.gd")

const ARENA_RADIUS := 6.5
const BOWL_SPHERE_RADIUS := 13.0  # larger = shallower bowl
const ROUNDS_TO_WIN := 3

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
var _dynamic_cam:   bool  = false
var _dyn_msg_timer: float = 0.0    # seconds until the "Dynamic Cam ON/OFF" toast clears

# Shape selection state
var NUM_SHAPES: int  # set from TopScript.type_count() in _ready()
var _p1_shape: int = 0
var _p2_shape: int = 0
var _p1_confirmed: bool = false
var _p2_confirmed: bool = false


func _ready() -> void:
	NUM_SHAPES = TopScript.type_count()
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
			# Clear the dynamic-cam toast once its timer expires.
			if _dyn_msg_timer > 0.0:
				_dyn_msg_timer -= delta
				if _dyn_msg_timer <= 0.0:
					_hud.hide_message()
		"result":
			_restart_timer -= delta
			if _restart_timer <= 0.0:
				_start_selecting()


func _handle_shape_input() -> void:
	if not _p1_confirmed:
		if Input.is_action_just_pressed("p1_left"):
			_p1_shape = (_p1_shape - 1 + NUM_SHAPES) % NUM_SHAPES
			_hud.update_shape_select(_p1_shape, _p2_shape, false, false)
		elif Input.is_action_just_pressed("p1_right"):
			_p1_shape = (_p1_shape + 1) % NUM_SHAPES
			_hud.update_shape_select(_p1_shape, _p2_shape, false, false)
		elif Input.is_action_just_pressed("p1_boost"):
			_p1_confirmed = true
			_hud.update_shape_select(_p1_shape, _p2_shape, true, _p2_confirmed)

	if not _p2_confirmed:
		if Input.is_action_just_pressed("p2_left"):
			_p2_shape = (_p2_shape - 1 + NUM_SHAPES) % NUM_SHAPES
			_hud.update_shape_select(_p1_shape, _p2_shape, _p1_confirmed, false)
		elif Input.is_action_just_pressed("p2_right"):
			_p2_shape = (_p2_shape + 1) % NUM_SHAPES
			_hud.update_shape_select(_p1_shape, _p2_shape, _p1_confirmed, false)
		elif Input.is_action_just_pressed("p2_boost"):
			_p2_confirmed = true
			_hud.update_shape_select(_p1_shape, _p2_shape, _p1_confirmed, true)

	if _p1_confirmed and _p2_confirmed:
		_hud.hide_shape_select()
		_start_countdown()


# ── Setup helpers ──────────────────────────────────────────────────────────────

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
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.04, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.18, 0.38)
	env.ambient_light_energy = 0.6
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.15
	env_node.environment = env
	add_child(env_node)


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

uniform vec4  base_color  : source_color = vec4(0.10, 0.13, 0.08, 1.0);
uniform vec4  grid_color  : source_color = vec4(0.22, 0.38, 0.18, 1.0);
uniform vec4  grid_emit   : source_color = vec4(0.18, 0.36, 0.14, 1.0);
uniform float grid_size   : hint_range(0.25, 4.0, 0.25) = 1.0;
uniform float line_width  : hint_range(0.01, 0.15, 0.005) = 0.035;
uniform float emit_str    : hint_range(0.0, 6.0, 0.1)  = 2.2;
uniform float pulse_speed : hint_range(0.0, 2.0, 0.05) = 0.4;
uniform float arena_radius: hint_range(1.0, 20.0) = 6.5;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Grid lines from world XZ — stays straight on the curved surface.
	vec2  uv   = world_pos.xz / grid_size;
	vec2  f    = fract(uv);
	float line = 1.0 - smoothstep(0.0, line_width, min(min(f.x, 1.0 - f.x),
	                                                     min(f.y, 1.0 - f.y)));

	// Subtle outward travel pulse so the grid feels alive.
	float dist   = length(world_pos.xz);
	float wave   = 0.5 + 0.5 * sin((dist * 1.2 - TIME * pulse_speed) * TAU);
	float pulse  = mix(0.75, 1.0, wave * 0.4);

	// Fade grid toward the rim so edges don't look clipped.
	float rim_fade = 1.0 - smoothstep(0.65, 1.0, dist / arena_radius);
	line *= rim_fade;

	ALBEDO    = mix(base_color.rgb, grid_color.rgb, line);
	EMISSION  = grid_emit.rgb * line * emit_str * pulse;
	ROUGHNESS = 0.82;
	METALLIC  = 0.12;
}
"""
	var bowl_mat := ShaderMaterial.new()
	bowl_mat.shader = bowl_shader
	bowl_mat.set_shader_parameter("arena_radius", ARENA_RADIUS)
	bowl_mesh.surface_set_material(0, bowl_mat)
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
	const DIST_CLOSE  : float = 9.0    # distance when tops are nearly touching
	const DIST_FAR    : float = 22.0   # distance when tops are at opposite ends
	const ELEV_CLOSE  : float = 0.70   # elevation (rad) when close — low, cinematic
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
	_p1_confirmed = false
	_p2_confirmed = false
	for top in _tops:
		top.queue_free()
	_tops.clear()
	_hud.update_scores(_scores[1], _scores[2])
	_hud.show_shape_select(_p1_shape, _p2_shape)


func _start_countdown() -> void:
	_state = "countdown"
	_countdown_timer = 3.0
	_spawn_tops()
	_hud.update_scores(_scores[1], _scores[2])
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
	t1.set("top_color", Color(0.24, 0.34, 0.822, 1.0))
	t1.set("shape_type", _p1_shape)
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
	t2.set("top_color", Color(1.0, 0.15, 0.1))
	t2.set("shape_type", _p2_shape)
	t2.position = Vector3(3.5, 1.6, 0.0)
	t2.freeze = true
	t2.connect("top_died", _on_top_died)
	add_child(t2)
	_tops.append(t2)


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
		_hud.show_message("P%d (%s) WINS THE MATCH!" % [winner, color_name])
		_restart_timer = 3.5
		await get_tree().create_timer(3.5).timeout
		_scores = {1: 0, 2: 0}
		_hud.update_scores(0, 0)
	else:
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
	torus_mat.albedo_color               = Color(0.008, 0.008, 0.009)
	torus_mat.emission_enabled           = true
	torus_mat.emission                   = Color(0.322, 0.322, 0.322)
	torus_mat.emission_energy_multiplier = 3.0
	torus_mat.metallic                   = 0.7
	torus_mat.roughness                  = 0.15
	torus_mesh.material   = torus_mat
	torus_inst.mesh       = torus_mesh
	torus_inst.position.y = rim_y
	add_child(torus_inst)

	# Ambient glow from the rim plane.
	var ring_light := OmniLight3D.new()
	ring_light.light_energy = 1.2
	ring_light.light_color  = Color(0.5, 0.3, 1.0)
	ring_light.omni_range   = 16.0
	ring_light.position     = Vector3(0.0, rim_y, 0.0)
	add_child(ring_light)

	# Shared material — CULL_DISABLED so both sides of each arc face render
	# without needing to verify per-face winding order.
	var seg_mat := StandardMaterial3D.new()
	seg_mat.albedo_color               = Color(0.10, 0.10, 0.13)
	seg_mat.emission_enabled           = true
	seg_mat.emission                   = Color(0.28, 0.28, 0.34)
	seg_mat.emission_energy_multiplier = 2.2
	seg_mat.metallic                   = 0.80
	seg_mat.roughness                  = 0.18
	seg_mat.cull_mode                  = BaseMaterial3D.CULL_DISABLED

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
		var cd: float     = top.get("_boost_cooldown")
		var type_idx: int = top.get("shape_type")
		var cd_max: float = TopScript.get_types()[type_idx].boost_cooldown
		var frac := 1.0 - clampf(cd / cd_max, 0.0, 1.0)
		if top.get("player_id") == 1:
			p1_frac = frac
		else:
			p2_frac = frac
	_hud.update_boost_bars(p1_frac, p2_frac)
