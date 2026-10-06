class_name GroundFaces
extends RefCounted
## Planar arrangement of the current rope projection. Split material edges at
## crossings and walk directed faces; a face can involve several material arcs.
## These are passage hypotheses, never claims of full 3D knot classification.
func observe(points: PackedVector3Array,radius: float,floor_y: float) -> Array[Dictionary]:
	var vertices: Array[Vector2] = []
	var cuts: Array[Array] = []
	for p in points: vertices.append(Vector2(p.x,p.z))
	for i in points.size()-1: cuts.append([{ "t":0.0,"node":i },{ "t":1.0,"node":i+1 }])
	for i in points.size()-1:
		for j in range(i+3,points.size()-1):
			var hit: Variant = Geometry2D.segment_intersects_segment(vertices[i],vertices[i+1],vertices[j],vertices[j+1])
			if hit == null: continue
			var p: Vector2 = hit
			var a := _parameter(p,vertices[i],vertices[i+1])
			var b := _parameter(p,vertices[j],vertices[j+1])
			if a < 0.0001 or a > 0.9999 or b < 0.0001 or b > 0.9999: continue
			if maxf(lerpf(points[i].y,points[i+1].y,a),lerpf(points[j].y,points[j+1].y,b)) > floor_y+0.3: continue
			if vertices.size() > points.size()+64: return []
			var node := vertices.size()
			vertices.append(p)
			cuts[i].append({"t":a,"node":node})
			cuts[j].append({"t":b,"node":node})
	var edges: Array[Dictionary] = []
	var outgoing: Array[Array] = []
	for p in vertices: outgoing.append([])
	for i in cuts.size():
		cuts[i].sort_custom(func(a: Dictionary,b: Dictionary): return a.t < b.t)
		for k in cuts[i].size()-1:
			var a: int = cuts[i][k].node
			var b: int = cuts[i][k+1].node
			if vertices[a].distance_squared_to(vertices[b]) < 1e-12: continue
			var id := edges.size()
			edges.append({"a":a,"b":b,"reverse":id+1,"material":i})
			edges.append({"a":b,"b":a,"reverse":id,"material":i})
			outgoing[a].append(id)
			outgoing[b].append(id+1)
	for node in outgoing.size():
		outgoing[node].sort_custom(func(a: int,b: int): return (vertices[edges[a].b]-vertices[node]).angle() < (vertices[edges[b].b]-vertices[node]).angle())
	var visited := {}
	var faces: Array[Dictionary] = []
	for start in edges.size():
		if visited.has(start): continue
		var polygon := PackedVector2Array()
		var materials: Array[int] = []
		var boundary: Array[int] = []
		var edge := start
		while not visited.has(edge):
			visited[edge] = true
			if not boundary.is_empty() and edges[boundary[-1]].reverse == edge:
				boundary.pop_back() # A free tail is a bridge, not a cell wall.
			else:
				boundary.append(edge)
			var next: Array = outgoing[edges[edge].b]
			var back := next.find(edges[edge].reverse)
			edge = next[posmod(back-1,next.size())]
		while boundary.size() >= 2 and edges[boundary[0]].reverse == boundary[-1]:
			boundary.pop_back()
			boundary.pop_front()
		for boundary_edge in boundary:
			polygon.append(vertices[edges[boundary_edge].a])
			materials.append(edges[boundary_edge].material)
		if edge != start or polygon.size() < 3: continue
		var grounded := true
		for material in materials:
			if maxf(points[material].y,points[material+1].y) > floor_y+0.3: grounded = false
		if not grounded: continue
		var area := 0.0
		var center := Vector2.ZERO
		for i in polygon.size():
			var cross := polygon[i].cross(polygon[(i+1)%polygon.size()])
			area += cross
			center += (polygon[i]+polygon[(i+1)%polygon.size()])*cross
		if area < radius*radius*40: continue
		center /= 3*area
		if not Geometry2D.is_point_in_polygon(center,polygon): continue
		materials.sort()
		faces.append({"id":Vector2i(materials[0],materials[-1]),"first":float(materials[0]),"last":float(materials[-1]+1),"polygon":polygon,"center":center,"face":true,"floor_height":floor_y})
	return faces

static func _parameter(p: Vector2,a: Vector2,b: Vector2) -> float:
	return clampf((p-a).dot(b-a)/maxf(a.distance_squared_to(b),1e-10),0,1)
