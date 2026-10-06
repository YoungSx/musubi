class_name SurfaceRoute
extends RefCounted
## Local, cached horizontal slices route a grip around a primitive union.
## Queries use the solver's geometry. No knot template or particle edits.
var _grid := AStarGrid2D.new()
var _height := INF
var _radius := 0.0
var _collision_id := 0
var _geometry_revision := -1
var _cell := 0.012
var _origin := Vector2.ZERO
var rebuilds := 0

func advance(start: Vector3,goal: Vector3,budget: float,radius: float,collision: RopeCollision) -> Vector3:
	if budget <= 0: return start
	if collision.is_body_segment_clear(start,goal,radius):
		return start.move_toward(goal,budget)
	if absf(start.y-goal.y) > 0.08:
		return collision.project_point(start.move_toward(goal,budget),radius+0.002)
	var height := (start.y+goal.y)*0.5
	if absf(height-_height) > 0.012 or _radius != radius or _collision_id != collision.get_instance_id() or _geometry_revision != collision.geometry_revision or not _grid.is_in_boundsv(_id(start)) or not _grid.is_in_boundsv(_id(goal)):
		if not _build(start,goal,height,radius,collision): return start
	var from := _nearest(start,collision)
	var to := _nearest(goal,collision)
	if from.x < 0 or to.x < 0: return start
	var path := _grid.get_point_path(from,to)
	for i in range(path.size()-1,-1,-1):
		var waypoint := Vector3(path[i].x,_height,path[i].y)
		if collision.is_body_segment_clear(start,waypoint,radius):
			return start.move_toward(waypoint,budget)
	return start

func _build(start: Vector3,goal: Vector3,height: float,radius: float,collision: RopeCollision) -> bool:
	_cell = maxf(radius,0.012)
	var bounds := collision.get_body_bounds().expand(start).expand(goal).grow(0.15)
	var size := Vector2i(ceili(bounds.size.x/_cell)+1,ceili(bounds.size.z/_cell)+1)
	if size.x > 128 or size.y > 128: return false
	_origin = Vector2(bounds.position.x,bounds.position.z)
	_height = height
	_radius = radius
	_collision_id = collision.get_instance_id()
	_geometry_revision = collision.geometry_revision
	_grid.region = Rect2i(Vector2i.ZERO,size)
	_grid.cell_size = Vector2.ONE*_cell
	_grid.offset = _origin
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	var clearance := radius+_cell*0.25+0.002
	var parts := collision.get_slice_parts(height,clearance)
	for x in size.x:
		for z in size.y:
			var point := Vector3(_origin.x+x*_cell,height,_origin.y+z*_cell)
			var solid := false
			for part in parts:
				if part.bounds.grow(clearance).has_point(point) and part.clearance(point) < clearance:
					solid = true
					break
			_grid.set_point_solid(Vector2i(x,z),solid)
	rebuilds += 1
	return true

func _id(point: Vector3) -> Vector2i:
	return Vector2i(((Vector2(point.x,point.z)-_origin)/_cell).round())

func _nearest(point: Vector3,collision: RopeCollision) -> Vector2i:
	var base := _id(point)
	var result := Vector2i(-1,-1)
	var best := INF
	for x in range(-3,4):
		for y in range(-3,4):
			var cell := base+Vector2i(x,y)
			if not _grid.is_in_boundsv(cell) or _grid.is_point_solid(cell): continue
			var p := _grid.get_point_position(cell)
			var world := Vector3(p.x,_height,p.y)
			var distance := point.distance_squared_to(world)
			if distance < best and collision.is_body_segment_clear(point,world,_radius):
				best = distance
				result = cell
	return result
