class_name SettingsFile
## Where the settings files (config.json, dots.json, ...) are read and written.
## In the editor they are the project's own res:// files, so tuned settings can
## be committed. An exported game can't write to res://, so it saves a copy in
## user:// and reads that copy once it exists, falling back to the shipped file.


static func read_path(path: String) -> String:
	var saved := write_path(path)
	return saved if FileAccess.file_exists(saved) else path


static func write_path(path: String) -> String:
	if OS.has_feature("editor"):
		return path
	return "user://" + path.trim_prefix("res://")
