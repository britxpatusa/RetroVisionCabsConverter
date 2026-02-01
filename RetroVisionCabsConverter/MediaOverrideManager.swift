import Foundation

// MARK: - Media Override

struct MediaOverride: Codable, Equatable {
    let partName: String
    var artFile: String?  // nil means "clear texture"
    var material: String?
    var isCleared: Bool  // true if user explicitly cleared the texture
    var rotation: Int?
    var invertX: Bool?
    var invertY: Bool?
    
    init(partName: String, artFile: String? = nil, material: String? = nil, isCleared: Bool = false, rotation: Int? = nil, invertX: Bool? = nil, invertY: Bool? = nil) {
        self.partName = partName
        self.artFile = artFile
        self.material = material
        self.isCleared = isCleared
        self.rotation = rotation
        self.invertX = invertX
        self.invertY = invertY
    }
}

struct VideoOverride: Codable, Equatable {
    var file: String?
    var invertX: Bool?
    var invertY: Bool?
    var isCleared: Bool
    
    init(file: String? = nil, invertX: Bool? = nil, invertY: Bool? = nil, isCleared: Bool = false) {
        self.file = file
        self.invertX = invertX
        self.invertY = invertY
        self.isCleared = isCleared
    }
}

struct CabinetOverrides: Codable, Equatable {
    let cabinetPath: String
    var partOverrides: [String: MediaOverride]  // keyed by part name
    var videoOverride: VideoOverride?
    var lastModified: Date
    
    init(cabinetPath: String) {
        self.cabinetPath = cabinetPath
        self.partOverrides = [:]
        self.videoOverride = nil
        self.lastModified = Date()
    }
}

// MARK: - Media Override Manager

class MediaOverrideManager: ObservableObject {
    @Published private(set) var overrides: [String: CabinetOverrides] = [:]  // keyed by cabinet path
    
    private let saveURL: URL
    
    init() {
        // Save overrides in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("RetroVisionCabsConverter")
        
        // Create folder if needed
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        
        saveURL = appFolder.appendingPathComponent("media_overrides.json")
        
        load()
    }
    
    // MARK: - Public Methods
    
    /// Check if a part has an override
    func hasOverride(cabinetPath: String, partName: String) -> Bool {
        overrides[cabinetPath]?.partOverrides[partName] != nil
    }
    
    /// Get override for a specific part
    func getOverride(cabinetPath: String, partName: String) -> MediaOverride? {
        overrides[cabinetPath]?.partOverrides[partName]
    }
    
    /// Set override for a part
    func setOverride(cabinetPath: String, partName: String, newArtFile: String?, material: String? = nil) {
        var cabinetOverride = overrides[cabinetPath] ?? CabinetOverrides(cabinetPath: cabinetPath)
        
        // Preserve existing transform if present
        let existing = cabinetOverride.partOverrides[partName]
        
        cabinetOverride.partOverrides[partName] = MediaOverride(
            partName: partName,
            artFile: newArtFile,
            material: material,
            isCleared: newArtFile == nil,
            rotation: existing?.rotation,
            invertX: existing?.invertX,
            invertY: existing?.invertY
        )
        cabinetOverride.lastModified = Date()
        
        overrides[cabinetPath] = cabinetOverride
    }
    
    /// Set part transform (rotation and flip)
    func setPartTransform(cabinetPath: String, partName: String, rotation: Int, invertX: Bool, invertY: Bool) {
        var cabinetOverride = overrides[cabinetPath] ?? CabinetOverrides(cabinetPath: cabinetPath)
        
        if var existing = cabinetOverride.partOverrides[partName] {
            existing.rotation = rotation
            existing.invertX = invertX
            existing.invertY = invertY
            cabinetOverride.partOverrides[partName] = existing
        } else {
            cabinetOverride.partOverrides[partName] = MediaOverride(
                partName: partName,
                rotation: rotation,
                invertX: invertX,
                invertY: invertY
            )
        }
        cabinetOverride.lastModified = Date()
        
        overrides[cabinetPath] = cabinetOverride
    }
    
