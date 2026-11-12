"""Sử Studio → Blender driver.

Run headless:  Blender -b --factory-startup -Y -P blender_render.py -- job.json
Check a script without Blender:  python3 blender_render.py --check script.py

The job builds a scene from a 3D model or from an AI-written script, adds a camera move and
lighting, and renders PNG frames into job["output"]. AI scripts are checked before running and
only see a small toolbox (bpy, math, random, bmesh, mathutils and the helpers below).
"""
import ast
import json
import math
import random
import sys

ALLOWED_IMPORTS = {"bpy", "math", "mathutils", "random", "bmesh"}
BLOCKED_NAMES = {"open", "exec", "eval", "compile", "__import__", "globals", "locals", "vars", "getattr", "setattr",
                 "delattr", "input", "breakpoint", "memoryview", "exit", "quit", "help", "classmethod", "staticmethod",
                 "super", "type", "object"}
BLOCKED_ATTRS = {"wm", "script", "utils", "app", "handlers", "path", "export_scene", "export_mesh", "import_scene",
                 "import_mesh", "import_curve", "texts", "text", "filepath", "filepath_raw", "save_as_mainfile",
                 "save_mainfile", "driver_namespace", "libraries", "preferences", "system", "os", "sys", "subprocess",
                 "file", "sound", "sounds", "images", "image", "movieclips", "fonts", "load", "write", "reload",
                 "addon_utils", "ops_module", "context_override", "temp_override", "pack", "unpack"}


def check_script(source):
    """Returns a list of problems; empty means the script may run."""
    try:
        tree = ast.parse(source)
    except SyntaxError as error:
        return ["Lỗi cú pháp dòng %s: %s" % (error.lineno, error.msg)]
    problems = []
    for node in ast.walk(tree):
        line = getattr(node, "lineno", "?")
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name.split(".")[0] not in ALLOWED_IMPORTS:
                    problems.append("Dòng %s: không được import %s" % (line, alias.name))
        elif isinstance(node, ast.ImportFrom):
            if (node.module or "").split(".")[0] not in ALLOWED_IMPORTS or node.level:
                problems.append("Dòng %s: không được import từ %s" % (line, node.module))
        elif isinstance(node, ast.Name):
            if node.id in BLOCKED_NAMES or node.id.startswith("_"):
                problems.append("Dòng %s: không được dùng %s" % (line, node.id))
        elif isinstance(node, ast.Attribute):
            if node.attr in BLOCKED_ATTRS or node.attr.startswith("_"):
                problems.append("Dòng %s: không được dùng thuộc tính .%s" % (line, node.attr))
        elif isinstance(node, (ast.Global, ast.Nonlocal, ast.AsyncFunctionDef, ast.Await, ast.ClassDef)):
            problems.append("Dòng %s: cấu trúc %s không được hỗ trợ" % (line, type(node).__name__))
        elif isinstance(node, ast.Constant) and isinstance(node.value, str) and ("/" in node.value and len(node.value) > 1 and node.value.startswith(("/", "~", ".."))):
            problems.append("Dòng %s: không được dùng đường dẫn file" % line)
    if len(source) > 100000:
        problems.append("Script quá dài")
    return problems


def log(message):
    print(message, flush=True)


def fail(message):
    log("SU_ERROR " + message)
    sys.exit(3)


