"""v37 (Claude): cap the character textures that the .glb files carry inside at 1024 px.
Run in CI after the first `--import` (which extracts them next to the .glb) and before the
second one (which re-imports what changed). Five characters ship 2048 px colour / roughness /
normal maps: in the browser every one becomes an uncompressed RGBA texture with mipmaps,
about 21 MB of video memory each, 15 of them ≈ 320 MB. Phones (iPhone Safari above all) run out
of memory long before a desktop does. At 1024 px they need ≈ 80 MB together; on screen the
characters are a few hundred pixels tall, so the difference is not visible. The other NPCs
already use 1024 px files, UI pictures and the sky keep their full size.
    python3 scripts/web_texture_limits.py
"""
import pathlib, re, struct

ROOT = pathlib.Path(__file__).resolve().parents[1] / "game/assets/characters"
LIMIT = 1024
changed = 0
for imp in sorted(ROOT.glob("*_3d_model_*.png.import")):
    png = imp.with_suffix("")
    head = png.read_bytes()[:24]
    if head[:8] != b"\x89PNG\r\n\x1a\n":continue
    w, h = struct.unpack(">II", head[16:24])
    if max(w, h) <= LIMIT:continue
    text = imp.read_text("utf-8")
    new = re.sub(r"^process/size_limit=\d+$", f"process/size_limit={LIMIT}", text, flags=re.M)
    if new == text and "process/size_limit=" not in text:
        new = text.replace("[params]\n", f"[params]\n\nprocess/size_limit={LIMIT}\n", 1)
    if new != text:
        imp.write_text(new, "utf-8"); changed += 1
        print(f"{png.name}: {w}x{h} -> at most {LIMIT}")
print(f"WEB_TEXTURE_LIMITS changed {changed}")