    /// Remove override for a part (revert to original)
    func removeOverride(cabinetPath: String, partName: String) {
        overrides[cabinetPath]?.partOverrides.removeValue(forKey: partName)
        overrides[cabinetPath]?.lastModified = Date()
        
        // Clean up empty cabinet overrides
        if overrides[cabinetPath]?.partOverrides.isEmpty == true {
            overrides.removeValue(forKey: cabinetPath)
        }
    }
    
    /// Clear all overrides for a cabinet
    func clearOverrides(for cabinetPath: String) {
        overrides.removeValue(forKey: cabinetPath)
    }
    
    /// Get all overrides for a cabinet
    func getOverrides(for cabinetPath: String) -> [MediaOverride] {
        Array(overrides[cabinetPath]?.partOverrides.values ?? [:].values)
    }
    
    // MARK: - Video Overrides
    
    /// Check if cabinet has a video override
    func hasVideoOverride(cabinetPath: String) -> Bool {
        overrides[cabinetPath]?.videoOverride != nil
    }
    
    /// Get video override for a cabinet
    func getVideoOverride(cabinetPath: String) -> VideoOverride? {
        overrides[cabinetPath]?.videoOverride
    }
    
    /// Set video override
    func setVideoOverride(cabinetPath: String, file: String?, invertX: Bool? = nil, invertY: Bool? = nil) {
        var cabinetOverride = overrides[cabinetPath] ?? CabinetOverrides(cabinetPath: cabinetPath)
        
        cabinetOverride.videoOverride = VideoOverride(
            file: file,
            invertX: invertX,
            invertY: invertY,
            isCleared: file == nil
        )
        cabinetOverride.lastModified = Date()
        
        overrides[cabinetPath] = cabinetOverride
    }
    
    /// Set video transform options only
    func setVideoTransform(cabinetPath: String, invertX: Bool, invertY: Bool) {
        var cabinetOverride = overrides[cabinetPath] ?? CabinetOverrides(cabinetPath: cabinetPath)
        
        if var existing = cabinetOverride.videoOverride {
            existing.invertX = invertX
            existing.invertY = invertY
            cabinetOverride.videoOverride = existing
        } else {
            cabinetOverride.videoOverride = VideoOverride(invertX: invertX, invertY: invertY)
        }
        cabinetOverride.lastModified = Date()
        
        overrides[cabinetPath] = cabinetOverride
    }
    
    /// Remove video override
    func removeVideoOverride(cabinetPath: String) {
        overrides[cabinetPath]?.videoOverride = nil
        overrides[cabinetPath]?.lastModified = Date()
    }
    
    /// Apply overrides to a cabinet detail
    func applyOverrides(to detail: inout CabinetDetail) {
        guard let cabinetOverrides = overrides[detail.path] else {
            return
        }
        
        // Apply part overrides
        for i in detail.parts.indices {
            let partName = detail.parts[i].name
            
            if let override = cabinetOverrides.partOverrides[partName] {
                if override.isCleared {
                    // Clear texture
                    detail.parts[i] = CabinetPartDetail(
                        from: CabinetPart(
                            name: partName,
                            type: detail.parts[i].type,
                            art: nil,
                            material: override.material ?? detail.parts[i].material,
                            color: detail.parts[i].color
                        ),
                        cabinetPath: detail.path
                    )
                } else if let artFile = override.artFile {
                    // Apply new texture
                    detail.parts[i] = CabinetPartDetail(
                        from: CabinetPart(
                            name: partName,
                            type: detail.parts[i].type,
                            art: ArtConfig(file: artFile),
                            material: override.material ?? detail.parts[i].material,
                            color: detail.parts[i].color
                        ),
                        cabinetPath: detail.path
                    )
                    
                    // Validate the overridden file exists
                    let fullPath = (detail.path as NSString).appendingPathComponent(artFile)
                    if FileManager.default.fileExists(atPath: fullPath) {
                        detail.parts[i].validationStatus = .valid
                    } else {
                        detail.parts[i].validationStatus = .error("Override file not found: \(artFile)")
                    }
                }
            }
        }
        
        // Apply video override
        if let videoOverride = cabinetOverrides.videoOverride {
            if videoOverride.isCleared {
                // Clear video
                detail.videoDetail = nil
            } else {
                // Apply video changes
                var video = detail.videoDetail ?? VideoDetail(from: nil, cabinetPath: detail.path)
                
                if let file = videoOverride.file {
                    let config = VideoConfig(
                        file: file,
                        invertX: videoOverride.invertX ?? video.invertX,
                        invertY: videoOverride.invertY ?? video.invertY
                    )
                    video = VideoDetail(from: config, cabinetPath: detail.path)
                } else {
                    // Just update transform
                    if let invertX = videoOverride.invertX {
                        video.invertX = invertX
                    }
                    if let invertY = videoOverride.invertY {
                        video.invertY = invertY
                    }
                }
                
                detail.videoDetail = video
            }
        }
        
        // Update file assignments
        let assignedFiles = Set(detail.parts.compactMap { $0.artFile })
        for i in detail.files.indices {
            detail.files[i].isAssigned = assignedFiles.contains(detail.files[i].filename)
            detail.files[i].assignedToPart = detail.parts.first { $0.artFile == detail.files[i].filename }?.name
        }
    }
    
