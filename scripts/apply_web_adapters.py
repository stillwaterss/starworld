"""Reapply browser-only fixes after refreshing desktop sources. Idempotent, fail closed.

Run with Python, optionally passing the browser game directory. Does not publish.
"""
from pathlib import Path
import sys

ADAPTERS = Path(__file__).resolve().parent / 'adapters'

def replace(text, old, new):
    if new in text:
        return text
    if text.count(old) != 1:
        raise RuntimeError(f'Browser adapter needs review; expected one anchor: {old[:90]!r}')
    return text.replace(old, new, 1)

def apply(root):
    root = Path(root)
    changes = {}
    def read(path): return (root/path).read_text(encoding='utf-8')
    path = 'scripts/main.gd'
    s = read(path).replace('night_sky_2k.exr', 'night_sky_2k_web.png').replace('galaxy_detail_2k.exr', 'galaxy_detail_2k_web.png')
    s = replace(s, '\tsky_material.shader = preload("res://shaders/twilight_sky.gdshader")', '\tsky_material.shader = preload("res://shaders/twilight_sky.gdshader")\n\tsky_material.set_shader_parameter("web_color_space",true)')
    changes[path] = s
    path = 'shaders/twilight_sky.gdshader'
    s = read(path)
    if 'uniform bool web_color_space' not in s:
        s = replace(s, 'float hash(', (ADAPTERS/'sky_helpers.gdinc').read_text(encoding='utf-8') + 'float hash(')
    s = replace(s, '    vec3 color=texture(panorama,uv).rgb;', '    vec3 color=texture(panorama,uv).rgb;\n    if(web_color_space) color=web_linear(color);')
    s = replace(s, '        color=mix(color,texture(galaxy_detail,patch).rgb,1.0-smoothstep(.29,.36,edge));', '        vec3 detail_color=texture(galaxy_detail,patch).rgb;\n        if(web_color_space) detail_color=web_linear(detail_color);\n        color=mix(color,detail_color,1.0-smoothstep(.29,.36,edge));')
    s = replace(s, '    COLOR=day*time_weights.x+dusk*time_weights.y+color*time_weights.z;', '    COLOR=day*time_weights.x+dusk*time_weights.y+color*time_weights.z;\n    if(web_color_space) COLOR=web_srgb(COLOR+web_night_lift*time_weights.z);')
    changes[path] = s
    path = 'scripts/day_cycle.gd'
    s = read(path)
    anchor = '\tkey.rotation_degrees=Vector3(-48,-38,0)*weights.x+Vector3(-13,-66,0)*weights.y+Vector3(-46,-34,0)*weights.z'
    changes[path] = replace(s, anchor, anchor+'\n\tpreload("res://scripts/web_visual_profile.gd").apply(self)')
    path = 'scripts/content/walk_grid.gd'
    s = read(path)
    if 'func save_web_cache(' not in s:
        s = replace(s, 'func index(', (ADAPTERS/'walk_cache.gdinc').read_text(encoding='utf-8')+'func index(')
    changes[path] = s
    path = 'scripts/content/content_root.gd'
    s = read(path)
    if 'grid.load_web_cache' not in s:s = replace(s, '\tgrid.bake(world.get_world_3d().direct_space_state, ignore)', '\tif not (OS.has_feature("web") and grid.load_web_cache("res://data/content/walk_grid_web.bin")):\n\t\tgrid.bake(world.get_world_3d().direct_space_state, ignore)')
    if 'window.starworldSceneReady' not in s:
        s = replace(s, '\tguide.refresh_route(true)\n\tui.refresh()', '\tguide.refresh_route(true)\n\tui.refresh()\n\tif OS.has_feature("web"):\n\t\tJavaScriptBridge.eval("window.starworldSceneReady = true")')
    changes[path] = s
    path = 'scripts/content/audio_director.gd'
    import runpy
    changes[path] = runpy.run_path(str(ADAPTERS/'audio_adapter.py'))['adapt_audio'](read(path),ADAPTERS)
    path = 'project.godot'
    s = read(path)
    if 'general/default_playback_type.web' not in s:
        if '[audio]' in s:
            s = replace(s, '[audio]', '[audio]\n\ngeneral/default_playback_type.web=2')
        else:
            s += '\n[audio]\n\ngeneral/default_playback_type.web=2\n'
    s = s.replace('general/default_playback_type.web=1','general/default_playback_type.web=2')
    changes[path] = s
    # Read-only telemetry lets CI click the real in-game buttons and verify movement.
    path = 'scripts/content/content_ui.gd'
    s = read(path)
    if 'The HTML shell already owns the web loading cover.' not in s:
        s = replace(s, 'func _boot_card() -> void:', 'func _boot_card() -> void:\n\t# The HTML shell already owns the web loading cover.\n\tif OS.has_feature("web"):return')
    if 'veil.name = "BootVeil"' not in s:
        s = replace(s, '\tvar veil := ColorRect.new()', '\tvar veil := ColorRect.new()\n\tveil.name = "BootVeil"')
    if 'var _web_diag_clock' not in s:
        s = replace(s, 'func _process(delta: float) -> void:', '''var _web_diag_clock := 0.0
func _process(delta: float) -> void:
\t_web_diag_clock += delta
\tif OS.has_feature("web") and _web_diag_clock >= .5:
\t\t_web_diag_clock = 0.0
\t\tvar buttons: Array = []
\t\tfor button in title_card.find_children("*", "Button", true, false):
\t\t\tif not button.is_visible_in_tree():continue
\t\t\tvar center: Vector2 = button.get_global_rect().get_center()
\t\t\tbuttons.append({"text": button.text, "x": center.x, "y": center.y})
\t\tvar controls: Array = []
\t\tfor button in root.find_children("*", "Button", true, false):
\t\t\tif not button.is_visible_in_tree():continue
\t\t\tvar center: Vector2 = button.get_global_rect().get_center()
\t\t\tcontrols.append({"text": button.text, "x": center.x, "y": center.y})
\t\tvar pos: Vector3 = content.world.player.global_position
\t\tvar size: Vector2 = root.size
\t\tJavaScriptBridge.eval("window.starworldUi = " + JSON.stringify({"title": title_card.visible, "booting": is_instance_valid(root.get_node_or_null("BootVeil")), "buttons": buttons, "controls": controls, "about": about_panel.visible, "opening": content.opening.playing, "chapter": showing_card(), "locked": content.world.player.controls_locked, "performance": content.world.performance.kind, "performing": content.world.performance.busy, "width": size.x, "height": size.y, "position": [pos.x, pos.y, pos.z], "panel": open_panel}))''')
    s = s.replace('"title": title_card.visible, "buttons": buttons', '"title": title_card.visible, "booting": is_instance_valid(root.get_node_or_null("BootVeil")), "buttons": buttons')
    s = s.replace('"opening": content.opening.playing, "chapter"', '"opening": content.opening.playing, "openingSkip": {"visible": content.opening.skip_button.is_visible_in_tree(), "x": content.opening.skip_button.get_global_rect().get_center().x, "y": content.opening.skip_button.get_global_rect().get_center().y}, "chapter"')
    s = s.replace('"performing": content.world.performance.busy, "width"', '"performing": content.world.performance.busy, "endingPlaying": content.ending.playing, "endingSky": content.ending.sky_layer.visible, "finale": is_instance_valid(content.ending.finale_panel) and content.ending.finale_panel.visible, "homeReturned": content.state.flag("xiaoguang_home"), "mainDone": content.director.main_done(), "shipAt": content.airship.at, "lanterns": content.ending.lanterns.size(), "width"')
    changes[path] = s
    key = 'scripts/cozy_activities.gd'
    text = changes.get(key, read(key))
    if 'var _web_flower_pool' not in text:
        text += '\n' + (ADAPTERS/'animation_warmup.gdinc').read_text(encoding='utf-8')
    marker = '## Keep flower meshes and drop resources ready without changing game progress.'
    if marker in text:
        text = text[:text.index(marker)] + (ADAPTERS/'animation_warmup.gdinc').read_text(encoding='utf-8').lstrip('\n')
    text = text.replace('var flower:=Flora.build(index)', 'var flower:=_web_flower(index)')
    text = text.replace('var m:=SphereMesh.new();m.radius=.012;m.height=.03;m.radial_segments=4;m.rings=2', 'var m:=_web_pour_mesh()')
    text = text.replace('var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.75,.9,1,.8);mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA', 'var mat:=_web_pour_material()')
    changes[key] = text
    key = 'scripts/performance.gd'
    text = changes.get(key, read(key))
    # Hurrying the acting must not cut away from a still-running return glide.
    text = text.replace('\t\tawait wait(back_seconds)', '\t\tif _glide:await _glide.finished')
    if 'func prepare_web_props()' not in text:
        text += (ADAPTERS/'performance_warmup.gdinc').read_text(encoding='utf-8')
        for factory in ['watering_can','paper_lantern','pebble','seed_pouch','cloth']:
            signature = 'static func '+factory+'() -> Node3D:'
            text = text.replace(signature, signature+'\n\tif OS.has_feature("web") and _web_prop_templates.has("'+factory+'") :return _web_prop_copy("'+factory+'")')
    marker = '## Compile prop material variants during the loading cover, then reuse their meshes.'
    if marker in text:
        text = text[:text.index(marker)] + (ADAPTERS/'performance_warmup.gdinc').read_text(encoding='utf-8').lstrip('\n')
    import re
    text = re.sub(r'_web_prop_templates\.has\("([^"]+)"\)', r'is_instance_valid(_web_prop_templates.get("\1"))', text)
    text = text.replace('if not OS.has_feature("web") or not _web_prop_templates.is_empty():return', 'if not OS.has_feature("web"):return\n\tif not _web_prop_templates.is_empty():\n\t\tif is_instance_valid(_web_prop_templates.get("paper_lantern")):return\n\t\t_web_prop_templates.clear()')
    changes[key] = text
    key = 'scripts/content/content_root.gd'
    text = changes.get(key, read(key))
    if 'await world.performance.prepare_web_props()' not in text:
        text = text.replace('\t\tJavaScriptBridge.eval("window.starworldSceneReady = true")', '\t\tawait world.performance.prepare_web_props()\n\t\tJavaScriptBridge.eval("window.starworldSceneReady = true")')
    changes[key] = text
    key = 'scripts/content/content_ui.gd'
    text = changes.get(key, read(key))
    if 'window.starworldFontCheck' not in text:
        text = text.replace('\tfont = preload("res://assets/fonts/LXGWWenKai-Regular.ttf")', '\tfont = preload("res://assets/fonts/LXGWWenKai-Regular.ttf")\n\tif OS.has_feature("web"):\n\t\tJavaScriptBridge.eval("window.starworldFontCheck = " + JSON.stringify({"bundledPrimary": font is FontFile, "playerName":font.has_char(0x4ed4), "filledStar":font.has_char(0x2605), "emptyStar":font.has_char(0x2606)}))')
    changes[key] = text
    # Use one comprehensive primary font on every browser UI and NPC label.
    import re
    for p in (root/'scripts').rglob('*.gd'):
        key = p.relative_to(root).as_posix()
        text = changes.get(key, p.read_text(encoding='utf-8'))
        text = text.replace('SystemFont.new()', 'preload("res://assets/fonts/LXGWWenKai-Regular.ttf")').replace(': SystemFont', ': Font').replace('-> SystemFont', '-> Font')
        text = re.sub(r';\w+\.font_names\s*=.*?(?=\n|$)', '', text)
        text = re.sub(r'^.*\.(?:font_names|font_weight|fallbacks)\s*=.*\n', '', text, flags=re.M)
        text = text.replace('✦', '★').replace('✧', '☆')
        text = text.replace('get_tree().quit()', 'preload("res://scripts/web_platform.gd").exit_game(get_tree())')
        changes[key] = text
    key = 'scripts/content/content_ui.gd'
    text = changes[key]
    if 'window.starworldFontCheck' not in text:
        text = text.replace('\tfont = preload("res://assets/fonts/LXGWWenKai-Regular.ttf")', '\tfont = preload("res://assets/fonts/LXGWWenKai-Regular.ttf")\n\tif OS.has_feature("web"):\n\t\tJavaScriptBridge.eval("window.starworldFontCheck = " + JSON.stringify({"bundledPrimary": font is FontFile, "playerName":font.has_char(0x4ed4), "filledStar":font.has_char(0x2605), "emptyStar":font.has_char(0x2606)}))')
    changes[key] = text
    key = 'project.godot'
    changes[key] = changes.get(key, read(key)).replace('theme/custom_font="res://assets/fonts/NotoSansSC.ttf"', 'theme/custom_font="res://assets/fonts/LXGWWenKai-Regular.ttf"')
    key = 'scripts/scene_actions.gd'
    text = changes.get(key, read(key))
    if '# Hide the close foreground silhouette in both seated vistas.' not in text:
        text = text.replace('func _enter_vista() -> void:', 'func _enter_vista() -> void:\n\t# Hide the close foreground silhouette in both seated vistas.\n\tplayer.model.visible=false')
        text = text.replace('func _leave_vista() -> void:', 'func _leave_vista() -> void:\n\tplayer.model.visible=true')
    text = text.replace('views.append(_first_clear([CHAIR-FACING*3.0+Vector3.UP*4.4-side*1.7,CHAIR-FACING*3.0+Vector3.UP*4.4+side*1.7,CHAIR-FACING*2.2+Vector3.UP*5.2],town,town))', 'views.append([CHAIR+FACING*5.0+Vector3.UP*4.4,town])')
    changes[key] = text
    # Validate every anchor before writing any file.
    key = 'scripts/main.gd'
    text = changes.get(key, read(key))
    if 'func _web_boot_mark(' not in text:
        text = text.replace('func _ready() -> void:', 'func _ready() -> void:\n\t_web_boot_mark("scene_start")', 1)
        for anchor,label in [('\t_add_collisions(island)','collisions_done'),('\tadd_child(preload("res://scripts/world_details.gd").new())','details_done'),('\tadd_child(player)','player_done'),('\tadd_child(activities)','activities_done'),('\tadd_child(content)','content_done')]:
            text = text.replace(anchor,anchor+'\n\t_web_boot_mark("'+label+'")',1)
        text += '\nfunc _web_boot_mark(label: String) -> void:\n\tif OS.has_feature("web"):JavaScriptBridge.eval("window.starworldBootTrace ??= []; window.starworldBootTrace.push({label:"+JSON.stringify(label)+",ms:performance.now()})")\n'
    if 'res://scripts/content/ending_checkpoint.gd' not in text:
        text = replace(text, '\tadd_child(content)\n', '\tadd_child(content)\n\tif "--ending-preview" in OS.get_cmdline_user_args():\n\t\tvar checkpoint = load("res://scripts/content/ending_checkpoint.gd")\n\t\tcheckpoint.seed(self)\n\t\tcheckpoint.place(self)\n')
    if 'var _web_geometry_ready' not in text:
        text = text.replace('\tadd_child(content)\n','\tadd_child(content)\n\t_web_stage_geometry()\n',1)
        text += (ADAPTERS/'geometry_warmup.gdinc').read_text(encoding='utf-8')
    changes[key] = text
    key = 'scripts/content/content_root.gd'
    text = changes.get(key, read(key))
    old = '\tif not (OS.has_feature("web") and grid.load_web_cache("res://data/content/walk_grid_web.bin")):\n\t\tgrid.bake(world.get_world_3d().direct_space_state, ignore)'
    new = '\tif OS.has_feature("web"):world._web_boot_mark("grid_begin")\n\tvar used_cache: bool=OS.has_feature("web") and grid.load_web_cache("res://data/content/walk_grid_web.bin")\n\tif not used_cache:\n\t\tgrid.bake(world.get_world_3d().direct_space_state, ignore)\n\tif OS.has_feature("web"):\n\t\tworld._web_boot_mark("grid_done")\n\t\tJavaScriptBridge.eval("window.starworldGridCacheHit = "+("true" if used_cache else "false"))'
    if "var used_cache:" not in text:text = text.replace(old,new)
    changes[key] = text
    # Predeclare buses: runtime insertion misroutes the Web Audio sample graph.
    layout_path=root/'default_bus_layout.tres'
    layout=layout_path.read_text('utf8') if layout_path.exists() else '[gd_resource type="AudioBusLayout" format=3]\n\n[resource]\nbus/0/name = &"Master"\nbus/0/volume_db = 0.0\n'
    import ast
    buses={int(i):name for i,name in re.findall(r'bus/(\d+)/name\s*=\s*&?"([^"]+)"',layout)}
    if buses.get(0)!='Master':raise RuntimeError('Browser audio layout requires Master at index zero')
    wanted=ast.literal_eval(re.search(r'const BUSES := (\[[^\n]+\])',changes['scripts/content/audio_director.gd']).group(1))
    for name in wanted:
        if name in buses.values():continue
        index=max(buses)+1;buses[index]=name
        layout+=f'bus/{index}/name = &"{name}"\nbus/{index}/volume_db = 0.0\nbus/{index}/mute = false\nbus/{index}/solo = false\nbus/{index}/bypass_fx = false\nbus/{index}/send = &"Master"\n'
    changes['default_bus_layout.tres']=layout
    for path, s in changes.items():
        (root/path).write_text(s, encoding='utf-8')
    print('Browser color, sound and navigation adapters applied:', root)

if __name__ == '__main__':
    apply(sys.argv[1] if len(sys.argv)>1 else Path(__file__).resolve().parents[1]/'game')
