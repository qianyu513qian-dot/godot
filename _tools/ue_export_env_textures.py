# Unreal Editor Python: export Fantastic Village Pack env textures to PNG
import unreal
import os

OUT = r"C:\Users\cc\Documents\GodotProjects\AoELite3D\assets\fantastic_village\env"
os.makedirs(OUT, exist_ok=True)

ASSETS = [
    "/Game/Fantastic_Village_Pack/textures/T_ENV_TERRAIN_grass_01_BC",
    "/Game/Fantastic_Village_Pack/textures/T_ENV_TERRAIN_grass_01_N",
    "/Game/Fantastic_Village_Pack/textures/T_ENV_TERRAIN_gravel_BC",
    "/Game/Fantastic_Village_Pack/textures/T_ENV_TERRAIN_gravel_N",
    "/Game/Fantastic_Village_Pack/textures/T_ENV_TERRAIN_gravel_02_BC",
    "/Game/Fantastic_Village_Pack/textures/T_ENV_TERRAIN_gravel_02_N",
    "/Game/Fantastic_Village_Pack/textures/T_ENV_farmfield_BC",
    "/Game/Fantastic_Village_Pack/textures/T_ENV_farmfield_N",
    "/Game/Fantastic_Village_Pack/textures/T_ENV_pavingstone_01_BC",
    "/Game/Fantastic_Village_Pack/textures/T_ENV_pavingstone_01_N",
    "/Game/Fantastic_Village_Pack/textures/T_ENV_pavingstone_02_BC",
    "/Game/Fantastic_Village_Pack/textures/T_ENV_pavingstone_02_N",
    "/Game/Fantastic_Village_Pack/textures/T_ENV_SKYBOX_01",
    "/Game/Fantastic_Village_Pack/textures/T_ENV_SKYBOX_02",
    "/Game/Fantastic_Village_Pack/textures/T_ENV_stone_BC",
    "/Game/Fantastic_Village_Pack/textures/T_ENV_stone_N",
    "/Game/Fantastic_Village_Pack/textures/T_ENV_grass_village_BC",
]

ok = 0
fail = []
for path in ASSETS:
    name = path.rsplit("/", 1)[-1]
    asset = unreal.EditorAssetLibrary.load_asset(path)
    if asset is None:
        fail.append(path + " (load None)")
        unreal.log_warning("FAIL load " + path)
        continue
    out_path = os.path.join(OUT, name + ".png")
    task = unreal.AssetExportTask()
    task.set_editor_property("object", asset)
    task.set_editor_property("filename", out_path)
    task.set_editor_property("selected", False)
    task.set_editor_property("replace_identical", True)
    task.set_editor_property("prompt", False)
    task.set_editor_property("automated", True)
    task.set_editor_property("exporter", unreal.TextureExporterPNG())
    success = unreal.Exporter.run_asset_export_task(task)
    if success and os.path.exists(out_path):
        ok += 1
        unreal.log("OK " + out_path)
    else:
        # fallback TGA
        out_tga = os.path.join(OUT, name + ".tga")
        task2 = unreal.AssetExportTask()
        task2.set_editor_property("object", asset)
        task2.set_editor_property("filename", out_tga)
        task2.set_editor_property("selected", False)
        task2.set_editor_property("replace_identical", True)
        task2.set_editor_property("prompt", False)
        task2.set_editor_property("automated", True)
        task2.set_editor_property("exporter", unreal.TextureExporterTGA())
        success2 = unreal.Exporter.run_asset_export_task(task2)
        if success2 and os.path.exists(out_tga):
            ok += 1
            unreal.log("OK TGA " + out_tga)
        else:
            fail.append(path)
            unreal.log_warning("FAIL export " + path)

unreal.log("EXPORT_DONE ok=%d fail=%d" % (ok, len(fail)))
for f in fail:
    unreal.log_warning("FAILED: " + f)

done_marker = os.path.join(OUT, "_export_done.txt")
with open(done_marker, "w", encoding="utf-8") as fh:
    fh.write("ok=%d fail=%d\n" % (ok, len(fail)))
    for f in fail:
        fh.write("FAIL " + f + "\n")
