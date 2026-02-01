import Foundation

// MARK: - Data Models

enum PartType: String, Codable, CaseIterable {
    case marquee
    case bezel
    case `default`
    
    init(from string: String?) {
        switch string?.lowercased() {
        case "marquee": self = .marquee
        case "bezel": self = .bezel
        default: self = .default
        }
    }
}

struct PartColor: Codable, Equatable {
    var r: Int
    var g: Int
    var b: Int
    var intensity: Double
    
    init(r: Int = 255, g: Int = 255, b: Int = 255, intensity: Double = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.intensity = intensity
    }
}

struct ArtConfig: Codable, Equatable {
    var file: String
    var invertX: Bool
    var invertY: Bool
    var rotate: Int
    
    init(file: String, invertX: Bool = false, invertY: Bool = false, rotate: Int = 0) {
        self.file = file
        self.invertX = invertX
        self.invertY = invertY
        self.rotate = rotate
    }
}

struct CabinetPart: Identifiable, Codable, Equatable {
    var id: String { name }
    var name: String
    var type: PartType
    var art: ArtConfig?
    var material: String?
    var color: PartColor?
    var marqueeConfig: [String: String]?
    
    init(name: String, type: PartType = .default, art: ArtConfig? = nil, material: String? = nil, color: PartColor? = nil) {
        self.name = name
        self.type = type
        self.art = art
        self.material = material
        self.color = color
    }
}

struct VideoConfig: Codable, Equatable {
    var file: String?
    var invertX: Bool
    var invertY: Bool
    
    init(file: String? = nil, invertX: Bool = false, invertY: Bool = false) {
        self.file = file
        self.invertX = invertX
        self.invertY = invertY
    }
    
    var hasVideo: Bool {
        file != nil && !file!.isEmpty
    }
}

struct CRTConfig: Codable, Equatable {
    var orientation: String  // "vertical" or "horizontal"
    
    init(orientation: String = "vertical") {
        self.orientation = orientation
    }
}

struct ModelConfig: Codable, Equatable {
    var file: String?
    var style: String?
    
    init(file: String? = nil, style: String? = nil) {
        self.file = file
        self.style = style
    }
}

struct CabinetDescription: Codable, Equatable {
    var name: String
    var year: String?
    var rom: String?
    var style: String?
    var material: String?
    var model: ModelConfig?
    var video: VideoConfig?
    var crt: CRTConfig?
    var coinslot: String?
    var parts: [CabinetPart]
    
    init(name: String) {
        self.name = name
        self.parts = []
    }
}

// MARK: - Simple YAML Parser

class DescriptionParser {
    
    enum ParseError: Error, LocalizedError {
        case fileNotFound(String)
        case invalidFormat(String)
        case missingRequiredField(String)
        
        var errorDescription: String? {
            switch self {
            case .fileNotFound(let path):
                return "File not found: \(path)"
            case .invalidFormat(let detail):
                return "Invalid YAML format: \(detail)"
            case .missingRequiredField(let field):
                return "Missing required field: \(field)"
            }
        }
    }
    
    /// Parse a description.yaml file from a cabinet folder
    static func parse(cabinetPath: String) throws -> CabinetDescription {
        let yamlPath = (cabinetPath as NSString).appendingPathComponent("description.yaml")
        
        guard FileManager.default.fileExists(atPath: yamlPath) else {
            throw ParseError.fileNotFound(yamlPath)
        }
        
        let content = try String(contentsOfFile: yamlPath, encoding: .utf8)
        return try parseYAML(content, cabinetName: (cabinetPath as NSString).lastPathComponent)
    }
    
