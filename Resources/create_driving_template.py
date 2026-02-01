#!/usr/bin/env python3
"""
Create a complete driving/racing arcade cabinet GLB template.
Run with: blender --background --python create_driving_template.py -- output.glb

Driving cabinets feature:
- Large horizontal screen (often curved or tilted)
- Steering wheel with force feedback
- Gas and brake pedals
- Gear shifter (sometimes)
- Bucket seat (sit-down models)
- Dashboard with speedometer/tachometer art
- Wide side panels for immersive racing graphics
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

def create_side_panel_driving(name, is_right=False):
    """Create driving cabinet side panel - wide and enclosing"""
    # Driving cabinets have a distinctive wraparound shape
    profile_2d = [
        (0.0, 0.0),        # Bottom front (where player sits)
        (0.0, 0.40),       # Front foot area
        (-0.20, 0.50),     # Dashboard angle start
        (-0.30, 0.80),     # Dashboard
        (-0.35, 1.10),     # Below screen
        (-0.30, 1.50),     # Screen area (angled back)
        (-0.25, 1.70),     # Above screen
        (-0.20, 1.85),     # Marquee area
        (-0.15, 1.95),     # Top front
        (-0.80, 1.95),     # Top back (long for sit-down)
        (-0.85, 1.80),     # Back upper
        (-0.85, 0.35),     # Back seat area
        (-0.80, 0.0),      # Back bottom
    ]
    
    thickness = 0.02
    
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    
    # Wider spacing for driving cabinet
    y_offset = 0.50 if is_right else -0.50
    y_back = y_offset - thickness if is_right else y_offset + thickness
    
    front_verts = [bm.verts.new((x, y_offset, z)) for x, z in profile_2d]
    back_verts = [bm.verts.new((x, y_back, z)) for x, z in profile_2d]
    
    bm.verts.ensure_lookup_table()
    
    # Create faces
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
    
    return obj

def create_steering_wheel(name, location):
    """Create a steering wheel"""
    # Wheel rim (torus)
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.15,
        minor_radius=0.015,
        location=location
    )
    wheel = bpy.context.active_object
    wheel.rotation_euler = (math.pi/2 - 0.5, 0, 0)  # Angled toward player
    
    # Center hub
    bpy.ops.mesh.primitive_cylinder_add(
        radius=0.04,
        depth=0.03,
        location=location
    )
    hub = bpy.context.active_object
    hub.rotation_euler = (math.pi/2 - 0.5, 0, 0)
    
    # Spokes (3 of them)
    spokes = []
    for i in range(3):
        angle = i * (2 * math.pi / 3)
        bpy.ops.mesh.primitive_cube_add(size=1, location=location)
        spoke = bpy.context.active_object
        spoke.scale = (0.12, 0.015, 0.01)
        spoke.rotation_euler = (math.pi/2 - 0.5, 0, angle)
        bpy.ops.object.transform_apply(scale=True, rotation=True)
        spokes.append(spoke)
    
    # Join all parts
    bpy.ops.object.select_all(action='DESELECT')
    wheel.select_set(True)
    hub.select_set(True)
    for spoke in spokes:
        spoke.select_set(True)
    bpy.context.view_layer.objects.active = wheel
    bpy.ops.object.join()
    
    wheel.name = name
    bpy.ops.object.transform_apply(rotation=True)
    return wheel

def create_pedals(parent):
    """Create gas and brake pedals"""
    # Gas pedal (right)
    gas = create_box("gas-pedal", (0.08, 0.12, 0.02), (-0.05, 0.15, 0.05))
    gas.rotation_euler = (0.6, 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    gas.parent = parent
    
    # Brake pedal (left, larger)
    brake = create_box("brake-pedal", (0.10, 0.15, 0.02), (-0.05, -0.10, 0.05))
    brake.rotation_euler = (0.6, 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    brake.parent = parent
    
    return gas, brake

def create_gear_shifter(name, location):
    """Create a gear shifter"""
    # Base
    bpy.ops.mesh.primitive_cylinder_add(radius=0.025, depth=0.03, location=location)
    base = bpy.context.active_object
    
    # Shaft
    shaft_loc = (location[0], location[1], location[2] + 0.08)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.012, depth=0.13, location=shaft_loc)
    shaft = bpy.context.active_object
    
    # Knob
    knob_loc = (location[0], location[1], location[2] + 0.15)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.025, location=knob_loc)
    knob = bpy.context.active_object
    
    # Join
    bpy.ops.object.select_all(action='DESELECT')
    base.select_set(True)
    shaft.select_set(True)
    knob.select_set(True)
    bpy.context.view_layer.objects.active = base
    bpy.ops.object.join()
    
    base.name = name
    return base

def create_seat(name, location):
    """Create a bucket seat"""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    
    # Seat base (cushion)
    seat_w, seat_d, seat_h = 0.40, 0.40, 0.08
    sw, sd, sh = seat_w/2, seat_d/2, seat_h
    
    # Seat cushion vertices
    v1 = bm.verts.new((-sw, -sd, 0))
    v2 = bm.verts.new((sw, -sd, 0))
    v3 = bm.verts.new((sw, sd, 0))
    v4 = bm.verts.new((-sw, sd, 0))
    v5 = bm.verts.new((-sw, -sd, sh))
    v6 = bm.verts.new((sw, -sd, sh))
    v7 = bm.verts.new((sw, sd, sh))
    v8 = bm.verts.new((-sw, sd, sh))
    
    bm.verts.ensure_lookup_table()
    
    # Cushion faces
    bm.faces.new([v1, v2, v3, v4])  # Bottom
    bm.faces.new([v8, v7, v6, v5])  # Top
    bm.faces.new([v1, v5, v6, v2])  # Front
    bm.faces.new([v3, v7, v8, v4])  # Back
    bm.faces.new([v1, v4, v8, v5])  # Left
    bm.faces.new([v2, v6, v7, v3])  # Right
    
    # Backrest
    back_h = 0.50
    b1 = bm.verts.new((-sw, sd - 0.05, sh))
    b2 = bm.verts.new((sw, sd - 0.05, sh))
    b3 = bm.verts.new((sw, sd, sh))
    b4 = bm.verts.new((-sw, sd, sh))
    b5 = bm.verts.new((-sw * 0.9, sd - 0.08, sh + back_h))
    b6 = bm.verts.new((sw * 0.9, sd - 0.08, sh + back_h))
    b7 = bm.verts.new((sw * 0.9, sd - 0.02, sh + back_h))
    b8 = bm.verts.new((-sw * 0.9, sd - 0.02, sh + back_h))
    
    bm.verts.ensure_lookup_table()
    
    bm.faces.new([b1, b2, b6, b5])
    bm.faces.new([b3, b4, b8, b7])
    bm.faces.new([b2, b3, b7, b6])
    bm.faces.new([b4, b1, b5, b8])
    bm.faces.new([b5, b6, b7, b8])
    
    bm.to_mesh(mesh)
    bm.free()
    
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    
    return obj

def create_bezel_with_cutout(name, outer_w, outer_h, cutout_w, cutout_h, thickness=0.015):
    """Create a bezel panel with screen cutout"""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    
    hw, hh = outer_w/2, outer_h/2
    chw, chh = cutout_w/2, cutout_h/2
    t = thickness/2
    
    # Outer corners (front)
    v1 = bm.verts.new((-hw, -t, -hh))
    v2 = bm.verts.new((hw, -t, -hh))
    v3 = bm.verts.new((hw, -t, hh))
    v4 = bm.verts.new((-hw, -t, hh))
    
    # Cutout corners (front)
    v5 = bm.verts.new((-chw, -t, -chh))
    v6 = bm.verts.new((chw, -t, -chh))
    v7 = bm.verts.new((chw, -t, chh))
    v8 = bm.verts.new((-chw, -t, chh))
    
    # Back vertices
    v1b = bm.verts.new((-hw, t, -hh))
    v2b = bm.verts.new((hw, t, -hh))
    v3b = bm.verts.new((hw, t, hh))
    v4b = bm.verts.new((-hw, t, hh))
    v5b = bm.verts.new((-chw, t, -chh))
    v6b = bm.verts.new((chw, t, -chh))
    v7b = bm.verts.new((chw, t, chh))
    v8b = bm.verts.new((-chw, t, chh))
    
    bm.verts.ensure_lookup_table()
    
    # Front faces (with hole)
    bm.faces.new([v1, v2, v6, v5])
    bm.faces.new([v2, v3, v7, v6])
    bm.faces.new([v3, v4, v8, v7])
    bm.faces.new([v4, v1, v5, v8])
    
    # Back faces
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

def create_t_molding_driving():
    """Create T-molding for driving cabinet"""
    radius = 0.008
    
    # Path around front edges
    path = [
        (-0.20, -0.50, 0.50),   # Left front lower
        (-0.20, -0.50, 1.70),   # Left front upper
        (-0.15, -0.50, 1.95),   # Left top
        (-0.15, 0.50, 1.95),    # Right top
        (-0.20, 0.50, 1.70),    # Right front upper
        (-0.20, 0.50, 0.50),    # Right front lower
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

def create_driving_cabinet():
    """Create complete driving arcade cabinet"""
    clear_scene()
    
    print("Creating driving cabinet template...")
    
    # Create root
    bpy.ops.object.empty_add(type='PLAIN_AXES', location=(0, 0, 0))
    root = bpy.context.active_object
    root.name = "cabinet-root"
    
    # Side panels
    print("  Creating side panels...")
    left = create_side_panel_driving("left", is_right=False)
    left.parent = root
    
    right = create_side_panel_driving("right", is_right=True)
    right.parent = root
    
    # Back panel
    print("  Creating back panel...")
    back = create_box("back", (0.02, 0.98, 1.60), (-0.84, 0, 0.90))
    back.parent = root
    
    # Top panel
    print("  Creating top panel...")
    top = create_box("top", (0.70, 0.98, 0.02), (-0.47, 0, 1.94))
    top.parent = root
    
    # Bottom/floor panel
    print("  Creating bottom panel...")
    bottom = create_box("bottom", (0.85, 0.98, 0.02), (-0.42, 0, 0.01))
    bottom.parent = root
    
    # Dashboard panel (where gauges go)
    print("  Creating dashboard...")
    dashboard = create_box("dashboard", (0.25, 0.70, 0.02), (-0.27, 0, 0.72))
    dashboard.rotation_euler = (0.8, 0, 0)  # Angled toward player
    bpy.ops.object.transform_apply(rotation=True)
    dashboard.parent = root
    
    # Marquee
    print("  Creating marquee...")
    bpy.ops.mesh.primitive_plane_add(size=1, location=(-0.17, 0, 1.90))
    marquee = bpy.context.active_object
    marquee.name = "marquee"
    marquee.scale = (0.90, 0.12, 1)
    marquee.rotation_euler = (math.pi/2, -0.15, 0)
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    marquee.parent = root
    
    # Marquee box
    marquee_box = create_box("marquee-box", (0.12, 0.98, 0.15), (-0.19, 0, 1.87))
    marquee_box.parent = root
    
    # Bezel (wide screen for racing)
    print("  Creating bezel...")
    bezel = create_bezel_with_cutout("bezel", 0.90, 0.55, 0.75, 0.45, 0.02)
    bezel.location = (-0.32, 0, 1.30)
    bezel.rotation_euler = (0, -0.25, 0)  # Tilted back
    bpy.ops.object.transform_apply(rotation=True)
    bezel.parent = root
    
    # Screen
    print("  Creating screen...")
    bpy.ops.mesh.primitive_plane_add(size=1, location=(-0.31, 0, 1.30))
    screen = bpy.context.active_object
    screen.name = "screen"
    screen.scale = (0.72, 0.42, 1)
    screen.rotation_euler = (math.pi/2, -0.25, 0)
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    screen.parent = root
    
    # Screen mocks
    bpy.ops.mesh.primitive_cube_add(size=0.01, location=(-0.31, 0, 1.30))
    screen_mock_h = bpy.context.active_object
    screen_mock_h.name = "screen-mock-horizontal"
    screen_mock_h.scale = (0.01, 0.72, 0.42)
    bpy.ops.object.transform_apply(scale=True)
    screen_mock_h.parent = root
    
    bpy.ops.mesh.primitive_cube_add(size=0.01, location=(-0.31, 0, 1.30))
    screen_mock_v = bpy.context.active_object
    screen_mock_v.name = "screen-mock-vertical"
    screen_mock_v.scale = (0.01, 0.42, 0.72)
    bpy.ops.object.transform_apply(scale=True)
    screen_mock_v.parent = root
    
    # Steering wheel
    print("  Creating steering wheel...")
    wheel = create_steering_wheel("steering-wheel", (-0.15, 0, 0.85))
    wheel.parent = root
    
    # Steering column housing
    column = create_box("steering-column", (0.08, 0.10, 0.25), (-0.20, 0, 0.70))
    column.rotation_euler = (0.5, 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    column.parent = root
    
    # Pedals
    print("  Creating pedals...")
    create_pedals(root)
    
    # Gear shifter
    print("  Creating gear shifter...")
    shifter = create_gear_shifter("gear-shifter", (-0.25, 0.25, 0.55))
    shifter.parent = root
    
    # Seat
    print("  Creating seat...")
    seat = create_seat("seat", (-0.55, 0, 0.30))
    seat.parent = root
    
    # Coin door
    print("  Creating coin door...")
    coin_door = create_box("coin-door", (0.02, 0.15, 0.10), (-0.05, 0.30, 0.35))
    coin_door.parent = root
    
    # Speaker panel (in dashboard area)
    print("  Creating speaker panel...")
    speaker = create_box("speaker", (0.02, 0.30, 0.08), (-0.22, 0, 1.65))
    speaker.parent = root
    
    # Front kick panel (foot rest area)
    print("  Creating front kick panel...")
    front_kick = create_box("front-kick", (0.15, 0.60, 0.02), (-0.07, 0, 0.25))
    front_kick.rotation_euler = (1.2, 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    front_kick.parent = root
    
    # T-Molding
    print("  Creating T-molding...")
    t_molding = create_t_molding_driving()
    if t_molding:
        t_molding.parent = root
    
    print("Driving cabinet creation complete!")
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
        output_path = "/tmp/driving_cabinet_template.glb"
    else:
        output_path = argv[0]
    
    create_driving_cabinet()
    export_glb(output_path)

if __name__ == "__main__":
    main()
