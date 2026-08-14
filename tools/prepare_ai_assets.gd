extends SceneTree


const PLANT_CANVAS_SIZE := Vector2i(512, 512)
const PLANT_MAX_SIZE := Vector2i(420, 400)
const PLANT_BASELINE_Y: int = 466
const BACKGROUND_SIZE := Vector2i(720, 1280)
const THUMBNAIL_SIZE := Vector2i(256, 455)


func _init() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty():
		_fail("Missing art preparation mode.")
		return

	var mode := arguments[0]
	var error := OK
	match mode:
		"plant":
			if arguments.size() != 4:
				_fail("Plant mode expects: plant SOURCE OUTPUT REMOVE_CHECKER.")
				return
			error = _prepare_plant(arguments[1], arguments[2], arguments[3] == "true")
		"portrait":
			if arguments.size() != 3:
				_fail("Portrait mode expects: portrait SOURCE OUTPUT.")
				return
			error = _resize_portrait(arguments[1], arguments[2])
		"thumbnail":
			if arguments.size() != 5:
				_fail("Thumbnail mode expects: thumbnail FAR MID FRONT OUTPUT.")
				return
			error = _create_thumbnail(arguments[1], arguments[2], arguments[3], arguments[4])
		_:
			_fail("Unknown art preparation mode: %s" % mode)
			return

	if error != OK:
		_fail("Art preparation failed with error %d." % error)
		return
	quit(0)


func _prepare_plant(source_path: String, output_path: String, remove_checker: bool) -> Error:
	var image := _load_image(source_path)
	if image == null or image.is_empty():
		return ERR_CANT_OPEN
	image.convert(Image.FORMAT_RGBA8)
	if remove_checker:
		_remove_painted_checker(image)
	_keep_largest_visible_component(image)

	var visible_bounds := _find_visible_bounds(image)
	if visible_bounds.size.x <= 0 or visible_bounds.size.y <= 0:
		return ERR_INVALID_DATA
	var cropped := image.get_region(visible_bounds)
	var scale := minf(
		float(PLANT_MAX_SIZE.x) / float(cropped.get_width()),
		float(PLANT_MAX_SIZE.y) / float(cropped.get_height()),
	)
	var destination_size := Vector2i(
		maxi(1, roundi(float(cropped.get_width()) * scale)),
		maxi(1, roundi(float(cropped.get_height()) * scale)),
	)
	cropped.resize(destination_size.x, destination_size.y, Image.INTERPOLATE_LANCZOS)

	var result := Image.create_empty(
		PLANT_CANVAS_SIZE.x,
		PLANT_CANVAS_SIZE.y,
		false,
		Image.FORMAT_RGBA8,
	)
	result.fill(Color.TRANSPARENT)
	var destination := Vector2i(
		(PLANT_CANVAS_SIZE.x - destination_size.x) / 2,
		PLANT_BASELINE_Y - destination_size.y,
	)
	result.blend_rect(cropped, Rect2i(Vector2i.ZERO, destination_size), destination)
	return _save_image(result, output_path)


func _resize_portrait(source_path: String, output_path: String) -> Error:
	var image := _load_image(source_path)
	if image == null or image.is_empty():
		return ERR_CANT_OPEN
	image.convert(Image.FORMAT_RGBA8)
	image.resize(BACKGROUND_SIZE.x, BACKGROUND_SIZE.y, Image.INTERPOLATE_LANCZOS)
	return _save_image(image, output_path)


func _create_thumbnail(
	far_path: String,
	mid_path: String,
	front_path: String,
	output_path: String,
) -> Error:
	var layers: Array[Image] = []
	for path in [far_path, mid_path, front_path]:
		var layer := _load_image(path)
		if layer == null or layer.is_empty():
			return ERR_CANT_OPEN
		layer.convert(Image.FORMAT_RGBA8)
		if layer.get_size() != BACKGROUND_SIZE:
			layer.resize(BACKGROUND_SIZE.x, BACKGROUND_SIZE.y, Image.INTERPOLATE_LANCZOS)
		layers.append(layer)

	var result := Image.create_empty(
		BACKGROUND_SIZE.x,
		BACKGROUND_SIZE.y,
		false,
		Image.FORMAT_RGBA8,
	)
	result.fill(Color.TRANSPARENT)
	var source_rect := Rect2i(Vector2i.ZERO, BACKGROUND_SIZE)
	for layer in layers:
		result.blend_rect(layer, source_rect, Vector2i.ZERO)
	result.resize(THUMBNAIL_SIZE.x, THUMBNAIL_SIZE.y, Image.INTERPOLATE_LANCZOS)
	return _save_image(result, output_path)


