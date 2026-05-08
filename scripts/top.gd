extends RigidBody3D

signal top_died(player_id: int)

# ── Part data classes ──────────────────────────────────────────────────────────
# Each top is assembled from three independently chosen parts:
#   Blade  → outer disc, knockback and movement force
#   Track  → energy ring, spin inertia and boost
#   Tip    → ground contact, friction and stability

class BladeData:
	var display_name:    String
	var desc:            String
	var disc_sides:      int     # polygon sides on the fusion wheel
	var angular_damp:    float   # spin decay rate
	var blade_thickness: float   # height of outer ring
	var blade_radius:    float   # radius of outer ring
	var blade_y:         float   # vertical centre of outer ring
	var disc_radius:     float   # collision cylinder radius (used for wall spark ref)
	var knockback:       float   # outgoing impulse on clash
	var ring_kb_mult:    float   # knockback multiplier when energy ring is the hit shape


class TrackData:
	var display_name:   String
	var desc:           String
	var inertia_spin:   float   # Y-axis rotational inertia
	var inertia_tilt:   float   # X/Z inertia
	var gyro_strength:  float   # upright-correction torque multiplier
	var boost_amount:   float   # spin added per boost
	var boost_cooldown: float   # seconds between boosts
	var ring_y:         float   # vertical centre of the energy ring
	var ring_radius:    float   # radius of the energy ring cylinder
	var ring_color:     Color   # colour of the energy ring, pegs, and crown tint
	var track_kb_mult:  float   # knockback multiplier when track body is the contact point


class TipData:
	var display_name: String
	var desc:         String
	var tip_radius:   float   # contact sphere radius
	var tip_y:        float   # vertical position of tip sphere
	var tip_color:    Color   # colour of shaft, barrel, and sphere
	var move_force:   float   # lateral drive force (scales with spin speed)


# ── Part registries ────────────────────────────────────────────────────────────
# No caching — these build functions are trivially fast (3 objects each) and
# static var caches persist across editor play sessions, causing stale data.

static func get_blades() -> Array: return _build_blades()
static func get_tracks() -> Array: return _build_tracks()
static func get_tips()   -> Array: return _build_tips()


static func _build_blades() -> Array:
	var t: Array = []
	var d: BladeData

	# ── Attack ────────────────────────────────────────────────────────────────
	d = BladeData.new()
	d.display_name    = "Attack"
	d.desc            = "High knockback, burns spin fast"
	d.disc_sides      = 16;    d.disc_radius    = 0.45
	d.angular_damp    = 0.10
	d.blade_thickness = 0.17;  d.blade_radius   = 0.45;  d.blade_y = 0.05
	d.knockback       = 5.2;   d.ring_kb_mult   = 1.8
	t.append(d)

	# ── Defense ───────────────────────────────────────────────────────────────
	d = BladeData.new()
	d.display_name    = "Defense"
	d.desc            = "Heavy rim, low knockback, hard to move"
	d.disc_sides      = 16;    d.disc_radius    = 0.45
	d.angular_damp    = 0.03
	d.blade_thickness = 0.21;  d.blade_radius   = 0.45;  d.blade_y = 0.03
	d.knockback       = 0.7;   d.ring_kb_mult   = 1.2
	t.append(d)

	# ── Stamina ───────────────────────────────────────────────────────────────
	d = BladeData.new()
	d.display_name    = "Stamina"
	d.desc            = "Minimal drag, prioritises spin retention"
	d.disc_sides      = 16;    d.disc_radius    = 0.45
	d.angular_damp    = 0.02
	d.blade_thickness = 0.11;  d.blade_radius   = 0.45;  d.blade_y = 0.08
	d.knockback       = 0.5;   d.ring_kb_mult   = 1.5
	t.append(d)

	return t


