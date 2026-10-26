extends RefCounted
## A separate, memory-only chapter-five checkpoint. Never imports or saves a journey.
static func seed(world: Node3D) -> void:
	var content=world.content
	assert(content.test_session,"The ending checkpoint requires isolated test-session arguments")
	content.state.persistent=false
	content.state.reset()
	content.state.data.started=true
	content.state.data.mode="story"
	content.state.data.player_name="星仔"
	var found:=false
	for chapter in content.director.main.size():
		var stages: Array=content.director.main[chapter].stages
		for stage in stages.size():
			if stages[stage].id==("c4_fly" if "--flight-preview" in OS.get_cmdline_user_args() else "c5_fly"):
				content.state.data.main={"chapter":chapter,"stage":stage,"done":false}
				found=true
	assert(found,"The final-flight checkpoint must exist")
	for site in ["garden","treehouse","lamps","oven","child","fountain","ship","lighthouse","grandma"]:
		content.state.set_flag("lit_"+site)
	for flag in ["xiaoguang","star_home","star_boat","star_bell","ship_lamp_lit","reaction_lighthouse_lit","reaction_garden_glow","keeper_door_open","window_polished","met_gardener","invite_gardener","invite_lamplighter","invite_baker","invite_child","invite_grandma"]:
		content.state.set_flag(flag)
	world.day_cycle.set_time(2,0.0)
	world.activities.progress={"flowers":0,"watered":false,"moments":[]}
	content.ui.close_panel()
	content.ui.title_card.visible=false
	content.ui.title_backdrop.visible=false
	world.player.controls_locked=true
	content._apply_reactions()

static func place(world: Node3D) -> void:
	var tree=world.get_tree()
	var content=world.content
	if OS.has_feature("web"):
		while not bool(JavaScriptBridge.eval("window.starworldSceneReady === true")):await tree.process_frame
	else:
		for i in 120:await tree.process_frame
	while not is_instance_valid(content.airship.rig) or content.props.doors.is_empty():await tree.process_frame
	content.registry.refresh()
	world.player.global_position=content.registry.position_of("dock")+Vector3.UP*.08
	world.player.velocity=Vector3.ZERO
	world.player.cam_yaw=0.0
	world.player.cam_pitch=-.25
	content.xiaoguang._restore()
	content.xiaoguang.visible=true
	content.ui.close_panel()
	content.ui.title_card.visible=false
	content.ui.title_backdrop.visible=false
	world.player.controls_locked=false
	content.director.evaluate()
	content.guide.refresh_route(true)
	content.ui.refresh()
	content.ui.toast("独立体验 · 小光的归途。靠近飞艇按 E 登艇；关闭后重开可再次体验。",8.0)
	if OS.has_feature("web"):JavaScriptBridge.eval("window.starworldEndingPreviewReady = true")
