//
//  VisionOSCabinetExporter.swift
//  RetroVisionCabsConverter
//
//  Exports arcade cabinets with VisionOS-ready Swift code and assets
//  Includes full interactivity: drag, rotate, scale, CRT effects, audio
//

import Foundation
import AppKit

// MARK: - VisionOS Cabinet Exporter

class VisionOSCabinetExporter {
    static let shared = VisionOSCabinetExporter()
    
    private let fileManager = FileManager.default
    
    // MARK: - Export Options
    
    struct ExportOptions {
        var videoCodec: VideoCodec = .hevc
        var videoQuality: VideoQuality = .high
        var includeSwiftCode: Bool = true
        var includeReadme: Bool = true
        var includeCRTShader: Bool = true
        var includeInteraction: Bool = true
        
        enum VideoCodec: String, CaseIterable {
            case hevc = "HEVC (H.265)"
            case h264 = "H.264"
            case prores = "ProRes"
            
            var ffmpegCodec: String {
                switch self {
                case .hevc: return "libx265"
                case .h264: return "libx264"
                case .prores: return "prores_ks"
                }
            }
        }
        
        enum VideoQuality: String, CaseIterable {
            case low = "Low"
            case medium = "Medium"
            case high = "High"
            case lossless = "Lossless"
            
            var crf: Int {
                switch self {
                case .low: return 28
                case .medium: return 23
                case .high: return 18
                case .lossless: return 0
                }
            }
        }
    }
    
    // MARK: - Export Cabinet
    
