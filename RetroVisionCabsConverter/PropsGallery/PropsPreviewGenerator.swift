//
//  PropsPreviewGenerator.swift
//  RetroVisionCabsConverter
//
//  Generates previews for non-cabinet props using Blender
//

import Foundation
import AppKit

// MARK: - Props Preview Generator

class PropsPreviewGenerator {
    static let shared = PropsPreviewGenerator()
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let logger = PreviewLogger.shared
    
    init() {
        let paths = RetroVisionPaths.load()
        cacheDirectory = URL(fileURLWithPath: paths.propPreviewCacheDir)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Public API
    
    /// Generate preview for a prop
    func generatePreview(for prop: DiscoveredProp) async -> NSImage? {
        logger.startSession(for: "Prop: \(prop.displayName)")
        
        let cacheKey = "\(prop.id)_prop_preview"
        
        // Check cache
        if let cached = getCachedPreview(cacheKey) {
            logger.log(.info, "Using cached preview")
            logger.endSession(success: true)
            return cached
        }
        
        guard let glbFile = prop.glbFile else {
            logger.log(.error, "No GLB file for prop")
            logger.endSession(success: false)
            return nil
        }
        
        logger.log(.info, "Generating preview for prop", details: glbFile.path)
        
        // Determine assets folder
        let assetsFolder = prop.sourcePath
        
        // Generate preview
        let outputPath = cacheDirectory.appendingPathComponent("\(cacheKey).png")
        
        let success = await renderPropPreview(
            glbFile: glbFile,
            assetsFolder: assetsFolder,
            meshMappings: prop.meshMappings,
            propType: prop.propType,
            outputPath: outputPath
        )
        
        if success, let image = NSImage(contentsOf: outputPath) {
            logger.log(.success, "Preview generated", details: "Size: \(Int(image.size.width))x\(Int(image.size.height))")
            logger.endSession(success: true)
            return image
        }
        
        logger.log(.error, "Failed to generate preview")
        logger.endSession(success: false)
        return nil
    }
    
    /// Generate previews for multiple props
    func generatePreviews(for props: [DiscoveredProp], progress: @escaping (Double, String) -> Void) async -> [String: NSImage] {
        var results: [String: NSImage] = [:]
        let total = Double(props.count)
        
        for (index, prop) in props.enumerated() {
            progress(Double(index) / total, "Generating preview: \(prop.displayName)")
            
            if let image = await generatePreview(for: prop) {
                results[prop.id] = image
            }
        }
        
        progress(1.0, "Preview generation complete")
        return results
    }
    
    // MARK: - Cache Management
    
    func getCachedPreview(_ cacheKey: String) -> NSImage? {
        let cachePath = cacheDirectory.appendingPathComponent("\(cacheKey).png")
        if fileManager.fileExists(atPath: cachePath.path) {
            return NSImage(contentsOf: cachePath)
        }
        return nil
    }
    
    func clearCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Rendering
    
    private func renderPropPreview(
        glbFile: URL,
        assetsFolder: URL,
        meshMappings: [String: String],
        propType: PropType,
        outputPath: URL
    ) async -> Bool {
        return await withCheckedContinuation { continuation in
            // Build texture assignments
            var textureAssignments: [[String: String]] = []
            for (meshName, assetFile) in meshMappings {
                let assetPath = assetsFolder.appendingPathComponent(assetFile).path
                if fileManager.fileExists(atPath: assetPath) {
                    textureAssignments.append([
                        "mesh": meshName,
                        "texture": assetPath
                    ])
                }
            }
            
            let texturesJSON = (try? JSONEncoder().encode(textureAssignments))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            
            // Adjust camera based on prop type
            let cameraDistance: String
            let cameraAngle: String
            
            switch propType {
            case .cutout, .wall:
                // Front-on view for flat items
                cameraDistance = "size * 1.5"
                cameraAngle = "(center[0], center[1] - distance, center[2] + distance * 0.2)"
            case .stage, .floor:
                // Elevated angle for floor items
                cameraDistance = "size * 2.5"
                cameraAngle = "(center[0] + distance * 0.5, center[1] - distance * 0.5, center[2] + distance * 0.8)"
            default:
                // Standard 3/4 view
                cameraDistance = "size * 2.2"
                cameraAngle = "(center[0] + distance * 0.7, center[1] - distance * 0.7, center[2] + distance * 0.5)"
            }
            
            let script = """
import bpy
import json
import math
import mathutils
import os

print("PROP_PREVIEW_LOG: Starting prop preview generation")
print(f"PROP_PREVIEW_LOG: GLB: \(glbFile.path)")

# Clear scene
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

# Import GLB
print("PROP_PREVIEW_LOG: Importing GLB...")
try:
    bpy.ops.import_scene.gltf(filepath='\(glbFile.path)')
    print("PROP_PREVIEW_LOG: Import successful")
except Exception as e:
    print(f"PROP_PREVIEW_LOG_ERROR: Import failed: {e}")

# List meshes
mesh_count = 0
for obj in bpy.data.objects:
    if obj.type == 'MESH':
        mesh_count += 1
        print(f"PROP_PREVIEW_LOG: Mesh: {obj.name}")
print(f"PROP_PREVIEW_LOG: Total meshes: {mesh_count}")

# Texture assignments
textures = json.loads('''\(texturesJSON)''')
print(f"PROP_PREVIEW_LOG: Texture assignments: {len(textures)}")

def find_mesh(name):
    name_lower = name.lower()
    for obj in bpy.data.objects:
        if obj.type == 'MESH':
            if obj.name.lower() == name_lower or name_lower in obj.name.lower():
                return obj
    return None

def apply_texture(obj, texture_path):
    if not obj or not texture_path:
        return False
    if not os.path.exists(texture_path):
        return False
    
    mat = bpy.data.materials.new(name=f"mat_{obj.name}")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    
    bsdf = nodes.get("Principled BSDF")
    if not bsdf:
        return False
    
    tex_node = nodes.new('ShaderNodeTexImage')
    try:
        tex_node.image = bpy.data.images.load(texture_path)
        links.new(tex_node.outputs['Color'], bsdf.inputs['Base Color'])
    except Exception as e:
        print(f"PROP_PREVIEW_LOG_ERROR: Texture load failed: {e}")
        return False
    
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    return True

# Apply textures
applied = 0
for assignment in textures:
    mesh_name = assignment.get('mesh', '')
    texture_path = assignment.get('texture', '')
    obj = find_mesh(mesh_name)
    if obj and apply_texture(obj, texture_path):
        applied += 1
        print(f"PROP_PREVIEW_LOG: Applied texture to {obj.name}")

print(f"PROP_PREVIEW_LOG: Textures applied: {applied}")

# Default material for untextured meshes - use a subtle gray
default_mat = bpy.data.materials.new(name="default_prop")
default_mat.use_nodes = True
default_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.4, 0.4, 0.4, 1)
default_mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.7

textured_meshes = set(a.get('mesh', '').lower() for a in textures)
for obj in bpy.data.objects:
    if obj.type == 'MESH':
        if obj.name.lower() not in textured_meshes:
            if not obj.data.materials or len(obj.data.materials) == 0:
                obj.data.materials.append(default_mat)

# Calculate bounding box
min_coords = [float('inf')] * 3
max_coords = [float('-inf')] * 3
for obj in bpy.data.objects:
    if obj.type == 'MESH':
        for v in obj.bound_box:
            world_v = obj.matrix_world @ mathutils.Vector(v)
            for i in range(3):
                min_coords[i] = min(min_coords[i], world_v[i])
                max_coords[i] = max(max_coords[i], world_v[i])

center = [(min_coords[i] + max_coords[i]) / 2 for i in range(3)]
size = max(max_coords[i] - min_coords[i] for i in range(3))
print(f"PROP_PREVIEW_LOG: Bounding box size: {size}")

# Setup camera
cam = bpy.data.cameras.new('PropCam')
cam.lens = 50
cam_obj = bpy.data.objects.new('PropCam', cam)
bpy.context.scene.collection.objects.link(cam_obj)
bpy.context.scene.camera = cam_obj

distance = \(cameraDistance)
cam_obj.location = \(cameraAngle)

# Point at center
direction = mathutils.Vector(center) - cam_obj.location
rot_quat = direction.to_track_quat('-Z', 'Y')
cam_obj.rotation_euler = rot_quat.to_euler()

# Lighting - 3 point setup
# Key light
sun = bpy.data.lights.new('Key', 'SUN')
sun_obj = bpy.data.objects.new('Key', sun)
bpy.context.scene.collection.objects.link(sun_obj)
sun_obj.rotation_euler = (math.radians(45), math.radians(30), 0)
sun.energy = 4

# Fill light
fill = bpy.data.lights.new('Fill', 'AREA')
fill_obj = bpy.data.objects.new('Fill', fill)
bpy.context.scene.collection.objects.link(fill_obj)
fill_obj.location = (center[0] - distance, center[1], center[2] + distance * 0.3)
fill.energy = 100

# Back/rim light
back = bpy.data.lights.new('Back', 'AREA')
back_obj = bpy.data.objects.new('Back', back)
bpy.context.scene.collection.objects.link(back_obj)
back_obj.location = (center[0], center[1] + distance, center[2] + distance * 0.5)
back.energy = 60

# World background - gradient
bpy.context.scene.world = bpy.data.worlds.new('PropWorld')
bpy.context.scene.world.use_nodes = True
bg = bpy.context.scene.world.node_tree.nodes['Background']
bg.inputs['Color'].default_value = (0.15, 0.17, 0.22, 1)

# Render settings
bpy.context.scene.render.engine = 'BLENDER_EEVEE'
bpy.context.scene.render.resolution_x = 512
bpy.context.scene.render.resolution_y = 512
bpy.context.scene.render.film_transparent = False
bpy.context.scene.render.filepath = '\(outputPath.path)'

# Render
print("PROP_PREVIEW_LOG: Rendering...")
bpy.ops.render.render(write_still=True)

if os.path.exists('\(outputPath.path)'):
    print("PROP_PREVIEW_LOG: Preview saved successfully")
    print("PROP_PREVIEW_GENERATED_SUCCESS")
else:
    print("PROP_PREVIEW_LOG_ERROR: Output file not created")
"""
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/Applications/Blender.app/Contents/MacOS/Blender")
            process.arguments = ["-b", "--factory-startup", "--python-expr", script]
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let outputString = String(data: outputData, encoding: .utf8) ?? ""
                
                // Log relevant output
                let relevantLines = outputString.components(separatedBy: "\n").filter { line in
                    line.contains("PROP_PREVIEW_LOG")
                }
                if !relevantLines.isEmpty {
                    self.logger.log(.debug, "Blender output:", details: relevantLines.joined(separator: "\n"))
                }
                
                let success = process.terminationStatus == 0 &&
                              self.fileManager.fileExists(atPath: outputPath.path)
                
                if success {
                    self.logger.log(.success, "Blender render completed")
                } else {
                    self.logger.log(.error, "Blender render failed", details: "Exit: \(process.terminationStatus)")
                }
                
                continuation.resume(returning: success)
            } catch {
                self.logger.log(.error, "Failed to run Blender", details: error.localizedDescription)
                continuation.resume(returning: false)
            }
        }
    }
    
