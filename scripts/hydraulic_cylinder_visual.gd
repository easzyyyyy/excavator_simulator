@tool
class_name HydraulicCylinderVisual
extends RefCounted
## Barrel and rod of one hydraulic cylinder. Both meshes live under the node
## that carries the base pin; the rod end point is given in that node's space
## every frame, so the rod slides in the barrel instead of stretching.

const ROD_EYE := 0.12
const OVERLAP := 0.10

var barrel: MeshInstance3D
var rod: MeshInstance3D
var barrel_length := 0.0
var rod_length := 0.0


func _init(parent: Node3D, node_name: String, closed_length: float, stroke: float, bore: float) -> void:
	barrel_length = closed_length - ROD_EYE
	rod_length = stroke + ROD_EYE + OVERLAP
	barrel = MeshKit.cylinder(parent, node_name + "Barrel", bore * 0.5 + 0.03, barrel_length, "yellow")
	rod = MeshKit.cylinder(parent, node_name + "Rod", bore * 0.35, rod_length, "chrome")


func update(base_point: Vector3, rod_end_point: Vector3) -> void:
	var axis := rod_end_point - base_point
	if axis.length_squared() < 1e-8:
		return
	var dir := axis.normalized()
	var basis := _basis_along(dir)
	barrel.transform = Transform3D(basis, base_point + dir * barrel_length * 0.5)
	rod.transform = Transform3D(basis, rod_end_point - dir * rod_length * 0.5)


static func _basis_along(dir: Vector3) -> Basis:
	if absf(dir.x) < 1e-4:
		return MeshKit.side_basis_y(dir)
	var reference := Vector3.RIGHT if absf(dir.dot(Vector3.RIGHT)) < 0.95 else Vector3.BACK
	var z := reference.cross(dir).normalized()
	var x := dir.cross(z).normalized()
	return Basis(x, dir, z)
