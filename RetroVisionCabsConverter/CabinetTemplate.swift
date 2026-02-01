//
//  CabinetTemplate.swift
//  RetroVisionCabsConverter
//
//  Cabinet template data models for the Build workflow
//

import Foundation
import SwiftUI

// MARK: - Template Part Type (distinct from DescriptionParser's PartType)

enum TemplatePartType: String, Codable {
    case texture = "texture"
    case marquee = "marquee"
    case bezel = "bezel"
    
    var yamlType: String {
        switch self {
        case .texture: return "default"
        case .marquee: return "marquee"
        case .bezel: return "bezel"
        }
    }
    
    /// Convert to DescriptionParser's PartType
    var descriptionPartType: PartType {
        switch self {
        case .texture: return .default
        case .marquee: return .marquee
        case .bezel: return .bezel
        }
    }
}

// MARK: - Template Part Color

struct TemplatePartColor: Codable, Equatable {
    let r: Int
    let g: Int
    let b: Int
    let intensity: Double?
    
    var swiftUIColor: Color {
        Color(
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0
        )
    }
}

// MARK: - Part Dimensions

struct PartDimensions: Codable, Equatable {
    let width: Int
    let height: Int
    
    var aspectRatio: Double {
        Double(width) / Double(height)
    }
    
    var displayString: String {
        "\(width) × \(height)"
    }
}

// MARK: - Template Part

struct TemplatePart: Codable, Identifiable, Equatable {
    let id: String
    let meshName: String
    let displayName: String
    let description: String?
    let dimensions: PartDimensions
    let filePatterns: [String]
    let required: Bool
    let type: TemplatePartType
    let hasAlpha: Bool?
    let emissive: Bool?
    let defaultColor: TemplatePartColor?
    let mirrorOf: String?
    let flipHorizontal: Bool?  // For right side panels - flip artwork horizontally
    
    enum CodingKeys: String, CodingKey {
        case id, meshName, displayName, description, dimensions
        case filePatterns, required, type, hasAlpha, emissive
        case defaultColor, mirrorOf, flipHorizontal
    }
    
    // Memberwise initializer for programmatic creation
    init(
        id: String,
        meshName: String,
        displayName: String,
        description: String?,
        dimensions: PartDimensions,
        filePatterns: [String],
        required: Bool,
        type: TemplatePartType,
        hasAlpha: Bool?,
        emissive: Bool?,
        defaultColor: TemplatePartColor?,
        mirrorOf: String?,
        flipHorizontal: Bool?
    ) {
        self.id = id
        self.meshName = meshName
        self.displayName = displayName
        self.description = description
        self.dimensions = dimensions
        self.filePatterns = filePatterns
        self.required = required
        self.type = type
        self.hasAlpha = hasAlpha
        self.emissive = emissive
        self.defaultColor = defaultColor
        self.mirrorOf = mirrorOf
        self.flipHorizontal = flipHorizontal
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        meshName = try container.decode(String.self, forKey: .meshName)
        displayName = try container.decode(String.self, forKey: .displayName)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        dimensions = try container.decode(PartDimensions.self, forKey: .dimensions)
        filePatterns = try container.decode([String].self, forKey: .filePatterns)
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        
        // Parse type string to enum
        let typeString = try container.decodeIfPresent(String.self, forKey: .type) ?? "texture"
        type = TemplatePartType(rawValue: typeString) ?? .texture
        
        hasAlpha = try container.decodeIfPresent(Bool.self, forKey: .hasAlpha)
        emissive = try container.decodeIfPresent(Bool.self, forKey: .emissive)
        defaultColor = try container.decodeIfPresent(TemplatePartColor.self, forKey: .defaultColor)
        mirrorOf = try container.decodeIfPresent(String.self, forKey: .mirrorOf)
        flipHorizontal = try container.decodeIfPresent(Bool.self, forKey: .flipHorizontal)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(meshName, forKey: .meshName)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(dimensions, forKey: .dimensions)
        try container.encode(filePatterns, forKey: .filePatterns)
        try container.encode(required, forKey: .required)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(hasAlpha, forKey: .hasAlpha)
        try container.encodeIfPresent(emissive, forKey: .emissive)
        try container.encodeIfPresent(defaultColor, forKey: .defaultColor)
        try container.encodeIfPresent(mirrorOf, forKey: .mirrorOf)
        try container.encodeIfPresent(flipHorizontal, forKey: .flipHorizontal)
    }
    
