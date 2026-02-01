import Foundation
import AppKit

// MARK: - Discovered Cabinet Model

/// Represents a cabinet discovered from an Age of Joy cabinet pack
struct DiscoveredCabinet: Identifiable, Hashable {
    var id: String
    var name: String
    var displayName: String
    var sourcePath: URL
    var sourceType: SourceType
    
    // Metadata from description.yaml
    var game: String?
    var rom: String?
    var author: String?
    var year: String?
    
    // Model info
    var glbFile: URL?
    var glbMeshNames: [String] = []
    
    // Cabinet dimensions (from GLB bounding box analysis)
    var dimensions: CabinetDimensions?
    var cabinetShape: CabinetShape?
    
    // Assets discovered
    var assets: [DiscoveredAsset] = []
    var videoFile: URL?
    
    // Template matching
    var suggestedTemplateID: String = "upright"
    var meshMappings: [String: String] = [:] // meshName -> assetFile
    
    // Preview
    var previewImage: NSImage?
    var previewGenerated: Bool = false
    
    // Analysis results
    var completenessScore: Double {
        guard !requiredParts.isEmpty else { return 1.0 }
        let mapped = requiredParts.filter { meshMappings[$0] != nil }.count
        return Double(mapped) / Double(requiredParts.count)
    }
    
    var requiredParts: [String] {
        ["left", "right", "marquee", "bezel"]
    }
    
    var missingParts: [String] {
        requiredParts.filter { meshMappings[$0] == nil }
    }
    
    var hasAllRequiredAssets: Bool {
        missingParts.isEmpty
    }
    
    enum SourceType: String, Codable {
        case folder
        case zip
    }
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: DiscoveredCabinet, rhs: DiscoveredCabinet) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Discovered Asset

/// An image asset found in a cabinet pack
struct DiscoveredAsset: Identifiable, Hashable {
    let id: String
    let filename: String
    let url: URL
    let fileSize: Int64
    
    // Inferred mapping
    var inferredMeshName: String?
    var isUsed: Bool = false
    
    // Preview
    var thumbnail: NSImage?
    
    init(url: URL) {
        self.id = url.lastPathComponent
        self.filename = url.lastPathComponent
        self.url = url
        self.fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        self.inferredMeshName = Self.inferMeshName(from: url.lastPathComponent)
    }
    
    /// Infer the mesh name from the filename
    static func inferMeshName(from filename: String) -> String? {
        let name = (filename as NSString).deletingPathExtension.lowercased()
        
        // Direct matches
        let directMatches = [
            "left", "right", "marquee", "bezel", "front", "joystick",
            "joystick-down", "joystickdown", "coin-slot", "coinslot",
            "cd-25c", "cd-slot", "cd-upper", "cd-lower", "cd-return",
            "overlay", "mirror", "dial"
        ]
        
        for match in directMatches {
            if name == match || name == match.replacingOccurrences(of: "-", with: "") {
                return match
            }
        }
        
        // Pattern matches
        if name.contains("side") && name.contains("left") { return "left" }
        if name.contains("side") && name.contains("right") { return "right" }
        if name.contains("marquee") { return "marquee" }
        if name.contains("bezel") { return "bezel" }
        if name.contains("kick") || name.contains("front") { return "front" }
        if name.contains("joystick") && name.contains("down") { return "joystick-down" }
        if name.contains("joystick") || name.contains("control") || name.contains("cpo") { return "joystick" }
        if name.contains("coin") { return "coin-slot" }
        
        return nil
    }
}

// MARK: - Cabinet Dimensions

/// 3D bounding box dimensions from GLB analysis
struct CabinetDimensions: Codable, Equatable {
    let width: Double   // X axis (left-right)
    let height: Double  // Y axis (floor-top)
    let depth: Double   // Z axis (front-back)
    
    /// Aspect ratio (width:depth) for shape comparison
    var widthToDepthRatio: Double {
        guard depth > 0 else { return 1.0 }
        return width / depth
    }
    
