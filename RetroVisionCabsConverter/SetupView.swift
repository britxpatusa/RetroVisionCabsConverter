import SwiftUI
import AppKit

struct SetupView: View {
    @ObservedObject var dependencyManager: DependencyManager
    let onComplete: () -> Void
    
    @State private var isChecking = true
    @State private var autoProceeded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 24) {
                    if isChecking {
                        checkingContent
                    } else if dependencyManager.allDependenciesReady {
                        // If all ready, show brief success then auto-proceed
                        readyContent
                    } else {
                        missingDependenciesContent
                    }
                }
                .padding(24)
            }
            
            Divider()
            
            // Footer
            footerView
        }
        .frame(minWidth: 600, idealWidth: 750, maxWidth: 900, minHeight: 500, idealHeight: 650, maxHeight: 750)
        .onAppear {
            checkDependencies()
        }
    }
    
    private func checkDependencies() {
        isChecking = true
        autoProceeded = false
        Task {
            await dependencyManager.checkAll()
            await MainActor.run {
                isChecking = false
                
                // Auto-proceed if all dependencies are ready
                if dependencyManager.allDependenciesReady && !autoProceeded {
                    autoProceeded = true
                    // Small delay to show the green checkmark briefly
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        UserDefaults.standard.hasCompletedSetup = true
                        onComplete()
                    }
                }
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 16) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 40))
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("RetroVision Cabs Converter")
                    .font(.title)
                    .fontWeight(.semibold)
                
                Text("Dependency Check")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Checking Content
    
    private var checkingContent: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
                .padding()
            
            Text("Checking Dependencies...")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Please wait while we verify required software is installed.")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 40)
    }
    
    // MARK: - Ready Content
    
    private var readyContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green.gradient)
            
            Text("All Dependencies Ready!")
                .font(.title)
                .fontWeight(.semibold)
            
            if autoProceeded {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Starting application...")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Everything is installed and configured. You can now start converting arcade cabinet models.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 450)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                statusRow(name: "Blender", status: dependencyManager.blender.status)
                statusRow(name: "Python 3", status: dependencyManager.python3.status)
                statusRow(name: "Python Packages", status: dependencyManager.pythonVenv.status)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    
    // MARK: - Missing Dependencies Content
    
    private var missingDependenciesContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)
            
            Text("Required Software Missing")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("The following dependencies must be installed before you can use this app:")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 500)
            
            VStack(spacing: 16) {
                // Blender
                if !dependencyManager.blender.status.isReady {
                    dependencyCard(
                        info: dependencyManager.blender,
                        instructions: "Download and install Blender from the official website. Drag Blender.app to your Applications folder.",
                        actionLabel: "Download Blender",
                        action: { dependencyManager.openBlenderDownload() }
                    )
                }
                
                // Python 3
                if !dependencyManager.python3.status.isReady {
                    dependencyCard(
                        info: dependencyManager.python3,
                        instructions: "Python 3 is required to run conversion scripts. Install via Homebrew (recommended) or download from python.org.",
                        actionLabel: "Download Python",
                        action: { dependencyManager.openPythonDownload() },
                        secondaryActionLabel: "Install via Homebrew",
                        secondaryAction: { openTerminalWithHomebrew() }
                    )
                }
                
                // Python venv (only show if Python is installed)
                if dependencyManager.python3.status.isReady && !dependencyManager.pythonVenv.status.isReady {
                    venvCard
                }
            }
            
            // Show installed dependencies
            if dependencyManager.blender.status.isReady || dependencyManager.python3.status.isReady || dependencyManager.pythonVenv.status.isReady {
                Divider()
                    .padding(.vertical, 8)
                
                Text("Installed:")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(alignment: .leading, spacing: 8) {
                    if dependencyManager.blender.status.isReady {
                        installedRow(info: dependencyManager.blender)
                    }
                    if dependencyManager.python3.status.isReady {
                        installedRow(info: dependencyManager.python3)
                    }
                    if dependencyManager.pythonVenv.status.isReady {
                        installedRow(info: dependencyManager.pythonVenv)
                    }
                }
            }
        }
    }
    
    private func dependencyCard(
        info: DependencyInfo,
        instructions: String,
        actionLabel: String,
        action: @escaping () -> Void,
        secondaryActionLabel: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.name)
                            .font(.headline)
                        Text(info.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Text("Required")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Capsule())
                }
                
                Text(instructions)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 12) {
                    Button(actionLabel) {
                        action()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    if let secondaryLabel = secondaryActionLabel, let secondaryAction = secondaryAction {
                        Button(secondaryLabel) {
                            secondaryAction()
                        }
                    }
                }
            }
            .padding(8)
        }
    }
    
    private var venvCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: dependencyManager.isSettingUp ? "arrow.triangle.2.circlepath" : "xmark.circle.fill")
                        .foregroundStyle(dependencyManager.isSettingUp ? .orange : .red)
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dependencyManager.pythonVenv.name)
                            .font(.headline)
                        Text(dependencyManager.pythonVenv.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if dependencyManager.isSettingUp {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text("Required")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                
                Text("Click below to automatically install the required Python packages (usd-core, pillow, numpy, pyyaml). This may take a few minutes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                
                Button(dependencyManager.isSettingUp ? "Installing..." : "Install Python Packages") {
                    Task {
                        await dependencyManager.installPythonVenv()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(dependencyManager.isSettingUp)
                
                // Show installation log if installing
                if !dependencyManager.setupLog.isEmpty {
                    GroupBox("Installation Progress") {
                        ScrollView {
                            Text(dependencyManager.setupLog)
                                .font(.system(size: 10, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(height: 120)
                    }
                }
            }
            .padding(8)
        }
    }
    
    private func installedRow(info: DependencyInfo) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(info.name)
            Spacer()
            Text(info.status.displayText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    
    private func statusRow(name: String, status: DependencyStatus) -> some View {
        HStack {
            Image(systemName: status.isReady ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(status.isReady ? .green : .red)
            
            Text(name)
            
            Spacer()
            
            Text(status.displayText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            Button("Quit App") {
                NSApplication.shared.terminate(nil)
            }
            
            Spacer()
            
            // Only show re-check when dependencies are missing
            if !dependencyManager.allDependenciesReady || !autoProceeded {
                Button("Re-check Dependencies") {
                    checkDependencies()
                }
                .disabled(isChecking || dependencyManager.isSettingUp)
            }
            
            // Only show Continue button if dependencies are ready but auto-proceed hasn't happened
            // (e.g., if user navigated back to this view manually)
            if dependencyManager.allDependenciesReady && !autoProceeded && !isChecking {
                Button("Continue") {
                    UserDefaults.standard.hasCompletedSetup = true
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Helpers
    
    private func openTerminalWithHomebrew() {
        let script = """
        tell application "Terminal"
            activate
            do script "brew install python3 || /bin/bash -c \\"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\\""
        end tell
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
        }
    }
}

// MARK: - Preview

#Preview {
    SetupView(dependencyManager: DependencyManager()) {
        print("Setup complete")
    }
}