    /// Parse YAML string content
    static func parseYAML(_ content: String, cabinetName: String) throws -> CabinetDescription {
        let lines = content.components(separatedBy: .newlines)
        var description = CabinetDescription(name: cabinetName)
        
        var currentSection: String?
        var currentPart: CabinetPart?
        var currentSubSection: String?
        var inPartsArray = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            
            // Calculate indent level
            let currentIndent = line.prefix(while: { $0 == " " }).count
            
            // Check for array item (starts with -)
            if trimmed.hasPrefix("- ") {
                if currentSection == "parts" {
                    // Save previous part if exists
                    if let part = currentPart {
                        description.parts.append(part)
                    }
                    
                    // Start new part - parse the name from "- name: value"
                    let partLine = String(trimmed.dropFirst(2))
                    if let (key, value) = parseKeyValue(partLine), key == "name" {
                        currentPart = CabinetPart(name: value)
                        inPartsArray = true
                    }
                }
                continue
            }
            
            // Parse key: value pairs
            guard let (key, value) = parseKeyValue(trimmed) else {
                continue
            }
            
            // Top-level keys
            if currentIndent == 0 {
                // Save any pending part
                if let part = currentPart {
                    description.parts.append(part)
                    currentPart = nil
                }
                inPartsArray = false
                currentSubSection = nil
                
                switch key {
                case "name":
                    description.name = value
                case "year":
                    description.year = value
                case "rom":
                    description.rom = value
                case "style":
                    description.style = value
                case "material":
                    description.material = value
                case "parts":
                    currentSection = "parts"
                case "model":
                    currentSection = "model"
                    description.model = ModelConfig()
                case "video":
                    currentSection = "video"
                    description.video = VideoConfig()
                case "crt":
                    currentSection = "crt"
                    description.crt = CRTConfig()
                case "coinslot":
                    description.coinslot = value
                default:
                    break
                }
            } else if inPartsArray && currentPart != nil {
                // Inside a part definition
                switch key {
                case "type":
                    currentPart?.type = PartType(from: value)
                case "material":
                    currentPart?.material = value
                case "art":
                    currentSubSection = "art"
                    currentPart?.art = ArtConfig(file: "")
                case "color":
                    currentSubSection = "color"
                    currentPart?.color = PartColor()
                case "marquee":
                    currentSubSection = "marquee"
                case "file":
                    if currentSubSection == "art" {
                        currentPart?.art?.file = value
                    }
                case "invertx":
                    if currentSubSection == "art" {
                        currentPart?.art?.invertX = (value.lowercased() == "true")
                    }
                case "inverty":
                    if currentSubSection == "art" {
                        currentPart?.art?.invertY = (value.lowercased() == "true")
                    }
                case "rotate":
                    if currentSubSection == "art" {
                        currentPart?.art?.rotate = Int(value) ?? 0
                    }
                case "r":
                    if currentSubSection == "color" {
                        currentPart?.color?.r = Int(value) ?? 255
                    }
                case "g":
                    if currentSubSection == "color" {
                        currentPart?.color?.g = Int(value) ?? 255
                    }
                case "b":
                    if currentSubSection == "color" {
                        currentPart?.color?.b = Int(value) ?? 255
                    }
                case "intensity":
                    if currentSubSection == "color" {
                        currentPart?.color?.intensity = Double(value) ?? 1.0
                    }
                default:
                    break
                }
            } else if currentSection == "model" {
                switch key {
                case "file":
                    description.model?.file = value
                case "style":
                    description.model?.style = value
                default:
                    break
                }
            } else if currentSection == "video" {
                switch key {
                case "file":
                    description.video?.file = value
                case "invertx":
                    description.video?.invertX = (value.lowercased() == "true")
                case "inverty":
                    description.video?.invertY = (value.lowercased() == "true")
                default:
                    break
                }
            } else if currentSection == "crt" {
                switch key {
                case "orientation":
                    description.crt?.orientation = value
                default:
                    break
                }
            }
        }
        
        // Don't forget the last part
        if let part = currentPart {
            description.parts.append(part)
        }
        
        return description
    }
    
    /// Parse a "key: value" line
    private static func parseKeyValue(_ line: String) -> (key: String, value: String)? {
        guard let colonIndex = line.firstIndex(of: ":") else {
            return nil
        }
        
        let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces).lowercased()
        var value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
        
        // Remove quotes if present
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
           (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }
        
        return (key, value)
    }
    
    /// Get list of image files in a cabinet folder
    static func getImageFiles(in cabinetPath: String) -> [String] {
        let fm = FileManager.default
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp"]
        
        guard let contents = try? fm.contentsOfDirectory(atPath: cabinetPath) else {
            return []
        }
        
        return contents.filter { filename in
            let ext = (filename as NSString).pathExtension.lowercased()
            return imageExtensions.contains(ext)
        }.sorted()
    }
    
    /// Get list of model files in a cabinet folder
    static func getModelFiles(in cabinetPath: String) -> [String] {
        let fm = FileManager.default
        let modelExtensions = ["glb", "gltf", "obj", "fbx"]
        
        guard let contents = try? fm.contentsOfDirectory(atPath: cabinetPath) else {
            return []
        }
        
        return contents.filter { filename in
            let ext = (filename as NSString).pathExtension.lowercased()
            return modelExtensions.contains(ext)
        }.sorted()
    }
}
