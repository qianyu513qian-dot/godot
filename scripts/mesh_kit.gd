extends RefCounted
class_name MeshKit
## High-quality toy/clay ArrayMeshes — beveled solids, curved pagoda roofs,
## noise-displaced candy canopies, capsule characters. No bare BoxMesh/SphereMesh art.

const SEG_BEVEL := 3
const SEG_ROOF := 14
const SEG_SPH := 12

static func mat(color: Color, roughness: float = 0.28, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	m.clearcoat_enabled = true
	m.clearcoat = 0.42
	m.clearcoat_roughness = 0.22
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	return m

static func _mi(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, roughness: float = 0.28) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat(color, roughness)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

# ─── Core ArrayMesh builders ───────────────────────────────────────────

static func make_bevel_box(size: Vector3, bevel: float = -1.0, seg: int = SEG_BEVEL) -> ArrayMesh:
	## Rounded box: flat faces + cylindrical edges + spherical corners.
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var r := bevel
	if r < 0.0:
		r = minf(minf(hx, hy), hz) * 0.38
	r = minf(r, minf(minf(hx, hy), hz) * 0.49)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 8 corners as octants of a sphere
	var corners := [
		Vector3(hx - r, hy - r, hz - r), Vector3(-(hx - r), hy - r, hz - r),
		Vector3(hx - r, -(hy - r), hz - r), Vector3(-(hx - r), -(hy - r), hz - r),
		Vector3(hx - r, hy - r, -(hz - r)), Vector3(-(hx - r), hy - r, -(hz - r)),
		Vector3(hx - r, -(hy - r), -(hz - r)), Vector3(-(hx - r), -(hy - r), -(hz - r)),
	]
	var sx := [1.0, -1.0, 1.0, -1.0, 1.0, -1.0, 1.0, -1.0]
	var sy := [1.0, 1.0, -1.0, -1.0, 1.0, 1.0, -1.0, -1.0]
	var sz := [1.0, 1.0, 1.0, 1.0, -1.0, -1.0, -1.0, -1.0]
	for ci in 8:
		_add_sphere_octant(st, corners[ci], r, seg, sx[ci], sy[ci], sz[ci])
	# 12 edges as quarter-cylinders
	_add_edge_cyl(st, Vector3(hx - r, hy - r, 0), r, hz - r, seg, Vector3(1, 1, 0), true)   # +x+y along z
	_add_edge_cyl(st, Vector3(-(hx - r), hy - r, 0), r, hz - r, seg, Vector3(-1, 1, 0), true)
	_add_edge_cyl(st, Vector3(hx - r, -(hy - r), 0), r, hz - r, seg, Vector3(1, -1, 0), true)
	_add_edge_cyl(st, Vector3(-(hx - r), -(hy - r), 0), r, hz - r, seg, Vector3(-1, -1, 0), true)
	_add_edge_cyl(st, Vector3(hx - r, 0, hz - r), r, hy - r, seg, Vector3(1, 0, 1), false)  # +x+z along y
	_add_edge_cyl(st, Vector3(-(hx - r), 0, hz - r), r, hy - r, seg, Vector3(-1, 0, 1), false)
	_add_edge_cyl(st, Vector3(hx - r, 0, -(hz - r)), r, hy - r, seg, Vector3(1, 0, -1), false)
	_add_edge_cyl(st, Vector3(-(hx - r), 0, -(hz - r)), r, hy - r, seg, Vector3(-1, 0, -1), false)
	_add_edge_cyl_x(st, Vector3(0, hy - r, hz - r), r, hx - r, seg, Vector3(0, 1, 1))
	_add_edge_cyl_x(st, Vector3(0, -(hy - r), hz - r), r, hx - r, seg, Vector3(0, -1, 1))
	_add_edge_cyl_x(st, Vector3(0, hy - r, -(hz - r)), r, hx - r, seg, Vector3(0, 1, -1))
	_add_edge_cyl_x(st, Vector3(0, -(hy - r), -(hz - r)), r, hx - r, seg, Vector3(0, -1, -1))
	# 6 flat faces (inset by r)
	_add_face_quad(st, Vector3(0, hy, 0), Vector3(hx - r, 0, 0), Vector3(0, 0, hz - r), Vector3.UP)
	_add_face_quad(st, Vector3(0, -hy, 0), Vector3(hx - r, 0, 0), Vector3(0, 0, -hz + r), Vector3.DOWN)
	_add_face_quad(st, Vector3(hx, 0, 0), Vector3(0, hy - r, 0), Vector3(0, 0, hz - r), Vector3.RIGHT)
	_add_face_quad(st, Vector3(-hx, 0, 0), Vector3(0, hy - r, 0), Vector3(0, 0, -hz + r), Vector3.LEFT)
	_add_face_quad(st, Vector3(0, 0, hz), Vector3(hx - r, 0, 0), Vector3(0, hy - r, 0), Vector3(0, 0, 1))
	_add_face_quad(st, Vector3(0, 0, -hz), Vector3(-hx + r, 0, 0), Vector3(0, hy - r, 0), Vector3(0, 0, -1))
	st.generate_normals()
	return st.commit()

static func _add_face_quad(st: SurfaceTool, center: Vector3, ux: Vector3, uz: Vector3, n: Vector3) -> void:
	var p0 := center - ux - uz
	var p1 := center + ux - uz
	var p2 := center + ux + uz
	var p3 := center - ux + uz
	st.set_normal(n)
	st.add_vertex(p0); st.add_vertex(p1); st.add_vertex(p2)
	st.add_vertex(p0); st.add_vertex(p2); st.add_vertex(p3)

static func _add_sphere_octant(st: SurfaceTool, c: Vector3, r: float, seg: int, sx: float, sy: float, sz: float) -> void:
	for i in seg:
		for j in seg:
			var u0 := float(i) / float(seg) * PI * 0.5
			var u1 := float(i + 1) / float(seg) * PI * 0.5
			var v0 := float(j) / float(seg) * PI * 0.5
			var v1 := float(j + 1) / float(seg) * PI * 0.5
			var pts: Array[Vector3] = []
			for uv in [[u0, v0], [u1, v0], [u1, v1], [u0, v1]]:
				var ux: float = uv[0]
				var vx: float = uv[1]
				var dir := Vector3(sx * cos(vx) * cos(ux), sy * sin(vx), sz * cos(vx) * sin(ux))
				pts.append(c + dir * r)
			st.set_normal((pts[0] - c).normalized())
			st.add_vertex(pts[0]); st.add_vertex(pts[1]); st.add_vertex(pts[2])
			st.set_normal((pts[0] - c).normalized())
			st.add_vertex(pts[0]); st.add_vertex(pts[2]); st.add_vertex(pts[3])

static func _add_edge_cyl(st: SurfaceTool, center: Vector3, r: float, half_len: float, seg: int, quad: Vector3, along_z: bool) -> void:
	## quarter-cylinder; quad.xy or xz signs pick the quadrant; along_z=true → axis Z
	var sgn_a := signf(quad.x)
	var sgn_b := signf(quad.y) if along_z else signf(quad.z)
	for i in seg:
		var a0 := float(i) / float(seg) * PI * 0.5
		var a1 := float(i + 1) / float(seg) * PI * 0.5
		var z0 := -half_len
		var z1 := half_len
		var d0a := Vector3(sgn_a * cos(a0), sgn_b * sin(a0), 0) if along_z else Vector3(sgn_a * cos(a0), 0, sgn_b * sin(a0))
		var d1a := Vector3(sgn_a * cos(a1), sgn_b * sin(a1), 0) if along_z else Vector3(sgn_a * cos(a1), 0, sgn_b * sin(a1))
		var p00 := center + d0a * r + (Vector3(0, 0, z0) if along_z else Vector3(0, z0, 0))
		var p10 := center + d1a * r + (Vector3(0, 0, z0) if along_z else Vector3(0, z0, 0))
		var p11 := center + d1a * r + (Vector3(0, 0, z1) if along_z else Vector3(0, z1, 0))
		var p01 := center + d0a * r + (Vector3(0, 0, z1) if along_z else Vector3(0, z1, 0))
		st.set_normal(d0a)
		st.add_vertex(p00); st.add_vertex(p10); st.add_vertex(p11)
		st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p01)

