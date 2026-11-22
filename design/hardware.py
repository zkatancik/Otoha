"""Rebuild the editable product library, metre-scale GLBs and shared app portraits.
blender -b --factory-startup --python-exit-code 1 -P design/hardware.py
Pass model keys after -- for a partial GLB/portrait rebuild.
"""

import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

DESIGN = Path(__file__).resolve().parent
sys.dont_write_bytecode = True
sys.path.insert(0, str(DESIGN))
from hardware_catalog import catalog

MODELS = list(catalog())
APP_ART = DESIGN.parent / "ios/Otoha/hardware"
GLBS = DESIGN / "models"
MM = 0.001
TAU = math.tau


def metres(coords):
    return tuple(value * MM for value in coords)


def material(name, color, metal=0, rough=0.38, transmission=0):
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes["Principled BSDF"]
    for socket, value in [
        ("Base Color", (*color, 1)),
        ("Metallic", metal),
        ("Roughness", rough),
        ("Transmission Weight", transmission),
    ]:
        shader.inputs[socket].default_value = value
    return mat


def finish(obj, name, mat, bevel=0):
    obj.name = name
    obj.data.materials.append(mat)
    if bevel:
        edge = obj.modifiers.new("Edge radius", "BEVEL")
        edge.width = bevel * MM
        edge.segments = 3
        normal = obj.modifiers.new("Panel normals", "WEIGHTED_NORMAL")
        normal.keep_sharp = True
    return obj


def box(name, pos, size, mat, bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=metres(pos))
    obj = bpy.context.object
    obj.dimensions = metres(size)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, mat, bevel)


def disc(name, pos, radius, depth, mat, front=False, bevel=0):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=64,
        radius=radius * MM,
        depth=depth * MM,
        location=metres(pos),
        rotation=(math.pi / 2 if front else 0, 0, 0),
    )
    obj = bpy.context.object
    for p in obj.data.polygons:
        p.use_smooth = len(p.vertices) == 4
    return finish(obj, name, mat, bevel)