def main(job_path):
    import bpy
    import bmesh
    import mathutils
    from mathutils import Vector

    with open(job_path, encoding="utf-8") as handle:
        job = json.load(handle)
    fps, duration = int(job["fps"]), float(job["duration"])
    end = max(1, int(round(duration * fps)))
    draft = job.get("quality") == "draft"
    effects = {"motionBlur": True, "dof": True, "shake": True, "bloom": True, "fog": 0.0}
    effects.update(job.get("effects") or {})

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene

    def apply_output():
        """Size, frame rate, length and output belong to the app; scripts may not change them."""
        scene.render.resolution_x, scene.render.resolution_y = int(job["width"]), int(job["height"])
        scene.render.resolution_percentage = 100
        scene.render.fps, scene.render.fps_base = fps, 1.0
        scene.frame_start, scene.frame_end = 1, end
        scene.render.image_settings.file_format = "PNG"
        scene.render.image_settings.color_mode = "RGB"
        scene.render.filepath = job["output"].rstrip("/") + "/frame_"
        for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
            try:
                scene.render.engine = engine
                break
            except TypeError:
                continue
        ee = scene.eevee
        settings = {"taa_render_samples": 8 if draft else 48, "use_volumetric_shadows": True,
                    "volumetric_tile_size": "16" if draft else "8", "use_raytracing": not draft,
                    "use_shadows": True, "volumetric_end": 400.0}
        for key, value in settings.items():
            try:
                setattr(ee, key, value)
            except (AttributeError, TypeError):
                pass
        scene.render.use_motion_blur = bool(effects.get("motionBlur"))
        try:
            scene.render.motion_blur_shutter = 0.5
        except AttributeError:
            pass
        try:
            scene.view_settings.view_transform = "AgX"
            for look in ("AgX - Punchy", "AgX - Medium High Contrast", "Punchy"):
                try:
                    scene.view_settings.look = look
                    break
                except TypeError:
                    continue
        except TypeError:
            pass

    apply_output()
    state = {"shot": None, "path": None, "world": False}

    # ---------- materials ----------
    def color_of(value):
        if isinstance(value, str):
            value = value.lstrip("#")
            if len(value) == 6:
                return tuple(int(value[i:i + 2], 16) / 255 for i in (0, 2, 4)) + (1.0,)
            return (0.7, 0.7, 0.7, 1.0)
        value = tuple(value)
        return value + (1.0,) if len(value) == 3 else value

    def node_tree(idblock):
        if idblock.node_tree is None or bpy.app.version < (5, 0, 0):
            idblock.use_nodes = True
        return idblock.node_tree

    def mat(color="#b0a080", roughness=0.6, metallic=0.0, emission=None, strength=1.0, alpha=1.0, name=None):
        material = bpy.data.materials.new(name or "Mat")
        shader = node_tree(material).nodes.get("Principled BSDF")
        rgba = color_of(color)
        material.diffuse_color = rgba
        if shader:
            shader.inputs["Base Color"].default_value = rgba
            shader.inputs["Roughness"].default_value = roughness
            shader.inputs["Metallic"].default_value = metallic
            if emission is not None:
                for key in ("Emission Color", "Emission"):
                    if key in shader.inputs:
                        shader.inputs[key].default_value = color_of(emission)
                        break
                if "Emission Strength" in shader.inputs:
                    shader.inputs["Emission Strength"].default_value = strength
            if alpha < 1.0:
                shader.inputs["Alpha"].default_value = alpha
                for attr, value in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
                    try:
                        setattr(material, attr, value)
                        break
                    except (AttributeError, TypeError):
                        continue
        return material

    def window_mat(size, wall="#3c4650", light="#ffb15c", lit=0.3, strength=1.6, bay=2.2, storey=3.2):
        """Facade with a procedural grid of windows, some lit; size is the box's (w, d, h) in metres."""
        material = bpy.data.materials.new("Mặt tiền")
        tree = node_tree(material)
        nodes, links = tree.nodes, tree.links
        wall_shader = nodes.get("Principled BSDF")
        wall_shader.inputs["Base Color"].default_value = color_of(wall)
        wall_shader.inputs["Roughness"].default_value = 0.85
        out = nodes.get("Material Output")
        glass = nodes.new("ShaderNodeBsdfPrincipled")
        glass.inputs["Base Color"].default_value = color_of("#0b0f14")
        glass.inputs["Roughness"].default_value = 0.12
        glass.inputs["Metallic"].default_value = 0.6
        coords = nodes.new("ShaderNodeTexCoord")
        split = nodes.new("ShaderNodeSeparateXYZ")
        across = nodes.new("ShaderNodeMath")
        across.operation = "MULTIPLY_ADD"
        across.inputs[1].default_value = size[0]
        sideways = nodes.new("ShaderNodeMath")
        sideways.operation = "MULTIPLY"
        sideways.inputs[1].default_value = size[1]
        up = nodes.new("ShaderNodeMath")
        up.operation = "MULTIPLY"
        up.inputs[1].default_value = size[2]
        join = nodes.new("ShaderNodeCombineXYZ")
        bricks = nodes.new("ShaderNodeTexBrick")
        bricks.offset = 0.0
        bricks.inputs["Color1"].default_value = color_of(light)
        bricks.inputs["Color2"].default_value = (0, 0, 0, 1)
        bricks.inputs["Mortar"].default_value = (0, 0, 0, 1)
        bricks.inputs["Scale"].default_value = 1.0
        bricks.inputs["Mortar Size"].default_value = 0.85
        bricks.inputs["Bias"].default_value = max(-1.0, min(1.0, 1 - lit * 2))
        bricks.inputs["Brick Width"].default_value = bay
        bricks.inputs["Row Height"].default_value = storey
        mix = nodes.new("ShaderNodeMixShader")
        links.new(coords.outputs["Object"], split.inputs[0])
        links.new(split.outputs["Y"], sideways.inputs[0])
        links.new(split.outputs["X"], across.inputs[0])
        links.new(sideways.outputs[0], across.inputs[2])
        links.new(split.outputs["Z"], up.inputs[0])
        links.new(across.outputs[0], join.inputs["X"])
        links.new(up.outputs[0], join.inputs["Y"])
        links.new(join.outputs[0], bricks.inputs["Vector"])
        for key in ("Emission Color", "Emission"):
            if key in glass.inputs:
                links.new(bricks.outputs["Color"], glass.inputs[key])
                break
        glass.inputs["Emission Strength"].default_value = strength
        links.new(bricks.outputs["Fac"], mix.inputs[0])
        links.new(glass.outputs[0], mix.inputs[1])
        links.new(wall_shader.outputs[0], mix.inputs[2])
        links.new(mix.outputs[0], out.inputs["Surface"])
        return material

    def glow(color="#56e4ff", strength=8.0):
        return mat(color, roughness=0.3, emission=color, strength=strength)

    def volume_mat(color="#6a6560", density=1.0, emission=None, strength=0.0, name="Smoke"):
        material = bpy.data.materials.new(name)
        nodes = node_tree(material).nodes
        links = material.node_tree.links
        for n in list(nodes):
            if n.bl_idname != "ShaderNodeOutputMaterial":
                nodes.remove(n)
        out = nodes.get("Material Output") or nodes.new("ShaderNodeOutputMaterial")
        vol = nodes.new("ShaderNodeVolumePrincipled")
        vol.inputs["Color"].default_value = color_of(color)
        vol.inputs["Density"].default_value = density
        if emission is not None:
            vol.inputs["Emission Color"].default_value = color_of(emission)
            vol.inputs["Emission Strength"].default_value = strength
        links.new(vol.outputs[0], out.inputs["Volume"])
        return material

    # ---------- primitives ----------
    def finish(obj, name, color, material, location, rotation, bevel=0.0):
        obj.name = name
        obj.location = location
        obj.rotation_euler = [math.radians(a) for a in rotation]
        obj.data.materials.clear()
        obj.data.materials.append(material or mat(color))
        if bevel > 0:
            mod = obj.modifiers.new("Bevel", "BEVEL")
            mod.width = bevel
            mod.segments = 2
        return obj

    def box(name="Box", size=(1, 1, 1), location=(0, 0, 0), rotation=(0, 0, 0), color="#a08060", material=None, bevel=None):
        bpy.ops.mesh.primitive_cube_add(size=1)
        obj = bpy.context.active_object
        obj.scale = size
        smallest = min(abs(v) for v in size)
        return finish(obj, name, color, material, location, rotation, (0.04 * smallest if smallest > 0.15 else 0) if bevel is None else bevel)

    def cylinder(name="Cylinder", radius=0.5, depth=1, location=(0, 0, 0), rotation=(0, 0, 0), color="#806040", material=None, vertices=24):
        bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, vertices=vertices)
        bpy.ops.object.shade_smooth()
        return finish(bpy.context.active_object, name, color, material, location, rotation)

    def cone(name="Cone", radius1=0.5, radius2=0.0, depth=1, location=(0, 0, 0), rotation=(0, 0, 0), color="#705030", material=None, vertices=24):
        bpy.ops.mesh.primitive_cone_add(radius1=radius1, radius2=radius2, depth=depth, vertices=vertices)
        return finish(bpy.context.active_object, name, color, material, location, rotation)

    def sphere(name="Sphere", radius=0.5, location=(0, 0, 0), color="#909090", material=None, segments=24):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=segments, ring_count=max(8, segments // 2))
        bpy.ops.object.shade_smooth()
        return finish(bpy.context.active_object, name, color, material, location, (0, 0, 0))

    def plane(name="Plane", size=(2, 2), location=(0, 0, 0), rotation=(0, 0, 0), color="#6a7a50", material=None):
        bpy.ops.mesh.primitive_plane_add(size=1)
        obj = bpy.context.active_object
        obj.scale = (size[0], size[1], 1)
        return finish(obj, name, color, material, location, rotation)

    def group(name, location=(0, 0, 0)):
        root = bpy.data.objects.new(name, None)
        scene.collection.objects.link(root)
        root.location = location
        return root

    def attach(parent, *parts):
        for part in parts:
            part.parent = parent
        return parent

    library = job.get("library") or {}

    def library_key(name):
        """AI scripts sometimes copy a label like "clear (Trời quang)": keep the key part only."""
        return str(name or "").split("(")[0].strip().lower().replace(" ", "_").replace("-", "_")
    procedural = {"mud": ("#4a3f2f", "#2e281e", 0.35), "mud_dry": ("#6b5a43", "#4c3f2f", 0.9), "forest_floor": ("#3d3a26", "#25261a", 0.8),
                  "grass": ("#4f6a33", "#33461f", 0.85), "sand": ("#b49c76", "#8f7a58", 0.9), "rocks": ("#6b6a63", "#45443f", 0.8),
                  "concrete": ("#8a8780", "#5f5d58", 0.85), "plaster": ("#c9bfa9", "#9e9480", 0.9), "brick": ("#8a4a36", "#5e3125", 0.85),
                  "planks": ("#6b4f35", "#45321f", 0.7), "bark": ("#4b3b2b", "#2f241a", 0.9), "roof_iron": ("#6b6f6c", "#3f3b33", 0.5),
                  "cobblestone": ("#77736a", "#4d4a44", 0.8), "stone_blocks": ("#8b8476", "#5d574c", 0.85)}

    def texture_mat(name="mud", scale=4.0, tint=None):
        """Real PBR textures from the downloaded library when present, else a procedural look-alike."""
        material = bpy.data.materials.new("Chất liệu " + str(name))
        tree = node_tree(material)
        nodes, links = tree.nodes, tree.links
        shader = nodes.get("Principled BSDF")
        coords = nodes.new("ShaderNodeTexCoord")
        mapping = nodes.new("ShaderNodeMapping")
        mapping.inputs["Scale"].default_value = (scale, scale, scale)
        links.new(coords.outputs["UV"], mapping.inputs["Vector"])
        name = library_key(name) if name else name
        files = (library.get("textures") or {}).get(name)
        if files:
            def image(path, color):
                node = nodes.new("ShaderNodeTexImage")
                node.image = bpy.data.images.load(path, check_existing=True)
                if not color:
                    node.image.colorspace_settings.name = "Non-Color"
                links.new(mapping.outputs["Vector"], node.inputs["Vector"])
                return node
            diff = image(files["diff"], True)
            if tint:
                mix = nodes.new("ShaderNodeMixRGB")
                mix.blend_type = "MULTIPLY"
                mix.inputs["Fac"].default_value = 0.6
                mix.inputs["Color2"].default_value = color_of(tint)
                links.new(diff.outputs["Color"], mix.inputs["Color1"])
                links.new(mix.outputs["Color"], shader.inputs["Base Color"])
            else:
                links.new(diff.outputs["Color"], shader.inputs["Base Color"])
            if files.get("rough"):
                links.new(image(files["rough"], False).outputs["Color"], shader.inputs["Roughness"])
            if files.get("nor"):
                normal = nodes.new("ShaderNodeNormalMap")
                links.new(image(files["nor"], False).outputs["Color"], normal.inputs["Color"])
                links.new(normal.outputs["Normal"], shader.inputs["Normal"])
            return material
        light, dark, rough = procedural.get(name, ("#6b6a5f", "#45443d", 0.85))
        noise = nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 6.0
        noise.inputs["Detail"].default_value = 8.0
        links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
        ramp = nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].color = color_of(dark)
        ramp.color_ramp.elements[1].color = color_of(tint or light)
        links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        links.new(ramp.outputs["Color"], shader.inputs["Base Color"])
        shader.inputs["Roughness"].default_value = rough
        bump = nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.4
        links.new(noise.outputs["Fac"], bump.inputs["Height"])
        links.new(bump.outputs["Normal"], shader.inputs["Normal"])
        return material

    def ground(size=60, color="#5f6b45", name="Ground", texture=None, scale=None):
        """Ground plane; texture='mud'|'forest_floor'|'grass'|'sand'|'rocks'|'concrete'|'cobblestone'… for a real surface."""
        material = texture_mat(texture, scale or size / 4, None) if texture else mat(color, roughness=0.9)
        obj = plane(name, (size, size), (0, 0, 0), (0, 0, 0), None, material)
        obj["su_ground"] = True
        return obj

    def sky_hdri(name="overcast", strength=1.0, rotation=0):
        """Real photographed sky and light from the library (overcast, clear, sunset, fire_sky, forest, misty, night, city_dusk)."""
        name = library_key(name)
        path = (library.get("hdri") or {}).get(name)
        if not path:
            fallback = {"overcast": ("#a8aeb0", 1.0), "clear": ("#9fc3e6", 1.2), "sunset": ("#d9935a", 0.9), "fire_sky": ("#d8703c", 0.9),
                        "forest": ("#8fa08a", 0.9), "misty": ("#b8bdb9", 1.0), "night": ("#0b1424", 0.2), "city_dusk": ("#4b4f6b", 0.8)}
            sky(*fallback.get(name, ("#a8aeb0", 1.0)))
            return
        world, tree = world_nodes()
        nodes, links = tree.nodes, tree.links
        background = nodes.get("Background")
        env = nodes.new("ShaderNodeTexEnvironment")
        env.image = bpy.data.images.load(path, check_existing=True)
        coords = nodes.new("ShaderNodeTexCoord")
        mapping = nodes.new("ShaderNodeMapping")
        mapping.inputs["Rotation"].default_value = (0, 0, math.radians(rotation))
        links.new(coords.outputs["Generated"], mapping.inputs["Vector"])
        links.new(mapping.outputs["Vector"], env.inputs["Vector"])
        links.new(env.outputs["Color"], background.inputs["Color"])
        background.inputs["Strength"].default_value = strength
        state["world"] = True
        state["hdri"] = True

    def water(name="Water", size=(40, 40), location=(0, 0, 0.02), color="#2f5d73"):
        obj = plane(name, size, location, (0, 0, 0), None, mat(color, roughness=0.08, metallic=0.1))
        obj["su_ground"] = True
        return obj

    # ---------- composite props ----------
    def building(name="Building", location=(0, 0, 0), size=(6, 6, 18), color="#3c4650", windows="#ffb15c", lit=0.35, damaged=0.0, seed=0):
        """Tower with window bands (some lit) and, when damaged > 0, a broken crown and debris."""
        rng = random.Random(seed or hash(name) % 9973)
        w, d, h = size
        x, y, z = location
        root = group(name, (x, y, z))
        body = box(name + " khối", (w, d, h), (0, 0, h / 2), material=window_mat((w, d, h), color, windows, lit), bevel=0.05)
        attach(root, body)
        roof = box(name + " mái", (w * 0.6, d * 0.5, 1.2), (rng.uniform(-w, w) * 0.15, 0, h + 0.6), color=color)
        attach(root, roof)
        if damaged > 0:
            chunk = box(name + " đỉnh gãy", (w * 0.7, d * 0.8, h * 0.12), (w * 0.15, 0, h + h * 0.03), (0, rng.uniform(8, 20), rng.uniform(-10, 10)), color=color)
            attach(root, chunk)
            for i in range(int(4 + damaged * 8)):
                rubble = box(name + " gạch vụn", [rng.uniform(0.4, 1.6)] * 3, (rng.uniform(-w, w), rng.uniform(-d, d) + d * 0.9, 0.3),
                             (rng.uniform(0, 40), rng.uniform(0, 40), rng.uniform(0, 90)), color="#4a4a48")
                attach(root, rubble)
        return root

    outfits = {
        "scifi": {"body": "#4c5c68", "head": "helmet", "accent": "#56e4ff", "skin": None},
        "soldier": {"body": "#4f5a3c", "head": "helmet", "accent": None, "skin": "#c69c74"},
        "vn": {"body": "#4e6a3f", "head": "boonie", "accent": None, "skin": "#c69c74"},
        "us": {"body": "#5b6140", "head": "m1", "accent": None, "skin": "#d5ab86"},
        "civilian": {"body": "#7b6a55", "head": "bare", "accent": None, "skin": "#c69c74"},
        "farmer": {"body": "#3b3a36", "head": "conical", "accent": None, "skin": "#b88d66"},
        "ancient": {"body": "#7a3b2a", "head": "ancient", "accent": None, "skin": "#c69c74"},
    }

    def figure(name="Người", location=(0, 0, 0), height=1.75, style="soldier", color=None, accent=None, run=False, pose=None, weapon=None, skin=None):
        """Human figure: style scifi|soldier|vn|us|civilian|farmer|ancient; pose stand|run|crouch|aim (run=True means run);
        weapon None|rifle|spear|sword. Returns a group; move it with animate()."""
        look = outfits.get(style, outfits["soldier"])
        pose = pose or ("run" if run else "stand")
        u = height / 1.75
        root = group(name, location)
        cloth = varied_mat(color or look["body"], 0.9, 60.0, 0.25, 0.25, "Vải")
        dark = mat("#2b2a26", roughness=0.7)
        skin_mat = mat(skin or look["skin"] or "#c69c74", roughness=0.6)
        glow_color = accent or look["accent"]
        lean = {"run": 14, "crouch": 28, "aim": 6}.get(pose, 0)
        torso = group(name + " thân", (0, 0, 0.92 * u))
        torso.rotation_euler = (math.radians(lean), 0, 0)
        torso.parent = root
        parts = [cone(name + " ngực", 0.2 * u, 0.15 * u, 0.56 * u, (0, 0, 0.3 * u), material=cloth, vertices=12),
                 sphere(name + " vai", 0.13 * u, (0.17 * u, 0, 0.52 * u), material=cloth, segments=12),
                 sphere(name + " vai", 0.13 * u, (-0.17 * u, 0, 0.52 * u), material=cloth, segments=12),
                 cylinder(name + " cổ", 0.05 * u, 0.1 * u, (0, 0, 0.62 * u), material=skin_mat, vertices=10),
                 sphere(name + " đầu", 0.11 * u, (0, -0.01 * u, 0.74 * u), material=skin_mat if look["head"] != "helmet" else cloth, segments=16)]
        head_kind = look["head"]
        if head_kind == "helmet":
            parts.append(sphere(name + " mũ bảo hộ", 0.135 * u, (0, 0, 0.77 * u), material=mat(color or look["body"], 0.4, 0.4), segments=16))
        elif head_kind == "m1":
            parts += [sphere(name + " mũ sắt", 0.14 * u, (0, 0, 0.78 * u), material=mat("#4d5236", 0.6), segments=16),
                      cylinder(name + " vành mũ", 0.16 * u, 0.015 * u, (0, 0, 0.75 * u), material=mat("#4d5236", 0.6), vertices=16)]
        elif head_kind == "boonie":
            parts += [cylinder(name + " mũ tai bèo", 0.12 * u, 0.09 * u, (0, 0, 0.82 * u), material=mat("#5d7146", 0.9), vertices=16),
                      cylinder(name + " vành tai bèo", 0.2 * u, 0.015 * u, (0, 0, 0.78 * u), material=mat("#5d7146", 0.9), vertices=20)]
        elif head_kind == "conical":
            parts.append(cone(name + " nón lá", 0.26 * u, 0.0, 0.17 * u, (0, 0, 0.86 * u), material=mat("#d8c79a", 0.8), vertices=24))
        elif head_kind == "ancient":
            parts.append(cone(name + " mũ trụ", 0.14 * u, 0.02 * u, 0.22 * u, (0, 0, 0.86 * u), material=mat("#5a4a30", 0.5, 0.6), vertices=16))
        if style in ("soldier", "vn", "us", "scifi"):
            parts.append(box(name + " ba lô", (0.3 * u, 0.14 * u, 0.36 * u), (0, 0.17 * u, 0.32 * u), material=dark))
        if glow_color:
            parts.append(box(name + " kính", (0.18 * u, 0.04 * u, 0.05 * u), (0, -0.11 * u, 0.76 * u), material=glow(glow_color, 6.0), bevel=0))
        attach(torso, *parts)
        limbs = []
        for side in (-1, 1):
            leg = group(name + " chân", (side * 0.1 * u, 0, 0.9 * u))
            attach(leg, cylinder(name + " đùi", 0.075 * u, 0.44 * u, (0, 0, -0.22 * u), material=cloth, vertices=10),
                   cylinder(name + " cẳng", 0.06 * u, 0.42 * u, (0, 0, -0.62 * u), material=cloth, vertices=10),
                   box(name + " giày", (0.11 * u, 0.24 * u, 0.08 * u), (0, -0.04 * u, -0.86 * u), material=dark))
            arm = group(name + " tay", (side * 0.21 * u, 0, 0.5 * u))
            attach(arm, cylinder(name + " cánh tay", 0.05 * u, 0.3 * u, (0, 0, -0.15 * u), material=cloth, vertices=10),
                   cylinder(name + " cẳng tay", 0.045 * u, 0.28 * u, (0, -0.06 * u, -0.38 * u), (20, 0, 0), material=cloth, vertices=10),
                   sphere(name + " bàn tay", 0.045 * u, (0, -0.1 * u, -0.53 * u), material=skin_mat, segments=8))
            leg.parent = root
            arm.parent = torso
            limbs.append((leg, arm, side))
        if weapon in ("rifle", "spear", "sword"):
            holder = limbs[1][1]
            if weapon == "rifle":
                gun = group(name + " súng", (0, -0.12 * u, -0.5 * u))
                wood = mat("#6a4a2e", 0.6)
                metal = mat("#2e302c", 0.4, 0.7)
                attach(gun, box(name + " thân súng", (0.05 * u, 0.42 * u, 0.07 * u), (0, -0.1 * u, 0), material=metal),
                       box(name + " báng", (0.05 * u, 0.22 * u, 0.09 * u), (0, 0.2 * u, -0.02 * u), material=wood),
                       cylinder(name + " nòng", 0.012 * u, 0.32 * u, (0, -0.45 * u, 0.01 * u), (90, 0, 0), material=metal, vertices=8),
                       box(name + " băng đạn", (0.04 * u, 0.06 * u, 0.13 * u), (0, -0.14 * u, -0.08 * u), (15, 0, 0), material=metal))
                gun.rotation_euler = (math.radians(-60 if pose in ("aim",) else -20), 0, math.radians(-10))
            else:
                gun = group(name + " vũ khí", (0, -0.1 * u, -0.5 * u))
                if weapon == "spear":
                    attach(gun, cylinder(name + " cán giáo", 0.015 * u, 2.0 * u, (0, 0, 0.5 * u), material=mat("#6a4a2e", 0.7), vertices=8),
                           cone(name + " mũi giáo", 0.04 * u, 0, 0.2 * u, (0, 0, 1.6 * u), material=mat("#9a9a96", 0.3, 0.8), vertices=8))
                else:
                    attach(gun, box(name + " lưỡi kiếm", (0.02 * u, 0.06 * u, 0.8 * u), (0, 0, 0.45 * u), material=mat("#a8a8a2", 0.25, 0.9)))
            gun.parent = holder
        if pose in ("run", "crouch"):
            step = max(2, int(fps * (0.18 if pose == "run" else 0.24)))
            for frame in range(1, end + 1, step):
                phase = 1 if (frame // step) % 2 == 0 else -1
                for leg, arm, side in limbs:
                    leg.rotation_euler = (math.radians(38 * phase * side), 0, 0)
                    leg.keyframe_insert("rotation_euler", frame=frame)
                    arm.rotation_euler = (math.radians(-30 * phase * side - (25 if weapon else 0)), 0, 0)
                    arm.keyframe_insert("rotation_euler", frame=frame)
        elif pose == "aim" or weapon:
            for leg, arm, side in limbs:
                arm.rotation_euler = (math.radians(-70 if pose == "aim" else -35), 0, math.radians(side * -15))
        if pose == "crouch":
            root.location.z -= 0.15 * u
        return root

    def mech(name="Mech", location=(0, 0, 0), height=12, color="#3a4048", eye="#ff5a2a"):
        """Giant walker robot; returns a group to move with animate()."""
        u = height / 12
        root = group(name, location)
        armor = mat(color, roughness=0.4, metallic=0.7)
        lamp_mat = glow(eye, 12.0)
        parts = [box(name + " thân", (4 * u, 3 * u, 3.6 * u), (0, 0, 7.6 * u), material=armor),
                 box(name + " đầu", (1.6 * u, 1.4 * u, 1.1 * u), (0, -0.6 * u, 9.9 * u), material=armor),
                 box(name + " mắt", (1.1 * u, 0.1 * u, 0.25 * u), (0, -1.32 * u, 9.95 * u), material=lamp_mat, bevel=0),
                 box(name + " lõi", (0.8 * u, 0.1 * u, 0.8 * u), (0, -1.52 * u, 7.8 * u), material=lamp_mat, bevel=0)]
        for side in (-1, 1):
            parts += [box(name + " vai", (1.4 * u, 2 * u, 1.2 * u), (side * 2.7 * u, 0, 8.8 * u), material=armor),
                      box(name + " tay", (0.9 * u, 0.9 * u, 3.6 * u), (side * 2.9 * u, -0.2 * u, 6.6 * u), material=armor),
                      cylinder(name + " nòng", 0.35 * u, 3 * u, (side * 2.9 * u, -1.8 * u, 5.1 * u), (90, 0, 0), material=armor),
                      box(name + " đùi", (1.3 * u, 1.5 * u, 3.2 * u), (side * 1.3 * u, 0, 4.4 * u), material=armor),
                      box(name + " cẳng", (1.1 * u, 1.3 * u, 3.4 * u), (side * 1.3 * u, -0.2 * u, 1.7 * u), material=armor),
                      box(name + " bàn chân", (1.6 * u, 2.4 * u, 0.5 * u), (side * 1.3 * u, -0.4 * u, 0.25 * u), material=armor)]
        attach(root, *parts)
        return root

    def ship(name="Ship", location=(0, 0, 20), size=6, color="#2f3640", engine="#5ad8ff"):
        """Small aircraft silhouette with glowing engines; move it with animate()."""
        u = size / 6
        root = group(name, location)
        hull = mat(color, roughness=0.35, metallic=0.7)
        flame = glow(engine, 15.0)
        attach(root, box(name + " thân", (1.2 * u, 6 * u, 0.7 * u), (0, 0, 0), material=hull),
               box(name + " cánh", (6 * u, 1.8 * u, 0.15 * u), (0, 0.6 * u, 0), material=hull),
               cone(name + " mũi", 0.55 * u, 0, 1.6 * u, (0, -3.7 * u, 0), (90, 0, 0), material=hull),
               box(name + " động cơ", (1 * u, 0.2 * u, 0.5 * u), (0, 3.05 * u, 0), material=flame, bevel=0))
        return root

    # ---------- nature ----------
    def varied_mat(color, roughness=0.75, scale=18.0, contrast=0.35, bump=0.5, name="Vật liệu"):
        """Colour with natural variation and fine bumps (leaves, cloth, painted metal) instead of flat plastic."""
        material = mat(color, roughness=roughness, name=name)
        tree = material.node_tree
        nodes, links = tree.nodes, tree.links
        shader = nodes.get("Principled BSDF")
        noise = nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = scale
        noise.inputs["Detail"].default_value = 6.0
        ramp = nodes.new("ShaderNodeValToRGB")
        r, g, b, a = color_of(color)
        ramp.color_ramp.elements[0].color = (r * (1 - contrast), g * (1 - contrast), b * (1 - contrast), 1)
        ramp.color_ramp.elements[1].color = (min(1, r * (1 + contrast * 0.6)), min(1, g * (1 + contrast * 0.6)), min(1, b * (1 + contrast * 0.4)), 1)
        links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        links.new(ramp.outputs["Color"], shader.inputs["Base Color"])
        relief = nodes.new("ShaderNodeBump")
        relief.inputs["Strength"].default_value = bump
        links.new(noise.outputs["Fac"], relief.inputs["Height"])
        links.new(relief.outputs["Normal"], shader.inputs["Normal"])
        return material

    def leaf_mat(color, seed):
        rng = random.Random(seed)
        r, g, b, _ = color_of(color)
        k = rng.uniform(0.7, 1.0)
        return varied_mat((r * k * 0.8, g * k * 0.9, b * k * 0.7), 0.7, 9.0, 0.45, 0.8, "Lá")

    def leaf_blade(name, length, width, material, droop=70, pinnate=False):
        """A leaf that starts at its base (the object origin), points along +Y and droops at the tip."""
        segments = 8
        verts, faces = [], []
        for i in range(segments + 1):
            t = i / segments
            w = width * (math.sin(math.pi * min(1, t * 1.1)) if not pinnate else (1 - t * 0.7)) / 2 + 0.01
            verts += [(-w, t * length, 0), (w, t * length, 0)]
            if i:
                a = (i - 1) * 2
                faces.append((a, a + 1, a + 3, a + 2))
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata([(x, y, -((y / length) ** 2) * length * math.sin(math.radians(droop)) * 0.6) for x, y, _ in verts], [], faces)
        obj = bpy.data.objects.new(name, mesh)
        scene.collection.objects.link(obj)
        obj.data.materials.append(material)
        if pinnate:
            mod = obj.modifiers.new("Răng lược", "WIREFRAME")
            mod.thickness = width * 0.18
            mod.use_replace = False
        return obj

    def blob(name, radius, location, color, seed=0, detail=0.35, material=None):
        """Organic lumpy shape (tree crowns, bushes, rocks, mounds)."""
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=radius)
        obj = bpy.context.active_object
        tex = bpy.data.textures.new(name + " noise", "CLOUDS")
        tex.noise_scale = 0.6
        disp = obj.modifiers.new("Displace", "DISPLACE")
        disp.texture = tex
        disp.strength = radius * detail
        disp.texture_coords = "OBJECT"
        bpy.ops.object.shade_smooth()
        return finish(obj, name, color, material or leaf_mat(color, seed), location, (0, 0, random.Random(seed).uniform(0, 360)))

    def tree(kind="jungle", location=(0, 0, 0), height=None, color=None, seed=0, sway=0.0):
        """kind jungle|palm|bamboo|pine|broadleaf|banana; returns a group. sway>0 makes the crown move in the wind."""
        rng = random.Random(seed or int(location[0] * 31 + location[1] * 17))
        h = height or {"palm": rng.uniform(8, 13), "bamboo": rng.uniform(7, 11), "pine": rng.uniform(9, 16), "banana": rng.uniform(3, 4.5)}.get(kind, rng.uniform(8, 15))
        root = group("Cây " + kind, location)
        bark = texture_mat("bark", 2) if (library.get("textures") or {}).get("bark") else mat("#4b3b2b", 0.9)
        leaves = color or {"palm": "#5c7a35", "bamboo": "#6d8a3c", "pine": "#2f4a2c", "banana": "#6a8f3a", "broadleaf": "#4f6b33"}.get(kind, "#3f5e2e")
        crown = group("Tán lá", (0, 0, h))
        crown.parent = root
        if kind == "palm":
            lean = rng.uniform(-8, 8)
            for i in range(5):
                seg = cylinder("Thân dừa", 0.2 - i * 0.02, h / 5, (math.sin(math.radians(lean)) * h * i / 5 * 0.3, 0, h / 10 + i * h / 5), (lean * i / 5, 0, 0), material=bark, vertices=10)
                seg.parent = root
            crown.location = (math.sin(math.radians(lean)) * h * 0.3, 0, h)
            for i in range(11):
                frond = leaf_blade("Lá dừa", 4.4, 0.9, leaf_mat(leaves, seed + i), rng.uniform(60, 95), pinnate=True)
                frond.rotation_euler = (math.radians(rng.uniform(-15, 10)), 0, math.radians(i * 360 / 11 + rng.uniform(-8, 8)))
                frond.parent = crown
        elif kind == "bamboo":
            for i in range(rng.randint(7, 12)):
                x, y = rng.uniform(-0.8, 0.8), rng.uniform(-0.8, 0.8)
                hh = h * rng.uniform(0.7, 1.05)
                stalk = cylinder("Thân tre", 0.05, hh, (x, y, hh / 2), (rng.uniform(-6, 6), rng.uniform(-6, 6), 0), material=mat("#7d8a45", 0.5), vertices=8)
                stalk.parent = root
                puff = blob("Lá tre", rng.uniform(0.6, 1.1), (x * 1.6, y * 1.6, hh * rng.uniform(0.75, 0.95)), leaves, seed + i, 0.6)
                puff.scale = (1, 1, 1.5)
                puff.parent = root
            crown.location = (0, 0, h * 0.85)
        elif kind == "pine":
            cylinder("Thân thông", 0.22, h * 0.35, (0, 0, h * 0.17), material=bark, vertices=10).parent = root
            for i in range(4):
                c = cone("Tầng lá thông", (1.8 - i * 0.4) * h / 12, 0, h * 0.34, (0, 0, h * (0.32 + i * 0.17) - h), material=leaf_mat(leaves, seed + i), vertices=12)
                c.parent = crown
        elif kind == "banana":
            cylinder("Thân chuối", 0.16, h * 0.6, (0, 0, h * 0.3), material=mat("#7a8a4a", 0.7), vertices=10).parent = root
            crown.location = (0, 0, h * 0.6)
            for i in range(7):
                leaf = leaf_blade("Lá chuối", 2.4, 0.75, leaf_mat(leaves, seed + i), rng.uniform(35, 70))
                leaf.rotation_euler = (math.radians(rng.uniform(-35, -10)), 0, math.radians(i * 51 + rng.uniform(-10, 10)))
                leaf.parent = crown
        else:
            trunk_h = h * (0.55 if kind == "jungle" else 0.45)
            cylinder("Thân cây", 0.28 * h / 12, trunk_h, (0, 0, trunk_h / 2), (rng.uniform(-4, 4), rng.uniform(-4, 4), 0), material=bark, vertices=10).parent = root
            crown.location = (0, 0, trunk_h)
            for i in range(rng.randint(3, 5)):
                r = h * rng.uniform(0.16, 0.26)
                b = blob("Tán lá", r, (rng.uniform(-r, r) * 0.8, rng.uniform(-r, r) * 0.8, rng.uniform(0, h - trunk_h) * 0.6), leaves, seed + i)
                b.scale = (1, 1, 0.75 if kind == "jungle" else 0.9)
                b.parent = crown
        if sway:
            for i, t in enumerate([0, duration * 0.33, duration * 0.66, duration]):
                angle = sway * 4 * (1 if i % 2 else -1)
                animate(crown, t, rotation=(angle, angle * 0.6, 0))
        return root

    def wind_curve(modifier, wind, gust, path="angle", scale=1.0):
        steps = max(4, int(duration * 2))
        for i in range(steps + 1):
            t = duration * i / steps
            angle = math.sin(i * 1.7) * 18 * wind
            if gust and gust[0] <= t <= gust[1]:
                angle += 75 * (gust[2] if len(gust) > 2 else 1.0) * (1 if i % 2 else 0.8)
            setattr(modifier, path, math.radians(angle * scale))
            modifier.keyframe_insert(path, frame=seconds(t))

    def grass(center=(0, 0, 0), size=(20, 20), density=40, height=0.6, color="#5d7a38", wind=0.3, gust=None, seed=1):
        """Grass field; gust=(start, end, strength 0..1) flattens it (helicopter downwash, explosion).
        Uses real grass clumps from the library when downloaded, else thousands of generated blades."""
        bpy.ops.mesh.primitive_plane_add(size=1)
        field = bpy.context.active_object
        field.name = "Đồng cỏ"
        field.scale = (size[0], size[1], 1)
        field.location = center
        field.data.materials.append(texture_mat("grass", max(size) / 3) if (library.get("textures") or {}).get("grass") else mat("#3a4a25", 0.9))
        field["su_ground"] = True
        clumps = [found for found in (asset_collection(k) for k in ("grass_clump", "grass_short")) if found]
        if clumps:
            coll, dims = clumps[0]
            for obj in coll.all_objects:
                if obj.type == "MESH":
                    bend = obj.modifiers.new("Gió", "SIMPLE_DEFORM")
                    bend.deform_method = "BEND"
                    bend.deform_axis = "X"
                    wind_curve(bend, wind, gust, scale=0.5)
            system = field.modifiers.new("Cỏ", "PARTICLE_SYSTEM").particle_system
            settings = system.settings
            settings.type = "HAIR"
            settings.use_advanced_hair = True
            # Real clumps are heavy: a few thousand per field reads as a meadow and keeps renders fast.
            settings.count = int(min(1500 if draft else 3500, size[0] * size[1] * density / 10))
            settings.hair_length = height
            settings.render_type = "COLLECTION"
            settings.instance_collection = coll
            settings.particle_size = height / max(dims.z, 0.05)
            settings.size_random = 0.5
            settings.use_rotations = True
            settings.rotation_mode = "GLOB_Z"
            settings.phase_factor_random = 2.0
            system.seed = seed
            return field
        bpy.ops.mesh.primitive_plane_add(size=1)
        blade = bpy.context.active_object
        blade.name = "Lá cỏ"
        blade.scale = (0.06, 1, 1)
        blade.rotation_euler = (math.radians(90), 0, 0)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        for v in blade.data.vertices:
            v.co.z += 0.5
            if v.co.z > 0.9:
                v.co.x *= 0.2
        blade.data.materials.append(leaf_mat(color, seed))
        bend = blade.modifiers.new("Gió", "SIMPLE_DEFORM")
        bend.deform_method = "BEND"
        bend.deform_axis = "X"
        blade.location = (0, 0, -500)
        blade["su_ground"] = True
        wind_curve(bend, wind, gust)
        system = field.modifiers.new("Cỏ", "PARTICLE_SYSTEM").particle_system
        settings = system.settings
        settings.type = "HAIR"
        settings.use_advanced_hair = True
        settings.count = int(min(20000 if draft else 50000, size[0] * size[1] * density * 3))
        settings.hair_length = height
        settings.render_type = "OBJECT"
        settings.instance_object = blade
        settings.particle_size = height
        settings.size_random = 0.6
        settings.use_rotations = True
        settings.rotation_mode = "NOR"
        settings.phase_factor_random = 2.0
        settings.use_rotation_instance = False
        system.seed = seed
        return field

    def mound(location=(0, 0, 0), size=(4, 3, 0.8), texture="mud", seed=3):
        obj = blob("Mô đất", 1.0, location, None, seed, 0.25, texture_mat(texture, 2))
        obj.scale = size
        obj["su_ground"] = True
        return obj

    def sandbags(start=(0, 0, 0), end=(4, 0, 0), rows=3, color="#9a8f6a"):
        """Wall of rounded sandbags from start to end."""
        a, b = Vector(start), Vector(end)
        length = (b - a).length
        count = max(1, int(length / 0.62))
        heading = math.degrees(math.atan2(b.y - a.y, b.x - a.x))
        bag_mat = texture_mat("planks", 1, color) if False else mat(color, roughness=0.95)
        wall = group("Bao cát", tuple(a))
        for row in range(rows):
            for i in range(count - (row % 2)):
                offset = (i + (0.5 if row % 2 else 0) + 0.5) / count
                p = a + (b - a) * offset
                bag = blob("Bao cát", 0.32, (p.x, p.y, a.z + 0.13 + row * 0.24), color, i + row * 31, 0.08, bag_mat)
                bag.scale = (0.95, 0.55, 0.4)
                bag.rotation_euler = (0, 0, math.radians(heading + random.uniform(-6, 6)))
        return wall

    def impact(location=(0, 0, 0), at=0.0, kind="dirt", size=1.0):
        """Bullet hit: dirt kicks up (kind='dirt') or sparks off metal/stone (kind='spark')."""
        if kind == "spark":
            sparks(location, at, 8, "#ffd27a", 0.6 * size)
            return
        rng = random.Random(int(at * 100 + location[0] * 7))
        dirt = mat("#4e4232", 0.95)
        for i in range(10):
            chunk = box("Đất tung", [0.06 * size] * 3, location, material=dirt, bevel=0)
            animate(chunk, at, location=tuple(location))
            peak = Vector(location) + Vector((rng.uniform(-0.6, 0.6) * size, rng.uniform(-0.6, 0.6) * size, rng.uniform(0.6, 1.6) * size))
            animate(chunk, at + 0.18, location=tuple(peak))
            animate(chunk, at + 0.55, location=(peak.x * 1.1, peak.y * 1.1, location[2]))
            appear(chunk, at, at + 0.6)
        smoke(location, 0.35 * size, 3, "#7d705a", 1.2 * size, at, 1.0, int(at * 10))

    def helicopter(name="Trực thăng", location=(0, 0, 10), size=13, color="#4d5638", rotor_speed=1440):
        """Utility helicopter (Huey-like silhouette) with spinning rotors; rotor_speed in degrees per second."""
        u = size / 13
        root = group(name, location)
        paint = mat(color, roughness=0.7, metallic=0.2)
        glass = mat("#2b3a40", 0.05, 0.6)
        dark = mat("#262824", 0.6)
        attach(root, blob(name + " thân", 1.5 * u, (0, 0, 0), color, 7, 0.0, paint),
               box(name + " kính", (1.7 * u, 0.6 * u, 0.9 * u), (0, -1.6 * u, 0.2 * u), (18, 0, 0), material=glass),
               cone(name + " cần đuôi", 0.45 * u, 0.15 * u, 6.5 * u, (0, 4.3 * u, 0.3 * u), (-90, 0, 0), material=paint, vertices=12),
               box(name + " vây đuôi", (0.12 * u, 1.0 * u, 1.6 * u), (0, 7.3 * u, 0.9 * u), (12, 0, 0), material=paint),
               cylinder(name + " trục", 0.12 * u, 0.6 * u, (0, -0.2 * u, 1.55 * u), material=dark, vertices=10))
        for blobpart in root.children:
            if blobpart.name.startswith(name + " thân"):
                blobpart.scale = (0.85, 1.7, 0.8)
        for side in (-1, 1):
            attach(root, cylinder(name + " càng", 0.06 * u, 3.6 * u, (side * 1.1 * u, -0.3 * u, -1.55 * u), (90, 0, 0), material=dark, vertices=8),
                   cylinder(name + " chân càng", 0.05 * u, 0.6 * u, (side * 1.0 * u, -1 * u, -1.25 * u), material=dark, vertices=8),
                   cylinder(name + " chân càng", 0.05 * u, 0.6 * u, (side * 1.0 * u, 0.6 * u, -1.25 * u), material=dark, vertices=8))
        rotor = group(name + " cánh quạt", (0, -0.2 * u, 1.9 * u))
        rotor.parent = root
        attach(rotor, box(name + " cánh", (14.6 * u, 0.5 * u, 0.06 * u), (0, 0, 0), material=dark, bevel=0))
        tail = group(name + " cánh đuôi", (0.25 * u, 7.4 * u, 0.9 * u))
        tail.parent = root
        attach(tail, box(name + " cánh đuôi", (0.05 * u, 2.6 * u, 0.25 * u), (0, 0, 0), material=dark, bevel=0))
        spin_object(rotor, rotor_speed, "Z")
        spin_object(tail, rotor_speed * 3, "X")
        return root

    def spin_object(obj, speed=360, axis="Z"):
        index = "XYZ".index(axis.upper()) if str(axis).upper() in "XYZ" else 2
        rot = list(obj.rotation_euler)
        obj.keyframe_insert("rotation_euler", index=index, frame=1)
        rot[index] += math.radians(speed * duration)
        obj.rotation_euler = rot
        obj.keyframe_insert("rotation_euler", index=index, frame=end)
        for curve in fcurves_of(obj):
            if curve.data_path == "rotation_euler":
                for point in curve.keyframe_points:
                    point.interpolation = "LINEAR"

    # ---------- library models (Poly Haven and the user's own) ----------
    asset_cache = {}

    def asset_collection(name):
        name = library_key(name) if (library.get("models") or {}).get(library_key(name)) else name
        if name in asset_cache:
            return asset_cache[name]
        path = (library.get("models") or {}).get(name)
        if not path:
            return None
        coll = bpy.data.collections.new("Kho " + name)
        scene.collection.children.link(coll)
        layer = bpy.context.view_layer.layer_collection.children[coll.name]
        bpy.context.view_layer.active_layer_collection = layer
        before = set(bpy.data.objects)
        ext = path.rsplit(".", 1)[-1].lower()
        try:
            if ext == "blend":
                with bpy.data.libraries.load(path, link=False) as (src, dst):
                    dst.objects = list(src.objects)
                for obj in dst.objects:
                    if obj is not None and obj.type not in ("CAMERA", "LIGHT"):
                        coll.objects.link(obj)
            elif ext in ("glb", "gltf"):
                bpy.ops.import_scene.gltf(filepath=path)
            elif ext == "fbx":
                bpy.ops.import_scene.fbx(filepath=path)
            elif ext == "obj":
                bpy.ops.wm.obj_import(filepath=path)
            elif ext in ("usd", "usdz", "usdc", "usda"):
                bpy.ops.wm.usd_import(filepath=path)
            elif ext == "stl":
                bpy.ops.wm.stl_import(filepath=path)
        except Exception as error:
            log("SU_STAGE Không nhập được model %s: %s" % (name, error))
        bpy.context.view_layer.active_layer_collection = bpy.context.view_layer.layer_collection
        for obj in [o for o in bpy.data.objects if o not in before]:
            if obj.type in ("CAMERA", "LIGHT"):
                bpy.data.objects.remove(obj)
        bpy.context.view_layer.update()
        meshes = [o for o in coll.all_objects if o.type == "MESH"]
        if not meshes:
            scene.collection.children.unlink(coll)
            asset_cache[name] = None
            return None
        pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
        lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
        hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
        coll.instance_offset = ((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z)
        scene.collection.children.unlink(coll)
        asset_cache[name] = (coll, hi - lo)
        return asset_cache[name]

    def asset(name, location=(0, 0, 0), rotation=(0, 0, 0), height=None, length=None, scale=None):
        """Place a model from the library by its name (see LIBRARY in the context). Size with height= or length= (metres)."""
        found = asset_collection(name)
        if not found:
            log("SU_STAGE Kho chưa có model '%s'" % name)
            return group("Thiếu " + str(name), location)
        coll, dims = found
        inst = bpy.data.objects.new(name, None)
        inst.instance_type = "COLLECTION"
        inst.instance_collection = coll
        scene.collection.objects.link(inst)
        k = scale or (height / max(dims.z, 0.001) if height else length / max(dims.x, dims.y, 0.001) if length else 1.0)
        inst.scale = (k, k, k)
        inst.location = location
        inst.rotation_euler = [math.radians(a) for a in rotation]
        inst["su_dims"] = [dims.x * k, dims.y * k, dims.z * k]
        return inst

    def spin(target, part="rotor", speed=1440, axis="Z"):
        """Spin a named part of a library model (e.g. spin(heli, 'rotor')) or any object."""
        coll = getattr(target, "instance_collection", None)
        if coll is None:
            spin_object(target, speed, axis)
            return
        for obj in coll.all_objects:
            if part.lower() in obj.name.lower():
                spin_object(obj, speed, axis)

    def scatter(kind, count=20, center=(0, 0, 0), area=(30, 30), size=(0.8, 1.2), avoid=None, seed=5, **options):
        """Place many trees/assets: kind is a library model name or a tree kind (jungle, palm, bamboo, pine, banana, broadleaf).
        avoid=(x, y, radius) keeps a clearing free (paths, the hero)."""
        rng = random.Random(seed)
        placed = []
        for i in range(count):
            for _ in range(10):
                x = center[0] + rng.uniform(-area[0] / 2, area[0] / 2)
                y = center[1] + rng.uniform(-area[1] / 2, area[1] / 2)
                if not avoid or math.hypot(x - avoid[0], y - avoid[1]) > avoid[2]:
                    break
            k = rng.uniform(*size)
            if (library.get("models") or {}).get(kind):
                obj = asset(kind, (x, y, center[2]), (0, 0, rng.uniform(0, 360)), scale=k * options.get("scale", 1.0))
            else:
                obj = tree(kind, (x, y, center[2]), options.get("height", None) and options["height"] * k, options.get("color"), seed + i, options.get("sway", 0.0))
                if not options.get("height"):
                    obj.scale = (k, k, k)
            placed.append(obj)
        return placed

    def slowmo(start=8.0, factor=0.35):
        """Everything after `start` seconds plays at `factor` speed (0.35 ≈ slow motion)."""
        state["slowmo"] = (float(start), max(0.1, min(1.0, float(factor))))

    # ---------- lights, sky, atmosphere ----------
    def sun(strength=3.0, elevation=40, azimuth=135, color="#fff4e0", angle=2.0):
        light = bpy.data.lights.new("Sun", "SUN")
        light.energy = strength
        light.color = color_of(color)[:3]
        light.angle = math.radians(angle)
        obj = bpy.data.objects.new("Sun", light)
        scene.collection.objects.link(obj)
        obj.rotation_euler = (math.radians(90 - elevation), 0, math.radians(azimuth))
        return obj

    def lamp(location=(0, 0, 3), power=500, color="#ffcf8a", radius=0.3):
        light = bpy.data.lights.new("Lamp", "POINT")
        light.energy = power
        light.color = color_of(color)[:3]
        light.shadow_soft_size = radius
        obj = bpy.data.objects.new("Lamp", light)
        scene.collection.objects.link(obj)
        obj.location = location
        return obj

    def world_nodes():
        world = scene.world or bpy.data.worlds.new("World")
        scene.world = world
        return world, node_tree(world)

    def sky(color="#9fb8d0", strength=1.0):
        world, tree = world_nodes()
        background = tree.nodes.get("Background")
        if background:
            background.inputs["Color"].default_value = color_of(color)
            background.inputs["Strength"].default_value = strength
        world.color = color_of(color)[:3]
        state["world"] = True

    def fog(density=0.006, color="#c9b9a8", anisotropy=0.4):
        """Atmospheric haze: light shafts and depth. 0.003 light haze, 0.006 clear haze, 0.012 thick smoke.
        Built after framing as a volume box around the scene (a world volume would swallow sun and sky light)."""
        state["fog"] = (max(0.0, min(0.05, float(density))), color, anisotropy)

    # ---------- animation and effects ----------
    def seconds(t):
        return 1 + int(round(float(t) * fps))

    def animate(obj, at, location=None, rotation=None, scale=None):
        frame = seconds(at)
        if location is not None:
            obj.location = location
            obj.keyframe_insert("location", frame=frame)
        if rotation is not None:
            obj.rotation_euler = [math.radians(a) for a in rotation]
            obj.keyframe_insert("rotation_euler", frame=frame)
        if scale is not None:
            obj.scale = scale if isinstance(scale, (tuple, list)) else (scale, scale, scale)
            obj.keyframe_insert("scale", frame=frame)

    def appear(obj, at, until=None):
        """Show obj only from second `at` (until second `until`)."""
        hidden, shown = (0.0001,) * 3, tuple(obj.scale)
        obj.scale = hidden
        obj.keyframe_insert("scale", frame=max(1, seconds(at) - 1))
        obj.scale = shown
        obj.keyframe_insert("scale", frame=seconds(at))
        if until is not None:
            obj.keyframe_insert("scale", frame=seconds(until))
            obj.scale = hidden
            obj.keyframe_insert("scale", frame=seconds(until) + 1)
        obj.scale = shown
        return obj

    def smoke(location=(0, 0, 0), radius=2.0, puffs=6, color="#5d5853", rise=3.0, at=0.0, density=1.2, seed=1):
        """Billowing smoke column made of soft volume puffs that grow and rise."""
        rng = random.Random(seed)
        material = volume_mat(color, density)
        root = group("Khói", location)
        for i in range(puffs):
            r = radius * rng.uniform(0.5, 1.0)
            puff = sphere("Khói", r, (rng.uniform(-radius, radius) * 0.6, rng.uniform(-radius, radius) * 0.6, r * 0.6 + i * radius * 0.35), material=material, segments=16)
            puff.parent = root
            start = puff.location.copy()
            animate(puff, at, location=tuple(start), scale=0.4)
            animate(puff, min(duration, at + duration), location=tuple(start + Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rise))), scale=1.15)
            if at > 0:
                appear(puff, at)
        return root

    def explosion(location=(0, 0, 0), at=1.0, size=4.0, color="#ff8a3a"):
        """Fireball flash, light burst, shockwave ring and lingering smoke."""
        fire = sphere("Quả cầu lửa", size * 0.5, location, material=volume_mat("#2a1a10", 4.0, color, 18.0, "Lửa"), segments=24)
        core = sphere("Lõi lửa", size * 0.12, location, material=glow("#ffc070", 14.0), segments=16)
        animate(core, max(0, at - 0.05), scale=0.001)
        animate(core, at + 0.15, scale=1.0)
        animate(core, at + 0.6, scale=0.001)
        animate(fire, max(0, at - 0.05), scale=0.001)
        animate(fire, at + 0.25, scale=1.0)
        animate(fire, at + 0.9, scale=1.25)
        animate(fire, at + 1.1, scale=0.001)
        light = lamp(location, 0, color, size * 0.4)
        light.data.energy = 0
        light.data.keyframe_insert("energy", frame=max(1, seconds(at) - 1))
        light.data.energy = 60000 * size
        light.data.keyframe_insert("energy", frame=seconds(at + 0.15))
        light.data.energy = 0
        light.data.keyframe_insert("energy", frame=seconds(at + 1.2))
        bpy.ops.mesh.primitive_torus_add(major_radius=size * 0.5, minor_radius=size * 0.04)
        ring = finish(bpy.context.active_object, "Sóng xung kích", None, volume_mat("#c8b8a0", 2.0), (location[0], location[1], location[2] * 0 + 0.3), (0, 0, 0))
        animate(ring, max(0, at - 0.05), scale=0.001)
        animate(ring, at + 0.05, scale=0.2)
        animate(ring, at + 1.0, scale=4.0)
        animate(ring, at + 1.2, scale=0.001)
        smoke(location, size * 0.8, 7, "#4a4440", size * 0.8, at + 0.3, 1.5)
        return fire

    def beam(start=(0, 0, 1), end=(10, 0, 1), at=0.0, travel=0.35, color="#56e4ff", width=0.06):
        """An energy bolt that flies from start to end, then sparks where it lands."""
        a, b = Vector(start), Vector(end)
        direction = b - a
        bolt = cylinder("Tia năng lượng", width, min(2.5, direction.length * 0.25), tuple(a), (0, 0, 0), material=glow(color, 30.0), vertices=8)
        bolt.rotation_mode = "QUATERNION"
        bolt.rotation_quaternion = direction.to_track_quat("Z", "Y")
        animate(bolt, at, location=tuple(a))
        animate(bolt, at + travel, location=tuple(b))
        appear(bolt, at, at + travel)
        sparks(tuple(b), at + travel, 10, color)
        return bolt

    def sparks(location=(0, 0, 0), at=0.0, count=12, color="#ffd27a", spread=1.5, seed=3):
        rng = random.Random(seed)
        material = glow(color, 20.0)
        for i in range(count):
            spark = box("Tia lửa", (0.05, 0.05, 0.05), location, material=material, bevel=0)
            target = Vector(location) + Vector((rng.uniform(-spread, spread), rng.uniform(-spread, spread), rng.uniform(0.2, spread)))
            animate(spark, at, location=tuple(location))
            animate(spark, at + rng.uniform(0.3, 0.7), location=tuple(target), scale=0.2)
            appear(spark, at, at + 0.8)

    def shield(location=(0, 0, 1), radius=1.4, color="#59d8ff", at=0.0):
        dome = sphere("Lá chắn", radius, location, material=mat(color, 0.1, 0, color, 1.2, alpha=0.12), segments=32)
        animate(dome, at, scale=0.001)
        animate(dome, at + 0.3, scale=1.0)
        return dome

    def shot(start=(8, -8, 4), end=None, target=(0, 0, 1), lens=35):
        state["shot"] = {"start": tuple(start), "end": tuple(end or start), "target": tuple(target), "lens": lens}

    def camera_path(keys, lens=35, shake=None, focus=None):
        """keys: [(second, (x,y,z) camera, (x,y,z) look-at), ...] — one key per beat of the shot list."""
        state["path"] = {"keys": [(float(t), tuple(p), tuple(a)) for t, p, a in keys], "lens": lens, "shake": shake, "focus": focus}

    toolbox = {"bpy": bpy, "bmesh": bmesh, "mathutils": mathutils, "Vector": Vector, "math": math, "random": random,
               "mat": mat, "glow": glow, "window_mat": window_mat, "box": box, "cylinder": cylinder, "cone": cone, "sphere": sphere, "plane": plane,
               "group": group, "attach": attach, "ground": ground, "water": water, "building": building, "figure": figure,
               "mech": mech, "ship": ship, "sun": sun, "lamp": lamp, "sky": sky, "fog": fog, "animate": animate,
               "appear": appear, "smoke": smoke, "explosion": explosion, "beam": beam, "sparks": sparks, "shield": shield,
               "texture_mat": texture_mat, "sky_hdri": sky_hdri, "blob": blob, "tree": tree, "grass": grass, "mound": mound,
               "sandbags": sandbags, "impact": impact, "helicopter": helicopter, "asset": asset, "spin": spin, "scatter": scatter,
               "slowmo": slowmo,
               "seconds": seconds, "shot": shot, "camera_path": camera_path, "FPS": fps, "DURATION": duration}

    # ---------- image mode: 2.5D camera moves over still images ----------
    if job["mode"] == "image":
        build_image_scene(bpy, scene, job, fps, end, effects, toolbox)
        render_frames(bpy, scene, job, end, effects)
        return

    # ---------- measure a model for the library (no render) ----------
    if job["mode"] == "measure":
        found = asset_collection("subject")
        if not found:
            fail("Không đọc được model 3D này.")
        coll, dims = found
        parts = sorted({o.name for o in coll.all_objects if o.type in ("MESH", "EMPTY")})[:40]
        animated = any(o.animation_data and o.animation_data.action for o in coll.all_objects)
        log("SU_MEASURE " + json.dumps({"size": [round(dims.x, 3), round(dims.y, 3), round(dims.z, 3)], "parts": parts, "animated": animated}, ensure_ascii=False))
        return

    # ---------- build the scene ----------
    if job["mode"] == "script":
        problems = check_script(job["script"])
        if problems:
            fail("Script chưa an toàn để chạy: " + "; ".join(problems[:5]))
        log("SU_STAGE Đang dựng cảnh từ script…")

        def limited_import(name, globals=None, locals=None, fromlist=(), level=0):
            if name.split(".")[0] not in ALLOWED_IMPORTS or level:
                raise ImportError(name)
            return __import__(name, globals, locals, fromlist, level)

        source = __builtins__ if isinstance(__builtins__, dict) else vars(__builtins__)
        safe = {k: source[k] for k in (
            "range", "len", "min", "max", "abs", "int", "float", "str", "list", "dict", "tuple", "set", "bool",
            "enumerate", "zip", "round", "sum", "sorted", "reversed", "print", "isinstance", "map", "filter", "any",
            "all", "pow", "divmod", "Exception", "ValueError", "KeyError", "IndexError", "True", "False", "None") if k in source}
        safe["__import__"] = limited_import
        namespace = dict(toolbox)
        namespace["__builtins__"] = safe
        try:
            exec(compile(job["script"], "scene_script", "exec"), namespace)
        except Exception as error:
            fail("Script dựng cảnh lỗi: %s: %s" % (type(error).__name__, error))
    else:
        path = job["model"]
        ext = path.rsplit(".", 1)[-1].lower()
        log("SU_STAGE Đang nhập model 3D…")
        before = set(bpy.data.objects)
        try:
            if ext == "blend":
                with bpy.data.libraries.load(path, link=False) as (source_data, target):
                    target.objects = list(source_data.objects)
                for obj in target.objects:
                    if obj is not None:
                        scene.collection.objects.link(obj)
            elif ext in ("glb", "gltf"):
                bpy.ops.import_scene.gltf(filepath=path)
            elif ext == "fbx":
                bpy.ops.import_scene.fbx(filepath=path)
            elif ext == "obj":
                if hasattr(bpy.ops.wm, "obj_import"):
                    bpy.ops.wm.obj_import(filepath=path)
                else:
                    bpy.ops.import_scene.obj(filepath=path)
            elif ext in ("usd", "usdz", "usdc", "usda"):
                bpy.ops.wm.usd_import(filepath=path)
            elif ext == "stl":
                if hasattr(bpy.ops.wm, "stl_import"):
                    bpy.ops.wm.stl_import(filepath=path)
                else:
                    bpy.ops.import_mesh.stl(filepath=path)
            else:
                fail("Định dạng model chưa hỗ trợ: ." + ext)
        except Exception as error:
            fail("Không nhập được model: %s" % error)
        imported = [o for o in bpy.data.objects if o not in before]
        if not any(o.type == "MESH" for o in imported):
            fail("Model không có khối 3D nào để render.")
        if job.get("useFileCamera"):
            cameras = [o for o in imported if o.type == "CAMERA"]
            if cameras:
                scene.camera = cameras[0]
        if job.get("ground", True):
            bpy.context.view_layer.update()
            low = min((o.matrix_world @ Vector(c)).z for o in imported if o.type == "MESH" for c in o.bound_box)
            g = ground(size=1, color="#6b6458")
            g.location.z = low
            g["su_auto_ground"] = True

    apply_output()
    bpy.context.view_layer.update()

    # ---------- framing ----------
    meshes = [o for o in scene.objects if o.type == "MESH" and not o.get("su_ground")]
    if not meshes:
        meshes = [o for o in scene.objects if o.type == "MESH" and o.location.z > -100]
    if not meshes and not any(o.type == "EMPTY" and o.get("su_dims") for o in scene.objects):
        fail("Cảnh chưa có vật thể nào để render.")
    points = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    for o in scene.objects:
        if o.type == "EMPTY" and o.get("su_dims"):
            half = Vector(o["su_dims"]) / 2
            base = o.matrix_world.translation
            points += [base + Vector((sx * half.x, sy * half.y, sz * half.z * 2)) for sx in (-1, 1) for sy in (-1, 1) for sz in (0, 1)]
    low = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    high = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    center = (low + high) / 2
    radius = max(0.5, (high - low).length / 2)
    for o in scene.objects:
        if o.get("su_auto_ground"):
            o.scale = (radius * 12, radius * 12, 1)

    # ---------- lighting and atmosphere ----------
    preset = job.get("lighting", "day")
    if not any(o.type == "LIGHT" and o.data.type == "SUN" for o in scene.objects) and not state.get("hdri"):
        if preset == "golden":
            sun(4.0, 9, 250, "#ff9a4d", 3.0)
        elif preset == "night":
            sun(0.5, 35, 60, "#7f9cff")
            lamp(tuple(center + Vector((radius, -radius, radius))), 120 * radius * radius, "#ffb060", radius * 0.2)
        elif preset == "studio":
            sun(2.0, 50, 140, "#ffffff")
            sun(0.8, 25, 300, "#dfe8ff")
        else:
            sun(3.5, 45, 135, "#fff2dc")
    if not state["world"]:
        sky({"golden": "#2c4258", "night": "#0a1222", "studio": "#d8d8d8"}.get(preset, "#9fbcd8"),
            {"night": 0.2, "studio": 0.8, "golden": 0.7}.get(preset, 0.9))
    fog_density = float(effects.get("fog") or 0)
    if fog_density > 0 and not state.get("fog"):
        fog(fog_density / max(1.0, radius / 15), {"golden": "#e3b089", "night": "#6c7fa8"}.get(preset, "#c9c4bc"))
    if state.get("fog"):
        density, color, anisotropy = state["fog"]
        span = max(120.0, radius * 6)
        material = volume_mat(color, density * 0.45, name="Sương")
        for node in material.node_tree.nodes:
            if node.bl_idname == "ShaderNodeVolumePrincipled":
                node.inputs["Anisotropy"].default_value = anisotropy
        domain = box("Sương mù", (span, span, max(40.0, high.z - low.z + 30)), (center.x, center.y, low.z + max(40.0, high.z - low.z + 30) / 2 - 1), material=material, bevel=0)
        domain["su_ground"] = True

    # ---------- camera ----------
    camera = scene.camera
    target = None
    if camera is None:
        cam_data = bpy.data.cameras.new("Camera")
        camera = bpy.data.objects.new("Camera", cam_data)
        scene.collection.objects.link(camera)
        scene.camera = camera
        target = bpy.data.objects.new("CameraTarget", None)
        scene.collection.objects.link(target)
        track = camera.constraints.new("TRACK_TO")
        track.target = target
        track.track_axis = "TRACK_NEGATIVE_Z"
        track.up_axis = "UP_Y"
        aspect = scene.render.resolution_x / scene.render.resolution_y
        if state["path"]:
            cam_data.lens = state["path"]["lens"]
            stops = [(seconds(t), Vector(p), Vector(a)) for t, p, a in sorted(state["path"]["keys"])]
        elif state["shot"]:
            s = state["shot"]
            cam_data.lens = s["lens"]
            stops = [(1, Vector(s["start"]), Vector(s["target"])), (end, Vector(s["end"]), Vector(s["target"]))]
        else:
            cam_data.lens = 35
            distance = radius * 2.6 * (1.0 if aspect >= 1 else 1.6)
            lift = math.radians(18)

            def orbit(angle, dist, height=None):
                a = math.radians(angle)
                h = dist * math.sin(lift) if height is None else height
                flat = dist * math.cos(lift)
                return center + Vector((flat * math.sin(a), -flat * math.cos(a), h))

            move = job.get("camera", "orbit")
            if move == "dolly":
                stops = [(1, orbit(-20, distance * 1.3), center), (end, orbit(-20, distance * 0.85), center)]
            elif move == "pan":
                side = Vector((radius * 0.7, 0, 0))
                stops = [(1, orbit(0, distance) - side, center - side), (end, orbit(0, distance) + side, center + side)]
            elif move == "crane":
                stops = [(1, orbit(-15, distance * 1.05, radius * 0.15), center), (end, orbit(-15, distance * 0.95, radius * 1.4), center)]
            elif move == "static":
                stops = [(1, orbit(-25, distance), center), (end, orbit(-25, distance), center)]
            else:
                stops = [(1, orbit(-35, distance), center), (end, orbit(35, distance), center)]
        for frame, position, aim in stops:
            camera.location = position
            camera.keyframe_insert("location", frame=frame)
            target.location = aim
            target.keyframe_insert("location", frame=frame)
        cam_data.clip_start = max(0.01, radius / 500)
        cam_data.clip_end = max(1000.0, radius * 60)
        focus_distance = (stops[0][1] - stops[0][2]).length
        if effects.get("dof"):
            cam_data.dof.use_dof = True
            cam_data.dof.focus_object = target
            cam_data.dof.aperture_fstop = 2.8 if focus_distance < 15 else 5.6
        shake = state["path"]["shake"] if state["path"] and state["path"]["shake"] is not None else effects.get("shake")
        if shake:
            amount = (0.03 if shake is True else float(shake)) * max(1.0, focus_distance / 10)
            for curve in fcurves_of(camera):
                if curve.data_path == "location":
                    noise = curve.modifiers.new("NOISE")
                    noise.strength = amount
                    noise.scale = 14
                    noise.phase = curve.array_index * 7.3

    # ---------- slow motion: stretch every animation curve after the start time ----------
    if state.get("slowmo"):
        start_s, factor = state["slowmo"]
        pivot = seconds(start_s)
        for action in bpy.data.actions:
            for curve in action_fcurves(action):
                for point in curve.keyframe_points:
                    for attr in ("co", "handle_left", "handle_right"):
                        value = getattr(point, attr)
                        if value.x > pivot:
                            value.x = pivot + (value.x - pivot) / factor
                curve.update()

    render_frames(bpy, scene, job, end, effects)