static func _build_tracks() -> Array:
	var t: Array = []
	var d: TrackData

	# ── Attack ────────────────────────────────────────────────────────────────
	d = TrackData.new()
	d.display_name   = "Attack"
	d.desc           = "Strong gyro, quick boost, low inertia"
	d.inertia_spin   = 0.28;  d.inertia_tilt  = 0.22
	d.gyro_strength  = 1.4
	d.boost_amount   = 14.0;  d.boost_cooldown = 3.0
	d.ring_y         = -0.02;  d.ring_radius = 0.27
	d.ring_color     = Color(0.90, 0.22, 0.12)   # fiery red-orange
	d.track_kb_mult  = 4.0   # still punchy on centre contact
	t.append(d)

	# ── Defense ───────────────────────────────────────────────────────────────
	d = TrackData.new()
	d.display_name   = "Defense"
	d.desc           = "High inertia, slow boost, hard to destabilise"
	d.inertia_spin   = 0.72;  d.inertia_tilt  = 0.30
	d.gyro_strength  = 1.0
	d.boost_amount   = 8.0;   d.boost_cooldown = 4.0
	d.ring_y         = -0.02;  d.ring_radius = 0.18
	d.ring_color     = Color(0.18, 0.48, 0.90)   # steel blue
	d.track_kb_mult  = 1.5   # heavily absorbs centre hits
	t.append(d)

	# ── Stamina ───────────────────────────────────────────────────────────────
	d = TrackData.new()
	d.display_name   = "Stamina"
	d.desc           = "Very high inertia, efficient boost"
	d.inertia_spin   = 0.60;  d.inertia_tilt  = 0.26
	d.gyro_strength  = 1.1
	d.boost_amount   = 10.0;  d.boost_cooldown = 3.5
	d.ring_y         = -0.02
	d.ring_radius    = 0.39
	d.ring_color     = Color(0.20, 0.80, 0.38)   # emerald green
	d.track_kb_mult  = 2.9   # mostly neutral, slight deflection
	t.append(d)

	return t


static func _build_tips() -> Array:
	var t: Array = []
	var d: TipData

	# ── Attack ────────────────────────────────────────────────────────────────
	d = TipData.new()
	d.display_name = "Attack"
	d.desc         = "Small sharp tip — high drive, spin-powered movement"
	d.tip_radius   = 0.08;  d.tip_y = -0.23
	d.tip_color    = Color(0.698, 0.092, 0.14)
	d.move_force   = 26.0   # aggressive — full power at high spin
	t.append(d)

	# ── Defense ───────────────────────────────────────────────────────────────
	d = TipData.new()
	d.display_name = "Defense"
	d.desc         = "Wide flat tip — low drive, planted and hard to steer"
	d.tip_radius   = 0.1;   d.tip_y = -0.23
	d.tip_color    = Color(0.614, 0.177, 0.459, 1.0)
	d.move_force   = 8.0    # sluggish — prioritises staying put
	t.append(d)

	# ── Stamina ───────────────────────────────────────────────────────────────
	d = TipData.new()
	d.display_name = "Stamina"
	d.desc         = "Tiny precision tip — efficient drive, minimal friction"
	d.tip_radius   = 0.07;  d.tip_y = -0.22
	d.tip_color    = Color(0.104, 0.34, 0.0, 1.0)
	d.move_force   = 14.0   # controlled — smooth spin-relative movement
	t.append(d)

	return t


# ── Convenience accessors (used by hud.gd and game_manager.gd) ────────────────
static func blade_count() -> int: return get_blades().size()
static func track_count() -> int: return get_tracks().size()
static func tip_count()   -> int: return get_tips().size()

static func blade_name(i: int) -> String: return get_blades()[i].display_name
static func track_name(i: int) -> String: return get_tracks()[i].display_name
static func tip_name(i: int)   -> String: return get_tips()[i].display_name

static func blade_desc(i: int) -> String: return get_blades()[i].desc
static func track_desc(i: int) -> String: return get_tracks()[i].desc
static func tip_desc(i: int)   -> String: return get_tips()[i].desc


# ── Instance variables ────────────────────────────────────────────────────────
@export var player_id:   int   = 1
@export var top_color:   Color = Color(0.262, 0.498, 0.977, 1.0)
@export var blade_type:  int   = 0   # index into get_blades()
@export var track_type:  int   = 0   # index into get_tracks()
@export var tip_type:    int   = 0   # index into get_tips()
@export var initial_spin: float = 70.0
@export var death_spin_threshold: float = 3.0

var current_spin: float = 0.0
var is_alive:     bool  = false

