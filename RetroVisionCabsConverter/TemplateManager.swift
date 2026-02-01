//
//  TemplateManager.swift
//  RetroVisionCabsConverter
//
//  Manages loading and caching of cabinet templates
//

import Foundation
import SwiftUI
import Compression

@MainActor
class TemplateManager: ObservableObject {
    @Published var templates: [CabinetTemplate] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private var templateCache: [String: CabinetTemplate] = [:]
    
    init() {
        loadTemplates()
    }
    
    // MARK: - Loading
    
    func loadTemplates() {
        isLoading = true
        error = nil
        templates = []
        templateCache = [:]
        
        // Get templates from bundle
        guard let bundlePath = Bundle.main.resourcePath else {
            error = "Could not find app resources"
            isLoading = false
            return
        }
        
        let templatesPath = (bundlePath as NSString).appendingPathComponent("Templates")
        
        // Also check configured templates directory (supports dev and deployed scenarios)
        let paths = RetroVisionPaths.load()
        let devTemplatesPath = paths.templatesDirectory
        
        // User-created templates
        let userTemplatesPath = getUserTemplatesPath().path
        
        let searchPaths = [templatesPath, devTemplatesPath, userTemplatesPath]
        var loadedTemplates: [CabinetTemplate] = []
        
        for basePath in searchPaths {
            if FileManager.default.fileExists(atPath: basePath) {
                loadedTemplates.append(contentsOf: loadTemplatesFromPath(basePath))
            }
        }
        
        // Remove duplicates by ID
        var seen = Set<String>()
        templates = loadedTemplates.filter { template in
            if seen.contains(template.id) {
                return false
            }
            seen.insert(template.id)
            return true
        }
        
        // Sort by name
        templates.sort { $0.name < $1.name }
        
        // Cache templates
        for template in templates {
            templateCache[template.id] = template
        }
        
        isLoading = false
        
        if templates.isEmpty {
            error = "No templates found"
        }
    }
    
    private func loadTemplatesFromPath(_ basePath: String) -> [CabinetTemplate] {
        var loadedTemplates: [CabinetTemplate] = []
        
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: basePath) else {
            return []
        }
        
        for folder in contents {
            let folderPath = (basePath as NSString).appendingPathComponent(folder)
            var isDirectory: ObjCBool = false
            
            guard fm.fileExists(atPath: folderPath, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }
            
            let configPath = (folderPath as NSString).appendingPathComponent("template-config.json")
            
            guard fm.fileExists(atPath: configPath),
                  let data = fm.contents(atPath: configPath) else {
                continue
            }
            
            do {
                var template = try JSONDecoder().decode(CabinetTemplate.self, from: data)
                template.bundlePath = folderPath
                loadedTemplates.append(template)
            } catch {
                print("Failed to load template from \(configPath): \(error)")
            }
        }
        
