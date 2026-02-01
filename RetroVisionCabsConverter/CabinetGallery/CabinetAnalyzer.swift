import Foundation

// MARK: - Cabinet Analyzer

/// Scans folders for Age of Joy cabinet packs and analyzes their contents
class CabinetAnalyzer {
    
    static let shared = CabinetAnalyzer()
    
    private let fileManager = FileManager.default
    private let tempDirectory: URL
    
    init() {
        // Use configured temp for extraction to avoid filling system disk
        let paths = RetroVisionPaths.load()
        tempDirectory = URL(fileURLWithPath: paths.galleryExtractDir)
        try? fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Public API
    
    /// Scan a folder for cabinet packs (folders and ZIPs)
    func scanFolder(_ folderURL: URL, progress: @escaping (Double, String) -> Void) async throws -> [DiscoveredCabinet] {
        var cabinets: [DiscoveredCabinet] = []
        
        // Get all items in folder
        let contents = try fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.isDirectoryKey])
        let items = contents.filter { !$0.lastPathComponent.hasPrefix(".") }
        
        let total = Double(items.count)
        var current = 0.0
        
        for item in items {
            current += 1
            let itemName = item.lastPathComponent
            progress(current / total, "Scanning: \(itemName)")
            
            // Check if it's a directory
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory)
            