# Bot control — set by game_manager when vs_bot is true.
var bot_controlled:      bool    = false
var _bot_move_dir:       Vector2 = Vector2.ZERO
var _bot_boost_request:  bool    = false
var _boost_cooldown:      float = 0.0
var _boost_charge:        float = 1.0
var _low_spin_timer:      float = 0.0
var _wall_spark_cooldown: float = 0.0
var _ring_col:  CollisionShape3D   # energy ring outer cylinder
var _track_col: CollisionShape3D   # track body inner drum
var _clash_cooldowns: Dictionary = {}
var _spin_label:      Label3D
var _collision_parts: Array[MeshInstance3D] = []
var _flash_mats: Array[StandardMaterial3D] = []

const LOW_SPIN_GRACE := 0.6


# ── Part accessors ─────────────────────────────────────────────────────────────
func _blade() -> BladeData:
	return get_blades()[clampi(blade_type, 0, get_blades().size() - 1)]

func _track() -> TrackData:
	return get_tracks()[clampi(track_type, 0, get_tracks().size() - 1)]

func _tip() -> TipData:
	return get_tips()[clampi(tip_type, 0, get_tips().size() - 1)]


func _ready() -> void:
	_build_mesh()

	var bd := _blade()
	var tr := _track()
	mass         = 1.5
	inertia      = Vector3(tr.inertia_tilt, tr.inertia_spin, tr.inertia_tilt)
	angular_damp = bd.angular_damp
	linear_damp  = 0.6

	var phys_mat := PhysicsMaterial.new()
	phys_mat.friction = 0.05
	phys_mat.bounce   = 0.05
	physics_material_override = phys_mat

	contact_monitor       = true
	max_contacts_reported = 4
	body_shape_entered.connect(_on_body_shape_entered)


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

	var tr := _track()

	# ── Spin-relative tilt inertia ─────────────────────────────────────────────
	# A real gyroscope resists tilting in proportion to its angular momentum.
	# spin_t = 0 at death threshold, 1 at full speed.
	# inertia_tilt scales from 40 % (wobbly, almost dead) up to 100 % (full spin).
	var spin_t      := clampf((current_spin - death_spin_threshold) /
	                          (initial_spin  - death_spin_threshold), 0.0, 1.0)
	var live_tilt   := tr.inertia_tilt * (0.40 + 0.60 * spin_t)
	inertia = Vector3(live_tilt, tr.inertia_spin, live_tilt)

	# ── Gyroscopic stabilisation ───────────────────────────────────────────────
	# Restoring torque proportional to tilt angle × current spin × gyro_strength.
	var tilt_axis := basis.y.cross(Vector3.UP)
	if tilt_axis.length_squared() > 1e-4:
		var tilt_angle := basis.y.angle_to(Vector3.UP)
		apply_torque(tilt_axis.normalized() * tilt_angle * current_spin * tr.gyro_strength)

	# ── Wobble damping ─────────────────────────────────────────────────────────
	# The gyro acts like a spring — without damping, tilt oscillates forever.
	# We separate angular velocity into spin (world UP) and tilt (perpendicular),
	# then damp only tilt. Damping also fades with spin so dying tops wobble visibly.
	var spin_part   := Vector3.UP * angular_velocity.dot(Vector3.UP)
	var wobble_part := angular_velocity - spin_part
	var wobble_damp := tr.gyro_strength * 4.5 * spin_t   # weakens as top slows
	angular_velocity -= wobble_part * clampf(wobble_damp * delta, 0.0, 0.45)

	if not is_alive:
		return

	_boost_cooldown      = maxf(0.0, _boost_cooldown      - delta)
	_boost_charge        = minf(1.0, _boost_charge        + delta * 0.12)
	_wall_spark_cooldown = maxf(0.0, _wall_spark_cooldown - delta)
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

	_handle_input()


