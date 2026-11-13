@tool
class_name BucketLoadVisual
extends MeshInstance3D
## Soil carried in the bucket, drawn in bucket space from BucketSoil.load_shape(). The
## mesh is rebuilt only when the load or the bucket orientation has changed.
##
## The soil profile runs to the tooth tip, but the drawn load stops at the opening from the
## cutting edge to the rim: soil faces running along the teeth would shimmer through them.

const SIDE_CLEARANCE := 0.04
const FILL_TOLERANCE := 0.002
const UP_TOLERANCE := 0.004

var _shown_fill := 0.0
var _shown_up := Vector3.ZERO
var _look := StandardMaterial3D.new()


func _init() -> void:
	name = "SoilLoad"
	_look = MeshKit.material("soil").duplicate()
	material_override = _look


func refresh(bucket_load: BucketSoil) -> void:
	var up := global_transform.basis.inverse() * Vector3.UP
	var emptied := bucket_load.fill <= 1e-4 and _shown_fill > 1e-4
	if not emptied and absf(bucket_load.fill - _shown_fill) < FILL_TOLERANCE and up.distance_to(_shown_up) < UP_TOLERANCE:
		return
	_shown_fill = bucket_load.fill
	_shown_up = up
	_look.albedo_color = bucket_load.material_params(bucket_load.load_material()).loose_color
	var shape := bucket_load.load_shape(global_transform.basis)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var x := bucket_load.params.bucket_width * 0.5 - SIDE_CLEARANCE
	var profile := bucket_load.params.bucket_profile
	var lip := profile[profile.size() - 2]
	var rim := profile[0]
	var opening := (rim - lip).orthogonal().normalized()
	if opening.dot(profile[1] - lip) > 0.0:
		opening = -opening
	for piece in shape["pieces"]:
		MeshKit.add_side_prism(vertices, normals, BucketSoil.clip(piece, opening, opening.dot(lip)), -x, x)
	var ridge: float = shape["heap"]
	if ridge > 0.002:
		_add_heap(vertices, normals, bucket_load, ridge, x)
	mesh = MeshKit.array_mesh(vertices, normals)


## Hip roof over the drawn opening, from the cutting edge to the rim: slopes from both
## sides and both ends up to a ridge along the opening, lifted along the opening normal.
func _add_heap(vertices: PackedVector3Array, normals: PackedVector3Array, bucket_load: BucketSoil, ridge: float,
		x: float) -> void:
	var profile := bucket_load.params.bucket_profile
	var edge := profile[profile.size() - 2]
	var rim := profile[0]
	var along := (rim - edge).normalized()
	var inset := bucket_load.heap_ridge_inset()
	var lift := bucket_load.opening_normal() * ridge
	var ridge_edge := ArmGeometry.to_local(edge + along * inset + lift)
	var ridge_rim := ArmGeometry.to_local(rim - along * inset + lift)
	var inside := ArmGeometry.to_local((edge + rim) * 0.5 - lift)
	var edge_left := ArmGeometry.to_local(edge, -x)
	var edge_right := ArmGeometry.to_local(edge, x)
	var rim_left := ArmGeometry.to_local(rim, -x)
	var rim_right := ArmGeometry.to_local(rim, x)
	MeshKit.add_face(vertices, normals, [edge_left, rim_left, ridge_rim, ridge_edge], inside)
	MeshKit.add_face(vertices, normals, [edge_right, rim_right, ridge_rim, ridge_edge], inside)
	MeshKit.add_face(vertices, normals, [edge_left, edge_right, ridge_edge], inside)
	MeshKit.add_face(vertices, normals, [rim_left, rim_right, ridge_rim], inside)
