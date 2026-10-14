import os, struct, zlib
OUT = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\assets\fantastic_village\env"
os.makedirs(OUT, exist_ok=True)
texdir = r"E:\UE\fantasy\Content\Fantastic_Village_Pack\textures"
targets = [
"T_ENV_TERRAIN_grass_01_BC","T_ENV_TERRAIN_grass_01_N",
"T_ENV_TERRAIN_gravel_BC","T_ENV_TERRAIN_gravel_N",
"T_ENV_TERRAIN_gravel_02_BC","T_ENV_TERRAIN_gravel_02_N",
"T_ENV_farmfield_BC","T_ENV_farmfield_N",
"T_ENV_pavingstone_01_BC","T_ENV_pavingstone_01_N",
"T_ENV_pavingstone_02_BC","T_ENV_pavingstone_02_N",
"T_ENV_SKYBOX_01","T_ENV_SKYBOX_02",
"T_ENV_stone_BC","T_ENV_stone_N","T_ENV_grass_village_BC",
]
PNG_SIG = b"\x89PNG\r\n\x1a\n"

def extract_pngs(data):
    out = []
    i = 0
    while True:
        j = data.find(PNG_SIG, i)
        if j < 0:
            break
        # walk PNG chunks until IEND
        pos = j + 8
        ok = False
        while pos + 8 <= len(data):
            length = struct.unpack(">I", data[pos:pos+4])[0]
            ctype = data[pos+4:pos+8]
            pos += 8 + length + 4  # len+type+data+crc
            if ctype == b"IEND":
                ok = True
                break
            if length > 200_000_000 or pos > len(data):
                break
        if ok:
            blob = data[j:pos]
            # IHDR
            w = struct.unpack(">I", blob[16:20])[0]
            h = struct.unpack(">I", blob[20:24])[0]
            out.append((w, h, len(blob), blob))
        i = j + 1
    return out

for name in targets:
    path = os.path.join(texdir, name + ".uasset")
    data = open(path, "rb").read()
    pngs = extract_pngs(data)
    print(f"{name}: {len(pngs)} pngs -> " + ", ".join(f"{w}x{h}({sz})" for w,h,sz,_ in pngs))
    if not pngs:
        continue
    # pick largest by pixel count, then by file size
    best = max(pngs, key=lambda t: (t[0]*t[1], t[2]))
    out_path = os.path.join(OUT, name + ".png")
    open(out_path, "wb").write(best[3])
    print(f"  wrote {out_path} {best[0]}x{best[1]} {best[2]} bytes")
print("DONE")