static func _add_edge_cyl_x(st: SurfaceTool, center: Vector3, r: float, half_len: float, seg: int, quad: Vector3) -> void:
	## quarter-cylinder along X; quad.yz signs
	var sgn_y := signf(quad.y)
	var sgn_z := signf(quad.z)
	for i in seg:
		var a0 := float(i) / float(seg) * PI * 0.5
		var a1 := float(i + 1) / float(seg) * PI * 0.5
		var d0 := Vector3(0, sgn_y * cos(a0), sgn_z * sin(a0))
		var d1 := Vector3(0, sgn_y * cos(a1), sgn_z * sin(a1))
		var p00 := center + d0 * r + Vector3(-half_len, 0, 0)
		var p10 := center + d1 * r + Vector3(-half_len, 0, 0)
		var p11 := center + d1 * r + Vector3(half_len, 0, 0)
		var p01 := center + d0 * r + Vector3(half_len, 0, 0)
		st.set_normal(d0)
		st.add_vertex(p00); st.add_vertex(p10); st.add_vertex(p11)
		st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p01)

static func make_soft_sphere(radius: float, seg: int = SEG_SPH, noise_amp: float = 0.12, noise_seed: int = 1) -> ArrayMesh:
	## UV sphere with smooth noise displacement — cotton-candy / clay blob.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := seg
	var radial := seg * 2
	for i in rings:
		var v0 := float(i) / float(rings)
		var v1 := float(i + 1) / float(rings)
		var phi0 := v0 * PI
		var phi1 := v1 * PI
		for j in radial:
			var u0 := float(j) / float(radial)
			var u1 := float(j + 1) / float(radial)
			var th0 := u0 * TAU
			var th1 := u1 * TAU
			var pts: Array[Vector3] = []
			var nrms: Array[Vector3] = []
			for pair in [[phi0, th0], [phi0, th1], [phi1, th1], [phi1, th0]]:
				var phi: float = pair[0]
				var th: float = pair[1]
				var n := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
				var nse := _noise3(n * 3.1 + Vector3(noise_seed, noise_seed * 0.7, noise_seed * 1.3))
				var rr := radius * (1.0 + noise_amp * nse)
				pts.append(n * rr)
				nrms.append(n)
			# two tris; skip degenerate at poles
			if i > 0:
				st.set_normal(nrms[0]); st.add_vertex(pts[0])
				st.set_normal(nrms[1]); st.add_vertex(pts[1])
				st.set_normal(nrms[2]); st.add_vertex(pts[2])
			if i < rings - 1:
				st.set_normal(nrms[0]); st.add_vertex(pts[0])
				st.set_normal(nrms[2]); st.add_vertex(pts[2])
				st.set_normal(nrms[3]); st.add_vertex(pts[3])
	st.generate_normals()
	return st.commit()

