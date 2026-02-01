import Foundation
import AppKit

// MARK: - Gallery Storage Manager

/// Manages persistence of cabinet gallery data including cabinets, assets, and backups
class GalleryStorage: ObservableObject {
    
    static let shared = GalleryStorage()
    
    private let fileManager = FileManager.default
    
    // Storage locations
    private var galleryRoot: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("RetroVisionCabsConverter/Gallery")
    }
    
    private var cabinetsDir: URL { galleryRoot.appendingPathComponent("Cabinets") }
    private var assetsDir: URL { galleryRoot.appendingPathComponent("Assets") }
    private var previewsDir: URL { galleryRoot.appendingPathComponent("Previews") }
    private var metadataFile: URL { galleryRoot.appendingPathComponent("gallery_metadata.json") }
    
    @Published var savedCabinets: [SavedCabinet] = []
    @Published var isSaving = false
    @Published var isLoading = false
    @Published var lastError: String?
    
    init() {
        ensureDirectoriesExist()
    }
    
    // MARK: - Directory Setup
    
    private func ensureDirectoriesExist() {
        for dir in [galleryRoot, cabinetsDir, assetsDir, previewsDir] {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Load Saved Gallery
    
    /// Load all previously saved cabinets
    func loadSavedCabinets() {
        isLoading = true
        
        guard fileManager.fileExists(atPath: metadataFile.path) else {
            isLoading = false
            return
        }
        
        do {
            let data = try Data(contentsOf: metadataFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            savedCabinets = try decoder.decode([SavedCabinet].self, from: data)
            
            // Load preview images
            for i in savedCabinets.indices {
                let previewPath = previewsDir.appendingPathComponent("\(savedCabinets[i].id).png")
                if fileManager.fileExists(atPath: previewPath.path) {
                    savedCabinets[i].previewImage = NSImage(contentsOf: previewPath)
                }
            }
            
            print("Loaded \(savedCabinets.count) saved cabinets")
        } catch {
            lastError = "Failed to load gallery: \(error.localizedDescription)"
            print(lastError!)
        }
        
        isLoading = false
    }
    
    /// Convert saved cabinets to DiscoveredCabinet format for display
    func toDiscoveredCabinets() -> [DiscoveredCabinet] {
        return savedCabinets.map { saved in
            var cabinet = DiscoveredCabinet(
                id: saved.id,
                name: saved.name,
                displayName: saved.displayName,
                sourcePath: cabinetsDir.appendingPathComponent(saved.id),
                sourceType: .folder
            )
            cabinet.game = saved.game
            cabinet.rom = saved.rom
            cabinet.author = saved.author
            cabinet.year = saved.year
            cabinet.suggestedTemplateID = saved.templateID
            cabinet.meshMappings = saved.meshMappings
            cabinet.previewImage = saved.previewImage
            cabinet.previewGenerated = saved.previewImage != nil
            
            // Build assets list
            cabinet.assets = saved.assetFiles.map { filename in
                DiscoveredAsset(url: assetsDir.appendingPathComponent(saved.id).appendingPathComponent(filename))
            }
            
            return cabinet
        }
    }
    
    // MARK: - Save Cabinets
    
    /// Save discovered cabinets to the gallery storage
    /// Returns: Number of new cabinets saved (excludes duplicates)
    @discardableResult
    func saveCabinets(_ cabinets: [DiscoveredCabinet], progress: @escaping (Double, String) -> Void) async -> Int {
        await MainActor.run { isSaving = true }
        
        var savedCount = 0
        let total = Double(cabinets.count)
        
        for (index, cabinet) in cabinets.enumerated() {
            progress(Double(index) / total, "Saving: \(cabinet.displayName)")
            
            // Check for duplicates using content hash
            let contentHash = computeContentHash(cabinet)
            if savedCabinets.contains(where: { $0.contentHash == contentHash }) {
                print("Skipping duplicate: \(cabinet.name)")
                continue
            }
            
            do {
                try await saveSingleCabinet(cabinet, contentHash: contentHash)
                savedCount += 1
            } catch {
                print("Failed to save \(cabinet.name): \(error)")
            }
        }
        
        // Save metadata
        try? saveMetadata()
        
        progress(1.0, "Saved \(savedCount) cabinet(s)")
        await MainActor.run { isSaving = false }
        
        return savedCount
    }
    
    private func saveSingleCabinet(_ cabinet: DiscoveredCabinet, contentHash: String) async throws {
        let cabinetDir = cabinetsDir.appendingPathComponent(cabinet.id)
        let assetsSubDir = assetsDir.appendingPathComponent(cabinet.id)
        
        // Create directories
        try fileManager.createDirectory(at: cabinetDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: assetsSubDir, withIntermediateDirectories: true)
        
        // Copy GLB model if exists
        var glbFilename: String?
        if let glbURL = cabinet.glbFile, fileManager.fileExists(atPath: glbURL.path) {
            let destGLB = cabinetDir.appendingPathComponent(glbURL.lastPathComponent)
            try? fileManager.removeItem(at: destGLB)
            try fileManager.copyItem(at: glbURL, to: destGLB)
            glbFilename = glbURL.lastPathComponent
        }
        
        // Copy assets
        var assetFiles: [String] = []
        for asset in cabinet.assets {
            if fileManager.fileExists(atPath: asset.url.path) {
                let destAsset = assetsSubDir.appendingPathComponent(asset.filename)
                try? fileManager.removeItem(at: destAsset)
                try fileManager.copyItem(at: asset.url, to: destAsset)
                assetFiles.append(asset.filename)
            }
        }
        
        // Copy description.yaml if exists
        let descURL = cabinet.sourcePath.appendingPathComponent("description.yaml")
        if fileManager.fileExists(atPath: descURL.path) {
            let destDesc = cabinetDir.appendingPathComponent("description.yaml")
            try? fileManager.removeItem(at: destDesc)
            try fileManager.copyItem(at: descURL, to: destDesc)
        }
        
        // Save preview image
        if let preview = cabinet.previewImage {
            let previewPath = previewsDir.appendingPathComponent("\(cabinet.id).png")
            if let tiff = preview.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                try png.write(to: previewPath)
            }
        }
        
        // Create saved cabinet record
        let saved = SavedCabinet(
            id: cabinet.id,
            name: cabinet.name,
            displayName: cabinet.displayName,
            game: cabinet.game,
            rom: cabinet.rom,
            author: cabinet.author,
            year: cabinet.year,
            templateID: cabinet.suggestedTemplateID,
            glbFile: glbFilename,
            assetFiles: assetFiles,
            meshMappings: cabinet.meshMappings,
            contentHash: contentHash,
            savedDate: Date(),
            originalSourcePath: cabinet.sourcePath.path
        )
        
        await MainActor.run {
            savedCabinets.append(saved)
        }
    }
    
    // MARK: - Duplicate Detection
    
    /// Compute a content hash for duplicate detection
    private func computeContentHash(_ cabinet: DiscoveredCabinet) -> String {
        var hashInput = cabinet.name.lowercased()
        
        // Include ROM name if available
        if let rom = cabinet.rom {
            hashInput += "_\(rom.lowercased())"
        }
        
        // Include sorted asset filenames
        let assetNames = cabinet.assets.map { $0.filename.lowercased() }.sorted().joined(separator: ",")
        hashInput += "_\(assetNames)"
        
        // Include mesh mappings
        let mappings = cabinet.meshMappings.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ";")
        hashInput += "_\(mappings)"
        
        // Generate hash
        return String(hashInput.hashValue)
    }
    
    /// Check if a cabinet already exists in saved gallery
    func isDuplicate(_ cabinet: DiscoveredCabinet) -> Bool {
        let hash = computeContentHash(cabinet)
        return savedCabinets.contains { $0.contentHash == hash }
    }
    
    /// Get count of duplicates from a list
    func countDuplicates(in cabinets: [DiscoveredCabinet]) -> Int {
        return cabinets.filter { isDuplicate($0) }.count
    }
    
    // MARK: - Delete Cabinet
    
    /// Remove a cabinet from the saved gallery
    func deleteCabinet(_ id: String) throws {
        // Remove files
        let cabinetDir = cabinetsDir.appendingPathComponent(id)
        let assetsSubDir = assetsDir.appendingPathComponent(id)
        let previewFile = previewsDir.appendingPathComponent("\(id).png")
        
        try? fileManager.removeItem(at: cabinetDir)
        try? fileManager.removeItem(at: assetsSubDir)
        try? fileManager.removeItem(at: previewFile)
        
        // Update metadata
        savedCabinets.removeAll { $0.id == id }
        try saveMetadata()
    }
    
    // MARK: - Metadata Persistence
    
    private func saveMetadata() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        let data = try encoder.encode(savedCabinets)
        try data.write(to: metadataFile)
    }
    
    // MARK: - Backup & Restore
    
    /// Create a backup ZIP of the entire gallery
    func createBackup(to destinationURL: URL, progress: @escaping (Double, String) -> Void) async throws {
        progress(0.1, "Preparing backup...")
        
        // Create temp directory for backup
        let tempBackupDir = fileManager.temporaryDirectory.appendingPathComponent("GalleryBackup_\(Date().timeIntervalSince1970)")
        try fileManager.createDirectory(at: tempBackupDir, withIntermediateDirectories: true)
        
        defer {
            try? fileManager.removeItem(at: tempBackupDir)
        }
        
        progress(0.2, "Copying cabinet data...")
        
        // Copy all gallery data to temp
        let itemsToCopy = ["Cabinets", "Assets", "Previews", "gallery_metadata.json"]
        for item in itemsToCopy {
            let source = galleryRoot.appendingPathComponent(item)
            let dest = tempBackupDir.appendingPathComponent(item)
            if fileManager.fileExists(atPath: source.path) {
                try fileManager.copyItem(at: source, to: dest)
            }
        }
        
        // Create backup info file
        let backupInfo = BackupInfo(
            version: "1.0",
            createdDate: Date(),
            cabinetCount: savedCabinets.count,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        )
        let infoData = try JSONEncoder().encode(backupInfo)
        try infoData.write(to: tempBackupDir.appendingPathComponent("backup_info.json"))
        
        progress(0.5, "Creating ZIP archive...")
        
        // Create ZIP
        let zipProcess = Process()
        zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zipProcess.arguments = ["-c", "-k", "--sequesterRsrc", tempBackupDir.path, destinationURL.path]
        
        try zipProcess.run()
        zipProcess.waitUntilExit()
        
        guard zipProcess.terminationStatus == 0 else {
            throw GalleryStorageError.backupFailed("ZIP creation failed")
        }
        
        progress(1.0, "Backup complete!")
    }
    
    /// Restore gallery from a backup ZIP
    func restoreBackup(from backupURL: URL, progress: @escaping (Double, String) -> Void) async throws -> Int {
        progress(0.1, "Extracting backup...")
        
        // Create temp directory for extraction
        let tempExtractDir = fileManager.temporaryDirectory.appendingPathComponent("GalleryRestore_\(Date().timeIntervalSince1970)")
        try fileManager.createDirectory(at: tempExtractDir, withIntermediateDirectories: true)
        
        defer {
            try? fileManager.removeItem(at: tempExtractDir)
        }
        
        // Extract ZIP
        let unzipProcess = Process()
        unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzipProcess.arguments = ["-q", "-o", backupURL.path, "-d", tempExtractDir.path]
        
        try unzipProcess.run()
        unzipProcess.waitUntilExit()
        
        guard unzipProcess.terminationStatus == 0 else {
            throw GalleryStorageError.restoreFailed("Failed to extract backup")
        }
        
        progress(0.3, "Validating backup...")
        
        // Find the backup root (might be nested)
        var backupRoot = tempExtractDir
        let possibleRoots = try fileManager.contentsOfDirectory(at: tempExtractDir, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") && !$0.lastPathComponent.hasPrefix("__MACOSX") }
        
        if possibleRoots.count == 1, possibleRoots[0].hasDirectoryPath {
            backupRoot = possibleRoots[0]
        }
        
        // Check for backup info
        let infoFile = backupRoot.appendingPathComponent("backup_info.json")
        if fileManager.fileExists(atPath: infoFile.path) {
            let infoData = try Data(contentsOf: infoFile)
            let info = try JSONDecoder().decode(BackupInfo.self, from: infoData)
            print("Restoring backup from \(info.createdDate), \(info.cabinetCount) cabinets")
        }
        
        progress(0.5, "Importing cabinets...")
        
        // Load metadata from backup
        let backupMetadataFile = backupRoot.appendingPathComponent("gallery_metadata.json")
        guard fileManager.fileExists(atPath: backupMetadataFile.path) else {
            throw GalleryStorageError.restoreFailed("Invalid backup: missing metadata")
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backupCabinets = try decoder.decode([SavedCabinet].self, from: Data(contentsOf: backupMetadataFile))
        
        var importedCount = 0
        let total = Double(backupCabinets.count)
        
        for (index, backupCabinet) in backupCabinets.enumerated() {
            progress(0.5 + (0.4 * Double(index) / total), "Importing: \(backupCabinet.displayName)")
            
            // Skip if already exists
            if savedCabinets.contains(where: { $0.contentHash == backupCabinet.contentHash }) {
                continue
            }
            
            // Copy cabinet files
            let srcCabinetDir = backupRoot.appendingPathComponent("Cabinets").appendingPathComponent(backupCabinet.id)
            let dstCabinetDir = cabinetsDir.appendingPathComponent(backupCabinet.id)
            if fileManager.fileExists(atPath: srcCabinetDir.path) {
                try? fileManager.removeItem(at: dstCabinetDir)
                try fileManager.copyItem(at: srcCabinetDir, to: dstCabinetDir)
            }
            
            // Copy assets
            let srcAssetsDir = backupRoot.appendingPathComponent("Assets").appendingPathComponent(backupCabinet.id)
            let dstAssetsDir = assetsDir.appendingPathComponent(backupCabinet.id)
            if fileManager.fileExists(atPath: srcAssetsDir.path) {
                try? fileManager.removeItem(at: dstAssetsDir)
                try fileManager.copyItem(at: srcAssetsDir, to: dstAssetsDir)
            }
            
            // Copy preview
            let srcPreview = backupRoot.appendingPathComponent("Previews").appendingPathComponent("\(backupCabinet.id).png")
            let dstPreview = previewsDir.appendingPathComponent("\(backupCabinet.id).png")
            if fileManager.fileExists(atPath: srcPreview.path) {
                try? fileManager.removeItem(at: dstPreview)
                try fileManager.copyItem(at: srcPreview, to: dstPreview)
            }
            
            // Add to saved list
            var cabinet = backupCabinet
            cabinet.previewImage = NSImage(contentsOf: dstPreview)
            savedCabinets.append(cabinet)
            importedCount += 1
        }
        
        // Save updated metadata
        try saveMetadata()
        
        progress(1.0, "Restored \(importedCount) cabinet(s)")
        return importedCount
    }
    
    // MARK: - Clear Gallery
    
    /// Remove all saved cabinets
    func clearAllSavedCabinets() throws {
        try? fileManager.removeItem(at: cabinetsDir)
        try? fileManager.removeItem(at: assetsDir)
        try? fileManager.removeItem(at: previewsDir)
        try? fileManager.removeItem(at: metadataFile)
        
        savedCabinets.removeAll()
        ensureDirectoriesExist()
    }
    
    // MARK: - Statistics
    
    var totalAssetCount: Int {
        savedCabinets.reduce(0) { $0 + $1.assetFiles.count }
    }
    
    var storageSize: String {
        let size = directorySize(galleryRoot)
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
    
    private func directorySize(_ url: URL) -> Int {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        var total = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += size
            }
        }
        return total
    }
}

