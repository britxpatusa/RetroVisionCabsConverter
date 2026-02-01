import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Cabinet Gallery View

/// Main view for browsing and selecting Age of Joy cabinets
struct CabinetGalleryView: View {
    @StateObject private var state = CabinetGalleryState()
    @StateObject private var storage = GalleryStorage.shared
    @ObservedObject var templateManager: TemplateManager
    
    @State private var showBackupExporter = false
    @State private var showBackupImporter = false
    @State private var selectedCabinet: DiscoveredCabinet?
    @State private var showSaveConfirmation = false
    @State private var showClearConfirmation = false
    @State private var sourceFolder: URL?
    @State private var saveResult: String?
    @State private var showingStorageMenu = false
    
    let templates: [CabinetTemplate]
    let onConvert: ([DiscoveredCabinet], [String: String]) -> Void
    var onClose: (() -> Void)?  // Back button callback
    
    var body: some View {
        VStack(spacing: 0) {
            // Header toolbar
            headerToolbar
            
            Divider()
            
            // Main content
            if state.cabinets.isEmpty && !state.isScanning && !storage.isLoading {
                emptyState
            } else if state.isScanning || storage.isLoading {
                scanningState
            } else {
                galleryContent
            }
            
            Divider()
            
            // Footer with actions
            footerBar
        }
        .sheet(item: $selectedCabinet) { cabinet in
            CabinetDetailSheet(
                cabinet: cabinet,
                templates: templates,
                templateManager: templateManager,
                onTemplateChange: { newTemplateID in
                    updateCabinetTemplate(cabinet.id, templateID: newTemplateID)
                },
                onClose: { selectedCabinet = nil }
            )
        }
        .fileExporter(
            isPresented: $showBackupExporter,
            document: GalleryBackupDocument(),
            contentType: .zip,
            defaultFilename: "GalleryBackup_\(dateString()).zip"
        ) { result in
            if case .success(let url) = result {
                Task {
                    await createBackup(to: url)
                }
            }
        }
        .fileImporter(
            isPresented: $showBackupImporter,
            allowedContentTypes: [.zip],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task {
                    await restoreBackup(from: url)
                }
            }
        }
        .alert("Save to Gallery", isPresented: $showSaveConfirmation) {
            Button("Save") {
                Task { await saveToGallery() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let duplicates = storage.countDuplicates(in: state.cabinets)
            let newCount = state.cabinets.count - duplicates
            Text("Save \(newCount) new cabinet(s) to your gallery?\n\(duplicates) duplicate(s) will be skipped.")
        }
        .alert("Clear Gallery", isPresented: $showClearConfirmation) {
            Button("Clear All", role: .destructive) {
                try? storage.clearAllSavedCabinets()
                state.cabinets = []
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove all \(storage.savedCabinets.count) saved cabinet(s) from the gallery? This cannot be undone.")
        }
        .onAppear {
            loadSavedCabinets()
        }
    }
    
    // MARK: - Header Toolbar
    
    private var headerToolbar: some View {
        HStack(spacing: 12) {
            // Back button
            if let onClose = onClose {
                Button {
                    onClose()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                
                Divider()
                    .frame(height: 20)
            }
            
            // Title
            Label("Cabinet Gallery", systemImage: "square.grid.3x3")
                .font(.headline)
            
            // Storage info badge
            if !storage.savedCabinets.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "externaldrive.fill")
                        .font(.caption)
                    Text("\(storage.savedCabinets.count) saved")
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.15))
                .foregroundStyle(.blue)
                .cornerRadius(10)
            }
            
            Spacer()
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search cabinets...", text: $state.filterText)
                    .textFieldStyle(.plain)
                    .frame(width: 150)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
            
            // Filter options
            Toggle("Show Incomplete", isOn: $state.showIncomplete)
                .toggleStyle(.checkbox)
            
            // Sort
            Picker("Sort", selection: $state.sortOrder) {
                ForEach(CabinetGalleryState.SortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .frame(width: 130)
            
            Divider()
                .frame(height: 20)
            
            // Storage menu
            Menu {
                Button {
                    showSaveConfirmation = true
                } label: {
                    Label("Save to Gallery", systemImage: "square.and.arrow.down")
                }
                .disabled(state.cabinets.isEmpty)
                
                Divider()
                
                Button {
                    showBackupExporter = true
                } label: {
                    Label("Export Backup...", systemImage: "arrow.up.doc")
                }
                .disabled(storage.savedCabinets.isEmpty)
                
                Button {
                    showBackupImporter = true
                } label: {
                    Label("Import Backup...", systemImage: "arrow.down.doc")
                }
                
                Divider()
                
                Button(role: .destructive) {
                    showClearConfirmation = true
                } label: {
                    Label("Clear Gallery", systemImage: "trash")
                }
                .disabled(storage.savedCabinets.isEmpty)
                
            } label: {
                Label("Storage", systemImage: "externaldrive")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 100)
            
            // Scan button
            Button {
                openFolderPicker()
            } label: {
                Label("Scan Folder", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "arcade.stick.console")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("No Cabinets Loaded")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Scan a folder containing Age of Joy cabinet packs,\nor import a backup to see them here.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            
            HStack(spacing: 16) {
                Button {
                    openFolderPicker()
                } label: {
                    Label("Scan Folder", systemImage: "folder")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                
                Button {
                    showBackupImporter = true
                } label: {
                    Label("Import Backup", systemImage: "arrow.down.doc")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Scanning State
    
    private var scanningState: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text(state.currentOperation)
                .font(.headline)
            
            ProgressView(value: state.scanProgress)
                .frame(width: 300)
            
            Text("\(Int(state.scanProgress * 100))% complete")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Gallery Content
    
    private var galleryContent: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 20)
            ], spacing: 20) {
                ForEach(state.filteredCabinets) { cabinet in
                    CabinetGalleryCard(
                        cabinet: cabinet,
                        isSelected: state.selectedCabinets.contains(cabinet.id),
                        isSaved: storage.isDuplicate(cabinet),
                        onSelect: { state.toggleSelection(cabinet.id) },
                        onDetail: {
                            selectedCabinet = cabinet
                        }
                    )
                }
            }
            .padding()
        }
    }
    
    // MARK: - Footer Bar
    
    private var footerBar: some View {
        HStack(spacing: 16) {
            // Stats
            if !state.cabinets.isEmpty {
                Text("\(state.cabinets.count) cabinets")
                    .foregroundStyle(.secondary)
                
                if storage.countDuplicates(in: state.cabinets) > 0 {
                    Text("•")
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("\(storage.countDuplicates(in: state.cabinets)) saved")
                    }
                    .font(.caption)
                }
                
                Text("•")
                    .foregroundStyle(.secondary)
                
                Text("\(state.completeCount) complete")
                    .foregroundStyle(.green)
            }
            
            // Storage size
            if !storage.savedCabinets.isEmpty {
                Text("•")
                    .foregroundStyle(.secondary)
                Text("Storage: \(storage.storageSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Selection buttons
            if !state.cabinets.isEmpty {
                Button("Select All") {
                    state.selectAll()
                }
                
                Button("Select New") {
                    selectUnsaved()
                }
                
                if !state.selectedCabinets.isEmpty {
                    Button("Clear Selection") {
                        state.clearSelection()
                    }
                }
            }
            
            // Save button (quick access)
            if !state.cabinets.isEmpty {
                let newCount = state.cabinets.count - storage.countDuplicates(in: state.cabinets)
                Button {
                    showSaveConfirmation = true
                } label: {
                    Label("Save \(newCount) New", systemImage: "square.and.arrow.down")
                }
                .disabled(newCount == 0)
            }
            
            // Convert button
            Button {
                convertSelected()
            } label: {
                Label("Convert \(state.selectedCount) Selected", systemImage: "arrow.right.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.selectedCabinets.isEmpty)
        }
        .padding()
    }
    
    // MARK: - Actions
    
    /// Open folder picker using NSOpenPanel
    private func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.title = "Select Cabinet Folder"
        panel.message = "Choose a folder containing Age of Joy cabinet packs"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        
        if panel.runModal() == .OK, let url = panel.url {
            sourceFolder = url
            Task {
                await scanFolder(url)
            }
        }
    }
    
    private func loadSavedCabinets() {
        storage.loadSavedCabinets()
        if !storage.savedCabinets.isEmpty {
            state.cabinets = storage.toDiscoveredCabinets()
            state.currentOperation = "Loaded \(storage.savedCabinets.count) saved cabinet(s)"
        }
    }
    
    private func scanFolder(_ url: URL) async {
        // Start accessing security-scoped resource
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        await MainActor.run {
            state.isScanning = true
            state.selectedCabinets = []
            state.scanProgress = 0
            state.currentOperation = "Starting scan..."
        }
        
        do {
            let analyzer = CabinetAnalyzer.shared
            let discovered = try await analyzer.scanFolder(url) { progress, message in
                Task { @MainActor in
                    state.scanProgress = progress
                    state.currentOperation = message
                }
            }
            
            await MainActor.run {
                // Merge with existing saved cabinets
                var allCabinets = storage.toDiscoveredCabinets()
                for newCab in discovered {
                    if !allCabinets.contains(where: { $0.id == newCab.id }) {
                        allCabinets.append(newCab)
                    }
                }
                state.cabinets = allCabinets
                state.isScanning = false
                state.currentOperation = "Found \(discovered.count) cabinet(s)"
            }
            
            // Generate previews for new cabinets
            await generatePreviews()
            
        } catch {
            await MainActor.run {
                state.isScanning = false
                state.errorMessage = error.localizedDescription
                state.currentOperation = "Scan failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func generatePreviews() async {
        await MainActor.run {
            state.isGeneratingPreviews = true
        }
        
        var templateURLs: [String: URL] = [:]
        for template in templates {
            if let modelPath = template.modelPath {
                templateURLs[template.id] = URL(fileURLWithPath: modelPath)
            }
        }
        
        let generator = PreviewGenerator.shared
        
        for i in state.cabinets.indices {
            let cabinet = state.cabinets[i]
            
            // Skip if already has preview
            if cabinet.previewImage != nil { continue }
            
            if let templateURL = templateURLs[cabinet.suggestedTemplateID] {
                if let preview = await generator.generatePreview(for: cabinet, templateGLB: templateURL) {
                    await MainActor.run {
                        if i < state.cabinets.count {
                            state.cabinets[i].previewImage = preview
                            state.cabinets[i].previewGenerated = true
                        }
                    }
                }
            }
            
            await MainActor.run {
                state.previewProgress = Double(i + 1) / Double(state.cabinets.count)
            }
        }
        
        await MainActor.run {
            state.isGeneratingPreviews = false
        }
    }
    
    private func saveToGallery() async {
        let cabinetsToSave = state.cabinets.filter { !storage.isDuplicate($0) }
        
        let savedCount = await storage.saveCabinets(cabinetsToSave) { progress, message in
            Task { @MainActor in
                state.scanProgress = progress
                state.currentOperation = message
            }
        }
        
        await MainActor.run {
            saveResult = "Saved \(savedCount) cabinet(s) to gallery"
            // Refresh view to show saved status
            state.cabinets = state.cabinets // Trigger refresh
        }
    }
    
    private func createBackup(to url: URL) async {
        await MainActor.run {
            state.isScanning = true
            state.currentOperation = "Creating backup..."
        }
        
        do {
            try await storage.createBackup(to: url) { progress, message in
                Task { @MainActor in
                    state.scanProgress = progress
                    state.currentOperation = message
                }
            }
        } catch {
            await MainActor.run {
                state.errorMessage = error.localizedDescription
            }
        }
        
        await MainActor.run {
            state.isScanning = false
        }
    }
    
    private func restoreBackup(from url: URL) async {
        await MainActor.run {
            state.isScanning = true
        }
        
        do {
            let importedCount = try await storage.restoreBackup(from: url) { progress, message in
                Task { @MainActor in
                    state.scanProgress = progress
                    state.currentOperation = message
                }
            }
            
            await MainActor.run {
                state.cabinets = storage.toDiscoveredCabinets()
                state.currentOperation = "Imported \(importedCount) cabinet(s)"
            }
        } catch {
            await MainActor.run {
                state.errorMessage = error.localizedDescription
            }
        }
        
        await MainActor.run {
            state.isScanning = false
        }
    }
    
    private func selectUnsaved() {
        let unsavedIDs = state.filteredCabinets
            .filter { !storage.isDuplicate($0) }
            .map { $0.id }
        state.selectedCabinets = Set(unsavedIDs)
    }
    
    private func updateCabinetTemplate(_ cabinetID: String, templateID: String) {
        if let index = state.cabinets.firstIndex(where: { $0.id == cabinetID }) {
            state.cabinets[index].suggestedTemplateID = templateID
            state.cabinets[index].previewGenerated = false
            
            Task {
                var templateURLs: [String: URL] = [:]
                for template in templates {
                    if let modelPath = template.modelPath {
                        templateURLs[template.id] = URL(fileURLWithPath: modelPath)
                    }
                }
                
                if let templateURL = templateURLs[templateID] {
                    let preview = await PreviewGenerator.shared.generatePreview(
                        for: state.cabinets[index],
                        templateGLB: templateURL
                    )
                    await MainActor.run {
                        state.cabinets[index].previewImage = preview
                        state.cabinets[index].previewGenerated = true
                    }
                }
            }
        }
    }
    
    private func convertSelected() {
        let selectedCabs = state.cabinets.filter { state.selectedCabinets.contains($0.id) }
        var templateMap: [String: String] = [:]
        
        for cab in selectedCabs {
            if let template = templates.first(where: { $0.id == cab.suggestedTemplateID }),
               let modelPath = template.modelPath {
                templateMap[cab.id] = modelPath
            }
        }
        
        onConvert(selectedCabs, templateMap)
    }
    
    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

// MARK: - Backup Document

struct GalleryBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }
    
    init() {}
    
    init(configuration: ReadConfiguration) throws {}
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // Return empty wrapper - actual backup is done separately
        return FileWrapper(regularFileWithContents: Data())
    }
}

// MARK: - Preview

#Preview {
    CabinetGalleryView(
        templateManager: TemplateManager(),
        templates: [],
        onConvert: { _, _ in },
        onClose: {}
    )
    .frame(minWidth: 800, idealWidth: 1000, minHeight: 600, idealHeight: 750)
}
