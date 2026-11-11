"""Remove redundant cobbles at the six path joins in the v16 island export.

Only the named merged paving meshes and known duplicate component centres are
touched. Trim index accessors in place so the other meshes and materials stay
byte-for-byte intact. Run against a fresh GLB when re-importing the v16 island.
"""
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXES = {
    "Decor_Details_stone_dark": [
        (-12.020, .075, 3.598), (-11.981, .075, 4.760), (-12.001, .075, 4.157),
        (-8.462, .075, 8.677), (-7.558, .075, 9.309), (-7.983, .075, 9.008),
        (7.499, .075, 9.253), (7.981, .075, 9.013), (8.440, .075, 8.692),
        (10.061, .075, -3.135), (9.987, .075, -2.001), (-8.094, 2.575, -5.416),
    ],
    "Decor_Details_stone_light": [
        (-7.552, 2.575, -5.494), (10.001, .075, -2.652), (-7.029, 2.575, -5.426),
    ],
}


def fix(path: Path) -> None:
    original = path.read_bytes()
    size, json_tag = struct.unpack_from("<II", original, 12)
    asset = json.loads(original[20:20 + size])
    length, bin_tag = struct.unpack_from("<II", original, 20 + size)
    binary = bytearray(original[28 + size:])
    assert len(binary) == length

    def view(accessor_id):
        accessor = asset["accessors"][accessor_id]
        info = asset["bufferViews"][accessor["bufferView"]]
        assert "byteStride" not in info
        return accessor, info.get("byteOffset", 0) + accessor.get("byteOffset", 0)

    removed = 0
    for node in asset["nodes"]:
        targets = FIXES.get(node.get("name"))
        if not targets:
            continue
        primitive, = asset["meshes"][node["mesh"]]["primitives"]
        positions, offset = view(primitive["attributes"]["POSITION"])
        assert positions["type"] == "VEC3" and positions["componentType"] == 5126
        points = list(struct.iter_unpack("<fff", binary[offset:offset + positions["count"] * 12]))
        indices, offset = view(primitive["indices"])
        fmt = {5123: "H", 5125: "I"}[indices["componentType"]]
        data = struct.unpack_from(f"<{indices['count']}{fmt}", binary, offset)
        triangles = list(zip(data[::3], data[1::3], data[2::3]))
        # Weld position only for the connectivity check; UV/normal seams remain intact.
        keys = [tuple(round(v, 5) for v in p) for p in points]
        linked = {}
        for triangle in triangles:
            group = [keys[i] for i in triangle]
            for point in group:
                linked.setdefault(point, set()).update(group)
        seen, drop, matched = set(), set(), set()
        for point in linked:
            if point in seen:
                continue
            component = [point]
            seen.add(point)
            for vertex in component:
                neighbors = linked[vertex] - seen
                component.extend(neighbors)
                seen.update(neighbors)
            axes = list(zip(*component))
            center = tuple((min(axis) + max(axis)) / 2 for axis in axes)
            if max(axes[1]) - min(axes[1]) > .12:
                continue
            for target in targets:
                if max(abs(a - b) for a, b in zip(center, target)) < .016:
                    assert target not in matched
                    matched.add(target)
                    drop.update(component)
        if not matched:
            continue
        assert len(matched) == len(targets), (node["name"], set(targets) - matched)
        keep = [i for tri in triangles if keys[tri[0]] not in drop for i in tri]
        assert len(keep) < len(data)
        struct.pack_into(f"<{len(keep)}{fmt}", binary, offset, *keep)
        indices["count"] = len(keep)
        indices["min"] = [min(keep)]
        indices["max"] = [max(keep)]
        removed += len(matched)
    if not removed:
        print("Paving: no duplicate components found")
        return
    assert removed == sum(map(len, FIXES.values()))
    header = json.dumps(asset, separators=(",", ":")).encode()
    header += b" " * (-len(header) % 4)
    result = struct.pack("<4sII", b"glTF", 2, 28 + len(header) + length)
    result += struct.pack("<II", len(header), json_tag) + header
    result += struct.pack("<II", length, bin_tag) + binary
    path.write_bytes(result)
    print(f"Paving: removed {removed} overlapping cobbles")


if __name__ == "__main__":
    fix(ROOT / "game/assets/island.glb")
