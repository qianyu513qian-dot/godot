import os, struct
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
for name in targets:
    path = os.path.join(texdir, name + ".uasset")
    if not os.path.exists(path):
        print("MISSING", name); continue
    data = open(path,"rb").read()
    # look for known headers
    markers = {
        b"\x89PNG": "png",
        b"DDS ": "dds",
        b"\x00\x00\x02\x00": "tga?",  # too common
    }
    found = []
    for magic, kind in [(b"\x89PNG\r\n\x1a\n","png"), (b"DDS ","dds"), (b"\xff\xd8\xff","jpg")]:
        i = 0
        while True:
            j = data.find(magic, i)
            if j < 0: break
            found.append((j, kind))
            i = j+1
    print(f"{name}: size={len(data)} hits={found[:5]}")
    # Also check for Oodle/UE bulk markers
    for m in [b"UNREALTEXTURE", b"PF_", b"BC7", b"DXT", b"ASTC"]:
        if m in data:
            print(f"  contains {m}")