    /// Aspect ratio (height:width) - tall vs wide
    var heightToWidthRatio: Double {
        guard width > 0 else { return 1.0 }
        return height / width
    }
    
    /// Compare dimensions similarity (0-1, higher = more similar)
    func similarity(to other: CabinetDimensions, tolerance: Double = 0.15) -> Double {
        let widthDiff = abs(width - other.width) / max(width, other.width, 0.001)
        let heightDiff = abs(height - other.height) / max(height, other.height, 0.001)
        let depthDiff = abs(depth - other.depth) / max(depth, other.depth, 0.001)
        
        // Weight height more heavily as it's most distinctive
        let avgDiff = (widthDiff + heightDiff * 1.5 + depthDiff) / 3.5
        return max(0, 1.0 - avgDiff)
    }
    
    /// Normalized dimensions (scale to unit height)
    var normalized: CabinetDimensions {
        guard height > 0 else { return self }
        return CabinetDimensions(
            width: width / height,
            height: 1.0,
            depth: depth / height
        )
    }
}

// MARK: - Cabinet Shape

/// Analyzed shape characteristics of a cabinet
struct CabinetShape: Codable, Equatable {
    let type: CabinetType
    let hasScreen: Bool
    let hasMarquee: Bool
    let hasControlPanel: Bool
    let hasJoystick: Bool
    let hasButtons: Bool
    let hasWheel: Bool
    let hasPedals: Bool
    let hasGun: Bool
    let hasCoinSlot: Bool
    let hasMirror: Bool
    let screenOrientation: ScreenOrientation
    let controlCount: Int  // Number of control-related meshes
    
    enum CabinetType: String, Codable {
        case upright = "upright"
        case cocktail = "cocktail"
        case driving = "driving"
        case lightgun = "lightgun"
        case flightstick = "flightstick"
        case neogeo = "neogeo"
        case pinball = "pinball"
        case custom = "custom"
        
        var displayName: String {
            switch self {
            case .upright: return "Upright"
            case .cocktail: return "Cocktail"
            case .driving: return "Driving"
            case .lightgun: return "Light Gun"
            case .flightstick: return "Flight Stick"
            case .neogeo: return "Neo Geo"
            case .pinball: return "Pinball"
            case .custom: return "Custom"
            }
        }
    }
    
    enum ScreenOrientation: String, Codable {
        case vertical = "vertical"
        case horizontal = "horizontal"
        case unknown = "unknown"
    }
    
    /// Calculate similarity score to another shape (0-1)
    func similarity(to other: CabinetShape) -> Double {
        var score = 0.0
        var weights = 0.0
        
        // Type match is most important
        if type == other.type {
            score += 3.0
        }
        weights += 3.0
        
        // Key features
        let features: [(Bool, Bool, Double)] = [
            (hasScreen, other.hasScreen, 1.0),
            (hasMarquee, other.hasMarquee, 0.5),
            (hasControlPanel, other.hasControlPanel, 0.8),
            (hasJoystick, other.hasJoystick, 0.7),
            (hasButtons, other.hasButtons, 0.5),
            (hasWheel, other.hasWheel, 1.5),
            (hasPedals, other.hasPedals, 1.2),
            (hasGun, other.hasGun, 1.5),
            (hasCoinSlot, other.hasCoinSlot, 0.3),
            (hasMirror, other.hasMirror, 0.8),
        ]
        
        for (a, b, weight) in features {
            if a == b {
                score += weight
            }
            weights += weight
        }
        
        // Screen orientation
        if screenOrientation == other.screenOrientation {
            score += 0.8
        }
        weights += 0.8
        
        return score / weights
    }
}

// MARK: - Template Match Result

