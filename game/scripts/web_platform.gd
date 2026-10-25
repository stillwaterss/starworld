extends RefCounted
## An exported browser game returns to its introduction when the player chooses Exit.
static func exit_game(tree: SceneTree) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.assign('../')")
	else:tree.quit()
