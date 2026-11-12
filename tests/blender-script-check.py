import importlib.util, sys
spec = importlib.util.spec_from_file_location("driver", sys.argv[1]); driver = importlib.util.module_from_spec(spec); spec.loader.exec_module(driver)
good = '''import math, random
ground(80, "#5f6b45")
for i in range(6):
    cylinder("Coc%d" % i, 0.15, 3, (i * 2, 8, 1), (8, 0, 0), "#4a3420")
boat = box("Thuyen", (6, 1.6, 0.8), (-25, 14, 0.4))
animate(boat, DURATION, location=(10, 14, 0.4))
print(bpy.context.active_object.type == "MESH")
shot((0, -18, 6), (6, -14, 5), (0, 10, 1), 35)
'''
assert driver.check_script(good) == [], driver.check_script(good)
for bad in ['import os', 'from subprocess import run', 'from . import x', '__import__("os")', 'open("/tmp/x","w")',
            'bpy.ops.wm.save_as_mainfile(filepath="x")', 'bpy.app.handlers.frame_change_pre.append(print)',
            'x = (1).__class__', 'getattr(bpy, "ops")', 'bpy.data.texts.new("a")', 'p = "/Users/x/.ssh/id_rsa"',
            'exec("1")', 'eval("1")', 'bpy.utils.register_class', 'class A: pass', 'def f(:', 'bpy.ops.import_scene.gltf()',
            'bpy.data.libraries.load', 'global x', 'img = bpy.data.images', 'bpy.context.preferences', 'p = "~/Desktop"']:
    assert driver.check_script(bad), bad
print("Blender script checker passed: toolbox scripts allowed; imports, files, handlers, dunder, reflection and paths refused")
