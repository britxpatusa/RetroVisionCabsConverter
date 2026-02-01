//
//  PropsStorage.swift
//  RetroVisionCabsConverter
//
//  Persistence layer for props gallery
//

import Foundation
import AppKit

// MARK: - Props Storage

class PropsStorage: ObservableObject {
    static let shared = PropsStorage()
    
    @Published var savedProps: [SavedProp] = []
    @Published var isLoading = false
    
    private let fileManager = FileManager.default
    private let propsRoot: URL
    private let metadataFile: URL
    private let assetsFolder: URL
    private let previewsFolder: URL
    
    init() {
        // Store props in workspace
        let paths = RetroVisionPaths.load()
        propsRoot = URL(fileURLWithPath: paths.workspaceRoot).appendingPathComponent("PropsGallery")
        metadataFile = propsRoot.appendingPathComponent("props_metadata.json")
        assetsFolder = propsRoot.appendingPathComponent("Assets")
        previewsFolder = propsRoot.appendingPathComponent("Previews")
        
        // Ensure directories exist
        try? fileManager.createDirectory(at: propsRoot, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: assetsFolder, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: previewsFolder, withIntermediateDirectories: true)
    }
    
    // MARK: - Loading
    
    /// Load saved props from storage
    func loadSavedProps() {
        isLoading = true
        defer { isLoading = false }
        
        guard fileManager.fileExists(atPath: metadataFile.path) else {
            savedProps = []
            return
        }
        
        do {
            let data = try Data(contentsOf: metadataFile)
            savedProps = try JSONDecoder().decode([SavedProp].self, from: data)
            print("Loaded \(savedProps.count) saved props")
        } catch {
            print("Failed to load props metadata: \(error)")
            savedProps = []
        }
    }
    
    /// Convert saved props to discovered props for display
    func toDiscoveredProps() -> [DiscoveredProp] {
        return savedProps.map { saved in
            var prop = DiscoveredProp(
                id: saved.id,
                name: saved.name,
                displayName: saved.displayName,
                sourcePath: assetsFolder.appendingPathComponent(saved.assetsFolder),
                sourceType: .folder
            )
            prop.propType = saved.propType
            prop.placement = saved.placement
            prop.tags = saved.tags
            prop.author = saved.author
            prop.theme = saved.theme
            
            // Load preview if available
            if let previewName = saved.previewFileName {
                let previewPath = previewsFolder.appendingPathComponent(previewName)
                if let image = NSImage(contentsOf: previewPath) {
                    prop.previewImage = image
                    prop.previewGenerated = true
                }
            }
            
            // Find GLB and other assets
            let propAssetsFolder = assetsFolder.appendingPathComponent(saved.assetsFolder)
            if let contents = try? fileManager.contentsOfDirectory(at: propAssetsFolder, includingPropertiesForKeys: nil) {
                prop.glbFile = contents.first { ["glb", "gltf"].contains($0.pathExtension.lowercased()) }
                prop.textureFiles = contents.filter { ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
                
                // Find video
                if saved.hasVideo, let videoFile = contents.first(where: { ["mp4", "m4v", "mov", "mkv"].contains($0.pathExtension.lowercased()) }) {
                    prop.videoInfo = PropVideoInfo(
                        file: videoFile,
                        format: videoFile.pathExtension.lowercased(),
                        needsConversion: !["mp4", "m4v", "mov"].contains(videoFile.pathExtension.lowercased())
                    )
                }
                
                // Find audio
                if saved.hasAudio {
                    prop.audioFiles = contents.filter { ["mp3", "wav", "m4a", "ogg"].contains($0.pathExtension.lowercased()) }
                }
            }
            
            return prop
        }
    }
    
    // MARK: - Saving
    
    /// Save a single prop to storage
    func saveProp(_ prop: DiscoveredProp, progress: ((Double, String) -> Void)? = nil) async -> Bool {
        progress?(0.1, "Preparing to save \(prop.displayName)...")
        
        // Create assets folder for this prop
        let propAssetsFolder = assetsFolder.appendingPathComponent(prop.name)
        
        do {
            // Remove existing if present
            if fileManager.fileExists(atPath: propAssetsFolder.path) {
                try fileManager.removeItem(at: propAssetsFolder)
            }
            try fileManager.createDirectory(at: propAssetsFolder, withIntermediateDirectories: true)
            
            progress?(0.3, "Copying assets...")
            
            // Copy GLB
            if let glbFile = prop.glbFile, fileManager.fileExists(atPath: glbFile.path) {
                try fileManager.copyItem(at: glbFile, to: propAssetsFolder.appendingPathComponent(glbFile.lastPathComponent))
            }
            
            // Copy textures
            for texture in prop.textureFiles {
                if fileManager.fileExists(atPath: texture.path) {
                    try fileManager.copyItem(at: texture, to: propAssetsFolder.appendingPathComponent(texture.lastPathComponent))
                }
            }
            
            // Copy video
            if let video = prop.videoInfo?.file, fileManager.fileExists(atPath: video.path) {
                try fileManager.copyItem(at: video, to: propAssetsFolder.appendingPathComponent(video.lastPathComponent))
            }
            
            // Copy audio
            for audio in prop.audioFiles {
                if fileManager.fileExists(atPath: audio.path) {
                    try fileManager.copyItem(at: audio, to: propAssetsFolder.appendingPathComponent(audio.lastPathComponent))
                }
            }
            
            // Copy YAML if exists
            let yamlPath = prop.sourcePath.appendingPathComponent("description.yaml")
            if fileManager.fileExists(atPath: yamlPath.path) {
                try fileManager.copyItem(at: yamlPath, to: propAssetsFolder.appendingPathComponent("description.yaml"))
            }
            
            progress?(0.6, "Saving preview...")
            
            // Save preview image
            var previewFileName: String? = nil
            if let preview = prop.previewImage {
                previewFileName = "\(prop.id)_preview.png"
                let previewPath = previewsFolder.appendingPathComponent(previewFileName!)
                if let tiffData = preview.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    try pngData.write(to: previewPath)
                }
            }
            
            progress?(0.8, "Updating metadata...")
            
            // Create saved prop entry
            let savedProp = SavedProp(
                id: prop.id,
                name: prop.name,
                displayName: prop.displayName,
                propType: prop.propType,
                placement: prop.placement,
                tags: prop.tags,
                hasVideo: prop.hasVideo,
                hasAudio: prop.hasAudio,
                author: prop.author,
                theme: prop.theme,
                dateAdded: Date(),
                previewFileName: previewFileName,
                assetsFolder: prop.name
            )
            
            // Update metadata
            await MainActor.run {
                // Remove existing entry if present
                savedProps.removeAll { $0.id == prop.id }
                savedProps.append(savedProp)
            }
            
            // Save metadata file
            try saveMetadata()
            
            progress?(1.0, "Saved \(prop.displayName)")
            return true
            
        } catch {
            print("Failed to save prop \(prop.name): \(error)")
            return false
        }
    }
    
