import Foundation
import AppKit

struct CabinetItem: Identifiable, Hashable {
    let id: String          // folder name or zip name without extension
    let path: String
    let hasDescriptionYAML: Bool
    let isZipFile: Bool
    let sourceZip: String?  // If extracted from a ZIP pack, the original ZIP path
    
    init(id: String, path: String, hasDescriptionYAML: Bool, isZipFile: Bool = false, sourceZip: String? = nil) {
        self.id = id
        self.path = path
        self.hasDescriptionYAML = hasDescriptionYAML
        self.isZipFile = isZipFile
        self.sourceZip = sourceZip
    }
    
    /// Display name showing source if from a ZIP
    var displayName: String {
        if let source = sourceZip {
            let zipName = URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent
            return "\(id) (from \(zipName))"
        }
        return id
    }
    
    /// Cabinet name (same as id for basic item)
    var name: String { id }
    
    /// Preview image (loaded from cache if available)
    var preview: NSImage? {
        // Try to load from preview cache using configured paths
        let paths = RetroVisionPaths.load()
        let cacheDir = URL(fileURLWithPath: paths.previewCacheDir)
        let cachePath = cacheDir.appendingPathComponent("\(id)_preview.png")
        return NSImage(contentsOf: cachePath)
    }
    
    /// Matched template (parsed from saved state if available)
    var matchedTemplate: String? {
        nil  // Would need to be loaded from state
    }
}

final class CabinetScanner {
    
    /// Cache for extracted ZIP contents
    private static var zipExtractionCache: [String: URL] = [:]
    
    /// Common cabinet file indicators (case-insensitive checking)
    private static let cabinetFileIndicators = [
        "description.yaml", "marquee.png", "bezel.png", "left.png", "right.png", 
        "side.png", "front.png", "back.png", "joystick.png", "control.png"
    ]
    
    func scan(ageCabinetsRoot: String) -> [CabinetItem] {
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: ageCabinetsRoot)

        guard let children = try? fm.contentsOfDirectory(at: rootURL,
                                                         includingPropertiesForKeys: [.isDirectoryKey],
                                                         options: [.skipsHiddenFiles]) else {
            return []
        }

        var out: [CabinetItem] = []

        for url in children {
            // Skip __MACOSX and hidden folders
            if url.lastPathComponent.hasPrefix(".") || url.lastPathComponent == "__MACOSX" {
                continue
            }
            
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            
            if values?.isDirectory == true {
                // It's a folder - check for description.yaml (case-insensitive)
                let hasDesc = hasCabinetDescriptionFile(in: url)
                let hasCabinetContent = hasCabinetContent(in: url)

                out.append(CabinetItem(
                    id: url.lastPathComponent,
                    path: url.path,
                    hasDescriptionYAML: hasDesc || hasCabinetContent,
                    isZipFile: false
                ))
            } else if url.pathExtension.lowercased() == "zip" {
                // It's a ZIP file - add directly without slow classification
                // ZIP extraction/inspection happens when user selects it
                let zipName = url.deletingPathExtension().lastPathComponent
                out.append(CabinetItem(
                    id: zipName,
                    path: url.path,
                    hasDescriptionYAML: true,  // Assume valid for now
                    isZipFile: true
                ))
            }
        }