    // MARK: - Video Thumbnail
    
    /// Generate a thumbnail from a video file
    func generateVideoThumbnail(from videoURL: URL, at time: Double = 1.0) async -> NSImage? {
        return await withCheckedContinuation { continuation in
            let script = """
import bpy
import os

# Clear scene
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

# Try to get a frame from the video using ffmpeg
import subprocess

output_path = '\(cacheDirectory.path)/video_thumb_\(videoURL.deletingPathExtension().lastPathComponent).png'

try:
    result = subprocess.run([
        '/opt/homebrew/bin/ffmpeg', '-y',
        '-ss', '\(time)',
        '-i', '\(videoURL.path)',
        '-vframes', '1',
        '-vf', 'scale=256:-1',
        output_path
    ], capture_output=True, timeout=10)
    
    if os.path.exists(output_path):
        print(f"VIDEO_THUMB_SUCCESS:{output_path}")
    else:
        print("VIDEO_THUMB_FAILED")
except Exception as e:
    print(f"VIDEO_THUMB_ERROR:{e}")
"""
            
            // Use Python directly for ffmpeg
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = ["-c", """
import subprocess
import os

output_path = '\(cacheDirectory.path)/video_thumb_\(videoURL.deletingPathExtension().lastPathComponent).png'

try:
    result = subprocess.run([
        '/opt/homebrew/bin/ffmpeg', '-y',
        '-ss', '\(time)',
        '-i', '\(videoURL.path)',
        '-vframes', '1',
        '-vf', 'scale=256:-1',
        output_path
    ], capture_output=True, timeout=10)
    
    if os.path.exists(output_path):
        print(f"SUCCESS:{output_path}")
except Exception as e:
    print(f"ERROR:{e}")
"""]
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = FileHandle.nullDevice
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let outputString = String(data: outputData, encoding: .utf8) ?? ""
                
                if outputString.contains("SUCCESS:"),
                   let pathStart = outputString.range(of: "SUCCESS:")?.upperBound {
                    let thumbPath = String(outputString[pathStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if let image = NSImage(contentsOfFile: thumbPath) {
                        continuation.resume(returning: image)
                        return
                    }
                }
                
                continuation.resume(returning: nil)
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