static func _noise3(p: Vector3) -> float:
	return sin(p.x * 1.7 + p.y * 2.3) * cos(p.z * 1.9 + p.x * 0.8) * 0.5 + sin(p.y * 3.1 - p.z * 2.2) * 0.25

static func make_capsule(radius: float, height: float, seg: int = 10) -> ArrayMesh:
	## Capsule along Y: cylinder + hemispheres.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cyl_h := maxf(height - radius * 2.0, 0.01)
	var half := cyl_h * 0.5
	# cylinder
	for j in seg * 2:
		var a0 := float(j) / float(seg * 2) * TAU
		var a1 := float(j + 1) / float(seg * 2) * TAU
		var n0 := Vector3(cos(a0), 0, sin(a0))
		var n1 := Vector3(cos(a1), 0, sin(a1))
		var p0b := n0 * radius + Vector3(0, -half, 0)
		var p1b := n1 * radius + Vector3(0, -half, 0)
		var p1t := n1 * radius + Vector3(0, half, 0)
		var p0t := n0 * radius + Vector3(0, half, 0)
		st.set_normal(n0); st.add_vertex(p0b)
		st.set_normal(n1); st.add_vertex(p1b)
		st.set_normal(n1); st.add_vertex(p1t)
		st.set_normal(n0); st.add_vertex(p0b)
		st.set_normal(n1); st.add_vertex(p1t)
		st.set_normal(n0); st.add_vertex(p0t)
	# hemispheres
	for top in [true, false]:
		var y_off := half if top else -half
		var y_sgn := 1.0 if top else -1.0
		for i in seg:
			var v0 := float(i) / float(seg)
			var v1 := float(i + 1) / float(seg)
			var phi0 := v0 * PI * 0.5
			var phi1 := v1 * PI * 0.5
			for j in seg * 2:
				var a0 := float(j) / float(seg * 2) * TAU
				var a1 := float(j + 1) / float(seg * 2) * TAU
				var dirs: Array[Vector3] = []
				for pair in [[phi0, a0], [phi0, a1], [phi1, a1], [phi1, a0]]:
					var ph: float = pair[0]
					var th: float = pair[1]
					dirs.append(Vector3(cos(th) * cos(ph), y_sgn * sin(ph), sin(th) * cos(ph)))
				var pts2: Array[Vector3] = []
				for d in dirs:
					pts2.append(d * radius + Vector3(0, y_off, 0))
				st.set_normal(dirs[0]); st.add_vertex(pts2[0])
				st.set_normal(dirs[1]); st.add_vertex(pts2[1])
				st.set_normal(dirs[2]); st.add_vertex(pts2[2])
				st.set_normal(dirs[0]); st.add_vertex(pts2[0])
				st.set_normal(dirs[2]); st.add_vertex(pts2[2])
				st.set_normal(dirs[3]); st.add_vertex(pts2[3])
	st.generate_normals()
	return st.commit()

static func make_pagoda_roof(width: float, depth: float, height: float, eave_curl: float = 0.35, ridges: int = 8) -> ArrayMesh:
	## Curved East-Asian roof with upturned eaves + ribbed tile strips.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := SEG_ROOF
	var nv := SEG_ROOF
	var hw := width * 0.5
	var hd := depth * 0.5
	for i in nu:
		for j in nv:
			var cells := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]
			var pts: Array[Vector3] = []
			for c in cells:
				var u := float(c[0]) / float(nu) * 2.0 - 1.0
				var v := float(c[1]) / float(nv) * 2.0 - 1.0
				pts.append(_roof_point(u, v, hw, hd, height, eave_curl, ridges))
			var n := (pts[1] - pts[0]).cross(pts[2] - pts[0])
			if n.length_squared() < 1e-10:
				continue
			n = n.normalized()
			# flip if facing down
			if n.y < 0.0:
				n = -n
				st.set_normal(n); st.add_vertex(pts[0]); st.add_vertex(pts[2]); st.add_vertex(pts[1])
				st.set_normal(n); st.add_vertex(pts[0]); st.add_vertex(pts[3]); st.add_vertex(pts[2])
			else:
				st.set_normal(n); st.add_vertex(pts[0]); st.add_vertex(pts[1]); st.add_vertex(pts[2])
				st.set_normal(n); st.add_vertex(pts[0]); st.add_vertex(pts[2]); st.add_vertex(pts[3])
	# underside (slightly inset) for thickness
	var thick := height * 0.18
	for i in nu:
		for j in nv:
			var cells2 := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]
			var pts2: Array[Vector3] = []
			for c in cells2:
				var u := float(c[0]) / float(nu) * 2.0 - 1.0
				var v := float(c[1]) / float(nv) * 2.0 - 1.0
				var p := _roof_point(u, v, hw * 0.96, hd * 0.96, height, eave_curl * 0.8, ridges)
				p.y -= thick
				pts2.append(p)
			st.set_normal(Vector3.DOWN)
			st.add_vertex(pts2[0]); st.add_vertex(pts2[2]); st.add_vertex(pts2[1])
			st.add_vertex(pts2[0]); st.add_vertex(pts2[3]); st.add_vertex(pts2[2])
	st.generate_normals()
	return st.commit()

