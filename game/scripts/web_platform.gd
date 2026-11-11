extends RefCounted
## An exported browser game returns to its introduction when the player chooses Exit.
static func exit_game(tree: SceneTree) -> void:
	# The web engine flushes IndexedDB before the shell's onExit redirects.
	tree.quit()
