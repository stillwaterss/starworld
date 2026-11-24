"""v36 (Claude): gzip parts + manifest for site/assets/star-loader-v37.js (v36 format, unchanged).
Run after the Web export, the WebLate pack export and scripts/fingerprint_pack.py:
    python3 scripts/web_pack.py
  site/play/parts/<version>/index.wasm.gz.000 …, <pack>.gz.000 …, late.pck.gz.000 …
  site/play/starworld_manifest.json   (the loader always fetches it fresh)
Parts are 1 MB: on a slow line a refresh keeps every finished part. The folder name is the
content version, so a browser can never mix parts of two releases. index.wasm and the
fingerprinted pack stay beside them: without the manifest the page loads them as before.
"""
import gzip, hashlib, json, pathlib, re, shutil

PLAY = pathlib.Path(__file__).resolve().parents[1] / "site/play"
PART = 1 << 20
html = (PLAY / "index.html").read_text("utf-8")
m = re.search(r'config\.mainPack = "([^"]+)";', html)
assert m, "run scripts/fingerprint_pack.py first"
pck_name = m.group(1)
sources = {"wasm": PLAY / "index.wasm", "pck": PLAY / pck_name}
if (PLAY / "late.pck").exists():sources["late"] = PLAY / "late.pck"
zipped = {k: gzip.compress(p.read_bytes(), 9, mtime=0) for k, p in sources.items()}
version = hashlib.sha256(b"".join(zipped[k] for k in sorted(zipped))).hexdigest()[:12]
out = PLAY / "parts" / version
if (PLAY / "parts").exists():shutil.rmtree(PLAY / "parts")
out.mkdir(parents=True)
files = {}
for key, data in zipped.items():
    src = sources[key]
    parts = []
    for i in range(0, len(data), PART):
        name = f"{src.name}.gz.{i // PART:03d}"
        (out / name).write_bytes(data[i:i + PART])
        parts.append({"name": f"parts/{version}/{name}", "size": len(data[i:i + PART])})
    files[key] = {"raw": src.stat().st_size, "parts": parts}
    print(f"{src.name:28s} {src.stat().st_size / 1048576:7.1f} MB -> gzip {len(data) / 1048576:6.1f} MB, {len(parts)} parts")
if "late" in sources:sources["late"].unlink()   # only its parts are needed
# extra download addresses (each must hold this play/ folder's parts/ and allow CORS), one
# per line in scripts/web_mirrors.txt; the page can add more in window.STAR_MIRRORS
mirror_file = pathlib.Path(__file__).resolve().parent / "web_mirrors.txt"
mirrors = [l.strip() for l in mirror_file.read_text("utf-8").splitlines() if l.strip() and not l.startswith("#")] if mirror_file.exists() else []
(PLAY / "starworld_manifest.json").write_text(json.dumps({"version": version, "wasm_name": "index.wasm", "pck_name": pck_name, "mirrors": mirrors, "files": files}, indent=1), "utf-8")
first = sum(p["size"] for k in ("wasm", "pck") for p in files[k]["parts"])
late = sum(p["size"] for p in files.get("late", {"parts": []})["parts"])
print(f"first download {first / 1048576:.1f} MB (gzip), late pack {late / 1048576:.1f} MB, version {version}")