static func _roof_point(u: float, v: float, hw: float, hd: float, height: float, curl: float, ridges: int) -> Vector3:
	## u,v in [-1,1]. Bold hip roof: high ridge, deep curve, strong eave upturn, chunky tile ribs.
	var au := absf(u)
	var av := absf(v)
	var t := maxf(au, av)
	# Ease: stay high near ridge, drop with soft S-curve, then curl up at eave
	var s := 1.0 - (t * t * (3.0 - 2.0 * t))  # smoothstep inverse feel
	s = pow(maxf(s, 0.0), 0.85)
	var eave := 0.0
	if t > 0.62:
		var et := (t - 0.62) / 0.38
		eave = curl * et * et * (1.2 + 0.4 * et)
	var y := height * s + eave
	# Chunky tile ribs (visible from RTS cam)
	var rib_u := absf(sin(au * float(ridges) * PI))
	var rib_v := absf(sin(av * float(maxi(ridges - 2, 3)) * PI))
	y += (rib_u * 0.10 + rib_v * 0.05) * height * (0.25 + 0.75 * t)
	# Slight flare outward near eave for thick toy silhouette
	var flare := 1.0 + 0.06 * maxf(t - 0.55, 0.0)
	return Vector3(u * hw * flare, y, v * hd * flare)

static func make_taper_cyl(r_top: float, r_bot: float, height: float, seg: int = 14, round_caps: bool = true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := height * 0.5
	for j in seg:
		var a0 := float(j) / float(seg) * TAU
		var a1 := float(j + 1) / float(seg) * TAU
		var n0 := Vector3(cos(a0), 0, sin(a0))
		var n1 := Vector3(cos(a1), 0, sin(a1))
		var p0b := n0 * r_bot + Vector3(0, -half, 0)
		var p1b := n1 * r_bot + Vector3(0, -half, 0)
		var p1t := n1 * r_top + Vector3(0, half, 0)
		var p0t := n0 * r_top + Vector3(0, half, 0)
		var nn0 := Vector3(n0.x, (r_bot - r_top) / height, n0.z).normalized()
		var nn1 := Vector3(n1.x, (r_bot - r_top) / height, n1.z).normalized()
		st.set_normal(nn0); st.add_vertex(p0b)
		st.set_normal(nn1); st.add_vertex(p1b)
		st.set_normal(nn1); st.add_vertex(p1t)
		st.set_normal(nn0); st.add_vertex(p0b)
		st.set_normal(nn1); st.add_vertex(p1t)
		st.set_normal(nn0); st.add_vertex(p0t)
	if round_caps:
		# soft dome caps
		for top in [false, true]:
			var y0 := -half if not top else half
			var rad := r_bot if not top else r_top
			var y_sgn := -1.0 if not top else 1.0
			for i in 4:
				var v0 := float(i) / 4.0
				var v1 := float(i + 1) / 4.0
				var phi0 := v0 * PI * 0.5
				var phi1 := v1 * PI * 0.5
				for j in seg:
					var a0 := float(j) / float(seg) * TAU
					var a1 := float(j + 1) / float(seg) * TAU
					var dirs: Array[Vector3] = []
					for pair in [[phi0, a0], [phi0, a1], [phi1, a1], [phi1, a0]]:
						var ph: float = pair[0]
						var th: float = pair[1]
						dirs.append(Vector3(cos(th) * cos(ph), y_sgn * sin(ph), sin(th) * cos(ph)))
					var rr := rad * 0.35
					for k in 3:
						st.set_normal(dirs[k])
						st.add_vertex(dirs[k] * rr + Vector3(0, y0, 0))
					st.set_normal(dirs[0]); st.add_vertex(dirs[0] * rr + Vector3(0, y0, 0))
					st.set_normal(dirs[2]); st.add_vertex(dirs[2] * rr + Vector3(0, y0, 0))
					st.set_normal(dirs[3]); st.add_vertex(dirs[3] * rr + Vector3(0, y0, 0))
	st.generate_normals()
	return st.commit()

# ─── Convenience adders (ArrayMesh only — no BoxMesh/SphereMesh) ───────

static func add_box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, roughness: float = 0.28) -> MeshInstance3D:
	var bevel := minf(minf(size.x, size.y), size.z) * 0.32
	return _mi(parent, make_bevel_box(size, bevel), pos, color, roughness)

static func add_cyl(parent: Node3D, r_top: float, r_bot: float, height: float, pos: Vector3, color: Color, roughness: float = 0.28) -> MeshInstance3D:
	return _mi(parent, make_taper_cyl(r_top, r_bot, height, 16, true), pos, color, roughness)

static func add_sphere(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color, roughness: float = 0.30) -> MeshInstance3D:
	var mesh := make_soft_sphere(radius, 10, 0.06, int(radius * 100) + 3)
	var mi := _mi(parent, mesh, pos, color, roughness)
	# squash to requested height if different
	if height > 0.01 and absf(height - radius * 2.0) > 0.05:
		mi.scale = Vector3(1.0, height / (radius * 2.0), 1.0)
	return mi

static func add_prism(parent: Node3D, size: Vector3, pos: Vector3, color: Color, roughness: float = 0.26) -> MeshInstance3D:
	## Prism slots used as roofs → curved pagoda roof instead of sharp PrismMesh.
	return _mi(parent, make_pagoda_roof(size.x, size.z, size.y, size.y * 0.28, 7), pos, color, roughness)

static func add_roof(parent: Node3D, width: float, depth: float, height: float, pos: Vector3, color: Color, curl: float = -1.0) -> MeshInstance3D:
	var c := height * 0.42 if curl < 0.0 else curl
	var mi := _mi(parent, make_pagoda_roof(width, depth, height, c, 9), pos, color, 0.22)
	var m: StandardMaterial3D = mi.material_override as StandardMaterial3D
	if m:
		m = m.duplicate()
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = color
		mi.material_override = m
	return mi

