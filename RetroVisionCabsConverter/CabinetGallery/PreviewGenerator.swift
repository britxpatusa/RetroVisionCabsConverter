import Foundation
import AppKit

// MARK: - Preview Log Entry

struct PreviewLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String
    let details: String?
    
    enum LogLevel: String {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
        case success = "OK"
        case debug = "DEBUG"
    }
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

// MARK: - Preview Logger

class PreviewLogger: ObservableObject {
    static let shared = PreviewLogger()
    
    @Published var entries: [PreviewLogEntry] = []
    @Published var isActive = false
    
    private let logFile: URL
    private let fileManager = FileManager.default
    
    init() {
        let paths = RetroVisionPaths.load()
        logFile = URL(fileURLWithPath: paths.previewLogFile)
    }
    
    func startSession(for cabinetName: String) {
        entries.removeAll()
        isActive = true
        
        // Append separator to existing log (don't overwrite)
        let header = """
        
        =============================================
        Preview Generation Log
        Cabinet: \(cabinetName)
        Started: \(Date())
        =============================================
        
        """
        
        // Append to existing log file or create new one
        if fileManager.fileExists(atPath: logFile.path) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                if let data = header.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            }
        } else {
            try? header.write(to: logFile, atomically: true, encoding: .utf8)
        }
        
        log(.info, "=== Session Started ===")
        log(.info, "Cabinet: \(cabinetName)")
    }
    
    func log(_ level: PreviewLogEntry.LogLevel, _ message: String, details: String? = nil) {
        let entry = PreviewLogEntry(timestamp: Date(), level: level, message: message, details: details)
        
        DispatchQueue.main.async {
            self.entries.append(entry)
        }
        
        // Also write to file
        let fileEntry = "[\(entry.formattedTime)] [\(level.rawValue)] \(message)\(details.map { "\n    Details: \($0)" } ?? "")\n"
        if let data = fileEntry.data(using: .utf8), let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
        
        // Also print to console
        print("[\(level.rawValue)] \(message)")
        if let details = details {
            print("    \(details)")
        }
    }
    
    func endSession(success: Bool) {
        if success {
            log(.success, "=== Preview Generation Completed Successfully ===")
        } else {
            log(.error, "=== Preview Generation Failed ===")
        }
        isActive = false
    }
    
    func getLogFileURL() -> URL {
        return logFile
    }
    
    func clearLog() {
        entries.removeAll()
        try? "".write(to: logFile, atomically: true, encoding: .utf8)
        log(.info, "Log cleared at \(Date())")
    }
    
    /// Get last N lines from log file for display
    func getRecentLogs(lines: Int = 50) -> String {
        guard let content = try? String(contentsOf: logFile, encoding: .utf8) else {
            return "No log file found"
        }
        let allLines = content.components(separatedBy: "\n")
        let recentLines = allLines.suffix(lines)
        return recentLines.joined(separator: "\n")
    }
}

// MARK: - Preview Generator

/// Generates textured cabinet previews using Blender
class PreviewGenerator {
    
    static let shared = PreviewGenerator()
    
    private let cacheDirectory: URL
    private let fileManager = FileManager.default
    private let logger = PreviewLogger.shared
    
