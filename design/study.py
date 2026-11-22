"""Stage the linked HK 3770 and RM mini 3 at their relative sizes for the design board."""

import bpy
from mathutils import Vector


def render_study(directory):
    # The products in the still come from the same exported meshes as the app portraits.
    scene = bpy.data.scenes.new("Linked equipment")
    bpy.context.window.scene = scene
    for model, position, angle in [("HK3770", (0, 0, 0), 0), ("RMmini3", (0.132, 0.038, 0.121), -0.22)]:
        bpy.ops.import_scene.gltf(filepath=str(directory / "models" / (model + ".glb")))
        root = next(o for o in bpy.context.selected_objects if not o.parent)
        root.location = position
        root.rotation_euler.z = angle
    bpy.ops.mesh.primitive_plane_add(size=200)
    floor = bpy.context.object
    floor.name = "Clay studio sweep"
    ground = bpy.data.materials.new("Burnt orange sweep")
    ground.use_nodes = True
    ground.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.69, 0.174, 0.064, 1)
    ground.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.87
    floor.data.materials.append(ground)
    target = Vector((-0.117, -0.048, 0.077))
    direction = Vector((0.48, -1.7, 0.47)).normalized()
    bpy.ops.object.camera_add(location=target + direction * 2)
    cam = bpy.context.object
    cam.name = "Linked equipment camera"
    cam.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 0.88
    scene.camera = cam
    for name, loc, power, width, height, color in [
        ("Broad key", (-0.72, -0.55, 0.97), 29, 0.72, 0.38, (1, 0.89, 0.78)),
        ("Rim strip", (0.34, 0.73, 0.8), 45, 0.84, 0.17, (0.84, 0.92, 1)),
        ("Fascia strip", (0.72, -0.65, 0.38), 16, 0.14, 0.84, (1, 0.93, 0.85)),
    ]:
        bpy.ops.object.light_add(type="AREA", location=loc)
        light = bpy.context.object
        light.name = name
        light.rotation_euler = (-light.location).to_track_quat("-Z", "Y").to_euler()
        light.data.shape = "RECTANGLE"
        light.data.size = width
        light.data.size_y = height
        light.data.energy = power
        light.data.color = color
    scene.world = bpy.data.worlds["Diffuse studio"]
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 40
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1800
    scene.render.resolution_y = 580
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.filepath = str(directory / "linked-equipment.png")
    bpy.ops.render.render(write_still=True)
    return scene
