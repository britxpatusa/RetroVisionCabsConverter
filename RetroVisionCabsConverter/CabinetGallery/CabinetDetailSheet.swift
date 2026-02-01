import SwiftUI
import AppKit
import SceneKit

// MARK: - Cabinet Detail Sheet

/// Detailed view of a cabinet with large 3D preview and asset list
struct CabinetDetailSheet: View {
    let cabinet: DiscoveredCabinet
    let templates: [CabinetTemplate]
    @ObservedObject var templateManager: TemplateManager
    let onTemplateChange: (String) -> Void
    let onClose: () -> Void
    
    @State private var selectedTemplateID: String
    @State private var showFullscreen3D = false
    @State private var isLoading3D = false
    @State private var sceneURL: URL?
    @State private var isCreatingTemplate = false
    @State private var creationError: String?
    @State private var templateRefreshTrigger = UUID()  // Triggers re-analysis when changed
    @State private var showVisionOSExport = false
    
    init(cabinet: DiscoveredCabinet, templates: [CabinetTemplate], templateManager: TemplateManager, onTemplateChange: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        self.cabinet = cabinet
        self.templates = templates
        self.templateManager = templateManager
        self.onTemplateChange = onTemplateChange
        self.onClose = onClose
        self._selectedTemplateID = State(initialValue: cabinet.suggestedTemplateID)
    }
    
