import Foundation
import SwiftUI

// MARK: - Validation Status

enum ValidationStatus: Equatable {
    case valid
    case warning(String)
    case error(String)
    case suggestion(file: String, confidence: Double)
    
    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }
    
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
    
    var isWarning: Bool {
        if case .warning = self { return true }
        return false
    }
    
    var hasSuggestion: Bool {
        if case .suggestion = self { return true }
        return false
    }
    
    var icon: String {
        switch self {
        case .valid: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        case .suggestion: return "lightbulb.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .valid: return .green
        case .warning: return .yellow
        case .error: return .red
        case .suggestion: return .orange
        }
    }
    
    var message: String {
        switch self {
        case .valid: return "Ready"
        case .warning(let msg): return msg
        case .error(let msg): return msg
        case .suggestion(let file, let confidence):
            return "Suggested: \(file) (\(Int(confidence * 100))% match)"
        }
    }
}

// MARK: - Cabinet Part Detail

struct CabinetPartDetail: Identifiable, Equatable {
    let id: String
    let name: String
    let type: PartType
    let artFile: String?
    let artFullPath: String?
    let material: String?
    let color: PartColor?
    var validationStatus: ValidationStatus
    var suggestedFile: String?
    var artRotation: Int = 0
    var artInvertX: Bool = false
    var artInvertY: Bool = false
    
    init(from part: CabinetPart, cabinetPath: String) {
        self.id = part.name
        self.name = part.name
        self.type = part.type
        self.artFile = part.art?.file
        self.material = part.material
        self.color = part.color
        self.artRotation = part.art?.rotate ?? 0
        self.artInvertX = part.art?.invertX ?? false
        self.artInvertY = part.art?.invertY ?? false
        
        if let artFile = part.art?.file, !artFile.isEmpty {
            self.artFullPath = (cabinetPath as NSString).appendingPathComponent(artFile)
        } else {
            self.artFullPath = nil
        }
        
        // Initial validation status - will be updated by ValidationEngine
        self.validationStatus = .valid
    }
    
    var hasTexture: Bool {
        artFile != nil && !artFile!.isEmpty
    }
    
    var displayMaterial: String {
        material ?? "default"
    }
}

// MARK: - Cabinet File Info

struct CabinetFileInfo: Identifiable, Equatable {
    let id: String
    let filename: String
    let fullPath: String
    let fileType: FileType
    var isAssigned: Bool
    var assignedToPart: String?
    
    enum FileType: String {
        case image
        case model
        case video
        case yaml
        case other
        
        var icon: String {
            switch self {
            case .image: return "photo"
            case .model: return "cube"
            case .video: return "film"
            case .yaml: return "doc.text"
            case .other: return "doc"
            }
        }
    }
    
    init(filename: String, cabinetPath: String) {
        self.id = filename
        self.filename = filename
        self.fullPath = (cabinetPath as NSString).appendingPathComponent(filename)
        self.isAssigned = false
        self.assignedToPart = nil
        
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp":
            self.fileType = .image
        case "glb", "gltf", "obj", "fbx":
            self.fileType = .model
        case "mp4", "mov", "avi", "webm":
            self.fileType = .video
        case "yaml", "yml":
            self.fileType = .yaml
        default:
            self.fileType = .other
        }
    }
}

// MARK: - Cabinet Detail

// MARK: - Video Detail

struct VideoDetail: Equatable {
    var file: String?
    var fullPath: String?
    var invertX: Bool
    var invertY: Bool
    var validationStatus: ValidationStatus
    
    init(from config: VideoConfig?, cabinetPath: String) {
        self.file = config?.file
        self.invertX = config?.invertX ?? false
        self.invertY = config?.invertY ?? false
        
        if let file = config?.file, !file.isEmpty {
            self.fullPath = (cabinetPath as NSString).appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: self.fullPath!) {
                self.validationStatus = .valid
            } else {
                self.validationStatus = .error("Video file not found")
            }
        } else {
            self.fullPath = nil
            self.validationStatus = .warning("No video configured")
        }
    }
    
    var hasVideo: Bool {
        file != nil && !file!.isEmpty
    }
    
    var fileExtension: String? {
        guard let file = file else { return nil }
        return (file as NSString).pathExtension.lowercased()
    }
    
    var isValid: Bool {
        validationStatus.isValid
    }
}

struct CabinetDetail: Identifiable, Equatable {
    let id: String
    let path: String
    var name: String
    var year: String?
    var rom: String?
    var style: String?
    var material: String?
    var modelFile: String?
    var videoDetail: VideoDetail?
    var crtOrientation: String?
    var parts: [CabinetPartDetail]
    var files: [CabinetFileInfo]
    var overallStatus: ValidationStatus
    var hasDescription: Bool
    
    // Legacy accessor
    var videoFile: String? {
        videoDetail?.file
    }
    
    init(path: String) {
        self.id = (path as NSString).lastPathComponent
        self.path = path
        self.name = (path as NSString).lastPathComponent
        self.videoDetail = nil
        self.parts = []
        self.files = []
        self.overallStatus = .valid
        self.hasDescription = false
    }
    