    func exportCabinet(
        _ cabinet: CabinetItem,
        to outputFolder: URL,
        options: ExportOptions = ExportOptions(),
        progress: @escaping (Double, String) -> Void
    ) async throws -> CabinetExportResult {
        
        let cabinetFolder = outputFolder.appendingPathComponent(sanitizeFileName(cabinet.name))
        try? fileManager.removeItem(at: cabinetFolder)
        try fileManager.createDirectory(at: cabinetFolder, withIntermediateDirectories: true)
        
        // Create subfolders
        let assetsFolder = cabinetFolder.appendingPathComponent("Assets")
        let modelFolder = assetsFolder.appendingPathComponent("Models")
        let textureFolder = assetsFolder.appendingPathComponent("Textures")
        let videoFolder = assetsFolder.appendingPathComponent("Video")
        let audioFolder = assetsFolder.appendingPathComponent("Audio")
        let shadersFolder = assetsFolder.appendingPathComponent("Shaders")
        
        for folder in [modelFolder, textureFolder, videoFolder, audioFolder, shadersFolder] {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        
        var result = CabinetExportResult(cabinetName: cabinet.name, outputFolder: cabinetFolder)
        
        // 1. Convert GLB to USDZ
        progress(0.1, "Converting 3D model...")
        if let glbFile = findGLBFile(in: cabinet) {
            let usdzPath = modelFolder.appendingPathComponent("\(cabinet.name).usdz")
            let success = await convertGLBToUSDZ(
                cabinet: cabinet,
                glbFile: glbFile,
                outputPath: usdzPath
            )
            if success {
                result.modelPath = usdzPath
            }
        }
        
        // 2. Process marquee/bezel video
        progress(0.3, "Processing video...")
        if let videoFile = findVideoFile(in: cabinet) {
            let videoResult = await convertVideoForVisionOS(
                input: videoFile,
                outputFolder: videoFolder,
                codec: options.videoCodec,
                quality: options.videoQuality
            )
            result.videoPath = videoResult.outputPath
            result.videoMetadata = videoResult
        }
        
        // 3. Copy textures
        progress(0.5, "Copying textures...")
        let textures = findTextureFiles(in: cabinet)
        for texture in textures {
            let destPath = textureFolder.appendingPathComponent(texture.lastPathComponent)
            try? fileManager.copyItem(at: texture, to: destPath)
            result.texturePaths.append(destPath)
        }
        
        // 4. Copy audio files
        progress(0.6, "Copying audio...")
        let audioFiles = findAudioFiles(in: cabinet)
        for audio in audioFiles {
            let destPath = audioFolder.appendingPathComponent(audio.lastPathComponent)
            try? fileManager.copyItem(at: audio, to: destPath)
            result.audioPaths.append(destPath)
        }
        
        // 5. Generate CRT shader if needed
        if options.includeCRTShader {
            progress(0.65, "Generating CRT shader...")
            let shaderCode = generateCRTShader()
            let shaderPath = shadersFolder.appendingPathComponent("CRTEffect.metal")
            try shaderCode.write(to: shaderPath, atomically: true, encoding: .utf8)
            result.shaderPath = shaderPath
        }
        
        // 6. Generate metadata
        progress(0.7, "Generating metadata...")
        let metadata = createVisionOSMetadata(cabinet: cabinet, result: result)
        let metadataPath = cabinetFolder.appendingPathComponent("cabinet_config.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(metadata).write(to: metadataPath)
        result.metadataPath = metadataPath
        
        // 7. Generate Swift code
        if options.includeSwiftCode {
            progress(0.8, "Generating Swift code...")
            let swiftCode = generateSwiftCode(for: cabinet, result: result, options: options)
            let swiftPath = cabinetFolder.appendingPathComponent("Cabinet\(sanitizeClassName(cabinet.name)).swift")
            try swiftCode.write(to: swiftPath, atomically: true, encoding: .utf8)
            result.swiftCodePath = swiftPath
        }
        
        // 8. Generate README
        if options.includeReadme {
            progress(0.9, "Generating documentation...")
            let readme = generateReadme(for: cabinet, result: result)
            let readmePath = cabinetFolder.appendingPathComponent("README.md")
            try readme.write(to: readmePath, atomically: true, encoding: .utf8)
            result.readmePath = readmePath
        }
        
        progress(1.0, "Export complete")
        result.success = true
        return result
    }
    
    // MARK: - Batch Export
    
    func exportCabinets(
        _ cabinets: [CabinetItem],
        to outputFolder: URL,
        options: ExportOptions = ExportOptions(),
        progress: @escaping (Double, String) -> Void
    ) async -> [CabinetExportResult] {
        var results: [CabinetExportResult] = []
        let total = Double(cabinets.count)
        
        for (index, cabinet) in cabinets.enumerated() {
            let subProgress: (Double, String) -> Void = { p, msg in
                let overall = (Double(index) + p) / total
                progress(overall, msg)
            }
            
            do {
                let result = try await exportCabinet(cabinet, to: outputFolder, options: options, progress: subProgress)
                results.append(result)
            } catch {
                results.append(CabinetExportResult(
                    cabinetName: cabinet.name,
                    outputFolder: outputFolder.appendingPathComponent(cabinet.name),
                    success: false,
                    error: error.localizedDescription
                ))
            }
        }
        
        return results
    }
    
    // MARK: - File Discovery
    
    private func findGLBFile(in cabinet: CabinetItem) -> URL? {
        let folderPath = URL(fileURLWithPath: cabinet.path)
        let glbExtensions = ["glb", "gltf"]
        
        if let contents = try? fileManager.contentsOfDirectory(at: folderPath, includingPropertiesForKeys: nil) {
            for file in contents {
                if glbExtensions.contains(file.pathExtension.lowercased()) {
                    return file
                }
            }
        }
        return nil
    }
    
    private func findVideoFile(in cabinet: CabinetItem) -> URL? {
        let folderPath = URL(fileURLWithPath: cabinet.path)
        let videoExtensions = ["mp4", "m4v", "mov", "mkv", "avi"]
        
        if let contents = try? fileManager.contentsOfDirectory(at: folderPath, includingPropertiesForKeys: nil) {
            for file in contents {
                if videoExtensions.contains(file.pathExtension.lowercased()) {
                    return file
                }
            }
        }
        return nil
    }
    
    private func findTextureFiles(in cabinet: CabinetItem) -> [URL] {
        let folderPath = URL(fileURLWithPath: cabinet.path)
        let textureExtensions = ["png", "jpg", "jpeg", "tga", "bmp"]
        var textures: [URL] = []
        
        if let contents = try? fileManager.contentsOfDirectory(at: folderPath, includingPropertiesForKeys: nil) {
            for file in contents {
                if textureExtensions.contains(file.pathExtension.lowercased()) {
                    textures.append(file)
                }
            }
        }
        return textures
    }
    
    private func findAudioFiles(in cabinet: CabinetItem) -> [URL] {
        let folderPath = URL(fileURLWithPath: cabinet.path)
        let audioExtensions = ["mp3", "wav", "m4a", "ogg", "aac"]
        var audioFiles: [URL] = []
        
        if let contents = try? fileManager.contentsOfDirectory(at: folderPath, includingPropertiesForKeys: nil) {
            for file in contents {
                if audioExtensions.contains(file.pathExtension.lowercased()) {
                    audioFiles.append(file)
                }
            }
        }
        return audioFiles
    }
    
    // MARK: - GLB to USDZ Conversion
    
    private func convertGLBToUSDZ(cabinet: CabinetItem, glbFile: URL, outputPath: URL) async -> Bool {
        return await withCheckedContinuation { continuation in
            let paths = RetroVisionPaths.load()
            let blenderTempDir = paths.blenderTempDir
            try? fileManager.createDirectory(atPath: blenderTempDir, withIntermediateDirectories: true)
            
            let cabinetFolder = URL(fileURLWithPath: cabinet.path)
            
            // Build texture assignments from cabinet's description.yaml
            var textureAssignments: [[String: String]] = []
            let yamlPath = cabinetFolder.appendingPathComponent("description.yaml")
            if let yamlContent = try? String(contentsOf: yamlPath, encoding: .utf8) {
                let mappings = parseYAMLMappings(yamlContent, baseFolder: cabinetFolder)
                for (mesh, texture) in mappings {
                    textureAssignments.append(["mesh": mesh, "texture": texture])
                }
            }
            
            let texturesJSON = (try? JSONEncoder().encode(textureAssignments))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            
            let script = """
import bpy
import json
import os

os.environ['TMPDIR'] = '\(blenderTempDir)'
os.environ['TMP'] = '\(blenderTempDir)'
os.environ['TEMP'] = '\(blenderTempDir)'

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

try:
    bpy.ops.import_scene.gltf(filepath='\(glbFile.path)')
    print("CABINET_CONVERT: Import successful")
except Exception as e:
    print(f"CABINET_CONVERT_ERROR: {e}")

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

try:
    bpy.ops.wm.usd_export(filepath='\(outputPath.path)', export_materials=True, evaluation_mode='RENDER')
    print("CABINET_CONVERT_SUCCESS")
except Exception as e:
    print(f"CABINET_CONVERT_ERROR: Export failed: {e}")
"""
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/Applications/Blender.app/Contents/MacOS/Blender")
            process.arguments = ["-b", "--factory-startup", "--python-expr", script]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            
            do {
                try process.run()
                process.waitUntilExit()
                continuation.resume(returning: fileManager.fileExists(atPath: outputPath.path))
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
    
    private func parseYAMLMappings(_ yaml: String, baseFolder: URL) -> [String: String] {
        var mappings: [String: String] = [:]
        let lines = yaml.components(separatedBy: "\n")
        var currentPart: String?
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("- name:") {
                currentPart = trimmed.replacingOccurrences(of: "- name:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("file:") && currentPart != nil {
                let fileName = trimmed.replacingOccurrences(of: "file:", with: "").trimmingCharacters(in: .whitespaces)
                let fullPath = baseFolder.appendingPathComponent(fileName).path
                if fileManager.fileExists(atPath: fullPath) {
                    mappings[currentPart!] = fullPath
                }
            }
        }
        
        return mappings
    }
    
    // MARK: - Video Conversion
    
    private func convertVideoForVisionOS(
        input: URL,
        outputFolder: URL,
        codec: ExportOptions.VideoCodec,
        quality: ExportOptions.VideoQuality
    ) async -> VideoConversionResult {
        var result = VideoConversionResult(
            originalFormat: input.pathExtension.uppercased(),
            outputFormat: "MP4",
            codec: codec.rawValue
        )
        
        let outputName = input.deletingPathExtension().lastPathComponent
        let outputPath = outputFolder.appendingPathComponent("\(outputName).mp4")
        
        let success = await runFFmpegConversion(input: input, output: outputPath, codec: codec, quality: quality)
        
        if success {
            result.outputPath = outputPath
        }
        
        return result
    }
    
    private func runFFmpegConversion(
        input: URL,
        output: URL,
        codec: ExportOptions.VideoCodec,
        quality: ExportOptions.VideoQuality
    ) async -> Bool {
        return await withCheckedContinuation { continuation in
            guard let ffmpeg = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first(where: { fileManager.fileExists(atPath: $0) }) else {
                continuation.resume(returning: false)
                return
            }
            
            var arguments: [String] = ["-y", "-i", input.path]
            
            switch codec {
            case .hevc:
                arguments += ["-c:v", "libx265", "-tag:v", "hvc1", "-preset", "medium", "-crf", "\(quality.crf)", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]
            case .h264:
                arguments += ["-c:v", "libx264", "-profile:v", "high", "-preset", "medium", "-crf", "\(quality.crf)", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]
            case .prores:
                arguments += ["-c:v", "prores_ks", "-profile:v", "3", "-c:a", "pcm_s16le"]
            }
            
            arguments.append(output.path)
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpeg)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            
            do {
                try process.run()
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0)
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
    
    // MARK: - CRT Shader Generation
    
    private func generateCRTShader() -> String {
        return """
//
//  CRTEffect.metal
//  Generated by RetroVisionCabsConverter
//
//  A CRT screen effect shader for VisionOS/RealityKit
//  Apply to the screen mesh to simulate vintage CRT displays
//

#include <metal_stdlib>
using namespace metal;

// CRT effect parameters
struct CRTParameters {
    float scanlineIntensity;    // 0.0 - 1.0
    float curvature;            // 0.0 - 1.0
    float vignetteIntensity;    // 0.0 - 1.0
    float brightness;           // 0.5 - 1.5
    float contrast;             // 0.5 - 1.5
    float saturation;           // 0.0 - 2.0
    float flickerIntensity;     // 0.0 - 1.0
    float time;                 // For animation
};

// Apply barrel distortion for CRT curvature
float2 applyCurvature(float2 uv, float curvature) {
    float2 centered = uv * 2.0 - 1.0;
    float2 offset = centered * pow(length(centered), 2.0) * curvature * 0.1;
    return (centered + offset) * 0.5 + 0.5;
}

// Generate scanlines
float scanlines(float2 uv, float intensity, float count) {
    float scanline = sin(uv.y * count * 3.14159) * 0.5 + 0.5;
    return mix(1.0, scanline, intensity);
}

// Apply vignette effect
float vignette(float2 uv, float intensity) {
    float2 centered = uv * 2.0 - 1.0;
    float dist = length(centered);
    return 1.0 - smoothstep(0.5, 1.5, dist) * intensity;
}

// CRT phosphor RGB separation
float3 phosphorMask(float2 uv, float2 resolution) {
    float2 pixelPos = uv * resolution;
    int pattern = int(pixelPos.x) % 3;
    
    if (pattern == 0) return float3(1.0, 0.7, 0.7);
    if (pattern == 1) return float3(0.7, 1.0, 0.7);
    return float3(0.7, 0.7, 1.0);
}

// Main CRT effect function
float4 applyCRTEffect(
    float4 inputColor,
    float2 uv,
    float2 resolution,
    constant CRTParameters& params
) {
    // Apply curvature
    float2 curvedUV = applyCurvature(uv, params.curvature);
    
    // Check if outside curved screen bounds
    if (curvedUV.x < 0.0 || curvedUV.x > 1.0 || curvedUV.y < 0.0 || curvedUV.y > 1.0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
    
    // Get base color
    float3 color = inputColor.rgb;
    
    // Apply brightness and contrast
    color = (color - 0.5) * params.contrast + 0.5;
    color *= params.brightness;
    
    // Apply saturation
    float gray = dot(color, float3(0.299, 0.587, 0.114));
    color = mix(float3(gray), color, params.saturation);
    
    // Apply scanlines
    float scanline = scanlines(curvedUV, params.scanlineIntensity, resolution.y * 0.5);
    color *= scanline;
    
    // Apply phosphor mask
    color *= phosphorMask(curvedUV, resolution);
    
    // Apply vignette
    color *= vignette(curvedUV, params.vignetteIntensity);
    
    // Apply flicker
    float flicker = 1.0 - params.flickerIntensity * 0.03 * sin(params.time * 60.0);
    color *= flicker;
    
    return float4(color, inputColor.a);
}

// Vertex shader for fullscreen quad
vertex float4 crtVertexShader(
    uint vertexID [[vertex_id]],
    constant float4x4& modelViewProjection [[buffer(0)]]
) {
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    
    float4 position = float4(positions[vertexID], 0.0, 1.0);
    return modelViewProjection * position;
}

// Fragment shader
fragment float4 crtFragmentShader(
    float4 position [[position]],
    float2 texCoord [[user(texturecoord)]],
    texture2d<float> screenTexture [[texture(0)]],
    constant CRTParameters& params [[buffer(0)]]
) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    float4 inputColor = screenTexture.sample(textureSampler, texCoord);
    
    float2 resolution = float2(screenTexture.get_width(), screenTexture.get_height());
    
    return applyCRTEffect(inputColor, texCoord, resolution, params);
}
"""
    }
    
    // MARK: - Metadata Generation
    
    private func createVisionOSMetadata(cabinet: CabinetItem, result: CabinetExportResult) -> VisionOSCabinetConfig {
        // Parse cabinet YAML for additional info
        let yamlPath = URL(fileURLWithPath: cabinet.path).appendingPathComponent("description.yaml")
        var gameName = cabinet.name
        var year = ""
        var manufacturer = ""
        
        if let yaml = try? String(contentsOf: yamlPath, encoding: .utf8) {
            gameName = extractYAMLValue(yaml, key: "game") ?? cabinet.name
            year = extractYAMLValue(yaml, key: "year") ?? ""
            manufacturer = extractYAMLValue(yaml, key: "manufacturer") ?? ""
        }
        
        return VisionOSCabinetConfig(
            id: cabinet.name,
            name: cabinet.name,
            gameName: gameName,
            year: year,
            manufacturer: manufacturer,
            
            model: result.modelPath != nil ? VisionOSCabinetConfig.ModelConfig(
                file: result.modelPath!.lastPathComponent,
                scale: 1.0
            ) : nil,
            
            screen: VisionOSCabinetConfig.ScreenConfig(
                meshName: "screen",
                type: "crt",
                orientation: "horizontal",
                aspectRatio: "4:3"
            ),
            
            video: result.videoPath != nil ? VisionOSCabinetConfig.VideoConfig(
                file: result.videoPath!.lastPathComponent,
                loop: true,
                autoplay: false
            ) : nil,
            
            audio: !result.audioPaths.isEmpty ? result.audioPaths.map {
                VisionOSCabinetConfig.AudioConfig(file: $0.lastPathComponent, type: "effect", volume: 1.0)
            } : nil,
            
            textures: result.texturePaths.map { $0.lastPathComponent },
            
            controls: VisionOSCabinetConfig.ControlsConfig(
                coinSlot: "coin-slot",
                joystick: nil,
                buttons: []
            ),
            
            interaction: VisionOSCabinetConfig.InteractionConfig(
                draggable: true,
                rotatable: true,
                scalable: true,
                minScale: 0.1,
                maxScale: 3.0,
                playable: true
            )
        )
    }
    
    private func extractYAMLValue(_ yaml: String, key: String) -> String? {
        let lines = yaml.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\(key):") {
                let value = trimmed.replacingOccurrences(of: "\(key):", with: "").trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }
    
    // MARK: - Swift Code Generation
    
    private func generateSwiftCode(for cabinet: CabinetItem, result: CabinetExportResult, options: ExportOptions) -> String {
        let className = "Cabinet\(sanitizeClassName(cabinet.name))"
        let modelFile = result.modelPath?.lastPathComponent ?? "\(cabinet.name).usdz"
        let hasVideo = result.videoPath != nil
        let hasAudio = !result.audioPaths.isEmpty
        
        var code = """
//
//  \(className).swift
//  Generated by RetroVisionCabsConverter
//
//  Arcade Cabinet: \(cabinet.name)
//
//  Features:
//  - Drag to move in 3D space
//  - Two-finger rotation
//  - Pinch to scale (10% - 300%)
//  - Hover highlighting (Apple HIG)
//  - CRT screen effect
//  - Coin slot interaction
//  - Accessibility support
//

import SwiftUI
import RealityKit
import AVFoundation

// MARK: - \(className)

/// An interactive VisionOS arcade cabinet entity
@MainActor
class \(className): ObservableObject {
    
    // MARK: - Properties
    
    /// The main entity containing the cabinet model
    @Published var entity: Entity?
    
    /// The screen mesh entity for video/game display
    @Published var screenEntity: ModelEntity?
    
    /// Video player for attract mode/gameplay
    @Published var videoPlayer: AVPlayer?
    
    /// Audio players for sound effects
    @Published var audioPlayers: [String: AVAudioPlayer] = [:]
    
    /// Whether the cabinet is loaded
    @Published var isLoaded = false
    
    /// Whether the cabinet is in "playing" state
    @Published var isPlaying = false
    
    /// Current credit count
    @Published var credits: Int = 0
    
    /// Error message
    @Published var errorMessage: String?
    
    /// Current scale
    @Published var currentScale: Float = 1.0
    
    // Scale bounds
    let minScale: Float = 0.1
    let maxScale: Float = 3.0
    
    // MARK: - Configuration
    
    static let modelFileName = "\(modelFile)"
"""
        
        if hasVideo {
            let videoFile = result.videoPath!.lastPathComponent
            code += """

    static let videoFileName = "\(videoFile)"
"""
        }
        
        if hasAudio {
            let audioFiles = result.audioPaths.map { "\"\($0.lastPathComponent)\"" }.joined(separator: ", ")
            code += """

    static let audioFileNames = [\(audioFiles)]
"""
        }
        
        code += """

    
    // Screen mesh name
    static let screenMeshName = "screen"
    
    // Coin slot mesh name
    static let coinSlotMeshName = "coin-slot"
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Loading
    
    /// Load the cabinet's 3D model and media
    func load() async {
        do {
            guard let modelURL = Bundle.main.url(
                forResource: Self.modelFileName.replacingOccurrences(of: ".usdz", with: ""),
                withExtension: "usdz"
            ) else {
                errorMessage = "Model not found: \\(Self.modelFileName)"
                return
            }
            
            entity = try await Entity(contentsOf: modelURL)
            
            // Setup interaction
            setupInteraction()
            
            // Find screen mesh
            findScreenMesh()
            
"""
        
        if hasVideo {
            code += """
            // Setup video
            setupVideoPlayer()
            
"""
        }
        
        if hasAudio {
            code += """
            // Setup audio
            setupAudioPlayers()
            
"""
        }
        
        code += """
            isLoaded = true
            
        } catch {
            errorMessage = "Load failed: \\(error.localizedDescription)"
        }
    }
    
    // MARK: - Interaction Setup
    
    /// Configure for full interaction
    private func setupInteraction() {
        guard let entity = entity else { return }
        
        // Collision shapes for gestures
        entity.generateCollisionShapes(recursive: true)
        
        // Input target for all input types
        entity.components.set(InputTargetComponent(allowedInputTypes: .all))
        
        // Hover effect
        entity.components.set(HoverEffectComponent())
        
        // Accessibility
        var accessibility = AccessibilityComponent()
        accessibility.label = "\(cabinet.name) Arcade Cabinet"
        accessibility.value = "Interactive arcade cabinet"
        accessibility.traits = [.button]
        accessibility.isAccessibilityElement = true
        entity.components.set(accessibility)
        
        // Setup coin slot tap detection
        setupCoinSlot()
    }
    
    /// Find and configure the screen mesh
    private func findScreenMesh() {
        entity?.visit { entity in
            if let model = entity as? ModelEntity,
               model.name.lowercased().contains(Self.screenMeshName) {
                screenEntity = model
            }
        }
    }
    
    /// Setup coin slot for tap interaction
    private func setupCoinSlot() {
        entity?.visit { entity in
            if entity.name.lowercased().contains(Self.coinSlotMeshName) {
                // Add special input target for coin slot
                entity.components.set(InputTargetComponent())
            }
        }
    }
    
    // MARK: - Gesture Handling
    
    /// Handle drag gesture
    func handleDrag(_ value: EntityTargetValue<DragGesture.Value>) {
        guard let entity = entity else { return }
        let translation = value.convert(value.translation3D, from: .local, to: .scene)
        entity.position += translation
    }
    
    /// Handle rotation gesture
    func handleRotation(_ angle: Angle) {
        guard let entity = entity else { return }
        let rotation = simd_quatf(angle: Float(angle.radians), axis: SIMD3<Float>(0, 1, 0))
        entity.orientation = rotation * entity.orientation
    }
    
    /// Handle scale gesture
    func handleScale(_ magnification: CGFloat) {
        guard let entity = entity else { return }
        let newScale = currentScale * Float(magnification)
        currentScale = max(minScale, min(maxScale, newScale))
        entity.scale = SIMD3<Float>(repeating: currentScale)
    }
    
    /// Reset transform
    func resetTransform() {
        guard let entity = entity else { return }
        entity.position = .zero
        entity.orientation = .init()
        currentScale = 1.0
        entity.scale = SIMD3<Float>(repeating: 1.0)
    }
    
    /// Move with animation
    func moveTo(_ position: SIMD3<Float>, animated: Bool = true) {
        guard let entity = entity else { return }
        if animated {
            var transform = entity.transform
            transform.translation = position
            entity.move(to: transform, relativeTo: entity.parent, duration: 0.3, timingFunction: .easeInOut)
        } else {
            entity.position = position
        }
    }
    
    // MARK: - Coin Slot
    
    /// Insert a coin
    func insertCoin() {
        credits += 1
        playSound("coin")
        
        // Haptic feedback if available
        // UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    /// Start game if credits available
    func startGame() {
        guard credits > 0 else { return }
        credits -= 1
        isPlaying = true
        playVideo()
        playSound("start")
    }
    
"""
        
        // Video methods
        if hasVideo {
            code += """
    // MARK: - Video
    
    private func setupVideoPlayer() {
        guard let videoURL = Bundle.main.url(
            forResource: Self.videoFileName.replacingOccurrences(of: ".mp4", with: ""),
            withExtension: "mp4"
        ) else { return }
        
        let player = AVPlayer(url: videoURL)
        
        // Loop video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
        
        videoPlayer = player
    }
    
    /// Apply video to screen mesh
    func applyVideoToScreen() {
        guard let screen = screenEntity, let player = videoPlayer else { return }
        screen.components[VideoPlayerComponent.self] = VideoPlayerComponent(avPlayer: player)
    }
    
    func playVideo() {
        applyVideoToScreen()
        videoPlayer?.play()
    }
    
    func pauseVideo() {
        videoPlayer?.pause()
    }
    
    func toggleVideo() {
        if videoPlayer?.rate == 0 {
            playVideo()
        } else {
            pauseVideo()
        }
    }
    
"""
        }
        
        // Audio methods
        if hasAudio {
            code += """
    // MARK: - Audio
    
    private func setupAudioPlayers() {
        for fileName in Self.audioFileNames {
            let name = (fileName as NSString).deletingPathExtension
            let ext = (fileName as NSString).pathExtension
            
            guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { continue }
            
            if let player = try? AVAudioPlayer(contentsOf: url) {
                player.prepareToPlay()
                audioPlayers[name] = player
            }
        }
    }
    
    func playSound(_ name: String) {
        audioPlayers[name]?.play()
    }
    
    func stopAllSounds() {
        audioPlayers.values.forEach { $0.stop() }
    }
    
"""
        }
        
        // Cleanup
        code += """
    // MARK: - Cleanup
    
    func cleanup() {
        videoPlayer?.pause()
        videoPlayer = nil
        audioPlayers.values.forEach { $0.stop() }
        audioPlayers.removeAll()
        entity?.removeFromParent()
        entity = nil
        screenEntity = nil
        isLoaded = false
        isPlaying = false
    }
    
    deinit {
        Task { @MainActor in cleanup() }
    }
}

// MARK: - Interactive SwiftUI View

/// Interactive cabinet view with full gesture support
struct \(className)View: View {
    @StateObject private var cabinet = \(className)()
    
    var body: some View {
        RealityView { content in
            if let entity = cabinet.entity {
                content.add(entity)
"""
        
        if hasVideo {
            code += """

                cabinet.applyVideoToScreen()
"""
        }
        
        code += """

            }
        }
        .gesture(DragGesture().targetedToAnyEntity().onChanged { cabinet.handleDrag($0) })
        .gesture(RotateGesture().targetedToAnyEntity().onChanged { cabinet.handleRotation($0.rotation) })
        .gesture(MagnifyGesture().targetedToAnyEntity().onChanged { cabinet.handleScale($0.magnification) })
        .gesture(TapGesture().targetedToAnyEntity().onEnded { value in
            // Check if coin slot was tapped
            if value.entity.name.lowercased().contains("coin") {
                cabinet.insertCoin()
            }
        })
        .task { await cabinet.load() }
        .onDisappear { cabinet.cleanup() }
    }
}

// MARK: - Static View (No Interaction)

struct \(className)StaticView: View {
    @StateObject private var cabinet = \(className)()
    
    var body: some View {
        RealityView { content in
            if let entity = cabinet.entity {
                content.add(entity)
            }
        }
        .task { await cabinet.load() }
        .onDisappear { cabinet.cleanup() }
    }
}

// MARK: - Control Ornament

struct \(className)Controls: View {
    @ObservedObject var cabinet: \(className)
    
    var body: some View {
        HStack(spacing: 16) {
            // Credits
            VStack {
                Text("\\(cabinet.credits)")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Credits")
                    .font(.caption)
            }
            
            Divider().frame(height: 40)
            
            // Insert Coin
            Button {
                cabinet.insertCoin()
            } label: {
                Label("Insert Coin", systemImage: "dollarsign.circle")
            }
            
            // Start Game
            Button {
                cabinet.startGame()
            } label: {
                Label("Start", systemImage: "play.fill")
            }
            .disabled(cabinet.credits == 0)
            
            // Reset Position
            Button {
                cabinet.resetTransform()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
        }
        .padding()
        .glassBackgroundEffect()
    }
}

// MARK: - Preview

#Preview {
    \(className)View()
}
"""
        
        return code
    }
    
    // MARK: - README Generation
    
    private func generateReadme(for cabinet: CabinetItem, result: CabinetExportResult) -> String {
        return """
# \(cabinet.name) Arcade Cabinet

A VisionOS arcade cabinet for RealityKit immersive experiences.

## Features

- **Interactive**: Drag, rotate, and scale the cabinet
- **CRT Screen**: Video playback on the screen mesh
- **Coin Slot**: Tap to insert coins
- **Audio**: Sound effects support
- **Accessibility**: VoiceOver compatible

## Gestures

| Gesture | Action |
|---------|--------|
| Drag | Move cabinet in 3D |
| Two-finger Rotate | Spin cabinet |
| Pinch | Scale 10% - 300% |
| Tap Coin Slot | Insert coin |
| Look | Hover highlight |

## Files

```
\(result.outputFolder.lastPathComponent)/
├── Assets/
│   ├── Models/\(result.modelPath?.lastPathComponent ?? "model.usdz")
│   ├── Video/\(result.videoPath?.lastPathComponent ?? "(none)")
│   ├── Textures/
│   ├── Audio/
│   └── Shaders/CRTEffect.metal
├── cabinet_config.json
├── \(sanitizeClassName(cabinet.name)).swift
└── README.md
```

## Usage

### Interactive View

```swift
struct ContentView: View {
    var body: some View {
        Cabinet\(sanitizeClassName(cabinet.name))View()
    }
}
```

### With Controls

```swift
struct ArcadeView: View {
    @StateObject private var cabinet = Cabinet\(sanitizeClassName(cabinet.name))()
    
    var body: some View {
        RealityView { content in
            if let entity = cabinet.entity {
                content.add(entity)
            }
        }
        .task { await cabinet.load() }
        .ornament(attachmentAnchor: .scene(.bottom)) {
            Cabinet\(sanitizeClassName(cabinet.name))Controls(cabinet: cabinet)
        }
    }
}
```

### Coin Operation

```swift
// Insert coin
cabinet.insertCoin()

// Start game (requires credits)
cabinet.startGame()

// Check credits
print(cabinet.credits)
```

---
*Generated by RetroVisionCabsConverter*
"""
    }
    
    // MARK: - Helpers
    
    private func sanitizeFileName(_ name: String) -> String {
        let invalidChars = CharacterSet.alphanumerics.inverted
        return name.components(separatedBy: invalidChars).joined(separator: "_")
    }
    
    private func sanitizeClassName(_ name: String) -> String {
        let words = name.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return words.map { $0.capitalized }.joined()
    }
}

// MARK: - Export Result

struct CabinetExportResult {
    var cabinetName: String
    var outputFolder: URL
    var modelPath: URL?
    var videoPath: URL?
    var videoMetadata: VideoConversionResult?
    var texturePaths: [URL] = []
    var audioPaths: [URL] = []
    var shaderPath: URL?
    var metadataPath: URL?
    var swiftCodePath: URL?
    var readmePath: URL?
    var success: Bool = false
    var error: String?
}

struct VideoConversionResult {
    var outputPath: URL?
    var originalFormat: String
    var outputFormat: String
    var codec: String
}

// MARK: - Cabinet Config

struct VisionOSCabinetConfig: Codable {
    var id: String
    var name: String
    var gameName: String
    var year: String
    var manufacturer: String
    
    var model: ModelConfig?
    var screen: ScreenConfig
    var video: VideoConfig?
    var audio: [AudioConfig]?
    var textures: [String]
    var controls: ControlsConfig
    var interaction: InteractionConfig
    
    struct ModelConfig: Codable {
        var file: String
        var scale: Float
    }
    
    struct ScreenConfig: Codable {
        var meshName: String
        var type: String
        var orientation: String
        var aspectRatio: String
    }
    
    struct VideoConfig: Codable {
        var file: String
        var loop: Bool
        var autoplay: Bool
    }
    
    struct AudioConfig: Codable {
        var file: String
        var type: String
        var volume: Float
    }
    
    struct ControlsConfig: Codable {
        var coinSlot: String?
        var joystick: String?
        var buttons: [String]
    }
    
    struct InteractionConfig: Codable {
        var draggable: Bool
        var rotatable: Bool
        var scalable: Bool
        var minScale: Float
        var maxScale: Float
        var playable: Bool
    }
}