            if isDirectory.boolValue {
                // Check if it's a cabinet folder or a pack containing ZIPs
                if let cabinet = try? await analyzeCabinetFolder(item) {
                    cabinets.append(cabinet)
                } else {
                    // Check for ZIPs inside (cabinet pack folder)
                    let subContents = try? fileManager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)
                    let zips = subContents?.filter { $0.pathExtension.lowercased() == "zip" } ?? []
                    
                    for zip in zips {
                        if let cabinet = try? await analyzeZipFile(zip) {
                            cabinets.append(cabinet)
                        }
                    }
                }
            } else if item.pathExtension.lowercased() == "zip" {
                // Direct ZIP file
                if let cabinet = try? await analyzeZipFile(item) {
                    cabinets.append(cabinet)
                }
            }
        }
        
        progress(1.0, "Scan complete")
        return cabinets
    }
    
    // MARK: - Folder Analysis
    
    /// Analyze a cabinet folder
    func analyzeCabinetFolder(_ folderURL: URL) async throws -> DiscoveredCabinet? {
        let yamlURL = folderURL.appendingPathComponent("description.yaml")
        
        // Must have description.yaml to be a valid cabinet
        guard fileManager.fileExists(atPath: yamlURL.path) else {
            return nil
        }
        
        let folderName = folderURL.lastPathComponent
        
        // Create unique ID using folder path hash to avoid duplicates
        let uniqueID = "\(folderName)_\(folderURL.path.hashValue)"
        
        var cabinet = DiscoveredCabinet(
            id: uniqueID,
            name: folderName,
            displayName: folderName.capitalized.replacingOccurrences(of: "_", with: " "),
            sourcePath: folderURL,
            sourceType: .folder
        )
        
        // Parse YAML
        var crtOrientation: String? = nil
        if let description = parseYAML(yamlURL) {
            cabinet.game = description.game ?? description.name
            cabinet.rom = description.rom
            cabinet.author = description.cabinetAuthor
            cabinet.year = description.year.map { String($0) }
            
            if let name = description.name {
                cabinet.displayName = name.capitalized
            }
            
            // Get CRT orientation
            crtOrientation = description.crt?.orientation
            
            // Get GLB file
            if let modelFile = description.model?.file {
                let glbURL = folderURL.appendingPathComponent(modelFile)
                if fileManager.fileExists(atPath: glbURL.path) {
                    cabinet.glbFile = glbURL
                }
            }
            
            // Get video file
            if let videoFile = description.video?.file {
                let videoURL = folderURL.appendingPathComponent(videoFile)
                if fileManager.fileExists(atPath: videoURL.path) {
                    cabinet.videoFile = videoURL
                }
            }
            
            // Build mesh mappings from YAML parts
            if let parts = description.parts {
                for part in parts {
                    if let artFile = part.art?.file {
                        cabinet.meshMappings[part.name] = artFile
                    }
                }
            }
        }
        
        // Find GLB if not specified in YAML
        if cabinet.glbFile == nil {
            let glbFiles = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "glb" }
            cabinet.glbFile = glbFiles?.first
        }
        
        // Discover image assets
        cabinet.assets = discoverAssets(in: folderURL)
        
        // Auto-map unmapped assets
        autoMapAssets(&cabinet)
        
        // Analyze GLB meshes and dimensions if available
        if let glbURL = cabinet.glbFile {
            let analysis = await analyzeGLB(glbURL)
            cabinet.glbMeshNames = analysis.meshNames
            cabinet.dimensions = analysis.dimensions
            cabinet.cabinetShape = analyzeShape(meshNames: analysis.meshNames, crtOrientation: crtOrientation)
        }
        
        // Suggest template based on mesh names (fallback)
        cabinet.suggestedTemplateID = suggestTemplate(meshNames: cabinet.glbMeshNames)
        
        return cabinet
    }
    
    // MARK: - ZIP Analysis
    
    /// Analyze a ZIP file containing a cabinet
    func analyzeZipFile(_ zipURL: URL) async throws -> DiscoveredCabinet? {
        let zipName = zipURL.deletingPathExtension().lastPathComponent
        let extractDir = tempDirectory.appendingPathComponent(zipName)
        
        // Clean and extract
        try? fileManager.removeItem(at: extractDir)
        try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        // Extract ZIP
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", zipURL.path, "-d", extractDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            return nil
        }
        
        // Check for nested folder
        var cabinetDir = extractDir
        let contents = try? fileManager.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { !$0.lastPathComponent.hasPrefix(".") && !$0.lastPathComponent.hasPrefix("__MACOSX") }
        
        if let singleItem = contents?.first,
           contents?.count == 1,
           (try? singleItem.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            cabinetDir = singleItem
        }
        
        // Analyze as folder
        if var cabinet = try? await analyzeCabinetFolder(cabinetDir) {
            cabinet.sourceType = .zip
            cabinet.sourcePath = zipURL
            // Use unique ID based on ZIP path
            cabinet.id = "\(zipName)_\(zipURL.path.hashValue)"
            cabinet.name = zipName
            if cabinet.displayName == cabinetDir.lastPathComponent.capitalized {
                cabinet.displayName = zipName.capitalized
            }
            return cabinet
        }
        
        return nil
    }
    
    // MARK: - YAML Parsing
    
    /// Parse description.yaml file (simple parser for AoJ YAML format)
    func parseYAML(_ url: URL) -> GalleryCabinetDescription? {
        guard let yamlString = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        
        // Simple YAML parser for AoJ cabinet description files
        var name: String?
        var game: String?
        var rom: String?
        var year: Int?
        var author: String?
        var modelFile: String?
        var videoFile: String?
        var material: String?
        var parts: [GalleryCabinetDescription.PartDescription] = []
        var crtOrientation: String?
        
        var currentPart: (name: String, type: String?, artFile: String?, color: GalleryCabinetDescription.ColorDescription?)?
        var inParts = false
        var inModel = false
        var inVideo = false
        var inArt = false
        var inColor = false
        var inCRT = false
        
        var colorR: Int?
        var colorG: Int?
        var colorB: Int?
        var colorIntensity: Double?
        
        for line in yamlString.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            
            let indent = line.prefix(while: { $0 == " " }).count
            
            // Reset context based on indent
            if indent == 0 {
                inParts = false
                inModel = false
                inVideo = false
                inCRT = false
            }
            if indent <= 2 {
                inArt = false
                inColor = false
            }
            
            // Parse key-value
            if let colonIndex = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                var value = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                
                // Remove quotes if present
                if value.hasPrefix("\"") && value.hasSuffix("\"") {
                    value = String(value.dropFirst().dropLast())
                }
                
                // Top-level keys
                if indent == 0 {
                    switch key {
                    case "name": name = value
                    case "game": game = value
                    case "rom": rom = value
                    case "year": year = Int(value)
                    case "cabinet author": author = value
                    case "material": material = value
                    case "model": inModel = true
                    case "video": inVideo = true
                    case "parts": inParts = true
                    case "crt": inCRT = true
                    default: break
                    }
                }
                // Model section
                else if inModel && indent == 2 {
                    if key == "file" { modelFile = value }
                }
                // Video section
                else if inVideo && indent == 2 {
                    if key == "file" { videoFile = value }
                }
                // CRT section
                else if inCRT && indent == 2 {
                    if key == "orientation" { crtOrientation = value }
                }
                // Parts section
                else if inParts {
                    if trimmed.hasPrefix("- name:") {
                        // Save previous part
                        if let current = currentPart {
                            let colorDesc = (colorR != nil || colorG != nil || colorB != nil) ?
                                GalleryCabinetDescription.ColorDescription(r: colorR, g: colorG, b: colorB, intensity: colorIntensity) : nil
                            parts.append(GalleryCabinetDescription.PartDescription(
                                name: current.name,
                                type: current.type,
                                art: current.artFile != nil ? GalleryCabinetDescription.ArtDescription(file: current.artFile, invertx: nil, inverty: nil, rotate: nil) : nil,
                                color: colorDesc,
                                material: nil
                            ))
                        }
                        // Start new part
                        currentPart = (name: value, type: nil, artFile: nil, color: nil)
                        colorR = nil; colorG = nil; colorB = nil; colorIntensity = nil
                        inArt = false
                        inColor = false
                    }
                    else if key == "type" && currentPart != nil {
                        currentPart?.type = value
                    }
                    else if key == "art" {
                        inArt = true
                        inColor = false
                    }
                    else if key == "color" {
                        inColor = true
                        inArt = false
                    }
                    else if inArt && key == "file" {
                        currentPart?.artFile = value
                    }
                    else if inColor {
                        switch key {
                        case "r": colorR = Int(value)
                        case "g": colorG = Int(value)
                        case "b": colorB = Int(value)
                        case "intensity": colorIntensity = Double(value)
                        default: break
                        }
                    }
                }
            }
        }
        
        // Save last part
        if let current = currentPart {
            let colorDesc = (colorR != nil || colorG != nil || colorB != nil) ?
                GalleryCabinetDescription.ColorDescription(r: colorR, g: colorG, b: colorB, intensity: colorIntensity) : nil
            parts.append(GalleryCabinetDescription.PartDescription(
                name: current.name,
                type: current.type,
                art: current.artFile != nil ? GalleryCabinetDescription.ArtDescription(file: current.artFile, invertx: nil, inverty: nil, rotate: nil) : nil,
                color: colorDesc,
                material: nil
            ))
        }
        
        return GalleryCabinetDescription(
            name: name,
            game: game,
            rom: rom,
            year: year,
            cabinetAuthor: author,
            model: modelFile != nil ? GalleryCabinetDescription.ModelDescription(file: modelFile) : nil,
            video: videoFile != nil ? GalleryCabinetDescription.VideoDescription(file: videoFile, invertx: nil, inverty: nil) : nil,
            material: material,
            parts: parts.isEmpty ? nil : parts,
            crt: crtOrientation != nil ? GalleryCabinetDescription.CRTDescription(type: nil, orientation: crtOrientation) : nil
        )
    }
    
    // MARK: - Asset Discovery
    
    /// Discover image assets in a folder
    func discoverAssets(in folderURL: URL) -> [DiscoveredAsset] {
        var assets: [DiscoveredAsset] = []
        
        let imageExtensions = ["png", "jpg", "jpeg"]
        
        guard let contents = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else {
            return assets
        }
        
        for file in contents {
            let ext = file.pathExtension.lowercased()
            if imageExtensions.contains(ext) {
                assets.append(DiscoveredAsset(url: file))
            }
        }
        
        return assets
    }
    
    /// Auto-map assets to meshes based on filename patterns
    func autoMapAssets(_ cabinet: inout DiscoveredCabinet) {
        for asset in cabinet.assets {
            if let meshName = asset.inferredMeshName {
                // Don't overwrite YAML-specified mappings
                if cabinet.meshMappings[meshName] == nil {
                    cabinet.meshMappings[meshName] = asset.filename
                }
            }
        }
    }
    
    // MARK: - GLB Analysis
    
    /// Result of GLB analysis
    struct GLBAnalysisResult {
        let meshNames: [String]
        let dimensions: CabinetDimensions?
    }
    
    /// Analyze GLB file to extract mesh names and bounding box dimensions
    func analyzeGLB(_ glbURL: URL) async -> GLBAnalysisResult {
        return await withCheckedContinuation { continuation in
            let script = """
            import bpy
            import json
            from mathutils import Vector

            # Clear scene
            bpy.ops.object.select_all(action='SELECT')
            bpy.ops.object.delete()

            # Import GLB
            bpy.ops.import_scene.gltf(filepath='\(glbURL.path)')

            # Get mesh names
            meshes = [o.name for o in bpy.data.objects if o.type == 'MESH']

            # Calculate overall bounding box
            min_coord = Vector((float('inf'), float('inf'), float('inf')))
            max_coord = Vector((float('-inf'), float('-inf'), float('-inf')))

            for obj in bpy.data.objects:
                if obj.type == 'MESH':
                    # Get world-space bounding box corners
                    bbox_corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
                    for corner in bbox_corners:
                        min_coord.x = min(min_coord.x, corner.x)
                        min_coord.y = min(min_coord.y, corner.y)
                        min_coord.z = min(min_coord.z, corner.z)
                        max_coord.x = max(max_coord.x, corner.x)
                        max_coord.y = max(max_coord.y, corner.y)
                        max_coord.z = max(max_coord.z, corner.z)

            # Calculate dimensions
            if min_coord.x != float('inf'):
                width = max_coord.x - min_coord.x
                height = max_coord.z - min_coord.z  # Z is up in Blender default
                depth = max_coord.y - min_coord.y
                dims = {'width': round(width, 4), 'height': round(height, 4), 'depth': round(depth, 4)}
            else:
                dims = None

            result = {'meshes': meshes, 'dimensions': dims}
            print('GLB_ANALYSIS:' + json.dumps(result))
            """
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/Applications/Blender.app/Contents/MacOS/Blender")
            process.arguments = ["-b", "--factory-startup", "--python-expr", script]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8),
                   let jsonLine = output.components(separatedBy: "\n").first(where: { $0.hasPrefix("GLB_ANALYSIS:") }),
                   let jsonString = jsonLine.components(separatedBy: "GLB_ANALYSIS:").last,
                   let jsonData = jsonString.data(using: .utf8),
                   let result = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    
                    let meshes = result["meshes"] as? [String] ?? []
                    var dimensions: CabinetDimensions? = nil
                    
                    if let dims = result["dimensions"] as? [String: Double] {
                        dimensions = CabinetDimensions(
                            width: dims["width"] ?? 0,
                            height: dims["height"] ?? 0,
                            depth: dims["depth"] ?? 0
                        )
                    }
                    
                    continuation.resume(returning: GLBAnalysisResult(meshNames: meshes, dimensions: dimensions))
                    return
                }
            } catch {
                print("GLB analysis error: \(error)")
            }
            
            continuation.resume(returning: GLBAnalysisResult(meshNames: [], dimensions: nil))
        }
    }
    
    /// Analyze shape characteristics from mesh names
    func analyzeShape(meshNames: [String], crtOrientation: String?) -> CabinetShape {
        let names = Set(meshNames.map { $0.lowercased() })
        
        // Detect features
        let hasScreen = names.contains(where: { $0.contains("screen") || $0.contains("monitor") || $0.contains("crt") })
        let hasMarquee = names.contains(where: { $0.contains("marquee") })
        let hasControlPanel = names.contains(where: { $0.contains("control") || $0.contains("panel") || $0.contains("cpo") })
        let hasJoystick = names.contains(where: { $0.contains("joystick") || $0.contains("stick") })
        let hasButtons = names.contains(where: { $0.contains("button") || $0.contains("btn") })
        let hasWheel = names.contains(where: { $0.contains("wheel") || $0.contains("steering") })
        let hasPedals = names.contains(where: { $0.contains("pedal") || $0.contains("gas") || $0.contains("brake") })
        let hasGun = names.contains(where: { $0.contains("gun") || $0.contains("pistol") || $0.contains("rifle") })
        let hasCoinSlot = names.contains(where: { $0.contains("coin") || $0.contains("slot") })
        let hasMirror = names.contains(where: { $0.contains("mirror") })
        
        // Count controls
        let controlKeywords = ["joystick", "button", "btn", "stick", "trigger", "wheel", "pedal", "gun", "dial", "spinner", "trackball"]
        let controlCount = names.filter { name in controlKeywords.contains(where: { name.contains($0) }) }.count
        
        // Determine screen orientation
        let screenOrientation: CabinetShape.ScreenOrientation
        if let orientation = crtOrientation?.lowercased() {
            screenOrientation = orientation.contains("vertical") ? .vertical : .horizontal
        } else {
            screenOrientation = .unknown
        }
        
        // Determine cabinet type
        let type: CabinetShape.CabinetType
        if hasWheel || hasPedals {
            type = .driving
        } else if hasGun {
            type = .lightgun
        } else if hasMirror || names.contains(where: { $0.contains("dial") && $0.contains("tron") }) {
            type = .flightstick
        } else if names.contains(where: { $0.contains("cocktail") || $0.contains("table") }) {
            type = .cocktail
        } else if names.contains(where: { $0.contains("neogeo") || $0.contains("mvs") }) {
            type = .neogeo
        } else if names.contains(where: { $0.contains("pinball") || $0.contains("flipper") }) {
            type = .pinball
        } else {
            type = .upright
        }
        
        return CabinetShape(
            type: type,
            hasScreen: hasScreen,
            hasMarquee: hasMarquee,
            hasControlPanel: hasControlPanel,
            hasJoystick: hasJoystick,
            hasButtons: hasButtons,
            hasWheel: hasWheel,
            hasPedals: hasPedals,
            hasGun: hasGun,
            hasCoinSlot: hasCoinSlot,
            hasMirror: hasMirror,
            screenOrientation: screenOrientation,
            controlCount: controlCount
        )
    }
    
    // MARK: - Template Suggestion
    
    /// Suggest the best template based on GLB mesh names
    func suggestTemplate(meshNames: [String]) -> String {
        let names = Set(meshNames.map { $0.lowercased() })
        
        // Light gun cabinet (has gun meshes)
        if names.contains(where: { $0.contains("gun") }) {
            return "lightgun"
        }
        
        // Tron-style cabinet (has mirrors, dial)
        if names.contains("mirror") || names.contains("dial") || names.contains("stick") {
            return "flightstick"
        }
        
        // Driving cabinet (has wheel, pedals)
        if names.contains("wheel") || names.contains("pedal") || names.contains("steering") {
            return "driving"
        }
        
        // Cocktail (has specific cocktail parts)
        if names.contains("glass") || names.contains("cocktail") {
            return "cocktail"
        }
        
        // Neo Geo style (4-button layout)
        if names.contains("btn-a") && names.contains("btn-b") && names.contains("btn-c") && names.contains("btn-d") {
            return "neogeo"
        }
        
        // Default to commando/upright style
        return "upright"
    }
    
    // MARK: - Cleanup
    
    /// Clean up temporary extraction folder
    func cleanup() {
        try? fileManager.removeItem(at: tempDirectory)
    }
}

// MARK: - Template Matching Helpers

extension CabinetAnalyzer {
    
    /// Get mesh names that match a template's expected parts
    func matchingMeshes(cabinetMeshes: [String], templateParts: [String]) -> [String: String] {
        var matches: [String: String] = [:]
        
        let cabinetSet = Set(cabinetMeshes.map { $0.lowercased() })
        
        for part in templateParts {
            let partLower = part.lowercased()
            
            // Direct match
            if cabinetSet.contains(partLower) {
                matches[part] = cabinetMeshes.first { $0.lowercased() == partLower }
            }
            // Partial match
            else if let match = cabinetMeshes.first(where: { $0.lowercased().contains(partLower) }) {
                matches[part] = match
            }
        }
        
        return matches
    }
}
