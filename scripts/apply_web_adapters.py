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
    s = replace(s, '\tgrid.bake(world.get_world_3d().direct_space_state, ignore)', '\tif not (OS.has_feature("web") and grid.load_web_cache("res://data/content/walk_grid_web.bin")):\n\t\tgrid.bake(world.get_world_3d().direct_space_state, ignore)')
    s = replace(s, '\tguide.refresh_route(true)\n\tui.refresh()', '\tguide.refresh_route(true)\n\tui.refresh()\n\tif OS.has_feature("web"):\n\t\tJavaScriptBridge.eval("window.starworldSceneReady = true")')
    changes[path] = s
    path = 'scripts/content/audio_director.gd'
    s = read(path)
    s = replace(s, '\tplayer.name = id', '\tplayer.name = id\n\tif OS.has_feature("web"):player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM')
    s = replace(s, '\tload_settings()', '\tload_settings()\n\tif OS.has_feature("web"):\n\t\t_web_sound_callback = JavaScriptBridge.create_callback(_enable_web_sound)\n\t\tJavaScriptBridge.get_interface("window").starworldEnableSound = _web_sound_callback')
    if 'func _enable_web_sound(' not in s:
        s += '\n'+(ADAPTERS/'audio_callback.gdinc').read_text(encoding='utf-8')
    if 'var _web_meter_time' not in s:
        s = replace(s, 'var _web_sound_callback: JavaScriptObject', 'var _web_sound_callback: JavaScriptObject\nvar _web_meter_time := 0.0')
    s = replace(s, 'func _process(delta: float) -> void:', 'func _process(delta: float) -> void:\n\t_web_meter_time += delta\n\tif OS.has_feature("web") and _web_meter_time >= 1.0:\n\t\t_web_meter_time = 0.0\n\t\tvar peak_db := AudioServer.get_bus_peak_volume_left_db(AudioServer.get_bus_index("Music"), 0)\n\t\tJavaScriptBridge.eval("window.starworldMusicPeakDb = Math.max(window.starworldMusicPeakDb ?? -200, " + str(peak_db) + ")")')
    changes[path] = s
    path = 'project.godot'
    s = read(path)
    if 'general/default_playback_type.web' not in s:
        if '[audio]' in s:
            s = replace(s, '[audio]', '[audio]\n\ngeneral/default_playback_type.web=1')
        else:
            s += '\n[audio]\n\ngeneral/default_playback_type.web=1\n'
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
\t\t\tvar center: Vector2 = button.get_global_rect().get_center()
\t\t\tbuttons.append({"text": button.text, "x": center.x, "y": center.y})
\t\tvar pos: Vector3 = content.world.player.global_position
\t\tvar size: Vector2 = root.size
\t\tJavaScriptBridge.eval("window.starworldUi = " + JSON.stringify({"title": title_card.visible, "booting": is_instance_valid(root.get_node_or_null("BootVeil")), "buttons": buttons, "width": size.x, "height": size.y, "position": [pos.x, pos.y, pos.z], "panel": open_panel}))''')
    s = s.replace('"title": title_card.visible, "buttons": buttons', '"title": title_card.visible, "booting": is_instance_valid(root.get_node_or_null("BootVeil")), "buttons": buttons')
    changes[path] = s
    key = 'scripts/performance.gd'
    text = changes.get(key, read(key))
    if 'func prepare_web_props()' not in text:
        text += (ADAPTERS/'performance_warmup.gdinc').read_text(encoding='utf-8')
        for factory in ['watering_can','paper_lantern','pebble','seed_pouch','cloth']:
            signature = 'static func '+factory+'() -> Node3D:'
            text = text.replace(signature, signature+'\n\tif OS.has_feature("web") and _web_prop_templates.has("'+factory+'") :return _web_prop_copy("'+factory+'")')
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
        text = text.replace('SystemFont.new()', 'preload("res://assets/fonts/LXGWWenKai-Regular.ttf")').replace(': SystemFont', ': Font')
        text = re.sub(r';\w+\.font_names\s*=.*?(?=\n|$)', '', text)
        text = re.sub(r'^.*\.(?:font_names|font_weight|fallbacks)\s*=.*\n', '', text, flags=re.M)
        text = text.replace('✦', '★').replace('✧', '☆')
        changes[key] = text
    key = 'project.godot'
    changes[key] = changes.get(key, read(key)).replace('theme/custom_font="res://assets/fonts/NotoSansSC.ttf"', 'theme/custom_font="res://assets/fonts/LXGWWenKai-Regular.ttf"')
    key = 'scripts/scene_actions.gd'
    text = changes.get(key, read(key))
    if '# Hide the close foreground silhouette in both seated vistas.' not in text:
        text = text.replace('func _enter_vista() -> void:', 'func _enter_vista() -> void:\n\t# Hide the close foreground silhouette in both seated vistas.\n\tplayer.model.visible=false')
        text = text.replace('func _leave_vista() -> void:', 'func _leave_vista() -> void:\n\tplayer.model.visible=true')
    changes[key] = text
    # Validate every anchor before writing any file.
    for path, s in changes.items():
        (root/path).write_text(s, encoding='utf-8')
    print('Browser color, sound and navigation adapters applied:', root)

if __name__ == '__main__':
    apply(sys.argv[1] if len(sys.argv)>1 else Path(__file__).resolve().parents[1]/'game')
