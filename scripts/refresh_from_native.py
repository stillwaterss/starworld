"""Refresh the browser release copy without touching desktop saves or publishing."""
from pathlib import Path
import re
import shutil
import runpy
import argparse
from datetime import datetime

ROOT = Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description="Refresh Claude/native content while retaining versioned web adapters")
parser.add_argument('--source',type=Path,required=True,help='Native game folder containing project.godot')
parser.add_argument('--out',type=Path,default=ROOT/'game')
parser.add_argument('--code-only',action='store_true',help='Fast adapter test in a separate folder; not a playable export')
args=parser.parse_args();SOURCE=args.source.resolve();OUT=args.out.resolve()
assert SOURCE!=OUT and (SOURCE/'project.godot').is_file()
assert not args.code_only or OUT!=(ROOT/'game').resolve(), 'Code-only tests require a separate --out folder'
import json
import re
baseline_project=(ROOT/'game/project.godot').read_text('utf8')
namespace=re.search(r'^config/name=(.+)$',baseline_project,re.M).group(1)
backup=ROOT/'local-backups'/datetime.now().strftime('before_refresh_%Y%m%d_%H%M%S')
for name in ['scripts','shaders']:
    if (OUT/name).exists():shutil.copytree(OUT/name,backup/name,dirs_exist_ok=True)
for name in ['project.godot','main.tscn','default_bus_layout.tres','web_shell.html']:
    if (OUT/name).exists():
        backup.mkdir(parents=True,exist_ok=True);shutil.copy2(OUT/name,backup/name)

OUT.mkdir(parents=True, exist_ok=True)
fallback=ROOT/'game/assets/fonts/NotoSansSC.ttf'
assert fallback.exists(),'Keep the existing licensed fallback font in the release repository'
(OUT/'assets/fonts').mkdir(parents=True,exist_ok=True)
if not args.code_only and fallback.resolve()!=(OUT/'assets/fonts/NotoSansSC.ttf').resolve():shutil.copy2(fallback,OUT/'assets/fonts/NotoSansSC.ttf')
for folder in ['scripts', 'data', 'shaders', 'assets']:
    if args.code_only and folder=='assets':continue
    shutil.copytree(SOURCE/folder, OUT/folder, dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('*.import', '*.uid'))
for name in ['project.godot', 'main.tscn']:
    shutil.copy2(SOURCE/name, OUT/name)
if not args.code_only:
    optimization = runpy.run_path(str(ROOT/'scripts/optimize_web_npcs.py'))['optimize'](OUT)
    print('Browser NPC optimization:', optimization)
for path in (OUT/'scripts').rglob('*.gd'):
    text = path.read_text(encoding='utf-8')
    text = re.sub(r'"D:/claude/starworld/game/save/([^"/]+)"', r'"user://\1"', text)
    text = re.sub(r'"res://save/([^"/]+)"', r'"user://\1"', text)
    text = text.replace('"res://save/" + file_name', '"user://" + file_name')
    lines = []
    for line in text.splitlines(True):
        lines.append(line)
        font_assignment = re.search(r'\b(\w+)\.font_names\s*=', line)
        if font_assignment:
            indent = line[:len(line)-len(line.lstrip())]
            lines.append(indent+font_assignment.group(1)+'.fallbacks = [preload("res://assets/fonts/NotoSansSC.ttf"), preload("res://assets/fonts/LXGWWenKai-Regular.ttf")]\n')
    text = ''.join(lines)
    if path.name == 'player.gd':
        text = text.replace('if capture_mouse:\n', 'if capture_mouse and not OS.has_feature("web"):\n')
    if path.name == 'photo_studio.gd':
        start = text.index('\t\tvar folder: String =', text.index('func shoot('))
        end = text.index('\n\tlast_saved', start)
        text = text[:start]+'''\t\tvar filename := Time.get_datetime_string_from_system().replace(":", "-") + ".png"
\t\tif OS.has_feature("web"):
\t\t\tJavaScriptBridge.download_buffer(image.save_png_to_buffer(),filename,"image/png")
\t\t\tpath=filename
\t\telse:
\t\t\tvar folder: String = preload("res://scripts/project_paths.gd").renders("photos")
\t\t\tDirAccess.make_dir_recursive_absolute(folder)
\t\t\tpath=folder+filename
\t\t\timage.save_png(path)'''+text[end:]
    path.write_text(text, encoding='utf-8')
path = OUT/'project.godot'
text = path.read_text(encoding='utf-8').replace('"Forward Plus"', '"GL Compatibility"')
text = text.replace('anti_aliasing/quality/msaa_3d=2', 'renderer/rendering_method="gl_compatibility"\nrenderer/rendering_method.mobile="gl_compatibility"\ntextures/vram_compression/import_etc2_astc=true\nanti_aliasing/quality/msaa_3d=0')
text = text.replace('file_logging/log_path="D:/Caches/StarworldTemp/starworld.log"', 'file_logging/enable_file_logging=false')
text += '\n[gui]\n\ntheme/custom_font="res://assets/fonts/NotoSansSC.ttf"\n'
path.write_text(text, encoding='utf-8')
# Preserve the existing browser storage namespace across native version names.
project=OUT/'project.godot'
project.write_text(re.sub(r'^config/name=.+$',lambda m:'config/name='+namespace,project.read_text('utf8'),flags=re.M),'utf8')
if OUT!=(ROOT/'game').resolve():shutil.copytree(ROOT/'game/tools',OUT/'tools',dirs_exist_ok=True)
# Regenerate the bundled Chinese subset whenever content changes.
if not args.code_only:
    from fontTools import subset
    font_path = OUT / 'assets/fonts/LXGWWenKai-Regular.ttf'
    font = subset.load_font(str(font_path), subset.Options())
    glyph_text = ''.join(p.read_text(encoding='utf-8') for folder in ['scripts', 'data'] for p in (OUT/folder).rglob('*') if p.is_file() and p.suffix in ['.gd', '.json'])
    subsetter = subset.Subsetter(options=subset.Options())
    subsetter.populate(text=glyph_text.replace('✦','★').replace('✧','☆') + ''.join(chr(n) for n in list(range(32,127))+list(range(0x3000,0x3100))+list(range(0x4e00,0xa000))) + '★☆')
    subsetter.subset(font)
    font.save(str(font_path))
    

adapter = ROOT / 'scripts/apply_web_adapters.py'
assert adapter.exists(), 'Keep the versioned web adapter alongside the release repository.'
for name in ['ending_checkpoint.gd','web_platform.gd','web_visual_profile.gd']:
    template=ROOT/'scripts/adapters/web_only'/name
    if template.exists():
        target=OUT/'scripts'/('content/'+name if name=='ending_checkpoint.gd' else name)
        target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(template,target)
if (SOURCE/'default_bus_layout.tres').exists():shutil.copy2(SOURCE/'default_bus_layout.tres',OUT/'default_bus_layout.tres')
if not (OUT/'web_shell.html').exists():shutil.copy2(ROOT/'game/web_shell.html',OUT/'web_shell.html')
runpy.run_path(str(adapter))['apply'](OUT)
print('Browser source refreshed with color/audio/navigation adapters. Review and push outputs/web_release_source to publish.')

checks=runpy.run_path(str(ROOT/'scripts/check_web_contract.py'))['check'](OUT)
print('Preserved web features:',len(checks))