static func add_candy(parent: Node3D, radius: float, pos: Vector3, color: Color, noise_seed: int = 1) -> MeshInstance3D:
	return _mi(parent, make_soft_sphere(radius, 14, 0.20, noise_seed), pos, color, 0.30)

static func add_capsule(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color, roughness: float = 0.28) -> MeshInstance3D:
	return _mi(parent, make_capsule(radius, height, 10), pos, color, roughness)

# ─── Buildings ─────────────────────────────────────────────────────────

static func build_town_center(parent: Node3D, size: Vector3) -> void:
	var wood := Color(0.78, 0.52, 0.30)
	var plaster := Color(0.97, 0.95, 0.91)
	var roof_blue := Color(0.12, 0.38, 1.0)
	var roof_red := Color(1.0, 0.12, 0.10)
	var stone := Color(0.82, 0.76, 0.64)
	var gold := Color(0.98, 0.82, 0.28)
	# Podium — stacked bevel discs via short bevel boxes + taper
	add_cyl(parent, size.x * 0.52, size.x * 0.56, 0.50, Vector3(0, 0.26, 0), stone, 0.40)
	add_cyl(parent, size.x * 0.46, size.x * 0.49, 0.30, Vector3(0, 0.68, 0), Color(0.74, 0.68, 0.56), 0.38)
	var hall_h := size.y * 0.50
	add_box(parent, Vector3(size.x * 0.68, hall_h, size.z * 0.50), Vector3(0, 0.9 + hall_h * 0.5, 0), plaster, 0.26)
	# Thick wood beams (beveled)
	add_box(parent, Vector3(size.x * 0.72, 0.26, size.z * 0.54), Vector3(0, 0.9 + hall_h * 0.08, 0), wood, 0.32)
	add_box(parent, Vector3(size.x * 0.72, 0.22, size.z * 0.54), Vector3(0, 0.9 + hall_h * 0.90, 0), wood, 0.32)
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			add_cyl(parent, 0.30, 0.34, hall_h * 0.92, Vector3(x * size.x * 0.26, 0.9 + hall_h * 0.45, z * size.z * 0.16), wood, 0.32)
	var wing_h := size.y * 0.34
	add_box(parent, Vector3(size.x * 0.28, wing_h, size.z * 0.44), Vector3(-size.x * 0.38, 0.9 + wing_h * 0.5, 0), plaster, 0.26)
	add_box(parent, Vector3(size.x * 0.28, wing_h, size.z * 0.44), Vector3(size.x * 0.38, 0.9 + wing_h * 0.5, 0), plaster, 0.26)
	var roof_y := 0.9 + hall_h
	add_roof(parent, size.x * 1.05, size.z * 0.88, size.y * 0.48, Vector3(0, roof_y + 0.02, 0), roof_blue, size.y * 0.38)
	add_roof(parent, size.x * 0.68, size.z * 0.55, size.y * 0.32, Vector3(0, roof_y + size.y * 0.38, 0), roof_red, size.y * 0.26)
	add_roof(parent, size.x * 0.40, size.z * 0.62, size.y * 0.22, Vector3(-size.x * 0.38, 0.9 + wing_h + 0.02, 0), roof_blue, size.y * 0.18)
	add_roof(parent, size.x * 0.40, size.z * 0.62, size.y * 0.22, Vector3(size.x * 0.38, 0.9 + wing_h + 0.02, 0), roof_red, size.y * 0.18)
	add_box(parent, Vector3(size.x * 0.36, 0.22, size.z * 0.24), Vector3(0, 0.95, size.z * 0.42), stone, 0.38)
	var ridge := add_cyl(parent, 0.14, 0.14, size.x * 0.40, Vector3(0, roof_y + size.y * 0.48, 0), gold, 0.20)
	ridge.rotation_degrees = Vector3(0, 0, 90)
	add_candy(parent, 0.26, Vector3(0, roof_y + size.y * 0.55, 0), gold, 9)

static func build_house(parent: Node3D, size: Vector3) -> void:
	var plaster := Color(0.97, 0.95, 0.90)
	var wood := Color(0.72, 0.48, 0.28)
	var thatch := Color(0.90, 0.70, 0.36)
	var roof_red := Color(0.93, 0.20, 0.16)
	var stone := Color(0.80, 0.74, 0.62)
	add_cyl(parent, size.x * 0.56, size.x * 0.58, 0.26, Vector3(0, 0.13, 0), stone, 0.40)
	add_box(parent, Vector3(size.x * 0.86, size.y * 0.66, size.z * 0.80), Vector3(0, 0.28 + size.y * 0.33, 0), plaster, 0.26)
	add_box(parent, Vector3(size.x * 0.90, 0.18, size.z * 0.84), Vector3(0, 0.28 + size.y * 0.08, 0), wood, 0.32)
	add_box(parent, Vector3(size.x * 0.90, 0.16, size.z * 0.84), Vector3(0, 0.28 + size.y * 0.64, 0), wood, 0.32)
	add_box(parent, Vector3(size.x * 0.22, size.y * 0.38, 0.14), Vector3(0, 0.28 + size.y * 0.26, size.z * 0.41), wood, 0.30)
	add_box(parent, Vector3(0.46, 0.46, 0.1), Vector3(-size.x * 0.26, 0.28 + size.y * 0.42, size.z * 0.41), Color(0.55, 0.80, 0.96), 0.20)
	add_box(parent, Vector3(0.46, 0.46, 0.1), Vector3(size.x * 0.26, 0.28 + size.y * 0.42, size.z * 0.41), Color(0.55, 0.80, 0.96), 0.20)
	add_roof(parent, size.x * 1.18, size.z * 1.12, size.y * 0.55, Vector3(0, 0.28 + size.y * 0.68, 0), roof_red, size.y * 0.32)
	add_roof(parent, size.x * 0.72, size.z * 0.70, size.y * 0.22, Vector3(0, 0.28 + size.y * 1.05, 0), Color(0.12, 0.38, 1.0), size.y * 0.14)
	add_cyl(parent, 0.26, 0.30, 0.80, Vector3(size.x * 0.26, 0.28 + size.y * 0.95, -size.z * 0.12), Color(0.72, 0.64, 0.55), 0.36)

