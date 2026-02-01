#!/usr/bin/env python3
"""
Create a complete light gun arcade cabinet GLB template.
Run with: blender --background --python create_lightgun_template.py -- output.glb

Light gun cabinets are larger deluxe units with:
- Wide horizontal screen
- Mounted light guns on retractable cables
- Often have pedal for reload/cover mechanics
- Popular for games like Time Crisis, House of the Dead, Point Blank
"""

import bpy
import bmesh
import math
import sys
from mathutils import Vector

def clear_scene():
    """Remove all objects from scene"""
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    for block in bpy.data.meshes:
        if block.users == 0:
            bpy.data.meshes.remove(block)

def create_box(name, dimensions, location=(0,0,0)):
    """Create a box mesh"""
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = dimensions
    bpy.ops.object.transform_apply(scale=True)
    return obj

def create_side_panel_lightgun(name, is_right=False):
    """Create light gun cabinet side panel with distinctive profile"""
    # Light gun cabinets are typically wider and have a different profile
    profile_2d = [
        (0.0, 0.0),       # Bottom front
        (0.0, 0.20),      # Front lower
        (-0.10, 0.30),    # Gun shelf angle
        (-0.10, 0.90),    # Gun area
        (-0.15, 1.00),    # Below screen
        (-0.12, 1.50),    # Screen area
        (-0.08, 1.80),    # Above screen
        (-0.05, 1.95),    # Marquee bottom
        (-0.05, 2.10),    # Marquee top
        (0.0, 2.15),      # Top front
        (-0.50, 2.15),    # Top back
        (-0.55, 2.00),    # Back angle
        (-0.55, 0.0),     # Back bottom
    ]
    
    thickness = 0.02
    
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    
    y_offset = thickness/2 if is_right else -thickness/2
    y_back = -thickness/2 if is_right else thickness/2
    
    front_verts = [bm.verts.new((x, y_offset, z)) for x, z in profile_2d]
    back_verts = [bm.verts.new((x, y_back, z)) for x, z in profile_2d]
    
    bm.verts.ensure_lookup_table()
    
    bm.faces.new(front_verts)
    bm.faces.new(list(reversed(back_verts)))
    
    n = len(profile_2d)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([front_verts[i], front_verts[j], back_verts[j], back_verts[i]])
    
    bm.to_mesh(mesh)
    bm.free()
    
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    
    y_pos = 0.40 if is_right else -0.40
    obj.location = (0, y_pos, 0)
    
    return obj

def create_bezel_with_cutout(name, outer_w, outer_h, cutout_w, cutout_h, thickness=0.01):
    """Create a bezel panel with screen cutout"""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    
    hw, hh = outer_w/2, outer_h/2
    chw, chh = cutout_w/2, cutout_h/2
    t = thickness/2
    
    v1 = bm.verts.new((-hw, -t, -hh))
    v2 = bm.verts.new((hw, -t, -hh))
    v3 = bm.verts.new((hw, -t, hh))
    v4 = bm.verts.new((-hw, -t, hh))
    
    v5 = bm.verts.new((-chw, -t, -chh))
    v6 = bm.verts.new((chw, -t, -chh))
    v7 = bm.verts.new((chw, -t, chh))
    v8 = bm.verts.new((-chw, -t, chh))
    
    v1b = bm.verts.new((-hw, t, -hh))
    v2b = bm.verts.new((hw, t, -hh))
    v3b = bm.verts.new((hw, t, hh))
    v4b = bm.verts.new((-hw, t, hh))
    
    v5b = bm.verts.new((-chw, t, -chh))
    v6b = bm.verts.new((chw, t, -chh))
    v7b = bm.verts.new((chw, t, chh))
    v8b = bm.verts.new((-chw, t, chh))
    
    bm.verts.ensure_lookup_table()
    
    bm.faces.new([v1, v2, v6, v5])
    bm.faces.new([v2, v3, v7, v6])
    bm.faces.new([v3, v4, v8, v7])
    bm.faces.new([v4, v1, v5, v8])
    
    bm.faces.new([v5b, v6b, v2b, v1b])
    bm.faces.new([v6b, v7b, v3b, v2b])
    bm.faces.new([v7b, v8b, v4b, v3b])
    bm.faces.new([v8b, v5b, v1b, v4b])
    
    bm.faces.new([v1, v1b, v2b, v2])
    bm.faces.new([v2, v2b, v3b, v3])
    bm.faces.new([v3, v3b, v4b, v4])
    bm.faces.new([v4, v4b, v1b, v1])
    
    bm.faces.new([v5, v6, v6b, v5b])
    bm.faces.new([v6, v7, v7b, v6b])
    bm.faces.new([v7, v8, v8b, v7b])
    bm.faces.new([v8, v5, v5b, v8b])
    
    bm.to_mesh(mesh)
    bm.free()
    
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj

def create_gun(name, location):
    """Create a simple light gun model"""
    # Gun body
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    gun_body = bpy.context.active_object
    gun_body.scale = (0.03, 0.15, 0.04)
    bpy.ops.object.transform_apply(scale=True)
    
    # Gun barrel
    bpy.ops.mesh.primitive_cylinder_add(radius=0.012, depth=0.08, 
                                        location=(location[0], location[1] + 0.11, location[2]))
    barrel = bpy.context.active_object
    barrel.rotation_euler = (math.pi/2, 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    
    # Gun handle
    bpy.ops.mesh.primitive_cube_add(size=1, 
                                     location=(location[0], location[1] - 0.02, location[2] - 0.05))
    handle = bpy.context.active_object
    handle.scale = (0.02, 0.04, 0.06)
    handle.rotation_euler = (0.3, 0, 0)
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    
    # Join all parts
    bpy.ops.object.select_all(action='DESELECT')
    gun_body.select_set(True)
    barrel.select_set(True)
    handle.select_set(True)
    bpy.context.view_layer.objects.active = gun_body
    bpy.ops.object.join()
    
    gun_body.name = name
    return gun_body

def create_t_molding_lightgun():
    """Create T-molding for light gun cabinet"""
    radius = 0.008
    
    # Cabinet front edge path
    path = [
        (-0.10, -0.40, 0.30),
        (-0.10, 0.40, 0.30),
        (-0.10, 0.40, 0.90),
        (-0.15, 0.40, 1.00),
        (-0.15, -0.40, 1.00),
        (-0.10, -0.40, 0.90),
        (-0.10, -0.40, 0.30),
    ]
    
    # Top edge path
    path2 = [
        (-0.05, -0.40, 1.95),
        (-0.05, 0.40, 1.95),
        (-0.05, 0.40, 2.10),
        (-0.05, -0.40, 2.10),
        (-0.05, -0.40, 1.95),
    ]
    
    def create_tube_segment(p1, p2, r):
        direction = Vector(p2) - Vector(p1)
        length = direction.length
        if length < 0.001:
            return None
        
        bpy.ops.mesh.primitive_cylinder_add(
            radius=r,
            depth=length,
            location=((p1[0]+p2[0])/2, (p1[1]+p2[1])/2, (p1[2]+p2[2])/2)
        )
        cyl = bpy.context.active_object
        
        direction.normalize()
        up = Vector((0, 0, 1))
        if abs(direction.dot(up)) > 0.999:
            up = Vector((1, 0, 0))
        
        rot_axis = up.cross(direction)
        if rot_axis.length > 0.001:
            rot_axis.normalize()
            rot_angle = math.acos(max(-1, min(1, up.dot(direction))))
            cyl.rotation_mode = 'AXIS_ANGLE'
            cyl.rotation_axis_angle = (rot_angle, rot_axis.x, rot_axis.y, rot_axis.z)
        
        return cyl
    
    segments = []
    for i in range(len(path) - 1):
        seg = create_tube_segment(path[i], path[i+1], radius)
        if seg:
            segments.append(seg)
    
    for i in range(len(path2) - 1):
        seg = create_tube_segment(path2[i], path2[i+1], radius)
        if seg:
            segments.append(seg)
    
    if segments:
        bpy.ops.object.select_all(action='DESELECT')
        for seg in segments:
            seg.select_set(True)
        bpy.context.view_layer.objects.active = segments[0]
        bpy.ops.object.join()
        
        obj = bpy.context.active_object
        obj.name = "t-molding"
        return obj
    
    return None

def create_lightgun_cabinet():
    """Create complete light gun arcade cabinet"""
    clear_scene()
    
    print("Creating light gun cabinet template...")
    
    # Create root
    bpy.ops.object.empty_add(type='PLAIN_AXES', location=(0, 0, 0))
    root = bpy.context.active_object
    root.name = "cabinet-root"
    
    # Side panels
    print("  Creating side panels...")
    left = create_side_panel_lightgun("left", is_right=False)
    left.parent = root
    
    right = create_side_panel_lightgun("right", is_right=True)
    right.parent = root
    
    # Back panel
    print("  Creating back panel...")
    back = create_box("back", (0.02, 0.78, 2.00), (-0.54, 0, 1.00))
    back.parent = root
    
    # Top panel
    print("  Creating top panel...")
    top = create_box("top", (0.50, 0.78, 0.02), (-0.27, 0, 2.14))
    top.parent = root
    
    # Bottom panel
    print("  Creating bottom panel...")
    bottom = create_box("bottom", (0.55, 0.78, 0.02), (-0.27, 0, 0.01))
    bottom.parent = root
    
    # Front upper panel (above guns)
    print("  Creating front panels...")
    front = create_box("front", (0.02, 0.78, 0.50), (-0.14, 0, 1.25))
    front.parent = root
    
    # Front lower panel (gun holster area)
    front_lower = create_box("front-lower", (0.02, 0.78, 0.55), (-0.09, 0, 0.60))
    front_lower.parent = root
    
    # Marquee
    print("  Creating marquee...")
    bpy.ops.mesh.primitive_plane_add(size=1, location=(-0.04, 0, 2.02))
    marquee = bpy.context.active_object
    marquee.name = "marquee"
    marquee.scale = (0.75, 0.12, 1)
    marquee.rotation_euler = (math.pi/2, -0.1, 0)
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    marquee.parent = root
    
    # Marquee box
    marquee_box = create_box("marquee-box", (0.10, 0.78, 0.15), (-0.08, 0, 2.02))
    marquee_box.parent = root
    
    # Bezel (large screen)
    print("  Creating bezel...")
    bezel = create_bezel_with_cutout("bezel", 0.75, 0.55, 0.60, 0.42, 0.015)
    bezel.location = (-0.13, 0, 1.25)
    bezel.rotation_euler = (0, -0.15, 0)
    bpy.ops.object.transform_apply(rotation=True)
    bezel.parent = root
    
    # Screen
    print("  Creating screen...")
    bpy.ops.mesh.primitive_plane_add(size=1, location=(-0.12, 0, 1.25))
    screen = bpy.context.active_object
    screen.name = "screen"
    screen.scale = (0.56, 0.40, 1)
    screen.rotation_euler = (math.pi/2, -0.15, 0)
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    screen.parent = root
    
    # Screen mocks
    bpy.ops.mesh.primitive_cube_add(size=0.01, location=(-0.12, 0, 1.25))
    screen_mock_h = bpy.context.active_object
    screen_mock_h.name = "screen-mock-horizontal"
    screen_mock_h.scale = (0.01, 0.56, 0.40)
    bpy.ops.object.transform_apply(scale=True)
    screen_mock_h.parent = root
    
    bpy.ops.mesh.primitive_cube_add(size=0.01, location=(-0.12, 0, 1.25))
    screen_mock_v = bpy.context.active_object
    screen_mock_v.name = "screen-mock-vertical"
    screen_mock_v.scale = (0.01, 0.40, 0.56)
    bpy.ops.object.transform_apply(scale=True)
    screen_mock_v.parent = root
    
    # Light guns
    print("  Creating light guns...")
    gun = create_gun("gun", (-0.08, -0.18, 0.85))
    gun.parent = root
    
    gun2 = create_gun("gun2", (-0.08, 0.18, 0.85))
    gun2.parent = root
    
    # Gun holster shelf
    gun_shelf = create_box("gun-shelf", (0.12, 0.78, 0.02), (-0.10, 0, 0.90))
    gun_shelf.parent = root
    
    # Coin door
    print("  Creating coin door...")
    coin_door = create_box("coin-door", (0.02, 0.15, 0.12), (-0.08, 0, 0.25))
    coin_door.parent = root
    
    # Speaker panel
    print("  Creating speaker panel...")
    speaker = create_box("speaker", (0.02, 0.40, 0.08), (-0.08, 0, 1.85))
    speaker.parent = root
    
    # Pedal (for reload/cover)
    print("  Creating foot pedal...")
    pedal = create_box("pedal", (0.15, 0.25, 0.03), (0.15, 0, 0.015))
    pedal.parent = root
    
    # T-Molding
    print("  Creating T-molding...")
    t_molding = create_t_molding_lightgun()
    if t_molding:
        t_molding.parent = root
    
    print("Light gun cabinet creation complete!")
    return root

def export_glb(filepath):
    """Export scene to GLB format"""
    print(f"Exporting to: {filepath}")
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format='GLB',
        use_selection=False,
        export_apply=True,
    )
    print("Export complete!")

def main():
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []
    
    if len(argv) < 1:
        output_path = "/tmp/lightgun_cabinet_template.glb"
    else:
        output_path = argv[0]
    
    create_lightgun_cabinet()
    export_glb(output_path)

if __name__ == "__main__":
    main()