    /// Generate override job file for conversion
    func generateOverrideJob(for detail: CabinetDetail, originalJobPath: String, outputPath: String) throws {
        guard let cabinetOverrides = overrides[detail.path],
              (!cabinetOverrides.partOverrides.isEmpty || cabinetOverrides.videoOverride != nil) else {
            // No overrides - just copy the original
            try FileManager.default.copyItem(atPath: originalJobPath, toPath: outputPath)
            return
        }
        
        // Read original job
        let jobData = try Data(contentsOf: URL(fileURLWithPath: originalJobPath))
        guard var job = try JSONSerialization.jsonObject(with: jobData) as? [String: Any] else {
            throw OverrideError.invalidJobFile
        }
        
        // Apply part overrides
        if var parts = job["parts"] as? [[String: Any]] {
            for i in parts.indices {
                guard let partName = parts[i]["name"] as? String else { continue }
                
                if let override = cabinetOverrides.partOverrides[partName] {
                    if override.isCleared {
                        // Remove art
                        parts[i].removeValue(forKey: "art")
                    } else if let artFile = override.artFile {
                        // Update art file
                        parts[i]["art"] = ["file": artFile]
                    }
                    
                    if let material = override.material {
                        parts[i]["material"] = material
                    }
                }
            }
            job["parts"] = parts
        }
        
        // Apply video override
        if let videoOverride = cabinetOverrides.videoOverride {
            if videoOverride.isCleared {
                job.removeValue(forKey: "video")
            } else {
                var video = job["video"] as? [String: Any] ?? [:]
                
                if let file = videoOverride.file {
                    video["file"] = file
                }
                if let invertX = videoOverride.invertX {
                    video["invertx"] = invertX
                }
                if let invertY = videoOverride.invertY {
                    video["inverty"] = invertY
                }
                
                job["video"] = video
            }
        }
        
        // Write modified job
        let outputData = try JSONSerialization.data(withJSONObject: job, options: [.prettyPrinted, .sortedKeys])
        try outputData.write(to: URL(fileURLWithPath: outputPath))
    }
    
    // MARK: - Persistence
    
    func save() {
        do {
            let data = try JSONEncoder().encode(overrides)
            try data.write(to: saveURL)
        } catch {
            print("Failed to save overrides: \(error)")
        }
    }
    
    func load() {
        guard FileManager.default.fileExists(atPath: saveURL.path) else {
            return
        }
        
        do {
            let data = try Data(contentsOf: saveURL)
            overrides = try JSONDecoder().decode([String: CabinetOverrides].self, from: data)
        } catch {
            print("Failed to load overrides: \(error)")
        }
    }
    
    // MARK: - Statistics
    
    var totalOverrideCount: Int {
        overrides.values.reduce(0) { $0 + $1.partOverrides.count }
    }
    
    var cabinetsWithOverrides: Int {
        overrides.count
    }
    
    // MARK: - Errors
    
    enum OverrideError: Error, LocalizedError {
        case invalidJobFile
        case fileNotFound(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidJobFile:
                return "Invalid job file format"
            case .fileNotFound(let path):
                return "File not found: \(path)"
            }
        }
    }
}
