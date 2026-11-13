@tool
class_name MeshKit
extends RefCounted
## Small helpers to build primitive placeholder geometry. Every generated node is
## left without an owner so that @tool previews are never saved into scenes.

static var _materials := {}


static func material(key: String) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	match key:
		"yellow":
			mat.albedo_color = Color(0.93, 0.66, 0.07)
			mat.roughness = 0.55
		"black":
			mat.albedo_color = Color(0.07, 0.07, 0.08)
			mat.roughness = 0.7
		"track":
			mat.albedo_color = Color(0.13, 0.12, 0.11)
			mat.roughness = 0.9
		"steel":
			mat.albedo_color = Color(0.35, 0.36, 0.38)
			mat.metallic = 0.8
			mat.roughness = 0.45
		"chrome":
			mat.albedo_color = Color(0.85, 0.86, 0.88)
			mat.metallic = 1.0
			mat.roughness = 0.12
		"seat":
			mat.albedo_color = Color(0.1, 0.1, 0.11)
			mat.roughness = 0.95
		"knob":
			mat.albedo_color = Color(0.05, 0.05, 0.05)
			mat.roughness = 0.4
		"screen":
			mat.albedo_color = Color(0.05, 0.12, 0.16)
			mat.emission_enabled = true
			mat.emission = Color(0.1, 0.3, 0.4)
			mat.emission_energy_multiplier = 0.6
		"truck_cab":
			mat.albedo_color = Color(0.88, 0.88, 0.85)
			mat.roughness = 0.45
		"truck_body":
			mat.albedo_color = Color(0.62, 0.16, 0.1)
			mat.roughness = 0.6
		"rubber":
			mat.albedo_color = Color(0.06, 0.06, 0.06)
			mat.roughness = 0.9
		"dark_glass":
			mat.albedo_color = Color(0.08, 0.1, 0.12)
			mat.roughness = 0.1
			mat.metallic_specular = 0.8
		"soil":
			mat.albedo_color = Color(0.29, 0.22, 0.15)
			mat.roughness = 1.0
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		"glass":
			mat.albedo_color = Color(0.75, 0.85, 0.9, 0.07)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.roughness = 0.05
			mat.metallic_specular = 0.8
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_:
			mat.albedo_color = Color.MAGENTA
	_materials[key] = mat
	return mat


static func box(parent: Node3D, node_name: String, size: Vector3, position: Vector3, mat_key: String) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _instance(parent, node_name, mesh, Transform3D(Basis.IDENTITY, position), mat_key)


## Box whose length runs from a to b. Both points must share the same x
## (side-plane segment); width is along x and height along the plane normal.
static func beam(parent: Node3D, node_name: String, a: Vector3, b: Vector3, width: float, height: float,
		mat_key: String, extend := 0.0) -> MeshInstance3D:
	var dir := (b - a).normalized()
	var length := a.distance_to(b) + extend * 2.0
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, height, length)
	return _instance(parent, node_name, mesh, Transform3D(side_basis_z(dir), (a + b) * 0.5), mat_key)


static func cylinder(parent: Node3D, node_name: String, radius: float, length: float, mat_key: String) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 16
	mesh.rings = 1
	return _instance(parent, node_name, mesh, Transform3D.IDENTITY, mat_key)


## Pin boss: a short cylinder along x.
static func pin(parent: Node3D, node_name: String, position: Vector3, radius: float, width: float, mat_key := "steel") -> MeshInstance3D:
	var node := cylinder(parent, node_name, radius, width, mat_key)
	node.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5), position)
	return node


## Appends a flat convex face, wound so its front and normal face away from inside.
static func add_face(vertices: PackedVector3Array, normals: PackedVector3Array, corners: Array,
		inside: Vector3) -> void:
	if corners.size() < 3:
		return
	var a: Vector3 = corners[0]
	var second: Vector3 = corners[1]
	var third: Vector3 = corners[2]
	var last: Vector3 = corners[corners.size() - 1]
	var normal := (second - a).cross(third - a)
	if normal.length_squared() < 1e-14:
		normal = (third - a).cross(last - a)
	if normal.length_squared() < 1e-14:
		return
	# Godot front faces are clockwise seen from the front: reverse when the right-hand
	# normal points outward.
	var reverse := normal.dot(a - inside) > 0.0
	normal = normal.normalized() * (1.0 if reverse else -1.0)
	for i in range(1, corners.size() - 1):
		var b: Vector3 = corners[i]
		var c: Vector3 = corners[i + 1]
		if reverse:
			vertices.append_array([a, c, b])
		else:
			vertices.append_array([a, b, c])
		normals.append_array([normal, normal, normal])


## Appends a convex side-plane polygon (u, v) extruded across x from x0 to x1.
static func add_side_prism(vertices: PackedVector3Array, normals: PackedVector3Array,
		polygon: PackedVector2Array, x0: float, x1: float) -> void:
	var count := polygon.size()
	if count < 3:
		return
	var centroid := Vector2.ZERO
	for point in polygon:
		centroid += point / count
	var inside := ArmGeometry.to_local(centroid, (x0 + x1) * 0.5)
	var near_cap := []
	var far_cap := []
	for point in polygon:
		near_cap.append(ArmGeometry.to_local(point, x0))
		far_cap.append(ArmGeometry.to_local(point, x1))
	add_face(vertices, normals, near_cap, inside)
	add_face(vertices, normals, far_cap, inside)
	for i in count:
		var j := (i + 1) % count
		add_face(vertices, normals, [near_cap[i], near_cap[j], far_cap[j], far_cap[i]], inside)


static func array_mesh(vertices: PackedVector3Array, normals: PackedVector3Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if vertices.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Basis with local -Z along dir and local X kept on the joint axis.
static func side_basis_z(dir: Vector3) -> Basis:
	var z := -dir.normalized()
	var x := Vector3.RIGHT
	var y := z.cross(x)
	return Basis(x, y, z)


## Basis with local +Y along dir and local X kept on the joint axis.
static func side_basis_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := Vector3.RIGHT
	var z := x.cross(y)
	return Basis(x, y, z)


static func _instance(parent: Node3D, node_name: String, mesh: Mesh, xform: Transform3D, mat_key: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material(mat_key)
	node.transform = xform
	if mat_key == "glass":
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node