static func build_relay(parent: Node3D, size: Vector3) -> void:
	var wood := Color(0.72, 0.50, 0.30)
	var cloth := Color(0.96, 0.58, 0.24)
	var stone := Color(0.80, 0.74, 0.60)
	add_cyl(parent, size.x * 0.52, size.x * 0.56, 0.20, Vector3(0, 0.10, 0), stone, 0.40)
	add_cyl(parent, 0.30, 0.36, size.y * 0.85, Vector3(0, size.y * 0.45, 0), wood, 0.30)
	add_cyl(parent, size.x * 0.40, size.x * 0.42, 0.20, Vector3(0, size.y * 0.55, 0), wood, 0.32)
	add_cyl(parent, 0.36, 0.20, 0.50, Vector3(0, size.y * 0.85, 0), cloth, 0.26)
	add_candy(parent, 0.34, Vector3(0, size.y * 1.08, 0), Color(1.0, 0.90, 0.38), 4)
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			add_cyl(parent, 0.12, 0.14, size.y * 0.48, Vector3(x * size.x * 0.30, size.y * 0.28, z * size.z * 0.30), wood, 0.32)

static func build_wall_segment(parent: Node3D, size: Vector3) -> void:
	var plaster := Color(0.95, 0.93, 0.88)
	var stone := Color(0.84, 0.80, 0.72)
	var dark := Color(0.66, 0.58, 0.48)
	add_box(parent, Vector3(size.x, size.y * 0.80, size.z * 0.92), Vector3(0, size.y * 0.40, 0), plaster, 0.32)
	add_box(parent, Vector3(size.x * 1.02, 0.26, size.z * 1.02), Vector3(0, size.y * 0.10, 0), stone, 0.38)
	for i in 4:
		var t := (float(i) + 0.5) / 4.0 - 0.5
		add_cyl(parent, size.z * 0.26, size.z * 0.28, size.y * 0.26, Vector3(t * size.x, size.y * 0.95, 0), dark, 0.34)

static func build_farm_extra_posts(parent: Node3D, size: Vector3) -> void:
	var wood := Color(0.70, 0.48, 0.28)
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			add_cyl(parent, 0.10, 0.12, size.y + 0.55, Vector3(x * size.x * 0.48, (size.y + 0.55) * 0.5, z * size.z * 0.48), wood, 0.34)

static func build_gate(parent: Node3D, size: Vector3) -> void:
	var stone := Color(0.82, 0.76, 0.66)
	var wood := Color(0.90, 0.55, 0.24)
	var wood_dark := Color(0.58, 0.34, 0.16)
	var iron := Color(0.48, 0.45, 0.42)
	var roof := Color(0.93, 0.18, 0.14)
	var plaster := Color(0.96, 0.94, 0.90)
	var tl := add_cyl(parent, size.x * 0.16, size.x * 0.18, size.y, Vector3(-size.x * 0.36, size.y * 0.5, 0), stone, 0.34)
	tl.name = "GateTowerL"
	add_box(parent, Vector3(size.x * 0.24, size.y * 0.90, size.z * 0.88), Vector3(-size.x * 0.36, size.y * 0.48, 0), plaster, 0.28)
	var tr := add_cyl(parent, size.x * 0.16, size.x * 0.18, size.y, Vector3(size.x * 0.36, size.y * 0.5, 0), stone, 0.34)
	tr.name = "GateTowerR"
	add_box(parent, Vector3(size.x * 0.24, size.y * 0.90, size.z * 0.88), Vector3(size.x * 0.36, size.y * 0.48, 0), plaster, 0.28)
	add_box(parent, Vector3(size.x * 0.52, size.y * 0.26, size.z * 0.82), Vector3(0, size.y * 0.78, 0), Color(0.58, 0.44, 0.30), 0.32)
	add_roof(parent, size.x * 0.72, size.z * 1.05, size.y * 0.18, Vector3(0, size.y * 0.95, 0), roof, size.y * 0.10)
	var leaf_w: float = size.x * 0.22
	var leaf_h: float = size.y * 0.68
	var leaf_t: float = 0.42
	var hinge_x: float = size.x * 0.235
	var hinge_l := Node3D.new()
	hinge_l.name = "GateHingeL"
	hinge_l.position = Vector3(-hinge_x, size.y * 0.38, 0.0)
	parent.add_child(hinge_l)
	var dl := add_box(hinge_l, Vector3(leaf_w, leaf_h, leaf_t), Vector3(leaf_w * 0.5, 0, 0), wood, 0.28)
	dl.name = "GateDoorL"
	var dlm: StandardMaterial3D = dl.material_override as StandardMaterial3D
	if dlm:
		dlm = dlm.duplicate()
		dlm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dlm.albedo_color = Color(0.96, 0.60, 0.24)
		dl.material_override = dlm
	add_box(hinge_l, Vector3(leaf_w * 0.92, 0.12, leaf_t + 0.04), Vector3(leaf_w * 0.5, leaf_h * 0.28, 0), iron, 0.32)
	add_box(hinge_l, Vector3(leaf_w * 0.92, 0.12, leaf_t + 0.04), Vector3(leaf_w * 0.5, -leaf_h * 0.22, 0), iron, 0.32)
	add_box(hinge_l, Vector3(0.1, leaf_h * 0.85, leaf_t + 0.05), Vector3(leaf_w * 0.78, 0, 0), wood_dark, 0.32)
	var hinge_r := Node3D.new()
	hinge_r.name = "GateHingeR"
	hinge_r.position = Vector3(hinge_x, size.y * 0.38, 0.0)
	parent.add_child(hinge_r)
	var dr := add_box(hinge_r, Vector3(leaf_w, leaf_h, leaf_t), Vector3(-leaf_w * 0.5, 0, 0), wood, 0.28)
	dr.name = "GateDoorR"
	var drm: StandardMaterial3D = dr.material_override as StandardMaterial3D
	if drm:
		drm = drm.duplicate()
		drm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		drm.albedo_color = Color(0.96, 0.60, 0.24)
		dr.material_override = drm
	add_box(hinge_r, Vector3(leaf_w * 0.92, 0.12, leaf_t + 0.04), Vector3(-leaf_w * 0.5, leaf_h * 0.28, 0), iron, 0.32)
	add_box(hinge_r, Vector3(leaf_w * 0.92, 0.12, leaf_t + 0.04), Vector3(-leaf_w * 0.5, -leaf_h * 0.22, 0), iron, 0.32)
	add_box(hinge_r, Vector3(0.1, leaf_h * 0.85, leaf_t + 0.05), Vector3(-leaf_w * 0.78, 0, 0), wood_dark, 0.32)
	var closed := Node3D.new()
	closed.name = "GateClosed"
	closed.visible = false
	parent.add_child(closed)
	add_cyl(parent, size.x * 0.12, size.x * 0.14, size.y * 0.20, Vector3(-size.x * 0.36, size.y + 0.08, 0), Color(0.58, 0.44, 0.30), 0.32)
	add_cyl(parent, size.x * 0.12, size.x * 0.14, size.y * 0.20, Vector3(size.x * 0.36, size.y + 0.08, 0), Color(0.58, 0.44, 0.30), 0.32)