    /// Check if a filename matches this part's patterns
    func matches(filename: String) -> Bool {
        let name = filename.lowercased()
        let baseName = (name as NSString).deletingPathExtension
        
        for pattern in filePatterns {
            if baseName.contains(pattern.lowercased()) {
                return true
            }
        }
        return false
    }
}

// MARK: - Cabinet Template

// MARK: - T-Molding Configuration

struct TMoldingColorOption: Codable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let hex: String
    
    var color: Color {
        Color(hex: hex) ?? .gray
    }
}

struct TMoldingConfig: Codable, Equatable {
    let id: String
    let meshName: String
    let displayName: String
    let description: String?
    let colorOptions: [TMoldingColorOption]
    let supportsLED: Bool?
    let ledAnimations: [String]?
}

// MARK: - Cabinet Template

struct CabinetTemplate: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let model: String
    let defaultMaterial: String?
    let crtOrientation: String
    let previewImage: String?
    let parts: [TemplatePart]
    let optionalParts: [TemplatePart]?
    let tMolding: TMoldingConfig?
    
    // Pre-built template properties
    let type: String?  // "prebuilt" or "custom"
    let cabinetType: String?  // "upright", "cocktail", "lightgun", "specialty", "driving"
    let prebuilt: Bool?
    let supportsCustomArtwork: Bool?
    
    /// Check if this is a pre-built template with baked artwork
    var isPrebuilt: Bool {
        prebuilt == true || type == "prebuilt"
    }
    
    /// Check if custom artwork can be applied
    var canCustomize: Bool {
        supportsCustomArtwork ?? !isPrebuilt
    }
    
    /// All parts including optional ones
    var allParts: [TemplatePart] {
        parts + (optionalParts ?? [])
    }
    
    /// Only required parts
    var requiredParts: [TemplatePart] {
        parts.filter { $0.required }
    }
    
    /// Path to the template bundle (set after loading)
    var bundlePath: String?
    
    /// Get the full model path
    var modelPath: String? {
        guard let bundlePath = bundlePath else { return nil }
        return (bundlePath as NSString).appendingPathComponent(model)
    }
    
    /// Get the preview image path
    var previewImagePath: String? {
        guard let bundlePath = bundlePath, let previewImage = previewImage else { return nil }
        return (bundlePath as NSString).appendingPathComponent(previewImage)
    }
    
    /// Get the preview NSImage for UI display
    var previewNSImage: NSImage? {
        // First try the configured preview image
        if let path = previewImagePath {
            return NSImage(contentsOfFile: path)
        }
        // Fall back to preview.png in the bundle
        if let bundlePath = bundlePath {
            let defaultPath = (bundlePath as NSString).appendingPathComponent("preview.png")
            return NSImage(contentsOfFile: defaultPath)
        }
        return nil
    }
    
    // Custom coding keys to handle bundlePath
    enum CodingKeys: String, CodingKey {
        case id, name, description, model, defaultMaterial
        case crtOrientation, previewImage, parts, optionalParts, tMolding
        case type, cabinetType, prebuilt, supportsCustomArtwork
    }
    
    static func == (lhs: CabinetTemplate, rhs: CabinetTemplate) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Color Extension for Hex

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
    
    var hexString: String {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(components.redComponent * 255)
        let g = Int(components.greenComponent * 255)
        let b = Int(components.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Artwork Mapping

struct ArtworkMapping: Identifiable, Equatable {
    let id: String  // Part ID
    var file: URL?
    var status: MappingStatus
    var rotation: Int = 0  // 0, 90, 180, 270 degrees
    var invertX: Bool = false
    var invertY: Bool = false
    var useDefaultBlack: Bool = false  // Use solid black color instead of artwork
    
    /// Whether this part has valid content (either file or default black)
    var hasContent: Bool {
        file != nil || useDefaultBlack
    }
    
    enum MappingStatus: Equatable {
        case unmapped
        case autoMapped
        case manuallyMapped
        case defaultBlack
        case invalid(String)
        
        var icon: String {
            switch self {
            case .unmapped: return "circle.dashed"
            case .autoMapped: return "wand.and.stars"
            case .manuallyMapped: return "checkmark.circle.fill"
            case .defaultBlack: return "square.fill"
            case .invalid: return "exclamationmark.triangle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .unmapped: return .secondary
            case .autoMapped: return .blue
            case .manuallyMapped: return .green
            case .defaultBlack: return .gray
            case .invalid: return .red
            }
        }
    }
}

// MARK: - Build Configuration

// MARK: - T-Molding Settings

struct TMoldingSettings: Equatable {
    var enabled: Bool = true
    var colorHex: String = "#1a1a1a"  // Default black
    var colorName: String = "Black"
    var ledEnabled: Bool = false
    var ledAnimation: String = "pulse"  // pulse, chase, rainbow, flash
    var ledSpeed: Double = 1.0  // Animation speed multiplier
    
    var color: Color {
        Color(hex: colorHex) ?? .black
    }
}

// MARK: - Build Configuration

struct BuildConfiguration: Equatable {
    var template: CabinetTemplate?
    var gameName: String = ""
    var romName: String = ""
    var year: String = ""
    var videoFile: URL?
    var artworkMappings: [String: ArtworkMapping] = [:]
    var outputFolder: URL?
    var tMoldingSettings: TMoldingSettings = TMoldingSettings()
    
    /// Check if the configuration is valid for building
    /// Requires ALL parts to have content (artwork OR default black)
    var isValid: Bool {
        guard let template = template else { return false }
        guard !gameName.isEmpty else { return false }
        
        // Check ALL parts have content (either artwork or default black)
        for part in template.parts {
            guard let mapping = artworkMappings[part.id],
                  mapping.hasContent else {
                return false
            }
        }
        
        return true
    }
    
    /// Get ALL missing parts (not mapped and not using default black)
    var missingParts: [TemplatePart] {
        guard let template = template else { return [] }
        return template.parts.filter { part in
            guard let mapping = artworkMappings[part.id] else { return true }
            return !mapping.hasContent
        }
    }
    
    /// Check if all parts have content (artwork or default black)
    var allArtworkProvided: Bool {
        guard let template = template else { return false }
        return template.parts.allSatisfy { part in
            artworkMappings[part.id]?.hasContent ?? false
        }
    }
    
    /// Get mapped parts count (including default black)
    var mappedCount: Int {
        artworkMappings.values.filter { $0.hasContent }.count
    }
    
    /// Get total parts count
    var totalPartsCount: Int {
        template?.parts.count ?? 0
    }
    
    /// Progress percentage for artwork completion
    var artworkProgress: Double {
        guard totalPartsCount > 0 else { return 0 }
        return Double(mappedCount) / Double(totalPartsCount)
    }
}

// MARK: - Template Picker View

struct TemplatePicker: View {
    @Binding var selectedTemplate: CabinetTemplate?
    let templates: [CabinetTemplate]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cabinet Template")
                .font(.headline)
            
            HStack(spacing: 12) {
                ForEach(templates) { template in
                    TemplatePickerCard(
                        template: template,
                        isSelected: selectedTemplate?.id == template.id
                    )
                    .onTapGesture {
                        selectedTemplate = template
                    }
                }
            }
        }
    }
}

struct TemplatePickerCard: View {
    let template: CabinetTemplate
    let isSelected: Bool
    
    /// Get appropriate SF Symbol for template type
    var templateIcon: String {
        switch template.id.lowercased() {
        case "upright": return "arcade.stick.console"
        case "neogeo": return "gamecontroller.fill"
        case "vertical": return "rectangle.portrait.fill"
        case "defender": return "display"
        case "driving": return "car.fill"
        case "flightstick": return "airplane"
        case "lightgun": return "scope"
        case "cocktail": return "tablecells"
        default: return "cube.fill"
        }
    }
    
    var body: some View {
        VStack(spacing: 6) {
            // Preview image - prominent
            if let image = template.previewNSImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .cornerRadius(6)
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    )
            }
            
            // Template name
            Text(template.name)
                .font(.caption)
                .fontWeight(isSelected ? .bold : .medium)
                .lineLimit(1)
            
            // Icon underneath
            Image(systemName: templateIcon)
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .help(template.description)
    }
}
