import Foundation

struct RetroVisionPaths: Codable {
    // User-configurable paths (empty by default for fresh installs)
    var ageCabinetsRoot: String = ""
    var workspaceRoot: String = ""
    
    // Temp directory path - defaults to system temp, but can be set to workspace
    // Using workspace temp avoids cross-filesystem issues when system disk is full
    var tempBasePath: String = ""
    
    // Check if paths have been configured
    var isConfigured: Bool {
        !ageCabinetsRoot.isEmpty && !workspaceRoot.isEmpty
    }
    
    // External Blender path
    var blenderPath: String = "/Applications/Blender.app/Contents/MacOS/Blender"
    
    // Computed paths for output
    var outputUSDZ: String { "\(workspaceRoot)/Output/USDZ" }
    var workRetroVision: String { "\(workspaceRoot)/_Work/RetroVision" }
    var workAoJ: String { "\(workspaceRoot)/_Work/AoJ" }
    var modelLibrary: String { "\(workspaceRoot)/ModelLibrary" }
    
    // Temp directory - uses configured path or defaults to workspace
    var tmpDir: String {
        if !tempBasePath.isEmpty {
            return "\(tempBasePath)/RetroVisionTemp"
        }
        // Default to workspace to avoid cross-filesystem issues
        return "\(workspaceRoot)/.temp"
    }
    var logsDir: String { "\(workspaceRoot)/_logs" }
    
    // Specific temp subdirectories
    var blenderTempDir: String { "\(tmpDir)/blender" }
    var galleryTempDir: String { "\(tmpDir)/gallery" }
    var previewCacheDir: String { "\(tmpDir)/previews" }
    var viewerTempDir: String { "\(tmpDir)/viewer" }
    var propsConvertTempDir: String { "\(tmpDir)/PropsConvert" }
    var propPreviewCacheDir: String { "\(tmpDir)/PropsPreviewCache" }
    var cabinetZipsTempDir: String { "\(tmpDir)/CabinetZips" }
    var templateZipsTempDir: String { "\(tmpDir)/TemplateZips" }
    var galleryExtractDir: String { "\(tmpDir)/GalleryExtract" }
    var previewLogFile: String { "\(tmpDir)/preview_log.txt" }
    
    // Resource directories (bundled with app or in workspace)
    var templatesDirectory: String {
        // First check for bundled resources
        if let bundlePath = Bundle.main.resourcePath {
            let bundledTemplates = "\(bundlePath)/Templates"
            if FileManager.default.fileExists(atPath: bundledTemplates) {
                return bundledTemplates
            }
        }
        // Fall back to workspace
        return "\(workspaceRoot)/Resources/Templates"
    }
    
    var propTemplatesDirectory: String {
        // First check for bundled resources
        if let bundlePath = Bundle.main.resourcePath {
            let bundledPropTemplates = "\(bundlePath)/PropTemplates"
            if FileManager.default.fileExists(atPath: bundledPropTemplates) {
                return bundledPropTemplates
            }
        }
        // Fall back to workspace
        return "\(workspaceRoot)/Resources/PropTemplates"
    }
    
    var sharedAssetsDirectory: String {
        if let bundlePath = Bundle.main.resourcePath {
            let bundledAssets = "\(bundlePath)/SharedAssets"
            if FileManager.default.fileExists(atPath: bundledAssets) {
                return bundledAssets
            }
        }
        return "\(workspaceRoot)/Resources/SharedAssets"
    }
    
    var visionOSCodeDirectory: String {
        if let bundlePath = Bundle.main.resourcePath {
            let bundledCode = "\(bundlePath)/VisionOSCode"
            if FileManager.default.fileExists(atPath: bundledCode) {
                return bundledCode
            }
        }
        return "\(workspaceRoot)/Resources/VisionOSCode"
    }
    
