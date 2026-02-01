//
//  SecurityUtils.swift
//  RetroVisionCabsConverter
//
//  Security utilities for path sanitization, process management, and ZIP validation
//

import Foundation

// MARK: - Path Sanitization

/// Utilities for sanitizing paths and shell command inputs
enum PathSanitizer {
    
    /// Characters that need escaping in shell commands
    private static let shellSpecialChars = CharacterSet(charactersIn: " '\"\\`$!&|;()<>[]{}*?#~")
    
    /// Sanitize a path for safe use in shell commands
    /// - Parameter path: The path to sanitize
    /// - Returns: Shell-safe escaped path
    static func sanitizeForShell(_ path: String) -> String {
        var result = ""
        for char in path {
            if shellSpecialChars.contains(char.unicodeScalars.first!) {
                result.append("\\")
            }
            result.append(char)
        }
        return result
    }
    
    /// Validate that a path is safe (no path traversal, no special sequences)
    /// - Parameter path: The path to validate
    /// - Returns: true if the path is safe
    static func isPathSafe(_ path: String) -> Bool {
        // Check for path traversal attempts
        if path.contains("..") { return false }
        
        // Check for null bytes
        if path.contains("\0") { return false }
        
        // Check for newlines (could break shell commands)
        if path.contains("\n") || path.contains("\r") { return false }
        
        // Check for shell command substitution
        if path.contains("$(") || path.contains("`") { return false }
        
        // Check for excessive length
        if path.count > 4096 { return false }
        
        return true
    }
    
    /// Sanitize and validate a path, returning nil if unsafe
    /// - Parameter path: The path to sanitize
    /// - Returns: Sanitized path or nil if unsafe
    static func sanitizeAndValidate(_ path: String) -> String? {
        guard isPathSafe(path) else { return nil }
        return sanitizeForShell(path)
    }
    
    /// Validate a filename (no path separators, no special characters)
    /// - Parameter filename: The filename to validate
    /// - Returns: true if the filename is valid
    static func isValidFilename(_ filename: String) -> Bool {
        // No path separators
        if filename.contains("/") || filename.contains("\\") { return false }
        
        // No hidden files that could be system files
        if filename.hasPrefix(".") { return false }
        
        // No excessive length
        if filename.count > 255 { return false }
        
        // Must have content
        if filename.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        
        return isPathSafe(filename)
    }
}

// MARK: - Process Management with Timeout

/// Manages process execution with configurable timeouts
class SecureProcessRunner {
    
    /// Default timeout for quick operations (30 seconds)
    static let defaultTimeout: TimeInterval = 30
    
    /// Extended timeout for long operations like Blender/FFmpeg (10 minutes)
    static let extendedTimeout: TimeInterval = 600
    
    /// Maximum timeout (1 hour)
    static let maximumTimeout: TimeInterval = 3600
    
