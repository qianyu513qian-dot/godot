import json, struct, os, sys
blend = r"C:\ProgramData\Epic\EpicGamesLauncher\VaultCache\FabLibrary\FANTASTIC_-_Village_Pack-52529a12\blender\fantastic_village_pack_blend.blend"
# Blender files aren't easy raw-parse; try listing via bpy if blender exists
print("blend exists", os.path.exists(blend), "size", os.path.getsize(blend) if os.path.exists(blend) else 0)
# Search for PNG/JPG magic inside blend (packed images sometimes embedded)
with open(blend, "rb") as f:
    data = f.read()
names = []
for needle in [b"T_ENV_", b"SKYBOX", b"TERRAIN", b"grass", b"gravel", b"farmfield", b"paving"]:
    idx = 0
    while True:
        i = data.find(needle, idx)
        if i < 0: break
        chunk = data[i:i+80]
        # extract printable
        s = ""
        for b in chunk:
            if 32 <= b < 127: s += chr(b)
            else: break
        if s and s not in names:
            names.append(s)
        idx = i + 1
print("found name-like strings:")
for n in sorted(names)[:80]:
    print(n)
