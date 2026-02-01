//
//  PropsConverter.swift
//  RetroVisionCabsConverter
//
//  Converts props to USDZ format with video/audio handling for VisionOS
//

import Foundation
import AppKit

// MARK: - Props Converter

class PropsConverter {
    static let shared = PropsConverter()
    
    private let fileManager = FileManager.default
    private let tempDirectory: URL
    
    init() {
        let paths = RetroVisionPaths.load()
        tempDirectory = URL(fileURLWithPath: paths.propsConvertTempDir)
        try? fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Conversion
    
    /// Convert a single prop to USDZ
    func convertProp(
        _ prop: DiscoveredProp,
        outputFolder: URL,
        progress: @escaping (Double, String) -> Void
    ) async throws -> PropConversionResult {
        
        progress(0.1, "Preparing \(prop.displayName)...")
        
        // Create output folder
        let propOutputFolder = outputFolder.appendingPathComponent(prop.name)
        try? fileManager.removeItem(at: propOutputFolder)
        try fileManager.createDirectory(at: propOutputFolder, withIntermediateDirectories: true)
        
        guard let glbFile = prop.glbFile else {
            throw PropsConverterError.noModel("No GLB file found for \(prop.name)")
        }
        
        progress(0.2, "Converting 3D model...")
        
        // Convert GLB to USDZ
        let usdzPath = propOutputFolder.appendingPathComponent("\(prop.name).usdz")
        let conversionSuccess = await convertGLBToUSDZ(
            glbFile: glbFile,
            assetsFolder: prop.sourcePath,
            meshMappings: prop.meshMappings,
            outputPath: usdzPath
        )
        
        guard conversionSuccess else {
            throw PropsConverterError.conversionFailed("Failed to convert GLB to USDZ")
        }
        
        progress(0.5, "Processing media files...")
        
        var videoOutputPath: URL? = nil
        var audioOutputPaths: [URL] = []
        
        // Handle video
        if let videoInfo = prop.videoInfo {
            progress(0.6, "Processing video...")
            
            if videoInfo.isVisionOSCompatible {
                // Just copy the video
                let videoFileName = videoInfo.file.lastPathComponent
                let destPath = propOutputFolder.appendingPathComponent(videoFileName)
                try fileManager.copyItem(at: videoInfo.file, to: destPath)
                videoOutputPath = destPath
            } else {
                // Convert to MP4
                let videoFileName = videoInfo.file.deletingPathExtension().lastPathComponent + ".mp4"
                let destPath = propOutputFolder.appendingPathComponent(videoFileName)
                
                let converted = await convertVideoToMP4(
                    input: videoInfo.file,
                    output: destPath
                )
                
                if converted {
                    videoOutputPath = destPath
                }
            }
        }
        
        // Handle audio files
        progress(0.7, "Processing audio...")
        
        for audioFile in prop.audioFiles {
            let audioFileName = audioFile.lastPathComponent
            let destPath = propOutputFolder.appendingPathComponent(audioFileName)
            try? fileManager.copyItem(at: audioFile, to: destPath)
            audioOutputPaths.append(destPath)
        }
        
        progress(0.8, "Generating metadata...")
        
        // Generate VisionOS metadata
        let metadata = PropVisionOSMetadata(
            id: prop.id,
            name: prop.displayName,
            type: "prop",
            propType: prop.propType.rawValue,
            placement: prop.placement.rawValue,
            dimensions: prop.dimensions,
            hasVideo: videoOutputPath != nil,
            videoFile: videoOutputPath?.lastPathComponent,
            videoLooping: true,
            hasAudio: !audioOutputPaths.isEmpty,
            audioFiles: audioOutputPaths.map { $0.lastPathComponent },
            interactionZones: extractInteractionZones(from: prop),
            tags: prop.tags,
            theme: prop.theme,
            author: prop.author
        )
        
        // Save metadata JSON
        let metadataPath = propOutputFolder.appendingPathComponent("prop_metadata.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let metadataData = try encoder.encode(metadata)
        try metadataData.write(to: metadataPath)
        
        progress(0.9, "Copying textures...")
        
        // Copy texture files
        for texture in prop.textureFiles {
            let destPath = propOutputFolder.appendingPathComponent(texture.lastPathComponent)
            if !fileManager.fileExists(atPath: destPath.path) {
                try? fileManager.copyItem(at: texture, to: destPath)
            }
        }
        
        progress(1.0, "Completed \(prop.displayName)")
        
        return PropConversionResult(
            propID: prop.id,
            propName: prop.displayName,
            outputFolder: propOutputFolder,
            usdzPath: usdzPath,
            videoPath: videoOutputPath,
            audioPaths: audioOutputPaths,
            metadataPath: metadataPath,
            success: true
        )
    }
    
    /// Convert multiple props
    func convertProps(
        _ props: [DiscoveredProp],
        outputFolder: URL,
        progress: @escaping (Double, String) -> Void
    ) async -> [PropConversionResult] {
        var results: [PropConversionResult] = []
        let total = Double(props.count)
        
        for (index, prop) in props.enumerated() {
            let subProgress: (Double, String) -> Void = { p, msg in
                let overall = (Double(index) + p) / total
                progress(overall, msg)
            }
            
            do {
                let result = try await convertProp(prop, outputFolder: outputFolder, progress: subProgress)
                results.append(result)
            } catch {
                print("Failed to convert prop \(prop.name): \(error)")
                results.append(PropConversionResult(
                    propID: prop.id,
                    propName: prop.displayName,
                    outputFolder: outputFolder.appendingPathComponent(prop.name),
                    usdzPath: nil,
                    videoPath: nil,
                    audioPaths: [],
                    metadataPath: nil,
                    success: false,
                    error: error.localizedDescription
                ))
            }
        }
        
        return results
    }
    
    // MARK: - GLB to USDZ Conversion
    
    private func convertGLBToUSDZ(
        glbFile: URL,
        assetsFolder: URL,
        meshMappings: [String: String],
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
            
            // Set temp directory from config
            let configPaths = RetroVisionPaths.load()
            let blenderTempDir = configPaths.blenderTempDir
            try? fileManager.createDirectory(atPath: blenderTempDir, withIntermediateDirectories: true)
            
            let script = """
import bpy
import json
import os

os.environ['TMPDIR'] = '\(blenderTempDir)'
os.environ['TMP'] = '\(blenderTempDir)'
os.environ['TEMP'] = '\(blenderTempDir)'

print("PROP_CONVERT: Starting conversion")
print(f"PROP_CONVERT: Input: \(glbFile.path)")
print(f"PROP_CONVERT: Output: \(outputPath.path)")

# Clear scene
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

# Import GLB
try:
    bpy.ops.import_scene.gltf(filepath='\(glbFile.path)')
    print("PROP_CONVERT: GLB imported")
except Exception as e:
    print(f"PROP_CONVERT_ERROR: Import failed: {e}")

# Apply textures
textures = json.loads('''\(texturesJSON)''')

def find_mesh(name):
    name_lower = name.lower()
    for obj in bpy.data.objects:
        if obj.type == 'MESH':
            if obj.name.lower() == name_lower or name_lower in obj.name.lower():
                return obj
    return None

def apply_texture(obj, texture_path):
    if not obj or not texture_path or not os.path.exists(texture_path):
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
    except:
        return False
    
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    return True

for assignment in textures:
    mesh_name = assignment.get('mesh', '')
    texture_path = assignment.get('texture', '')
    obj = find_mesh(mesh_name)
    if obj:
        apply_texture(obj, texture_path)

# Export as USDZ
print("PROP_CONVERT: Exporting to USDZ...")
try:
    bpy.ops.wm.usd_export(
        filepath='\(outputPath.path)',
        export_materials=True,
        evaluation_mode='RENDER'
    )
    print("PROP_CONVERT: Export successful")
except Exception as e:
    print(f"PROP_CONVERT_ERROR: Export failed: {e}")

if os.path.exists('\(outputPath.path)'):
    print("PROP_CONVERT_SUCCESS")
else:
    print("PROP_CONVERT_FAILED")
"""
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/Applications/Blender.app/Contents/MacOS/Blender")
            process.arguments = ["-b", "--factory-startup", "--python-expr", script]
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = FileHandle.nullDevice
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let outputString = String(data: outputData, encoding: .utf8) ?? ""
                
                let success = outputString.contains("PROP_CONVERT_SUCCESS") &&
                              self.fileManager.fileExists(atPath: outputPath.path)
                
                continuation.resume(returning: success)
            } catch {
                print("Blender error: \(error)")
                continuation.resume(returning: false)
            }
        }
    }
    
