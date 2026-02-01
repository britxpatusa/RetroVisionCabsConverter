import Foundation

@MainActor
final class ProcessRunner: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var log: String = ""
    @Published var lastExitCode: Int32? = nil
    @Published var validationSummary: ValidationSummary?
    @Published var showValidationAlert: Bool = false

    private var process: Process?
    private var pipe: Pipe?
    private var pathsToSanitize: [String: String] = [:]
    private let validationEngine = ValidationEngine()

    func clearLog() {
        log = ""
        lastExitCode = nil
        validationSummary = nil
    }
    
    // MARK: - Validation
    
    /// Validate selected cabinets before conversion
    func validateCabinets(_ items: [CabinetItem], detailManager: CabinetDetailManager) -> ValidationSummary {
        var details: [CabinetDetail] = []
        
        for item in items {
            let detail = detailManager.loadDetail(for: item.path)
            details.append(detail)
        }
        
        let summary = validationEngine.validateBatch(details)
        validationSummary = summary
        
        return summary
    }
    
    /// Run validation and show results in log
    func runValidation(_ items: [CabinetItem], detailManager: CabinetDetailManager) {
        clearLog()
        
        append("Validating \(items.count) cabinet(s)...\n\n")
        
        var readyCount = 0
        var warningCount = 0
        var errorCount = 0
        
        for item in items {
            let detail = detailManager.loadDetail(for: item.path)
            
            switch detail.overallStatus {
            case .valid:
                append("  ✓ \(detail.name)\n")
                readyCount += 1
                
            case .warning(let msg):
                append("  ⚠️ \(detail.name): \(msg)\n")
                warningCount += 1
                
            case .error(let msg):
                append("  ❌ \(detail.name): \(msg)\n")
                errorCount += 1
                
            case .suggestion:
                append("  💡 \(detail.name): Has suggestions\n")
                warningCount += 1
            }
        }
        
        append("\n--- Summary ---\n")
        append("Ready: \(readyCount)\n")
        append("Warnings: \(warningCount)\n")
        append("Errors: \(errorCount)\n")
        
        if errorCount > 0 {
            append("\n⚠️ Some cabinets have errors. Review and fix issues before converting.\n")
        } else if warningCount > 0 {
            append("\n✅ Ready to convert (with \(warningCount) warning(s))\n")
        } else {
            append("\n✅ All cabinets ready!\n")
        }
        
        validationSummary = ValidationSummary(
            totalCount: items.count,
            readyCount: readyCount,
            warningCount: warningCount,
            errorCount: errorCount,
            issues: []
        )
    }
    
    /// Run conversion with pre-validation
    func runConvertWithValidation(
        paths: RetroVisionPaths,
        items: [CabinetItem],
        detailManager: CabinetDetailManager,
        skipErrors: Bool = false,
        templateMap: [String: String] = [:]  // cabinetID -> templatePath
    ) {
        // First validate
        let summary = validateCabinets(items, detailManager: detailManager)
        
        if summary.errorCount > 0 && !skipErrors {
            // Show validation alert
            clearLog()
            append("⚠️ Validation found \(summary.errorCount) error(s)\n\n")
            
            for issue in summary.issues where issue.severity == .error {
                append("  ❌ \(issue.cabinetName): \(issue.message)\n")
            }
            
            append("\nFix the errors or choose to skip problematic cabinets.\n")
            showValidationAlert = true
            return
        }
        
        // Proceed with conversion
        runConvertAll(paths: paths, templateMap: templateMap)
    }

    func stop() {
        process?.terminate()
    }

    private func append(_ text: String) {
        guard !text.isEmpty else { return }
        let sanitized = sanitizeOutput(text)
        log += sanitized
        if !log.hasSuffix("\n") { log += "\n" }
    }
    
    /// Sanitize output to hide paths and technical details
    private func sanitizeOutput(_ text: String) -> String {
        var result = text
        
        // Replace known paths with friendly names
        for (path, replacement) in pathsToSanitize {
            result = result.replacingOccurrences(of: path, with: replacement)
        }
        
        // Remove common path patterns
        let patterns: [(String, String)] = [
            // Home directory paths
            (#"/Users/[^/\s\"]+/"#, "~/"),
            // Volumes paths
            (#"/Volumes/[^/\s\"]+/"#, "[Drive]/"),
            // Application Support
            (#"Library/Application Support/[^/\s\"]+"#, "[App Data]"),
            // Blender path
            (#"/Applications/Blender\.app/Contents/MacOS/Blender"#, "Blender"),
            // Python venv paths
            (#"/[^\s\"]+/venv/bin/python"#, "Python"),
            // Generic deep paths (more than 3 levels)
            (#"(/[^/\s\"]{1,30}){4,}"#, "[...]"),
            // Error paths with colons
            (#"at: /[^\n]+"#, ""),
            (#"at /[^\n]+"#, ""),
            // Script paths
            (#"Script: [^\n]+"#, ""),
            (#"Source: [^\n]+"#, ""),
            (#"Output: [^\n]+"#, ""),
            // Log file paths
            (#"\(see [^\)]+\)"#, "(see log file)"),
        ]
        
        for (pattern, replacement) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: replacement
                )
            }
        }
        
        // Clean up multiple newlines
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        
        return result
    }
    
    /// Setup path sanitization mappings
    private func setupSanitization(paths: RetroVisionPaths) {
        pathsToSanitize = [
            paths.ageCabinetsRoot: "[Cabinets]",
            paths.workspaceRoot: "[Workspace]",
            paths.outputUSDZ: "[Output]",
            paths.venvPath: "[Python]",
            paths.blenderPath: "Blender",
            paths.bundledScriptsPath: "[Internal]",
            paths.bundledPythonScriptsPath: "[Internal]",
            paths.tmpDir: "[Temp]",
            paths.logsDir: "[Logs]",
        ]
        
        // Also add home directory
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            pathsToSanitize[home] = "~"
        }
    }

    func runConvertAll(paths: RetroVisionPaths, templateMap: [String: String] = [:]) {
        clearLog()
        isRunning = true
        setupSanitization(paths: paths)

        let scriptPath = paths.converterScript
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            append("❌ Conversion script not found.")
            append("Please restart the app to reinitialize.")
            isRunning = false
            return
        }

        // Ensure directories exist
        do {
            try paths.ensureDirectoriesExist()
        } catch {
            append("⚠️ Warning: Could not create output directories")
        }
        
        // Save template map as JSON for the script to read
        let templateMapPath = (paths.workRetroVision as NSString).appendingPathComponent("template_map.json")
        if !templateMap.isEmpty {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: templateMap, options: .prettyPrinted)
                try jsonData.write(to: URL(fileURLWithPath: templateMapPath))
                append("📦 Template assignments:\n")
                for (cabinetID, path) in templateMap.sorted(by: { $0.key < $1.key }) {
                    let templateName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                    append("  • \(cabinetID) → \(templateName)\n")
                }
                append("\n")
            } catch {
                append("⚠️ Could not save template map: \(error.localizedDescription)\n")
            }
        }

        // Build the command with proper environment setup
        let cmd = """
        set -e
        export TMPDIR=\"\(paths.tmpDir)/\"
        export TEMP=\"\(paths.tmpDir)/\"
        export TMP=\"\(paths.tmpDir)/\"
        export TMPPREFIX=\"\(paths.tmpDir)/zsh_\"
        mkdir -p \"$TMPDIR\"

        \"\(scriptPath)\"
        """

        let p = Process()
        p.launchPath = "/bin/zsh"
        p.arguments = ["-lc", cmd]

        // Use the environment from RetroVisionPaths
        var env = paths.scriptEnvironment()
        
        // Add template map path
        if !templateMap.isEmpty {
            env["CABINET_TEMPLATE_MAP"] = templateMapPath
        }
        
        p.environment = env

        let pipe = Pipe()
        self.pipe = pipe
        p.standardOutput = pipe
        p.standardError = pipe

        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { return }
            if let str = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    self?.append(str)
                }
            }
        }

        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                handle.readabilityHandler = nil
                self?.lastExitCode = proc.terminationStatus
                if proc.terminationStatus == 0 {
                    self?.append("\n✅ Conversion completed successfully!\n")
                } else {
                    self?.append("\n❌ Conversion failed. Check the log for details.\n")
                }
                self?.isRunning = false
            }
        }

        self.process = p
        do {
            try p.run()
            append("▶️ Starting conversion...\n\n")
        } catch {
            append("❌ Could not start conversion process\n")
            isRunning = false
        }
    }
    
    // MARK: - Gallery Conversion
    
    /// Convert cabinets from the Gallery view
    func runGalleryConversion(
        sources: [String],
        templateMapPath: String,
        paths: RetroVisionPaths
    ) async throws {
        await MainActor.run {
            clearLog()
            isRunning = true
            setupSanitization(paths: paths)
        }
        
        let scriptPath = paths.converterScript
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            await MainActor.run {
                append("❌ Conversion script not found.")
                isRunning = false
            }
            throw ConversionError.scriptNotFound
        }
        
        // Ensure directories exist
        do {
            try paths.ensureDirectoriesExist()
        } catch {
            await MainActor.run {
                append("⚠️ Warning: Could not create output directories")
            }
        }
        
        await MainActor.run {
            append("📦 Gallery conversion: \(sources.count) cabinet(s)\n\n")
        }
        
        // Convert each cabinet
        for (index, sourcePath) in sources.enumerated() {
            let cabinetName = URL(fileURLWithPath: sourcePath).lastPathComponent
            
            await MainActor.run {
                append("[\(index + 1)/\(sources.count)] Converting: \(cabinetName)\n")
            }
            
            // Build the command
            let cmd = """
            set -e
            export TMPDIR=\"\(paths.tmpDir)/\"
            export TEMP=\"\(paths.tmpDir)/\"
            export TMP=\"\(paths.tmpDir)/\"
            mkdir -p \"$TMPDIR\"
            
            # Set cabinet template from map
            export CABINET_TEMPLATE_MAP=\"\(templateMapPath)\"
            export RETROVISION_GALLERY_SOURCE=\"\(sourcePath)\"
            
            \"\(scriptPath)\"
            """
            
            let p = Process()
            p.launchPath = "/bin/zsh"
            p.arguments = ["-lc", cmd]
            
            var env = paths.scriptEnvironment()
            env["RETROVISION_AGE_SRC"] = sourcePath
            env["CABINET_TEMPLATE_MAP"] = templateMapPath
            p.environment = env
            
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            
            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = { [weak self] h in
                let data = h.availableData
                guard !data.isEmpty else { return }
                if let str = String(data: data, encoding: .utf8) {
                    Task { @MainActor in
                        self?.append(str)
                    }
                }
            }
            
            try p.run()
            p.waitUntilExit()
            handle.readabilityHandler = nil
            
            if p.terminationStatus != 0 {
                await MainActor.run {
                    append("⚠️ Failed to convert: \(cabinetName)\n")
                }
            } else {
                await MainActor.run {
                    append("✓ Completed: \(cabinetName)\n\n")
                }
            }
        }
        
        await MainActor.run {
            isRunning = false
            append("\n✅ Gallery conversion finished!\n")
        }
    }
    
    // MARK: - Single Cabinet Conversion
    
    /// Convert a single cabinet to USDZ
    /// - Parameters:
    ///   - cabinetPath: Path to the cabinet folder containing description.yaml
    ///   - paths: RetroVisionPaths configuration
    ///   - onProgress: Callback for progress updates
    ///   - completion: Called when conversion completes with the USDZ URL or error
    func convertSingleCabinet(
        cabinetPath: String,
        paths: RetroVisionPaths,
        onProgress: @escaping (String) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        setupSanitization(paths: paths)
        
        let scriptPath = paths.singleConverterScript
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            completion(.failure(ConversionError.scriptNotFound))
            return
        }
        
        // Verify cabinet has description.yaml
        let descPath = (cabinetPath as NSString).appendingPathComponent("description.yaml")
        guard FileManager.default.fileExists(atPath: descPath) else {
            completion(.failure(ConversionError.missingDescription))
            return
        }
        
        // Ensure output directories exist
        do {
            try paths.ensureDirectoriesExist()
        } catch {
            onProgress("⚠️ Warning: Could not create output directories")
        }
        
        // Build the command
        let cmd = """
        set -e
        export TMPDIR=\"\(paths.tmpDir)/\"
        export TEMP=\"\(paths.tmpDir)/\"
        export TMP=\"\(paths.tmpDir)/\"
        export TMPPREFIX=\"\(paths.tmpDir)/zsh_\"
        mkdir -p \"$TMPDIR\"
        
        \"\(scriptPath)\" \"\(cabinetPath)\"
        """
        
        let p = Process()
        p.launchPath = "/bin/zsh"
        p.arguments = ["-lc", cmd]
        p.environment = paths.scriptEnvironment()
        
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { return }
            if let str = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    let sanitized = self?.sanitizeOutput(str) ?? str
                    onProgress(sanitized)
                }
            }
        }
        
        p.terminationHandler = { proc in
            Task { @MainActor in
                handle.readabilityHandler = nil
                
                if proc.terminationStatus == 0 {
                    // Extract USDZ path from output - now in cabinet's own folder
                    let cabinetName = (cabinetPath as NSString).lastPathComponent
                    let cabinetOutputFolder = URL(fileURLWithPath: paths.outputUSDZ)
                        .appendingPathComponent(cabinetName)
                    let usdzPath = cabinetOutputFolder
                        .appendingPathComponent("\(cabinetName).usdz")
                    
                    if FileManager.default.fileExists(atPath: usdzPath.path) {
                        completion(.success(usdzPath))
                    } else {
                        completion(.failure(ConversionError.outputNotFound))
                    }
                } else {
                    completion(.failure(ConversionError.conversionFailed(exitCode: proc.terminationStatus)))
                }
            }
        }
        
        do {
            try p.run()
            onProgress("▶️ Starting conversion...\n")
        } catch {
            completion(.failure(ConversionError.processStartFailed))
        }
    }
    
    enum ConversionError: LocalizedError {
        case scriptNotFound
        case missingDescription
        case outputNotFound
        case conversionFailed(exitCode: Int32)
        case processStartFailed
        
        var errorDescription: String? {
            switch self {
            case .scriptNotFound:
                return "Conversion script not found. Please restart the app."
            case .missingDescription:
                return "Cabinet is missing description.yaml file."
            case .outputNotFound:
                return "Conversion completed but USDZ file was not created."
            case .conversionFailed(let exitCode):
                return "Conversion failed with exit code \(exitCode). Check the log for details."
            case .processStartFailed:
                return "Could not start the conversion process."
            }
        }
    }
    
    // MARK: - Run Check Tools
    
    func runCheckTools(paths: RetroVisionPaths) {
        clearLog()
        isRunning = true
        setupSanitization(paths: paths)
        
        let scriptPath = paths.checkToolsScript
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            append("❌ Tool check script not found")
            isRunning = false
            return
        }
        
        let p = Process()
        p.launchPath = "/bin/zsh"
        p.arguments = ["-lc", "\"\(scriptPath)\""]
        p.environment = paths.scriptEnvironment()
        
        let pipe = Pipe()
        self.pipe = pipe
        p.standardOutput = pipe
        p.standardError = pipe
        
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { return }
            if let str = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    self?.append(str)
                }
            }
        }
        
        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                handle.readabilityHandler = nil
                self?.lastExitCode = proc.terminationStatus
                self?.isRunning = false
            }
        }
        
        self.process = p
        do {
            try p.run()
            append("▶️ Checking tools...\n\n")
        } catch {
            append("❌ Could not run tool check\n")
            isRunning = false
        }
    }
}