static func build_arrow_tower(parent: Node3D, size: Vector3) -> void:
	var stone := Color(0.82, 0.78, 0.68)
	var wood := Color(0.70, 0.46, 0.28)
	var plaster := Color(0.96, 0.94, 0.90)
	var roof := Color(0.16, 0.40, 0.95)
	add_cyl(parent, size.x * 0.52, size.x * 0.56, 0.34, Vector3(0, 0.17, 0), stone, 0.38)
	add_cyl(parent, size.x * 0.38, size.x * 0.42, size.y * 0.72, Vector3(0, 0.38 + size.y * 0.36, 0), plaster, 0.28)
	add_box(parent, Vector3(size.x * 0.98, 0.22, size.z * 0.98), Vector3(0, size.y * 0.78, 0), wood, 0.30)
	for x in [-1.0, 0.0, 1.0]:
		for z in [-1.0, 1.0]:
			if absf(x) < 0.1 and absf(z) < 0.1:
				continue
			add_cyl(parent, 0.20, 0.22, 0.50, Vector3(x * size.x * 0.34, size.y * 0.92, z * size.z * 0.34), Color(0.62, 0.50, 0.36), 0.32)
	add_roof(parent, size.x * 0.82, size.z * 0.82, size.y * 0.26, Vector3(0, size.y * 1.05, 0), roof, size.y * 0.14)

static func build_scout_camp(parent: Node3D, size: Vector3) -> void:
	var canvas := Color(0.96, 0.80, 0.45)
	var wood := Color(0.70, 0.46, 0.28)
	var pole := Color(0.62, 0.42, 0.24)
	add_cyl(parent, size.x * 0.52, size.x * 0.55, 0.16, Vector3(0, 0.08, 0), Color(0.76, 0.60, 0.40), 0.40)
	add_box(parent, Vector3(size.x * 0.70, size.y * 0.40, size.z * 0.66), Vector3(0, size.y * 0.28, 0), canvas, 0.30)
	add_roof(parent, size.x * 0.90, size.z * 0.84, size.y * 0.38, Vector3(0, size.y * 0.55, 0), Color(0.94, 0.58, 0.24), size.y * 0.16)
	add_cyl(parent, 0.09, 0.11, size.y * 0.88, Vector3(-size.x * 0.34, size.y * 0.45, size.z * 0.28), pole, 0.32)
	add_cyl(parent, 0.09, 0.11, size.y * 0.88, Vector3(size.x * 0.34, size.y * 0.45, size.z * 0.28), pole, 0.32)
	add_box(parent, Vector3(1.10, 0.72, 0.92), Vector3(size.x * 0.28, 0.48, -size.z * 0.28), wood, 0.30)

