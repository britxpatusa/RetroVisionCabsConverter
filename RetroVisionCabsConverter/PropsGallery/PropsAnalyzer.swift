//
//  PropsAnalyzer.swift
//  RetroVisionCabsConverter
//
//  Scans folders for non-cabinet props and analyzes their content
//

import Foundation
import AppKit

// MARK: - Props Analyzer

class PropsAnalyzer {
    static let shared = PropsAnalyzer()
    
    private let fileManager = FileManager.default
    private let tempDirectory: URL
    
    // Supported file extensions
    private let modelExtensions = ["glb", "gltf"]
    private let textureExtensions = ["png", "jpg", "jpeg", "tga", "bmp"]
    private let videoExtensions = ["mp4", "m4v", "mov", "mkv", "avi", "webm"]
    private let audioExtensions = ["mp3", "wav", "m4a", "ogg", "aac"]
    
    init() {
        tempDirectory = URL(fileURLWithPath: RetroVisionPaths.load().galleryTempDir)
            .deletingLastPathComponent()
            .appendingPathComponent("PropsExtract")
        try? fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Scanning
    
    /// Scan a folder for props
    func scanFolder(_ folderURL: URL, progress: @escaping (Double, String) -> Void) async throws -> [DiscoveredProp] {
        var props: [DiscoveredProp] = []
        
        progress(0.0, "Scanning for props...")
        
        // Get all items in folder
        let contents = try fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.isDirectoryKey])
        let total = Double(contents.count)
        
        for (index, itemURL) in contents.enumerated() {
            progress(Double(index) / total, "Analyzing: \(itemURL.lastPathComponent)")
            
            // Check if it's a folder or ZIP
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDirectory)
            
