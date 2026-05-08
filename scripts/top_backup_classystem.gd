extends RigidBody3D

signal top_died(player_id: int)

# ── Top type class ─────────────────────────────────────────────────────────────
# Add a new type by appending another TopTypeData block inside _build_types().
# Every stat lives here — nothing is hard-coded elsewhere in the script.
class TopTypeData:
	var display_name:  String
	var desc:          String
	var disc_sides:    int      # polygon sides for the fusion wheel (16 = round)
	# Physics
	var move_force:    float    # lateral push force
	var boost_amount:  float    # extra spin from boost
	var boost_cooldown: float   # seconds between boosts
	var gyro_strength: float    # upright-correction torque multiplier
	var angular_damp:  float    # spin decay rate (0 = no decay)
	var inertia_spin:  float    # Y-axis rotational inertia (higher = spin lasts longer)
	var inertia_tilt:  float    # X/Z inertia (lower = gyro corrects tilt faster)
	# Geometry / collision
	var tip_radius:    float    # tip sphere radius (smaller = less friction, more stamina)
	var disc_radius:   float    # outer collision cylinder radius (wider = more blade reach)
	var blade_len:       float  # blade box Z length  (0 = no blades, smooth rim instead)
	var blade_w:         float  # blade box X width
	var blade_h:         float  # blade box Y height
	var blade_thickness: float  # height of the outer metal ring (visual + collision depth)
	var blade_radius:    float  # radius of the outer blade ring (visual + collision)
	var blade_y:         float  # vertical centre of the blade ring and its collision shape
	var tip_y:           float  # vertical position of the tip sphere (negative = lower)
	var tip_color:       Color  # colour of the shaft, barrel, and tip sphere
	var ring_y:          float  # vertical centre of the energy ring (and its collision)
	# Impact
	var knockback:     float    # extra outgoing impulse applied to the other top on contact
								# (stacks with the physics engine's own collision response)
	var ring_kb_mult:  float    # knockback multiplier when the energy ring is the contact shape


# ── Type registry ──────────────────────────────────────────────────────────────
static var _type_cache: Array = []

static func get_types() -> Array:
	if _type_cache.is_empty():
		_type_cache = _build_types()
	return _type_cache

static func _build_types() -> Array:
	var t: Array = []
	var d: TopTypeData

	# ── Attack ────────────────────────────────────────────────────────────────
	d = TopTypeData.new()
	d.display_name  = "Attack"
	d.desc          = "Highest push force, massive knockback, burns spin fast"
	d.disc_sides    = 16 
	d.move_force    = 24.0
	d.boost_amount  = 14.0;  d.boost_cooldown = 3.0
	d.gyro_strength = 1.2;   d.angular_damp   = 0.10
	d.inertia_spin  = 0.28;  d.inertia_tilt   = 0.10
	d.tip_radius    = 0.08;  d.disc_radius     = 0.45 
	d.blade_len     = 0.0;   d.blade_w         = 0.0;   d.blade_h = 0.0
	d.blade_thickness = 0.17;  d.blade_radius = 0.45;  d.blade_y = 0.05
	d.tip_y           = -0.23;  d.tip_color = Color(0.698, 0.092, 0.14, 1.0)
	d.ring_y          = -0.02
	d.knockback     = 5.2;  d.ring_kb_mult = 1.8
	t.append(d)

	# ── Defense ───────────────────────────────────────────────────────────────
	d = TopTypeData.new()
	d.display_name  = "Defense"
	d.desc          = "Heavy rim, very long spin, low knockback but hard to move"
	d.disc_sides    = 16
	d.move_force    = 8.0
	d.boost_amount  = 8.0;   d.boost_cooldown = 4.0
	d.gyro_strength = 0.8;   d.angular_damp   = 0.03
	d.inertia_spin  = 0.72;  d.inertia_tilt   = 0.07
	d.tip_radius    = 0.15;  d.disc_radius     = 0.45
	d.blade_len     = 0.0;   d.blade_w         = 0.0;   d.blade_h = 0.0
	d.blade_thickness = 0.21;  d.blade_radius = 0.45;  d.blade_y = 0.08
	d.tip_y           = -0.33;  d.tip_color = Color(0.76, 0.76, 0.84)
	d.ring_y          = -0.02
	d.knockback     = 0.7;  d.ring_kb_mult = 1.2
	t.append(d)

	# ── Stamina ───────────────────────────────────────────────────────────────
	d = TopTypeData.new()
	d.display_name  = "Stamina"
	d.desc          = "Tiny tip, almost no friction, outlasts all others"
	d.disc_sides    = 16
	d.move_force    = 10.0
	d.boost_amount  = 10.0;  d.boost_cooldown = 3.5
	d.gyro_strength = 1.0;   d.angular_damp   = 0.02
	d.inertia_spin  = 0.60;  d.inertia_tilt   = 0.08
	d.tip_radius    = 0.07;  d.disc_radius     = 0.45
	d.blade_len     = 0.0;   d.blade_w         = 0.0;   d.blade_h = 0.0
	d.blade_thickness = 0.11;  d.blade_radius = 0.45;  d.blade_y = 0.08
	d.tip_y           = -0.22;  d.tip_color = Color(0.76, 0.76, 0.84)
	d.ring_y          = -0.02
	d.knockback     = 0.5;  d.ring_kb_mult = 1.5
	t.append(d)

	return t


