import Foundation
import SwiftUI

// MARK: - Dependency Status

enum DependencyStatus: Equatable {
    case unknown
    case checking
    case installed(version: String)
    case missing
    case installing
    case failed(String)
    
    var isReady: Bool {
        if case .installed = self { return true }
        return false
    }
    
    var displayText: String {
        switch self {
        case .unknown: return "Unknown"
        case .checking: return "Checking..."
        case .installed(let version): return "Installed (\(version))"
        case .missing: return "Not Installed"
        case .installing: return "Installing..."
        case .failed(let msg): return "Failed: \(msg)"
        }
    }
    
    var color: Color {
        switch self {
        case .installed: return .green
        case .missing, .failed: return .red
        case .checking, .installing: return .orange
        case .unknown: return .secondary
        }
    }
}

// MARK: - Dependency Info

struct DependencyInfo: Identifiable {
    let id: String
    let name: String
    let description: String
    let downloadURL: URL?
    var status: DependencyStatus
    
    static let blender = DependencyInfo(
        id: "blender",
        name: "Blender 3D",
        description: "Required for converting GLB models to USDZ format. Download the free, open-source 3D software.",
        downloadURL: URL(string: "https://www.blender.org/download/"),
        status: .unknown
    )
    
    static let python3 = DependencyInfo(
        id: "python3",
        name: "Python 3",
        description: "Required scripting language for running conversion tools. Usually pre-installed on macOS.",
        downloadURL: URL(string: "https://www.python.org/downloads/macos/"),
        status: .unknown
    )
    
    static let pythonVenv = DependencyInfo(
        id: "venv",
        name: "Python Packages",
        description: "Required libraries: usd-core (USD/USDZ support), pillow (images), numpy, pyyaml (YAML parsing)",
        downloadURL: nil,
        status: .unknown
    )
}

// MARK: - Dependency Manager

@MainActor
final class DependencyManager: ObservableObject {
    @Published var blender: DependencyInfo = .blender
    @Published var python3: DependencyInfo = .python3
    @Published var pythonVenv: DependencyInfo = .pythonVenv
    
    @Published var setupLog: String = ""
    @Published var isSettingUp: Bool = false
    
    // Paths
    private let defaultBlenderPath = "/Applications/Blender.app/Contents/MacOS/Blender"
    
    var venvPath: String {
        // Store venv in Application Support for persistence
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("RetroVisionCabsConverter")
        return appFolder.appendingPathComponent("venv").path
    }
    
    var blenderPath: String {
        defaultBlenderPath
    }
    
    var allDependenciesReady: Bool {
        blender.status.isReady && python3.status.isReady && pythonVenv.status.isReady
    }
    
    var bundledScriptsPath: String {
        Bundle.main.resourcePath.map { "\($0)/Scripts" } ?? ""
    }
    
    var bundledPythonScriptsPath: String {
        "\(bundledScriptsPath)/python"
    }
    
    var bundledShellScriptsPath: String {
        "\(bundledScriptsPath)/bin"
    }
    
    // MARK: - Check Dependencies
    
    func checkAll() async {
        await checkBlender()
        await checkPython3()
        await checkPythonVenv()
    }
    
    func checkBlender() async {
        blender.status = .checking
        
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: defaultBlenderPath) else {
            blender.status = .missing
            return
        }
        
