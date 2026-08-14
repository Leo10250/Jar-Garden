class_name TestTempPaths
extends RefCounted


const DIRECTORY_NAME: String = "jar_garden_test_saves"


static func make_path(stem: String, extension: String = ".json") -> String:
	var temp_root := OS.get_environment("TEMP")
	if temp_root.is_empty():
		temp_root = OS.get_cache_dir()
	var directory := temp_root.path_join(DIRECTORY_NAME)
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_error("Could not create isolated test save directory: %s" % directory)
	return directory.path_join("%s_%d%s" % [stem, Time.get_ticks_usec(), extension])
