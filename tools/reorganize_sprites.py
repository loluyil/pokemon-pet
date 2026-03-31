"""
Reorganizes sprites/pokemon/front/ into per-Pokemon subdirectories and
generates SpriteFrames .tres files for each Pokemon.

Before: sprites/pokemon/front/abomasnow.png
After:  sprites/pokemon/front/abomasnow/abomasnow.png
        sprites/pokemon/front/abomasnow/abomasnow_back.png
        sprites/pokemon/front/abomasnow/abomasnow_anim.tres
"""

import os
import re
import shutil
import random
import string

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FRONT_DIR    = os.path.join(PROJECT_ROOT, "sprites", "pokemon", "front")
META_PATH    = os.path.join(PROJECT_ROOT, "scripts", "sprite_meta.gd")

# ── Parse sprite_meta.gd ──────────────────────────────────────────────────────

def parse_sprite_meta(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    result = {}
    for m in re.finditer(r'"([^"]+)":\s*\{([^}]+)\}', content):
        name = m.group(1)
        props = {k: int(v) for k, v in re.findall(r'"(\w+)":\s*(\d+)', m.group(2))}
        result[name] = props
    return result

# ── UID / ID helpers ──────────────────────────────────────────────────────────

_UID_CHARS = string.ascii_lowercase + string.digits

def gen_uid() -> str:
    return "uid://" + "".join(random.choices(_UID_CHARS, k=13))

def gen_id(prefix: str = "") -> str:
    return prefix + "".join(random.choices(string.ascii_letters + string.digits, k=6))

# ── .tres generation ──────────────────────────────────────────────────────────

def build_tres(name: str, meta: dict, has_back: bool) -> str:
    ff = meta.get("ff", 0)
    fc = meta.get("fc", 1)
    fh = meta.get("fh", 0)
    bf = meta.get("bf", 0)
    bc = meta.get("bc", 1)
    bh = meta.get("bh", 0)

    front_path = f"res://sprites/pokemon/front/{name}/{name}.png"
    back_path  = f"res://sprites/pokemon/front/{name}/{name}_back.png"

    front_ext = gen_id("fe_")
    back_ext  = gen_id("be_") if has_back else None

    # Count sub-resources
    front_animated = ff > 0 and fc > 1
    back_animated  = has_back and bf > 0 and bc > 1
    n_sub = (fc if front_animated else 0) + (bc if back_animated else 0)
    n_ext = 1 + (1 if has_back else 0)
    load_steps = n_ext + n_sub + 1

    out = []
    out.append(f'[gd_resource type="SpriteFrames" load_steps={load_steps} format=3 uid="{gen_uid()}"]')
    out.append("")
    out.append(f'[ext_resource type="Texture2D" path="{front_path}" id="{front_ext}"]')
    if has_back:
        out.append(f'[ext_resource type="Texture2D" path="{back_path}" id="{back_ext}"]')
    out.append("")

    # AtlasTexture sub-resources for front animation frames
    front_frame_refs = []
    if front_animated:
        for i in range(fc):
            sid = f"AtlasTexture_f{i}"
            out.append(f'[sub_resource type="AtlasTexture" id="{sid}"]')
            out.append(f'atlas = ExtResource("{front_ext}")')
            out.append(f'region = Rect2({i * ff}, 0, {ff}, {fh})')
            out.append("")
            front_frame_refs.append(f'SubResource("{sid}")')
    else:
        front_frame_refs.append(f'ExtResource("{front_ext}")')

    # AtlasTexture sub-resources for back animation frames
    back_frame_refs = []
    if has_back:
        if back_animated:
            for i in range(bc):
                sid = f"AtlasTexture_b{i}"
                out.append(f'[sub_resource type="AtlasTexture" id="{sid}"]')
                out.append(f'atlas = ExtResource("{back_ext}")')
                out.append(f'region = Rect2({i * bf}, 0, {bf}, {bh})')
                out.append("")
                back_frame_refs.append(f'SubResource("{sid}")')
        else:
            back_frame_refs.append(f'ExtResource("{back_ext}")')

    # resource section
    out.append("[resource]")

    def frames_array(refs: list) -> str:
        parts = [f'{{"duration": 1.0, "texture": {r}}}' for r in refs]
        return "[" + ", ".join(parts) + "]"

    animations = []
    animations.append(
        f'{{"frames": {frames_array(front_frame_refs)}, "loop": true, "name": &"front", "speed": 6.0}}'
    )
    if has_back:
        animations.append(
            f'{{"frames": {frames_array(back_frame_refs)}, "loop": true, "name": &"back", "speed": 6.0}}'
        )

    out.append("animations = [" + ", ".join(animations) + "]")
    return "\n".join(out)

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    sprite_meta = parse_sprite_meta(META_PATH)

    # Collect all Pokemon names from filenames (strip _back suffix)
    png_files = [f for f in os.listdir(FRONT_DIR)
                 if f.endswith(".png") and not f.endswith("_back.png")
                 and os.path.isfile(os.path.join(FRONT_DIR, f))]
    pokemon_names = sorted(f[:-4] for f in png_files)  # strip .png

    print(f"Found {len(pokemon_names)} Pokemon to reorganize.")

    moved = 0
    tres_created = 0

    for name in pokemon_names:
        dest_dir = os.path.join(FRONT_DIR, name)
        os.makedirs(dest_dir, exist_ok=True)

        front_src = os.path.join(FRONT_DIR, f"{name}.png")
        back_src  = os.path.join(FRONT_DIR, f"{name}_back.png")
        has_back  = os.path.isfile(back_src)

        # Move front PNG
        if os.path.isfile(front_src):
            shutil.move(front_src, os.path.join(dest_dir, f"{name}.png"))
            moved += 1

        # Move back PNG
        if has_back:
            shutil.move(back_src, os.path.join(dest_dir, f"{name}_back.png"))
            moved += 1

        # Remove stale .import files (Godot regenerates on next open)
        for stale in [f"{name}.png.import", f"{name}_back.png.import"]:
            stale_path = os.path.join(FRONT_DIR, stale)
            if os.path.isfile(stale_path):
                os.remove(stale_path)

        # Generate .tres
        meta = sprite_meta.get(name, {})
        tres_content = build_tres(name, meta, has_back)
        tres_path = os.path.join(dest_dir, f"{name}_anim.tres")
        with open(tres_path, "w", encoding="utf-8") as f:
            f.write(tres_content)
        tres_created += 1

    print(f"Moved {moved} PNG files into subdirectories.")
    print(f"Created {tres_created} SpriteFrames .tres files.")
    print("Done. Re-open the Godot project to reimport sprites.")

if __name__ == "__main__":
    main()