        // Get version
        let version = await runCommand(defaultBlenderPath, arguments: ["--version"])
        if let firstLine = version?.components(separatedBy: "\n").first,
           firstLine.contains("Blender") {
            let ver = firstLine.replacingOccurrences(of: "Blender ", with: "")
            blender.status = .installed(version: ver)
        } else {
            blender.status = .installed(version: "Unknown")
        }
    }
    
    func checkPython3() async {
        python3.status = .checking
        
        // Check for python3 in common locations
        let possiblePaths = [
            "/usr/bin/python3",
            "/usr/local/bin/python3",
            "/opt/homebrew/bin/python3"
        ]
        
        var foundPath: String?
        for path in possiblePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                foundPath = path
                break
            }
        }
        
        guard let pythonPath = foundPath else {
            python3.status = .missing
            return
        }
        
        let version = await runCommand(pythonPath, arguments: ["--version"])
        if let ver = version?.trimmingCharacters(in: .whitespacesAndNewlines) {
            python3.status = .installed(version: ver.replacingOccurrences(of: "Python ", with: ""))
        } else {
            python3.status = .installed(version: "Found")
        }
    }
    
    func checkPythonVenv() async {
        pythonVenv.status = .checking
        
        let pythonExe = "\(venvPath)/bin/python"
        let fm = FileManager.default
        
        guard fm.isExecutableFile(atPath: pythonExe) else {
            pythonVenv.status = .missing
            return
        }
        
        // Check if required packages are installed
        let checkScript = """
        import sys
        try:
            from pxr import Usd
            import PIL
            import numpy
            import yaml
            print(f"OK:{Usd.GetVersion()}")
        except ImportError as e:
            print(f"MISSING:{e}")
            sys.exit(1)
        """
        
        let result = await runCommand(pythonExe, arguments: ["-c", checkScript])
        if let output = result, output.hasPrefix("OK:") {
            let version = output.replacingOccurrences(of: "OK:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            pythonVenv.status = .installed(version: "USD \(version)")
        } else {
            pythonVenv.status = .missing
        }
    }
    
    // MARK: - Install Dependencies
    
    func installPythonVenv() async {
        guard python3.status.isReady else {
            appendLog("ERROR: Python 3 must be installed first")
            return
        }
        
        isSettingUp = true
        pythonVenv.status = .installing
        setupLog = ""
        
        appendLog("Creating Python virtual environment...")
        appendLog("Path: \(venvPath)")
        
        // Create parent directory
        let parentDir = URL(fileURLWithPath: venvPath).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        
        // Find python3
        let pythonPath = findPython3Path() ?? "/usr/bin/python3"
        
        // Create venv
        appendLog("\n==> Creating venv...")
        let createResult = await runCommandWithOutput(pythonPath, arguments: ["-m", "venv", venvPath])
        if !createResult.success {
            pythonVenv.status = .failed("Failed to create venv")
            isSettingUp = false
            return
        }
        
        let pipPath = "\(venvPath)/bin/pip"
        
        // Upgrade pip
        appendLog("\n==> Upgrading pip...")
        _ = await runCommandWithOutput(pipPath, arguments: ["install", "--upgrade", "pip", "setuptools", "wheel"])
        
        // Install packages
        appendLog("\n==> Installing usd-core (this may take a few minutes)...")
        let usdResult = await runCommandWithOutput(pipPath, arguments: ["install", "usd-core"])
        if !usdResult.success {
            appendLog("WARNING: usd-core installation may have issues")
        }
        
        appendLog("\n==> Installing pillow...")
        _ = await runCommandWithOutput(pipPath, arguments: ["install", "pillow"])
        
        appendLog("\n==> Installing numpy...")
        _ = await runCommandWithOutput(pipPath, arguments: ["install", "numpy"])
        
        appendLog("\n==> Installing pyyaml...")
        _ = await runCommandWithOutput(pipPath, arguments: ["install", "pyyaml"])
        
        appendLog("\n==> Verifying installation...")
        await checkPythonVenv()
        
        if pythonVenv.status.isReady {
            appendLog("\n✅ Python environment setup complete!")
        } else {
            appendLog("\n❌ Setup completed with errors. Some packages may be missing.")
        }
        
        isSettingUp = false
    }
    
    func openBlenderDownload() {
        if let url = blender.downloadURL {
            NSWorkspace.shared.open(url)
        }
    }
    
    func openPythonDownload() {
        if let url = python3.downloadURL {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Helpers
    
    private func findPython3Path() -> String? {
        let possiblePaths = [
            "/usr/bin/python3",
            "/usr/local/bin/python3",
            "/opt/homebrew/bin/python3"
        ]
        
        for path in possiblePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
    
    private func appendLog(_ text: String) {
        setupLog += text + "\n"
    }
    
    private func runCommand(_ command: String, arguments: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: command)
                process.arguments = arguments
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func runCommandWithOutput(_ command: String, arguments: [String]) async -> (success: Bool, output: String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: command)
                process.arguments = arguments
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                
                // Stream output
                let handle = pipe.fileHandleForReading
                var output = ""
                
                handle.readabilityHandler = { h in
                    let data = h.availableData
                    if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                        output += str
                        Task { @MainActor in
                            self?.appendLog(str)
                        }
                    }
                }
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    handle.readabilityHandler = nil
                    
                    let success = process.terminationStatus == 0
                    continuation.resume(returning: (success, output))
                } catch {
                    handle.readabilityHandler = nil
                    continuation.resume(returning: (false, error.localizedDescription))
                }
            }
        }
    }
}

// MARK: - App Storage Keys

extension UserDefaults {
    static let hasCompletedSetupKey = "hasCompletedSetup"
    
    var hasCompletedSetup: Bool {
        get { bool(forKey: Self.hasCompletedSetupKey) }
        set { set(newValue, forKey: Self.hasCompletedSetupKey) }
    }
}