        return loadedTemplates
    }
    
    // MARK: - Access
    
    func template(withId id: String) -> CabinetTemplate? {
        templateCache[id]
    }
    
    func refresh() {
        loadTemplates()
    }
    
    // MARK: - Template Dimensions Cache
    
    private var templateDimensionsCache: [String: CabinetDimensions] = [:]
    
    /// Get dimensions for a template (from its GLB model)
    func getDimensions(for template: CabinetTemplate) async -> CabinetDimensions? {
        // Check cache first
        if let cached = templateDimensionsCache[template.id] {
            return cached
        }
        
        guard let modelPath = template.modelPath else { return nil }
        
        // Analyze the template's GLB
        let result = await CabinetAnalyzer.shared.analyzeGLB(URL(fileURLWithPath: modelPath))
        
        if let dims = result.dimensions {
            templateDimensionsCache[template.id] = dims
        }
        
        return result.dimensions
    }
    
    // MARK: - Template Matching
    
    /// Match a discovered cabinet to existing templates
    func matchTemplates(for cabinet: DiscoveredCabinet) async -> [TemplateMatchResult] {
        var results: [TemplateMatchResult] = []
        
        for template in templates {
            let match = await matchTemplate(template, to: cabinet)
            results.append(match)
        }
        
        // Sort by confidence (highest first)
        results.sort { $0.confidence > $1.confidence }
        
        return results
    }
    
    /// Match a single template to a cabinet
    private func matchTemplate(_ template: CabinetTemplate, to cabinet: DiscoveredCabinet) async -> TemplateMatchResult {
        var dimensionScore = 0.5  // Default neutral
        var shapeScore = 0.5
        var meshMatchCount = 0
        
        // Compare dimensions if available
        if let cabinetDims = cabinet.dimensions {
            if let templateDims = await getDimensions(for: template) {
                dimensionScore = cabinetDims.similarity(to: templateDims)
            }
        }
        
        // Compare shape
        if let cabinetShape = cabinet.cabinetShape {
            let templateShape = inferTemplateShape(template)
            shapeScore = cabinetShape.similarity(to: templateShape)
        }
        
        // Count mesh matches
        let templateMeshNames = Set(template.parts.map { $0.meshName.lowercased() })
        let cabinetMeshNames = Set(cabinet.glbMeshNames.map { $0.lowercased() })
        
        for templateMesh in templateMeshNames {
            if cabinetMeshNames.contains(where: { $0.contains(templateMesh) || templateMesh.contains($0) }) {
                meshMatchCount += 1
            }
        }
        
        let meshMatchScore = templateMeshNames.isEmpty ? 0.5 : Double(meshMatchCount) / Double(templateMeshNames.count)
        
        // Calculate overall confidence
        let confidence = (dimensionScore * 0.35 + shapeScore * 0.40 + meshMatchScore * 0.25)
        
        return TemplateMatchResult(
            templateID: template.id,
            templateName: template.name,
            confidence: confidence,
            dimensionScore: dimensionScore,
            shapeScore: shapeScore,
            meshMatchCount: meshMatchCount,
            totalMeshes: templateMeshNames.count
        )
    }
    
    /// Infer shape characteristics from template configuration
    private func inferTemplateShape(_ template: CabinetTemplate) -> CabinetShape {
        let partNames = Set(template.parts.map { $0.id.lowercased() })
        let meshNames = Set(template.parts.map { $0.meshName.lowercased() })
        let allNames = partNames.union(meshNames)
        
        let hasJoystick = allNames.contains(where: { $0.contains("joystick") || $0.contains("stick") })
        let hasButtons = allNames.contains(where: { $0.contains("button") || $0.contains("btn") })
        let hasWheel = allNames.contains(where: { $0.contains("wheel") || $0.contains("steering") })
        let hasPedals = allNames.contains(where: { $0.contains("pedal") })
        let hasGun = allNames.contains(where: { $0.contains("gun") })
        let hasMirror = allNames.contains(where: { $0.contains("mirror") })
        
        let type: CabinetShape.CabinetType
        switch template.cabinetType?.lowercased() ?? template.id.lowercased() {
        case let t where t.contains("driving"): type = .driving
        case let t where t.contains("lightgun") || t.contains("gun"): type = .lightgun
        case let t where t.contains("flightstick") || t.contains("tron"): type = .flightstick
        case let t where t.contains("cocktail"): type = .cocktail
        case let t where t.contains("neogeo"): type = .neogeo
        default: type = .upright
        }
        
        let orientation: CabinetShape.ScreenOrientation
        switch template.crtOrientation.lowercased() {
        case "vertical": orientation = .vertical
        case "horizontal": orientation = .horizontal
        default: orientation = .unknown
        }
        
        return CabinetShape(
            type: type,
            hasScreen: true,
            hasMarquee: true,
            hasControlPanel: true,
            hasJoystick: hasJoystick,
            hasButtons: hasButtons,
            hasWheel: hasWheel,
            hasPedals: hasPedals,
            hasGun: hasGun,
            hasCoinSlot: true,
            hasMirror: hasMirror,
            screenOrientation: orientation,
            controlCount: template.parts.filter { $0.id.lowercased().contains("control") }.count
        )
    }
    
    // MARK: - Create New Template
    
    /// Create a new template from a cabinet's GLB file
    func createTemplate(from cabinet: DiscoveredCabinet, name: String, id: String? = nil) async throws -> CabinetTemplate {
        guard let glbFile = cabinet.glbFile else {
            throw TemplateCreationError.noGLBFile
        }
        
        let templateID = id ?? name.lowercased().replacingOccurrences(of: " ", with: "-")
        
        // Get user templates directory
        let userTemplatesPath = getUserTemplatesPath()
        let templateFolder = userTemplatesPath.appendingPathComponent(templateID)
        
        // Create folder
        try FileManager.default.createDirectory(at: templateFolder, withIntermediateDirectories: true)
        
        // Copy GLB file
        let destGLB = templateFolder.appendingPathComponent("\(templateID).glb")
        try FileManager.default.copyItem(at: glbFile, to: destGLB)
        
        // Analyze the GLB to extract parts
        let analysis = await CabinetAnalyzer.shared.analyzeGLB(glbFile)
        let shape = CabinetAnalyzer.shared.analyzeShape(meshNames: analysis.meshNames, crtOrientation: nil)
        
        // Create template parts from mesh names
        let parts = createPartsFromMeshes(analysis.meshNames)
        
        // Determine CRT orientation
        let crtOrientation = shape.screenOrientation == .vertical ? "vertical" : "horizontal"
        
        // Create template config
        let template = CabinetTemplate(
            id: templateID,
            name: name,
            description: "Custom template created from \(cabinet.displayName)",
            model: "\(templateID).glb",
            defaultMaterial: "black",
            crtOrientation: crtOrientation,
            previewImage: nil,
            parts: parts,
            optionalParts: nil,
            tMolding: nil,
            type: "custom",
            cabinetType: shape.type.rawValue,
            prebuilt: false,
            supportsCustomArtwork: true
        )
        
        // Save template config
        let configPath = templateFolder.appendingPathComponent("template-config.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let configData = try encoder.encode(template)
        try configData.write(to: configPath)
        
        // Generate preview image
        await generateTemplatePreview(for: template, at: templateFolder)
        
        // Reload templates
        loadTemplates()
        
        // Return the newly created template (with bundlePath set)
        return templateCache[templateID] ?? template
    }
    
    /// Get the path for user-created templates
    private func getUserTemplatesPath() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("RetroVisionCabsConverter")
        let templatesFolder = appFolder.appendingPathComponent("UserTemplates")
        
        try? FileManager.default.createDirectory(at: templatesFolder, withIntermediateDirectories: true)
        
        return templatesFolder
    }
    
    /// Create template parts from mesh names
    private func createPartsFromMeshes(_ meshNames: [String]) -> [TemplatePart] {
        var parts: [TemplatePart] = []
        
        // Map common mesh names to part configurations
        let partConfigs: [(keywords: [String], id: String, displayName: String, type: TemplatePartType, width: Int, height: Int)] = [
            (["left", "side-left", "sideleft"], "side-left", "Left Side", .texture, 2048, 1536),
            (["right", "side-right", "sideright"], "side-right", "Right Side", .texture, 2048, 1536),
            (["marquee"], "marquee", "Marquee", .marquee, 1024, 256),
            (["bezel"], "bezel", "Bezel", .bezel, 1024, 768),
            (["control", "cpo", "panel"], "control-panel", "Control Panel", .texture, 1024, 512),
            (["front", "kick"], "front", "Front Panel", .texture, 768, 512),
            (["back"], "back", "Back Panel", .texture, 768, 1024),
            (["top"], "top", "Top Panel", .texture, 768, 512),
            (["joystick"], "joystick", "Joystick", .texture, 256, 256),
            (["coin"], "coin-slot", "Coin Slot", .texture, 256, 256),
        ]
        
        for meshName in meshNames {
            let lowerName = meshName.lowercased()
            
            for config in partConfigs {
                if config.keywords.contains(where: { lowerName.contains($0) }) {
                    // Check if we already have this part
                    if !parts.contains(where: { $0.id == config.id }) {
                        let part = TemplatePart(
                            id: config.id,
                            meshName: meshName,
                            displayName: config.displayName,
                            description: nil,
                            dimensions: PartDimensions(width: config.width, height: config.height),
                            filePatterns: config.keywords,
                            required: ["side-left", "side-right", "marquee", "bezel"].contains(config.id),
                            type: config.type,
                            hasAlpha: config.type == .bezel,
                            emissive: config.type == .marquee,
                            defaultColor: nil,
                            mirrorOf: nil,
                            flipHorizontal: config.id == "side-right"
                        )
                        parts.append(part)
                    }
                    break
                }
            }
        }
        
        return parts
    }
    
    /// Generate a preview image for a template
    private func generateTemplatePreview(for template: CabinetTemplate, at folder: URL) async {
        guard let modelPath = folder.appendingPathComponent(template.model).path as String? else { return }
        
        let outputPath = folder.appendingPathComponent("preview.png")
        
        let script = """
        import bpy
        import math

        # Clear scene
        bpy.ops.object.select_all(action='SELECT')
        bpy.ops.object.delete()

        # Import GLB
        bpy.ops.import_scene.gltf(filepath='\(modelPath)')

        # Calculate bounding box
        min_coord = [float('inf')] * 3
        max_coord = [float('-inf')] * 3
        for obj in bpy.data.objects:
            if obj.type == 'MESH':
                for corner in [obj.matrix_world @ v.co for v in obj.data.vertices]:
                    for i in range(3):
                        min_coord[i] = min(min_coord[i], corner[i])
                        max_coord[i] = max(max_coord[i], corner[i])

        center = [(min_coord[i] + max_coord[i]) / 2 for i in range(3)]
        size = max(max_coord[i] - min_coord[i] for i in range(3))

        # Add camera
        bpy.ops.object.camera_add()
        camera = bpy.context.object
        camera.location = (center[0] + size * 1.5, center[1] - size * 1.5, center[2] + size * 0.8)
        camera.rotation_euler = (math.radians(70), 0, math.radians(45))
        bpy.context.scene.camera = camera

        # Add lights
        bpy.ops.object.light_add(type='SUN', location=(10, -10, 10))
        bpy.context.object.data.energy = 3

        bpy.ops.object.light_add(type='AREA', location=(-5, -5, 5))
        bpy.context.object.data.energy = 200

        # Render settings
        bpy.context.scene.render.resolution_x = 512
        bpy.context.scene.render.resolution_y = 512
        bpy.context.scene.render.film_transparent = True
        bpy.context.scene.render.filepath = '\(outputPath.path)'
        bpy.context.scene.render.image_settings.file_format = 'PNG'

        bpy.ops.render.render(write_still=True)
        """
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/Applications/Blender.app/Contents/MacOS/Blender")
        process.arguments = ["-b", "--factory-startup", "--python-expr", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        try? process.run()
        process.waitUntilExit()
    }
    
    enum TemplateCreationError: LocalizedError {
        case noGLBFile
        case copyFailed
        case configSaveFailed
        
        var errorDescription: String? {
            switch self {
            case .noGLBFile: return "Cabinet has no GLB model file"
            case .copyFailed: return "Failed to copy cabinet files"
            case .configSaveFailed: return "Failed to save template configuration"
            }
        }
    }
    
    // MARK: - Auto-Mapping
    
    /// Auto-map artwork files to template parts
    func autoMapArtwork(files: [URL], template: CabinetTemplate) -> [String: ArtworkMapping] {
        var mappings: [String: ArtworkMapping] = [:]
        
        // Initialize all parts as unmapped
        for part in template.allParts {
            mappings[part.id] = ArtworkMapping(id: part.id, file: nil, status: .unmapped)
        }
        
        // Filter to only image files
        let imageExtensions = ["png", "jpg", "jpeg", "tiff", "bmp"]
        let imageFiles = files.filter { url in
            imageExtensions.contains(url.pathExtension.lowercased())
        }
        
        // Try to match each file to a part
        for file in imageFiles {
            let filename = file.lastPathComponent
            
            // Find the best matching part
            if let matchingPart = findBestMatch(for: filename, in: template.allParts) {
                // Only map if not already mapped (first match wins)
                if mappings[matchingPart.id]?.file == nil {
                    mappings[matchingPart.id] = ArtworkMapping(
                        id: matchingPart.id,
                        file: file,
                        status: .autoMapped
                    )
                }
            }
        }
        
        // Handle mirror relationships
        for part in template.allParts {
            if let mirrorOf = part.mirrorOf,
               mappings[part.id]?.file == nil,
               let sourceMapping = mappings[mirrorOf],
               sourceMapping.file != nil {
                // Auto-use the source file for mirrored parts
                mappings[part.id] = ArtworkMapping(
                    id: part.id,
                    file: sourceMapping.file,
                    status: .autoMapped
                )
            }
        }
        
        return mappings
    }
    
    private func findBestMatch(for filename: String, in parts: [TemplatePart]) -> TemplatePart? {
        let baseName = (filename as NSString).deletingPathExtension.lowercased()
        
        // First pass: exact pattern match
        for part in parts {
            for pattern in part.filePatterns {
                if baseName == pattern.lowercased() {
                    return part
                }
            }
        }
        
        // Second pass: contains pattern
        for part in parts {
            for pattern in part.filePatterns {
                if baseName.contains(pattern.lowercased()) {
                    return part
                }
            }
        }
        
        // Third pass: pattern contains base name
        for part in parts {
            for pattern in part.filePatterns {
                if pattern.lowercased().contains(baseName) && baseName.count > 3 {
                    return part
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Artwork Guide Generation
    
    /// Generate complete artwork template pack for a template
    func generateArtworkGuides(for template: CabinetTemplate, outputFolder: URL) throws {
        let fm = FileManager.default
        
        // Create output folder structure
        try fm.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        
        let templatesFolder = outputFolder.appendingPathComponent("Templates")
        let guidesFolder = outputFolder.appendingPathComponent("Guides")
        
        try fm.createDirectory(at: templatesFolder, withIntermediateDirectories: true)
        try fm.createDirectory(at: guidesFolder, withIntermediateDirectories: true)
        
        // Generate full-size PNG templates for each part
        for part in template.allParts {
            // Full-size template (for artist to work on)
            let templateImage = createFullSizeTemplate(for: part, template: template)
            let templateFilename = "\(part.id).png"
            let templatePath = templatesFolder.appendingPathComponent(templateFilename)
            
            if let pngData = templateImage.pngData() {
                try pngData.write(to: templatePath)
            }
            
            // Guide image (with labels and info)
            let guideImage = createArtworkGuide(for: part, template: template)
            let guideFilename = "\(part.id)-guide.png"
            let guidePath = guidesFolder.appendingPathComponent(guideFilename)
            
            if let pngData = guideImage.pngData() {
                try pngData.write(to: guidePath)
            }
        }
        
        // Create SVG file with all layers
        let svgContent = generateSVGTemplate(for: template)
        let svgPath = outputFolder.appendingPathComponent("\(template.name)-template.svg")
        try svgContent.write(to: svgPath, atomically: true, encoding: .utf8)
        
        // Create manifest JSON for import
        let manifest = generateManifest(for: template)
        let manifestPath = outputFolder.appendingPathComponent("manifest.json")
        try manifest.write(to: manifestPath, atomically: true, encoding: .utf8)
        
        // Create README
        let readme = generateReadme(for: template)
        let readmePath = outputFolder.appendingPathComponent("README.txt")
        try readme.write(to: readmePath, atomically: true, encoding: .utf8)
        
        // Create Photoshop instructions
        let psInstructions = generatePhotoshopInstructions(for: template)
        let psPath = outputFolder.appendingPathComponent("PHOTOSHOP-INSTRUCTIONS.txt")
        try psInstructions.write(to: psPath, atomically: true, encoding: .utf8)
    }
    
    /// Create full-size PNG template at actual dimensions with proper cabinet part shape
    private func createFullSizeTemplate(for part: TemplatePart, template: CabinetTemplate) -> NSImage {
        let width = CGFloat(part.dimensions.width)
        let height = CGFloat(part.dimensions.height)
        
        let image = NSImage(size: NSSize(width: width, height: height))
        
        image.lockFocus()
        
        // Transparent background
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        
        // Get the cabinet part shape path
        let shapePath = createCabinetPartShape(for: part, width: width, height: height)
        
        // Fill shape with checkered pattern to show transparency
        NSGraphicsContext.saveGraphicsState()
        shapePath.addClip()
        
        let gridColor = NSColor.gray.withAlphaComponent(0.08)
        gridColor.setFill()
        let gridSize: CGFloat = max(30, min(width, height) * 0.02)
        for x in stride(from: 0, to: width, by: gridSize * 2) {
            for y in stride(from: 0, to: height, by: gridSize * 2) {
                NSRect(x: x, y: y, width: gridSize, height: gridSize).fill()
                NSRect(x: x + gridSize, y: y + gridSize, width: gridSize, height: gridSize).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        
        // Draw shape outline (cut line) in red
        NSColor.red.withAlphaComponent(0.6).setStroke()
        shapePath.lineWidth = max(2, min(width, height) * 0.002)
        shapePath.stroke()
        
        // Draw safe area inside shape
        let safeInset = min(width, height) * 0.05
        let safeShapePath = createCabinetPartShape(for: part, width: width - safeInset * 2, height: height - safeInset * 2)
        let safeTransform = AffineTransform(translationByX: safeInset, byY: safeInset)
        safeShapePath.transform(using: safeTransform)
        
        NSColor.cyan.withAlphaComponent(0.4).setStroke()
        safeShapePath.lineWidth = max(1.5, min(width, height) * 0.0015)
        let dashPattern: [CGFloat] = [max(8, width * 0.005), max(4, width * 0.003)]
        safeShapePath.setLineDash(dashPattern, count: 2, phase: 0)
        safeShapePath.stroke()
        
        // For bezel, draw screen cutout area
        if part.type == .bezel {
            let screenPath = createScreenCutoutPath(width: width, height: height)
            NSColor.black.withAlphaComponent(0.3).setFill()
            screenPath.fill()
            
            NSColor.yellow.withAlphaComponent(0.8).setStroke()
            screenPath.lineWidth = max(2, min(width, height) * 0.003)
            screenPath.stroke()
            
            // Label for screen area
            let screenLabel = "SCREEN CUTOUT"
            let screenAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: max(14, min(width, height) * 0.025)),
                .foregroundColor: NSColor.yellow.withAlphaComponent(0.8)
            ]
            let screenLabelSize = screenLabel.size(withAttributes: screenAttrs)
            screenLabel.draw(at: NSPoint(x: (width - screenLabelSize.width) / 2, y: height * 0.5 - screenLabelSize.height / 2), withAttributes: screenAttrs)
        }
        
        // Center guides
        NSColor.magenta.withAlphaComponent(0.15).setStroke()
        let centerV = NSBezierPath()
        centerV.move(to: NSPoint(x: width / 2, y: 0))
        centerV.line(to: NSPoint(x: width / 2, y: height))
        centerV.lineWidth = 1
        centerV.setLineDash([5, 5], count: 2, phase: 0)
        centerV.stroke()
        
        let centerH = NSBezierPath()
        centerH.move(to: NSPoint(x: 0, y: height / 2))
        centerH.line(to: NSPoint(x: width, y: height / 2))
        centerH.lineWidth = 1
        centerH.setLineDash([5, 5], count: 2, phase: 0)
        centerH.stroke()
        
        // Corner info labels
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(14, min(width, height) * 0.018)),
            .foregroundColor: NSColor.gray.withAlphaComponent(0.5)
        ]
        
        let filename = "\(part.id).png"
        filename.draw(at: NSPoint(x: 15, y: 15), withAttributes: labelAttrs)
        
        let dimText = "\(Int(width))×\(Int(height))px"
        let dimSize = dimText.size(withAttributes: labelAttrs)
        dimText.draw(at: NSPoint(x: width - dimSize.width - 15, y: height - dimSize.height - 15), withAttributes: labelAttrs)
        
        // Part name label at top center
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: max(16, min(width, height) * 0.02)),
            .foregroundColor: NSColor.gray.withAlphaComponent(0.4)
        ]
        let nameSize = part.displayName.size(withAttributes: nameAttrs)
        part.displayName.draw(at: NSPoint(x: (width - nameSize.width) / 2, y: height - nameSize.height - 20), withAttributes: nameAttrs)
        
        image.unlockFocus()
        
        return image
    }
    
    /// Create the actual shape path for different cabinet parts
    private func createCabinetPartShape(for part: TemplatePart, width: CGFloat, height: CGFloat) -> NSBezierPath {
        let partId = part.id.lowercased()
        
        // Side panels - Classic arcade cabinet side profile
        if partId.contains("side-left") || partId == "side" {
            return createSidePanelPath(width: width, height: height, mirrored: false)
        }
        
        // Right side panel - mirrored shape
        if partId.contains("side-right") {
            return createSidePanelPath(width: width, height: height, mirrored: true)
        }
        
        // Any other side panel
        if partId.contains("side") {
            let mirrored = part.flipHorizontal == true
            return createSidePanelPath(width: width, height: height, mirrored: mirrored)
        }
        
        // Marquee art - Wide rectangle with rounded corners
        if part.type == .marquee || partId == "marquee" {
            let cornerRadius = min(width, height) * 0.03
            return NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: height),
                               xRadius: cornerRadius, yRadius: cornerRadius)
        }
        
        // Marquee box - housing shape
        if partId.contains("marquee-box") {
            return createMarqueeBoxPath(width: width, height: height)
        }
        
        // Bezel - Rectangle (screen cutout drawn separately)
        if part.type == .bezel || partId.contains("bezel") {
            let cornerRadius = min(width, height) * 0.02
            return NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: height),
                               xRadius: cornerRadius, yRadius: cornerRadius)
        }
        
        // Control panel overlay - Angled trapezoid shape
        if partId.contains("control-panel-overlay") || partId.contains("cpo") || partId == "control-panel" {
            return createControlPanelPath(width: width, height: height)
        }
        
        // Control panel shell - side pieces
        if partId.contains("control") && partId.contains("shell") {
            return createControlPanelShellPath(width: width, height: height)
        }
        
        // Front kick plate
        if partId.contains("kick") || partId.contains("front-kick") {
            return createKickPlatePath(width: width, height: height)
        }
        
        // Back panel
        if partId.contains("back") {
            return createBackPanelPath(width: width, height: height)
        }
        
        // Top panel
        if partId.contains("top") && !partId.contains("marquee") {
            return createTopPanelPath(width: width, height: height)
        }
        
        // Bottom/base panel
        if partId.contains("bottom") || partId.contains("base") {
            return createBottomPanelPath(width: width, height: height)
        }
        
        // Coin door
        if partId.contains("coin") {
            return createCoinDoorPath(width: width, height: height)
        }
        
        // Speaker panel
        if partId.contains("speaker") {
            return createSpeakerPanelPath(width: width, height: height)
        }
        
        // Default: simple rounded rectangle
        let cornerRadius = min(width, height) * 0.01
        return NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: height),
                           xRadius: cornerRadius, yRadius: cornerRadius)
    }
    
    /// Create classic arcade cabinet side panel shape
    /// Width = depth (front to back), Height = cabinet height
    /// Left side: Left edge = BACK, Right edge = FRONT
    /// Right side (mirrored): Left edge = FRONT, Right edge = BACK
    private func createSidePanelPath(width: CGFloat, height: CGFloat, mirrored: Bool) -> NSBezierPath {
        let path = NSBezierPath()
        
        // Key vertical positions (from bottom to top)
        let floorY: CGFloat = 0
        let kickPanelTopY = height * 0.15
        let controlPanelBottomY = height * 0.30
        let controlPanelTopY = height * 0.38
        let screenBottomY = height * 0.40
        let screenTopY = height * 0.72
        let marqueeBottomY = height * 0.75
        let marqueeTopY = height * 0.88
        let cabinetTopY = height
        
        // For left side: BACK on left (x=0), FRONT on right (x=width)
        // For right side (mirrored): FRONT on left (x=0), BACK on right (x=width)
        
        func x(_ normalizedX: CGFloat) -> CGFloat {
            return mirrored ? width - (normalizedX * width) : normalizedX * width
        }
        
        // Normalized X positions (0 = back, 1 = front for left side)
        let backNorm: CGFloat = 0.0
        let backTopNorm: CGFloat = 0.05
        let frontBottomNorm: CGFloat = 0.85
        let frontKickNorm: CGFloat = 0.90
        let frontControlNorm: CGFloat = 0.98
        let frontScreenBottomNorm: CGFloat = 1.0
        let frontScreenTopNorm: CGFloat = 0.92
        let frontMarqueeNorm: CGFloat = 0.88
        let topFrontNorm: CGFloat = 0.75
        
        if !mirrored {
            // LEFT SIDE - back on left, front on right
            path.move(to: NSPoint(x: x(backNorm), y: floorY))
            path.line(to: NSPoint(x: x(frontBottomNorm), y: floorY))
            path.line(to: NSPoint(x: x(frontKickNorm), y: kickPanelTopY))
            path.line(to: NSPoint(x: x(frontKickNorm), y: controlPanelBottomY))
            path.line(to: NSPoint(x: x(frontControlNorm), y: controlPanelTopY))
            path.line(to: NSPoint(x: x(frontScreenBottomNorm), y: screenBottomY))
            path.line(to: NSPoint(x: x(frontScreenTopNorm), y: screenTopY))
            path.line(to: NSPoint(x: x(frontMarqueeNorm), y: marqueeBottomY))
            path.line(to: NSPoint(x: x(frontMarqueeNorm + 0.02), y: marqueeTopY))
            path.curve(to: NSPoint(x: x(topFrontNorm), y: cabinetTopY),
                      controlPoint1: NSPoint(x: x(frontMarqueeNorm), y: height * 0.92),
                      controlPoint2: NSPoint(x: x(0.82), y: cabinetTopY))
            path.curve(to: NSPoint(x: x(backTopNorm), y: cabinetTopY),
                      controlPoint1: NSPoint(x: x(0.4), y: cabinetTopY),
                      controlPoint2: NSPoint(x: x(0.15), y: cabinetTopY))
            path.curve(to: NSPoint(x: x(backNorm), y: marqueeTopY),
                      controlPoint1: NSPoint(x: x(backNorm), y: height * 0.98),
                      controlPoint2: NSPoint(x: x(backNorm), y: height * 0.92))
            path.line(to: NSPoint(x: x(backNorm), y: floorY))
        } else {
            // RIGHT SIDE - front on left, back on right (mirrored)
            path.move(to: NSPoint(x: x(backNorm), y: floorY))  // back is now on RIGHT
            path.line(to: NSPoint(x: x(frontBottomNorm), y: floorY))  // front is now on LEFT
            path.line(to: NSPoint(x: x(frontKickNorm), y: kickPanelTopY))
            path.line(to: NSPoint(x: x(frontKickNorm), y: controlPanelBottomY))
            path.line(to: NSPoint(x: x(frontControlNorm), y: controlPanelTopY))
            path.line(to: NSPoint(x: x(frontScreenBottomNorm), y: screenBottomY))
            path.line(to: NSPoint(x: x(frontScreenTopNorm), y: screenTopY))
            path.line(to: NSPoint(x: x(frontMarqueeNorm), y: marqueeBottomY))
            path.line(to: NSPoint(x: x(frontMarqueeNorm + 0.02), y: marqueeTopY))
            path.curve(to: NSPoint(x: x(topFrontNorm), y: cabinetTopY),
                      controlPoint1: NSPoint(x: x(frontMarqueeNorm), y: height * 0.92),
                      controlPoint2: NSPoint(x: x(0.82), y: cabinetTopY))
            path.curve(to: NSPoint(x: x(backTopNorm), y: cabinetTopY),
                      controlPoint1: NSPoint(x: x(0.4), y: cabinetTopY),
                      controlPoint2: NSPoint(x: x(0.15), y: cabinetTopY))
            path.curve(to: NSPoint(x: x(backNorm), y: marqueeTopY),
                      controlPoint1: NSPoint(x: x(backNorm), y: height * 0.98),
                      controlPoint2: NSPoint(x: x(backNorm), y: height * 0.92))
            path.line(to: NSPoint(x: x(backNorm), y: floorY))
        }
        
        path.close()
        return path
    }
    
    /// Create marquee box housing shape
    private func createMarqueeBoxPath(width: CGFloat, height: CGFloat) -> NSBezierPath {
        let cornerRadius = min(width, height) * 0.05
        return NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: height),
                           xRadius: cornerRadius, yRadius: cornerRadius)
    }
    
    /// Create control panel shell (side pieces) shape
    private func createControlPanelShellPath(width: CGFloat, height: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let cornerRadius = min(width, height) * 0.02
        
        // Trapezoidal shape - wider at bottom
        let topInset = width * 0.08
        
        path.move(to: NSPoint(x: cornerRadius, y: 0))
        path.line(to: NSPoint(x: width - cornerRadius, y: 0))
        path.curve(to: NSPoint(x: width, y: cornerRadius),
                  controlPoint1: NSPoint(x: width, y: 0),
                  controlPoint2: NSPoint(x: width, y: cornerRadius))
        path.line(to: NSPoint(x: width - topInset, y: height - cornerRadius))
        path.curve(to: NSPoint(x: width - topInset - cornerRadius, y: height),
                  controlPoint1: NSPoint(x: width - topInset, y: height),
                  controlPoint2: NSPoint(x: width - topInset - cornerRadius, y: height))
        path.line(to: NSPoint(x: topInset + cornerRadius, y: height))
        path.curve(to: NSPoint(x: topInset, y: height - cornerRadius),
                  controlPoint1: NSPoint(x: topInset, y: height),
                  controlPoint2: NSPoint(x: topInset, y: height - cornerRadius))
        path.line(to: NSPoint(x: 0, y: cornerRadius))
        path.curve(to: NSPoint(x: cornerRadius, y: 0),
                  controlPoint1: NSPoint(x: 0, y: 0),
                  controlPoint2: NSPoint(x: cornerRadius, y: 0))
        
        path.close()
        return path
    }
    
    /// Create kick plate shape
    private func createKickPlatePath(width: CGFloat, height: CGFloat) -> NSBezierPath {
        let cornerRadius = min(width, height) * 0.02
        // Simple rectangle with rounded corners
        return NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: height),
                           xRadius: cornerRadius, yRadius: cornerRadius)
    }
    
    /// Create back panel shape
    private func createBackPanelPath(width: CGFloat, height: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let cornerRadius = min(width, height) * 0.01
        
        // Back panel follows cabinet contour - narrower at bottom, curves at top
        let bottomInset = width * 0.05
        let topCurveStart = height * 0.90
        
        path.move(to: NSPoint(x: bottomInset + cornerRadius, y: 0))
        path.line(to: NSPoint(x: width - bottomInset - cornerRadius, y: 0))
        path.curve(to: NSPoint(x: width - bottomInset, y: cornerRadius),
                  controlPoint1: NSPoint(x: width - bottomInset, y: 0),
                  controlPoint2: NSPoint(x: width - bottomInset, y: cornerRadius))
        path.line(to: NSPoint(x: width, y: topCurveStart))
        path.curve(to: NSPoint(x: width / 2, y: height),
                  controlPoint1: NSPoint(x: width, y: height * 0.95),
                  controlPoint2: NSPoint(x: width * 0.75, y: height))
        path.curve(to: NSPoint(x: 0, y: topCurveStart),
                  controlPoint1: NSPoint(x: width * 0.25, y: height),
                  controlPoint2: NSPoint(x: 0, y: height * 0.95))
        path.line(to: NSPoint(x: bottomInset, y: cornerRadius))
        path.curve(to: NSPoint(x: bottomInset + cornerRadius, y: 0),
                  controlPoint1: NSPoint(x: bottomInset, y: 0),
                  controlPoint2: NSPoint(x: bottomInset + cornerRadius, y: 0))
        
        path.close()
        return path
    }
    
    /// Create top panel shape
    private func createTopPanelPath(width: CGFloat, height: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let cornerRadius = min(width, height) * 0.03
        
        // Top is narrower at back, wider at front (toward player)
        let backInset = width * 0.1
        
        path.move(to: NSPoint(x: backInset + cornerRadius, y: 0))
        path.line(to: NSPoint(x: width - backInset - cornerRadius, y: 0))
        path.curve(to: NSPoint(x: width - backInset, y: cornerRadius),
                  controlPoint1: NSPoint(x: width - backInset, y: 0),
                  controlPoint2: NSPoint(x: width - backInset, y: cornerRadius))
        path.line(to: NSPoint(x: width, y: height - cornerRadius))
        path.curve(to: NSPoint(x: width - cornerRadius, y: height),
                  controlPoint1: NSPoint(x: width, y: height),
                  controlPoint2: NSPoint(x: width - cornerRadius, y: height))
        path.line(to: NSPoint(x: cornerRadius, y: height))
        path.curve(to: NSPoint(x: 0, y: height - cornerRadius),
                  controlPoint1: NSPoint(x: 0, y: height),
                  controlPoint2: NSPoint(x: 0, y: height - cornerRadius))
        path.line(to: NSPoint(x: backInset, y: cornerRadius))
        path.curve(to: NSPoint(x: backInset + cornerRadius, y: 0),
                  controlPoint1: NSPoint(x: backInset, y: 0),
                  controlPoint2: NSPoint(x: backInset + cornerRadius, y: 0))
        
        path.close()
        return path
    }
    
    /// Create bottom/base panel shape
    private func createBottomPanelPath(width: CGFloat, height: CGFloat) -> NSBezierPath {
        let cornerRadius = min(width, height) * 0.02
        return NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: height),
                           xRadius: cornerRadius, yRadius: cornerRadius)
    }
    
    /// Create coin door shape
    private func createCoinDoorPath(width: CGFloat, height: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let cornerRadius = min(width, height) * 0.05
        
        // Coin door with coin slot cutouts indicated
        let mainRect = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: height),
                                    xRadius: cornerRadius, yRadius: cornerRadius)
        path.append(mainRect)
        
        return path
    }
    
    /// Create speaker panel shape
    private func createSpeakerPanelPath(width: CGFloat, height: CGFloat) -> NSBezierPath {
        let cornerRadius = min(width, height) * 0.03
        return NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: height),
                           xRadius: cornerRadius, yRadius: cornerRadius)
    }
    
    /// Create control panel shape (angled trapezoid)
    private func createControlPanelPath(width: CGFloat, height: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        
        // Control panel is wider at front (bottom), narrower at back (top)
        let topInset = width * 0.05
        let cornerRadius = min(width, height) * 0.03
        
        path.move(to: NSPoint(x: cornerRadius, y: 0))
        path.line(to: NSPoint(x: width - cornerRadius, y: 0))
        path.curve(to: NSPoint(x: width, y: cornerRadius),
                  controlPoint1: NSPoint(x: width, y: 0),
                  controlPoint2: NSPoint(x: width, y: cornerRadius))
        path.line(to: NSPoint(x: width - topInset, y: height - cornerRadius))
        path.curve(to: NSPoint(x: width - topInset - cornerRadius, y: height),
                  controlPoint1: NSPoint(x: width - topInset, y: height),
                  controlPoint2: NSPoint(x: width - topInset - cornerRadius, y: height))
        path.line(to: NSPoint(x: topInset + cornerRadius, y: height))
        path.curve(to: NSPoint(x: topInset, y: height - cornerRadius),
                  controlPoint1: NSPoint(x: topInset, y: height),
                  controlPoint2: NSPoint(x: topInset, y: height - cornerRadius))
        path.line(to: NSPoint(x: 0, y: cornerRadius))
        path.curve(to: NSPoint(x: cornerRadius, y: 0),
                  controlPoint1: NSPoint(x: 0, y: 0),
                  controlPoint2: NSPoint(x: cornerRadius, y: 0))
        
        path.close()
        return path
    }
    
    /// Create front panel shape with coin door area
    private func createFrontPanelPath(width: CGFloat, height: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let cornerRadius = min(width, height) * 0.02
        
        // Main rectangle with slightly narrower bottom
        let bottomInset = width * 0.02
        
        path.move(to: NSPoint(x: bottomInset + cornerRadius, y: 0))
        path.line(to: NSPoint(x: width - bottomInset - cornerRadius, y: 0))
        path.curve(to: NSPoint(x: width - bottomInset, y: cornerRadius),
                  controlPoint1: NSPoint(x: width - bottomInset, y: 0),
                  controlPoint2: NSPoint(x: width - bottomInset, y: cornerRadius))
        path.line(to: NSPoint(x: width, y: height - cornerRadius))
        path.curve(to: NSPoint(x: width - cornerRadius, y: height),
                  controlPoint1: NSPoint(x: width, y: height),
                  controlPoint2: NSPoint(x: width - cornerRadius, y: height))
        path.line(to: NSPoint(x: cornerRadius, y: height))
        path.curve(to: NSPoint(x: 0, y: height - cornerRadius),
                  controlPoint1: NSPoint(x: 0, y: height),
                  controlPoint2: NSPoint(x: 0, y: height - cornerRadius))
        path.line(to: NSPoint(x: bottomInset, y: cornerRadius))
        path.curve(to: NSPoint(x: bottomInset + cornerRadius, y: 0),
                  controlPoint1: NSPoint(x: bottomInset, y: 0),
                  controlPoint2: NSPoint(x: bottomInset + cornerRadius, y: 0))
        
        path.close()
        return path
    }
    
    /// Create screen cutout path for bezel
    private func createScreenCutoutPath(width: CGFloat, height: CGFloat) -> NSBezierPath {
        // Screen cutout is typically 4:3 ratio centered in bezel
        let screenRatio: CGFloat = 4.0 / 3.0
        let margin = min(width, height) * 0.1
        
        var screenWidth = width - margin * 2
        var screenHeight = screenWidth / screenRatio
        
        // Adjust if too tall
        if screenHeight > height - margin * 2 {
            screenHeight = height - margin * 2
            screenWidth = screenHeight * screenRatio
        }
        
        let screenX = (width - screenWidth) / 2
        let screenY = (height - screenHeight) / 2
        
        let cornerRadius = min(screenWidth, screenHeight) * 0.02
        return NSBezierPath(roundedRect: NSRect(x: screenX, y: screenY, width: screenWidth, height: screenHeight),
                           xRadius: cornerRadius, yRadius: cornerRadius)
    }
    
    private func createArtworkGuide(for part: TemplatePart, template: CabinetTemplate) -> NSImage {
        let width = CGFloat(part.dimensions.width)
        let height = CGFloat(part.dimensions.height)
        
        // Create a scaled-down version for the guide (max 800px on longest side)
        let scale = min(800.0 / max(width, height), 1.0)
        let scaledWidth = width * scale
        let scaledHeight = height * scale
        
        let image = NSImage(size: NSSize(width: scaledWidth, height: scaledHeight))
        
        image.lockFocus()
        
        // White background
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight).fill()
        
        // Get the cabinet part shape (scaled)
        let shapePath = createCabinetPartShape(for: part, width: scaledWidth, height: scaledHeight)
        
        // Fill shape with checkered pattern
        NSGraphicsContext.saveGraphicsState()
        shapePath.addClip()
        
        let checkSize: CGFloat = 8
        NSColor.lightGray.withAlphaComponent(0.2).setFill()
        for x in stride(from: 0, to: scaledWidth, by: checkSize * 2) {
            for y in stride(from: 0, to: scaledHeight, by: checkSize * 2) {
                NSRect(x: x, y: y, width: checkSize, height: checkSize).fill()
                NSRect(x: x + checkSize, y: y + checkSize, width: checkSize, height: checkSize).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        
        // Shape outline in black
        NSColor.black.setStroke()
        shapePath.lineWidth = 2
        shapePath.stroke()
        
        // Safe area inside shape
        let safeInset = min(scaledWidth, scaledHeight) * 0.05
        let safeShapePath = createCabinetPartShape(for: part, width: scaledWidth - safeInset * 2, height: scaledHeight - safeInset * 2)
        let safeTransform = AffineTransform(translationByX: safeInset, byY: safeInset)
        safeShapePath.transform(using: safeTransform)
        
        NSColor.blue.setStroke()
        safeShapePath.lineWidth = 1
        let dashPattern: [CGFloat] = [6, 3]
        safeShapePath.setLineDash(dashPattern, count: 2, phase: 0)
        safeShapePath.stroke()
        
        // For bezel, draw screen cutout
        if part.type == .bezel {
            let screenPath = createScreenCutoutPath(width: scaledWidth, height: scaledHeight)
            NSColor.darkGray.withAlphaComponent(0.4).setFill()
            screenPath.fill()
            
            NSColor.orange.setStroke()
            screenPath.lineWidth = 2
            screenPath.stroke()
            
            // Screen area label
            let screenLabel = "SCREEN"
            let screenAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 12),
                .foregroundColor: NSColor.white
            ]
            let screenLabelSize = screenLabel.size(withAttributes: screenAttrs)
            screenLabel.draw(at: NSPoint(x: (scaledWidth - screenLabelSize.width) / 2, y: scaledHeight * 0.5 - screenLabelSize.height / 2), withAttributes: screenAttrs)
        }
        
        // Center crosshair
        NSColor.red.withAlphaComponent(0.5).setStroke()
        let crosshairSize: CGFloat = 30
        let cx = scaledWidth / 2
        let cy = scaledHeight / 2
        
        let crossH = NSBezierPath()
        crossH.move(to: NSPoint(x: cx - crosshairSize, y: cy))
        crossH.line(to: NSPoint(x: cx + crosshairSize, y: cy))
        crossH.lineWidth = 1
        crossH.stroke()
        
        let crossV = NSBezierPath()
        crossV.move(to: NSPoint(x: cx, y: cy - crosshairSize))
        crossV.line(to: NSPoint(x: cx, y: cy + crosshairSize))
        crossV.lineWidth = 1
        crossV.stroke()
        
        // Info box at top
        let boxHeight: CGFloat = 80 * scale
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSRect(x: 10, y: scaledHeight - boxHeight - 10, width: scaledWidth - 20, height: boxHeight).fill()
        
        NSColor.gray.setStroke()
        let boxPath = NSBezierPath(rect: NSRect(x: 10, y: scaledHeight - boxHeight - 10, width: scaledWidth - 20, height: boxHeight))
        boxPath.lineWidth = 1
        boxPath.stroke()
        
        // Text - Part name
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 16),
            .foregroundColor: NSColor.black
        ]
        let title = part.displayName
        title.draw(at: NSPoint(x: 20, y: scaledHeight - 35), withAttributes: titleAttrs)
        
        // Text - Dimensions
        let dimAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.darkGray
        ]
        let dimText = "Size: \(part.dimensions.width) × \(part.dimensions.height) pixels"
        dimText.draw(at: NSPoint(x: 20, y: scaledHeight - 55), withAttributes: dimAttrs)
        
        // Text - Filename
        let fileAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.blue
        ]
        let fileText = "Save as: \(part.id).png"
        fileText.draw(at: NSPoint(x: 20, y: scaledHeight - 75), withAttributes: fileAttrs)
        
        // Type badge
        var typeText = part.type.rawValue.uppercased()
        if part.hasAlpha == true {
            typeText += " + ALPHA"
        }
        if part.emissive == true {
            typeText += " + GLOW"
        }
        let typeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 10),
            .foregroundColor: NSColor.white,
            .backgroundColor: partTypeColor(part.type)
        ]
        let typeSize = typeText.size(withAttributes: typeAttrs)
        typeText.draw(at: NSPoint(x: scaledWidth - typeSize.width - 20, y: scaledHeight - 35), withAttributes: typeAttrs)
        
        // Orientation arrow at bottom
        let arrowAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.gray
        ]
        let arrowText = "↑ TOP"
        let arrowSize = arrowText.size(withAttributes: arrowAttrs)
        arrowText.draw(at: NSPoint(x: (scaledWidth - arrowSize.width) / 2, y: 15), withAttributes: arrowAttrs)
        
        image.unlockFocus()
        
        return image
    }
    
    private func partTypeColor(_ type: TemplatePartType) -> NSColor {
        switch type {
        case .marquee: return NSColor.purple
        case .bezel: return NSColor.blue
        case .texture: return NSColor.orange
        }
    }
    
    /// Generate SVG with all parts as separate layers
    private func generateSVGTemplate(for template: CabinetTemplate) -> String {
        // Find the maximum dimensions to create a canvas
        let maxWidth = template.allParts.map { $0.dimensions.width }.max() ?? 1024
        let maxHeight = template.allParts.map { $0.dimensions.height }.max() ?? 1024
        
        var svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" 
             xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape"
             width="\(maxWidth)" height="\(maxHeight)"
             viewBox="0 0 \(maxWidth) \(maxHeight)">
        
        <title>\(template.name) Artwork Template</title>
        <desc>Cabinet artwork template with layers for each part. Open in Photoshop, Illustrator, or Inkscape.</desc>
        
        <!-- INSTRUCTIONS:
             Each cabinet part is a separate layer (group).
             Export each layer as a separate PNG file.
             Use the exact filenames shown in each layer name.
        -->
        
        """
        
        for (index, part) in template.allParts.enumerated() {
            let layerName = "\(part.id) (\(part.dimensions.width)x\(part.dimensions.height))"
            let visible = index == 0 ? "display:inline" : "display:none"
            
            svg += """
            
            <!-- Layer: \(part.displayName) - Export as: \(part.id).png -->
            <g id="\(part.id)" 
               inkscape:groupmode="layer" 
               inkscape:label="\(layerName)"
               style="\(visible)">
               
               <!-- Canvas boundary -->
               <rect x="0" y="0" width="\(part.dimensions.width)" height="\(part.dimensions.height)" 
                     fill="none" stroke="#cccccc" stroke-width="1" stroke-dasharray="5,5"/>
               
               <!-- Safe area (5% inset) -->
               <rect x="\(Int(Double(part.dimensions.width) * 0.05))" 
                     y="\(Int(Double(part.dimensions.height) * 0.05))" 
                     width="\(Int(Double(part.dimensions.width) * 0.9))" 
                     height="\(Int(Double(part.dimensions.height) * 0.9))" 
                     fill="none" stroke="#0088ff" stroke-width="1" stroke-dasharray="3,3" opacity="0.5"/>
               
               <!-- Center guides -->
               <line x1="\(part.dimensions.width / 2)" y1="0" 
                     x2="\(part.dimensions.width / 2)" y2="\(part.dimensions.height)" 
                     stroke="#ff00ff" stroke-width="0.5" stroke-dasharray="2,2" opacity="0.3"/>
               <line x1="0" y1="\(part.dimensions.height / 2)" 
                     x2="\(part.dimensions.width)" y2="\(part.dimensions.height / 2)" 
                     stroke="#ff00ff" stroke-width="0.5" stroke-dasharray="2,2" opacity="0.3"/>
               
               <!-- Label -->
               <text x="10" y="25" font-family="Arial" font-size="14" fill="#666666">
                   \(part.displayName) - \(part.dimensions.width)×\(part.dimensions.height)px
               </text>
               <text x="10" y="45" font-family="monospace" font-size="12" fill="#0066cc">
                   Export as: \(part.id).png
               </text>
               
               <!-- YOUR ARTWORK GOES HERE -->
               <!-- Delete guides before export -->
               
            </g>
            
            """
        }
        
        svg += """
        
        </svg>
        """
        
        return svg
    }
    
    /// Generate JSON manifest for artwork import
    private func generateManifest(for template: CabinetTemplate) -> String {
        var manifest: [String: Any] = [
            "template_id": template.id,
            "template_name": template.name,
            "version": "1.0",
            "crt_orientation": template.crtOrientation,
            "parts": []
        ]
        
        var partsArray: [[String: Any]] = []
        for part in template.allParts {
            var partDict: [String: Any] = [
                "id": part.id,
                "display_name": part.displayName,
                "filename": "\(part.id).png",
                "width": part.dimensions.width,
                "height": part.dimensions.height,
                "type": part.type.rawValue,
                "required": true  // All parts required now
            ]
            
            if part.hasAlpha == true {
                partDict["has_alpha"] = true
            }
            if part.emissive == true {
                partDict["emissive"] = true
            }
            if let mirrorOf = part.mirrorOf {
                partDict["mirror_of"] = mirrorOf
            }
            if let patterns = part.filePatterns as [String]? {
                partDict["accepted_filenames"] = patterns + [part.id]
            }
            
            partsArray.append(partDict)
        }
        
        manifest["parts"] = partsArray
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "{}"
    }
    
    private func generatePhotoshopInstructions(for template: CabinetTemplate) -> String {
        return """
        PHOTOSHOP / ILLUSTRATOR INSTRUCTIONS
        ====================================
        
        Template: \(template.name)
        
        OPTION 1: Using SVG File (Recommended)
        --------------------------------------
        
        1. Open "\(template.name)-template.svg" in Photoshop or Illustrator
        2. Each cabinet part is a separate layer
        3. Work on one layer at a time:
           - Show the layer you want to edit
           - Create your artwork within the guides
           - Hide guide layers before export
        4. Export each layer as PNG:
           - File > Export > Export As (Photoshop)
           - File > Export > Export for Screens (Illustrator)
           - Use the exact filename shown in the layer name
        
        OPTION 2: Using Individual Templates
        ------------------------------------
        
        1. Open individual PNG files from the "Templates" folder
        2. Each file is at the exact required dimensions
        3. Create your artwork:
           - RED line = cut boundary (don't exceed)
           - CYAN dashed line = safe area (keep important content inside)
           - MAGENTA lines = center guides
           - Gray checkered = transparent areas
        4. Delete the guide layers before saving
        5. Save as PNG with the same filename
        
        PART LIST
        ---------
        
        """
        + template.allParts.map { part in
            """
            \(part.displayName)
            • Filename: \(part.id).png
            • Size: \(part.dimensions.width) × \(part.dimensions.height) pixels
            • Type: \(part.type.rawValue)\(part.hasAlpha == true ? " (with transparency)" : "")\(part.emissive == true ? " (will glow)" : "")
            
            """
        }.joined()
        + """
        
        IMPORTING BACK INTO APP
        -----------------------
        
        When you're done creating artwork:
        
        1. Put all your PNG files in a single folder
        2. Name them exactly as specified above (or use the filename patterns)
        3. In the app, use "Import Artwork Pack" button
        4. Select your folder
        5. The app will automatically match files to cabinet parts
        
        Alternatively, ZIP all PNG files and import the ZIP directly.
        
        TIPS
        ----
        
        • Work at the exact dimensions specified
        • Use PNG format for transparency support
        • Keep important content in the safe area
        • Test your artwork in the app preview before final build
        
        """
    }
    
    private func generateReadme(for template: CabinetTemplate) -> String {
        var readme = """
        \(template.name) - Artwork Template Pack
        \(String(repeating: "=", count: template.name.count + 24))
        
        Template ID: \(template.id)
        CRT Orientation: \(template.crtOrientation)
        Total Parts: \(template.allParts.count)
        
        FOLDER CONTENTS
        ---------------
        
        📁 Templates/     - Full-size PNG templates (work on these)
        📁 Guides/        - Reference guides with labels
        📄 \(template.name)-template.svg  - All-in-one layered file for Photoshop/Illustrator
        📄 manifest.json  - Import manifest (do not edit)
        📄 README.txt     - This file
        📄 PHOTOSHOP-INSTRUCTIONS.txt  - Detailed editing instructions
        
        QUICK START
        -----------
        
        1. Open the SVG file OR individual templates from Templates/ folder
        2. Create your artwork for each piece
        3. Export/save each piece as PNG with exact filenames
        4. Import the completed artwork back into RetroVisionCabs
        
        ALL ARTWORK PIECES
        ------------------
        
        """
        
        for part in template.allParts {
            readme += """
            
            [\(part.type.rawValue.uppercased())] \(part.displayName)
            • Filename: \(part.id).png
            • Dimensions: \(part.dimensions.width) × \(part.dimensions.height) pixels
            """
            if part.hasAlpha == true {
                readme += "\n• Supports transparency (use PNG)"
            }
            if part.emissive == true {
                readme += "\n• Will be illuminated on the cabinet"
            }
            if let mirrorOf = part.mirrorOf {
                readme += "\n• Can use same artwork as: \(mirrorOf)"
            }
            readme += "\n"
        }
        
        readme += """
        
        
        FILE FORMAT REQUIREMENTS
        ------------------------
        
        • Format: PNG (recommended) or JPG
        • Color: RGB
        • Transparency: Use PNG for parts that need transparent areas
        • Dimensions: MUST match exactly as specified above
        
        
        NAMING CONVENTION
        -----------------
        
        Files MUST be named exactly as shown above.
        
        Examples:
        - marquee.png (for marquee)
        - bezel.png (for bezel/screen frame)
        - side-left.png (for left side panel)
        - side-right.png (for right side panel)
        - control-panel.png (for control panel)
        
        
        IMPORTING COMPLETED ARTWORK
        ---------------------------
        
        1. Place all PNG files in a single folder
        2. In RetroVisionCabs app, click "Import Artwork Pack"
        3. Select your folder or ZIP file
        4. The app will automatically match files to parts
        5. Review the mappings and adjust if needed
        
        """
        
        return readme
    }
    
    // MARK: - Artwork Import
    
    /// Import artwork from a folder or ZIP file
    func importArtworkPack(from url: URL, for template: CabinetTemplate) -> [String: ArtworkMapping] {
        var mappings: [String: ArtworkMapping] = [:]
        
        // Initialize all parts as unmapped
        for part in template.allParts {
            mappings[part.id] = ArtworkMapping(id: part.id, file: nil, status: .unmapped)
        }
        
        // Determine if it's a folder or ZIP
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return mappings
        }
        
        var artworkFiles: [URL] = []
        
        if isDirectory.boolValue {
            // Import from folder
            artworkFiles = collectArtworkFiles(from: url)
        } else if url.pathExtension.lowercased() == "zip" {
            // Extract ZIP and import
            if let extractedFolder = extractZipToTemp(url) {
                artworkFiles = collectArtworkFiles(from: extractedFolder)
            }
        }
        
        // Map files to parts
        for file in artworkFiles {
            let filename = file.deletingPathExtension().lastPathComponent.lowercased()
            
            // Find matching part
            for part in template.allParts {
                // Check exact match first
                if filename == part.id.lowercased() {
                    mappings[part.id] = ArtworkMapping(id: part.id, file: file, status: .autoMapped)
                    break
                }
                
                // Check file patterns
                for pattern in part.filePatterns {
                    if filename.contains(pattern.lowercased()) || pattern.lowercased().contains(filename) {
                        if mappings[part.id]?.file == nil {
                            mappings[part.id] = ArtworkMapping(id: part.id, file: file, status: .autoMapped)
                        }
                        break
                    }
                }
            }
        }
        
        // Handle mirror relationships
        for part in template.allParts {
            if let mirrorOf = part.mirrorOf,
               mappings[part.id]?.file == nil,
               let sourceMapping = mappings[mirrorOf],
               sourceMapping.file != nil {
                mappings[part.id] = ArtworkMapping(
                    id: part.id,
                    file: sourceMapping.file,
                    status: .autoMapped
                )
            }
        }
        
        return mappings
    }
    
    private func collectArtworkFiles(from folder: URL) -> [URL] {
        var files: [URL] = []
        let imageExtensions = ["png", "jpg", "jpeg", "tiff", "bmp", "mp4", "mov", "m4v"]
        
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else {
            return files
        }
        
        for case let fileURL as URL in enumerator {
            if imageExtensions.contains(fileURL.pathExtension.lowercased()) {
                files.append(fileURL)
            }
        }
        
        return files
    }
    
    private func extractZipToTemp(_ zipURL: URL) -> URL? {
        // Use configured temp to avoid filling system disk
        let paths = RetroVisionPaths.load()
        let tempDir = URL(fileURLWithPath: paths.templateZipsTempDir)
            .appendingPathComponent(UUID().uuidString)
        
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            // Use ditto to extract (built-in macOS tool)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-xk", zipURL.path, tempDir.path]
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                return tempDir
            }
        } catch {
            print("Failed to extract ZIP: \(error)")
        }
        
        return nil
    }
}

// MARK: - NSImage Extension for PNG Export

extension NSImage {
    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