func _remove_painted_checker(image: Image) -> void:
	var width := image.get_width()
	var height := image.get_height()
	var pixel_count := width * height
	var outside := PackedByteArray()
	outside.resize(pixel_count)
	var queue := PackedInt32Array()

	for x in width:
		_seed_checker_pixel(image, x, 0, width, outside, queue)
		_seed_checker_pixel(image, x, height - 1, width, outside, queue)
	for y in height:
		_seed_checker_pixel(image, 0, y, width, outside, queue)
		_seed_checker_pixel(image, width - 1, y, width, outside, queue)

	var head := 0
	while head < queue.size():
		var index := queue[head]
		head += 1
		var x := index % width
		var y := index / width
		if x > 0:
			_seed_checker_pixel(image, x - 1, y, width, outside, queue)
		if x + 1 < width:
			_seed_checker_pixel(image, x + 1, y, width, outside, queue)
		if y > 0:
			_seed_checker_pixel(image, x, y - 1, width, outside, queue)
		if y + 1 < height:
			_seed_checker_pixel(image, x, y + 1, width, outside, queue)

	var visited := outside.duplicate()
	var largest_component := PackedInt32Array()
	for start in pixel_count:
		if visited[start] != 0:
			continue
		var component := PackedInt32Array()
		queue.clear()
		queue.append(start)
		visited[start] = 1
		head = 0
		while head < queue.size():
			var index := queue[head]
			head += 1
			component.append(index)
			var x := index % width
			var y := index / width
			if x > 0:
				_visit_component_pixel(index - 1, visited, queue)
			if x + 1 < width:
				_visit_component_pixel(index + 1, visited, queue)
			if y > 0:
				_visit_component_pixel(index - width, visited, queue)
			if y + 1 < height:
				_visit_component_pixel(index + width, visited, queue)
		if component.size() > largest_component.size():
			largest_component = component

	var keep := PackedByteArray()
	keep.resize(pixel_count)
	for index in largest_component:
		keep[index] = 1
	for index in pixel_count:
		var x := index % width
		var y := index / width
		if keep[index] == 0:
			image.set_pixel(x, y, Color.TRANSPARENT)
		else:
			var color := image.get_pixel(x, y)
			color.a = 1.0
			image.set_pixel(x, y, color)


func _keep_largest_visible_component(image: Image) -> void:
	var width := image.get_width()
	var height := image.get_height()
	var pixel_count := width * height
	var visited := PackedByteArray()
	visited.resize(pixel_count)
	for index in pixel_count:
		var x := index % width
		var y := int(index / width)
		if image.get_pixel(x, y).a <= 0.02:
			visited[index] = 1

	var queue := PackedInt32Array()
	var largest_component := PackedInt32Array()
	for start in pixel_count:
		if visited[start] != 0:
			continue
		var component := PackedInt32Array()
		queue.clear()
		queue.append(start)
		visited[start] = 1
		var head := 0
		while head < queue.size():
			var index := queue[head]
			head += 1
			component.append(index)
			var x := index % width
			var y := int(index / width)
			if x > 0:
				_visit_component_pixel(index - 1, visited, queue)
			if x + 1 < width:
				_visit_component_pixel(index + 1, visited, queue)
			if y > 0:
				_visit_component_pixel(index - width, visited, queue)
			if y + 1 < height:
				_visit_component_pixel(index + width, visited, queue)
		if component.size() > largest_component.size():
			largest_component = component

	var keep := PackedByteArray()
	keep.resize(pixel_count)
	for index in largest_component:
		keep[index] = 1
	for index in pixel_count:
		if keep[index] != 0:
			continue
		image.set_pixel(index % width, int(index / width), Color.TRANSPARENT)


func _seed_checker_pixel(
	image: Image,
	x: int,
	y: int,
	width: int,
	outside: PackedByteArray,
	queue: PackedInt32Array,
) -> void:
	var index := y * width + x
	if outside[index] != 0 or not _is_checker_background(image.get_pixel(x, y)):
		return
	outside[index] = 1
	queue.append(index)


func _visit_component_pixel(
	index: int,
	visited: PackedByteArray,
	queue: PackedInt32Array,
) -> void:
	if visited[index] != 0:
		return
	visited[index] = 1
	queue.append(index)


func _is_checker_background(color: Color) -> bool:
	var red := roundi(color.r * 255.0)
	var green := roundi(color.g * 255.0)
	var blue := roundi(color.b * 255.0)
	var minimum := mini(red, mini(green, blue))
	var maximum := maxi(red, maxi(green, blue))
	return minimum >= 218 and maximum - minimum <= 18


func _find_visible_bounds(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a <= 0.02:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return Rect2i()
	min_x = maxi(0, min_x - 4)
	min_y = maxi(0, min_y - 4)
	max_x = mini(image.get_width() - 1, max_x + 4)
	max_y = mini(image.get_height() - 1, max_y + 4)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _save_image(image: Image, output_path: String) -> Error:
	var absolute_path := output_path
	if not output_path.is_absolute_path():
		absolute_path = ProjectSettings.globalize_path(output_path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK:
		return directory_error
	return image.save_png(absolute_path)


func _load_image(path: String) -> Image:
	var absolute_path := path
	if not path.is_absolute_path():
		absolute_path = ProjectSettings.globalize_path(path)
	return Image.load_from_file(absolute_path)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