# ── Convenience accessors (used by hud.gd) ────────────────────────────────────
static func type_count() -> int:
	return get_types().size()

static func type_name(idx: int) -> String:
	return get_types()[idx].display_name

static func type_desc(idx: int) -> String:
	return get_types()[idx].desc


# ── Instance variables ────────────────────────────────────────────────────────
@export var player_id:   int   = 1
@export var top_color:   Color = Color(0.262, 0.498, 0.977, 1.0)
@export var shape_type:  int   = 0   # index into get_types()
@export var initial_spin: float = 70.0
@export var death_spin_threshold: float = 3.0

var current_spin: float = 0.0
var is_alive:     bool  = false
var _boost_cooldown:      float = 0.0
var _boost_charge:        float = 1.0   # 0–1 multiplier on boost spin; drains per use, recovers over time
var _low_spin_timer:      float = 0.0
var _wall_spark_cooldown: float = 0.0   # prevents spark spam on sustained wall contact
var _ring_col: CollisionShape3D          # energy ring collision shape (for ring_kb_mult checks)
var _clash_cooldowns: Dictionary = {}    # Node → float; deduplicates multi-shape contacts
var _spin_label:      Label3D
var _collision_parts: Array[MeshInstance3D] = []
# Materials that flash white on contact — populated during _build_fusion_wheel().
var _flash_mats: Array[StandardMaterial3D] = []

const LOW_SPIN_GRACE := 0.6


func _ready() -> void:
	_build_mesh()
	#_build_spin_label()

	var td := _type_data()
	mass         = 1.5
	inertia      = Vector3(td.inertia_tilt, td.inertia_spin, td.inertia_tilt)
	angular_damp = td.angular_damp
	linear_damp  = 0.6

	var phys_mat := PhysicsMaterial.new()
	phys_mat.friction = 0.05
	phys_mat.bounce   = 0.05
	physics_material_override = phys_mat

	contact_monitor       = true
	max_contacts_reported = 4
	body_shape_entered.connect(_on_body_shape_entered)


# Shorthand — avoids repeating get_types()[shape_type] everywhere.
func _type_data() -> TopTypeData:
	return get_types()[clampi(shape_type, 0, get_types().size() - 1)]


func start_spinning() -> void:
	is_alive = true
	_boost_cooldown = 0.0
	_boost_charge   = 1.0
	_low_spin_timer = 0.0
	rotation         = Vector3.ZERO
	linear_velocity  = Vector3.ZERO
	angular_velocity = Vector3.UP * initial_spin


func _physics_process(delta: float) -> void:
	current_spin = angular_velocity.length()

	# Gyroscopic stabilisation — runs even during countdown so top stays upright.
	var td       := _type_data()
	var tilt_axis := basis.y.cross(Vector3.UP)
	if tilt_axis.length_squared() > 1e-4:
		var tilt_angle := basis.y.angle_to(Vector3.UP)
		apply_torque(tilt_axis.normalized() * tilt_angle * current_spin * td.gyro_strength)

	if not is_alive:
		return

	_boost_cooldown      = maxf(0.0, _boost_cooldown      - delta)
	_boost_charge        = minf(1.0, _boost_charge        + delta * 0.12)  # ~8 s full recovery
	_wall_spark_cooldown = maxf(0.0, _wall_spark_cooldown - delta)
	# Expire per-body clash cooldowns so repeated contacts can fire again.
	for k in _clash_cooldowns.keys():
		_clash_cooldowns[k] -= delta
		if _clash_cooldowns[k] <= 0.0:
			_clash_cooldowns.erase(k)
	_update_label()

	if current_spin <= death_spin_threshold or global_position.y < -1.0:
		_low_spin_timer += delta
		if _low_spin_timer >= LOW_SPIN_GRACE:
			_die()
		return
	_low_spin_timer = 0.0

	_handle_input(td)


