//
//  PropsTemplateManager.swift
//  RetroVisionCabsConverter
//
//  Manages prop templates for reusable configurations
//

import Foundation
import AppKit

// MARK: - Props Template Manager

class PropsTemplateManager: ObservableObject {
    static let shared = PropsTemplateManager()
    
    private let fileManager = FileManager.default
    private let templatesDirectory: URL
    
    @Published var templates: [PropTemplate] = []
    
    init() {
        let paths = RetroVisionPaths.load()
        templatesDirectory = URL(fileURLWithPath: paths.propTemplatesDirectory)
        loadTemplates()
    }
    
    // MARK: - Template Loading
    
    func loadTemplates() {
        templates = []
        
        guard fileManager.fileExists(atPath: templatesDirectory.path) else {
            try? fileManager.createDirectory(at: templatesDirectory, withIntermediateDirectories: true)
            return
        }
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: templatesDirectory, includingPropertiesForKeys: nil)
            
            for folder in contents where folder.hasDirectoryPath {
                let configPath = folder.appendingPathComponent("prop-template.json")
                if let template = loadTemplate(from: configPath) {
                    templates.append(template)
                }
            }
            
            templates.sort { $0.name < $1.name }
        } catch {
            print("Error loading prop templates: \(error)")
        }
    }
    
    private func loadTemplate(from path: URL) -> PropTemplate? {
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? JSONDecoder().decode(PropTemplate.self, from: data)
    }
    
    // MARK: - Template Creation
    
    /// Create a template from a discovered prop
    func createTemplate(from prop: DiscoveredProp, preview: NSImage?) -> PropTemplate? {
        let templateID = prop.name.lowercased().replacingOccurrences(of: " ", with: "-")
        let templateFolder = templatesDirectory.appendingPathComponent(templateID)
        
        // Remove existing if present
        try? fileManager.removeItem(at: templateFolder)
        
        do {
            try fileManager.createDirectory(at: templateFolder, withIntermediateDirectories: true)
            
            // Build parts from mesh mappings
            var parts: [PropTemplate.PropTemplatePart] = []
            for (meshName, texturePath) in prop.meshMappings {
                parts.append(PropTemplate.PropTemplatePart(
                    name: meshName,
                    type: "texture",
                    defaultFile: texturePath
                ))
            }
            
            // Check for video mesh
            if prop.videoInfo != nil, let videoMesh = findVideoMesh(in: prop.glbMeshNames) {
                parts.append(PropTemplate.PropTemplatePart(
                    name: videoMesh,
                    type: "video",
                    defaultFile: prop.videoInfo?.file.lastPathComponent
                ))
            }
            
            // Save preview path
            let previewPath = templateFolder.appendingPathComponent("preview.png").path
            
            // Create template config
            let template = PropTemplate(
                id: templateID,
                name: prop.displayName,
                propType: prop.propType,
                placement: prop.placement,
                modelPath: prop.glbFile?.path,
                previewPath: previewPath,
                parts: parts,
                tags: prop.tags
            )
            
            // Save template config
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let configData = try encoder.encode(template)
            try configData.write(to: templateFolder.appendingPathComponent("prop-template.json"))
            
            // Save preview if available
            if let image = preview ?? prop.previewImage {
                savePreviewImage(image, to: URL(fileURLWithPath: previewPath))
            }
            
            // Copy reference GLB if small enough (< 10MB)
            if let glbFile = prop.glbFile {
                let attrs = try? fileManager.attributesOfItem(atPath: glbFile.path)
                let size = (attrs?[.size] as? Int) ?? 0
                if size < 10_000_000 {
                    try? fileManager.copyItem(at: glbFile, to: templateFolder.appendingPathComponent("reference.glb"))
                }
            }
            
            // Reload templates
            loadTemplates()
            
            return template
            
        } catch {
            print("Error creating prop template: \(error)")
            return nil
        }
    }
    
    /// Create templates from multiple props
    func createTemplates(from props: [DiscoveredProp], progress: @escaping (Double, String) -> Void) async -> [PropTemplate] {
        var created: [PropTemplate] = []
        let total = Double(props.count)
        
        for (index, prop) in props.enumerated() {
            progress(Double(index) / total, "Creating template: \(prop.displayName)")
            
            if let template = createTemplate(from: prop, preview: prop.previewImage) {
                created.append(template)
            }
        }
        
        progress(1.0, "Created \(created.count) templates")
        return created
    }
    
    // MARK: - Template Matching
    
    /// Find best matching template for a prop
    func findMatchingTemplate(for prop: DiscoveredProp) -> PropTemplate? {
        // First try exact name match
        if let match = templates.first(where: { $0.id == prop.name.lowercased() }) {
            return match
        }
        
        // Try mesh name matching based on parts
        let propMeshes = Set(prop.glbMeshNames.map { $0.lowercased() })
        
        var bestMatch: PropTemplate?
        var bestScore = 0
        
        for template in templates {
            let templateMeshes = Set(template.parts.map { $0.name.lowercased() })
            let overlap = propMeshes.intersection(templateMeshes).count
            
            if overlap > bestScore {
                bestScore = overlap
                bestMatch = template
            }
        }
        
        // Require at least 50% part overlap
        if bestScore > 0 && !propMeshes.isEmpty && Double(bestScore) / Double(propMeshes.count) >= 0.5 {
            return bestMatch
        }
        
        return nil
    }
    
    /// Apply template settings to a prop
    func applyTemplate(_ template: PropTemplate, to prop: inout DiscoveredProp) {
        prop.propType = template.propType
        prop.placement = template.placement
        
        // Apply mesh mappings from template parts
        for part in template.parts {
            if part.type == "texture", let defaultFile = part.defaultFile {
                if prop.meshMappings[part.name] == nil {
                    prop.meshMappings[part.name] = defaultFile
                }
            }
        }
        
        // Merge tags
        prop.tags = Array(Set(prop.tags + template.tags))
    }
    
    // MARK: - Template Deletion
    
    func deleteTemplate(_ template: PropTemplate) {
        let templateFolder = templatesDirectory.appendingPathComponent(template.id)
        try? fileManager.removeItem(at: templateFolder)
        loadTemplates()
    }
    
    // MARK: - Helper Functions
    
    private func findVideoMesh(in meshNames: [String]) -> String? {
        let videoKeywords = ["screen", "display", "video", "tv", "monitor", "panel"]
        
        for mesh in meshNames {
            let meshLower = mesh.lowercased()
            for keyword in videoKeywords {
                if meshLower.contains(keyword) {
                    return mesh
                }
            }
        }
        
        return nil
    }
    
    private func savePreviewImage(_ image: NSImage, to url: URL) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return
        }
        try? pngData.write(to: url)
    }
    
    // MARK: - Template Preview
    
    func getTemplatePreview(_ template: PropTemplate) -> NSImage? {
        let previewPath = templatesDirectory
            .appendingPathComponent(template.id)
            .appendingPathComponent("preview.png")
        return NSImage(contentsOf: previewPath)
    }
}

// MARK: - Enhanced PropTemplate

extension PropTemplate {
    var previewImage: NSImage? {
        PropsTemplateManager.shared.getTemplatePreview(self)
    }
}