    /// Save multiple props
    func saveProps(_ props: [DiscoveredProp], progress: @escaping (Double, String) -> Void) async -> Int {
        var savedCount = 0
        let total = Double(props.count)
        
        for (index, prop) in props.enumerated() {
            let subProgress: (Double, String) -> Void = { p, msg in
                let overall = (Double(index) + p) / total
                progress(overall, msg)
            }
            
            if await saveProp(prop, progress: subProgress) {
                savedCount += 1
            }
        }
        
        return savedCount
    }
    
    // MARK: - Metadata
    
    private func saveMetadata() throws {
        let data = try JSONEncoder().encode(savedProps)
        try data.write(to: metadataFile)
    }
    
    // MARK: - Duplicate Check
    
    func isDuplicate(_ prop: DiscoveredProp) -> Bool {
        return savedProps.contains { $0.id == prop.id || $0.name == prop.name }
    }
    
    func countDuplicates(in props: [DiscoveredProp]) -> Int {
        return props.filter { isDuplicate($0) }.count
    }
    
    // MARK: - Deletion
    
    func deleteProp(_ id: String) throws {
        guard let prop = savedProps.first(where: { $0.id == id }) else { return }
        
        // Remove assets folder
        let propAssetsFolder = assetsFolder.appendingPathComponent(prop.assetsFolder)
        try? fileManager.removeItem(at: propAssetsFolder)
        
        // Remove preview
        if let previewName = prop.previewFileName {
            try? fileManager.removeItem(at: previewsFolder.appendingPathComponent(previewName))
        }
        
        // Update metadata
        savedProps.removeAll { $0.id == id }
        try saveMetadata()
    }
    
    func clearAllProps() throws {
        // Remove all assets
        try? fileManager.removeItem(at: assetsFolder)
        try fileManager.createDirectory(at: assetsFolder, withIntermediateDirectories: true)
        
        // Remove all previews
        try? fileManager.removeItem(at: previewsFolder)
        try fileManager.createDirectory(at: previewsFolder, withIntermediateDirectories: true)
        
        // Clear metadata
        savedProps = []
        try saveMetadata()
    }
    
    // MARK: - Storage Info
    
