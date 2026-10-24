extends SceneTree

func _initialize() -> void:
	for id in ["night_sky_2k", "galaxy_detail_2k"]:
		var image := Image.load_from_file("res://assets/" + id + ".exr")
		assert(image != null and not image.is_empty())
		print("SKY_SOURCE ", id, " ", image.get_size())
		if image.get_width() > 2048:
			image.resize(2048, int(image.get_height() * 2048.0 / image.get_width()), Image.INTERPOLATE_LANCZOS)
		image.convert(Image.FORMAT_RGB8)
		image.linear_to_srgb()
		assert(image.save_png("res://assets/" + id + "_web.png") == OK)
	quit()
