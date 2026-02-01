//
//  VisionOSPropExporter.swift
//  RetroVisionCabsConverter
//
//  Exports props with VisionOS-ready Swift code and assets
//

import Foundation
import AppKit

// MARK: - VisionOS Prop Exporter

class VisionOSPropExporter {
    static let shared = VisionOSPropExporter()
    
    private let fileManager = FileManager.default
    
    // MARK: - Export Options
    
    struct ExportOptions {
        var videoCodec: VideoCodec = .hevc
        var videoQuality: VideoQuality = .high
        var includeSwiftCode: Bool = true
        var includeReadme: Bool = true
        var bundleAsPackage: Bool = false
        
        enum VideoCodec: String, CaseIterable {
            case hevc = "HEVC (H.265)"      // Best for VisionOS
            case h264 = "H.264"              // Compatible fallback
            case prores = "ProRes"           // High quality, large files
            
            var ffmpegCodec: String {
                switch self {
                case .hevc: return "libx265"
                case .h264: return "libx264"
                case .prores: return "prores_ks"
                }
            }
        }
        
        enum VideoQuality: String, CaseIterable {
            case low = "Low (smaller files)"
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
    
    // MARK: - Export Single Prop
    
    func exportProp(
        _ prop: DiscoveredProp,
        to outputFolder: URL,
        options: ExportOptions = ExportOptions(),
        progress: @escaping (Double, String) -> Void
    ) async throws -> PropExportResult {
        
        let propFolder = outputFolder.appendingPathComponent(sanitizeFileName(prop.name))
        try? fileManager.removeItem(at: propFolder)
        try fileManager.createDirectory(at: propFolder, withIntermediateDirectories: true)
        
        // Create subfolders
        let assetsFolder = propFolder.appendingPathComponent("Assets")
        let modelFolder = assetsFolder.appendingPathComponent("Models")
        let textureFolder = assetsFolder.appendingPathComponent("Textures")
        let videoFolder = assetsFolder.appendingPathComponent("Video")
        let audioFolder = assetsFolder.appendingPathComponent("Audio")
        
        try fileManager.createDirectory(at: modelFolder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: textureFolder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: videoFolder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: audioFolder, withIntermediateDirectories: true)
        
        var result = PropExportResult(propName: prop.displayName, outputFolder: propFolder)
        
        // 1. Convert GLB to USDZ
        progress(0.1, "Converting 3D model...")
        if let glbFile = prop.glbFile {
            let usdzPath = modelFolder.appendingPathComponent("\(prop.name).usdz")
            let success = await convertGLBToUSDZ(
                glbFile: glbFile,
                assetsFolder: prop.sourcePath,
                meshMappings: prop.meshMappings,
                outputPath: usdzPath
            )
            if success {
                result.modelPath = usdzPath
            }
        }
        
        // 2. Convert video for VisionOS
        progress(0.3, "Processing video...")
        if let videoInfo = prop.videoInfo {
            let videoResult = await convertVideoForVisionOS(
                input: videoInfo.file,
                outputFolder: videoFolder,
                codec: options.videoCodec,
                quality: options.videoQuality
            )
            result.videoPath = videoResult.outputPath
            result.videoMetadata = videoResult
        }
        
        // 3. Copy textures
        progress(0.5, "Copying textures...")
        for texture in prop.textureFiles {
            let destPath = textureFolder.appendingPathComponent(texture.lastPathComponent)
            try? fileManager.copyItem(at: texture, to: destPath)
            result.texturePaths.append(destPath)
        }
        
        // 4. Copy audio
        progress(0.6, "Copying audio...")
        for audio in prop.audioFiles {
            let destPath = audioFolder.appendingPathComponent(audio.lastPathComponent)
            try? fileManager.copyItem(at: audio, to: destPath)
            result.audioPaths.append(destPath)
        }
        
        // 5. Generate metadata JSON
        progress(0.7, "Generating metadata...")
        let metadata = createVisionOSMetadata(prop: prop, result: result)
        let metadataPath = propFolder.appendingPathComponent("prop_config.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(metadata).write(to: metadataPath)
        result.metadataPath = metadataPath
        
        // 6. Generate Swift code
        if options.includeSwiftCode {
            progress(0.8, "Generating Swift code...")
            let swiftCode = generateSwiftCode(for: prop, result: result)
            let swiftPath = propFolder.appendingPathComponent("Prop\(sanitizeClassName(prop.name)).swift")
            try swiftCode.write(to: swiftPath, atomically: true, encoding: .utf8)
            result.swiftCodePath = swiftPath
        }
        
        // 7. Generate README
        if options.includeReadme {
            progress(0.9, "Generating documentation...")
            let readme = generateReadme(for: prop, result: result)
            let readmePath = propFolder.appendingPathComponent("README.md")
            try readme.write(to: readmePath, atomically: true, encoding: .utf8)
            result.readmePath = readmePath
        }
        
        progress(1.0, "Export complete")
        result.success = true
        return result
    }
    
    // MARK: - Video Conversion
    
    struct VideoConversionResult {
        var outputPath: URL?
        var originalFormat: String
        var outputFormat: String
        var codec: String
        var width: Int?
        var height: Int?
        var duration: Double?
        var fileSize: Int64?
        var isLoopable: Bool = true
    }
    
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
        
        // Determine output filename
        let outputName = input.deletingPathExtension().lastPathComponent
        let outputPath: URL
        
        switch codec {
        case .prores:
            outputPath = outputFolder.appendingPathComponent("\(outputName).mov")
            result.outputFormat = "MOV"
        default:
            outputPath = outputFolder.appendingPathComponent("\(outputName).mp4")
        }
        
        // Get video info first
        if let info = await getVideoInfo(input) {
            result.width = info.width
            result.height = info.height
            result.duration = info.duration
        }
        
        // Check if conversion is needed
        let inputExt = input.pathExtension.lowercased()
        let isVisionOSCompatible = ["mp4", "m4v", "mov"].contains(inputExt)
        
        // Always convert to ensure VisionOS compatibility
        let success = await runFFmpegConversion(
            input: input,
            output: outputPath,
            codec: codec,
            quality: quality
        )
        
        if success {
            result.outputPath = outputPath
            if let attrs = try? fileManager.attributesOfItem(atPath: outputPath.path) {
                result.fileSize = attrs[.size] as? Int64
            }
        } else if isVisionOSCompatible {
            // Fallback: just copy if already compatible
            try? fileManager.copyItem(at: input, to: outputPath)
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
            let ffmpegPath = findFFmpeg()
            guard let ffmpeg = ffmpegPath else {
                print("FFmpeg not found")
                continuation.resume(returning: false)
                return
            }
            
            var arguments: [String] = [
                "-y",                       // Overwrite
                "-i", input.path,           // Input
            ]
            
            switch codec {
            case .hevc:
                arguments += [
                    "-c:v", "libx265",
                    "-tag:v", "hvc1",       // Required for Apple devices
                    "-preset", "medium",
                    "-crf", "\(quality.crf)",
                    "-c:a", "aac",
                    "-b:a", "192k",
                    "-movflags", "+faststart"
                ]
            case .h264:
                arguments += [
                    "-c:v", "libx264",
                    "-profile:v", "high",
                    "-level", "4.2",
                    "-preset", "medium",
                    "-crf", "\(quality.crf)",
                    "-c:a", "aac",
                    "-b:a", "192k",
                    "-movflags", "+faststart"
                ]
            case .prores:
                arguments += [
                    "-c:v", "prores_ks",
                    "-profile:v", "3",      // ProRes 422 HQ
                    "-c:a", "pcm_s16le"
                ]
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
    
    private func getVideoInfo(_ url: URL) async -> (width: Int, height: Int, duration: Double)? {
        return await withCheckedContinuation { continuation in
            guard let ffprobe = findFFprobe() else {
                continuation.resume(returning: nil)
                return
            }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffprobe)
            process.arguments = [
                "-v", "quiet",
                "-print_format", "json",
                "-show_streams",
                url.path
            ]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let streams = json["streams"] as? [[String: Any]] {
                    for stream in streams {
                        if stream["codec_type"] as? String == "video" {
                            let width = stream["width"] as? Int ?? 0
                            let height = stream["height"] as? Int ?? 0
                            let durationStr = stream["duration"] as? String ?? "0"
                            let duration = Double(durationStr) ?? 0
                            continuation.resume(returning: (width, height, duration))
                            return
                        }
                    }
                }
                continuation.resume(returning: nil)
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
    
    // MARK: - GLB to USDZ
    
    private func convertGLBToUSDZ(
        glbFile: URL,
        assetsFolder: URL,
        meshMappings: [String: String],
        outputPath: URL
    ) async -> Bool {
        return await withCheckedContinuation { continuation in
            var textureAssignments: [[String: String]] = []
            for (meshName, assetFile) in meshMappings {
                let assetPath = assetsFolder.appendingPathComponent(assetFile).path
                if fileManager.fileExists(atPath: assetPath) {
                    textureAssignments.append(["mesh": meshName, "texture": assetPath])
                }
            }
            
            let texturesJSON = (try? JSONEncoder().encode(textureAssignments))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            
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

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

try:
    bpy.ops.import_scene.gltf(filepath='\(glbFile.path)')
except Exception as e:
    print(f"Import error: {e}")

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
    print("EXPORT_SUCCESS")
except Exception as e:
    print(f"Export error: {e}")
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
                
                let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let success = output.contains("EXPORT_SUCCESS") && fileManager.fileExists(atPath: outputPath.path)
                continuation.resume(returning: success)
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
    
    // MARK: - VisionOS Metadata
    
    private func createVisionOSMetadata(prop: DiscoveredProp, result: PropExportResult) -> VisionOSPropConfig {
        return VisionOSPropConfig(
            id: prop.id,
            name: prop.displayName,
            type: prop.propType.rawValue,
            placement: prop.placement.rawValue,
            
            model: result.modelPath != nil ? VisionOSPropConfig.ModelConfig(
                file: result.modelPath!.lastPathComponent,
                scale: 1.0
            ) : nil,
            
            video: result.videoPath != nil ? VisionOSPropConfig.VideoConfig(
                file: result.videoPath!.lastPathComponent,
                width: result.videoMetadata?.width ?? 1920,
                height: result.videoMetadata?.height ?? 1080,
                loop: true,
                autoplay: true,
                meshTarget: findVideoMesh(in: prop.glbMeshNames)
            ) : nil,
            
            audio: !result.audioPaths.isEmpty ? result.audioPaths.map {
                VisionOSPropConfig.AudioConfig(file: $0.lastPathComponent, volume: 1.0, loop: false)
            } : nil,
            
            textures: result.texturePaths.map { $0.lastPathComponent },
            
            interaction: VisionOSPropConfig.InteractionConfig(
                blockers: prop.glbMeshNames.filter { $0.lowercased().contains("blocker") },
                triggers: prop.glbMeshNames.filter { $0.lowercased().contains("trigger") }
            ),
            
            dimensions: prop.dimensions,
            author: prop.author,
            tags: prop.tags
        )
    }
    
    // MARK: - Swift Code Generation
    
    private func generateSwiftCode(for prop: DiscoveredProp, result: PropExportResult) -> String {
        let className = "Prop\(sanitizeClassName(prop.name))"
        let modelFile = result.modelPath?.lastPathComponent ?? "\(prop.name).usdz"
        let videoFile = result.videoPath?.lastPathComponent
        
        var code = """
//
//  \(className).swift
//  Generated by RetroVisionCabsConverter
//
//  Prop: \(prop.displayName)
//  Type: \(prop.propType.displayName)
//  Placement: \(prop.placement.displayName)
//
//  Features:
//  - Drag to move in 3D space
//  - Two-finger rotation
//  - Pinch to scale
//  - Hover highlighting (Apple HIG compliant)
//  - Accessibility support
//

import SwiftUI
import RealityKit
import AVFoundation

// MARK: - \(className)

/// A VisionOS prop entity for \(prop.displayName)
/// Supports full interaction: drag, rotate, scale, and hover effects
@MainActor
class \(className): ObservableObject {
    
    // MARK: - Properties
    
    /// The main entity containing the 3D model
    @Published var entity: Entity?
    
    /// Video player for video content (if applicable)
    @Published var videoPlayer: AVPlayer?
    
    /// Audio players for sound effects
    @Published var audioPlayers: [AVAudioPlayer] = []
    
    /// Whether the prop is currently loaded
    @Published var isLoaded = false
    
    /// Error message if loading fails
    @Published var errorMessage: String?
    
    /// Whether the prop is currently being interacted with
    @Published var isSelected = false
    
    /// Current scale of the prop (for gesture handling)
    @Published var currentScale: Float = 1.0
    
    /// Minimum and maximum scale bounds
    let minScale: Float = 0.1
    let maxScale: Float = 5.0
    
    // MARK: - Configuration
    
    static let modelFileName = "\(modelFile)"
"""
        
        if let video = videoFile {
            code += """

    static let videoFileName = "\(video)"
"""
        }
        
        if !result.audioPaths.isEmpty {
            let audioFiles = result.audioPaths.map { "\"\($0.lastPathComponent)\"" }.joined(separator: ", ")
            code += """

    static let audioFileNames = [\(audioFiles)]
"""
        }
        
        code += """

    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Loading
    
    /// Load the prop's 3D model and media
    func load() async {
        do {
            // Load 3D model
            guard let modelURL = Bundle.main.url(forResource: Self.modelFileName.replacingOccurrences(of: ".usdz", with: ""),
                                                  withExtension: "usdz") else {
                errorMessage = "Model file not found: \\(Self.modelFileName)"
                return
            }
            
            entity = try await Entity(contentsOf: modelURL)
            
            // Setup interaction components
            setupInteraction()
            
"""
        
        if videoFile != nil {
            code += """
            // Setup video player
            setupVideoPlayer()
            
"""
        }
        
        if !result.audioPaths.isEmpty {
            code += """
            // Setup audio players
            setupAudioPlayers()
            
"""
        }
        
        code += """
            isLoaded = true
            
        } catch {
            errorMessage = "Failed to load prop: \\(error.localizedDescription)"
        }
    }
    
    // MARK: - Interaction Setup (Apple HIG Compliant)
    
    /// Configure the entity for full interaction support
    private func setupInteraction() {
        guard let entity = entity else { return }
        
        // Generate collision shapes for interaction
        entity.generateCollisionShapes(recursive: true)
        
        // Add input target component for gesture recognition
        entity.components.set(InputTargetComponent(allowedInputTypes: .all))
        
        // Add hover effect component for visual feedback
        entity.components.set(HoverEffectComponent())
        
        // Make entity accessible
        setupAccessibility()
        
        print("Interaction setup complete for \\(Self.modelFileName)")
    }
    
    /// Configure accessibility for VoiceOver and assistive technologies
    private func setupAccessibility() {
        guard let entity = entity else { return }
        
        var accessibilityComponent = AccessibilityComponent()
        accessibilityComponent.label = "\(prop.displayName)"
        accessibilityComponent.value = "\(prop.propType.displayName)"
        accessibilityComponent.traits = [.button]
        accessibilityComponent.isAccessibilityElement = true
        entity.components.set(accessibilityComponent)
    }
    
    // MARK: - Gesture Handling
    
    /// Handle drag gesture to move the prop in 3D space
    func handleDrag(_ value: EntityTargetValue<DragGesture.Value>) {
        guard let entity = entity else { return }
        
        let translation = value.convert(value.translation3D, from: .local, to: .scene)
        entity.position += translation
    }
    
    /// Handle rotation gesture
    func handleRotation(_ angle: Angle, axis: RotationAxis3D = .y) {
        guard let entity = entity else { return }
        
        let rotation = simd_quatf(angle: Float(angle.radians), axis: SIMD3<Float>(axis.x, axis.y, axis.z))
        entity.orientation = rotation * entity.orientation
    }
    
    /// Handle scale gesture with bounds
    func handleScale(_ magnification: CGFloat) {
        guard let entity = entity else { return }
        
        let newScale = currentScale * Float(magnification)
        currentScale = max(minScale, min(maxScale, newScale))
        entity.scale = SIMD3<Float>(repeating: currentScale)
    }
    
    /// Reset transform to original state
    func resetTransform() {
        guard let entity = entity else { return }
        
        entity.position = .zero
        entity.orientation = .init()
        currentScale = 1.0
        entity.scale = SIMD3<Float>(repeating: 1.0)
    }
    
    /// Move prop to specific position
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
    
    /// Rotate prop to face a target position
    func lookAt(_ target: SIMD3<Float>) {
        guard let entity = entity else { return }
        
        entity.look(at: target, from: entity.position, relativeTo: nil)
    }
    
"""
        
        // Video setup
        if videoFile != nil {
            let videoMesh = findVideoMesh(in: prop.glbMeshNames) ?? "screen"
            code += """
    // MARK: - Video
    
    /// Setup video player for the prop's video content
    private func setupVideoPlayer() {
        guard let videoURL = Bundle.main.url(forResource: Self.videoFileName.replacingOccurrences(of: ".mp4", with: ""),
                                              withExtension: "mp4") else {
            print("Video file not found")
            return
        }
        
        let player = AVPlayer(url: videoURL)
        player.isMuted = false
        
        // Loop the video
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
    
    /// Apply video material to the model's screen mesh
    func applyVideoMaterial() {
        guard let entity = entity,
              let player = videoPlayer else { return }
        
        // Find the screen/video mesh
        let targetMeshName = "\(videoMesh)"
        
        entity.visit { entity in
            if let modelEntity = entity as? ModelEntity,
               modelEntity.name.lowercased().contains(targetMeshName.lowercased()) {
                
                // Create video material
                var material = UnlitMaterial()
                
                // Note: For actual video texture, you'll need to create a VideoMaterial
                // This requires setting up an AVPlayerVideoOutput
                
                // For now, apply the player to a VideoPlayerComponent if available
                modelEntity.components[VideoPlayerComponent.self] = VideoPlayerComponent(avPlayer: player)
            }
        }
    }
    
    /// Start playing the video
    func playVideo() {
        videoPlayer?.play()
    }
    
    /// Pause the video
    func pauseVideo() {
        videoPlayer?.pause()
    }
    
    /// Toggle video playback
    func toggleVideo() {
        if videoPlayer?.rate == 0 {
            playVideo()
        } else {
            pauseVideo()
        }
    }
    
"""
        }
        
        // Audio setup
        if !result.audioPaths.isEmpty {
            code += """
    // MARK: - Audio
    
    /// Setup audio players for sound effects
    private func setupAudioPlayers() {
        for fileName in Self.audioFileNames {
            let name = (fileName as NSString).deletingPathExtension
            let ext = (fileName as NSString).pathExtension
            
            guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
                print("Audio file not found: \\(fileName)")
                continue
            }
            
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                audioPlayers.append(player)
            } catch {
                print("Failed to create audio player: \\(error)")
            }
        }
    }
    
    /// Play all audio
    func playAudio() {
        audioPlayers.forEach { $0.play() }
    }
    
    /// Stop all audio
    func stopAudio() {
        audioPlayers.forEach { $0.stop() }
    }
    
"""
        }
        
        // Placement helpers
        code += """
    // MARK: - Placement
    
    /// Place the prop in the scene at the specified position
    func place(in scene: RealityKit.Scene, at position: SIMD3<Float> = .zero) {
        guard let entity = entity else { return }
        
        entity.position = position
        
        // Add to scene's root anchor or create a new one
        let anchor = AnchorEntity(world: position)
        anchor.addChild(entity)
        scene.addAnchor(anchor)
    }
    
    /// Place the prop relative to another entity
    func place(relativeTo parent: Entity, offset: SIMD3<Float> = .zero) {
        guard let entity = entity else { return }
        
        entity.position = offset
        parent.addChild(entity)
    }
    
    // MARK: - Cleanup
    
    /// Clean up resources when the prop is no longer needed
    func cleanup() {
        videoPlayer?.pause()
        videoPlayer = nil
        
        audioPlayers.forEach { $0.stop() }
        audioPlayers.removeAll()
        
        entity?.removeFromParent()
        entity = nil
        
        isLoaded = false
    }
    
    deinit {
        Task { @MainActor in
            cleanup()
        }
    }
}

// MARK: - Interactive SwiftUI View

/// A SwiftUI view that displays this prop with full interaction support
/// - Drag to move in 3D space
/// - Rotate with two-finger gesture
/// - Pinch to scale
/// - Hover highlight (Apple HIG)
struct \(className)View: View {
    @StateObject private var prop = \(className)()
    @State private var initialScale: Float = 1.0
    
    var body: some View {
        RealityView { content in
            if let entity = prop.entity {
                content.add(entity)
"""
        
        if videoFile != nil {
            code += """

                prop.applyVideoMaterial()
                prop.playVideo()
"""
        }
        
        code += """

            }
        } update: { content in
            // Handle updates to the entity
        }
        .gesture(dragGesture)
        .gesture(rotateGesture)
        .gesture(scaleGesture)
        .task {
            await prop.load()
        }
        .onDisappear {
            prop.cleanup()
        }
    }
    
    // MARK: - Gestures
    
    /// Drag gesture for moving the prop in 3D space
    private var dragGesture: some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                prop.handleDrag(value)
            }
    }
    
    /// Rotation gesture for rotating the prop
    private var rotateGesture: some Gesture {
        RotateGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                prop.handleRotation(value.rotation)
            }
    }
    
    /// Magnification gesture for scaling the prop
    private var scaleGesture: some Gesture {
        MagnifyGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                prop.handleScale(value.magnification)
            }
            .onEnded { _ in
                initialScale = prop.currentScale
            }
    }
}

// MARK: - Non-Interactive View (Static Display)

/// A simpler view for displaying the prop without interaction
struct \(className)StaticView: View {
    @StateObject private var prop = \(className)()
    
    var body: some View {
        RealityView { content in
            if let entity = prop.entity {
                content.add(entity)
"""
        
        if videoFile != nil {
            code += """

                prop.applyVideoMaterial()
                prop.playVideo()
"""
        }
        
        code += """

            }
        }
        .task {
            await prop.load()
        }
        .onDisappear {
            prop.cleanup()
        }
    }
}

// MARK: - Ornament Controls

/// A toolbar ornament for controlling the prop
struct \(className)Controls: View {
    @ObservedObject var prop: \(className)
    
    var body: some View {
        HStack(spacing: 20) {
            // Reset button
            Button {
                prop.resetTransform()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
"""
        
        if videoFile != nil {
            code += """

            
            // Video controls
            Button {
                prop.toggleVideo()
            } label: {
                Label("Play/Pause", systemImage: "play.pause")
            }
"""
        }
        
        code += """

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
    
    private func generateReadme(for prop: DiscoveredProp, result: PropExportResult) -> String {
        var readme = """
# \(prop.displayName)

A VisionOS prop for use in RealityKit immersive experiences.

## Prop Information

| Property | Value |
|----------|-------|
| **Type** | \(prop.propType.displayName) |
| **Placement** | \(prop.placement.displayName) |
| **Author** | \(prop.author ?? "Unknown") |
| **Has Video** | \(result.videoPath != nil ? "Yes" : "No") |
| **Has Audio** | \(!result.audioPaths.isEmpty ? "Yes" : "No") |

"""
        
        if let dims = prop.dimensions {
            readme += """
### Dimensions

- Width: \(String(format: "%.2f", dims.width)) meters
- Height: \(String(format: "%.2f", dims.height)) meters
- Depth: \(String(format: "%.2f", dims.depth)) meters

"""
        }
        
        readme += """
## Files Included

```
\(result.outputFolder.lastPathComponent)/
├── Assets/
│   ├── Models/
│   │   └── \(result.modelPath?.lastPathComponent ?? "model.usdz")
"""
        
        if let video = result.videoPath {
            readme += """

│   ├── Video/
│   │   └── \(video.lastPathComponent)
"""
        }
        
        if !result.texturePaths.isEmpty {
            readme += """

│   ├── Textures/
"""
            for texture in result.texturePaths {
                readme += """

│   │   └── \(texture.lastPathComponent)
"""
            }
        }
        
        if !result.audioPaths.isEmpty {
            readme += """

│   └── Audio/
"""
            for audio in result.audioPaths {
                readme += """

│       └── \(audio.lastPathComponent)
"""
            }
        }
        
        readme += """

├── prop_config.json
├── Prop\(sanitizeClassName(prop.name)).swift
└── README.md
```

## Interactive Features (Apple HIG Compliant)

This prop includes full interaction support following Apple's Human Interface Guidelines for visionOS:

| Gesture | Action | Description |
|---------|--------|-------------|
| **Drag** | Move | Drag the prop to move it in 3D space |
| **Rotate** | Spin | Two-finger rotate to spin the prop |
| **Pinch** | Scale | Pinch to make the prop larger or smaller |
| **Look** | Highlight | Looking at the prop shows a subtle highlight |

### Accessibility

- VoiceOver support with descriptive labels
- Full accessibility traits for assistive technologies

## Integration Guide

### Step 1: Add Files to Your Xcode Project

1. Drag the `Assets` folder into your Xcode project
2. Make sure "Copy items if needed" is checked
3. Add to your app target

### Step 2: Add the Swift File

1. Drag `Prop\(sanitizeClassName(prop.name)).swift` into your project
2. Add to your app target

### Step 3: Use Interactive View

```swift
import SwiftUI
import RealityKit

struct ContentView: View {
    var body: some View {
        // Interactive version - user can move, rotate, scale
        Prop\(sanitizeClassName(prop.name))View()
    }
}
```

### Step 4: Use Static View (No Interaction)

```swift
struct ContentView: View {
    var body: some View {
        // Static version - display only, no gestures
        Prop\(sanitizeClassName(prop.name))StaticView()
    }
}
```

### Step 5: Add Control Ornament

```swift
struct ContentView: View {
    @StateObject private var prop = Prop\(sanitizeClassName(prop.name))()
    
    var body: some View {
        RealityView { content in
            if let entity = prop.entity {
                content.add(entity)
            }
        }
        .task { await prop.load() }
        .ornament(attachmentAnchor: .scene(.bottom)) {
            Prop\(sanitizeClassName(prop.name))Controls(prop: prop)
        }
    }
}
```

### Step 6: Manual Control

```swift
@StateObject private var prop = Prop\(sanitizeClassName(prop.name))()

// Load the prop
await prop.load()

// Place in scene
if let entity = prop.entity {
    content.add(entity)
}
"""
        
        if result.videoPath != nil {
            readme += """


// Control video playback
prop.playVideo()
prop.pauseVideo()
prop.toggleVideo()
"""
        }
        
        if !result.audioPaths.isEmpty {
            readme += """


// Control audio
prop.playAudio()
prop.stopAudio()
"""
        }
        
        readme += """


// Interactive methods
prop.moveTo(SIMD3<Float>(0, 1, -2), animated: true)  // Move with animation
prop.lookAt(SIMD3<Float>(0, 0, 0))                    // Face a point
prop.resetTransform()                                  // Reset to original

// Scale control
prop.handleScale(1.5)  // Make 50% larger
prop.currentScale      // Get current scale (0.1 to 5.0)

// Cleanup when done
prop.cleanup()
```

## Video Configuration

"""
        
        if let video = result.videoMetadata {
            readme += """
| Property | Value |
|----------|-------|
| **Original Format** | \(video.originalFormat) |
| **Output Format** | \(video.outputFormat) |
| **Codec** | \(video.codec) |
| **Resolution** | \(video.width ?? 0) × \(video.height ?? 0) |
| **Duration** | \(String(format: "%.1f", video.duration ?? 0)) seconds |
| **File Size** | \(formatFileSize(video.fileSize ?? 0)) |
| **Loopable** | \(video.isLoopable ? "Yes" : "No") |

"""
        } else {
            readme += "No video included.\n\n"
        }
        
        readme += """
## VisionOS Requirements

- visionOS 1.0+
- Xcode 15.0+
- RealityKit framework
- AVFoundation framework (for video/audio)

## Notes

- The USDZ model has been optimized for VisionOS
- Video is encoded in HEVC (H.265) for best performance on Apple Silicon
- Audio files are in their original format (MP3/WAV/M4A)

---

*Generated by RetroVisionCabsConverter*
"""
        
        return readme
    }
    
    // MARK: - Helpers
    
    private func findFFmpeg() -> String? {
        let paths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        return paths.first { fileManager.fileExists(atPath: $0) }
    }
    
    private func findFFprobe() -> String? {
        let paths = ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe", "/usr/bin/ffprobe"]
        return paths.first { fileManager.fileExists(atPath: $0) }
    }
    
    private func sanitizeFileName(_ name: String) -> String {
        let invalidChars = CharacterSet.alphanumerics.inverted
        return name.components(separatedBy: invalidChars).joined(separator: "_")
    }
    
    private func sanitizeClassName(_ name: String) -> String {
        let words = name.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return words.map { $0.capitalized }.joined()
    }
    
    private func findVideoMesh(in meshNames: [String]) -> String? {
        let keywords = ["screen", "display", "video", "tv", "monitor", "painting", "crt"]
        for mesh in meshNames {
            let lower = mesh.lowercased()
            for keyword in keywords {
                if lower.contains(keyword) {
                    return mesh
                }
            }
        }
        return meshNames.first
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Export Result

struct PropExportResult {
    var propName: String
    var outputFolder: URL
    var modelPath: URL?
    var videoPath: URL?
    var videoMetadata: VisionOSPropExporter.VideoConversionResult?
    var texturePaths: [URL] = []
    var audioPaths: [URL] = []
    var metadataPath: URL?
    var swiftCodePath: URL?
    var readmePath: URL?
    var success: Bool = false
}

// MARK: - VisionOS Config

struct VisionOSPropConfig: Codable {
    var id: String
    var name: String
    var type: String
    var placement: String
    
    var model: ModelConfig?
    var video: VideoConfig?
    var audio: [AudioConfig]?
    var textures: [String]
    var interaction: InteractionConfig
    var dimensions: PropDimensions?
    var author: String?
    var tags: [String]
    
    struct ModelConfig: Codable {
        var file: String
        var scale: Float
    }
    
    struct VideoConfig: Codable {
        var file: String
        var width: Int
        var height: Int
        var loop: Bool
        var autoplay: Bool
        var meshTarget: String?
    }
    
    struct AudioConfig: Codable {
        var file: String
        var volume: Float
        var loop: Bool
    }
    
    struct InteractionConfig: Codable {
        var blockers: [String]
        var triggers: [String]
    }
}
