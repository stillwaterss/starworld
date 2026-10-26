"""Fail if refreshing a native patch discards an established browser safeguard."""
from pathlib import Path
import argparse, json, re

def check(root):
    root=Path(root); repo=Path(__file__).resolve().parents[1]
    rules={
      'audio_native_samples':('scripts/content/audio_director.gd','AudioServer.PLAYBACK_TYPE_SAMPLE'),
      'audio_predecode':('scripts/content/audio_director.gd','_web_prepare_audio_samples()'),
      'audio_after_ready':('scripts/content/audio_director.gd','window.starworldGameAudioReady === true'),
      'audio_status':('scripts/content/audio_director.gd','window.starworldAudioStatus'),
      'sample_project_mode':('project.godot','general/default_playback_type.web=2'),
      'bundled_chinese':('project.godot','theme/custom_font="res://assets/fonts/LXGWWenKai-Regular.ttf"'),
      'sky_color_space':('scripts/main.gd','sky_material.set_shader_parameter("web_color_space",true)'),
      'sky_color_profile':('scripts/day_cycle.gd','web_visual_profile.gd'),
      'walk_cache':('scripts/content/content_root.gd','grid.load_web_cache'),
      'prop_cache':('scripts/performance.gd','prepare_web_props()'),
      'flower_cache':('scripts/cozy_activities.gd','_web_flower(index)'),
      'subtitle_preparation':('scripts/performance.gd','glyphs.keys()'),
      'staged_scene':('scripts/main.gd','_web_stage_geometry()'),
      'seat_foreground_hidden':('scripts/scene_actions.gd','player.model.visible=false'),
      'camera_waits_for_return':('scripts/performance.gd','if _glide:await _glide.finished'),
      'ship_fov_continuity':('scripts/content/airship.gd','camera.fov = initial_camera.fov'),
      'chapter_five_persistence':('scripts/content/story_state.gd','last_chapter'),
      'ending_preview':('scripts/content/ending_checkpoint.gd','content.state.persistent=false'),
      'web_exit':('scripts/web_platform.gd','exit_game'),
      'versioned_audio_shell':('web_shell.html','../assets/web-audio-v172.js'),
      'audio_opens_after_scene':('web_shell.html','window.starworldStartAudio()'),
    }
    result={name:needle in (root/file).read_text('utf8') if (root/file).exists() else False for name,(file,needle) in rules.items()}
    layout=(root/'default_bus_layout.tres').read_text('utf8')
    names=re.findall(r'bus/\d+/name\s*=\s*&?"([^"]+)"',layout)
    result['buses_predeclared']=names[:4]==['Master','Music','Ambience','SFX']
    js=(repo/'site/assets/web-audio-v172.js').read_text('utf8')
    result['loading_gate']=('gate.gain.value=0' in js and 'window.starworldGameAudioReady=true' in js)
    result['gain_buffers_reused']='samples:new Float32Array' in js
    failed=[k for k,v in result.items() if not v]
    if failed:raise RuntimeError('Native patch requires reviewing these web features: '+', '.join(failed))
    return result

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--project',type=Path,default=Path(__file__).resolve().parents[1]/'game');parser.add_argument('--report',type=Path)
    args=parser.parse_args();report=check(args.project)
    if args.report:args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2),'utf8')
    print(json.dumps({'passed':len(report),'checks':report},ensure_ascii=True))
