import SwiftUI
import AppKit

struct FolderSetupView: View {
    @Binding var paths: RetroVisionPaths
    let onComplete: () -> Void
    
    @State private var ageCabinetsPath: String = ""
    @State private var workspacePath: String = ""
    @State private var isCreatingFolders = false
    @State private var setupError: String?
    @State private var setupComplete = false
    
    var canContinue: Bool {
        !ageCabinetsPath.isEmpty && !workspacePath.isEmpty && !isCreatingFolders
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 24) {
                    if setupComplete {
                        setupCompleteContent
                    } else {
                        folderSelectionContent
                    }
                }
                .padding(24)
            }
            
            Divider()
            
            // Footer
            footerView
        }
        .frame(minWidth: 600, idealWidth: 750, maxWidth: 900, minHeight: 500, idealHeight: 600, maxHeight: 700)
        .onAppear {
            // Load any previously saved paths
            ageCabinetsPath = paths.ageCabinetsRoot
            workspacePath = paths.workspaceRoot
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 16) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 40))
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("RetroVision Cabs Converter")
                    .font(.title)
                    .fontWeight(.semibold)
                
                Text("Folder Setup")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Folder Selection Content
    
    private var folderSelectionContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.fill.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.blue.gradient)
            
            Text("Select Your Folders")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Please select the folders where your arcade cabinet files are stored and where you want the converter to work.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 500)
            
            VStack(spacing: 20) {
                // Age Cabinets folder
                folderPickerCard(
                    title: "Age Cabinets Folder",
                    description: "Select the folder containing your Age of Joy cabinet folders (each with description.yaml files)",
                    icon: "arcade.stick.console",
                    path: $ageCabinetsPath,
                    placeholder: "Select folder containing cabinet definitions..."
                )
                
                // Workspace folder
                folderPickerCard(
                    title: "Workspace Folder",
                    description: "Select or create a folder where the converter will store output files, temporary data, and logs",
                    icon: "hammer",
                    path: $workspacePath,
                    placeholder: "Select or create workspace folder..."
                )
            }
            
            // Info about what will be created
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("The following folders will be created in your workspace:", systemImage: "info.circle")
                        .font(.callout)
                        .fontWeight(.medium)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        folderInfoRow("Output/USDZ", description: "Converted USDZ files")
                        folderInfoRow("_Work/AoJ", description: "Job files and temporary data")
                        folderInfoRow("_Work/RetroVision", description: "Working files")
                        folderInfoRow("ModelLibrary", description: "Shared model templates")
                        folderInfoRow(".temp", description: "Temporary files (auto-cleaned on exit)")
                        folderInfoRow("_logs", description: "Conversion logs")
                    }
                    .padding(.leading, 24)
                    
                    Divider()
                    
                    Label("Temp files are stored in your workspace to avoid disk space issues", systemImage: "clock.badge.checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }
            
            if let error = setupError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
    
    private func folderPickerCard(
        title: String,
        description: String,
        icon: String,
        path: Binding<String>,
        placeholder: String
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: 30)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                HStack(spacing: 12) {
                    TextField(placeholder, text: path)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Choose...") {
                        selectFolder(for: path)
                    }
                }
                
                if !path.wrappedValue.isEmpty {
                    HStack {
                        if FileManager.default.fileExists(atPath: path.wrappedValue) {
                            Label("Folder exists", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Label("Folder will be created", systemImage: "folder.badge.plus")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .padding(8)
        }
    }
    
    private func folderInfoRow(_ name: String, description: String) -> some View {
        HStack {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(name)
                .font(.system(size: 12, design: .monospaced))
            Text("—")
                .foregroundStyle(.secondary)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Setup Complete Content
    
    private var setupCompleteContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green.gradient)
            
            Text("Folders Ready!")
                .font(.title)
                .fontWeight(.semibold)
            
            Text("Your workspace has been set up and all necessary folders have been created.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 450)
            
            VStack(alignment: .leading, spacing: 12) {
                folderStatusRow(name: "Age Cabinets", path: ageCabinetsPath)
                folderStatusRow(name: "Workspace", path: workspacePath)
                folderStatusRow(name: "Output (USDZ)", path: "\(workspacePath)/Output/USDZ")
                folderStatusRow(name: "Model Library", path: "\(workspacePath)/ModelLibrary")
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    
    private func folderStatusRow(name: String, path: String) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(name)
                .fontWeight(.medium)
            Spacer()
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Open in Finder")
        }
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            Button("Back") {
                // Go back - but in this flow we can't really go back
                // This could reset setup
                setupComplete = false
                setupError = nil
            }
            .opacity(setupComplete ? 1 : 0)
            
            Spacer()
            
            if setupComplete {
                Button("Open Workspace") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: workspacePath))
                }
                
                Button("Start Converting") {
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Set Up Folders") {
                    createFoldersAndContinue()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canContinue)
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Actions
    
    private func selectFolder(for path: Binding<String>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Choose a folder"
        
        if panel.runModal() == .OK, let url = panel.url {
            path.wrappedValue = url.path
        }
    }
    
    private func createFoldersAndContinue() {
        isCreatingFolders = true
        setupError = nil
        
        Task {
            do {
                let fm = FileManager.default
                
                // Create Age Cabinets folder if it doesn't exist
                if !fm.fileExists(atPath: ageCabinetsPath) {
                    try fm.createDirectory(atPath: ageCabinetsPath, withIntermediateDirectories: true)
                }
                
                // Create workspace and all subdirectories
                let workspaceDirs = [
                    workspacePath,
                    "\(workspacePath)/Output/USDZ",
                    "\(workspacePath)/_Work/AoJ",
                    "\(workspacePath)/_Work/RetroVision",
                    "\(workspacePath)/ModelLibrary",
                    "\(workspacePath)/.temp",
                    "\(workspacePath)/.temp/blender",
                    "\(workspacePath)/.temp/gallery",
                    "\(workspacePath)/.temp/previews",
                    "\(workspacePath)/_logs"
                ]
                
                for dir in workspaceDirs {
                    if !fm.fileExists(atPath: dir) {
                        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
                    }
                }
                
                // Save paths
                paths.ageCabinetsRoot = ageCabinetsPath
                paths.workspaceRoot = workspacePath
                paths.save()
                
                await MainActor.run {
                    isCreatingFolders = false
                    setupComplete = true
                }
                
            } catch {
                await MainActor.run {
                    isCreatingFolders = false
                    setupError = "Failed to create folders: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    FolderSetupView(paths: .constant(RetroVisionPaths())) {
        print("Setup complete")
    }
}
