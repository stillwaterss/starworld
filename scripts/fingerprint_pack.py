"""Give each release a distinct pack URL so browser caching cannot mix versions."""
from pathlib import Path
import hashlib

root = Path(__file__).resolve().parents[1]/'site/play'
pack = root/'index.pck'
digest = hashlib.sha256(pack.read_bytes()).hexdigest()[:16]
name = f'index.{digest}.pck'
page = root/'index.html'
text = page.read_text(encoding='utf-8')
anchor = 'config.mainPack = config.executable + ".pck";'
assert text.count(anchor) == 1
text = text.replace(anchor, f'config.mainPack = "{name}";')
pack.rename(root/name)
page.write_text(text, encoding='utf-8')
print('Versioned browser pack:', name, (root/name).stat().st_size)
