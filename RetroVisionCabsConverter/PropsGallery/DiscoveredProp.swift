//
//  DiscoveredProp.swift
//  RetroVisionCabsConverter
//
//  Data models for non-cabinet props (decorations, cutouts, stages, etc.)
//

import Foundation
import AppKit

// MARK: - Prop Type

/// Types of non-cabinet props
enum PropType: String, Codable, CaseIterable {
    case cutout = "cutout"          // Flat panel/standee
    case stage = "stage"            // Stage or platform
    case decoration = "decoration"  // 3D decoration object
    case videoDisplay = "video"     // Video display/screen
    case furniture = "furniture"    // Tables, chairs, etc.
    case lighting = "lighting"      // Lamps, neon signs
    case wall = "wall"              // Wall decorations
    case floor = "floor"            // Floor items/rugs
    case unknown = "unknown"
    
    var displayName: String {
        switch self {
        case .cutout: return "Cutout/Standee"
        case .stage: return "Stage"
        case .decoration: return "Decoration"
        case .videoDisplay: return "Video Display"
        case .furniture: return "Furniture"
        case .lighting: return "Lighting"
        case .wall: return "Wall Decoration"
        case .floor: return "Floor Item"
        case .unknown: return "Unknown"
        }
    }
    
    var icon: String {
        switch self {
        case .cutout: return "person.crop.rectangle"
        case .stage: return "theatermasks"
        case .decoration: return "cube"
        case .videoDisplay: return "tv"
        case .furniture: return "sofa"
        case .lighting: return "lightbulb"
        case .wall: return "photo.artframe"
        case .floor: return "square.grid.3x3"
        case .unknown: return "questionmark.square"
        }
    }
}

// MARK: - Placement Hint

/// Suggested placement location in room
enum PlacementHint: String, Codable, CaseIterable {
    case wall = "wall"
    case floor = "floor"
    case ceiling = "ceiling"
    case corner = "corner"
    case center = "center"
    case table = "table"
    case freestanding = "freestanding"
    
    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Prop Asset

/// An asset file associated with a prop
struct PropAsset: Identifiable, Codable {
    var id: String { url.lastPathComponent }
    var url: URL
    var type: AssetType
    var thumbnail: NSImage?
    
    enum AssetType: String, Codable {
        case texture = "texture"
        case video = "video"
        case audio = "audio"
        case model = "model"
    }
    
    enum CodingKeys: String, CodingKey {
        case url, type
    }
}

// MARK: - Video Info

/// Information about a video file
struct PropVideoInfo: Codable {
    var file: URL
    var format: String          // mp4, mkv, etc.
    var duration: Double?       // seconds
    var width: Int?
    var height: Int?
    var needsConversion: Bool   // true for MKV
    var looping: Bool = true    // should loop in VisionOS
    
    var formatDisplayName: String {
        format.uppercased()
    }
    
    var isVisionOSCompatible: Bool {
        ["mp4", "m4v", "mov"].contains(format.lowercased())
    }
}

// MARK: - Prop Dimensions

/// Physical dimensions of a prop
struct PropDimensions: Codable {
    var width: Double
    var height: Double
    var depth: Double
    
    var isFlat: Bool {
        depth < 0.1 || (depth / width < 0.15 && depth / height < 0.15)
    }
    
    var volume: Double {
        width * height * depth
    }
    
    var displayString: String {
        String(format: "%.2f × %.2f × %.2f m", width, height, depth)
    }
}

// MARK: - Discovered Prop

/// A non-cabinet prop discovered during folder scanning
struct DiscoveredProp: Identifiable, Codable {
    var id: String
    var name: String
    var displayName: String
    var sourcePath: URL
    var sourceType: SourceType
    
    // Classification
    var propType: PropType = .unknown
    var placement: PlacementHint = .freestanding
    var tags: [String] = []
    
    // Model info
    var glbFile: URL?
    var glbMeshNames: [String] = []
    var dimensions: PropDimensions?
    
    // Assets
    var assets: [PropAsset] = []
    var textureFiles: [URL] = []
    var meshMappings: [String: String] = [:]  // mesh name -> texture file
    
    // Video/Audio
    var videoInfo: PropVideoInfo?
    var audioFiles: [URL] = []
    var hasVideo: Bool { videoInfo != nil }
    var hasAudio: Bool { !audioFiles.isEmpty }
    
    // YAML metadata
    var author: String?
    var version: String?
    var theme: String?
    
    // UI state (not persisted)
    var previewImage: NSImage?
    var previewGenerated: Bool = false
    var isSelected: Bool = false
    
    enum SourceType: String, Codable {
        case folder
        case zip
    }
    
    // MARK: - Coding Keys
    
    enum CodingKeys: String, CodingKey {
        case id, name, displayName, sourcePath, sourceType
        case propType, placement, tags
        case glbFile, glbMeshNames, dimensions
        case assets, textureFiles, meshMappings
        case videoInfo, audioFiles
        case author, version, theme
    }
    
    // MARK: - Computed Properties
    
    var completenessScore: Double {
        var score = 0.0
        var total = 0.0
        
        // Has GLB model (required)
        total += 1.0
        if glbFile != nil { score += 1.0 }
        
        // Has textures
        total += 0.5
        if !textureFiles.isEmpty { score += 0.5 }
        
        // Has video (optional bonus)
        if hasVideo { score += 0.25 }
        
        // Has preview
        total += 0.25
        if previewGenerated { score += 0.25 }
        
        return min(score / total, 1.0)
    }
    
    var missingParts: [String] {
        var missing: [String] = []
        if glbFile == nil { missing.append("3D Model") }
        return missing
    }
    
    // MARK: - Initialization
    
    init(id: String, name: String, displayName: String, sourcePath: URL, sourceType: SourceType) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.sourcePath = sourcePath
        self.sourceType = sourceType
    }
}

// MARK: - Prop Template

/// A reusable template for props
struct PropTemplate: Identifiable, Codable {
    var id: String
    var name: String
    var propType: PropType
    var placement: PlacementHint
    var modelPath: String?
    var previewPath: String?
    var parts: [PropTemplatePart]
    var tags: [String]
    
    var previewNSImage: NSImage? {
        guard let path = previewPath else { return nil }
        return NSImage(contentsOfFile: path)
    }
    
    struct PropTemplatePart: Codable {
        var name: String
        var type: String  // texture, video, color
        var defaultFile: String?
    }
}

// MARK: - VisionOS Export Metadata

/// Metadata exported alongside USDZ for VisionOS consumption
struct PropVisionOSMetadata: Codable {
    var id: String
    var name: String
    var type: String  // "prop"
    var propType: String
    var placement: String
    var dimensions: PropDimensions?
    var hasVideo: Bool
    var videoFile: String?
    var videoLooping: Bool
    var hasAudio: Bool
    var audioFiles: [String]
    var interactionZones: [InteractionZone]
    var tags: [String]
    var theme: String?
    var author: String?
    
    struct InteractionZone: Codable {
        var name: String
        var type: String  // blocker, trigger, etc.
    }
}

// MARK: - Saved Prop (for persistence)

struct SavedProp: Identifiable, Codable {
    var id: String
    var name: String
    var displayName: String
    var propType: PropType
    var placement: PlacementHint
    var tags: [String]
    var hasVideo: Bool
    var hasAudio: Bool
    var author: String?
    var theme: String?
    var dateAdded: Date
    var previewFileName: String?
    var assetsFolder: String  // Relative path within storage
}