// MARK: - Saved Cabinet Model

struct SavedCabinet: Codable, Identifiable {
    var id: String
    var name: String
    var displayName: String
    var game: String?
    var rom: String?
    var author: String?
    var year: String?
    var templateID: String
    var glbFile: String?
    var assetFiles: [String]
    var meshMappings: [String: String]
    var contentHash: String
    var savedDate: Date
    var originalSourcePath: String
    
    // Not persisted
    var previewImage: NSImage?
    
    enum CodingKeys: String, CodingKey {
        case id, name, displayName, game, rom, author, year, templateID
        case glbFile, assetFiles, meshMappings, contentHash, savedDate, originalSourcePath
    }
}

// MARK: - Backup Info

struct BackupInfo: Codable {
    let version: String
    let createdDate: Date
    let cabinetCount: Int
    let appVersion: String
}

// MARK: - Errors

enum GalleryStorageError: Error, LocalizedError {
    case backupFailed(String)
    case restoreFailed(String)
    case duplicateExists
    case saveFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .backupFailed(let reason): return "Backup failed: \(reason)"
        case .restoreFailed(let reason): return "Restore failed: \(reason)"
        case .duplicateExists: return "Cabinet already exists in gallery"
        case .saveFailed(let reason): return "Save failed: \(reason)"
        }
    }
}