    /// Run a process with a timeout
    /// - Parameters:
    ///   - executablePath: Path to the executable
    ///   - arguments: Command arguments
    ///   - environment: Environment variables
    ///   - timeout: Timeout in seconds
    ///   - onOutput: Callback for stdout/stderr output
    /// - Returns: Exit code and any captured output
    static func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: String? = nil,
        timeout: TimeInterval = defaultTimeout,
        onOutput: ((String) -> Void)? = nil
    ) async throws -> ProcessResult {
        
        // Validate executable path
        guard PathSanitizer.isPathSafe(executablePath) else {
            throw SecureProcessError.unsafeExecutablePath
        }
        
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw SecureProcessError.executableNotFound(executablePath)
        }
        
        // Validate arguments
        for arg in arguments {
            if !PathSanitizer.isPathSafe(arg) {
                throw SecureProcessError.unsafeArgument(arg)
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            
            if let env = environment {
                process.environment = env
            }
            
            if let workDir = workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: workDir)
            }
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            
            var outputData = Data()
            let outputLock = NSLock()
            
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    outputLock.lock()
                    outputData.append(data)
                    outputLock.unlock()
                    
                    if let str = String(data: data, encoding: .utf8), let callback = onOutput {
                        callback(str)
                    }
                }
            }
            
            // Setup timeout
            var timeoutTask: Task<Void, Never>?
            let processTerminated = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
            processTerminated.pointee = false
            
            timeoutTask = Task {
                do {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    if !processTerminated.pointee {
                        process.terminate()
                        // Give it a moment, then force kill if needed
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        if process.isRunning {
                            process.interrupt() // SIGINT
                        }
                    }
                } catch {
                    // Task was cancelled, process completed normally
                }
            }
            
            process.terminationHandler = { proc in
                processTerminated.pointee = true
                timeoutTask?.cancel()
                
                outputPipe.fileHandleForReading.readabilityHandler = nil
                
                // Read any remaining data
                let remainingData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                outputLock.lock()
                outputData.append(remainingData)
                outputLock.unlock()
                
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let timedOut = proc.terminationReason == .uncaughtSignal
                
                processTerminated.deallocate()
                
                let result = ProcessResult(
                    exitCode: proc.terminationStatus,
                    output: output,
                    timedOut: timedOut
                )
                continuation.resume(returning: result)
            }
            
            do {
                try process.run()
            } catch {
                processTerminated.deallocate()
                timeoutTask?.cancel()
                continuation.resume(throwing: SecureProcessError.launchFailed(error))
            }
        }
    }
    
    struct ProcessResult {
        let exitCode: Int32
        let output: String
        let timedOut: Bool
        
        var success: Bool { exitCode == 0 && !timedOut }
    }
    
    enum SecureProcessError: LocalizedError {
        case unsafeExecutablePath
        case executableNotFound(String)
        case unsafeArgument(String)
        case launchFailed(Error)
        case timeout
        
        var errorDescription: String? {
            switch self {
            case .unsafeExecutablePath:
                return "The executable path contains unsafe characters."
            case .executableNotFound(let path):
                return "Executable not found: \(path)"
            case .unsafeArgument(let arg):
                return "Argument contains unsafe characters: \(arg.prefix(50))"
            case .launchFailed(let error):
                return "Failed to launch process: \(error.localizedDescription)"
            case .timeout:
                return "Process timed out and was terminated."
            }
        }
    }
}

// MARK: - ZIP Validation

/// Validates ZIP files before extraction to prevent security issues
enum ZIPValidator {
    
    /// Maximum allowed file count in a ZIP
    static let maxFileCount = 10_000
    
    /// Maximum allowed total uncompressed size (10 GB)
    static let maxTotalSize: UInt64 = 10 * 1024 * 1024 * 1024
    
    /// Maximum allowed single file size (2 GB)
    static let maxSingleFileSize: UInt64 = 2 * 1024 * 1024 * 1024
    
    /// Maximum compression ratio (to detect ZIP bombs)
    static let maxCompressionRatio: Double = 100.0
    
    /// Allowed file extensions for extraction
    static let allowedExtensions: Set<String> = [
        // 3D models
        "glb", "gltf", "usdz", "obj", "fbx",
        // Images
        "png", "jpg", "jpeg", "gif", "tga", "bmp", "webp",
        // Video
        "mp4", "m4v", "mov", "mkv", "avi", "webm",
        // Audio
        "mp3", "wav", "m4a", "ogg", "aac",
        // Config
        "yaml", "yml", "json", "txt", "md",
    ]
    
    /// Validate a ZIP file before extraction
    /// - Parameter zipURL: URL to the ZIP file
    /// - Returns: Validation result with details
    static func validate(_ zipURL: URL) -> ValidationResult {
        let fm = FileManager.default
        
        guard fm.fileExists(atPath: zipURL.path) else {
            return ValidationResult(valid: false, error: "ZIP file does not exist")
        }
        
        // Check compressed file size
        do {
            let attrs = try fm.attributesOfItem(atPath: zipURL.path)
            if let compressedSize = attrs[.size] as? UInt64 {
                if compressedSize > maxTotalSize {
                    return ValidationResult(valid: false, error: "ZIP file too large")
                }
            }
        } catch {
            return ValidationResult(valid: false, error: "Cannot read ZIP file attributes")
        }
        
        // Use zipinfo to analyze contents
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        process.arguments = ["-l", zipURL.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ValidationResult(valid: false, error: "Cannot analyze ZIP file")
        }
        
        guard process.terminationStatus == 0 else {
            return ValidationResult(valid: false, error: "ZIP file appears corrupted")
        }
        
        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: outputData, encoding: .utf8) else {
            return ValidationResult(valid: false, error: "Cannot read ZIP info")
        }
        
        // Parse zipinfo output
        let lines = output.components(separatedBy: "\n")
        var fileCount = 0
        var totalUncompressedSize: UInt64 = 0
        var suspiciousFiles: [String] = []
        
