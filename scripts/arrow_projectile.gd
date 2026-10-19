extends Node3D
class_name ArrowProjectile
## Simple ranged arrow: flies toward a unit, applies pierce damage on arrival.

const Combat := preload("res://scripts/combat.gd")

signal diagnostic_impact(attacker: Node3D, target: Node3D, damage: float, actual_damage: float, hp_before: float, hp_after: float)

var _target: Node3D = null
var _attacker: Node3D = null
var _dmg: float = 8.0
var _speed: float = 28.0
var _life: float = 1.2
var _mesh: MeshInstance3D

func setup(from: Vector3, target: Node3D, dmg: float, attacker: Node3D = null) -> void:
	_target = target
	_attacker = attacker
	_dmg = dmg
	global_position = from
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.08, 0.55)
	_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.75, 0.25)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.15)
	mat.emission_energy_multiplier = 1.4
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh.material_override = mat
	add_child(_mesh)
	add_to_group("arrows")

func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if _target == null or not is_instance_valid(_target) or not Combat.is_alive(_target):
		queue_free()
		return
	var aim: Vector3 = _target.global_position + Vector3(0, 1.0, 0)
	var to: Vector3 = aim - global_position
	var dist: float = to.length()
	if dist < 0.45:
		_hit()
		return
	var step: float = minf(_speed * delta, dist)
	global_position += to.normalized() * step
	# Point arrow along flight
	if to.length_squared() > 0.0001:
		look_at(global_position + to.normalized(), Vector3.UP)

func _hit() -> void:
	if _target != null and is_instance_valid(_target) and _target.has_method("take_damage"):
		var attacker: Node3D = _attacker if is_instance_valid(_attacker) else null
		var hp_before := float(_target.get("hp"))
		_target.call("take_damage", _dmg, true, attacker)
		var hp_after := float(_target.get("hp"))
		diagnostic_impact.emit(attacker, _target, _dmg, maxf(0.0, hp_before-hp_after), hp_before, hp_after)
	queue_free()
