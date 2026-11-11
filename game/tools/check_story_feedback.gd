extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:await process_frame

func gap(a: Node3D, b: Node3D) -> float:
	return (a.global_position - b.global_position).slide(Vector3.UP).length()

func run() -> void:
	root.size = Vector2i(1280, 720)
	var w = load("res://main.tscn").instantiate()
	root.add_child(w)
	await frames(60)
	var c = w.content
	var player: CharacterBody3D = w.player
	assert(not c.state.persistent, "Isolated test session only")
	c.state.data.started = true
	c.state.data.mode = "story"
	c.state.data.main = {"done":true, "chapter":4, "stage":99}
	c.ui.close_panel()
	c.ui.title_card.visible = false
	c.ending._build_finale()
	await frames(4)
	var panel: PanelContainer = c.ending.finale_panel
	var labels: Array = panel.find_children("*", "Label", true, false).map(func(l):return l.text)
	for id in c.director.side_order:
		if id != "s_keeper":assert(c.director.sides[id].title in labels, "Missing side: "+id)
	assert(panel.get_global_rect().end.y <= 720.0, "Finale exceeds the viewport")
	var buttons: Array = panel.find_children("*", "Button", true, false).map(func(b):return b.text)
	assert(buttons[0] == "开始后记" and "查看小故事" in buttons)
	panel.get_parent().queue_free()
	c.state.side("s_keeper").state = "active"
	c.state.data.track = "s_keeper"
	var stages: Array = c.director.sides["s_keeper"].stages
	var ids: Array = stages.map(func(stage):return stage.id)
	c.state.side("s_keeper").stage = ids.find("s_keeper_watch")
	w.day_cycle.set_time(1, 0)
	assert("按 T" in c.director.tracked().hint, "No key in the watch hint")
	c.state.side("s_keeper").stage = ids.find("s_keeper_ride")
	c.airship.at = "keeper_isle"
	var park: Array = c.airship._keeper_park()
	c.airship._place(park[0], park[1])
	c.airship._show_gangway(true)
	player.global_position = c.registry.position_of("keeper_dock") + Vector3.UP * .02
	player.velocity = Vector3.ZERO
	c._keeper_ride()
	var flight_gap := INF
	var flight_frames := 0
	for i in 1900:
		if is_instance_valid(c._rider):
			flight_gap = minf(flight_gap, gap(player,c._rider))
			flight_frames += 1
			if flight_frames > 100:c.airship.skip = true
		if not c._staging:break
		await process_frame
	assert(flight_frames > 100 and flight_gap >= 1.05, "Ship gap: "+str(flight_gap))
	assert(c._followers.size() == 1 and c.state.flag("keeper_in_town"))
	var keeper: Node3D = c._followers[0]
	var dock_gap := gap(player, keeper)
	assert(dock_gap >= 1.05, "Dock gap: "+str(dock_gap))
	var rest: Vector3 = c.npcs.actors["grandma"].rest
	var front: Vector3 = c.props.doors["grandma"].front
	player.global_position = c._floor_at(rest + front * 1.3) + Vector3.UP * .04
	keeper.global_position = c._floor_at(rest + front * 2.7)
	c._door_reunion()
	for i in 1200:
		if w.interactions.mode == "dialogue" and i % 24 == 0:
			w.interactions.next_dialogue()
		if not c._staging:break
		await process_frame
	assert(c._followers.size()==2 and c.state.flag("grandma_joined"), "Door did not finish")
	var grandma: Node3D = c._followers[1]
	var near := INF
	for i in 150:
		near = minf(minf(near, gap(player,keeper)), minf(gap(player,grandma), gap(keeper,grandma)))
		await process_frame
	assert(near >= 1.05, "Door spacing: "+str(near))
	var props = c.props
	var beam: Node3D = props.prepare_lighthouse()
	assert(not beam.visible and not c.state.flag("reaction_lighthouse_lit"), "Prewarm changed progress")
	props.light_lighthouse()
	await frames(200)
	assert(beam.visible and beam.scale.is_equal_approx(Vector3.ONE) and c.state.flag("reaction_lighthouse_lit"))
	print("FEEDBACK_STORY_PASS side_tags=",labels.size(), " deck_gap=",flight_gap," dock_gap=",dock_gap," door_gap=",near," lighthouse_visible=",beam.visible)
	quit()