def render_frames(bpy, scene, job, end, effects):
    """Bloom, then either a few preview stills or the whole animation as PNG frames."""
    if effects.get("bloom"):
        add_bloom(bpy, scene)

    def on_frame(*_args):
        log("SU_PROGRESS %d/%d" % (bpy.context.scene.frame_current, end))

    stills = [int(f) for f in job.get("frames") or [] if 1 <= int(f) <= end]
    if stills:
        # Preview: a few single frames instead of the whole clip.
        log("SU_STAGE Đang render %d khung xem trước…" % len(stills))
        for index, frame in enumerate(stills, 1):
            scene.frame_set(frame)
            scene.render.filepath = job["output"].rstrip("/") + "/frame_%04d.png" % frame
            bpy.ops.render.render(write_still=True)
            log("SU_PROGRESS %d/%d" % (index, len(stills)))
        log("SU_DONE")
        return
    bpy.app.handlers.render_write.append(on_frame)
    log("SU_STAGE Đang render %d khung hình…" % end)
    bpy.ops.render.render(animation=True)
    log("SU_DONE")


def build_image_scene(bpy, scene, job, fps, end, effects, tools):
    """Each shot: a background plane and (when separated) a subject plane closer to the camera, so camera moves
    give real parallax. Shots sit far apart; the camera cuts between them. Overlays add smoke, fog, dust, embers, rain."""
    from mathutils import Vector
    log("SU_STAGE Đang dựng cảnh từ ảnh…")
    # Show the pictures' own colours: no filmic tone mapping on the images.
    try:
        scene.view_settings.view_transform = "Standard"
        scene.view_settings.look = "None"
    except TypeError:
        pass
    if hasattr(scene.render, "motion_blur_position"):
        scene.render.motion_blur_position = "START"
    width, height = scene.render.resolution_x, scene.render.resolution_y
    aspect = width / height
    lens, sensor = 50.0, 36.0
    cam_data = bpy.data.cameras.new("Camera")
    cam_data.lens, cam_data.sensor_width, cam_data.sensor_fit = lens, sensor, "AUTO"
    camera = bpy.data.objects.new("Camera", cam_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.rotation_euler = (math.radians(90), 0, 0)
    tools["sky"]("#8a8f94", 0.9)
    tools["sun"](2.0, 35, 140, "#fff1dc")

    def frame_size(distance):
        span = distance * sensor / lens
        return (span, span / aspect) if aspect >= 1 else (span * aspect, span)

    def picture(path, distance, x, name, flashes, alpha=False):
        image = bpy.data.images.load(path, check_existing=True)
        iw, ih = image.size
        fw, fh = frame_size(distance)
        ratio = iw / max(ih, 1)
        w = max(fw, fh * ratio) * 1.2
        h = w / ratio
        bpy.ops.mesh.primitive_plane_add(size=1)
        plane = bpy.context.active_object
        plane.name = name
        plane.scale = (w, h, 1)
        plane.location = (x, distance, 0)
        plane.rotation_euler = (math.radians(90), 0, 0)
        material = bpy.data.materials.new(name)
        if material.node_tree is None or bpy.app.version < (5, 0, 0):
            material.use_nodes = True
        nodes, links = material.node_tree.nodes, material.node_tree.links
        for node in list(nodes):
            if node.bl_idname != "ShaderNodeOutputMaterial":
                nodes.remove(node)
        out = next(n for n in nodes if n.bl_idname == "ShaderNodeOutputMaterial")
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = image
        tex.extension = "EXTEND"
        emit = nodes.new("ShaderNodeEmission")
        links.new(tex.outputs["Color"], emit.inputs["Color"])
        emit.inputs["Strength"].default_value = 1.0
        for at in flashes:
            for t, value in ((at - 0.05, 1.0), (at + 0.06, 2.4), (at + 0.5, 1.0)):
                emit.inputs["Strength"].default_value = value
                emit.inputs["Strength"].keyframe_insert("default_value", frame=max(1, 1 + int(round(t * fps))))
        emit.inputs["Strength"].default_value = 1.0
        if alpha:
            clear = nodes.new("ShaderNodeBsdfTransparent")
            mix = nodes.new("ShaderNodeMixShader")
            links.new(tex.outputs["Alpha"], mix.inputs[0])
            links.new(clear.outputs[0], mix.inputs[1])
            links.new(emit.outputs[0], mix.inputs[2])
            links.new(mix.outputs[0], out.inputs["Surface"])
            for attr, value in (("surface_render_method", "DITHERED"), ("blend_method", "HASHED")):
                try:
                    setattr(material, attr, value)
                except (AttributeError, TypeError):
                    pass
        else:
            links.new(emit.outputs[0], out.inputs["Surface"])
        plane.data.materials.append(material)
        return plane, (w, h)

    def particles(name, x, count, size, color, strength, velocity, brownian, lifetime_s, box, gravity=0.0, seed=1, streak=False):
        bpy.ops.mesh.primitive_cube_add(size=1)
        emitter = bpy.context.active_object
        emitter.name = name
        emitter.scale = box[1]
        emitter.location = (x + box[0][0], box[0][1], box[0][2])
        emitter.display_type = "WIRE"
        emitter.show_instancer_for_render = False  # show the particles, not the emitter box
        if streak:
            bpy.ops.mesh.primitive_cylinder_add(radius=size, depth=size * 40, vertices=6)
        else:
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=size)
        speck = bpy.context.active_object
        speck.name = name + " hạt"
        speck.location = (x, -500, 0)
        speck.data.materials.append(tools["glow"](color, strength))
        system = emitter.modifiers.new(name, "PARTICLE_SYSTEM").particle_system
        settings = system.settings
        settings.count = int(count)
        settings.frame_start = 1 - int(lifetime_s * fps)
        settings.frame_end = end
        settings.lifetime = int(lifetime_s * fps)
        settings.lifetime_random = 0.5
        settings.emit_from = "VOLUME"
        settings.physics_type = "NEWTON"
        settings.normal_factor = 0.0
        settings.object_align_factor = tuple(velocity) if isinstance(velocity, (tuple, list)) else (0.0, 0.0, float(velocity))
        settings.factor_random = 0.3
        settings.brownian_factor = brownian
        settings.effector_weights.gravity = gravity
        settings.render_type = "OBJECT"
        settings.instance_object = speck
        settings.particle_size = 1.0
        settings.size_random = 0.6
        settings.use_rotations = streak
        if streak:
            settings.rotation_mode = "VEL"
        system.seed = seed
        return emitter

    def fog_layer(x, density, color="#c8c4bc"):
        material = bpy.data.materials.new("Sương trôi")
        if material.node_tree is None or bpy.app.version < (5, 0, 0):
            material.use_nodes = True
        nodes, links = material.node_tree.nodes, material.node_tree.links
        for node in list(nodes):
            if node.bl_idname != "ShaderNodeOutputMaterial":
                nodes.remove(node)
        out = next(n for n in nodes if n.bl_idname == "ShaderNodeOutputMaterial")
        coords, mapping, noise, ramp, vol = (nodes.new(k) for k in ("ShaderNodeTexCoord", "ShaderNodeMapping", "ShaderNodeTexNoise", "ShaderNodeValToRGB", "ShaderNodeVolumePrincipled"))
        noise.inputs["Scale"].default_value = 0.6
        noise.inputs["Detail"].default_value = 4.0
        ramp.color_ramp.elements[0].position = 0.45
        ramp.color_ramp.elements[0].color = (0, 0, 0, 1)
        ramp.color_ramp.elements[1].color = (density, density, density, 1)
        vol.inputs["Color"].default_value = tuple(int(color.lstrip("#")[i:i + 2], 16) / 255 for i in (0, 2, 4)) + (1,)
        links.new(coords.outputs["Object"], mapping.inputs["Vector"])
        links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
        links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        links.new(ramp.outputs["Color"], vol.inputs["Density"])
        links.new(vol.outputs[0], out.inputs["Volume"])
        mapping.inputs["Location"].default_value = (0, 0, 0)
        mapping.inputs["Location"].keyframe_insert("default_value", frame=1)
        mapping.inputs["Location"].default_value = (0.35 * end / fps, 0.05, 0)
        mapping.inputs["Location"].keyframe_insert("default_value", frame=end)
        bpy.ops.mesh.primitive_cube_add(size=1)
        box = bpy.context.active_object
        box.name = "Sương trôi"
        box.scale = (14, 3, 8)
        box.location = (x, 8.5, 0)
        box.data.materials.append(material)
        return box

    overlays = job.get("overlays") or {}
    shots = job["shots"]
    cursor = 1
    keys = []
    for index, shot in enumerate(shots):
        x = index * 400.0
        frames = max(1, int(round(float(shot["seconds"]) * fps)))
        first, last = cursor, min(end, cursor + frames - 1)
        cursor = last + 1
        flashes = [float(t) for t in shot.get("flashes", [])]
        background, (bw, bh) = picture(shot["background"], 10.0, x, "Ảnh nền %d" % (index + 1), flashes)
        if shot.get("subject"):
            picture(shot["subject"], 7.0, x, "Chủ thể %d" % (index + 1), flashes, alpha=True)
        move = shot.get("move", "push")
        strength = float(shot.get("strength", 1.0))
        a, b = Vector((x, 0, 0)), Vector((x, 0, 0))
        tilt_a = tilt_b = 0.0
        if move == "push":
            b.y += 1.1 * strength
        elif move == "pull":
            a.y += 1.1 * strength
        elif move == "pan_left":
            a.x += 0.55 * strength
            b.x -= 0.55 * strength
        elif move == "pan_right":
            a.x -= 0.55 * strength
            b.x += 0.55 * strength
        elif move == "rise":
            a.z -= 0.4 * strength
            b.z += 0.4 * strength
            b.y += 0.4 * strength
        elif move == "orbit":
            a.x -= 0.5 * strength
            b.x += 0.5 * strength
            tilt_a, tilt_b = 1.6 * strength, -1.6 * strength
            b.y += 0.5 * strength
        else:
            b.x += 0.12 * strength
            b.y += 0.15 * strength
        keys.append((first, a, tilt_a, False))
        keys.append((last, b, tilt_b, index < len(shots) - 1))
        smoke_k, fog_k, dust_k, ember_k, rain_k = (float(overlays.get(k, 0)) for k in ("smoke", "fog", "dust", "embers", "rain"))
        if smoke_k:
            # Low drifting smoke between the subject and the background, kept to the lower part of the frame.
            for side in (-1, 1):
                tools["smoke"]((x + side * 2.6, 8.4, -2.4), 0.8 + smoke_k * 0.6, int(3 + smoke_k * 3), "#7a736c", 0.8 + smoke_k, 0.0, 0.25 + smoke_k * 0.35, index * 7 + side)
        if fog_k:
            fog_layer(x, 0.035 * fog_k)
        if dust_k:
            particles("Bụi", x, 160 * dust_k + 40, 0.012, "#fff1d6", 1.5, 0.0, 0.25, 8, ((0, 5.5, 0), (8, 6, 5)), seed=index + 3)
        if ember_k:
            e = particles("Tàn lửa", x, 120 * ember_k + 20, 0.018, "#ff8a3a", 18.0, 0.0, 0.6, 4, ((0, 6, -3.2), (8, 5, 0.5)), gravity=-0.12, seed=index + 5)
            e.particle_systems[0].settings.normal_factor = 0.0
            e.particle_systems[0].settings.object_align_factor = (0, 0, 0.7)
        if rain_k:
            r = particles("Mưa", x, 1600 * rain_k + 200, 0.004, "#cfd6dc", 0.9, 0.0, 0.0, 1.2, ((0, 5, 3.5), (10, 6, 1)), gravity=1.0, seed=index + 9, streak=True)
            r.particle_systems[0].settings.object_align_factor = (0.4, 0, -14)
    # Camera keys: eased moves inside a shot, hard cuts between shots.
    from_curves = []
    for frame, position, tilt, cut in keys:
        camera.location = position
        camera.keyframe_insert("location", frame=frame)
        camera.rotation_euler = (math.radians(90), 0, math.radians(tilt))
        camera.keyframe_insert("rotation_euler", frame=frame)
    for curve in fcurves_of(camera):
        for point in curve.keyframe_points:
            match = [k for k in keys if k[0] == int(round(point.co.x))]
            if match and match[-1][3]:
                point.interpolation = "CONSTANT"
    if effects.get("shake"):
        for curve in fcurves_of(camera):
            if curve.data_path == "location":
                noise = curve.modifiers.new("NOISE")
                noise.strength = 0.025
                noise.scale = 16
                noise.phase = curve.array_index * 5.1
    scene.render.use_motion_blur = bool(effects.get("motionBlur")) and len(shots) == 1