        out.sort { $0.id.lowercased() < $1.id.lowercased() }
        return out
    }
    
    /// Check if a folder contains a description.yaml file (case-insensitive)
    private func hasCabinetDescriptionFile(in folderURL: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: folderURL,
                                                                           includingPropertiesForKeys: nil,
                                                                           options: [.skipsHiddenFiles]) else {
            return false
        }
        
        return contents.contains { url in
            url.lastPathComponent.lowercased() == "description.yaml"
        }
    }
    
    /// Check if a folder contains cabinet content files (GLB, common artwork)
    private func hasCabinetContent(in folderURL: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: folderURL,
                                                                           includingPropertiesForKeys: nil,
                                                                           options: [.skipsHiddenFiles]) else {
            return false
        }
        
        let filenames = contents.map { $0.lastPathComponent.lowercased() }
        
        // Check for GLB model files
        if filenames.contains(where: { $0.hasSuffix(".glb") }) {
            return true
        }
        
        // Check for common cabinet artwork files
        let artworkIndicators = ["marquee.png", "bezel.png", "left.png", "right.png", 
                                 "side.png", "front.png", "joystick.png", "control.png"]
        let matchCount = artworkIndicators.filter { indicator in
            filenames.contains(where: { $0.contains(indicator) || $0 == indicator })
        }.count
        
        // If at least 2 artwork files match, consider it cabinet content
        return matchCount >= 2
    }
    
    /// Classification of ZIP contents
    private enum ZipContentType {
        case singleCabinet    // Contains description.yaml and cabinet files
        case cabinetPack      // Contains nested ZIP files (pack of cabinets)
        case unknown          // Unknown content
    }
    
    /// Classify what type of content a ZIP file contains
    private func classifyZipContents(zipURL: URL) -> ZipContentType {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        process.arguments = ["-1", zipURL.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return .unknown }
            
            let files = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
            let lowercasedFiles = files.map { $0.lowercased() }
            
            // Check for description.yaml (case-insensitive, at root or in subfolder)
            let hasDescYAML = lowercasedFiles.contains { file in
                file == "description.yaml" || 
                file.hasSuffix("/description.yaml")
            }
            
            // Check for nested ZIP files (cabinet pack)
            let nestedZipCount = lowercasedFiles.filter { $0.hasSuffix(".zip") }.count
            let hasNestedZips = nestedZipCount > 0
            
            // Check for GLB model files
            let hasGLB = lowercasedFiles.contains { $0.hasSuffix(".glb") }
            
            // Check for MKV video files (intro videos)
            let hasMKV = lowercasedFiles.contains { $0.hasSuffix(".mkv") }
            
            // Check for common cabinet artwork files
            let artworkIndicators = [
                "marquee.png", "bezel.png", "left.png", "right.png", "side.png",
                "front.png", "back.png", "joystick.png", "control.png", "kick.png",
                "sideart", "side-art", "side_art"
            ]
            
            var artworkMatchCount = 0
            for indicator in artworkIndicators {
                if lowercasedFiles.contains(where: { $0.contains(indicator) }) {
                    artworkMatchCount += 1
                }
            }
            let hasCabinetArtwork = artworkMatchCount >= 2  // At least 2 artwork files
            
            // Classify based on findings
            // If it's mostly ZIPs and no cabinet content, it's a pack
            if hasNestedZips && !hasDescYAML && !hasGLB && artworkMatchCount < 2 {
                return .cabinetPack
            }
            
            // If it has cabinet content indicators, it's a single cabinet
            if hasDescYAML || hasGLB || hasCabinetArtwork || hasMKV {
                return .singleCabinet
            }
            
            // If it only has nested ZIPs (and nothing else suggests cabinet content)
            if hasNestedZips {
                return .cabinetPack
            }
            
        } catch {
            print("Failed to classify ZIP: \(error)")
        }
        
        return .unknown
    }
    
    /// Check if a ZIP file contains cabinet content
    /// Returns true if it contains description.yaml, GLB files, or nested cabinet ZIPs
    private func checkZipForDescriptionYAML(zipURL: URL) -> Bool {
        // Use zipinfo to list contents without extracting
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        process.arguments = ["-1", zipURL.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return false }
            
            let files = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
            
            // Check for description.yaml at root level (case-insensitive)
            if files.contains(where: { $0.lowercased() == "description.yaml" }) {
                return true
            }
            
            // Check for description.yaml in any subfolder
            for file in files {
                let lowercased = file.lowercased()
                if lowercased.hasSuffix("/description.yaml") || lowercased.hasSuffix("\\description.yaml") {
                    return true
                }
            }
            
            // Check for GLB files as an indicator of cabinet content
            let hasGLB = files.contains { $0.lowercased().hasSuffix(".glb") }
            if hasGLB {
                return true
            }
            
            // Check if this is a pack of cabinet ZIPs (ZIP containing ZIPs)
            let hasNestedZips = files.contains { $0.lowercased().hasSuffix(".zip") }
            if hasNestedZips {
                return true  // Contains nested ZIPs - likely a cabinet pack
            }
            
            // Check for common cabinet artwork files as indicators
            let cabinetIndicators = ["marquee.png", "bezel.png", "left.png", "right.png", "side.png"]
            let hasCabinetArtwork = files.contains { file in
                let lowercased = file.lowercased()
                return cabinetIndicators.contains { lowercased.hasSuffix($0) }
            }
            if hasCabinetArtwork {
                return true
            }
            
        } catch {
            print("Failed to check ZIP contents: \(error)")
        }
        
        return false
    }
    
    /// Get temp directory (avoids filling up Macintosh HD)
    static var externalTempDirectory: URL {
        // Use configured workspace temp folder instead of system temp
        let paths = RetroVisionPaths.load()
        return URL(fileURLWithPath: paths.cabinetZipsTempDir)
    }
    
    /// Extract a ZIP file to a temporary location for processing
    static func extractZipForProcessing(_ zipPath: String) -> URL? {
        // Check cache first
        if let cached = zipExtractionCache[zipPath] {
            if FileManager.default.fileExists(atPath: cached.path) {
                return cached
            }
        }
        
        let zipURL = URL(fileURLWithPath: zipPath)
        
        // Validate ZIP before extraction (security check)
        let validation = ZIPValidator.validate(zipURL)
        if !validation.valid {
            SecurityLogger.shared.log(SecurityLogger.SecurityEvent(
                type: .zipExtraction,
                severity: .error,
                message: "ZIP validation failed for \(zipURL.lastPathComponent): \(validation.error ?? "unknown")"
            ))
            print("ZIP validation failed: \(validation.error ?? "unknown error")")
            return nil
        }
        
        // Log warnings if any
        for warning in validation.warnings {
            SecurityLogger.shared.log(SecurityLogger.SecurityEvent(
                type: .zipExtraction,
                severity: .warning,
                message: "ZIP warning for \(zipURL.lastPathComponent): \(warning)"
            ))
        }
        
        let tempDir = externalTempDirectory
            .appendingPathComponent(zipURL.deletingPathExtension().lastPathComponent)
        
        // Clean up any existing extraction
        try? FileManager.default.removeItem(at: tempDir)
        
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            // Extract using unzip
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-q", "-o", zipPath, "-d", tempDir.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                // Check if files are in a subfolder
                let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                    .filter { !$0.lastPathComponent.hasPrefix(".") && !$0.lastPathComponent.hasPrefix("__MACOSX") }
                
                // If there's a single subfolder, use that as the cabinet root
                if contents.count == 1, 
                   let first = contents.first,
                   (try? first.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    zipExtractionCache[zipPath] = first
                    return first
                }
                
                // Check if this is a pack of nested ZIPs - extract them too
                let nestedZips = contents.filter { $0.pathExtension.lowercased() == "zip" }
                if !nestedZips.isEmpty {
                    // Extract all nested ZIPs
                    for nestedZip in nestedZips {
                        let nestedDir = tempDir.appendingPathComponent(nestedZip.deletingPathExtension().lastPathComponent)
                        try? FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
                        
                        let nestedProcess = Process()
                        nestedProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                        nestedProcess.arguments = ["-q", "-o", nestedZip.path, "-d", nestedDir.path]
                        nestedProcess.standardOutput = FileHandle.nullDevice
                        nestedProcess.standardError = FileHandle.nullDevice
                        
                        try? nestedProcess.run()
                        nestedProcess.waitUntilExit()
                    }
                }
                
                zipExtractionCache[zipPath] = tempDir
                return tempDir
            }
        } catch {
            print("Failed to extract ZIP: \(error)")
        }
        
        return nil
    }
    
    /// Scan a ZIP pack for multiple cabinets (handles nested ZIPs)
    static func scanZipPack(_ zipPath: String) -> [CabinetItem] {
        guard let extractedURL = extractZipForProcessing(zipPath) else {
            return []
        }
        
        var items: [CabinetItem] = []
        let fm = FileManager.default
        
        // Check contents
        guard let contents = try? fm.contentsOfDirectory(at: extractedURL, 
                                                          includingPropertiesForKeys: [.isDirectoryKey],
                                                          options: [.skipsHiddenFiles]) else {
            return []
        }
        
        for url in contents {
            // Skip __MACOSX and hidden files
            if url.lastPathComponent.hasPrefix(".") || url.lastPathComponent == "__MACOSX" {
                continue
            }
            
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            
            if values?.isDirectory == true {
                // Check if this folder has description.yaml (case-insensitive) or cabinet content
                let hasDesc = hasCabinetDescriptionFileStatic(in: url)
                let hasCabContent = hasCabinetContentStatic(in: url)
                
                items.append(CabinetItem(
                    id: url.lastPathComponent,
                    path: url.path,
                    hasDescriptionYAML: hasDesc || hasCabContent,
                    isZipFile: false
                ))
            }
        }
        
        return items
    }
    
    /// Static version: Check if a folder contains a description.yaml file (case-insensitive)
    private static func hasCabinetDescriptionFileStatic(in folderURL: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: folderURL,
                                                                           includingPropertiesForKeys: nil,
                                                                           options: [.skipsHiddenFiles]) else {
            return false
        }
        
        return contents.contains { url in
            url.lastPathComponent.lowercased() == "description.yaml"
        }
    }
    
    /// Static version: Check if a folder contains cabinet content files (GLB, common artwork)
    private static func hasCabinetContentStatic(in folderURL: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: folderURL,
                                                                           includingPropertiesForKeys: nil,
                                                                           options: [.skipsHiddenFiles]) else {
            return false
        }
        
        let filenames = contents.map { $0.lastPathComponent.lowercased() }
        
        // Check for GLB model files
        if filenames.contains(where: { $0.hasSuffix(".glb") }) {
            return true
        }
        
        // Check for common cabinet artwork files
        let artworkIndicators = ["marquee.png", "bezel.png", "left.png", "right.png", 
                                 "side.png", "front.png", "joystick.png", "control.png"]
        let matchCount = artworkIndicators.filter { indicator in
            filenames.contains(where: { $0.contains(indicator) || $0 == indicator })
        }.count
        
        // If at least 2 artwork files match, consider it cabinet content
        return matchCount >= 2
    }
    
    /// Clean up extracted ZIP caches
    static func cleanupExtractedZips() {
        // Clean up external temp directory
        try? FileManager.default.removeItem(at: externalTempDirectory)
        // Also clean legacy system temp location
        let systemTemp = FileManager.default.temporaryDirectory.appendingPathComponent("CabinetZips")
        try? FileManager.default.removeItem(at: systemTemp)
        zipExtractionCache.removeAll()
    }
}
