extends SceneTree
## 纹理探针：检查程序化纹理的实际像素值

func _init() -> void:
	var grass := RRTextures.grass()
	print("grass size=", grass.get_size())
	for p in [Vector2i(5, 5), Vector2i(256, 256), Vector2i(300, 100), Vector2i(511, 511)]:
		print("  grass", p, " = ", grass.get_image().get_pixel(p.x, p.y))
	var asphalt := RRTextures.asphalt()
	for p in [Vector2i(5, 5), Vector2i(256, 256)]:
		print("  asphalt", p, " = ", asphalt.get_image().get_pixel(p.x, p.y))
	# 与渲染对照的期望值：#4a7c37 底色
	var expect := Color("#4a7c37")
	print("expect base #4a7c37 = ", expect)
	quit()
