#!/usr/bin/env python3
"""
Create a complete arcade cabinet GLB template with all required parts.
Run with: blender --background --python create_cabinet_template.py -- output.glb

Parts included:
- left, right (side panels)
- front-kick (front kick plate)
- back (back panel)
- top (top panel)  
- bottom (bottom panel)
- marquee (marquee display area)
- marquee-box (marquee housing)
- bezel (monitor bezel with screen cutout)
- cp-shell (control panel shell/housing)
- joystick (control panel overlay)
- coin-door (coin door area)
- speaker (speaker panel)
- t-molding (edge trim for LED effects)
- screen (screen surface for video playback)
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
    
    # Clear orphan data
    for block in bpy.data.meshes:
        if block.users == 0:
            bpy.data.meshes.remove(block)

def create_box(name, location, dimensions, parent=None):
    """Create a box mesh with given dimensions"""
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (dimensions[0], dimensions[1], dimensions[2])
    bpy.ops.object.transform_apply(scale=True)
    if parent:
        obj.parent = parent
    return obj

def create_side_panel(name, is_right=False):
    """Create arcade cabinet side panel with classic profile"""
    verts = []
    
    # Classic arcade cabinet side profile (in meters, scaled up)
    # Starting from bottom-front, going clockwise
    profile_2d = [
        (0.0, 0.0),      # Bottom front
        (0.0, 0.15),     # Front kick bottom
        (-0.05, 0.20),   # Kick angle
        (-0.05, 0.70),   # Control panel bottom
        (-0.15, 0.85),   # Control panel angle
        (-0.15, 1.10),   # Below screen
        (-0.10, 1.20),   # Screen angle start
        (-0.05, 1.50),   # Screen area
        (-0.08, 1.65),   # Above screen
        (-0.10, 1.75),   # Marquee bottom
        (-0.10, 1.90),   # Marquee top
        (-0.05, 1.95),   # Top front
        (-0.35, 1.95),   # Top back
        (-0.40, 1.85),   # Back top angle
        (-0.40, 0.0),    # Back bottom
    ]
    
    # Mirror for right side
    if is_right:
        profile_2d = [(x, y) for x, y in profile_2d]
    
    thickness = 0.02  # Panel thickness
    
    # Create mesh
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    
    # Create front face vertices
    front_verts = []
    for x, z in profile_2d:
        v = bm.verts.new((x, thickness/2 if is_right else -thickness/2, z))
        front_verts.append(v)
    
    # Create back face vertices
    back_verts = []
    for x, z in profile_2d:
        v = bm.verts.new((x, -thickness/2 if is_right else thickness/2, z))
        back_verts.append(v)
    
    bm.verts.ensure_lookup_table()
    
    # Create front and back faces
    bm.faces.new(front_verts)
    bm.faces.new(list(reversed(back_verts)))
    
    # Create side faces connecting front and back
    n = len(profile_2d)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([front_verts[i], front_verts[j], back_verts[j], back_verts[i]])
    
    bm.to_mesh(mesh)
    bm.free()
    
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    
    # Position
    y_offset = 0.25 if is_right else -0.25
    obj.location = (0, y_offset, 0)
    
    return obj

def create_flat_panel(name, width, height, thickness, location, rotation=(0,0,0)):
    """Create a flat rectangular panel"""
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (thickness, width, height)
    obj.rotation_euler = rotation
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    return obj

def create_t_molding():
    """Create T-molding edge trim around cabinet using simple box strips"""
    # T-molding dimensions
    width = 0.012  # Width of T-molding strip
    depth = 0.008  # Depth/thickness
    
    # Create mesh using bmesh for precise control
    mesh = bpy.data.meshes.new("t-molding")
    bm = bmesh.new()
    
    def add_strip(p1, p2, w, d):
        """Add a rectangular strip between two points"""
        start = Vector(p1)
        end = Vector(p2)
        direction = end - start
        length = direction.length
        if length < 0.001:
            return
        
        direction.normalize()
        
        # Calculate perpendicular vectors
        # For vertical strips (along Z), perp should be in X-Y plane
        if abs(direction.z) > 0.9:
            perp1 = Vector((1, 0, 0)) * (w / 2)
            perp2 = Vector((0, 1, 0)) * (d / 2)
        # For horizontal strips along Y
        elif abs(direction.y) > 0.9:
            perp1 = Vector((1, 0, 0)) * (d / 2)
            perp2 = Vector((0, 0, 1)) * (w / 2)
        # For horizontal strips along X
        else:
            perp1 = Vector((0, 1, 0)) * (d / 2)
            perp2 = Vector((0, 0, 1)) * (w / 2)
        
        # Create 8 vertices for a box
        v = []
        for point in [start, end]:
            v.append(bm.verts.new(point - perp1 - perp2))
            v.append(bm.verts.new(point + perp1 - perp2))
            v.append(bm.verts.new(point + perp1 + perp2))
            v.append(bm.verts.new(point - perp1 + perp2))
        
        bm.verts.ensure_lookup_table()
        
        # Create faces
        # Start cap
        bm.faces.new([v[0], v[1], v[2], v[3]])
        # End cap
        bm.faces.new([v[7], v[6], v[5], v[4]])
        # Sides
        bm.faces.new([v[0], v[4], v[5], v[1]])
        bm.faces.new([v[1], v[5], v[6], v[2]])
        bm.faces.new([v[2], v[6], v[7], v[3]])
        bm.faces.new([v[3], v[7], v[4], v[0]])
    
    # T-molding paths - front edges of cabinet
    # Left side vertical (bottom to top)
    add_strip((-0.04, -0.26, 0.02), (-0.04, -0.26, 1.90), width, depth)
    # Right side vertical
    add_strip((-0.04, 0.26, 0.02), (-0.04, 0.26, 1.90), width, depth)
    # Bottom front horizontal
    add_strip((-0.04, -0.26, 0.02), (-0.04, 0.26, 0.02), width, depth)
    # Top front horizontal (at marquee level)
    add_strip((-0.08, -0.26, 1.90), (-0.08, 0.26, 1.90), width, depth)
    # Control panel front edge
    add_strip((-0.04, -0.26, 0.70), (-0.04, 0.26, 0.70), width, depth)
    
    bm.to_mesh(mesh)
    bm.free()
    
    obj = bpy.data.objects.new("t-molding", mesh)
    bpy.context.collection.objects.link(obj)
    
    return obj

def create_bezel_with_cutout():
    """Create monitor bezel with screen cutout"""
    # Bezel outer dimensions
    outer_width = 0.45
    outer_height = 0.40
    thickness = 0.01
    
    # Screen cutout dimensions
    cutout_width = 0.35
    cutout_height = 0.28
    
    mesh = bpy.data.meshes.new("bezel")
    bm = bmesh.new()
    
    # Create outer rectangle vertices (front)
    hw, hh = outer_width/2, outer_height/2
    chw, chh = cutout_width/2, cutout_height/2
    
    # Outer corners (front)
    v1 = bm.verts.new((-hw, -thickness/2, -hh))
    v2 = bm.verts.new((hw, -thickness/2, -hh))
    v3 = bm.verts.new((hw, -thickness/2, hh))
    v4 = bm.verts.new((-hw, -thickness/2, hh))
    
    # Cutout corners (front)
    v5 = bm.verts.new((-chw, -thickness/2, -chh))
    v6 = bm.verts.new((chw, -thickness/2, -chh))
    v7 = bm.verts.new((chw, -thickness/2, chh))
    v8 = bm.verts.new((-chw, -thickness/2, chh))
    
    # Outer corners (back)
    v1b = bm.verts.new((-hw, thickness/2, -hh))
    v2b = bm.verts.new((hw, thickness/2, -hh))
    v3b = bm.verts.new((hw, thickness/2, hh))
    v4b = bm.verts.new((-hw, thickness/2, hh))
    
    # Cutout corners (back)
    v5b = bm.verts.new((-chw, thickness/2, -chh))
    v6b = bm.verts.new((chw, thickness/2, -chh))
    v7b = bm.verts.new((chw, thickness/2, chh))
    v8b = bm.verts.new((-chw, thickness/2, chh))
    
    bm.verts.ensure_lookup_table()
    
    # Front face (with hole) - create as 4 quads around the hole
    bm.faces.new([v1, v2, v6, v5])  # Bottom
    bm.faces.new([v2, v3, v7, v6])  # Right
    bm.faces.new([v3, v4, v8, v7])  # Top
    bm.faces.new([v4, v1, v5, v8])  # Left
    
    # Back face (with hole)
    bm.faces.new([v5b, v6b, v2b, v1b])
    bm.faces.new([v6b, v7b, v3b, v2b])
    bm.faces.new([v7b, v8b, v4b, v3b])
    bm.faces.new([v8b, v5b, v1b, v4b])
    
    # Outer edges
    bm.faces.new([v1, v1b, v2b, v2])
    bm.faces.new([v2, v2b, v3b, v3])
    bm.faces.new([v3, v3b, v4b, v4])
    bm.faces.new([v4, v4b, v1b, v1])
    
    # Inner edges (cutout)
    bm.faces.new([v5, v6, v6b, v5b])
    bm.faces.new([v6, v7, v7b, v6b])
    bm.faces.new([v7, v8, v8b, v7b])
    bm.faces.new([v8, v5, v5b, v8b])
    
    bm.to_mesh(mesh)
    bm.free()
    
    obj = bpy.data.objects.new("bezel", mesh)
    bpy.context.collection.objects.link(obj)
    
    # Position at screen location
    obj.location = (-0.07, 0, 1.35)
    obj.rotation_euler = (0, -0.25, 0)  # Tilt back slightly
    
    return obj

def create_screen():
    """Create screen surface for video playback"""
    bpy.ops.mesh.primitive_plane_add(size=1, location=(-0.06, 0, 1.35))
    obj = bpy.context.active_object
    obj.name = "screen"
    obj.scale = (0.32, 0.26, 1)
    obj.rotation_euler = (math.pi/2, -0.25, 0)  # Face forward, tilted
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    return obj

def create_cabinet():
    """Create complete arcade cabinet with all parts"""
    clear_scene()
    
    print("Creating arcade cabinet template...")
    
    # Create parent empty for organization
    bpy.ops.object.empty_add(type='PLAIN_AXES', location=(0, 0, 0))
    root = bpy.context.active_object
    root.name = "cabinet-root"
    
    # Side panels
    print("  Creating side panels...")
    left = create_side_panel("left", is_right=False)
    left.parent = root
    
    right = create_side_panel("right", is_right=True)
    right.parent = root
    
    # Back panel
    print("  Creating back panel...")
    back = create_flat_panel("back", 0.50, 1.85, 0.02, (-0.39, 0, 0.925))
    back.parent = root
    
    # Top panel - create as horizontal panel at top of cabinet
    print("  Creating top panel...")
    bpy.ops.mesh.primitive_cube_add(size=1, location=(-0.22, 0, 1.94))
    top = bpy.context.active_object
    top.name = "top"
    # For a horizontal panel: X=depth, Y=width, Z=thickness
    top.scale = (0.30, 0.50, 0.02)
    bpy.ops.object.transform_apply(scale=True)
    top.parent = root
    
    # Bottom panel - create as horizontal panel at bottom of cabinet
    print("  Creating bottom panel...")
    bpy.ops.mesh.primitive_cube_add(size=1, location=(-0.20, 0, 0.01))
    bottom = bpy.context.active_object
    bottom.name = "bottom"
    # For a horizontal panel: X=depth, Y=width, Z=thickness
    bottom.scale = (0.40, 0.50, 0.02)
    bpy.ops.object.transform_apply(scale=True)
    bottom.parent = root
    
    # Front kick plate
    print("  Creating front kick plate...")
    front_kick = create_flat_panel("front-kick", 0.50, 0.18, 0.02, (-0.04, 0, 0.09))
    front_kick.parent = root
    
    # Marquee box (housing)
    print("  Creating marquee box...")
    marquee_box = create_flat_panel("marquee-box", 0.50, 0.12, 0.10, (-0.12, 0, 1.82))
    marquee_box.parent = root
    
    # Marquee (display panel)
    print("  Creating marquee...")
    bpy.ops.mesh.primitive_plane_add(size=1, location=(-0.06, 0, 1.82))
    marquee = bpy.context.active_object
    marquee.name = "marquee"
    marquee.scale = (0.48, 0.10, 1)
    marquee.rotation_euler = (math.pi/2, -0.1, 0)
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    marquee.parent = root
    
    # Bezel (with screen cutout)
    print("  Creating bezel...")
    bezel = create_bezel_with_cutout()
    bezel.parent = root
    
    # Screen
    print("  Creating screen...")
    screen = create_screen()
    screen.parent = root
    
    # Control panel shell - angled wedge for control surface
    print("  Creating control panel shell...")
    mesh = bpy.data.meshes.new("cp-shell")
    bm_cp = bmesh.new()
    
    # Create angled control panel as a wedge
    # Front edge is higher, back edge is lower (tilted toward player)
    cp_width = 0.50  # Width (Y axis)
    cp_depth = 0.18  # Depth (X axis) 
    cp_front_z = 0.90  # Front edge height
    cp_back_z = 0.75   # Back edge height
    cp_thickness = 0.03
    
    hw = cp_width / 2
    
    # Top surface vertices (angled)
    v1 = bm_cp.verts.new((-0.04, -hw, cp_front_z))  # Front left
    v2 = bm_cp.verts.new((-0.04, hw, cp_front_z))   # Front right
    v3 = bm_cp.verts.new((-0.04 - cp_depth, hw, cp_back_z))   # Back right
    v4 = bm_cp.verts.new((-0.04 - cp_depth, -hw, cp_back_z))  # Back left
    
    # Bottom surface vertices
    v5 = bm_cp.verts.new((-0.04, -hw, cp_front_z - cp_thickness))
    v6 = bm_cp.verts.new((-0.04, hw, cp_front_z - cp_thickness))
    v7 = bm_cp.verts.new((-0.04 - cp_depth, hw, cp_back_z - cp_thickness))
    v8 = bm_cp.verts.new((-0.04 - cp_depth, -hw, cp_back_z - cp_thickness))
    
    bm_cp.verts.ensure_lookup_table()
    
    # Faces
    bm_cp.faces.new([v1, v2, v3, v4])  # Top
    bm_cp.faces.new([v8, v7, v6, v5])  # Bottom
    bm_cp.faces.new([v1, v5, v6, v2])  # Front
    bm_cp.faces.new([v3, v7, v8, v4])  # Back
    bm_cp.faces.new([v1, v4, v8, v5])  # Left
    bm_cp.faces.new([v2, v6, v7, v3])  # Right
    
    bm_cp.to_mesh(mesh)
    bm_cp.free()
    
    cp_shell = bpy.data.objects.new("cp-shell", mesh)
    bpy.context.collection.objects.link(cp_shell)
    cp_shell.parent = root
    
    # Control panel / joystick overlay
    print("  Creating control panel overlay...")
    bpy.ops.mesh.primitive_plane_add(size=1, location=(-0.08, 0, 0.85))
    joystick = bpy.context.active_object
    joystick.name = "joystick"
    joystick.scale = (0.48, 0.18, 1)
    joystick.rotation_euler = (math.pi/2 + 0.3, 0, 0)
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    joystick.parent = root
    
    # Coin door
    print("  Creating coin door...")
    coin_door = create_flat_panel("coin-door", 0.20, 0.15, 0.02, (-0.04, 0, 0.35))
    coin_door.parent = root
    
    # Speaker panel
    print("  Creating speaker panel...")
    speaker = create_flat_panel("speaker", 0.50, 0.08, 0.02, (-0.04, 0, 0.55))
    speaker.parent = root
    
    # T-Molding
    print("  Creating T-molding...")
    t_molding = create_t_molding()
    if t_molding:
        t_molding.parent = root
    
    # Create screen mock objects for orientation detection
    print("  Creating screen mocks...")
    
    # Vertical screen mock
    bpy.ops.mesh.primitive_cube_add(size=0.01, location=(-0.06, 0, 1.35))
    screen_mock_v = bpy.context.active_object
    screen_mock_v.name = "screen-mock-vertical"
    screen_mock_v.scale = (0.01, 0.26, 0.32)
    bpy.ops.object.transform_apply(scale=True)
    screen_mock_v.parent = root
    
    # Horizontal screen mock  
    bpy.ops.mesh.primitive_cube_add(size=0.01, location=(-0.06, 0, 1.35))
    screen_mock_h = bpy.context.active_object
    screen_mock_h.name = "screen-mock-horizontal"
    screen_mock_h.scale = (0.01, 0.32, 0.26)
    bpy.ops.object.transform_apply(scale=True)
    screen_mock_h.parent = root
    
    print("Cabinet creation complete!")
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
    # Get output path from command line
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []
    
    if len(argv) < 1:
        output_path = "/tmp/arcade_cabinet_template.glb"
    else:
        output_path = argv[0]
    
    # Create cabinet
    create_cabinet()
    
    # Export
    export_glb(output_path)

if __name__ == "__main__":
    main()