            if isDirectory.boolValue {
                // Analyze folder
                if let prop = await analyzePropFolder(itemURL) {
                    props.append(prop)
                }
            } else if itemURL.pathExtension.lowercased() == "zip" {
                // Extract and analyze ZIP
                if let prop = await analyzeZipFile(itemURL) {
                    props.append(prop)
                }
            }
        }
        
        progress(1.0, "Found \(props.count) prop(s)")
        return props
    }
    
    // MARK: - Folder Analysis
    
    /// Analyze a single prop folder
    func analyzePropFolder(_ folderURL: URL) async -> DiscoveredProp? {
        let folderName = folderURL.lastPathComponent
        
        // Check for description.yaml
        let yamlPath = folderURL.appendingPathComponent("description.yaml")
        guard fileManager.fileExists(atPath: yamlPath.path) else {
            // No YAML = not a valid prop pack
            return nil
        }
        
        // Create prop
        var prop = DiscoveredProp(
            id: "\(folderName)_\(folderURL.path.hashValue)",
            name: folderName,
            displayName: folderName.replacingOccurrences(of: "-", with: " ").capitalized,
            sourcePath: folderURL,
            sourceType: .folder
        )
        
        // Parse YAML
        if let yamlContent = try? String(contentsOf: yamlPath, encoding: .utf8) {
            parseYAML(yamlContent, into: &prop, baseFolder: folderURL)
        }
        
        // Find GLB file
        if let glbFiles = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
            .filter({ modelExtensions.contains($0.pathExtension.lowercased()) }) {
            prop.glbFile = glbFiles.first
        }
        
        // Find textures
        if let allFiles = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) {
            prop.textureFiles = allFiles.filter { textureExtensions.contains($0.pathExtension.lowercased()) }
            
            // Find video files
            let videoFiles = allFiles.filter { videoExtensions.contains($0.pathExtension.lowercased()) }
            if let firstVideo = videoFiles.first {
                prop.videoInfo = PropVideoInfo(
                    file: firstVideo,
                    format: firstVideo.pathExtension.lowercased(),
                    needsConversion: !["mp4", "m4v", "mov"].contains(firstVideo.pathExtension.lowercased())
                )
            }
            
            // Find audio files
            prop.audioFiles = allFiles.filter { audioExtensions.contains($0.pathExtension.lowercased()) }
        }
        
        // Analyze GLB for meshes and dimensions
        if let glbURL = prop.glbFile {
            let analysis = await analyzeGLB(glbURL)
            prop.glbMeshNames = analysis.meshNames
            prop.dimensions = analysis.dimensions
        }
        
        // Infer prop type
        prop.propType = inferPropType(from: prop)
        prop.placement = inferPlacement(from: prop)
        
        return prop
    }
    
    // MARK: - ZIP Analysis
    
    /// Analyze a ZIP file containing a prop
    func analyzeZipFile(_ zipURL: URL) async -> DiscoveredProp? {
        let zipName = zipURL.deletingPathExtension().lastPathComponent
        
        // Validate ZIP before extraction (security check)
        let validation = ZIPValidator.validate(zipURL)
        if !validation.valid {
            SecurityLogger.shared.log(SecurityLogger.SecurityEvent(
                type: .zipExtraction,
                severity: .error,
                message: "Prop ZIP validation failed for \(zipURL.lastPathComponent): \(validation.error ?? "unknown")"
            ))
            print("ZIP validation failed: \(validation.error ?? "unknown error")")
            return nil
        }
        
        let extractFolder = tempDirectory.appendingPathComponent(zipName)
        
        // Clean up existing extraction
        try? fileManager.removeItem(at: extractFolder)
        try? fileManager.createDirectory(at: extractFolder, withIntermediateDirectories: true)
        
        // Extract ZIP
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", zipURL.path, "-d", extractFolder.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            
            guard process.terminationStatus == 0 else {
                print("Failed to extract ZIP: \(zipURL.lastPathComponent)")
                return nil
            }
        } catch {
            print("ZIP extraction error: \(error)")
            return nil
        }
        
        // Find the actual prop folder (may be nested)
        var propFolder = extractFolder
        if let contents = try? fileManager.contentsOfDirectory(at: extractFolder, includingPropertiesForKeys: [.isDirectoryKey]) {
            // Check if there's a single subfolder
            let folders = contents.filter { url in
                var isDir: ObjCBool = false
                return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            }
            if folders.count == 1 {
                propFolder = folders[0]
            }
        }
        
        // Analyze the extracted folder
        guard var prop = await analyzePropFolder(propFolder) else {
            return nil
        }
        
        // Update source info
        prop.id = "\(zipName)_\(zipURL.path.hashValue)"
        prop.sourceType = .zip
        
        return prop
    }
    
    // MARK: - YAML Parsing
    
    /// Parse description.yaml into prop
    private func parseYAML(_ content: String, into prop: inout DiscoveredProp, baseFolder: URL) {
        let lines = content.components(separatedBy: .newlines)
        var currentSection: String?
        var currentPart: String?
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            
            // Check for section headers
            if trimmed.hasPrefix("model:") {
                currentSection = "model"
                continue
            } else if trimmed.hasPrefix("video:") {
                currentSection = "video"
                continue
            } else if trimmed.hasPrefix("parts:") {
                currentSection = "parts"
                continue
            } else if trimmed.hasPrefix("crt:") {
                currentSection = "crt"
                continue
            }
            
            // Parse key-value pairs
            if let colonIndex = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                
                if !value.isEmpty {
                    switch key {
                    case "name":
                        prop.displayName = value
                    case "author":
                        prop.author = value
                    case "version":
                        prop.version = value
                    case "game":
                        prop.theme = value
                    case "file":
                        if currentSection == "model" {
                            prop.glbFile = baseFolder.appendingPathComponent(value)
                        } else if currentSection == "video" {
                            let videoURL = baseFolder.appendingPathComponent(value)
                            prop.videoInfo = PropVideoInfo(
                                file: videoURL,
                                format: videoURL.pathExtension.lowercased(),
                                needsConversion: !["mp4", "m4v", "mov"].contains(videoURL.pathExtension.lowercased())
                            )
                        } else if currentPart != nil {
                            // Part texture mapping
                            prop.meshMappings[currentPart!] = value
                        }
                    case "- name":
                        currentPart = value
                    case "type":
                        if currentSection == "parts", let part = currentPart {
                            // Could use this to identify blockers, etc.
                            if value == "blocker" {
                                // Track interaction zones
                            }
                        }
                    default:
                        break
                    }
                }
            }
            
            // Handle part definitions
            if trimmed.hasPrefix("- name:") {
                currentPart = trimmed.replacingOccurrences(of: "- name:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
    }
    
    // MARK: - GLB Analysis
    
    struct GLBAnalysisResult {
        var meshNames: [String]
        var dimensions: PropDimensions?
    }
    
    /// Analyze a GLB file using Blender
    func analyzeGLB(_ glbURL: URL) async -> GLBAnalysisResult {
        return await withCheckedContinuation { continuation in
            let script = """
            import bpy
            import json
            import mathutils
            
            # Clear scene
            bpy.ops.object.select_all(action='SELECT')
            bpy.ops.object.delete()
            
            # Import GLB
            try:
                bpy.ops.import_scene.gltf(filepath='\(glbURL.path)')
            except Exception as e:
                print(f"PROP_ANALYSIS_ERROR: {e}")
                print("PROP_ANALYSIS_RESULT:{}")
                quit()
            
            # Collect mesh names
            meshes = []
            for obj in bpy.data.objects:
                if obj.type == 'MESH':
                    meshes.append(obj.name)
            
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
            
            # Calculate dimensions
            if min_coords[0] != float('inf'):
                width = round(max_coords[0] - min_coords[0], 4)
                height = round(max_coords[2] - min_coords[2], 4)  # Z is up in Blender
                depth = round(max_coords[1] - min_coords[1], 4)
            else:
                width = height = depth = 0
            
            result = {
                "meshes": meshes,
                "width": width,
                "height": height,
                "depth": depth
            }
            
            print(f"PROP_ANALYSIS_RESULT:{json.dumps(result)}")
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
                
                // Parse result
                if let resultLine = outputString.components(separatedBy: "\n").first(where: { $0.contains("PROP_ANALYSIS_RESULT:") }),
                   let jsonStart = resultLine.range(of: "PROP_ANALYSIS_RESULT:")?.upperBound {
                    let jsonString = String(resultLine[jsonStart...])
                    if let jsonData = jsonString.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        let meshes = json["meshes"] as? [String] ?? []
                        let width = json["width"] as? Double ?? 0
                        let height = json["height"] as? Double ?? 0
                        let depth = json["depth"] as? Double ?? 0
                        
                        let dimensions = (width > 0 || height > 0 || depth > 0)
                            ? PropDimensions(width: width, height: height, depth: depth)
                            : nil
                        
                        continuation.resume(returning: GLBAnalysisResult(meshNames: meshes, dimensions: dimensions))
                        return
                    }
                }
                
                continuation.resume(returning: GLBAnalysisResult(meshNames: [], dimensions: nil))
            } catch {
                print("GLB analysis error: \(error)")
                continuation.resume(returning: GLBAnalysisResult(meshNames: [], dimensions: nil))
            }
        }
    }
    
    // MARK: - Type Inference
    
    /// Infer prop type from its characteristics
    func inferPropType(from prop: DiscoveredProp) -> PropType {
        let nameLower = prop.name.lowercased()
        let meshNames = prop.glbMeshNames.map { $0.lowercased() }
        
        // Check name hints
        if nameLower.contains("cutout") || nameLower.contains("standee") {
            return .cutout
        }
        if nameLower.contains("stage") || nameLower.contains("disco") {
            return .stage
        }
        if nameLower.contains("light") || nameLower.contains("neon") || nameLower.contains("lamp") {
            return .lighting
        }
        if nameLower.contains("table") || nameLower.contains("chair") || nameLower.contains("sofa") {
            return .furniture
        }
        if nameLower.contains("poster") || nameLower.contains("painting") || nameLower.contains("frame") {
            return .wall
        }
        
        // Check mesh names for hints
        if meshNames.contains(where: { $0.contains("painting") || $0.contains("cutout") }) {
            return .cutout
        }
        
        // Check dimensions - flat objects are likely cutouts
        if let dims = prop.dimensions, dims.isFlat {
            return .cutout
        }
        
        // Has video = video display or cutout with video
        if prop.hasVideo {
            if let dims = prop.dimensions, dims.isFlat {
                return .cutout
            }
            return .videoDisplay
        }
        
        return .decoration
    }
    
    /// Infer placement from prop type and dimensions
    func inferPlacement(from prop: DiscoveredProp) -> PlacementHint {
        switch prop.propType {
        case .cutout:
            return .wall
        case .wall:
            return .wall
        case .lighting:
            return .ceiling
        case .floor:
            return .floor
        case .stage:
            return .floor
        case .furniture:
            return .floor
        case .decoration, .videoDisplay:
            if let dims = prop.dimensions {
                // Tall items likely go on floor
                if dims.height > dims.width && dims.height > 1.0 {
                    return .floor
                }
                // Wide flat items go on wall
                if dims.isFlat {
                    return .wall
                }
            }
            return .freestanding
        case .unknown:
            return .freestanding
        }
    }
}
