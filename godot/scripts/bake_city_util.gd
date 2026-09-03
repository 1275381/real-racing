# 由 tools/bake_city.gd 与 tests/test_city_golden.gd 以 preload 引用（不走 class_name，
# 避免依赖编辑器的类缓存 —— headless 下类缓存可能是陈的）
## 烘焙与 golden 断言共用的几何指纹。
## 存全部 44406 个采样点要 1.3MB 不划算；用加权校验和做指纹 ——
## 权重按下标轮转（i%7+1），保证「两点互换位置」也会被检出。
static func csum(vals: Array) -> float:
	var s := 0.0
	for i in vals.size():
		s += float(vals[i]) * float(i % 7 + 1)
	return snappedf(s, 0.0001)
