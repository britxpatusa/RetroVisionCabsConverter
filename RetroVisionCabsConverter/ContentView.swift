import SwiftUI
import AppKit

enum AppSetupState {
    case checkingDependencies
    case dependenciesMissing
    case folderSetup
    case ready
}

struct ContentView: View {
    @StateObject private var runner = ProcessRunner()
    @StateObject private var dependencyManager = DependencyManager()
    @StateObject private var detailManager = CabinetDetailManager()
    @StateObject private var overrideManager = MediaOverrideManager()
    @State private var paths = RetroVisionPaths.load()
    @State private var cabinets: [CabinetItem] = []
    @State private var selected: Set<CabinetItem> = []
    @State private var selectedCabinet: CabinetItem?
    @State private var showSettings = false
    @State private var showMediaInspector = false
    @State private var validationErrors: [String] = []
    @State private var setupState: AppSetupState = .checkingDependencies
    @State private var showValidationResults = false
    @State private var filterStatus: FilterStatus = .all
    @State private var showBuildView = false
    @State private var showGalleryView = false
    @State private var showPropsGallery = false
    @State private var availableTemplates: [CabinetTemplate] = []
    @State private var selectedTemplate: CabinetTemplate?
    @State private var isScanning = false
    @State private var showTemplateAssignment = false
    @StateObject private var templateManager = TemplateManager()
    @StateObject private var templateAssignments = TemplateAssignmentManager()

    private let scanner = CabinetScanner()
    
    enum FilterStatus: String, CaseIterable {
        case all = "All"
        case ready = "Ready"
        case warnings = "Warnings"
        case errors = "Errors"
    }

    var body: some View {
        Group {
            switch setupState {
            case .checkingDependencies:
                // Show dependency check view
                SetupView(dependencyManager: dependencyManager) {
                    // Dependencies passed, check if folders are configured
                    if paths.isConfigured {
                        setupState = .ready
                        loadTemplates()  // Load templates only, no auto-scan
                    } else {
                        setupState = .folderSetup
                    }
                }
                
            case .dependenciesMissing:
                // Show dependency check view (same as checking)
                SetupView(dependencyManager: dependencyManager) {
                    if paths.isConfigured {
                        setupState = .ready
                        loadTemplates()  // Load templates only, no auto-scan
                    } else {
                        setupState = .folderSetup
                    }
                }
                
            case .folderSetup:
                // Show folder setup view
                FolderSetupView(paths: $paths) {
                    setupState = .ready
                    loadTemplates()  // Load templates only, no auto-scan
                }
                
            case .ready:
                mainContent
            }
        }
        .onAppear {
            // Start by checking dependencies
            setupState = .checkingDependencies
            Task {
                await dependencyManager.checkAll()
                // SetupView will handle the flow from here
            }
        }
    }
    
    // MARK: - Main Content
    