static func build_attack_barracks(parent: Node3D, size: Vector3) -> void:
	var plaster := Color(0.96, 0.90, 0.84)
	var wood := Color(0.68, 0.42, 0.24)
	var roof := Color(0.93, 0.16, 0.12)
	add_cyl(parent, size.x * 0.52, size.x * 0.56, 0.26, Vector3(0, 0.13, 0), Color(0.76, 0.68, 0.56), 0.38)
	add_box(parent, Vector3(size.x * 0.86, size.y * 0.60, size.z * 0.80), Vector3(0, 0.28 + size.y * 0.30, 0), plaster, 0.26)
	add_box(parent, Vector3(size.x * 0.90, 0.16, size.z * 0.84), Vector3(0, 0.28 + size.y * 0.08, 0), wood, 0.32)
	add_box(parent, Vector3(size.x * 0.14, size.y * 0.46, size.z * 0.50), Vector3(-size.x * 0.38, 0.28 + size.y * 0.28, 0), wood, 0.30)
	add_roof(parent, size.x * 1.08, size.z * 1.00, size.y * 0.34, Vector3(0, 0.28 + size.y * 0.68, 0), roof, size.y * 0.16)
	add_cyl(parent, 0.08, 0.10, size.y * 0.82, Vector3(size.x * 0.40, size.y * 0.55, size.z * 0.34), wood, 0.30)
	add_box(parent, Vector3(0.70, 0.52, 0.1), Vector3(size.x * 0.40 + 0.36, size.y * 0.85, size.z * 0.34), Color(0.96, 0.26, 0.18), 0.26)

static func build_defend_garrison(parent: Node3D, size: Vector3) -> void:
	var stone := Color(0.80, 0.82, 0.88)
	var wood := Color(0.64, 0.44, 0.26)
	var roof := Color(0.16, 0.40, 0.95)
	add_cyl(parent, size.x * 0.54, size.x * 0.56, 0.30, Vector3(0, 0.15, 0), Color(0.72, 0.68, 0.58), 0.38)
	add_box(parent, Vector3(size.x * 0.82, size.y * 0.66, size.z * 0.82), Vector3(0, 0.32 + size.y * 0.33, 0), stone, 0.30)
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			add_cyl(parent, 0.55, 0.58, size.y * 0.82, Vector3(x * size.x * 0.34, size.y * 0.48, z * size.z * 0.34), stone.darkened(0.04), 0.30)
	add_roof(parent, size.x * 1.00, size.z * 1.00, size.y * 0.28, Vector3(0, 0.32 + size.y * 0.76, 0), roof, size.y * 0.14)
	add_box(parent, Vector3(0.88, 0.96, 0.14), Vector3(0, size.y * 0.55, size.z * 0.42), wood, 0.30)

# ─── Trees / resources / characters ────────────────────────────────────

static func build_candy_tree(parent: Node3D) -> void:
	add_cyl(parent, 0.28, 0.48, 3.0, Vector3(0, 1.5, 0), Color(0.74, 0.50, 0.30), 0.36)
	add_cyl(parent, 0.40, 0.58, 0.45, Vector3(0, 0.22, 0), Color(0.64, 0.42, 0.24), 0.40)
	var candy := [
		Color(0.96, 0.42, 0.72), Color(0.70, 0.40, 0.96), Color(1.0, 0.55, 0.26),
		Color(0.98, 0.62, 0.80), Color(0.55, 0.78, 0.38),
	]
	var offsets := [
		Vector3(0, 4.0, 0), Vector3(0.9, 3.5, 0.4), Vector3(-0.85, 3.55, -0.35),
		Vector3(0.2, 3.2, 0.9), Vector3(-0.35, 3.7, 0.7),
	]
	var radii := [2.05, 1.55, 1.45, 1.30, 1.25]
	for i in candy.size():
		add_candy(parent, radii[i], offsets[i], candy[i], 11 + i * 3)

static func build_toy_villager(parent: Node3D) -> void:
	var cloth := Color(0.28, 0.58, 0.95)
	var skin := Color(0.97, 0.80, 0.64)
	var pants := Color(0.38, 0.40, 0.50)
	var hat_c := Color(0.96, 0.74, 0.30)
	add_capsule(parent, 0.11, 0.48, Vector3(-0.13, 0.26, 0), pants, 0.32)
	add_capsule(parent, 0.11, 0.48, Vector3(0.13, 0.26, 0), pants, 0.32)
	add_capsule(parent, 0.30, 0.72, Vector3(0, 0.78, 0), cloth, 0.26)
	add_capsule(parent, 0.08, 0.40, Vector3(-0.34, 0.78, 0), cloth.darkened(0.05), 0.28)
	add_capsule(parent, 0.08, 0.40, Vector3(0.34, 0.78, 0), cloth.darkened(0.05), 0.28)
	add_candy(parent, 0.24, Vector3(0, 1.30, 0), skin, 2)
	add_cyl(parent, 0.04, 0.40, 0.18, Vector3(0, 1.52, 0), hat_c, 0.26)

static func build_toy_soldier(parent: Node3D, team: String, is_zombie: bool) -> void:
	var body_c: Color
	var helm_c: Color
	if is_zombie:
		body_c = Color(0.45, 0.75, 0.38)
		helm_c = Color(0.58, 0.65, 0.40)
	elif team == "enemy":
		body_c = Color(1.0, 0.28, 0.90)
		helm_c = Color(1.0, 0.90, 0.28)
	else:
		body_c = Color(0.90, 0.28, 0.22)
		helm_c = Color(0.78, 0.82, 0.90)
	var body_h := 1.25 if team != "enemy" else 1.40
	var body_r := 0.38 if team != "enemy" else 0.44
	add_capsule(parent, body_r, body_h, Vector3(0, body_h * 0.5, 0), body_c, 0.26)
	add_candy(parent, 0.30 if team != "enemy" else 0.34, Vector3(0, body_h + 0.12, 0), helm_c, 5)
