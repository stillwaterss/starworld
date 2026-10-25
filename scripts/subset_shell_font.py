"""Build the small HTML loading-screen font; the game keeps broad CJK coverage."""
from pathlib import Path
from fontTools import subset
R=Path(__file__).resolve().parents[1]
shell=R/'game/web_shell.html'
font=subset.load_font(str(R/'game/assets/fonts/LXGWWenKai-Regular.ttf'),subset.Options())
builder=subset.Subsetter(options=subset.Options())
builder.populate(text=shell.read_text(encoding='utf8')+''.join(chr(i) for i in range(32,127)))
builder.subset(font)
target=R/'site/assets/starworld-ui-v16-r3.ttf';font.save(str(target))
shell.write_text(shell.read_text(encoding='utf8').replace('starworld-ui-v16-r2.ttf',target.name),encoding='utf8')
print('HTML font bytes:',target.stat().st_size)