    // Python virtual environment (stored in Application Support)
    var venvPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("RetroVisionCabsConverter")
        return appFolder.appendingPathComponent("venv").path
    }
    
    // MARK: - Secure Scripts (embedded in app, extracted at runtime)
    
    var bundledScriptsPath: String {
        SecureScriptManager.shared.shellScriptsPath
    }
    
    var bundledBinPath: String {
        SecureScriptManager.shared.shellScriptsPath
    }
    
    var bundledPythonScriptsPath: String {
        SecureScriptManager.shared.pythonScriptsPath
    }
    
    // Main converter script - extracted from embedded code
    var converterScript: String {
        SecureScriptManager.shared.converterScriptPath
    }
    
    // Single cabinet converter script
    var singleConverterScript: String {
        SecureScriptManager.shared.singleConverterScriptPath
    }
    
    // Setup venv script
    var setupVenvScript: String {
        "\(bundledBinPath)/setup_venv.sh"
    }
    
    // Check tools script
    var checkToolsScript: String {
        "\(bundledBinPath)/check_tools.sh"
    }
    
    // MARK: - Environment Variables for Scripts
    
    /// Returns environment variables to pass to conversion scripts
    func scriptEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        
        // Set RetroVision-specific environment variables
        env["RETROVISION_BASE"] = workspaceRoot
        env["RETROVISION_AGE_SRC"] = ageCabinetsRoot
        env["RETROVISION_VENV"] = venvPath
        env["RETROVISION_BLENDER"] = blenderPath
        env["RETROVISION_SCRIPTS"] = bundledPythonScriptsPath
        
        // Temp directories - use our configured temp path
        env["TMPDIR"] = "\(blenderTempDir)/"
        env["TEMP"] = "\(blenderTempDir)/"
        env["TMP"] = "\(blenderTempDir)/"
        env["TMPPREFIX"] = "\(tmpDir)/zsh_"
        
        // Pass our temp dir to scripts
        env["RETROVISION_TEMP"] = tmpDir
        env["RETROVISION_BLENDER_TEMP"] = blenderTempDir
        
        return env
    }
    
    // MARK: - Validation
    
    func validatePaths() -> [String] {
        var errors: [String] = []
        let fm = FileManager.default
        
        if !fm.fileExists(atPath: ageCabinetsRoot) {
            errors.append("Age Cabinets folder not found: \(ageCabinetsRoot)")
        }
        
        if !fm.fileExists(atPath: workspaceRoot) {
            errors.append("Workspace folder not found: \(workspaceRoot)")
        }
        
        if !fm.isExecutableFile(atPath: blenderPath) {
            errors.append("Blender not found: \(blenderPath)")
        }
        
        let pythonPath = "\(venvPath)/bin/python"
        if !fm.isExecutableFile(atPath: pythonPath) {
            errors.append("Python venv not set up: \(venvPath)")
        }
        
        return errors
    }
    
    // MARK: - Directory Creation
    
    func ensureDirectoriesExist() throws {
        let fm = FileManager.default
        let dirs = [
            outputUSDZ, workRetroVision, workAoJ, modelLibrary, 
            tmpDir, logsDir, blenderTempDir, galleryTempDir, previewCacheDir,
            viewerTempDir, propsConvertTempDir, propPreviewCacheDir,
            cabinetZipsTempDir, templateZipsTempDir, galleryExtractDir
        ]
        
        for dir in dirs {
            if !fm.fileExists(atPath: dir) {
                try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            }
        }
    }
    
    // MARK: - Temp Directory Cleanup
    
    /// Clean up all temporary files
    func cleanupTempFiles() {
        let fm = FileManager.default
        
        // Clean the main temp directory
        if fm.fileExists(atPath: tmpDir) {
            do {
                let contents = try fm.contentsOfDirectory(atPath: tmpDir)
                for item in contents {
                    let itemPath = (tmpDir as NSString).appendingPathComponent(item)
                    try? fm.removeItem(atPath: itemPath)
                }
                print("Cleaned temp directory: \(tmpDir)")
            } catch {
                print("Failed to clean temp directory: \(error)")
            }
        }
        
        // Also clean any stale system temp files we may have created
        let systemTempDirs = [
            "/tmp/cabinet_analysis_all",
            "/tmp/RetroVisionTemp"
        ]
        for dir in systemTempDirs {
            if fm.fileExists(atPath: dir) {
                try? fm.removeItem(atPath: dir)
                print("Cleaned system temp: \(dir)")
            }
        }
    }
    
    /// Clean up secure scripts (call on app termination)
    func cleanupAll() {
        cleanupTempFiles()
        SecureScriptManager.shared.cleanup()
    }
}

// MARK: - Persistence

extension RetroVisionPaths {
    private static let userDefaultsKey = "RetroVisionPaths"
    
    static func load() -> RetroVisionPaths {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let paths = try? JSONDecoder().decode(RetroVisionPaths.self, from: data) else {
            return RetroVisionPaths()
        }
        return paths
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }
}