    var storageSize: String {
        guard let enumerator = fileManager.enumerator(at: propsRoot, includingPropertiesForKeys: [.fileSizeKey]) else {
            return "0 MB"
        }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }
        
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSize)
    }
    
    // MARK: - Backup & Restore
    
    func createBackup(to destinationURL: URL, progress: @escaping (Double, String) -> Void) async throws {
        progress(0.1, "Preparing props backup...")
        
        let tempBackupDir = fileManager.temporaryDirectory.appendingPathComponent("PropsBackup_\(Date().timeIntervalSince1970)")
        try fileManager.createDirectory(at: tempBackupDir, withIntermediateDirectories: true)
        
        defer {
            try? fileManager.removeItem(at: tempBackupDir)
        }
        
        // Copy all props data
        progress(0.3, "Copying props data...")
        
        let itemsToCopy = ["Assets", "Previews", "props_metadata.json"]
        for item in itemsToCopy {
            let source = propsRoot.appendingPathComponent(item)
            let dest = tempBackupDir.appendingPathComponent(item)
            if fileManager.fileExists(atPath: source.path) {
                try fileManager.copyItem(at: source, to: dest)
            }
        }
        
        // Create backup info
        let backupInfo: [String: Any] = [
            "version": "1.0",
            "type": "props",
            "createdDate": ISO8601DateFormatter().string(from: Date()),
            "propCount": savedProps.count
        ]
        let infoData = try JSONSerialization.data(withJSONObject: backupInfo)
        try infoData.write(to: tempBackupDir.appendingPathComponent("backup_info.json"))
        
        progress(0.6, "Creating ZIP archive...")
        
        // Create ZIP
        let zipProcess = Process()
        zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zipProcess.arguments = ["-c", "-k", "--sequesterRsrc", tempBackupDir.path, destinationURL.path]
        
        try zipProcess.run()
        zipProcess.waitUntilExit()
        
        guard zipProcess.terminationStatus == 0 else {
            throw PropsStorageError.backupFailed("ZIP creation failed")
        }
        
        progress(1.0, "Props backup complete!")
    }
    
    func restoreBackup(from backupURL: URL, progress: @escaping (Double, String) -> Void) async throws -> Int {
        progress(0.1, "Extracting props backup...")
        
        let tempExtractDir = fileManager.temporaryDirectory.appendingPathComponent("PropsRestore_\(Date().timeIntervalSince1970)")
        try fileManager.createDirectory(at: tempExtractDir, withIntermediateDirectories: true)
        
        defer {
            try? fileManager.removeItem(at: tempExtractDir)
        }
        
        // Extract ZIP
        let unzipProcess = Process()
        unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzipProcess.arguments = ["-o", "-q", backupURL.path, "-d", tempExtractDir.path]
        
        try unzipProcess.run()
        unzipProcess.waitUntilExit()
        
        guard unzipProcess.terminationStatus == 0 else {
            throw PropsStorageError.restoreFailed("ZIP extraction failed")
        }
        
        progress(0.4, "Restoring props...")
        
        // Copy assets
        let sourceAssets = tempExtractDir.appendingPathComponent("Assets")
        if fileManager.fileExists(atPath: sourceAssets.path) {
            // Merge with existing
            if let contents = try? fileManager.contentsOfDirectory(at: sourceAssets, includingPropertiesForKeys: nil) {
                for item in contents {
                    let dest = assetsFolder.appendingPathComponent(item.lastPathComponent)
                    if !fileManager.fileExists(atPath: dest.path) {
                        try? fileManager.copyItem(at: item, to: dest)
                    }
                }
            }
        }
        
        // Copy previews
        let sourcePreviews = tempExtractDir.appendingPathComponent("Previews")
        if fileManager.fileExists(atPath: sourcePreviews.path) {
            if let contents = try? fileManager.contentsOfDirectory(at: sourcePreviews, includingPropertiesForKeys: nil) {
                for item in contents {
                    let dest = previewsFolder.appendingPathComponent(item.lastPathComponent)
                    if !fileManager.fileExists(atPath: dest.path) {
                        try? fileManager.copyItem(at: item, to: dest)
                    }
                }
            }
        }
        
        progress(0.7, "Loading metadata...")
        
        // Merge metadata
        let sourceMetadata = tempExtractDir.appendingPathComponent("props_metadata.json")
        if fileManager.fileExists(atPath: sourceMetadata.path) {
            let data = try Data(contentsOf: sourceMetadata)
            let importedProps = try JSONDecoder().decode([SavedProp].self, from: data)
            
            var importedCount = 0
            for imported in importedProps {
                if !savedProps.contains(where: { $0.id == imported.id }) {
                    savedProps.append(imported)
                    importedCount += 1
                }
            }
            
            try saveMetadata()
            
            progress(1.0, "Imported \(importedCount) props")
            return importedCount
        }
        
        return 0
    }
}

// MARK: - Errors

enum PropsStorageError: LocalizedError {
    case backupFailed(String)
    case restoreFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .backupFailed(let reason): return "Backup failed: \(reason)"
        case .restoreFailed(let reason): return "Restore failed: \(reason)"
        }
    }
}