    // MARK: - Video Conversion
    
    private func convertVideoToMP4(input: URL, output: URL) async -> Bool {
        return await withCheckedContinuation { continuation in
            let process = Process()
            
            // Try homebrew ffmpeg first, then system
            let ffmpegPaths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
            var ffmpegPath: String? = nil
            
            for path in ffmpegPaths {
                if fileManager.fileExists(atPath: path) {
                    ffmpegPath = path
                    break
                }
            }
            
            guard let ffmpeg = ffmpegPath else {
                print("FFmpeg not found")
                continuation.resume(returning: false)
                return
            }
            
            process.executableURL = URL(fileURLWithPath: ffmpeg)
            process.arguments = [
                "-y",                       // Overwrite
                "-i", input.path,           // Input
                "-c:v", "libx264",          // Video codec
                "-preset", "medium",        // Encoding speed
                "-crf", "23",               // Quality
                "-c:a", "aac",              // Audio codec
                "-b:a", "128k",             // Audio bitrate
                "-movflags", "+faststart",  // Web optimization
                output.path                 // Output
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let success = process.terminationStatus == 0 &&
                              self.fileManager.fileExists(atPath: output.path)
                continuation.resume(returning: success)
            } catch {
                print("FFmpeg error: \(error)")
                continuation.resume(returning: false)
            }
        }
    }
    
    // MARK: - Interaction Zones
    
    private func extractInteractionZones(from prop: DiscoveredProp) -> [PropVisionOSMetadata.InteractionZone] {
        var zones: [PropVisionOSMetadata.InteractionZone] = []
        
        // Check mesh names for blockers/triggers
        for meshName in prop.glbMeshNames {
            let nameLower = meshName.lowercased()
            
            if nameLower.contains("blocker") {
                zones.append(PropVisionOSMetadata.InteractionZone(name: meshName, type: "blocker"))
            } else if nameLower.contains("trigger") {
                zones.append(PropVisionOSMetadata.InteractionZone(name: meshName, type: "trigger"))
            } else if nameLower.contains("button") {
                zones.append(PropVisionOSMetadata.InteractionZone(name: meshName, type: "button"))
            }
        }
        
        return zones
    }
}

// MARK: - Conversion Result

struct PropConversionResult {
    var propID: String
    var propName: String
    var outputFolder: URL
    var usdzPath: URL?
    var videoPath: URL?
    var audioPaths: [URL]
    var metadataPath: URL?
    var success: Bool
    var error: String?
}

// MARK: - Errors

enum PropsConverterError: LocalizedError {
    case noModel(String)
    case conversionFailed(String)
    case videoConversionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noModel(let msg): return "No model: \(msg)"
        case .conversionFailed(let msg): return "Conversion failed: \(msg)"
        case .videoConversionFailed(let msg): return "Video conversion failed: \(msg)"
        }
    }
}