/// Result of matching a cabinet to templates
struct TemplateMatchResult: Identifiable {
    let id = UUID()
    let templateID: String
    let templateName: String
    let confidence: Double  // 0-1, higher = better match
    let dimensionScore: Double
    let shapeScore: Double
    let meshMatchCount: Int
    let totalMeshes: Int
    
    var isGoodMatch: Bool {
        confidence >= 0.7
    }
    
    var isExactMatch: Bool {
        confidence >= 0.9
    }
    
    var confidenceDescription: String {
        switch confidence {
        case 0.9...: return "Excellent"
        case 0.75..<0.9: return "Good"
        case 0.5..<0.75: return "Fair"
        default: return "Poor"
        }
    }
}

// MARK: - Gallery Cabinet Description (YAML)

/// Parsed description.yaml structure for gallery analysis
struct GalleryCabinetDescription {
    let name: String?
    let game: String?
    let rom: String?
    let year: Int?
    let cabinetAuthor: String?
    
    let model: ModelDescription?
    let video: VideoDescription?
    let material: String?
    let parts: [PartDescription]?
    let crt: CRTDescription?
    
    struct ModelDescription {
        let file: String?
    }
    
    struct VideoDescription {
        let file: String?
        let invertx: Bool?
        let inverty: Bool?
    }
    
    struct PartDescription {
        let name: String
        let type: String?
        let art: ArtDescription?
        let color: ColorDescription?
        let material: String?
    }
    
    struct ArtDescription {
        let file: String?
        let invertx: Bool?
        let inverty: Bool?
        let rotate: Double?
    }
    
    struct ColorDescription {
        let r: Int?
        let g: Int?
        let b: Int?
        let intensity: Double?
    }
    
    struct CRTDescription {
        let type: String?
        let orientation: String?
    }
}

// MARK: - Gallery State

/// State management for the cabinet gallery
class CabinetGalleryState: ObservableObject {
    @Published var cabinets: [DiscoveredCabinet] = []
    @Published var selectedCabinets: Set<String> = []
    @Published var isScanning: Bool = false
    @Published var isGeneratingPreviews: Bool = false
    @Published var scanProgress: Double = 0
    @Published var previewProgress: Double = 0
    @Published var currentOperation: String = ""
    @Published var errorMessage: String?
    
    @Published var filterText: String = ""
    @Published var showIncomplete: Bool = true
    @Published var sortOrder: SortOrder = .name
    
    enum SortOrder: String, CaseIterable {
        case name = "Name"
        case completeness = "Completeness"
        case assetCount = "Asset Count"
    }
    
    var filteredCabinets: [DiscoveredCabinet] {
        var result = cabinets
        
        // Filter by text
        if !filterText.isEmpty {
            result = result.filter {
                $0.displayName.localizedCaseInsensitiveContains(filterText) ||
                $0.name.localizedCaseInsensitiveContains(filterText)
            }
        }
        
        // Filter incomplete
        if !showIncomplete {
            result = result.filter { $0.hasAllRequiredAssets }
        }
        
        // Sort
        switch sortOrder {
        case .name:
            result.sort { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
        case .completeness:
            result.sort { $0.completenessScore > $1.completenessScore }
        case .assetCount:
            result.sort { $0.assets.count > $1.assets.count }
        }
        
        return result
    }
    
    var selectedCount: Int {
        selectedCabinets.count
    }
    
    var completeCount: Int {
        cabinets.filter { $0.hasAllRequiredAssets }.count
    }
    
    func toggleSelection(_ cabinetID: String) {
        if selectedCabinets.contains(cabinetID) {
            selectedCabinets.remove(cabinetID)
        } else {
            selectedCabinets.insert(cabinetID)
        }
    }
    
    func selectAll() {
        selectedCabinets = Set(filteredCabinets.map { $0.id })
    }
    
    func selectComplete() {
        selectedCabinets = Set(filteredCabinets.filter { $0.hasAllRequiredAssets }.map { $0.id })
    }
    
    func clearSelection() {
        selectedCabinets.removeAll()
    }
}