    init() {
        let paths = RetroVisionPaths.load()
        cacheDirectory = URL(fileURLWithPath: paths.previewCacheDir)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Public API
    
    /// Generate preview for a discovered cabinet
    /// Uses the cabinet's own GLB file (not template) with its artwork
    func generatePreview(for cabinet: DiscoveredCabinet, templateGLB: URL) async -> NSImage? {
        logger.startSession(for: cabinet.displayName)
        
        let cacheKey = "\(cabinet.id)_preview"
        logger.log(.debug, "Cache key: \(cacheKey)")
        
        // Check cache
        if let cached = getCachedPreview(cacheKey) {
            logger.log(.info, "Using cached preview")
            logger.endSession(success: true)
            return cached
        }
        logger.log(.info, "No cached preview found, generating new one")
        
        // Determine source folder for assets
        let assetsFolder: URL
        let paths = RetroVisionPaths.load()
        if cabinet.sourceType == .zip {
            // For ZIPs, use the extracted temp folder
            assetsFolder = URL(fileURLWithPath: paths.galleryExtractDir)
                .appendingPathComponent(cabinet.name)
            logger.log(.info, "Source type: ZIP", details: "Extract folder: \(assetsFolder.path)")
        } else {
            assetsFolder = cabinet.sourcePath
            logger.log(.info, "Source type: Folder", details: assetsFolder.path)
        }
        
        // Check if assets folder exists
        if !fileManager.fileExists(atPath: assetsFolder.path) {
            logger.log(.error, "Assets folder does not exist!", details: assetsFolder.path)
        } else {
            // List contents
            if let contents = try? fileManager.contentsOfDirectory(atPath: assetsFolder.path) {
                logger.log(.debug, "Assets folder contents (\(contents.count) items):", details: contents.joined(separator: ", "))
            }
        }
        
        // Use the cabinet's own GLB file if available, otherwise use template
        let glbToUse: URL
        if let cabinetGLB = cabinet.glbFile, fileManager.fileExists(atPath: cabinetGLB.path) {
            glbToUse = cabinetGLB
            logger.log(.info, "Using cabinet's own GLB file", details: cabinetGLB.path)
        } else {
            glbToUse = templateGLB
            logger.log(.warning, "Cabinet GLB not found, using template", details: templateGLB.path)
        }
        
        // Verify GLB exists
        if !fileManager.fileExists(atPath: glbToUse.path) {
            logger.log(.error, "GLB file does not exist!", details: glbToUse.path)
            logger.endSession(success: false)
            return nil
        }
        
        // Log mesh mappings
        logger.log(.info, "Mesh mappings (\(cabinet.meshMappings.count) entries):")
        for (mesh, asset) in cabinet.meshMappings {
            let assetPath = assetsFolder.appendingPathComponent(asset).path
            let exists = fileManager.fileExists(atPath: assetPath)
            logger.log(exists ? .debug : .warning, "  \(mesh) → \(asset)", details: exists ? "Found" : "MISSING: \(assetPath)")
        }
        
        // Generate preview
        let outputPath = cacheDirectory.appendingPathComponent("\(cacheKey).png")
        logger.log(.info, "Output path: \(outputPath.path)")
        
        let success = await renderPreview(
            glbFile: glbToUse,
            assetsFolder: assetsFolder,
            meshMappings: cabinet.meshMappings,
            outputPath: outputPath
        )
        
        if success, let image = NSImage(contentsOf: outputPath) {
            logger.log(.success, "Preview generated successfully", details: "Size: \(Int(image.size.width))x\(Int(image.size.height))")
            logger.endSession(success: true)
            return image
        }
        
        logger.log(.error, "Failed to generate preview or load output image")
        logger.endSession(success: false)
        return nil
    }
    
    /// Generate previews for multiple cabinets
    func generatePreviews(
        for cabinets: [DiscoveredCabinet],
        templates: [String: URL],
        progress: @escaping (Double, String) -> Void
    ) async -> [String: NSImage] {
        var results: [String: NSImage] = [:]
        let total = Double(cabinets.count)
        
        for (index, cabinet) in cabinets.enumerated() {
            progress(Double(index) / total, "Generating preview: \(cabinet.displayName)")
            
            guard let templateURL = templates[cabinet.suggestedTemplateID] else {
                continue
            }
            
            if let image = await generatePreview(for: cabinet, templateGLB: templateURL) {
                results[cabinet.id] = image
            }
        }
        
        progress(1.0, "Preview generation complete")
        return results
    }
    
    // MARK: - Cache Management
    
    /// Get cached preview if available
    func getCachedPreview(_ cacheKey: String) -> NSImage? {
        let cachePath = cacheDirectory.appendingPathComponent("\(cacheKey).png")
        if fileManager.fileExists(atPath: cachePath.path) {
            return NSImage(contentsOf: cachePath)
        }
        return nil
    }
    
    /// Clear preview cache
    func clearCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Blender Rendering
    
    /// Render a preview using Blender
    private func renderPreview(
        glbFile: URL,
        assetsFolder: URL,
        meshMappings: [String: String],
        outputPath: URL
    ) async -> Bool {
        logger.log(.info, "Starting Blender render...")
        
        return await withCheckedContinuation { continuation in
            // Build texture assignments JSON
            var textureAssignments: [[String: String]] = []
            var missingTextures: [String] = []
            
            for (meshName, assetFile) in meshMappings {
                let assetPath = assetsFolder.appendingPathComponent(assetFile).path
                if fileManager.fileExists(atPath: assetPath) {
                    textureAssignments.append([
                        "mesh": meshName,
                        "texture": assetPath
                    ])
                } else {
                    missingTextures.append("\(meshName): \(assetFile)")
                }
            }
            
            if !missingTextures.isEmpty {
                logger.log(.warning, "Missing textures (\(missingTextures.count)):", details: missingTextures.joined(separator: "\n"))
            }
            
            logger.log(.info, "Texture assignments: \(textureAssignments.count) valid mappings")
            
            let texturesJSON = (try? JSONEncoder().encode(textureAssignments))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            
            let script = """
import bpy
import json
import math
import mathutils
import os

print("PREVIEW_LOG: Starting preview generation")
print(f"PREVIEW_LOG: GLB file: \(glbFile.path)")

# Clear scene
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

# Import GLB (cabinet's own model)
print(f"PREVIEW_LOG: Importing GLB...")
try:
    bpy.ops.import_scene.gltf(filepath='\(glbFile.path)')
    print("PREVIEW_LOG: GLB import successful")
except Exception as e:
    print(f"PREVIEW_LOG_ERROR: GLB import failed: {e}")

# List all imported meshes
print("PREVIEW_LOG: Imported meshes:")
mesh_list = []
for obj in bpy.data.objects:
    if obj.type == 'MESH':
        mesh_list.append(obj.name)
        print(f"  MESH: {obj.name}")
print(f"PREVIEW_LOG: Total meshes: {len(mesh_list)}")

# Texture assignments
textures = json.loads('''\(texturesJSON)''')
print(f"PREVIEW_LOG: Texture assignments to apply: {len(textures)}")

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
    
    # Check if texture file exists
    if not os.path.exists(texture_path):
        print(f"PREVIEW_LOG_ERROR: Texture file not found: {texture_path}")
        return False
    
    # Create material
    mat = bpy.data.materials.new(name=f"mat_{obj.name}")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    
    # Get principled BSDF
    bsdf = nodes.get("Principled BSDF")
    if not bsdf:
        print(f"PREVIEW_LOG_ERROR: No Principled BSDF for {obj.name}")
        return False
    
    # Add image texture
    tex_node = nodes.new('ShaderNodeTexImage')
    try:
        tex_node.image = bpy.data.images.load(texture_path)
        links.new(tex_node.outputs['Color'], bsdf.inputs['Base Color'])
        print(f"PREVIEW_LOG: Applied texture to {obj.name}")
    except Exception as e:
        print(f"PREVIEW_LOG_ERROR: Failed to load texture {texture_path}: {e}")
        return False
    
    # Apply material
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    return True

# Apply textures
applied_count = 0
failed_count = 0
for assignment in textures:
    mesh_name = assignment.get('mesh', '')
    texture_path = assignment.get('texture', '')
    obj = find_mesh(mesh_name)
    if obj:
        if apply_texture(obj, texture_path):
            applied_count += 1
        else:
            failed_count += 1
    else:
        print(f"PREVIEW_LOG_WARNING: Mesh not found: {mesh_name}")
        failed_count += 1

print(f"PREVIEW_LOG: Textures applied: {applied_count}, Failed: {failed_count}")

# Apply gray material to untextured meshes
gray_mat = bpy.data.materials.new(name="gray_default")
gray_mat.use_nodes = True
gray_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.3, 0.3, 0.3, 1)

textured_meshes = set(a.get('mesh', '').lower() for a in textures)
gray_count = 0
for obj in bpy.data.objects:
    if obj.type == 'MESH' and 'mock' not in obj.name.lower():
        if obj.name.lower() not in textured_meshes and not any(t in obj.name.lower() for t in textured_meshes):
            if not obj.data.materials:
                obj.data.materials.append(gray_mat)
                gray_count += 1
                print(f"PREVIEW_LOG: Applied gray to untextured mesh: {obj.name}")

print(f"PREVIEW_LOG: Applied gray material to {gray_count} untextured meshes")

# Calculate bounding box of all objects to frame camera
min_coords = [float('inf')] * 3
max_coords = [float('-inf')] * 3
for obj in bpy.data.objects:
    if obj.type == 'MESH':
        for v in obj.bound_box:
            world_v = obj.matrix_world @ mathutils.Vector(v)
            for i in range(3):
                min_coords[i] = min(min_coords[i], world_v[i])
                max_coords[i] = max(max_coords[i], world_v[i])

# Calculate center and size
center = [(min_coords[i] + max_coords[i]) / 2 for i in range(3)]
size = max(max_coords[i] - min_coords[i] for i in range(3))

# Setup camera - position based on model size
cam = bpy.data.cameras.new('PreviewCam')
cam.lens = 35  # Wider lens to capture more
cam_obj = bpy.data.objects.new('PreviewCam', cam)
bpy.context.scene.collection.objects.link(cam_obj)
bpy.context.scene.camera = cam_obj

# Position camera to see full cabinet (further back, looking at center)
distance = size * 2.5  # Distance based on model size
cam_obj.location = (center[0] + distance * 0.7, center[1] - distance * 0.7, center[2] + distance * 0.5)

# Point camera at center of model
direction = mathutils.Vector(center) - cam_obj.location
rot_quat = direction.to_track_quat('-Z', 'Y')
cam_obj.rotation_euler = rot_quat.to_euler()

# Setup lighting
sun = bpy.data.lights.new('Sun', 'SUN')
sun_obj = bpy.data.objects.new('Sun', sun)
bpy.context.scene.collection.objects.link(sun_obj)
sun_obj.rotation_euler = (math.radians(50), math.radians(20), 0)
sun.energy = 5

# Add fill light
fill = bpy.data.lights.new('Fill', 'AREA')
fill_obj = bpy.data.objects.new('Fill', fill)
bpy.context.scene.collection.objects.link(fill_obj)
fill_obj.location = (center[0] - distance, center[1], center[2] + distance * 0.5)
fill.energy = 150

# Add back light
back = bpy.data.lights.new('Back', 'AREA')
back_obj = bpy.data.objects.new('Back', back)
bpy.context.scene.collection.objects.link(back_obj)
back_obj.location = (center[0], center[1] + distance, center[2] + distance * 0.3)
back.energy = 80

# Setup world
bpy.context.scene.world = bpy.data.worlds.new('World')
bpy.context.scene.world.use_nodes = True
bg = bpy.context.scene.world.node_tree.nodes['Background']
bg.inputs['Color'].default_value = (0.12, 0.14, 0.18, 1)

# Render settings - higher resolution for quality previews
bpy.context.scene.render.engine = 'BLENDER_EEVEE'
bpy.context.scene.render.resolution_x = 600
bpy.context.scene.render.resolution_y = 600
bpy.context.scene.render.film_transparent = False
bpy.context.scene.render.filepath = '\(outputPath.path)'

# Render
bpy.ops.render.render(write_still=True)
print('PREVIEW_GENERATED_SUCCESS')
"""
            
            self.logger.log(.debug, "Launching Blender process...")
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/Applications/Blender.app/Contents/MacOS/Blender")
            process.arguments = ["-b", "--factory-startup", "--python-expr", script]
            
            // Capture output for logging
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                // Read output
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let outputString = String(data: outputData, encoding: .utf8) ?? ""
                let errorString = String(data: errorData, encoding: .utf8) ?? ""
                
                // Log relevant output lines
                let relevantLines = outputString.components(separatedBy: "\n").filter { line in
                    line.contains("PREVIEW") || line.contains("Error") || line.contains("Warning") ||
                    line.contains("import") || line.contains("mesh") || line.contains("texture")
                }
                if !relevantLines.isEmpty {
                    self.logger.log(.debug, "Blender output:", details: relevantLines.joined(separator: "\n"))
                }
                
                // Log errors if any
                if !errorString.isEmpty && !errorString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.logger.log(.warning, "Blender stderr:", details: String(errorString.prefix(2000)))
                }
                
                // Check success
                let success = process.terminationStatus == 0 &&
                              self.fileManager.fileExists(atPath: outputPath.path)
                
                if success {
                    self.logger.log(.success, "Blender render completed", details: "Exit code: \(process.terminationStatus)")
                } else {
                    self.logger.log(.error, "Blender render failed", details: "Exit code: \(process.terminationStatus), Output exists: \(self.fileManager.fileExists(atPath: outputPath.path))")
                    
                    // Log more output on failure
                    if !outputString.isEmpty {
                        self.logger.log(.debug, "Full Blender output on failure:", details: String(outputString.suffix(3000)))
                    }
                }
                
                continuation.resume(returning: success)
            } catch {
                self.logger.log(.error, "Failed to run Blender process", details: error.localizedDescription)
                continuation.resume(returning: false)
            }
        }
    }
    
    // MARK: - Thumbnail Generation
    
    /// Generate a smaller thumbnail from an existing preview
    func generateThumbnail(from image: NSImage, size: CGSize = CGSize(width: 100, height: 100)) -> NSImage {
        let thumbnail = NSImage(size: size)
        thumbnail.lockFocus()
        
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        
        thumbnail.unlockFocus()
        return thumbnail
    }
}

// MARK: - Asset Thumbnail Generator

extension PreviewGenerator {
    
    /// Generate thumbnails for discovered assets
    func generateAssetThumbnails(for cabinet: inout DiscoveredCabinet) {
        for i in cabinet.assets.indices {
            if let image = NSImage(contentsOf: cabinet.assets[i].url) {
                cabinet.assets[i].thumbnail = generateThumbnail(from: image, size: CGSize(width: 50, height: 50))
            }
        }
    }
}
