extends RefCounted
## Paths that resolve to the same folders on Windows (D:/claude/starworld/...) and on the
## Linux copy, so scripts and tests no longer hard-code a drive letter.

## Folder that holds game/, renders/, assets/ (D:/claude/starworld on the main machine).
static func root() -> String:
	return ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()

## renders/<sub>/ under the project root, with a trailing slash.
static func renders(sub: String) -> String:
	return root().path_join("renders").path_join(sub) + "/"

## Player progress lives in game/save (the same file as D:/claude/starworld/game/save/<name>).
static func save(file_name: String) -> String:
	return "user://" + file_name