func _handle_input(td: TopTypeData) -> void:
	var move_dir    := Vector2.ZERO
	var boost_pressed := false

	match player_id:
		1:
			move_dir.x    = Input.get_axis("p1_left", "p1_right")
			move_dir.y    = Input.get_axis("p1_up",   "p1_down")
			boost_pressed = Input.is_action_just_pressed("p1_boost")
		2:
			move_dir.x    = Input.get_axis("p2_left", "p2_right")
			move_dir.y    = Input.get_axis("p2_up",   "p2_down")
			boost_pressed = Input.is_action_just_pressed("p2_boost")

	if move_dir.length_squared() > 0.01:
		apply_central_force(Vector3(move_dir.x, 0.0, move_dir.y).normalized() * td.move_force)

	if boost_pressed and _boost_cooldown <= 0.0:
		var deficit := initial_spin - angular_velocity.dot(basis.y)
		if deficit > 0.0:
			# Spin added scales with current charge — repeated boosts give less.
			angular_velocity += basis.y * minf(td.boost_amount * _boost_charge, deficit)
		_boost_cooldown = td.boost_cooldown
		# Drain charge; floor at 0.1 so boost never becomes completely useless.
		_boost_charge = maxf(0.1, _boost_charge - 0.28)


func _on_body_shape_entered(body_rid: RID, body: Node, body_shape_index: int, local_shape_index: int) -> void:
	if not is_alive:
		return

	if body.get("player_id") != null:
		# ── Top-to-top clash ─────────────────────────────────────────────────
		# body_shape_entered can fire multiple times if several shape pairs overlap
		# simultaneously. Use a short per-body cooldown to process each clash once.
		if body in _clash_cooldowns:
			return
		_clash_cooldowns[body] = 0.15

		var other     := body as RigidBody3D
		var rel_speed := (linear_velocity - other.linear_velocity).length()
		var contact_pos := Vector3(
			(global_position.x + other.global_position.x) * 0.5,
			global_position.y + 0.11,
			(global_position.z + other.global_position.z) * 0.5
		)
		var clash_dir := (global_position - other.global_position).normalized()
		_spawn_clash_sparks(contact_pos, clash_dir, rel_speed)
		_flash_collision()

		# Check whether the local hit shape is the energy ring.
		var owner_id   := shape_find_owner(local_shape_index)
		var hit_ring   := (_ring_col != null and shape_owner_get_owner(owner_id) == _ring_col)

		var td  := _type_data()
		var kb  := td.knockback * clampf(rel_speed * 0.2, 0.3, 3.0)
		if hit_ring:
			kb *= td.ring_kb_mult   # bonus knockback when the ring takes the hit
		other.apply_central_impulse(-clash_dir * kb)

	elif body is StaticBody3D:
		# ── Stadium wall / bowl hit ──────────────────────────────────────────
		var speed := linear_velocity.length()
		if speed < 2.5 or _wall_spark_cooldown > 0.0:
			return
		_wall_spark_cooldown = 0.25

		var hit_dir     := linear_velocity.normalized()
		var contact_pos := global_position + hit_dir * _type_data().disc_radius
		contact_pos.y   = global_position.y + 0.11
		var spray_dir   := -hit_dir
		_spawn_wall_sparks(contact_pos, spray_dir, speed)