    init(from description: CabinetDescription, path: String) {
        self.id = (path as NSString).lastPathComponent
        self.path = path
        self.name = description.name
        self.year = description.year
        self.rom = description.rom
        self.style = description.style
        self.material = description.material
        self.modelFile = description.model?.file
        self.videoDetail = VideoDetail(from: description.video, cabinetPath: path)
        self.crtOrientation = description.crt?.orientation
        self.hasDescription = true
        self.overallStatus = .valid
        
        // Convert parts
        let convertedParts = description.parts.map { CabinetPartDetail(from: $0, cabinetPath: path) }
        self.parts = convertedParts
        
        // Scan files in folder
        var scannedFiles = CabinetDetail.scanFiles(in: path)
        
        // Mark assigned files
        let assignedFiles = Set(convertedParts.compactMap { $0.artFile })
        for i in scannedFiles.indices {
            if assignedFiles.contains(scannedFiles[i].filename) {
                scannedFiles[i].isAssigned = true
                scannedFiles[i].assignedToPart = convertedParts.first { $0.artFile == scannedFiles[i].filename }?.name
            }
        }
        
        // Check for model file
        if let modelFile = description.model?.file {
            for i in scannedFiles.indices {
                if scannedFiles[i].filename == modelFile {
                    scannedFiles[i].isAssigned = true
                    scannedFiles[i].assignedToPart = "Model"
                }
            }
        }
        
        self.files = scannedFiles
    }
    
    private static func scanFiles(in path: String) -> [CabinetFileInfo] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: path) else {
            return []
        }
        
        return contents
            .filter { !$0.hasPrefix(".") }
            .sorted()
            .map { CabinetFileInfo(filename: $0, cabinetPath: path) }
    }
    
    // MARK: - Computed Properties
    
    var imageFiles: [CabinetFileInfo] {
        files.filter { $0.fileType == .image }
    }
    
    var videoFiles: [CabinetFileInfo] {
        files.filter { $0.fileType == .video }
    }
    
    var unassignedImages: [CabinetFileInfo] {
        files.filter { $0.fileType == .image && !$0.isAssigned }
    }
    
    var unassignedVideos: [CabinetFileInfo] {
        files.filter { $0.fileType == .video && !$0.isAssigned }
    }
    
    var hasVideo: Bool {
        videoDetail?.hasVideo ?? false
    }
    
    var videoStatus: ValidationStatus {
        videoDetail?.validationStatus ?? .warning("No video")
    }
    
    var partsWithErrors: [CabinetPartDetail] {
        parts.filter { $0.validationStatus.isError }
    }
    
    var partsWithWarnings: [CabinetPartDetail] {
        parts.filter { $0.validationStatus.isWarning }
    }
    
    var readyParts: [CabinetPartDetail] {
        parts.filter { $0.validationStatus.isValid }
    }
    
    var errorCount: Int {
        partsWithErrors.count
    }
    
    var warningCount: Int {
        partsWithWarnings.count
    }
    
    var isReady: Bool {
        hasDescription && errorCount == 0
    }
    
    var statusSummary: String {
        if !hasDescription {
            return "No description.yaml"
        }
        if errorCount > 0 {
            return "\(errorCount) error(s)"
        }
        if warningCount > 0 {
            return "\(warningCount) warning(s)"
        }
        return "Ready"
    }
}

// MARK: - Cabinet Detail Manager

@MainActor
class CabinetDetailManager: ObservableObject {
    @Published var details: [String: CabinetDetail] = [:]
    @Published var isLoading = false
    
    private let validationEngine = ValidationEngine()
    
    /// Load details for a single cabinet
    func loadDetail(for path: String) -> CabinetDetail {
        if let cached = details[path] {
            return cached
        }
        
        var detail: CabinetDetail
        
        do {
            let description = try DescriptionParser.parse(cabinetPath: path)
            detail = CabinetDetail(from: description, path: path)
            
            // Run validation
            detail = validationEngine.validate(cabinet: detail)
        } catch {
            // No description.yaml or parse error
            detail = CabinetDetail(path: path)
            detail.overallStatus = .error("No description.yaml found")
        }
        
        details[path] = detail
        return detail
    }
    
    /// Load details for multiple cabinets
    func loadDetails(for items: [CabinetItem]) async {
        isLoading = true
        
        for item in items {
            let effectivePath = getEffectivePath(for: item)
            _ = loadDetail(for: effectivePath)
        }
        
        isLoading = false
    }
    
    /// Get the effective path for a cabinet item (extracts ZIP if needed)
    func getEffectivePath(for item: CabinetItem) -> String {
        if item.isZipFile {
            // Extract ZIP and return the extracted path
            if let extractedURL = CabinetScanner.extractZipForProcessing(item.path) {
                return extractedURL.path
            }
        }
        return item.path
    }
    
    /// Clear cached details
    func clearCache() {
        details.removeAll()
    }
    
    /// Refresh detail for a specific cabinet
    func refresh(path: String) -> CabinetDetail {
        details.removeValue(forKey: path)
        return loadDetail(for: path)
    }
}