    /// Convert DiscoveredCabinet to CabinetItem for export
    private var cabinetAsCabinetItem: CabinetItem {
        CabinetItem(
            id: cabinet.id,
            path: cabinet.sourcePath.path,
            hasDescriptionYAML: true,
            isZipFile: cabinet.sourceType == .zip,
            sourceZip: nil
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Main content
            HStack(alignment: .top, spacing: 24) {
                // Large Preview
                previewSection
                
                // Details panel
                detailsPanel
            }
            .padding(20)
            
            Divider()
            
            // Footer
            footerView
        }
        .frame(minWidth: 800, idealWidth: 950, maxWidth: 1200, minHeight: 550, idealHeight: 700, maxHeight: 900)
        .sheet(isPresented: $showFullscreen3D) {
            Fullscreen3DViewer(
                cabinet: cabinet,
                glbURL: cabinet.glbFile,
                onClose: { showFullscreen3D = false }
            )
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            // Back button
            Button {
                onClose()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.escape)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(cabinet.displayName)
                    .font(.title)
                    .fontWeight(.bold)
                
                HStack(spacing: 16) {
                    if let game = cabinet.game {
                        Label(game, systemImage: "gamecontroller")
                    }
                    if let author = cabinet.author {
                        Label(author, systemImage: "person")
                    }
                    if let year = cabinet.year {
                        Label(year, systemImage: "calendar")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.leading, 12)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Preview Section
    
    private var previewSection: some View {
        VStack(spacing: 12) {
            // Large preview image
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(nsColor: .controlBackgroundColor))
                
                if let preview = cabinet.previewImage {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(12)
                        .padding(8)
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Generating preview...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(minWidth: 350, idealWidth: 450, maxWidth: 550, minHeight: 350, idealHeight: 450, maxHeight: 550)
            .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
            
            // View 3D button
            if cabinet.glbFile != nil {
                Button {
                    showFullscreen3D = true
                } label: {
                    Label("View Full 3D Model", systemImage: "rotate.3d")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }
    
    // MARK: - Details Panel
    
    private var detailsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Template matching and selection
            TemplateMatchView(
                cabinet: cabinet,
                templateManager: templateManager,
                selectedTemplateID: $selectedTemplateID,
                refreshTrigger: templateRefreshTrigger,
                onCreateTemplate: { name, id in
                    createTemplate(name: name, id: id)
                }
            )
            .onChange(of: selectedTemplateID) { _, newValue in
                onTemplateChange(newValue)
            }
            
            if isCreatingTemplate {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Creating template...")
                        .font(.caption)
                }
            }
            
            if let error = creationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            
            // Completeness
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Completeness", systemImage: "checkmark.circle")
                        .font(.headline)
                    
                    HStack {
                        ProgressView(value: cabinet.completenessScore)
                            .tint(completenessColor)
                        Text("\(Int(cabinet.completenessScore * 100))%")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(completenessColor)
                    }
                    
                    if !cabinet.missingParts.isEmpty {
                        Text("Missing: \(cabinet.missingParts.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Label("All required assets found!", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                .padding(4)
            }
            
            // Asset list
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Assets (\(cabinet.assets.count))", systemImage: "photo.stack")
                        .font(.headline)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(cabinet.requiredParts, id: \.self) { part in
                                assetRow(for: part)
                            }
                            
                            if !cabinet.assets.filter({ !cabinet.requiredParts.contains($0.inferredMeshName ?? "") }).isEmpty {
                                Divider()
                                    .padding(.vertical, 4)
                                
                                Text("Additional Assets")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                ForEach(cabinet.assets.filter { asset in
                                    !cabinet.requiredParts.contains(asset.inferredMeshName ?? "")
                                }) { asset in
                                    extraAssetRow(asset)
                                }
                            }
                        }
                    }
                    .frame(height: 180)
                }
                .padding(4)
            }
            
            // GLB info
            if let glb = cabinet.glbFile {
                GroupBox {
                    HStack {
                        Label("3D Model", systemImage: "cube.fill")
                            .font(.headline)
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(glb.lastPathComponent)
                                .font(.caption)
                            Text("\(cabinet.glbMeshNames.count) meshes")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(4)
                }
            }
        }
        .frame(minWidth: 300, idealWidth: 380, maxWidth: 450)
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            // Source info
            HStack(spacing: 4) {
                Image(systemName: cabinet.sourceType == .zip ? "doc.zipper" : "folder")
                Text(cabinet.sourcePath.lastPathComponent)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            
            Spacer()
            
            // Selected template indicator
            if let template = templateManager.template(withId: selectedTemplateID) {
                HStack(spacing: 6) {
                    Image(systemName: "cube.fill")
                        .foregroundStyle(.blue)
                    Text("Template: \(template.name)")
                        .fontWeight(.medium)
                }
                .font(.caption)
            }
            
            Spacer()
            
            Button {
                showVisionOSExport = true
            } label: {
                Label("Export for VisionOS", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            
            Button("Done") {
                onClose()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .sheet(isPresented: $showVisionOSExport) {
            CabinetExportSheet(cabinet: cabinetAsCabinetItem) {
                showVisionOSExport = false
            }
        }
    }
    
    // MARK: - Asset Rows
    
    private func assetRow(for part: String) -> some View {
        HStack {
            if let assetFile = cabinet.meshMappings[part] {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(part)
                    .fontWeight(.medium)
                Spacer()
                Text(assetFile)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.orange)
                Text(part)
                    .fontWeight(.medium)
                Spacer()
                Text("(fallback)")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
    }
    
    private func extraAssetRow(_ asset: DiscoveredAsset) -> some View {
        HStack {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
            Text(asset.filename)
            Spacer()
            if let mesh = asset.inferredMeshName {
                Text("→ \(mesh)")
                    .foregroundStyle(.blue)
            }
        }
        .font(.caption)
    }
    
    // MARK: - Helpers
    
    private var completenessColor: Color {
        switch cabinet.completenessScore {
        case 1.0: return .green
        case 0.75...: return .yellow
        case 0.5...: return .orange
        default: return .red
        }
    }
    
    private func iconForTemplate(_ templateID: String) -> String {
        switch templateID.lowercased() {
        case "upright": return "arcade.stick.console"
        case "neogeo": return "gamecontroller.fill"
        case "vertical": return "rectangle.portrait.fill"
        case "driving": return "car.fill"
        case "flightstick": return "airplane"
        case "lightgun": return "scope"
        case "cocktail": return "tablecells"
        default: return "cube.fill"
        }
    }
    
    // MARK: - Template Creation
    
    private func createTemplate(name: String, id: String) {
        isCreatingTemplate = true
        creationError = nil
        
        Task {
            do {
                let newTemplate = try await templateManager.createTemplate(from: cabinet, name: name, id: id)
                await MainActor.run {
                    // Set the new template as selected
                    selectedTemplateID = newTemplate.id
                    onTemplateChange(newTemplate.id)
                    
                    // Trigger refresh of template matching view
                    templateRefreshTrigger = UUID()
                    
                    isCreatingTemplate = false
                }
            } catch {
                await MainActor.run {
                    creationError = error.localizedDescription
                    isCreatingTemplate = false
                }
            }
        }
    }
}

// MARK: - Interactive 3D Viewer

struct Fullscreen3DViewer: View {
    let cabinet: DiscoveredCabinet
    let glbURL: URL?
    let onClose: () -> Void
    
    @State private var scene: SCNScene?
    @State private var isLoading = true
    @State private var loadingMessage = "Preparing 3D model..."
    @State private var errorMessage: String?
    @State private var usdzURL: URL?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                // Back button (prominent, on the left)
                Button {
                    cleanup()
                    onClose()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape)
                
                VStack(alignment: .leading) {
                    Text(cabinet.displayName)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Drag to rotate • Scroll to zoom • Shift+drag to pan")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 12)
                
                Spacer()
                
                // View Log button
                Button {
                    let logURL = PreviewLogger.shared.getLogFileURL()
                    if FileManager.default.fileExists(atPath: logURL.path) {
                        NSWorkspace.shared.open(logURL)
                    }
                } label: {
                    Label("View Log", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
                .help("Open the preview generation log file")
                
                // External app buttons
                if let glbURL = glbURL {
                    Button {
                        openInBlender(glbURL)
                    } label: {
                        Label("Blender", systemImage: "cube")
                    }
                    .buttonStyle(.bordered)
                    
                    Button {
                        if let usdz = usdzURL {
                            NSWorkspace.shared.open(usdz)
                        } else {
                            openInRealityConverter(glbURL)
                        }
                    } label: {
                        Label("Quick Look", systemImage: "eye")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            
            Divider()
            
            // 3D View
            ZStack {
                if isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text(loadingMessage)
                            .font(.headline)
                        Text("Converting GLB to viewable format...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
                } else if let error = errorMessage {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 60))
                            .foregroundStyle(.orange)
                        Text("Could not load 3D model")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 400)
                        
                        HStack {
                            Button("View Log") {
                                let logURL = PreviewLogger.shared.getLogFileURL()
                                if FileManager.default.fileExists(atPath: logURL.path) {
                                    NSWorkspace.shared.open(logURL)
                                }
                            }
                            .buttonStyle(.bordered)
                            
                            if let glbURL = glbURL {
                                Button("Open in Blender") {
                                    openInBlender(glbURL)
                                }
                                .buttonStyle(.borderedProminent)
                                
                                Button("Open in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([glbURL])
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
                } else if let scene = scene {
                    GallerySceneView(scene: scene)
                }
            }
            
            Divider()
            
            // Footer
            HStack {
                if let glb = glbURL {
                    Image(systemName: "cube.fill")
                        .foregroundStyle(.blue)
                    Text(glb.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if scene != nil {
                    Text("Left-drag: Rotate • Scroll: Zoom • Right-drag: Pan")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding()
        }
        .frame(minWidth: 800, idealWidth: 1100, maxWidth: 1400, minHeight: 600, idealHeight: 850, maxHeight: 1000)
        .onAppear {
            loadModel()
        }
        .onDisappear {
            cleanup()
        }
    }
    
    private func loadModel() {
        let logger = PreviewLogger.shared
        logger.startSession(for: "\(cabinet.displayName) - 3D Viewer")
        
        guard let glbURL = glbURL else {
            logger.log(.error, "No 3D model file available")
            errorMessage = "No 3D model file available"
            isLoading = false
            logger.endSession(success: false)
            return
        }
        
        logger.log(.info, "Starting 3D model conversion", details: "GLB: \(glbURL.path)")
        
        Task.detached(priority: .userInitiated) {
            await MainActor.run {
                self.loadingMessage = "Converting model..."
            }
            
            // Check if GLB file exists
            if !FileManager.default.fileExists(atPath: glbURL.path) {
                logger.log(.error, "GLB file does not exist!", details: glbURL.path)
                await MainActor.run {
                    self.errorMessage = "GLB file not found: \(glbURL.lastPathComponent)"
                    self.isLoading = false
                }
                logger.endSession(success: false)
                return
            }
            
            // Get file size
            if let attrs = try? FileManager.default.attributesOfItem(atPath: glbURL.path),
               let size = attrs[.size] as? Int64 {
                logger.log(.debug, "GLB file size: \(size / 1024) KB")
            }
            
            // Convert GLB to USDZ using Blender
            // IMPORTANT: Use configured temp directory to avoid cross-filesystem issues
            let configPaths = RetroVisionPaths.load()
            let tempDir = URL(fileURLWithPath: configPaths.viewerTempDir)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let outputPath = tempDir.appendingPathComponent("viewer_\(UUID().uuidString).usdz")
            logger.log(.info, "Output USDZ path: \(outputPath.path)")
            
            // Set Blender temp directory as well
            let blenderTempDir = configPaths.blenderTempDir
            try? FileManager.default.createDirectory(atPath: blenderTempDir, withIntermediateDirectories: true)
            logger.log(.debug, "Blender temp dir: \(blenderTempDir)")
            
            let script = """
            import bpy
            import math
            import os
            import sys
            
            print("3DVIEWER_LOG: Starting GLB to USDZ conversion")
            print(f"3DVIEWER_LOG: Input: \(glbURL.path)")
            print(f"3DVIEWER_LOG: Output: \(outputPath.path)")
            print(f"3DVIEWER_LOG: Blender version: {bpy.app.version_string}")
            
            # Set temp directory to external drive to avoid cross-filesystem issues
            os.environ['TMPDIR'] = '\(blenderTempDir)'
            os.environ['TMP'] = '\(blenderTempDir)'
            os.environ['TEMP'] = '\(blenderTempDir)'
            print(f"3DVIEWER_LOG: Temp dir set to: {os.environ.get('TMPDIR')}")
            
            # Clear scene
            bpy.ops.object.select_all(action='SELECT')
            bpy.ops.object.delete()
            
            # Import GLB
            print("3DVIEWER_LOG: Importing GLB...")
            import_success = False
            try:
                result = bpy.ops.import_scene.gltf(filepath='\(glbURL.path)')
                print(f"3DVIEWER_LOG: Import result: {result}")
                import_success = True
                print("3DVIEWER_LOG: GLB import successful")
            except Exception as e:
                print(f"3DVIEWER_LOG_ERROR: Import failed: {e}")
                import_success = False
            
            if not import_success:
                print("3DVIEWER_LOG_ERROR: Cannot proceed without successful import")
                sys.exit(1)
            
            # List imported objects
            mesh_count = 0
            for obj in bpy.data.objects:
                if obj.type == 'MESH':
                    mesh_count += 1
                    print(f"3DVIEWER_LOG: Mesh: {obj.name}")
            print(f"3DVIEWER_LOG: Total meshes imported: {mesh_count}")
            
            if mesh_count == 0:
                print("3DVIEWER_LOG_ERROR: No meshes found in GLB!")
                sys.exit(1)
            
            # Export as USDZ
            print("3DVIEWER_LOG: Exporting to USDZ...")
            export_success = False
            try:
                # Note: export_textures parameter removed as it's deprecated in newer Blender
                result = bpy.ops.wm.usd_export(
                    filepath='\(outputPath.path)',
                    export_materials=True,
                    evaluation_mode='RENDER'
                )
                print(f"3DVIEWER_LOG: Export result: {result}")
                export_success = True
                print("3DVIEWER_LOG: USDZ export successful")
            except Exception as e:
                print(f"3DVIEWER_LOG_ERROR: Export failed: {e}")
                print(f"3DVIEWER_LOG_ERROR: Exception type: {type(e).__name__}")
                import traceback
                traceback.print_exc()
                export_success = False
            
            # Verify output file exists
            if os.path.exists('\(outputPath.path)'):
                file_size = os.path.getsize('\(outputPath.path)')
                print(f"3DVIEWER_LOG: Output file created, size: {file_size} bytes")
            else:
                print("3DVIEWER_LOG_ERROR: Output file was not created!")
                export_success = False
            
            if export_success:
                print('CONVERSION_COMPLETE_SUCCESS')
            else:
                print('CONVERSION_FAILED')
                sys.exit(1)
            """
            
            logger.log(.debug, "Launching Blender for conversion...")
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/Applications/Blender.app/Contents/MacOS/Blender")
            process.arguments = ["-b", "--factory-startup", "--python-expr", script]
            
            // Capture output for logging
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                // Read output
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let outputString = String(data: outputData, encoding: .utf8) ?? ""
                let errorString = String(data: errorData, encoding: .utf8) ?? ""
                
                // Log relevant output
                let relevantLines = outputString.components(separatedBy: "\n").filter { line in
                    line.contains("3DVIEWER_LOG") || line.contains("Error") || line.contains("CONVERSION")
                }
                if !relevantLines.isEmpty {
                    logger.log(.debug, "Blender output:", details: relevantLines.joined(separator: "\n"))
                }
                
                if !errorString.isEmpty && !errorString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    logger.log(.warning, "Blender stderr:", details: String(errorString.prefix(1500)))
                }
                
                logger.log(.info, "Blender process finished", details: "Exit code: \(process.terminationStatus)")
                
                if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: outputPath.path) {
                    await MainActor.run {
                        self.loadingMessage = "Loading scene..."
                    }
                    
                    logger.log(.info, "Loading USDZ into SceneKit...")
                    
                    // Load the USDZ into SceneKit
                    let loadedScene = try SCNScene(url: outputPath, options: [
                        .checkConsistency: true,
                        .convertToYUp: true
                    ])
                    
                    // Setup lighting
                    self.setupLighting(for: loadedScene)
                    
                    // Setup background
                    loadedScene.background.contents = NSColor(calibratedRed: 0.1, green: 0.12, blue: 0.15, alpha: 1.0)
                    
                    logger.log(.success, "3D model loaded successfully")
                    logger.endSession(success: true)
                    
                    await MainActor.run {
                        self.scene = loadedScene
                        self.usdzURL = outputPath
                        self.isLoading = false
                    }
                } else {
                    // Extract error details from output
                    let errorLines = outputString.components(separatedBy: "\n").filter { line in
                        line.contains("ERROR") || line.contains("Error") || line.contains("FAILED") || line.contains("failed")
                    }
                    let errorDetails = errorLines.isEmpty ? "Unknown error" : errorLines.joined(separator: "\n")
                    
                    logger.log(.error, "Blender conversion failed", details: "Exit: \(process.terminationStatus), Output exists: \(FileManager.default.fileExists(atPath: outputPath.path))")
                    logger.log(.error, "Error details:", details: errorDetails)
                    
                    // Log full output on failure
                    if !outputString.isEmpty {
                        logger.log(.debug, "Full Blender stdout:", details: String(outputString.suffix(3000)))
                    }
                    if !errorString.isEmpty {
                        logger.log(.debug, "Full Blender stderr:", details: String(errorString.suffix(2000)))
                    }
                    
                    logger.endSession(success: false)
                    
                    // Build a more helpful error message
                    var userError = "Blender conversion failed (exit code: \(process.terminationStatus))."
                    if !errorLines.isEmpty {
                        userError += "\n\nError: \(errorLines.first ?? "Unknown")"
                    }
                    userError += "\n\nClick 'View Log' for full details."
                    
                    await MainActor.run {
                        self.errorMessage = userError
                        self.isLoading = false
                    }
                }
            } catch {
                logger.log(.error, "Failed to run Blender", details: error.localizedDescription)
                logger.endSession(success: false)
                
                await MainActor.run {
                    self.errorMessage = "Failed to load model: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func setupLighting(for scene: SCNScene) {
        // Ambient light
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 400
        ambient.color = NSColor.white
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)
        
        // Key light
        let key = SCNLight()
        key.type = .directional
        key.intensity = 800
        key.castsShadow = true
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(x: -.pi/4, y: .pi/4, z: 0)
        scene.rootNode.addChildNode(keyNode)
        
        // Fill light
        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 400
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(x: -.pi/6, y: -.pi/4, z: 0)
        scene.rootNode.addChildNode(fillNode)
    }
    
    private func cleanup() {
        // Remove temporary USDZ file
        if let usdz = usdzURL {
            try? FileManager.default.removeItem(at: usdz)
        }
    }
    
    private func openInRealityConverter(_ url: URL) {
        let realityConverterURL = URL(fileURLWithPath: "/Applications/Reality Converter.app")
        if FileManager.default.fileExists(atPath: realityConverterURL.path) {
            NSWorkspace.shared.open([url], withApplicationAt: realityConverterURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func openInBlender(_ url: URL) {
        let blenderURL = URL(fileURLWithPath: "/Applications/Blender.app")
        if FileManager.default.fileExists(atPath: blenderURL.path) {
            NSWorkspace.shared.open([url], withApplicationAt: blenderURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Gallery Scene View Wrapper

struct GallerySceneView: NSViewRepresentable {
    let scene: SCNScene
    
    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = scene
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.backgroundColor = NSColor(calibratedRed: 0.1, green: 0.12, blue: 0.15, alpha: 1.0)
        scnView.showsStatistics = false
        
        // Configure camera control
        scnView.defaultCameraController.interactionMode = .orbitTurntable
        scnView.defaultCameraController.inertiaEnabled = true
        scnView.defaultCameraController.automaticTarget = true
        
        // Add default camera if none exists
        if scene.rootNode.childNodes.filter({ $0.camera != nil }).isEmpty {
            let camera = SCNCamera()
            camera.automaticallyAdjustsZRange = true
            camera.fieldOfView = 45
            
            let cameraNode = SCNNode()
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(x: 2, y: 1.5, z: 3)
            cameraNode.look(at: SCNVector3(x: 0, y: 0.5, z: 0))
            
            scene.rootNode.addChildNode(cameraNode)
        }
        
        return scnView
    }
    
    func updateNSView(_ nsView: SCNView, context: Context) {
        nsView.scene = scene
    }
}

// MARK: - Preview

#Preview {
    CabinetDetailSheet(
        cabinet: DiscoveredCabinet(
            id: "galaga",
            name: "galaga",
            displayName: "Galaga",
            sourcePath: URL(fileURLWithPath: "/test/galaga"),
            sourceType: .folder
        ),
        templates: [],
        templateManager: TemplateManager(),
        onTemplateChange: { _ in },
        onClose: {}
    )
}
