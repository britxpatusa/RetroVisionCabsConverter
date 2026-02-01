#!/usr/bin/env python3
"""
Create a complete cocktail (table-top) arcade cabinet GLB template.
Run with: blender --background --python create_cocktail_template.py -- output.glb

Cocktail cabinets are table-style with:
- Horizontal screen under glass top
- Control panels on opposite sides for 2-player games
- Players sit facing each other
- Screen flips between turns (for games like Pac-Man, Donkey Kong)
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

def create_bezel_with_cutout(name, outer_w, outer_h, cutout_w, cutout_h, thickness=0.005):
    """Create a bezel panel with screen cutout"""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    
    hw, hh = outer_w/2, outer_h/2
    chw, chh = cutout_w/2, cutout_h/2
    t = thickness/2
    
    # Outer corners (top)
    v1 = bm.verts.new((-hw, -hh, t))
    v2 = bm.verts.new((hw, -hh, t))
    v3 = bm.verts.new((hw, hh, t))
    v4 = bm.verts.new((-hw, hh, t))
    
    # Cutout corners (top)
    v5 = bm.verts.new((-chw, -chh, t))
    v6 = bm.verts.new((chw, -chh, t))
    v7 = bm.verts.new((chw, chh, t))
    v8 = bm.verts.new((-chw, chh, t))
    
    # Outer corners (bottom)
    v1b = bm.verts.new((-hw, -hh, -t))
    v2b = bm.verts.new((hw, -hh, -t))
    v3b = bm.verts.new((hw, hh, -t))
    v4b = bm.verts.new((-hw, hh, -t))
    
    # Cutout corners (bottom)
    v5b = bm.verts.new((-chw, -chh, -t))
    v6b = bm.verts.new((chw, -chh, -t))
    v7b = bm.verts.new((chw, chh, -t))
    v8b = bm.verts.new((-chw, chh, -t))
    
    bm.verts.ensure_lookup_table()
    
    # Top faces (with hole)
    bm.faces.new([v1, v2, v6, v5])
    bm.faces.new([v2, v3, v7, v6])
    bm.faces.new([v3, v4, v8, v7])
    bm.faces.new([v4, v1, v5, v8])
    
    # Bottom faces
    bm.faces.new([v5b, v6b, v2b, v1b])
    bm.faces.new([v6b, v7b, v3b, v2b])
    bm.faces.new([v7b, v8b, v4b, v3b])
    bm.faces.new([v8b, v5b, v1b, v4b])
    
    # Outer edges
    bm.faces.new([v1, v1b, v2b, v2])
    bm.faces.new([v2, v2b, v3b, v3])
    bm.faces.new([v3, v3b, v4b, v4])
    bm.faces.new([v4, v4b, v1b, v1])
    
    # Cutout edges
    bm.faces.new([v5, v6, v6b, v5b])
    bm.faces.new([v6, v7, v7b, v6b])
    bm.faces.new([v7, v8, v8b, v7b])
    bm.faces.new([v8, v5, v5b, v8b])
    
    bm.to_mesh(mesh)
    bm.free()
    
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj

def create_t_molding_cocktail():
    """Create T-molding around cocktail cabinet edges"""
    mesh = bpy.data.meshes.new("t-molding")
    bm = bmesh.new()
    
    radius = 0.006
    
    # Table dimensions
    table_w = 0.70
    table_d = 0.55
    table_h = 0.70
    hw, hd = table_w/2, table_d/2
    
    # Path around top edge
    path = [
        (hw, -hd, table_h),
        (hw, hd, table_h),
        (-hw, hd, table_h),
        (-hw, -hd, table_h),
        (hw, -hd, table_h),  # Close loop
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

def create_cocktail_cabinet():
    """Create complete cocktail arcade cabinet"""
    clear_scene()
    
    print("Creating cocktail cabinet template...")
    
    # Dimensions (meters)
    table_width = 0.70   # Width (X)
    table_depth = 0.55   # Depth (Y)
    table_height = 0.70  # Height (Z)
    leg_height = 0.60
    panel_thickness = 0.02
    
    # Create root
    bpy.ops.object.empty_add(type='PLAIN_AXES', location=(0, 0, 0))
    root = bpy.context.active_object
    root.name = "cabinet-root"
    
    # Top glass bezel (with screen cutout)
    print("  Creating glass top bezel...")
    bezel = create_bezel_with_cutout("bezel", table_width, table_depth, 0.45, 0.35, 0.01)
    bezel.location = (0, 0, table_height + 0.005)
    bezel.parent = root
    
    # Screen surface
    print("  Creating screen...")
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0, table_height - 0.01))
    screen = bpy.context.active_object
    screen.name = "screen"
    screen.scale = (0.42, 0.32, 1)
    bpy.ops.object.transform_apply(scale=True)
    screen.parent = root
    
    # Screen mocks for orientation
    bpy.ops.mesh.primitive_cube_add(size=0.01, location=(0, 0, table_height - 0.01))
    screen_mock_h = bpy.context.active_object
    screen_mock_h.name = "screen-mock-horizontal"
    screen_mock_h.scale = (0.42, 0.32, 0.01)
    bpy.ops.object.transform_apply(scale=True)
    screen_mock_h.parent = root
    
    bpy.ops.mesh.primitive_cube_add(size=0.01, location=(0, 0, table_height - 0.01))
    screen_mock_v = bpy.context.active_object
    screen_mock_v.name = "screen-mock-vertical"
    screen_mock_v.scale = (0.32, 0.42, 0.01)
    bpy.ops.object.transform_apply(scale=True)
    screen_mock_v.parent = root
    
    # Side panels (all 4 sides)
    print("  Creating side panels...")
    # Left side
    left = create_box("left", (panel_thickness, table_depth, table_height - leg_height), 
                      (-table_width/2, 0, (table_height + leg_height)/2))
    left.parent = root
    
    # Right side
    right = create_box("right", (panel_thickness, table_depth, table_height - leg_height),
                       (table_width/2, 0, (table_height + leg_height)/2))
    right.parent = root
    
    # Back panel
    back = create_box("back", (table_width, panel_thickness, table_height - leg_height),
                      (0, table_depth/2, (table_height + leg_height)/2))
    back.parent = root
    
    # Front panel (shorter for control area)
    front = create_box("front", (table_width, panel_thickness, table_height - leg_height - 0.12),
                       (0, -table_depth/2, (table_height + leg_height)/2 + 0.06))
    front.parent = root
    
    # Top panel (under glass)
    print("  Creating top panel...")
    top = create_box("top", (table_width - 0.02, table_depth - 0.02, panel_thickness),
                     (0, 0, table_height - 0.015))
    top.parent = root
    
    # Bottom panel
    print("  Creating bottom panel...")
    bottom = create_box("bottom", (table_width - 0.04, table_depth - 0.04, panel_thickness),
                        (0, 0, leg_height + 0.01))
    bottom.parent = root
    
    # Control panels (2 players, opposite sides)
    print("  Creating control panels...")
    # Player 1 (front)
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, -table_depth/2 + 0.06, table_height - 0.05))
    joystick = bpy.context.active_object
    joystick.name = "joystick"
    joystick.scale = (0.30, 0.08, 1)
    joystick.rotation_euler = (0.4, 0, 0)  # Angled toward player
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    joystick.parent = root
    
    # Player 2 (back - opposite side)
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, table_depth/2 - 0.06, table_height - 0.05))
    joystick2 = bpy.context.active_object
    joystick2.name = "joystick-2"
    joystick2.scale = (0.30, 0.08, 1)
    joystick2.rotation_euler = (-0.4 + math.pi, 0, 0)  # Angled toward player 2
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    joystick2.parent = root
    
    # Marquee (small side panel)
    print("  Creating marquee...")
    bpy.ops.mesh.primitive_plane_add(size=1, location=(table_width/2 + 0.005, 0, table_height - 0.05))
    marquee = bpy.context.active_object
    marquee.name = "marquee"
    marquee.scale = (0.15, 0.08, 1)
    marquee.rotation_euler = (0, math.pi/2, 0)
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    marquee.parent = root
    
    # Coin door
    print("  Creating coin door...")
    coin_door = create_box("coin-door", (0.08, panel_thickness + 0.005, 0.06),
                           (0.15, -table_depth/2 - 0.002, leg_height + 0.10))
    coin_door.parent = root
    
    # Legs (4 corners)
    print("  Creating legs...")
    leg_positions = [
        (table_width/2 - 0.03, table_depth/2 - 0.03),
        (-table_width/2 + 0.03, table_depth/2 - 0.03),
        (table_width/2 - 0.03, -table_depth/2 + 0.03),
        (-table_width/2 + 0.03, -table_depth/2 + 0.03),
    ]
    for i, (x, y) in enumerate(leg_positions):
        leg = create_box(f"leg-{i+1}", (0.04, 0.04, leg_height), (x, y, leg_height/2))
        leg.parent = root
    
    # T-Molding
    print("  Creating T-molding...")
    t_molding = create_t_molding_cocktail()
    if t_molding:
        t_molding.parent = root
    
    # Speaker panel (under table)
    print("  Creating speaker panel...")
    speaker = create_box("speaker", (0.15, panel_thickness, 0.08),
                         (0, -table_depth/2, leg_height + 0.06))
    speaker.parent = root
    
    print("Cocktail cabinet creation complete!")
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
        output_path = "/tmp/cocktail_cabinet_template.glb"
    else:
        output_path = argv[0]
    
    create_cocktail_cabinet()
    export_glb(output_path)

if __name__ == "__main__":
    main()
