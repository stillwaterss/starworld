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
    # Validate every anchor before writing any file.
    for path, s in changes.items():
        (root/path).write_text(s, encoding='utf-8')
    print('Browser color, sound and navigation adapters applied:', root)

if __name__ == '__main__':
    apply(sys.argv[1] if len(sys.argv)>1 else Path(__file__).resolve().parents[1]/'game')