func _handle_input() -> void:
	var tp := _tip()
	var tr := _track()
	var move_dir      := Vector2.ZERO
	var boost_pressed := false

	if bot_controlled:
		move_dir      = _bot_move_dir
		boost_pressed = _bot_boost_request
		_bot_boost_request = false   # consume the request
	else:
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
		# Drive force scales with spin — a fast top has more gyroscopic drive.
		# spin_t: 0 at death threshold, 1 at full speed. Floor at 0.2 so the
		# player retains minimal control even as the top is dying.
		var spin_t       := clampf((current_spin - death_spin_threshold) /
		                           (initial_spin  - death_spin_threshold), 0.0, 1.0)
		var drive        := tp.move_force * (0.2 + 0.8 * spin_t)
		apply_central_force(Vector3(move_dir.x, 0.0, move_dir.y).normalized() * drive)

	if boost_pressed and _boost_cooldown <= 0.0:
		var deficit := initial_spin - angular_velocity.dot(basis.y)
		if deficit > 0.0:
			angular_velocity += basis.y * minf(tr.boost_amount * _boost_charge, deficit)
		_boost_cooldown = tr.boost_cooldown
		_boost_charge   = maxf(0.1, _boost_charge - 0.28)


func _on_body_shape_entered(body_rid: RID, body: Node, body_shape_index: int, local_shape_index: int) -> void:
	if not is_alive:
		return

	if body.get("player_id") != null:
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

		var owner_id  := shape_find_owner(local_shape_index)
		var hit_node  := shape_owner_get_owner(owner_id)
		var hit_ring  := (_ring_col  != null and hit_node == _ring_col)
		var hit_track := (_track_col != null and hit_node == _track_col)

		var bd  := _blade()
		var tr  := _track()
		var kb  := bd.knockback * clampf(rel_speed * 0.2, 0.3, 3.0)
		if hit_ring:
			kb *= bd.ring_kb_mult
		if hit_track:
			kb *= tr.track_kb_mult
		other.apply_central_impulse(-clash_dir * kb)

	elif body is StaticBody3D:
		var speed := linear_velocity.length()
		if speed < 2.5 or _wall_spark_cooldown > 0.0:
			return
		_wall_spark_cooldown = 0.25

		var hit_dir     := linear_velocity.normalized()
		var contact_pos := global_position + hit_dir * _blade().disc_radius
		contact_pos.y   = global_position.y + 0.11
		_spawn_wall_sparks(contact_pos, -hit_dir, speed)


