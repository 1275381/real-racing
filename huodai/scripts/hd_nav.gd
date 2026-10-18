extends RefCounted
## 烽火地带 —— 步行寻路网格（第四阶段：AI 搜刮者跨图跑箱子/撤离要绕开围墙大院）。
## 1 m 格 AStarGrid2D 覆盖 ±BOUND；障碍判挡与 HDSoldiers._push_out 同口径
## （top ≥ 1.0 且 bot ≤ 1.6 才挡人），按 AGENT_R 外扩——1.8 m 门洞仍留 1 格通道。
## 路径做视线剪枝（网格直线可走就跳过中间点），返回地面坐标点列。
## 无 class_name（新脚本一律 preload）

const CELL := 1.0
const AGENT_R := 0.35            # 人体半径外扩（略小于 MOVE_R 0.4：门洞更宽容，贴墙靠 push_out 滑）
const SNAP_R := 4                # 起终点落在障碍格里时向外找空格的半径（格）

var _g: AStarGrid2D
var _n := 0
var _half := 0.0
var _comp := PackedInt32Array()   # 连通分量编号（-1 = 障碍格）：不连通直接判走不到，
								  # 免得 A* 部分路径把整张图翻一遍（实测 113 ms 卡顿）


func build(world) -> void:
	_half = HDWorld.BOUND
	_n = int(ceil(_half * 2.0 / CELL))
	_g = AStarGrid2D.new()
	_g.region = Rect2i(0, 0, _n, _n)
	_g.cell_size = Vector2(CELL, CELL)
	_g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_g.update()
	for ob in world.obstacles:
		if float(ob.get("top", 3.0)) < 1.0 or float(ob.get("bot", 0.0)) > 1.6:
			continue
		var x0 := float(ob["cx"]) - float(ob["hx"]) - AGENT_R
		var x1 := float(ob["cx"]) + float(ob["hx"]) + AGENT_R
		var z0 := float(ob["cz"]) - float(ob["hz"]) - AGENT_R
		var z1 := float(ob["cz"]) + float(ob["hz"]) + AGENT_R
		var i0 := maxi(0, int(ceil((x0 + _half) / CELL - 0.5)))
		var i1 := mini(_n - 1, int(floor((x1 + _half) / CELL - 0.5)))
		var j0 := maxi(0, int(ceil((z0 + _half) / CELL - 0.5)))
		var j1 := mini(_n - 1, int(floor((z1 + _half) / CELL - 0.5)))
		for i in range(i0, i1 + 1):
			for j in range(j0, j1 + 1):
				_g.set_point_solid(Vector2i(i, j), true)
	_flood()


## 四连通洪泛标连通分量（加载时一次，~8.8 万格）
func _flood() -> void:
	var total := _n * _n
	_comp.resize(total)
	_comp.fill(-2)
	for idx in total:
		if _g.is_point_solid(Vector2i(idx % _n, idx / _n)):
			_comp[idx] = -1
	var q := PackedInt32Array()
	q.resize(total)
	var cid := 0
	for start in total:
		if _comp[start] != -2:
			continue
		var head := 0
		var tail := 0
		q[tail] = start
		tail += 1
		_comp[start] = cid
		while head < tail:
			var c := q[head]
			head += 1
			var cx := c % _n
			var cz := c / _n
			if cx > 0 and _comp[c - 1] == -2:
				_comp[c - 1] = cid
				q[tail] = c - 1
				tail += 1
			if cx < _n - 1 and _comp[c + 1] == -2:
				_comp[c + 1] = cid
				q[tail] = c + 1
				tail += 1
			if cz > 0 and _comp[c - _n] == -2:
				_comp[c - _n] = cid
				q[tail] = c - _n
				tail += 1
			if cz < _n - 1 and _comp[c + _n] == -2:
				_comp[c + _n] = cid
				q[tail] = c + _n
				tail += 1
		cid += 1


## 两点是否步行连通（起终点各自就近吸附到空格后比分量号）
func reachable(from: Vector3, to: Vector3) -> bool:
	if _comp.is_empty():
		return true
	var a := _snap(cell_of(from))
	var b := _snap(cell_of(to))
	var ca := _comp[a.y * _n + a.x]
	return ca >= 0 and ca == _comp[b.y * _n + b.x]


func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(floor((p.x + _half) / CELL)), 0, _n - 1),
			clampi(int(floor((p.z + _half) / CELL)), 0, _n - 1))


func world_of(c: Vector2i) -> Vector3:
	return Vector3(-_half + (float(c.x) + 0.5) * CELL, 0.0, -_half + (float(c.y) + 0.5) * CELL)


func is_free(p: Vector3) -> bool:
	return not _g.is_point_solid(cell_of(p))


## 障碍格就近找空格（容器/首领柜本身是障碍，目标点要落到它旁边）
func _snap(c: Vector2i) -> Vector2i:
	if not _g.is_point_solid(c):
		return c
	for r in range(1, SNAP_R + 1):
		for dx in range(-r, r + 1):
			for dz in [-r, r]:
				var a := Vector2i(c.x + dx, c.y + dz)
				if _g.is_in_boundsv(a) and not _g.is_point_solid(a):
					return a
				var b := Vector2i(c.x + dz, c.y + dx)
				if _g.is_in_boundsv(b) and not _g.is_point_solid(b):
					return b
	return c


## from → to 的步行路径（含终点附近格，不含起点）；走不通返回能走到的最近处（部分路径）
func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	if _g == null:
		return out
	var a := _snap(cell_of(from))
	var b := _snap(cell_of(to))
	if a == b:
		return out
	if not _comp.is_empty() and (_comp[a.y * _n + a.x] < 0 or _comp[a.y * _n + a.x] != _comp[b.y * _n + b.x]):
		return out   # 不连通：调用方按卡路处理（换目标）
	var ids: Array[Vector2i] = _g.get_id_path(a, b, true)
	if ids.size() < 2:
		return out
	# 视线剪枝：从锚点往后找最远一个网格直线可走的点
	var anchor := 0
	var k := 1
	while k < ids.size():
		var far := k
		var m := k + 1
		while m < ids.size() and m - anchor < 40:
			if _clear(ids[anchor], ids[m]):
				far = m
			m += 1
		out.append(world_of(ids[far]))
		anchor = far
		k = far + 1
	return out


## 网格直线是否全空（半格步长采样）
func _clear(a: Vector2i, b: Vector2i) -> bool:
	var d := Vector2(b - a)
	var steps := int(ceil(d.length() * 2.0))
	for t in range(1, steps):
		var p := Vector2(a) + d * (float(t) / float(steps))
		if _g.is_point_solid(Vector2i(int(round(p.x)), int(round(p.y)))):
			return false
	return true
