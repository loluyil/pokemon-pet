"""
Removes embedded binary sub-resources from battle_scene.tscn that inflate it
to 75 MiB:

  - All Image sub-resources  (Godot font-glyph cache — regenerated at runtime)
  - SpriteFrames_svpld / SpriteFrames_y8gcu  (pokemon sprites now runtime-loaded)
  - FontFile_m0ksu  (full .otf embedded as PackedByteArray)

Replaces SubResource("FontFile_m0ksu") → ExtResource("13_16mmc"), which is the
already-present ext_resource pointing to the same font file on disk.
"""

import re, os, shutil

SCENE = os.path.join(os.path.dirname(__file__), "..", "scenes", "battle_scene.tscn")

# Sub-resource IDs to remove entirely
REMOVE_BY_ID = {"SpriteFrames_svpld", "SpriteFrames_y8gcu", "FontFile_m0ksu"}

# Sub-resource TYPES to remove entirely (all instances)
REMOVE_BY_TYPE = {"Image"}

# Node properties to strip (stripped line match)
REMOVE_PROPS = {
    'sprite_frames = SubResource("SpriteFrames_svpld")',
    'sprite_frames = SubResource("SpriteFrames_y8gcu")',
}

# Inline sub-resource reference → ext-resource replacement
REPLACE_FONT = ('SubResource("FontFile_m0ksu")', 'ExtResource("13_16mmc")')

# ─────────────────────────────────────────────────────────────────────────────

HEADER_RE = re.compile(r"^\[")

def parse_sections(text):
    sections = []
    cur_header, cur_body = None, []
    for line in text.splitlines(keepends=True):
        if HEADER_RE.match(line):
            if cur_header is not None:
                sections.append((cur_header, cur_body))
            cur_header, cur_body = line, []
        else:
            cur_body.append(line)
    if cur_header is not None:
        sections.append((cur_header, cur_body))
    return sections

def get_attr(header, attr):
    m = re.search(rf'{attr}="([^"]+)"', header)
    return m.group(1) if m else None

def should_drop_section(header):
    if "[sub_resource" not in header:
        return False
    sid   = get_attr(header, "id")
    stype = get_attr(header, "type")
    return sid in REMOVE_BY_ID or stype in REMOVE_BY_TYPE

def clean_body(body):
    result = []
    for line in body:
        if line.strip() in REMOVE_PROPS:
            continue
        if REPLACE_FONT[0] in line:
            line = line.replace(REPLACE_FONT[0], REPLACE_FONT[1])
        result.append(line)
    return result

def clean(text):
    sections = parse_sections(text)
    out = []
    for header, body in sections:
        if should_drop_section(header):
            continue
        out.append(header)
        out.extend(clean_body(body))
    return "".join(out)

def main():
    print(f"Reading {SCENE} …")
    with open(SCENE, "r", encoding="utf-8") as f:
        original = f.read()
    print(f"  Original size: {len(original) / 1_048_576:.1f} MiB")

    # Use the .bak as the source of truth if it already exists (original clean)
    bak = SCENE + ".bak"
    source = original
    if os.path.exists(bak):
        with open(bak, "r", encoding="utf-8") as f:
            source = f.read()
        print(f"  Using backup as source ({len(source)/1_048_576:.1f} MiB)")
    else:
        shutil.copy2(SCENE, bak)
        print(f"  Backup written to {os.path.basename(bak)}")

    cleaned = clean(source)

    with open(SCENE, "w", encoding="utf-8") as f:
        f.write(cleaned)
    print(f"  Cleaned size:  {len(cleaned) / 1_048_576:.1f} MiB")
    print("Done.")

if __name__ == "__main__":
    main()