        for line in lines {
            // Skip empty lines and header/footer
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("Archive:") || trimmed.contains("bytes") {
                continue
            }
            
            fileCount += 1
            
            // Check file count limit
            if fileCount > maxFileCount {
                return ValidationResult(valid: false, error: "ZIP contains too many files (\(fileCount))")
            }
            
            // Parse file info from zipinfo output
            // Format: -rw-r--r--  2.0 unx     1234 b- defN 23-Jan-01 12:00 filename.ext
            let components = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            if components.count >= 8 {
                // Get uncompressed size (4th column)
                if let size = UInt64(components[3]) {
                    totalUncompressedSize += size
                    
                    if size > maxSingleFileSize {
                        return ValidationResult(valid: false, error: "ZIP contains a file larger than 2GB")
                    }
                }
                
                // Get filename (last component)
                let filename = String(components.last ?? "")
                
                // Check for path traversal
                if filename.contains("..") {
                    return ValidationResult(valid: false, error: "ZIP contains path traversal attempt")
                }
                
                // Check for absolute paths
                if filename.hasPrefix("/") {
                    return ValidationResult(valid: false, error: "ZIP contains absolute path")
                }
                
                // Check file extension
                let ext = (filename as NSString).pathExtension.lowercased()
                if !ext.isEmpty && !allowedExtensions.contains(ext) && !filename.hasSuffix("/") {
                    suspiciousFiles.append(filename)
                }
            }
        }
        
        // Check total uncompressed size
        if totalUncompressedSize > maxTotalSize {
            return ValidationResult(
                valid: false,
                error: "ZIP uncompressed size exceeds limit (\(totalUncompressedSize / 1024 / 1024)MB)"
            )
        }
        
        // Check compression ratio (ZIP bomb detection)
        if let attrs = try? fm.attributesOfItem(atPath: zipURL.path),
           let compressedSize = attrs[.size] as? UInt64,
           compressedSize > 0 {
            let ratio = Double(totalUncompressedSize) / Double(compressedSize)
            if ratio > maxCompressionRatio {
                return ValidationResult(
                    valid: false,
                    error: "Suspicious compression ratio (\(Int(ratio))x) - possible ZIP bomb"
                )
            }
        }
        
        // Warn about suspicious files but don't reject
        var warnings: [String] = []
        if !suspiciousFiles.isEmpty {
            warnings.append("ZIP contains \(suspiciousFiles.count) file(s) with unexpected extensions")
        }
        
        return ValidationResult(
            valid: true,
            fileCount: fileCount,
            totalSize: totalUncompressedSize,
            warnings: warnings
        )
    }
    
    struct ValidationResult {
        let valid: Bool
        var error: String?
        var fileCount: Int = 0
        var totalSize: UInt64 = 0
        var warnings: [String] = []
        
        init(valid: Bool, error: String? = nil, fileCount: Int = 0, totalSize: UInt64 = 0, warnings: [String] = []) {
            self.valid = valid
            self.error = error
            self.fileCount = fileCount
            self.totalSize = totalSize
            self.warnings = warnings
        }
    }
}

// MARK: - Security Logging

/// Logs security-relevant events
class SecurityLogger {
    static let shared = SecurityLogger()
    
    private let fileManager = FileManager.default
    private var logURL: URL?
    
    private init() {
        let paths = RetroVisionPaths.load()
        let logsDir = paths.logsDir
        try? fileManager.createDirectory(atPath: logsDir, withIntermediateDirectories: true)
        logURL = URL(fileURLWithPath: logsDir).appendingPathComponent("security.log")
    }
    
    func log(_ event: SecurityEvent) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(timestamp)] [\(event.severity.rawValue)] \(event.type): \(event.message)\n"
        
        guard let url = logURL else { return }
        
        if let data = entry.data(using: .utf8) {
            if fileManager.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: url)
            }
        }
        
        // Also print to console in debug
        #if DEBUG
        print("[Security] \(entry)", terminator: "")
        #endif
    }
    
    struct SecurityEvent {
        enum EventType: String {
            case processExecution = "PROCESS"
            case fileAccess = "FILE_ACCESS"
            case zipExtraction = "ZIP_EXTRACT"
            case pathValidation = "PATH_VALIDATION"
            case timeout = "TIMEOUT"
        }
        
        enum Severity: String {
            case info = "INFO"
            case warning = "WARNING"
            case error = "ERROR"
        }
        
        let type: EventType
        let severity: Severity
        let message: String
    }
}
