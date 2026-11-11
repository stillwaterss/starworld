extends RefCounted
## An exported browser game returns to its introduction when the player chooses Exit.
static func exit_game(tree: SceneTree) -> void:
	if OS.has_feature("web"):
		# Let the browser persist the save before navigating away. Quitting the Web
		# runtime directly can leave the sample audio driver waiting for its context.
		JavaScriptBridge.force_fs_sync()
		await tree.create_timer(1.0).timeout
		JavaScriptBridge.eval("window.location.assign('../')")
	else:tree.quit()