def mesh(name, verts, faces, mat, bevel=0):
    data = bpy.data.meshes.new(name)
    data.from_pydata([metres(v) for v in verts], [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    return finish(obj, name, mat, bevel)


def shell(name, rings, mat, segments=80):
    # Each ring gives height and radius. Doubling back makes the inside wall of an open port.
    verts = [
        (r * math.cos(TAU * i / segments), r * math.sin(TAU * i / segments), z)
        for z, r in rings
        for i in range(segments)
    ]
    faces = []
    for row in range(len(rings) - 1):
        for i in range(segments):
            a = row * segments + i
            b = row * segments + (i + 1) % segments
            faces.append((a, b, b + segments, a + segments))
    faces.extend([tuple(reversed(range(segments))), tuple(range(len(verts) - segments, len(verts)))])
    obj = mesh(name, verts, faces, mat)
    for p in list(obj.data.polygons)[:-2]:
        p.use_smooth = True
    return obj


def outline(name, points, layers, mat, bevel=0):
    verts = [(x * s, y * s, z) for z, s in layers for x, y in points]
    n = len(points)
    faces = [tuple(reversed(range(n)))]
    for row in range(len(layers) - 1):
        for i in range(n):
            a = row * n + i
            b = row * n + (i + 1) % n
            faces.append((a, b, b + n, a + n))
    faces.append(tuple(range(len(verts) - n, len(verts))))
    return mesh(name, verts, faces, mat, bevel)


def rounded_rect(w, d, r):
    pts = []
    for x, y, angle in [
        (w / 2 - r, d / 2 - r, 0),
        (-w / 2 + r, d / 2 - r, 90),
        (-w / 2 + r, -d / 2 + r, 180),
        (w / 2 - r, -d / 2 + r, 270),
    ]:
        for i in range(11):
            a = math.radians(angle + 9 * i)
            pts.append((x + r * math.cos(a), y + r * math.sin(a)))
    return pts


def rod(name, points, radius, mat, closed=False):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius * MM
    curve.bevel_resolution = 3
    curve.resolution_u = 1
    curve.use_fill_caps = True
    path = curve.splines.new("POLY")
    path.points.add(len(points) - 1)
    for p, v in zip(path.points, points):
        p.co = (*metres(v), 1)
    path.use_cyclic_u = closed
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def typeface(body, pos, size, mat, top=False, align="LEFT"):
    bpy.ops.object.text_add(location=metres(pos), rotation=(0 if top else math.pi / 2, 0, 0))
    obj = bpy.context.object
    obj.name = "Legend · " + body
    obj.data.body = body
    obj.data.align_x = align
    obj.data.size = size * MM
    obj.data.resolution_u = 4
    obj.data.materials.append(mat)
    return obj


def socket(x, y, z, r=3.5):
    disc("Jack bezel", (x, y, z), r, 1.4, nickel, True, 0.24)
    disc("Jack bore", (x, y - 0.83, z), r * 0.69, 0.55, void, True)


def usb(x, y, z):
    box("USB shield", (x, y, z), (13.2, 1.6, 6.2), nickel, 0.55)
    box("USB opening", (x, y - 0.9, z), (11.8, 0.5, 4.7), void, 0.3)
    box("USB tongue", (x, y - 1.22, z - 0.8), (9.3, 0.18, 1), graphite)


def feet(w, d, h):
    for x in (-w * 0.38, w * 0.38):
        for y in (-d * 0.43, d * 0.40):
            disc("Isolator", (x, y, h / 2), w * 0.042, h, rubber, bevel=1.3)


def vented_cover(w, d, h, foot):
    # Between punched slots the top is a continuous sheet. A recessed dark backing
    # gives each opening depth at the low equipment-plate camera angle.
    top = h - 1.4
    box("Enclosure interior", (0, 4, (foot + top - 4) / 2), (w - 4, d - 10, top - 4 - foot), void, 2)
    for side in (-1, 1):
        box("Folded side", (side * (w / 2 - 1.8), 4, (foot + h) / 2), (2, d - 8, h - foot), graphite, 0.8)
    xs = [-w / 2 + 1] + [(-16.5 + i) * 8.6 for i in range(34)] + [w / 2 - 1]
    ys = [-d / 2 + 8, -d * 0.30, 0, d * 0.30, d / 2]
    verts = []
    faces = []
    for i, (left, right) in enumerate(zip(xs, xs[1:])):
        for j, (front, back) in enumerate(zip(ys, ys[1:])):
            start = len(verts)
            verts.extend([(left, front, h), (right, front, h), (right, back, h), (left, back, h)])
            if i in (0, len(xs) - 2) or j in (0, 3):
                faces.append(tuple(start + n for n in range(4)))
                continue
            cx = (left + right) / 2
            inner = [
                (cx - 1.85, front + 5),
                (cx + 1.85, front + 5),
                (cx + 1.85, back - 5),
                (cx - 1.85, back - 5),
            ]
            verts.extend([(x, y, z) for z in (h, top) for x, y in inner])
            for k in range(4):
                n = (k + 1) % 4
                faces.append(tuple(start + t for t in (k, n, 4 + n, 4 + k)))
                faces.append(tuple(start + t for t in (4 + k, 4 + n, 8 + n, 8 + k)))
    mesh("Punched steel lid", verts, faces, graphite)


def rear_panel(model, depth, height):
    # Coordinates run right-to-left in a rear view of the unit.
    y = depth / 2
    box("Rear terminal plate", (0, y - 1.6, (height + 10) / 2), (435, 2.5, height - 12), metal, 1)
    bank = 4 if model.form == "stereo" else 7 if model.form in ("avr-171", "avr-270", "avr-370") else 5
    for i in range(bank):
        x = 10 + (i - (bank - 1) / 2) * 19
        for j, m in enumerate((rubber, red)):
            z = 28 + j * 17
            disc("Speaker binding post", (x, y + 3, z), 5.3, 7.2, m, True, 0.7)
            disc("Banana plug bore", (x, y + 6.7, z), 2, 1, void, True)
    for i in range(6 if model.form == "stereo" else 3):
        x = 98 + i * 16
        for j, m in enumerate((red, bone)):
            z = 28 + j * 15
            disc("Line input insulator", (x, y + 0.7, z), 4.5, 2, m, True, 0.4)
            disc("RCA shield", (x, y + 3, z), 3.55, 4, nickel, True, 0.3)
            disc("RCA opening", (x, y + 5.1, z), 1.9, 0.4, void, True)
    z = height - 27
    box("Network socket", (164, y + 0.4, z), (17, 2, 14), nickel, 0.65)
    box("RJ45 opening", (164, y + 1.6, z), (14, 1, 10), void, 0.4)
    if model.form == "stereo":
        if model.key == "HK3770":
            for x in (-86, -104):
                box("Optical input", (x, y + 1, z), (12, 4, 11), rubber, 1)
            disc("Coaxial digital input", (-122, y + 3, z), 4.4, 6, nickel, True, 0.4)
    else:
        inputs = {"avr-151": 4, "avr-161": 5, "avr-171": 6, "avr-170": 6, "avr-270": 7, "avr-370": 7}
        for i in range(inputs[model.form] + 1):
            x = 97 - i * 24
            box("HDMI shield", (x, y + 0.2, z), (16, 2, 6.5), nickel, 0.9)
            box("HDMI opening", (x, y + 1.4, z), (13.6, 0.8, 4), void, 0.55)
    box("Mains inlet", (-177, y + 0.5, 36), (26, 3, 17), rubber, 2)
    box("Inlet well", (-177, y + 2.2, 36), (21, 1.2, 11), void, 1)
    for dx in (-5, 5):
        box("Inlet pin", (-177 + dx, y + 3, 36), (1.6, 2, 5), nickel, 0.25)


def rack(model):
    stereo = model.form == "stereo"
    tall = model.form in ("avr-170", "avr-270", "avr-370")
    w, h, d = 440, (165 if tall else 121), (377 if model.form == "avr-170" else 435 if tall else 300)
    y = -d / 2
    foot = 12 if tall else 9
    feet(w, d, foot)
    vented_cover(w, d, h, foot)
    rear_panel(model, d, h)
    seam = h * (0.52 if tall else 0.44)
    box("Brushed lower fascia", (0, y + 2, (foot + seam) / 2), (w, 7, seam - foot), metal, 1.5)
    box("Smoked display glass", (0, y + 1, (h + seam) / 2), (w, 8, h - seam), glass, 2)
    for i in range(16):
        box("Control key", (-204 + i * 25, y - 3.5, seam + 0.9), (15.5, 2, 2), key, 0.6)
    z = seam + (h - seam) * 0.55
    r = 27 if tall else 22
    disc("Machined volume surround", (172, y - 3, z), r + 2, 3, silver, True, 1)
    disc("Light guide", (172, y - 5, z), r, 0.9, frost, True, 0.4)
    disc("Recessed rotary encoder", (172, y - 6.5, z), r - 2.6, 3.6, metal, True, 1.6)
    typeface(model.label, (-204, y - 3.2, h - 11), 5, silver)
    typeface("harman/kardon", (0, y - 1.8, foot + (seam - foot) * 0.40), 8, silver, align="CENTER")
    typeface("FM   87.50  MHz", (-42, y - 3.26, z), 7.4, phosphor)
    box("Standby indicator", (-204, y - 3.45, seam + 4.2), (5, 0.8, 1.1), frost, 0.35)
    x = 104 if model.form == "avr-170" else -197
    socket(x, y - 2, foot + 11)
    usb(x + 21, y - 2, foot + 11)
    if model.form == "avr-170":
        for j, m in enumerate((bone, red)):
            disc("Auxiliary input", (x + 46 + j * 15, y - 2, foot + 11), 5.2, 1.4, m, True)
            socket(x + 46 + j * 15, y - 3.2, foot + 11, 3)
    elif model.form in ("avr-161", "avr-171"):
        socket(x + 43, y - 2, foot + 11, 2.6)
    elif model.form in ("avr-270", "avr-370"):
        box("Front HDMI", (x + 46, y - 2, foot + 11), (16, 2, 6), void, 1)
    for side in (-1, 1):
        for yy in (-d * 0.32, d * 0.32):
            bolt = disc("Cover screw", (side * (w / 2 - 0.65), yy, h - 11), 2.3, 0.7, key)
            bolt.rotation_euler.y = math.pi / 2


def bluray(model):
    w = 400
    d = 285 if model.form != "bds-80" else 301
    h = 78.5 if model.form == "bds-35" else 80
    white = model.finish == "white"
    case = bone if white else graphite
    face = porcelain if white else glass
    feet(w, d, 6)
    rim = rounded_rect(w, d, 14)
    outline("Tapered lower deck", rim, [(6, 0.93), (10, 0.967), (21, 1)], case, 1.1)
    outline("Wraparound disc deck", rim, [(21, 1), (h - 3, 1), (h, 0.992)], face, 1.5)
    y = -d / 2
    box("Slot-loading disc transport", (-94, y - 0.2, 54), (145, 1.3, 3.5), void, 1)
    typeface("BDS", (-183, y - 0.5, 66), 4.5, silver)
    typeface("harman/kardon", (0, y - 0.8, 28), 8, nickel if white else silver, align="CENTER")
    typeface("BLU-RAY  3D", (-10, y - 0.8, 51), 5, phosphor)
    for radius, offset, m in [(25, 0, silver), (22.2, 1, frost), (20, 2, case)]:
        disc("Volume and power ring", (159, y - offset, 43), radius, 2.6, m, True, 1)
    usb(-110, y + 1.0, 17.5)
    if model.form != "bds-35":
        socket(-142, y + 1.0, 17.5)
    if model.form == "bds-80":
        typeface("N", (-151, -95, h + 0.2), 6, nickel, True)
    if model.form == "bds-35":
        rod("Wireless aerial", [(-152, d / 2 - 10, h - 8), (-152, d / 2 - 8, h + 39)], 2.2, rubber)
    # Terminals distinguish two-channel and five-channel head units from the back.
    channels = 2 if model.key.startswith("BDS2") else 5
    for i in range(channels):
        for j, m in enumerate((red, void)):
            disc("Speaker terminal", (56 + i * 19, d / 2 + 2, 27 + 12 * j), 4.4, 5, m, True, 0.55)


def orb(name, pos, radii, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=80, ring_count=48, location=metres(pos))
    obj = bpy.context.object
    obj.scale = metres(radii)
    for p in obj.data.polygons:
        p.use_smooth = True
    return finish(obj, name, mat)


def fabric(name, tone):
    # A repeating two-yarn swatch, packed into the GLB so the weave survives export.
    m = material(name, tone, 0, 0.86)
    nodes = m.node_tree.nodes
    if nodes.get("Woven threads"):
        return m
    size = 64
    tex = bpy.data.images.new(name + " swatch", width=size, height=size, alpha=False)
    pix = []
    for y in range(size):
        for x in range(size):
            a = math.cos((x + y * 0.23) * TAU / 8)
            b = math.cos((y - x * 0.25) * TAU / 8)
            brightness = 0.48 + 0.52 * max(a, b) ** 2 if max(a, b) > 0 else 0.36
            pix.extend([min(1, (c * brightness) ** (1 / 2.2)) for c in tone] + [1])
    tex.pixels[:] = pix
    tex.pack()
    t = nodes.new("ShaderNodeTexImage")
    t.name = "Woven threads"
    t.image = tex
    t.interpolation = "Linear"
    uv = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (38, 21, 1)
    links = m.node_tree.links
    links.new(uv.outputs["UV"], mapping.inputs["Vector"])
    links.new(mapping.outputs["Vector"], t.inputs["Vector"])
    links.new(t.outputs["Color"], nodes["Principled BSDF"].inputs["Base Color"])
    return m


def aura(model):
    pale = model.finish == "white"
    chassis = bone if pale else graphite
    cloth = fabric(
        "Silver knit" if pale else "Charcoal knit", (0.58, 0.55, 0.50) if pale else (0.055, 0.060, 0.064)
    )
    disc("Rubber foot", (0, 0, 4), 83, 8, rubber, bevel=2)
    shell("Curved bass cabinet", [(6, 81), (12, 92), (23, 100), (54, 106), (84, 107), (96, 104)], chassis)
    # UV cylinder gives the woven jacket a continuous seam at the rear.
    disc("Woven speaker grille", (0, 0, 58), 106.6, 66, cloth, bevel=5)
    shell("Touch rail", [(87, 106), (90, 108), (99, 107), (103, 104)], chassis)
    for x, s in [(-63, "–"), (-42, "+"), (57, "o")]:
        typeface(s, (x, -math.sqrt(107**2 - x * x) - 0.2, 92), 5.2, silver)
    typeface("harman/kardon", (0, -107.3, 53), 6.2, nickel if pale else silver, align="CENTER")
    shell(
        "Acoustic diffuser",
        [(96, 95), (100, 96), (106, 78), (113, 58), (120, 44), (129, 37), (133, 32)],
        nickel,
    )
    for z, r in [(105, 73), (112, 58), (119, 46), (125, 39)]:
        disc("Diffuser ridge", (0, 0, z), r, 2.4, chassis, bevel=0.6)
    bell = [
        (99, 104),
        (117, 106),
        (147, 107.5),
        (181, 106),
        (208, 101),
        (228, 94),
        (244, 83),
        (255, 70),
        (262, 57),
        (266, 44),
        (267, 36),
        (265, 31),
        (258, 28),
        (243, 27),
        (213, 25),
        (177, 21),
        (149, 19),
        (139, 18),
        (136, 18),
    ]
    # Continuous hollow bell and its inward-returning flared bass port.
    wall = bell + [(z, max(1, r - 1.9)) for z, r in reversed(bell)]
    shell("Transparent acoustic dome and descending port", wall, clear, 128)
    shell(
        "Smoked wall of acoustic throat",
        [
            (137, 16),
            (155, 17),
            (185, 19),
            (215, 22),
            (242, 24),
            (254, 25),
            (254, 24),
            (242, 23),
            (215, 21),
            (185, 18),
            (155, 16),
            (137, 15),
        ],
        smoke,
    )
    disc("Throat", (0, 0, 135), 17, 2, void)
    disc("Port light diffuser", (0, 0, 133), 20, 2.2, frost, bevel=0.6)


def onyx(model):
    # The transverse stainless hoop tilts behind the cabinet and meets the floor.
    pts = []
    for i in range(160):
        a = TAU * i / 160
        pts.append((169 * math.cos(a), 35 + 76 * math.sin(a), 154 + 150 * math.sin(a)))
    rod("Bent stainless stand and handle", pts, 4.4, silver, True)
    obj = orb("Leather rear cabinet", (0, 0, 160), (154, 92, 148), graphite)
    obj.rotation_euler.x = math.radians(-12)
    obj = orb(
        "Convex woven grille", (0, -37, 164), (151, 65, 143), fabric("Charcoal knit", (0.055, 0.060, 0.064))
    )
    obj.rotation_euler.x = math.radians(-12)
    disc("Rear passive radiator", (0, 84, 163), 63, 4, nickel, True, 2)
    disc("Spun diaphragm", (0, 87, 163), 55, 2, metal, True, 2)
    typeface("harman/kardon", (0, -104.8, 166), 10, silver, align="CENTER")
    for x in (-105, 105):
        rod("Stand pivot", [(x, 39, 95), (x, 60, 98)], 5, metal)


def triangle_points(w, d):
    # A rounded triangular moulding, with a broad front and a single rear apex.
    corners = [(-w * 0.52, -d * 0.43), (w * 0.52, -d * 0.43), (0, d * 0.60)]
    pts = []
    for i, (cx, cy) in enumerate(corners):
        prev = corners[(i - 1) % 3]
        nxt = corners[(i + 1) % 3]
        a = (cx * 0.72 + prev[0] * 0.28, cy * 0.72 + prev[1] * 0.28)
        b = (cx * 0.72 + nxt[0] * 0.28, cy * 0.72 + nxt[1] * 0.28)
        for j in range(16):
            t = j / 15
            s = 1 - t
            pts.append(
                (s * s * a[0] + 2 * t * s * cx + t * t * b[0], s * s * a[1] + 2 * t * s * cy + t * t * b[1])
            )
    return pts


def broadlink(model):
    form = model.form
    if form in ("bean", "mini", "mini-c", "mate", "pro4-c"):
        radius, h = {
            "bean": (27.5, 65),
            "mini": (24, 43),
            "mini-c": (23, 43),
            "mate": (23, 20),
            "pro4-c": (22.85, 50.1),
        }[form]
        if form == "bean":
            shell("Tapered black moulding", [(0, 25), (2, 26), (9, 26.5), (49, 27.5), (53, 27)], graphite)
            shell("Stepped IR window", [(52.5, 27), (54, 27.2), (58, 26.3), (63, 22.5), (65, 19.5)], glass)
            disc("Inset crown", (0, 0, 65.05), 18.4, 0.3, glass, bevel=0.14)
        elif form == "pro4-c":
            shell("Black IR core", [(0, 20), (2, 22), (36, 22), (49, 22.0), (h, 21.3)], glass)
            # A break in the white wrap exposes the narrow vertical status strip.
            verts = []
            faces = []
            for z, r in [(1, radius * 0.94), (3, radius), (32, radius), (35, radius * 0.98)]:
                for i in range(97):
                    angle = math.radians(-84 + 348 * i / 96)
                    soft_notch = 3.7 * math.exp(-((min(i, 96 - i) / 2.8) ** 2)) if z == 35 else 0
                    verts.append((r * math.cos(angle), r * math.sin(angle), z - soft_notch))
            for row in range(3):
                for i in range(96):
                    n = row * 97 + i
                    faces.append((n, n + 1, n + 98, n + 97))
            wrap = mesh("White wraparound sleeve", verts, faces, bone)
            for polygon in wrap.data.polygons:
                polygon.use_smooth = True
            wall = wrap.modifiers.new("Sleeve thickness", "SOLIDIFY")
            wall.thickness = 0.00065
        else:
            gloss = form in ("mini-c", "mate")
            split = 4 if gloss else h * 0.70
            r = radius
            shell("Ventilated foot", [(0, r * 0.81), (1, r * 0.88), (4, r * 0.94)], rubber)
            shell(
                "Lower moulding",
                [(3, r * 0.94), (5, r * 0.98), (split + 1, r)],
                glass if gloss else graphite,
            )
            shell(
                "Flat optical window",
                [(split, r), (h - 1.4, r * 0.986), (h - 0.4, r * 0.97), (h, r * 0.94)],
                glass,
            )
        led_height = 13 if form == "bean" else h * 0.43
        box("Status light", (0, -radius * 0.985, led_height), (1.4, 1, 3), blue, 0.4)
        box("Micro USB socket", (0, radius * 0.98, 6), (8, 1.4, 3.8), void, 0.7)
        return

    if form == "triangle":
        pts = triangle_points(122, 112)
        h = 36
        outline("Undercut foot", pts, [(0, 0.86), (3, 0.93), (6, 0.98)], rubber, 0.6)
        outline("Infrared belt", pts, [(6, 0.98), (22, 1)], glass, 1)
        outline("Sloping lid", pts, [(22, 1), (32, 0.97), (h, 0.90)], graphite, 1.1)
        typeface("BroadLink", (0, 1, h + 0.12), 4.3, nickel, True, "CENTER")
    else:
        # The fourth-generation Pro has four raised corners and pinched sides.
        pts = [
            (x * (0.87 + 0.13 * (y / 42.5) ** 2), y * (0.87 + 0.13 * (x / 42.5) ** 2))
            for x, y in rounded_rect(85, 85, 9)
        ]
        h = 31
        outline("Inset foot", pts, [(0, 0.83), (2, 0.91), (5, 0.97)], rubber, 0.6)
        outline("Optical belt", pts, [(5, 0.97), (h * 0.42, 1)], glass, 0.75)
        outline(
            "Pillow-shaped lid",
            pts,
            [(h * 0.42, 1), (h * 0.62, 0.97), (h * 0.82, 0.83), (h * 0.95, 0.67), (h, 0.54)],
            graphite,
            0.9,
        )
        disc("Embossed circular mark", (0, 0, h + 0.03), 12, 0.25, key, bevel=0.1)
        disc("Recess inside mark", (0, 0, h + 0.2), 11.45, 0.18, graphite, bevel=0.08)
    front = min(y for x, y in pts)
    box("Indicator", (0, front * 0.987, h * 0.36), (1.4, 0.8, 2.5), blue, 0.5)


def global_cache(model):
    form = model.form
    if form.startswith("itach"):
        box("Extruded enclosure", (0, 0, 16), (79, 53, 29), graphite, 3.5)
        for x in (-39, 39):
            box("Bumper", (x, 0, 16), (5, 57, 32), rubber, 2.3)
        box("IR module insert", (18, -27, 16), (35, 2, 20), red, 1.3)
        for j in range(3):
            socket(6 + 11.2 * j, -28.5, 15.5, 3.65)
            disc("Port LED", (6 + 11.2 * j, -28.35, 21), 0.8, 1, void, True)
        if form == "itach-wf":
            rod("Swivel aerial", [(-27, -26, 14), (-28, -31, 22), (-30, -29, 64)], 2.5, rubber)
        else:
            ethernet(-27, -27.5, 15)
        socket(-10, -27.2, 15, 3.5)
        typeface("iTach", (-19, 0, 30.7), 8.3, nickel, True)
        return
    wifi = form == "flex-wf"
    h = 12.3 if wifi else 20.8
    pts = rounded_rect(31, 65, 5)
    case = outline("Flex Link shell", pts, [(0, 0.94), (2, 0.99), (h - 2, 1), (h, 0.94)], grayshell, 0.7)
    # The wired model rises behind the Flex Link socket to accommodate the RJ45 jack.
    for v in case.data.vertices:
        ratio = (v.co.y / MM + 32.5) / 65
        if v.co.z > 3 * MM:
            v.co.z *= 0.55 + 0.45 * (ratio * ratio * (3 - 2 * ratio))
    hfront = h * 0.55
    socket(0, -32, hfront * 0.49, 3.35)
    typeface("Flex", (0, 23, h * 0.98), 3.4, nickel, True, "CENTER")
    for x in (-8, 8):
        disc("Moulding screw", (x, -23, h * 0.58), 1.25, 0.45, nickel)
    if not wifi:
        box("Network jack", (0, 32, h * 0.50), (16, 2, 13), void, 0.65)
    else:
        box("DC input", (0, 32, 5), (8, 1.5, 3), void, 0.45)
    # One Flex Link cable, visible from the equipment-plate camera.
    rod(
        "Emitter lead",
        [
            (0, -32, hfront * 0.49),
            (0, -42, hfront * 0.49),
            (4, -46, 4),
            (12, -49, 2),
            (20, -52, 1.5),
            (24, -57, 1.5),
        ],
        0.85,
        rubber,
    )
    box("Stick-on emitter", (26, -59, 2.3), (8, 5, 4.6), glass, 1.6)


def ethernet(x, y, z):
    box("Ethernet shield", (x, y, z), (17, 2, 15), nickel, 1)
    box("RJ45 opening", (x, y - 1.2, z), (14.4, 0.8, 10.8), void, 0.55)
    for i in range(8):
        box("Ethernet contact", (x - 4.7 + 1.34 * i, y - 1.75, z - 3.9), (0.65, 0.25, 1.1), gold)


def small_ir(model):
    form = model.form
    if form == "board":
        box("ESP carrier", (0, 0, 2.4), (26, 45, 1.6), pcb, 0.8)
        box("RF can", (0, 5, 4.3), (15, 17, 2.4), nickel, 0.5)
        typeface("ESP", (-4, 4, 5.55), 3.5, metal, True)
        for i in range(13):
            for x in (-10.8, 10.8):
                disc("Through-hole pad", (x, -17 + i * 2.7, 3.28), 0.9, 0.21, gold)
                disc("Plated hole", (x, -17 + i * 2.7, 3.43), 0.43, 0.16, void)
        for j in (-1, 1):
            rod(
                "Through-hole lead",
                [(j * 1.5, -13, 3.3), (j * 1.5, -14, 7), (j * 1.5, -20, 7)],
                0.3,
                nickel,
            )
        orb("IR diode", (0, -22, 7), (2.6, 4, 2.6), irblue)
        box("USB socket", (0, 20, 4.8), (8.2, 6, 3), silver, 0.6)
        for j in range(4):
            box("SMD component", (-6 + j * 3.2, -9, 3.9), (1.3, 2.4, 0.85), graphite, 0.2)
        return
    kit = form == "irkit"
    w = 62 if kit else 58 if "mini" in form else 70 if form == "remo-3" else 74
    h = 17 if kit else 16 if "mini" in form else 18
    m = {"white": bone, "blue": navy, "black": graphite}[model.finish] if not kit else bone
    pts = rounded_rect(w, w, w * (0.17 if kit else 0.21))
    outline("Lower shell", pts, [(0, 0.88), (1.8, 0.96), (4.5, 0.98)], grayshell if kit else m, 0.45)
    outline("Top moulding", pts, [(4.8, 0.981), (h - 4, 1), (h - 1, 0.98), (h, 0.90)], m, 0.65)
    box("USB power", (0, w * 0.49, 6), (8, 1.7, 3.7), void, 0.6)
    if kit:
        for r in (10, 17, 24):
            # Three broad embossed segments of the IRKit mark.
            arc = [math.radians(-41 + 82 * j / 24) for j in range(25)]
            pts = [
                (-15 + (r + offset) * math.cos(a), (r + offset) * math.sin(a))
                for offset, angles in [(1.7, arc), (-1.7, list(reversed(arc)))]
                for a in angles
            ]
            outline("Embossed signal wave", pts, [(h, 1), (h + 0.85, 1)], porcelain, 0.18)
        for i, x in enumerate((-16, -5, 5, 16)):
            disc("IR window", (x, -w * 0.49, 8.7), 2 if i in (1, 2) else 1.2, 1.7, irblue, True, 0.4)
    else:
        disc("Status aperture", (0, -w * 0.30, h + 0.09), 0.72, 0.35, frost)
        typeface(
            "Nature",
            (0, 0, h + 0.12),
            3.8,
            nickel if model.finish != "white" else grayshell,
            True,
            "CENTER",
        )


def new_scene(name):
    scene = bpy.data.scenes.new(name)
    bpy.context.window.scene = scene
    scene.unit_settings.system = "METRIC"
    return scene


def studio(scene, objects, category):
    # Project the actual mesh bounds onto the camera axes, including the antenna and emitter lead.
    direction = Vector((0.52, -1.70, 0.38 if category == "rack" else 0.80))
    rotation = (-direction).to_track_quat("-Z", "Y")
    right, up = rotation @ Vector((1, 0, 0)), rotation @ Vector((0, 1, 0))
    deps = bpy.context.evaluated_depsgraph_get()
    points = []
    for obj in objects:
        evaluated = obj.evaluated_get(deps)
        if evaluated.type == "MESH":
            points.extend(evaluated.matrix_world @ v.co for v in evaluated.data.vertices)
    bounds = lambda axis: (min(p.dot(axis) for p in points), max(p.dot(axis) for p in points))
    left, rightmost = bounds(right)
    bottom, top = bounds(up)
    aspect = 1.96 if category == "rack" else 1.19
    span = max(rightmost - left, (top - bottom) * aspect) * 1.08
    target = right * ((left + rightmost) / 2) + up * ((bottom + top) / 2)
    bpy.ops.object.camera_add(location=target + direction.normalized() * span * 3)
    cam = bpy.context.object
    cam.name = "Equipment plate camera"
    cam.rotation_euler = rotation.to_euler()
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = span
    cam.data.clip_start = 0.0005
    scene.camera = cam
    for name, pos, power, width, depth, color in [
        ("Long softbox", (-0.85, -1.1, 1.55), 57, 1.24, 0.59, (1, 0.92, 0.80)),
        ("Cool edge strip", (0.45, 1, 1.1), 83, 1.0, 0.33, (0.79, 0.89, 1)),
        ("Front strip", (1.25, -0.85, 0.50), 33, 0.30, 0.96, (1, 0.90, 0.79)),
    ]:
        location = target + Vector(pos) * span
        bpy.ops.object.light_add(type="AREA", location=location)
        lamp = bpy.context.object
        lamp.name = name
        lamp.rotation_euler = (target - location).to_track_quat("-Z", "Y").to_euler()
        lamp.data.shape = "RECTANGLE"
        lamp.data.size = width * span
        lamp.data.size_y = depth * span
        lamp.data.energy = power * span**2
        lamp.data.color = color
    world = bpy.data.worlds.get("Diffuse studio")
    if not world:
        world = bpy.data.worlds.new("Diffuse studio")
        world.use_nodes = True
        world.node_tree.nodes["Background"].inputs[0].default_value = (0.48, 0.50, 0.54, 1)
        world.node_tree.nodes["Background"].inputs[1].default_value = 0.65
    scene.world = world
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 20
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.resolution_x = 768 if category == "rack" else 432
    scene.render.resolution_y = round(scene.render.resolution_x / aspect)
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "WEBP"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.quality = 94
    return cam


def export_model(scene, model, components):
    # Keep curves, type and modifiers editable in the source. Freeze only the export copy.
    staging = new_scene("Export")
    for obj in components:
        copy = obj.copy()
        staging.collection.objects.link(copy)
        copy.select_set(True)
    bpy.context.view_layer.objects.active = next(iter(staging.objects))
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.join()
    bpy.context.object.name = model.label + " · enclosure and fittings"
    bpy.ops.object.empty_add(type="PLAIN_AXES")
    root = bpy.context.object
    root.name = model.label + " · product"
    root["identities"] = ", ".join((model.label, *model.aliases))
    for obj in staging.objects:
        if obj != root:
            obj.parent = root
    filename = str(GLBS / (model.key + ".glb"))
    bpy.ops.export_scene.gltf(
        filepath=filename,
        export_format="GLB",
        use_active_scene=True,
        export_draco_mesh_compression_enable=True,
        export_draco_position_quantization=16,
        export_extras=True,
        export_animations=False,
        export_cameras=False,
        export_lights=False,
    )
    bpy.context.window.scene = scene
    for obj in list(staging.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.scenes.remove(staging)
    return filename


def make(model):
    scene = new_scene(model.label)
    form = model.form
    if form == "stereo" or form.startswith("avr"):
        rack(model)
    elif form.startswith("bds"):
        bluray(model)
    elif form == "aura":
        aura(model)
    elif form == "onyx":
        onyx(model)
    elif model.label.startswith("Broadlink"):
        broadlink(model)
    elif model.label.startswith("Global"):
        global_cache(model)
    else:
        small_ir(model)
    parts = list(scene.objects)
    category = "rack" if form.startswith(("avr", "bds", "stereo")) else "compact"
    filename = export_model(scene, model, parts)
    proof = new_scene("GLB proof")
    bpy.ops.import_scene.gltf(filepath=filename)
    cam = studio(proof, list(proof.objects), category)
    proof.render.filepath = str(APP_ART / (model.key + ".webp"))
    bpy.ops.render.render(write_still=True)
    # Use the proof camera and light rig for the editable source scene too.
    for obj in list(proof.objects):
        if obj.type in ("CAMERA", "LIGHT"):
            scene.collection.objects.link(obj)
        else:
            bpy.data.objects.remove(obj, do_unlink=True)
    scene.camera = cam
    scene.world = proof.world
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 32
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.resolution_x = proof.render.resolution_x
    scene.render.resolution_y = proof.render.resolution_y
    scene.render.resolution_percentage = 100
    bpy.context.window.scene = scene
    bpy.data.scenes.remove(proof)
    scene.use_fake_user = True
    bpy.data.orphans_purge(do_recursive=True)
    print("PORTRAIT", model.key, flush=True)


if __name__ == "__main__":
    keys = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    unknown = set(keys) - {m.key for m in MODELS}
    if unknown:
        raise ValueError(f"Unknown model keys: {unknown}")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    empty = bpy.context.scene
    graphite = material("Graphite powder coat", (0.039, 0.044, 0.049), 0.30, 0.39)
    metal = material("Brushed charcoal aluminium", (0.066, 0.071, 0.075), 0.67, 0.31)
    glass = material("Smoked fascia", (0.014, 0.020, 0.025), 0.32, 0.15)
    silver = material("Brushed aluminium", (0.63, 0.68, 0.73), 0.83, 0.23)
    nickel = material("Satin nickel", (0.32, 0.36, 0.38), 0.62, 0.30)
    key = material("Keys", (0.091, 0.106, 0.11), 0.57, 0.29)
    void = material("Socket interior", (0.004, 0.006, 0.008), 0.04, 0.65)
    rubber = material("Rubber", (0.019, 0.022, 0.025), 0.02, 0.66)
    phosphor = material("Fluorescent lettering", (0.60, 0.73, 0.77), 0.12, 0.37)
    frost = material("Opal light guide", (0.73, 0.83, 0.87), 0.20, 0.27)
    bone = material("Warm white polymer", (0.78, 0.78, 0.73), 0.08, 0.36)
    porcelain = material("Gloss white", (0.92, 0.90, 0.86), 0.16, 0.24)
    clear = material("Optical polycarbonate", (0.96, 0.99, 1), 0, 0.055, 0.97)
    clear.node_tree.nodes["Principled BSDF"].inputs["IOR"].default_value = 1.48
    smoke = material("Smoked acoustic throat", (0.15, 0.18, 0.20), 0.15, 0.15, 0.64)
    grayshell = material("Mineral grey ABS", (0.43, 0.46, 0.48), 0.14, 0.38)
    gold = material("Contact gold", (0.63, 0.39, 0.11), 0.72, 0.31)
    blue = material("Blue indicator", (0.10, 0.47, 0.79), 0.13, 0.28)
    irblue = material("IR lens", (0.07, 0.10, 0.19), 0.24, 0.17)
    red = material("IR output red", (0.55, 0.032, 0.009), 0.11, 0.36)
    pcb = material("PCB solder mask", (0.022, 0.16, 0.123), 0.26, 0.43)
    navy = material("Nature Blue", (0.028, 0.078, 0.123), 0.12, 0.36)
    # Keep shared palette entries available between isolated builds.
    for mat in bpy.data.materials:
        mat.use_fake_user = True
    APP_ART.mkdir(exist_ok=True, parents=True)
    GLBS.mkdir(exist_ok=True)
    for model in MODELS:
        if not keys or model.key in keys:
            make(model)
    if not keys:
        aliases = {label: m.key for m in MODELS for label in (m.label, *m.aliases)}
        (APP_ART / "catalog.json").write_text(json.dumps(aliases, indent=2, ensure_ascii=False) + "\n")
        bpy.data.scenes.remove(empty)
        from study import render_study

        render_study(DESIGN)
        for screen in bpy.data.screens:
            for area in screen.areas:
                if area.type == "VIEW_3D":
                    area.spaces.active.region_3d.view_perspective = "CAMERA"
                    area.spaces.active.overlay.show_overlays = False
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=str(DESIGN / "Otoha Hardware.blend"), compress=True)