func _flash_collision() -> void:
	for mat in _flash_mats:
		var original_emission := mat.emission
		var original_energy   := mat.emission_energy_multiplier
		var tween := create_tween().set_parallel(true)
		tween.tween_property(mat, "emission", Color(1.0, 1.0, 1.0), 0.03)
		tween.tween_property(mat, "emission_energy_multiplier", 6.0, 0.03)
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
		chip_mesh.height          = 0.01
		chip_mesh.radial_segments = sides
		chip_mesh.cap_top         = true
		chip_mesh.cap_bottom      = false
		chip_mesh.material        = mat
		var chip := MeshInstance3D.new()
		chip.mesh = chip_mesh
		get_parent().add_child(chip)
		chip.global_position = pos
		var spread_angle := randf_range(0.0, TAU)
		var spread_tilt  := randf_range(0.1, 0.55)
		var fly_dir := dir.rotated(Vector3.UP, spread_angle)
		fly_dir = fly_dir.lerp(Vector3.UP, spread_tilt).normalized()
		var speed   := randf_range(0.5, 1.0)
		var travel  := fly_dir * speed * 0.35
		var spin_axis := Vector3(randf(), randf(), randf()).normalized()
		var duration := randf_range(0.25, 0.40)
		var tween    := chip.create_tween()
		tween.set_parallel(true)
		tween.tween_property(chip, "global_position", pos + travel, duration)\
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tween.tween_property(chip, "rotation", spin_axis * randf_range(TAU, TAU * 2.0), duration)
		tween.tween_property(mat, "albedo_color",
			Color(mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b, 0.0),
			duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.chain().tween_callback(chip.queue_free)


func _spawn_wall_sparks(pos: Vector3, dir: Vector3, speed: float) -> void:
	var count := clampi(int(speed * 0.4), 2, 5)
	var colours := [
		Color(0.85, 0.85, 0.90),
		Color(0.70, 0.72, 0.78),
		Color(1.00, 0.95, 0.70),
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
		tween.tween_property(chip, "global_position", pos + travel, duration)\
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tween.tween_property(chip, "rotation", spin_axis * randf_range(TAU, TAU * 2.0), duration)
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


# ── Performance Tip (uses TipData) ────────────────────────────────────────────
func _build_performance_tip() -> void:
	var tp  := _tip()
	var mat := StandardMaterial3D.new()
	mat.albedo_color             = tp.tip_color
	mat.metallic                 = 0.85
	mat.roughness                = 0.12
	mat.emission_enabled         = true
	mat.emission                 = tp.tip_color
	mat.emission_energy_multiplier = 0.9

	# ── Contact sphere at the very bottom ─────────────────────────────────────
	var ball   := MeshInstance3D.new()
	var ball_m := SphereMesh.new()
	ball_m.radius            = tp.tip_radius
	ball_m.height            = tp.tip_radius * 2.0
	ball_m.radial_segments   = 16
	ball_m.rings             = 8
	ball_m.material          = mat
	ball.mesh                = ball_m
	ball.position.y          = tp.tip_y
	add_child(ball)

	# ── Short barrel cylinder sitting above the sphere ─────────────────────────
	var barrel_h  := tp.tip_radius * 1.0
	var barrel_cy := tp.tip_y + tp.tip_radius + barrel_h * 0.5
	var barrel    := MeshInstance3D.new()
	var barrel_m  := CylinderMesh.new()
	barrel_m.top_radius      = tp.tip_radius
	barrel_m.bottom_radius   = tp.tip_radius
	barrel_m.height          = barrel_h
	barrel_m.radial_segments = 12
	barrel_m.material        = mat
	barrel.mesh              = barrel_m
	barrel.position.y        = barrel_cy
	add_child(barrel)

	# ── Tapered shaft connecting barrel to the underside of the disc ──────────
	# disc bottom sits at 0.11 - 0.14/2 = 0.04 — shaft must reach there.
	const DISC_BOTTOM := 0.04
	var barrel_top := barrel_cy + barrel_h * 0.5
	var shaft_len  := maxf(0.01, DISC_BOTTOM - barrel_top)
	var shaft      := MeshInstance3D.new()
	var shaft_m    := CylinderMesh.new()
	shaft_m.top_radius      = 0.035
	shaft_m.bottom_radius   = tp.tip_radius
	shaft_m.height          = shaft_len
	shaft_m.radial_segments = 8
	shaft_m.material        = mat
	shaft.mesh              = shaft_m
	shaft.position.y        = barrel_top + shaft_len * 0.5
	add_child(shaft)


# ── Fusion Wheel (uses BladeData) ─────────────────────────────────────────────
func _build_fusion_wheel() -> void:
	var bd    := _blade()
	var sides := bd.disc_sides

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
	blade_ring_m.top_radius      = bd.blade_radius
	blade_ring_m.bottom_radius   = bd.blade_radius
	blade_ring_m.height          = bd.blade_thickness
	blade_ring_m.material        = blade_ring_mat
	blade_ring.mesh              = blade_ring_m
	blade_ring.position.y        = bd.blade_y
	add_child(blade_ring)
	_flash_mats.append(blade_ring_mat)

	# Smooth outer rim (all current types have blade_len = 0)
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


# ── Energy Ring (uses TrackData) ──────────────────────────────────────────────
func _build_energy_ring() -> void:
	var tr    := _track()
	var sides := _blade().disc_sides

	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color             = tr.ring_color.lightened(0.18)
	ring_mat.metallic                 = 1.0
	ring_mat.roughness                = 0.08
	ring_mat.emission_enabled         = true
	ring_mat.emission                 = tr.ring_color
	ring_mat.emission_energy_multiplier = 2.3

	var ring   := MeshInstance3D.new()
	var ring_m := CylinderMesh.new()
	ring_m.radial_segments = 20
	ring_m.top_radius      = tr.ring_radius
	ring_m.bottom_radius   = tr.ring_radius
	ring_m.height          = 0.20
	ring_m.material        = ring_mat
	ring.mesh              = ring_m
	ring.position.y        = tr.ring_y
	add_child(ring)

	var peg_count := mini(sides, 8)
	var peg_mat   := StandardMaterial3D.new()
	peg_mat.albedo_color             = tr.ring_color.lightened(0.38)
	peg_mat.metallic                 = 1.0
	peg_mat.roughness                = 0.06
	peg_mat.emission_enabled         = true
	peg_mat.emission                 = tr.ring_color.lightened(0.28)
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
		peg.position          = Vector3(cos(angle) * tr.ring_radius, 0.18, sin(angle) * tr.ring_radius)
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


# ── Collision (uses all three parts) ──────────────────────────────────────────
func _build_collision() -> void:
	var bd := _blade()
	var tr := _track()
	var tp := _tip()

	# ── Tip contact sphere ─────────────────────────────────────────────────────
	# Matches _build_performance_tip(): sphere at tp.tip_y, radius tp.tip_radius.
	var tip_col   := CollisionShape3D.new()
	var tip_shape := SphereShape3D.new()
	tip_shape.radius = tp.tip_radius
	tip_col.shape    = tip_shape
	tip_col.position = Vector3(0.0, tp.tip_y, 0.0)
	add_child(tip_col)

	# ── Shaft cylinder ─────────────────────────────────────────────────────────
	# Tapered tube from barrel top up to disc bottom (y = 0.04).
	const DISC_BOTTOM := 0.04
	var barrel_h   := tp.tip_radius * 1.0
	var barrel_top := tp.tip_y + tp.tip_radius + barrel_h
	var shaft_len  := maxf(0.01, DISC_BOTTOM - barrel_top)
	var shaft_col   := CollisionShape3D.new()
	var shaft_shape := CylinderShape3D.new()
	shaft_shape.radius = (0.035 + tp.tip_radius) * 0.5   # averaged taper
	shaft_shape.height = shaft_len
	shaft_col.shape    = shaft_shape
	shaft_col.position = Vector3(0.0, barrel_top + shaft_len * 0.5, 0.0)
	add_child(shaft_col)

	# ── Energy ring ────────────────────────────────────────────────────────────
	# Outer cylinder — radius and height match the energy ring mesh exactly.
	# ring_radius is set per TrackData (Attack 0.27, Defense 0.18, Stamina 0.39).
	var ring_col   := CollisionShape3D.new()
	var ring_shape := CylinderShape3D.new()
	ring_shape.radius = tr.ring_radius   # ← scales with TrackData.ring_radius
	ring_shape.height = 0.20             # matches ring mesh height
	ring_col.shape    = ring_shape
	ring_col.position = Vector3(0.0, tr.ring_y, 0.0)
	add_child(ring_col)
	_ring_col = ring_col                 # stored so clash handler can detect ring hits

	# ── Track body (inner drum) ────────────────────────────────────────────────
	# Narrower inner cylinder sitting inside the energy ring.
	# Scales proportionally with ring_radius; drives track_kb_mult on impact.
	var track_col   := CollisionShape3D.new()
	var track_shape := CylinderShape3D.new()
	track_shape.radius = maxf(0.08, tr.ring_radius * 0.55)  # ← scales with ring_radius
	track_shape.height = 0.28
	track_col.shape    = track_shape
	track_col.position = Vector3(0.0, tr.ring_y - 0.04, 0.0)
	add_child(track_col)
	_track_col = track_col

	# ── Blade disc ─────────────────────────────────────────────────────────────
	# Outer flat disc — radius and thickness from BladeData.
	var disc_col   := CollisionShape3D.new()
	var disc_shape := CylinderShape3D.new()
	disc_shape.radius = bd.blade_radius    # ← scales with BladeData.blade_radius
	disc_shape.height = bd.blade_thickness # ← scales with BladeData.blade_thickness
	disc_col.shape    = disc_shape
	disc_col.position = Vector3(0.0, bd.blade_y, 0.0)
	add_child(disc_col)


func _build_spin_label() -> void:
	_spin_label = Label3D.new()
	_spin_label.text          = "100%"
	_spin_label.font_size     = 48
	_spin_label.modulate      = Color(1.0, 1.0, 0.3)
	_spin_label.billboard     = BaseMaterial3D.BILLBOARD_ENABLED
	_spin_label.no_depth_test = true
	_spin_label.position      = Vector3(0.0, 1.2, 0.0)
	add_child(_spin_label)