    private var mainContent: some View {
        VStack(spacing: 12) {
            // Toolbar
            toolbarView
            
            // Paths configuration
            GroupBox("Paths") {
                VStack(spacing: 10) {
                    FolderPickerField(title: "Age Cabinets Root", path: $paths.ageCabinetsRoot)
                        .onChange(of: paths.ageCabinetsRoot) { _, _ in paths.save() }
                    
                    FolderPickerField(title: "3D Models Workspace", path: $paths.workspaceRoot)
                        .onChange(of: paths.workspaceRoot) { _, _ in paths.save() }

                    HStack(spacing: 12) {
                        Button {
                            scanCabinetsAsync()
                        } label: {
                            if isScanning {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Scanning...")
                                }
                            } else {
                                Text("Scan Cabinets")
                            }
                        }
                        .disabled(isScanning)
                        
                        Button("Assign Templates") {
                            showTemplateAssignment = true
                        }
                        .disabled(cabinets.isEmpty || availableTemplates.isEmpty)

                        Spacer()

                        Button("Open Output Folder") { openInFinder(paths.outputUSDZ) }
                        Button("Open Work Folder") { openInFinder(paths.workRetroVision) }
                    }
                }
                .padding(8)
            }

            HSplitView {
                // Left: Cabinets list
                cabinetListPanel
                    .frame(minWidth: 280, maxWidth: 400)
                
                // Center: Detail view
                detailPanel
                    .frame(minWidth: 350)
                
                // Right: Run panel + Log
                VStack(spacing: 12) {
                    runPanel
                    logPanel
                }
                .frame(minWidth: 380)
            }
        }
        .padding(12)
        .frame(minWidth: 1200, minHeight: 780)
        .sheet(isPresented: $showSettings) {
            SettingsView(
                dependencyManager: dependencyManager,
                paths: $paths,
                runner: runner,
                onDependencyIssue: {
                    setupState = .dependenciesMissing
                }
            )
        }
        .sheet(isPresented: $showMediaInspector) {
            if let cabinet = selectedCabinet {
                mediaInspectorSheet(for: cabinet)
            }
        }
        .sheet(isPresented: $showTemplateAssignment) {
            TemplateAssignmentView(
                assignmentManager: templateAssignments,
                cabinets: cabinets,
                templates: availableTemplates,
                isPresented: $showTemplateAssignment
            )
        }
        .alert("Validation Issues", isPresented: $runner.showValidationAlert) {
            Button("Fix Issues") {
                runner.showValidationAlert = false
            }
            Button("Convert Anyway", role: .destructive) {
                runner.showValidationAlert = false
                runner.runConvertAll(paths: paths)
            }
        } message: {
            Text("Some cabinets have missing textures or configuration errors. Would you like to fix them first or proceed anyway?")
        }
    }
    
    // MARK: - Cabinet List Panel
    
    private var cabinetListPanel: some View {
        GroupBox("Cabinets") {
            VStack(spacing: 8) {
                // Header with filter
                HStack {
                    Text("Found: \(cabinets.count)")
                        .font(.caption)
                    
                    Spacer()
                    
                    Picker("Filter", selection: $filterStatus) {
                        ForEach(FilterStatus.allCases, id: \.self) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }

                // Cabinet list
                List(filteredCabinets, selection: $selected) { item in
                    HStack {
                        CabinetListRow(
                            item: item,
                            detail: detailFor(item),
                            isSelected: selectedCabinet?.id == item.id
                        )
                        
                        // Template assignment indicator
                        CabinetTemplateIndicator(
                            cabinetID: item.id,
                            templates: availableTemplates,
                            assignmentManager: templateAssignments
                        )
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedCabinet = item
                    }
                }
                .listStyle(.inset)
                
                // Selection info
                HStack {
                    if !selected.isEmpty {
                        Text("\(selected.count) selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Select All") {
                        selected = Set(filteredCabinets)
                    }
                    .font(.caption)
                    .disabled(filteredCabinets.isEmpty)
                    
                    Button("Deselect") {
                        selected.removeAll()
                    }
                    .font(.caption)
                    .disabled(selected.isEmpty)
                }
            }
            .padding(8)
        }
    }
    
    /// Get the effective path for a cabinet item (handles ZIP extraction)
    private func effectivePath(for item: CabinetItem) -> String {
        return detailManager.getEffectivePath(for: item)
    }
    
    /// Get the detail for a cabinet item
    private func detailFor(_ item: CabinetItem) -> CabinetDetail? {
        return detailManager.details[effectivePath(for: item)]
    }
    
    private var filteredCabinets: [CabinetItem] {
        switch filterStatus {
        case .all:
            return cabinets
        case .ready:
            return cabinets.filter { item in
                guard let detail = detailFor(item) else { return item.hasDescriptionYAML }
                return detail.overallStatus.isValid
            }
        case .warnings:
            return cabinets.filter { item in
                guard let detail = detailFor(item) else { return false }
                return detail.overallStatus.isWarning
            }
        case .errors:
            return cabinets.filter { item in
                guard let detail = detailFor(item) else { return !item.hasDescriptionYAML }
                return detail.overallStatus.isError
            }
        }
    }
    
    // MARK: - Detail Panel
    
    private var detailPanel: some View {
        GroupBox("Details") {
            if let cabinet = selectedCabinet {
                let cabPath = effectivePath(for: cabinet)
                let detail = detailManager.loadDetail(for: cabPath)
                CabinetDetailView(
                    detail: detail,
                    showMediaInspector: $showMediaInspector,
                    onApplySuggestion: { partName, suggestedFile in
                        overrideManager.setOverride(
                            cabinetPath: cabPath,
                            partName: partName,
                            newArtFile: suggestedFile
                        )
                        overrideManager.save()
                        // Refresh the detail
                        _ = detailManager.refresh(path: cabPath)
                    }
                )
            } else {
                VStack {
                    Image(systemName: "archivebox")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    
                    Text("Select a cabinet to view details")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    Text("Click on a cabinet in the list to see its parts, textures, and validation status.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Run Panel
    
    private var runPanel: some View {
        GroupBox("Run") {
            VStack(alignment: .leading, spacing: 10) {
                // Status info
                HStack {
                    Text("Status:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    if FileManager.default.fileExists(atPath: paths.converterScript) {
                        Label("Ready", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Ready", systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                
                // Validation summary
                if let summary = runner.validationSummary {
                    HStack(spacing: 12) {
                        Label("\(summary.readyCount)", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                        Label("\(summary.warningCount)", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.yellow)
                        Label("\(summary.errorCount)", systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                    }
                    .font(.caption)
                }

                Divider()
                
                // Template assignment summary
                if !cabinets.isEmpty {
                    HStack {
                        let assigned = cabinets.filter { templateAssignments.hasAssignment(for: $0.id) }.count
                        let total = cabinets.count
                        
                        Image(systemName: assigned == total ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(assigned == total ? .green : .orange)
                        
                        Text("\(assigned)/\(total) templates assigned")
                            .font(.caption)
                        
                        Spacer()
                        
                        Button("Assign All") {
                            showTemplateAssignment = true
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                }

                Divider()
                
                // Action buttons
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Button("Validate") {
                            runner.runValidation(Array(selected.isEmpty ? cabinets : Array(selected)), detailManager: detailManager)
                        }
                        .disabled(runner.isRunning || cabinets.isEmpty)
                        
                        Button(runner.isRunning ? "Running..." : "Convert") {
                            validationErrors = paths.validatePaths()
                            if validationErrors.isEmpty {
                                let items = selected.isEmpty ? cabinets : Array(selected)
                                // Build template map for selected items
                                var templateMap: [String: String] = [:]
                                for item in items {
                                    if let templateID = templateAssignments.templateID(for: item.id),
                                       let template = availableTemplates.first(where: { $0.id == templateID }),
                                       let modelPath = template.modelPath {
                                        templateMap[item.id] = modelPath
                                    }
                                }
                                runner.runConvertWithValidation(
                                    paths: paths,
                                    items: items,
                                    detailManager: detailManager,
                                    templateMap: templateMap
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(runner.isRunning || cabinets.isEmpty)
                    }
                    
                    HStack(spacing: 10) {
                        Button("Stop") { runner.stop() }
                            .disabled(!runner.isRunning)

                        Button("Clear Log") { runner.clearLog() }
                            .disabled(runner.isRunning)
                        
                        Spacer()
                    }
                }
                
                // Validation errors
                if !validationErrors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(validationErrors, id: \.self) { error in
                            Text("• \(error)")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.top, 4)
                }

                if let code = runner.lastExitCode {
                    Text("Exit code: \(code)")
                        .font(.caption)
                        .foregroundStyle(code == 0 ? .green : .red)
                }
            }
            .padding(8)
        }
    }
    
    // MARK: - Log Panel
    
    private var logPanel: some View {
        GroupBox("Log") {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(runner.log.isEmpty ? "Logs will appear here..." : runner.log)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .textSelection(.enabled)
                        .id("logBottom")
                }
                .onChange(of: runner.log) { _, _ in
                    withAnimation {
                        proxy.scrollTo("logBottom", anchor: .bottom)
                    }
                }
            }
        }
        .frame(minHeight: 180)
    }
    
    // MARK: - Media Inspector Sheet
    
    private func mediaInspectorSheet(for cabinet: CabinetItem) -> some View {
        let cabPath = effectivePath(for: cabinet)
        var detail = detailManager.loadDetail(for: cabPath)
        overrideManager.applyOverrides(to: &detail)
        
        return MediaInspectorView(
            detail: .init(
                get: { detail },
                set: { newDetail in
                    // Update in detail manager
                    detailManager.details[cabPath] = newDetail
                }
            ),
            isPresented: $showMediaInspector,
            overrideManager: overrideManager,
            onSave: {
                // Refresh the detail
                _ = detailManager.refresh(path: cabPath)
            }
        )
    }
    
    // MARK: - Helpers
    
    private func scanCabinetsAsync() {
        guard !isScanning else { return }
        
        // Capture values needed for background work
        let rootPath = paths.ageCabinetsRoot
        let scannerRef = scanner
        
        isScanning = true
        selected = []
        selectedCabinet = nil
        cabinets = []
        detailManager.clearCache()
        
        Task {
            // Load templates first (quick operation)
            templateManager.loadTemplates()
            availableTemplates = templateManager.templates
            if selectedTemplate == nil, let first = availableTemplates.first {
                selectedTemplate = first
            }
            
            // Run scan on background thread
            let scannedCabinets = await Task.detached(priority: .userInitiated) {
                scannerRef.scan(ageCabinetsRoot: rootPath)
            }.value
            
            // Update UI
            cabinets = scannedCabinets
            isScanning = false
            
            // Don't pre-load details - load on demand when selected
        }
    }
    
    private func scanCabinets() {
        scanCabinetsAsync()
    }
    
    private func loadTemplates() {
        Task {
            templateManager.loadTemplates()
            availableTemplates = templateManager.templates
            if selectedTemplate == nil, let first = availableTemplates.first {
                selectedTemplate = first
            }
        }
    }
    
    /// Convert cabinets selected from the Gallery view
    private func convertFromGallery(cabinets: [DiscoveredCabinet], templateMap: [String: String]) {
        guard !cabinets.isEmpty else { return }
        
        // Build list of source paths
        var sourcePaths: [String] = []
        var galleryCabinetMap: [String: String] = [:]  // cabinetID -> templatePath
        
        for cabinet in cabinets {
            sourcePaths.append(cabinet.sourcePath.path)
            if let templatePath = templateMap[cabinet.id] {
                galleryCabinetMap[cabinet.id] = templatePath
            }
        }
        
        runner.log = "Starting Gallery conversion of \(cabinets.count) cabinet(s)...\n"
        
        Task {
            do {
                // Save template map for the conversion script
                let templateMapPath = (paths.workRetroVision as NSString).appendingPathComponent("gallery_template_map.json")
                let mapData = try JSONEncoder().encode(galleryCabinetMap)
                try mapData.write(to: URL(fileURLWithPath: templateMapPath))
                
                // Run conversion with the gallery sources
                try await runner.runGalleryConversion(
                    sources: sourcePaths,
                    templateMapPath: templateMapPath,
                    paths: paths
                )
                
                runner.log += "\n✅ Gallery conversion complete!"
            } catch {
                runner.log += "\n❌ Conversion failed: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Toolbar
    
    private var toolbarView: some View {
        HStack {
            Text("RetroVision Cabs Converter")
                .font(.headline)
            
            Spacer()
            
            // Cabinet Gallery button
            Button {
                showGalleryView = true
            } label: {
                Label("Cabinets", systemImage: "arcade.stick.console")
            }
            .help("Browse and convert Age of Joy cabinet packs")
            
            // Props Gallery button
            Button {
                showPropsGallery = true
            } label: {
                Label("Props", systemImage: "cube.transparent")
            }
            .help("Browse and convert non-cabinet props (decorations, cutouts, stages)")
            
            // Build New Cabinet button
            Button {
                showBuildView = true
            } label: {
                Label("Build New", systemImage: "plus.square.on.square")
            }
            .help("Build a new cabinet from a template")
            
            Divider()
                .frame(height: 20)
            
            // Dependency status indicators
            HStack(spacing: 16) {
                dependencyIndicator(name: "Blender", status: dependencyManager.blender.status)
                dependencyIndicator(name: "Python", status: dependencyManager.pythonVenv.status)
            }
            
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
        }
        .padding(.horizontal, 4)
        .sheet(isPresented: $showBuildView) {
            BuildView(paths: paths) { newCabinetFolder in
                // Refresh cabinet list after building
                scanCabinets()
            }
        }
        .sheet(isPresented: $showGalleryView) {
            CabinetGalleryView(
                templateManager: templateManager,
                templates: availableTemplates,
                onConvert: { selectedCabinets, templateMap in
                    showGalleryView = false
                    convertFromGallery(cabinets: selectedCabinets, templateMap: templateMap)
                },
                onClose: { showGalleryView = false }
            )
            .frame(minWidth: 850, idealWidth: 1100, maxWidth: 1400, minHeight: 650, idealHeight: 800, maxHeight: 1000)
        }
        .sheet(isPresented: $showPropsGallery) {
            PropsGalleryView(
                onClose: { showPropsGallery = false },
                onConvert: { selectedProps in
                    showPropsGallery = false
                    convertProps(selectedProps)
                }
            )
            .frame(minWidth: 850, idealWidth: 1100, maxWidth: 1400, minHeight: 650, idealHeight: 800, maxHeight: 1000)
        }
    }
    
    // MARK: - Props Conversion
    
    private func convertProps(_ props: [DiscoveredProp]) {
        guard !props.isEmpty else { return }
        
        // Create output folder for props
        let propsOutputFolder = URL(fileURLWithPath: paths.workspaceRoot).appendingPathComponent("Output/Props")
        try? FileManager.default.createDirectory(at: propsOutputFolder, withIntermediateDirectories: true)
        
        Task {
            await MainActor.run {
                self.runner.isRunning = true
                self.runner.log = "Converting \(props.count) prop(s)...\n"
            }
            
            let converter = PropsConverter.shared
            let results = await converter.convertProps(props, outputFolder: propsOutputFolder) { progress, message in
                Task { @MainActor in
                    self.runner.log += "\(message)\n"
                }
            }
            
            let successCount = results.filter { $0.success }.count
            let failCount = results.count - successCount
            
            await MainActor.run {
                self.runner.isRunning = false
                self.runner.log += "\n=== Conversion Complete ===\n"
                self.runner.log += "Successful: \(successCount)\n"
                self.runner.log += "Failed: \(failCount)\n"
                self.runner.log += "Output folder: \(propsOutputFolder.path)\n"
                
                // List converted files
                for result in results where result.success {
                    self.runner.log += "\n✓ \(result.propName)\n"
                    if let usdz = result.usdzPath {
                        self.runner.log += "  USDZ: \(usdz.lastPathComponent)\n"
                    }
                    if let video = result.videoPath {
                        self.runner.log += "  Video: \(video.lastPathComponent)\n"
                    }
                }
                
                for result in results where !result.success {
                    self.runner.log += "\n✗ \(result.propName): \(result.error ?? "Unknown error")\n"
                }
            }
        }
    }
    
    private func dependencyIndicator(name: String, status: DependencyStatus) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func openInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var dependencyManager: DependencyManager
    @Binding var paths: RetroVisionPaths
    @ObservedObject var runner: ProcessRunner
    var onDependencyIssue: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Dependencies section
                    GroupBox("Dependencies") {
                        VStack(alignment: .leading, spacing: 12) {
                            dependencyRow(info: dependencyManager.blender)
                            Divider()
                            dependencyRow(info: dependencyManager.python3)
                            Divider()
                            dependencyRow(info: dependencyManager.pythonVenv)
                            
                            HStack {
                                Button("Refresh Status") {
                                    Task {
                                        await dependencyManager.checkAll()
                                        if !dependencyManager.allDependenciesReady {
                                            dismiss()
                                            onDependencyIssue()
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                Button("Check Tools") {
                                    runner.runCheckTools(paths: paths)
                                }
                            }
                            .padding(.top, 8)
                        }
                        .padding(8)
                    }
                    
                    // Blender path
                    GroupBox("Blender Path") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Blender Path", text: $paths.blenderPath)
                                .textFieldStyle(.roundedBorder)
                            
                            Text("Default: /Applications/Blender.app/Contents/MacOS/Blender")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }
                    
                    // System info
                    GroupBox("System") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Converter Scripts")
                                Spacer()
                                if FileManager.default.fileExists(atPath: paths.converterScript) {
                                    Label("Ready", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Label("Missing", systemImage: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                            HStack {
                                Text("Python Environment")
                                Spacer()
                                let venvExists = FileManager.default.fileExists(atPath: "\(paths.venvPath)/bin/python")
                                if venvExists {
                                    Label("Configured", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Label("Not Set Up", systemImage: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                        .padding(8)
                    }
                    
                    // About & Legal
                    GroupBox("About") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("RetroVision Cabs Converter")
                                    .fontWeight(.medium)
                                Spacer()
                                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.0")")
                                    .foregroundStyle(.secondary)
                            }
                            
                            Divider()
                            
                            HStack {
                                Button {
                                    showPrivacyPolicy = true
                                } label: {
                                    Label("Privacy Policy", systemImage: "hand.raised.fill")
                                }
                                
                                Spacer()
                                
                                Link(destination: URL(string: "https://github.com/britx/RetroVisionCabsConverter")!) {
                                    Label("View on GitHub", systemImage: "link")
                                }
                            }
                            
                            Text("© 2024-2026 BritX. All rights reserved.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }
                    
                    // Log output
                    if !runner.log.isEmpty {
                        GroupBox("Output") {
                            ScrollView {
                                Text(runner.log)
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(height: 150)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 500, idealWidth: 650, maxWidth: 750, minHeight: 450, idealHeight: 580, maxHeight: 700)
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView()
        }
    }
    
    @State private var showPrivacyPolicy = false
    
    private func dependencyRow(info: DependencyInfo) -> some View {
        HStack {
            Circle()
                .fill(info.status.color)
                .frame(width: 10, height: 10)
            
            VStack(alignment: .leading) {
                Text(info.name)
                    .fontWeight(.medium)
                Text(info.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(info.status.displayText)
                .font(.caption)
                .foregroundStyle(info.status.color)
        }
    }
    
    private func infoRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}

// MARK: - Cabinet List Row

struct CabinetListRow: View {
    let item: CabinetItem
    let detail: CabinetDetail?
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            // ZIP file indicator
            if item.isZipFile {
                Image(systemName: "doc.zipper")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.id)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .medium : .regular)
                    
                    if item.isZipFile {
                        Text("ZIP")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.2))
                            .foregroundStyle(.blue)
                            .cornerRadius(3)
                    }
                }
                
                HStack(spacing: 8) {
                    if let detail = detail {
                        Text(detail.statusSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        if detail.parts.count > 0 {
                            Text("\(detail.parts.count) parts")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else if !item.hasDescriptionYAML {
                        Text("No description.yaml")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }
            
            Spacer()
            
            // Warning/error count badges
            if let detail = detail {
                if detail.errorCount > 0 {
                    Text("\(detail.errorCount)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.2))
                        .foregroundStyle(.red)
                        .cornerRadius(4)
                }
                
                if detail.warningCount > 0 {
                    Text("\(detail.warningCount)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.2))
                        .foregroundStyle(.orange)
                        .cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }
    
    private var statusColor: Color {
        if let detail = detail {
            return detail.overallStatus.color
        }
        return item.hasDescriptionYAML ? .green : .red
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