func _flash_collision() -> void:
	for mat in _flash_mats:
		var original_emission := mat.emission
		var original_energy   := mat.emission_energy_multiplier
		var tween := create_tween().set_parallel(true)
		# Spike to white
		tween.tween_property(mat, "emission", Color(1.0, 1.0, 1.0), 0.03)
		tween.tween_property(mat, "emission_energy_multiplier", 6.0, 0.03)
		# Fade back to original
		tween.chain().set_parallel(true)
		tween.tween_property(mat, "emission", original_emission, 0.18)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(mat, "emission_energy_multiplier", original_energy, 0.18)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _spawn_clash_sparks(pos: Vector3, dir: Vector3, _intensity: float) -> void:
	var count   := 3
	var colours := [
		Color(1.0, 0.486, 0.2, 1.0),
		Color(1.0, 0.4,  0.1),
		Color(0.806, 0.019, 0.0, 1.0),
	]

	for i in range(count):
		# Flat polygon chip — CylinderMesh with 3–5 sides and tiny height.
		var sides := randi_range(3, 4)
		var size  := randf_range(0.008, 0.07)

		var mat := StandardMaterial3D.new()
		mat.transparency             = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color             = colours[i % colours.size()]
		mat.emission_enabled         = true
		mat.emission                 = mat.albedo_color
		mat.emission_energy_multiplier = 2.5
		mat.shading_mode             = BaseMaterial3D.SHADING_MODE_UNSHADED

		var chip_mesh := CylinderMesh.new()
		chip_mesh.top_radius      = size
		chip_mesh.bottom_radius   = size
		chip_mesh.height          = 0.01   # almost flat
		chip_mesh.radial_segments = sides
		chip_mesh.cap_top         = true
		chip_mesh.cap_bottom      = false
		chip_mesh.material        = mat

		var chip := MeshInstance3D.new()
		chip.mesh = chip_mesh
		get_parent().add_child(chip)
		chip.global_position = pos

		# Each chip flies outward in a cone around the clash direction.
		var spread_angle := randf_range(0.0, TAU)
		var spread_tilt  := randf_range(0.1, 0.55)
		var fly_dir := dir.rotated(Vector3.UP, spread_angle)
		fly_dir = fly_dir.lerp(Vector3.UP, spread_tilt).normalized()
		var speed   := randf_range(0.5, 1.0)
		var travel  := fly_dir * speed * 0.35   # distance over lifetime

		# Random spin for tumbling look.
		var spin_axis := Vector3(randf(), randf(), randf()).normalized()

		var duration := randf_range(0.25, 0.40)
		var tween    := chip.create_tween()
		tween.set_parallel(true)
		tween.tween_property(chip, "global_position",
			pos + travel, duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tween.tween_property(chip, "rotation",
			spin_axis * randf_range(TAU, TAU * 2.0), duration)
		tween.tween_property(mat, "albedo_color",
			Color(mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b, 0.0),
			duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.chain().tween_callback(chip.queue_free)


# Silver/grey chips for stadium-wall impacts — visually distinct from clash sparks.
func _spawn_wall_sparks(pos: Vector3, dir: Vector3, speed: float) -> void:
	# Scale chip count with impact speed (2 at minimum, up to 5 at high speed).
	var count := clampi(int(speed * 0.4), 2, 5)
	var colours := [
		Color(0.85, 0.85, 0.90),   # silver-white
		Color(0.70, 0.72, 0.78),   # cool grey
		Color(1.00, 0.95, 0.70),   # brief yellow flash
	]

	for i in range(count):
		var sides := randi_range(3, 5)
		var size  := randf_range(0.005, 0.05)

		var mat := StandardMaterial3D.new()
		mat.transparency             = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color             = colours[i % colours.size()]
		mat.emission_enabled         = true
		mat.emission                 = mat.albedo_color
		mat.emission_energy_multiplier = 3.0
		mat.shading_mode             = BaseMaterial3D.SHADING_MODE_UNSHADED

		var chip_mesh := CylinderMesh.new()
		chip_mesh.top_radius      = size
		chip_mesh.bottom_radius   = size
		chip_mesh.height          = 0.01
		chip_mesh.radial_segments = sides
		chip_mesh.cap_top         = true
		chip_mesh.cap_bottom      = false
		chip_mesh.material        = mat

		var chip := MeshInstance3D.new()
		chip.mesh = chip_mesh
		get_parent().add_child(chip)
		chip.global_position = pos

		# Spray in a tight cone around the bounce-back direction, with a small upward bias.
		var spread_angle := randf_range(0.0, TAU)
		var spread_tilt  := randf_range(0.05, 0.35)
		var fly_dir := dir.rotated(Vector3.UP, spread_angle)
		fly_dir = fly_dir.lerp(Vector3.UP, spread_tilt).normalized()
		var chip_speed := randf_range(0.3, 0.8) * clampf(speed / 8.0, 0.5, 1.5)
		var travel     := fly_dir * chip_speed * 0.3

		var spin_axis := Vector3(randf(), randf(), randf()).normalized()
		var duration  := randf_range(0.15, 0.30)
		var tween     := chip.create_tween()
		tween.set_parallel(true)
		tween.tween_property(chip, "global_position",
			pos + travel, duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tween.tween_property(chip, "rotation",
			spin_axis * randf_range(TAU, TAU * 2.0), duration)
		tween.tween_property(mat, "albedo_color",
			Color(mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b, 0.0),
			duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.chain().tween_callback(chip.queue_free)


func _die() -> void:
	if not is_alive:
		return
	is_alive     = false
	angular_damp = 3.0
	linear_damp  = 0.3
	top_died.emit(player_id)


func _update_label() -> void:
	if not _spin_label:
		return
	var t := clampf(current_spin / initial_spin, 0.0, 1.0)
	_spin_label.text     = "%d%%" % int(t * 100.0)
	_spin_label.modulate = Color(1.0, t, t * 0.3)


# ── Mesh + collision ───────────────────────────────────────────────────────────
func _build_mesh() -> void:
	_build_performance_tip()
	_build_fusion_wheel()
	_build_energy_ring()
	_build_rotation_marker()
	_build_collision()


# ── Performance Tip ────────────────────────────────────────────────────────────
# Shape: shaft (thin cylinder) → tip barrel (wider cylinder) → rounded end (hemisphere).
# The shaft tapers into the barrel which sits just above the contact sphere.
func _build_performance_tip() -> void:
	var td  := _type_data()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = td.tip_color
	mat.metallic     = 1.0
	mat.roughness    = 0.05

	# ── Rounded contact end — sphere at the very bottom ──────────────────────
	var ball   := MeshInstance3D.new()
	var ball_m := SphereMesh.new()
	ball_m.radius   = td.tip_radius
	ball_m.height   = td.tip_radius * 2.0
	ball_m.material = mat
	ball.mesh       = ball_m
	ball.position.y = td.tip_y
	add_child(ball)
	_collision_parts.append(ball)

	# ── Tip barrel — short cylinder just above the sphere ────────────────────
	# Height = one radius so the barrel doesn't crowd out the shaft.
	var barrel_h   := td.tip_radius * 1.0
	var barrel_cy  := td.tip_y + td.tip_radius + barrel_h * 0.5
	var barrel     := MeshInstance3D.new()
	var barrel_m   := CylinderMesh.new()
	barrel_m.top_radius      = td.tip_radius
	barrel_m.bottom_radius   = td.tip_radius
	barrel_m.height          = barrel_h
	barrel_m.radial_segments = 12
	barrel_m.material        = mat
	barrel.mesh              = barrel_m
	barrel.position.y        = barrel_cy
	add_child(barrel)

	# ── Shaft — thin tapered cylinder connecting disc to barrel top ───────────
	var barrel_top := barrel_cy + barrel_h * 0.5
	var shaft_len  := -barrel_top   # barrel_top is negative, so this is positive
	var shaft      := MeshInstance3D.new()
	var shaft_m    := CylinderMesh.new()
	shaft_m.top_radius      = 0.035
	shaft_m.bottom_radius   = td.tip_radius   # widens at barrel junction
	shaft_m.height          = shaft_len
	shaft_m.radial_segments = 8
	shaft_m.material        = mat
	shaft.mesh              = shaft_m
	shaft.position.y        = barrel_top + shaft_len * 0.5
	add_child(shaft)
	_collision_parts.append(shaft)


# ── Fusion Wheel ───────────────────────────────────────────────────────────────
func _build_fusion_wheel() -> void:
	var td    := _type_data()
	var sides := td.disc_sides

	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color             = top_color
	wheel_mat.metallic                 = 0.85
	wheel_mat.roughness                = 0.18
	wheel_mat.emission_enabled         = true
	wheel_mat.emission                 = top_color
	wheel_mat.emission_energy_multiplier = 1.7

	var disc   := MeshInstance3D.new()
	var disc_m := CylinderMesh.new()
	disc_m.radial_segments = sides
	disc_m.rings           = 1
	disc_m.top_radius      = 0.38
	disc_m.bottom_radius   = 0.38
	disc_m.height          = 0.14
	disc_m.material        = wheel_mat
	disc.mesh              = disc_m
	disc.position.y        = 0.11
	add_child(disc)
	_collision_parts.append(disc)
	_flash_mats.append(wheel_mat)

	# ── Outer metal blade ring — present on every type ─────────────────────────
	var blade_ring_mat := StandardMaterial3D.new()
	blade_ring_mat.albedo_color              = Color(0.82, 0.82, 0.90)
	blade_ring_mat.metallic                  = 0.9
	blade_ring_mat.roughness                 = 0.25
	blade_ring_mat.emission_enabled          = true
	blade_ring_mat.emission                  = Color(0.55, 0.55, 0.62)
	blade_ring_mat.emission_energy_multiplier = 0.6

	var blade_ring   := MeshInstance3D.new()
	var blade_ring_m := CylinderMesh.new()
	blade_ring_m.radial_segments = 48
	blade_ring_m.top_radius      = td.blade_radius
	blade_ring_m.bottom_radius   = td.blade_radius
	blade_ring_m.height          = td.blade_thickness
	blade_ring_m.material        = blade_ring_mat
	blade_ring.mesh              = blade_ring_m
	blade_ring.position.y        = td.blade_y
	add_child(blade_ring)
	_flash_mats.append(blade_ring_mat)

	if td.blade_len <= 0.0:
		# No blades — smooth outer rim (Stamina type)
		var rim   := MeshInstance3D.new()
		var rim_m := CylinderMesh.new()
		rim_m.radial_segments = 24
		rim_m.top_radius      = 0.38
		rim_m.bottom_radius   = 0.30
		rim_m.height          = 0.10
		rim_m.material        = wheel_mat
		rim.mesh              = rim_m
		rim.position.y        = 0.11
		add_child(rim)
		_collision_parts.append(rim)
	else:
		var blade_mat := StandardMaterial3D.new()
		blade_mat.albedo_color             = top_color.darkened(0.18)
		blade_mat.metallic                 = 0.92
		blade_mat.roughness                = 0.12
		blade_mat.emission_enabled         = true
		blade_mat.emission                 = top_color.darkened(0.10)
		blade_mat.emission_energy_multiplier = 1.3

		for i in range(sides):
			var angle := i * TAU / sides
			var b     := MeshInstance3D.new()
			var b_m   := BoxMesh.new()
			b_m.size     = Vector3(td.blade_w, td.blade_h, td.blade_len)
			b_m.material = blade_mat
			b.mesh       = b_m
			var r        := 0.38 + td.blade_len * 0.5
			b.position   = Vector3(cos(angle) * r, 0.11, sin(angle) * r)
			b.rotation.y = -angle
			add_child(b)
			_collision_parts.append(b)


# ── Energy Ring ────────────────────────────────────────────────────────────────
func _build_energy_ring() -> void:
	var td    := _type_data()
	var sides := td.disc_sides

	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color             = top_color.lightened(0.28)
	ring_mat.metallic                 = 1.0
	ring_mat.roughness                = 0.08
	ring_mat.emission_enabled         = true
	ring_mat.emission                 = top_color.lightened(0.22)
	ring_mat.emission_energy_multiplier = 2.3

	var ring   := MeshInstance3D.new()
	var ring_m := CylinderMesh.new()
	ring_m.radial_segments = 20
	ring_m.top_radius      = 0.27
	ring_m.bottom_radius   = 0.27
	ring_m.height          = 0.20
	ring_m.material        = ring_mat
	ring.mesh              = ring_m
	ring.position.y        = td.ring_y
	add_child(ring)

	var peg_count := mini(sides, 8)
	var peg_mat   := StandardMaterial3D.new()
	peg_mat.albedo_color             = top_color.lightened(0.48)
	peg_mat.metallic                 = 1.0
	peg_mat.roughness                = 0.06
	peg_mat.emission_enabled         = true
	peg_mat.emission                 = top_color.lightened(0.42)
	peg_mat.emission_energy_multiplier = 3.0

	for i in range(peg_count):
		var angle := i * TAU / peg_count
		var peg   := MeshInstance3D.new()
		var peg_m := CylinderMesh.new()
		peg_m.top_radius      = 0.05
		peg_m.bottom_radius   = 0.05
		peg_m.height          = 0.01
		peg_m.radial_segments = 8
		peg_m.material        = peg_mat
		peg.mesh              = peg_m
		peg.position          = Vector3(cos(angle) * 0.27, 0.18, sin(angle) * 0.27)
		add_child(peg)

	var crown_mat := StandardMaterial3D.new()
	crown_mat.albedo_color             = Color(0.94, 0.94, 1.00)
	crown_mat.metallic                 = 1.0
	crown_mat.roughness                = 0.02
	crown_mat.emission_enabled         = true
	crown_mat.emission                 = Color(0.85, 0.85, 1.00)
	crown_mat.emission_energy_multiplier = 2.0

	var crown   := MeshInstance3D.new()
	var crown_m := SphereMesh.new()
	crown_m.radius   = 0.08
	crown_m.height   = 0.16
	crown_m.material = crown_mat
	crown.mesh       = crown_m
	crown.position.y = 0.18
	add_child(crown)


# ── Rotation marker ────────────────────────────────────────────────────────────
func _build_rotation_marker() -> void:
	var stripe_mat := StandardMaterial3D.new()
	stripe_mat.albedo_color             = Color(0.089, 0.089, 0.089, 1.0)
	stripe_mat.emission_enabled         = true
	stripe_mat.emission                 = Color(0.333, 0.333, 0.333, 1.0)
	stripe_mat.emission_energy_multiplier = 1.6

	var stripe   := MeshInstance3D.new()
	var stripe_m := BoxMesh.new()
	stripe_m.size     = Vector3(0.06, 0.020, 0.38)
	stripe_m.material = stripe_mat
	stripe.mesh       = stripe_m
	stripe.position.y = 0.18
	add_child(stripe)


# ── Collision — two primitives ─────────────────────────────────────────────────
# SphereShape3D for the tip (smooth bowl contact) +
# CylinderShape3D for the disc (blade-to-blade hits).
# Radii come from the active TopTypeData so each type feels physically distinct.
func _build_collision() -> void:
	_collision_parts.clear()

	var td := _type_data()

	var tip_col   := CollisionShape3D.new()
	var tip_shape := SphereShape3D.new()
	tip_shape.radius = td.tip_radius
	tip_col.shape    = tip_shape
	tip_col.position = Vector3(0.0, td.tip_y, 0.0)
	add_child(tip_col)

	# Shaft collision — replicates geometry from _build_performance_tip().
	var barrel_h   := td.tip_radius * 1.0
	var barrel_top := td.tip_y + td.tip_radius + barrel_h
	var shaft_len  := maxf(0.01, -barrel_top)
	var shaft_col   := CollisionShape3D.new()
	var shaft_shape := CylinderShape3D.new()
	shaft_shape.radius = (0.035 + td.tip_radius) * 0.5   # average of taper ends
	shaft_shape.height = shaft_len
	shaft_col.shape    = shaft_shape
	shaft_col.position = Vector3(0.0, barrel_top + shaft_len * 0.5, 0.0)
	add_child(shaft_col)

	var ring_col   := CollisionShape3D.new()
	var ring_shape := CylinderShape3D.new()
	ring_shape.radius = 0.27
	ring_shape.height = 0.20
	ring_col.shape    = ring_shape
	ring_col.position = Vector3(0.0, td.ring_y, 0.0)
	add_child(ring_col)
	_ring_col = ring_col   # stored so body_shape_entered can identify ring hits

	var disc_col   := CollisionShape3D.new()
	var disc_shape := CylinderShape3D.new()
	disc_shape.radius = td.blade_radius
	disc_shape.height = td.blade_thickness
	disc_col.shape    = disc_shape
	disc_col.position = Vector3(0.0, td.blade_y, 0.0)
	add_child(disc_col)


func _build_spin_label() -> void:
	_spin_label = Label3D.new()
	_spin_label.text         = "100%"
	_spin_label.font_size    = 48
	_spin_label.modulate     = Color(1.0, 1.0, 0.3)
	_spin_label.billboard    = BaseMaterial3D.BILLBOARD_ENABLED
	_spin_label.no_depth_test = true
	_spin_label.position     = Vector3(0.0, 1.2, 0.0)
	add_child(_spin_label)
