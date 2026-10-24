extends SceneTree

func _initialize() -> void:
	for id in ["night_sky_2k", "galaxy_detail_2k"]:
		var image := Image.load_from_file("res://assets/" + id + ".exr")
		assert(image != null and not image.is_empty())
		print("SKY_SOURCE ", id, " ", image.get_size())
		if image.get_width() > 2048:
			image.resize(2048, int(image.get_height() * 2048.0 / image.get_width()), Image.INTERPOLATE_LANCZOS)
		# Encode gamma while still floating point; quantizing linear night colors
		# first would crush faint stars and introduce visible dark-sky banding.
		image.convert(Image.FORMAT_RGBF)
		var pixels := image.get_data().to_float32_array()
		for i in pixels.size():
			var value := clampf(pixels[i], 0.0, 1.0)
			pixels[i] = value * 12.92 if value <= .0031308 else 1.055 * pow(value, 1.0 / 2.4) - .055
		image = Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBF, pixels.to_byte_array())
		image.convert(Image.FORMAT_RGB8)
		assert(image.save_png("res://assets/" + id + "_web.png") == OK)
	quit()