def fcurves_of(obj):
    """Animation curves of an object, across Blender 4.x (action.fcurves) and 5.x (channelbags)."""
    data = obj.animation_data
    if not data or not data.action:
        return []
    action = data.action
    if hasattr(action, "fcurves"):
        return list(action.fcurves)
    from bpy_extras import anim_utils
    bag = anim_utils.action_get_channelbag_for_slot(action, data.action_slot)
    return list(bag.fcurves) if bag else []


def action_fcurves(action):
    """All curves in an action (4.x flat list; 5.x layered channelbags)."""
    if hasattr(action, "fcurves"):
        return list(action.fcurves)
    curves = []
    for layer in getattr(action, "layers", []):
        for strip in layer.strips:
            for bag in getattr(strip, "channelbags", []):
                curves += list(bag.fcurves)
    return curves


def add_bloom(bpy, scene):
    """Compositor glare in Bloom mode; Blender 5 uses node groups, 4.x the scene node tree."""
    try:
        if hasattr(scene, "compositing_node_group") and bpy.app.version >= (5, 0, 0):
            tree = bpy.data.node_groups.new("Su Studio Bloom", "CompositorNodeTree")
            tree.interface.new_socket(name="Image", in_out="OUTPUT", socket_type="NodeSocketColor")
            layers = tree.nodes.new("CompositorNodeRLayers")
            glare = tree.nodes.new("CompositorNodeGlare")
            output = tree.nodes.new("NodeGroupOutput")
            glare.inputs["Type"].default_value = "Bloom"
            for key, value in (("Threshold", 1.0), ("Strength", 0.7), ("Size", 0.6), ("Quality", "Medium")):
                if key in glare.inputs:
                    glare.inputs[key].default_value = value
            tree.links.new(layers.outputs["Image"], glare.inputs["Image"])
            tree.links.new(glare.outputs["Image"], output.inputs["Image"])
            scene.compositing_node_group = tree
        else:
            scene.use_nodes = True
            tree = scene.node_tree
            layers = tree.nodes.get("Render Layers") or tree.nodes.new("CompositorNodeRLayers")
            composite = tree.nodes.get("Composite") or tree.nodes.new("CompositorNodeComposite")
            glare = tree.nodes.new("CompositorNodeGlare")
            glare.glare_type = "BLOOM" if "BLOOM" in [i.identifier for i in glare.bl_rna.properties["glare_type"].enum_items] else "FOG_GLOW"
            glare.threshold = 1.0
            tree.links.new(layers.outputs["Image"], glare.inputs["Image"])
            tree.links.new(glare.outputs["Image"], composite.inputs["Image"])
        scene.render.use_compositing = True
    except Exception as error:
        log("SU_STAGE Bỏ qua hiệu ứng phát sáng: %s" % error)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    if args[:1] == ["--check"]:
        with open(args[1], encoding="utf-8") as handle:
            found = check_script(handle.read())
        print(json.dumps(found, ensure_ascii=False))
        sys.exit(1 if found else 0)
    if not args:
        fail("Thiếu file công việc.")
    try:
        main(args[0])
    except SystemExit:
        raise
    except Exception as error:
        import traceback
        for line in traceback.format_exc().strip().splitlines()[-6:]:
            log("SU_TRACE " + line)
        fail("%s: %s" % (type(error).__name__, str(error).strip().splitlines()[-1] if str(error).strip() else ""))
