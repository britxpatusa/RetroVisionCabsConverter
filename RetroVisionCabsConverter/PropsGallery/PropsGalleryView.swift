//
//  PropsGalleryView.swift
//  RetroVisionCabsConverter
//
//  Main view for browsing and managing non-cabinet props
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Props Gallery View

struct PropsGalleryView: View {
    @StateObject private var state = PropsGalleryState()
    @StateObject private var storage = PropsStorage.shared
    
    @State private var selectedProp: DiscoveredProp?
    @State private var showSaveConfirmation = false
    @State private var showClearConfirmation = false
    @State private var showBackupExporter = false
    @State private var showBackupImporter = false
    @State private var showBatchExport = false
    @State private var showExportAll = false
    
    var onClose: (() -> Void)?
    var onConvert: (([DiscoveredProp]) -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerToolbar
            
            Divider()
            
            // Content
            if state.props.isEmpty && !state.isScanning && !storage.isLoading {
                emptyState
            } else if state.isScanning || storage.isLoading {
                scanningState
            } else {
                galleryContent
            }
            
            Divider()
            
            // Footer
            footerBar
        }
        .sheet(item: $selectedProp) { prop in
            PropDetailSheet(
                prop: prop,
                onClose: { selectedProp = nil }
            )
        }
        .fileExporter(
            isPresented: $showBackupExporter,
            document: PropsBackupDocument(),
            contentType: .zip,
            defaultFilename: "PropsBackup_\(dateString()).zip"
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
        .alert("Save to Props Gallery", isPresented: $showSaveConfirmation) {
            Button("Save") {
                Task { await saveToGallery() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let duplicates = storage.countDuplicates(in: state.props)
            let newCount = state.props.count - duplicates
            Text("Save \(newCount) new prop(s) to your gallery?\n\(duplicates) duplicate(s) will be skipped.")
        }
        .alert("Clear Props Gallery", isPresented: $showClearConfirmation) {
            Button("Clear All", role: .destructive) {
                try? storage.clearAllProps()
                state.props = []
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove all \(storage.savedProps.count) saved prop(s) from the gallery?")
        }
        .sheet(isPresented: $showBatchExport) {
            let selectedProps = state.props.filter { state.selectedProps.contains($0.id) }
            BatchPropExportSheet(props: selectedProps) {
                showBatchExport = false
            }
        }
        .sheet(isPresented: $showExportAll) {
            BatchPropExportSheet(props: state.props) {
                showExportAll = false
            }
        }
        .onAppear {
            loadSavedProps()
        }
    }
    
    // MARK: - Header
    
    private var headerToolbar: some View {
        HStack(spacing: 12) {
            // Back button
            if let onClose = onClose {
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
                
                Divider().frame(height: 20)
            }
            
            // Title
            Label("Props Gallery", systemImage: "cube.transparent")
                .font(.headline)
            
            // Storage badge
            if !storage.savedProps.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "externaldrive.fill")
                        .font(.caption)
                    Text("\(storage.savedProps.count) saved")
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.purple.opacity(0.15))
                .foregroundStyle(.purple)
                .cornerRadius(10)
            }
            
            Spacer()
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search props...", text: $state.filterText)
                    .textFieldStyle(.plain)
                    .frame(width: 150)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
            
            // Filter by type
            Picker("Type", selection: $state.filterType) {
                Text("All Types").tag(PropType?.none)
                ForEach(PropType.allCases, id: \.self) { type in
                    Label(type.displayName, systemImage: type.icon).tag(PropType?.some(type))
                }
            }
            .frame(width: 140)
            
            // Filter by media
            Toggle("Has Video", isOn: $state.filterHasVideo)
                .toggleStyle(.checkbox)
            
            Divider().frame(height: 20)
            
            // Storage menu
            Menu {
                Button {
                    showSaveConfirmation = true
                } label: {
                    Label("Save to Gallery", systemImage: "square.and.arrow.down")
                }
                .disabled(state.props.isEmpty)
                
                Divider()
                
                Button {
                    showBackupExporter = true
                } label: {
                    Label("Export Backup...", systemImage: "arrow.up.doc")
                }
                .disabled(storage.savedProps.isEmpty)
                
                Button {
                    showBackupImporter = true
                } label: {
                    Label("Import Backup...", systemImage: "arrow.down.doc")
                }
                
                Divider()
                
                Button {
                    Task { await saveAsTemplates() }
                } label: {
                    Label("Save All as Templates", systemImage: "doc.badge.plus")
                }
                .disabled(state.props.isEmpty)
                
                Divider()
                
                Button {
                    exportAllProps()
                } label: {
                    Label("Export All for VisionOS", systemImage: "square.and.arrow.up.on.square")
                }
                .disabled(state.props.isEmpty)
                
                Divider()
                
                Button(role: .destructive) {
                    showClearConfirmation = true
                } label: {
                    Label("Clear Gallery", systemImage: "trash")
                }
                .disabled(storage.savedProps.isEmpty)
                
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
            Image(systemName: "cube.transparent")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("No Props Loaded")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Scan a folder containing non-cabinet props like\ncutouts, stages, decorations, and video displays.")
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
            
            // Quick scan for sample props folder
            if FileManager.default.fileExists(atPath: samplePropsPath) {
                Divider()
                    .frame(width: 200)
                    .padding(.vertical, 8)
                
                Button {
                    Task {
                        await scanFolder(URL(fileURLWithPath: samplePropsPath))
                    }
                } label: {
                    VStack(spacing: 4) {
                        Label("Quick Scan Sample Props", systemImage: "bolt.fill")
                        Text(samplePropsPath)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
            }
            
            // Load saved props
            if !storage.savedProps.isEmpty {
                Button {
                    loadSavedProps()
                } label: {
                    Label("Load \(storage.savedProps.count) Saved Props", systemImage: "arrow.clockwise")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var samplePropsPath: String {
        "/Volumes/FASTUSB/Age of Joy Cabinets/None Cabinets"
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
                GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 20)
            ], spacing: 20) {
                ForEach(state.filteredProps) { prop in
                    PropGalleryCard(
                        prop: prop,
                        isSelected: state.selectedProps.contains(prop.id),
                        isSaved: storage.isDuplicate(prop),
                        onSelect: { state.toggleSelection(prop.id) },
                        onDetail: { selectedProp = prop }
                    )
                }
            }
            .padding()
        }
    }
    
    // MARK: - Footer
    
    private var footerBar: some View {
        HStack(spacing: 16) {
            // Stats
            if !state.props.isEmpty {
                Text("\(state.props.count) props")
                    .foregroundStyle(.secondary)
                
                if state.videoCount > 0 {
                    Text("•").foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: "video.fill")
                        Text("\(state.videoCount) with video")
                    }
                    .font(.caption)
                    .foregroundStyle(.blue)
                }
                
                if storage.countDuplicates(in: state.props) > 0 {
                    Text("•").foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("\(storage.countDuplicates(in: state.props)) saved")
                    }
                    .font(.caption)
                }
            }
            
            if !storage.savedProps.isEmpty {
                Text("•").foregroundStyle(.secondary)
                Text("Storage: \(storage.storageSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Preview generation
            if state.isGeneratingPreviews {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Generating previews...")
                        .font(.caption)
                    Text("\(Int(state.previewProgress * 100))%")
                        .font(.caption.monospacedDigit())
                }
            } else if !state.props.isEmpty {
                Button {
                    Task { await generatePreviews() }
                } label: {
                    Label("Generate Previews", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
            }
            
            // Selection buttons
            if !state.props.isEmpty {
                Button("Select All") {
                    state.selectAll()
                }
                
                Button("Select New") {
                    selectUnsaved()
                }
                
                if !state.selectedProps.isEmpty {
                    Button("Clear Selection") {
                        state.clearSelection()
                    }
                }
            }
            
            // Save button
            if !state.props.isEmpty {
                let newCount = state.props.count - storage.countDuplicates(in: state.props)
                Button {
                    showSaveConfirmation = true
                } label: {
                    Label("Save \(newCount) New", systemImage: "square.and.arrow.down")
                }
                .disabled(newCount == 0)
            }
            
            // Export for VisionOS button
            if state.selectedProps.isEmpty {
                Text("Select props to export")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Button {
                showBatchExport = true
            } label: {
                Label("Export \(state.selectedProps.count) for VisionOS", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.selectedProps.isEmpty)
            
            // Convert button
            if let onConvert = onConvert {
                Button {
                    let selected = state.props.filter { state.selectedProps.contains($0.id) }
                    onConvert(selected)
                } label: {
                    Label("Convert \(state.selectedProps.count) Selected", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.selectedProps.isEmpty)
            }
        }
        .padding()
    }
    
    // MARK: - Actions
    
    private func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.title = "Select Props Folder"
        panel.message = "Choose a folder containing non-cabinet props"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await scanFolder(url)
            }
        }
    }
    
    private func loadSavedProps() {
        storage.loadSavedProps()
        if !storage.savedProps.isEmpty {
            state.props = storage.toDiscoveredProps()
            state.currentOperation = "Loaded \(storage.savedProps.count) saved prop(s)"
        }
    }
    
    private func scanFolder(_ url: URL) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        await MainActor.run {
            state.isScanning = true
            state.selectedProps = []
            state.scanProgress = 0
        }
        
        do {
            let discovered = try await PropsAnalyzer.shared.scanFolder(url) { progress, message in
                Task { @MainActor in
                    state.scanProgress = progress
                    state.currentOperation = message
                }
            }
            
            await MainActor.run {
                var allProps = storage.toDiscoveredProps()
                for newProp in discovered {
                    if !allProps.contains(where: { $0.id == newProp.id }) {
                        allProps.append(newProp)
                    }
                }
                state.props = allProps
                state.isScanning = false
                state.currentOperation = "Found \(discovered.count) prop(s)"
            }
            
            // Generate previews
            await generatePreviews()
            
        } catch {
            await MainActor.run {
                state.isScanning = false
                state.currentOperation = "Scan failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func generatePreviews() async {
        await MainActor.run {
            state.isGeneratingPreviews = true
        }
        
        let generator = PropsPreviewGenerator.shared
        
        for i in state.props.indices {
            let prop = state.props[i]
            
            // Skip if already has preview
            if prop.previewImage != nil { continue }
            
            if let preview = await generator.generatePreview(for: prop) {
                await MainActor.run {
                    if i < state.props.count {
                        state.props[i].previewImage = preview
                        state.props[i].previewGenerated = true
                    }
                }
            } else {
                await MainActor.run {
                    if i < state.props.count {
                        state.props[i].previewGenerated = true  // Mark as attempted
                    }
                }
            }
            
            await MainActor.run {
                state.previewProgress = Double(i + 1) / Double(state.props.count)
            }
        }
        
        await MainActor.run {
            state.isGeneratingPreviews = false
        }
    }
    
    private func saveToGallery() async {
        let propsToSave = state.props.filter { !storage.isDuplicate($0) }
        
        _ = await storage.saveProps(propsToSave) { progress, message in
            Task { @MainActor in
                state.scanProgress = progress
                state.currentOperation = message
            }
        }
    }
    
    private func exportAllProps() {
        showExportAll = true
    }
    
    private func saveAsTemplates() async {
        await MainActor.run {
            state.isScanning = true
            state.currentOperation = "Creating templates..."
        }
        
        let templateManager = PropsTemplateManager.shared
        let propsToTemplate = state.props
        
        var created = 0
        let total = propsToTemplate.count
        
        for (index, prop) in propsToTemplate.enumerated() {
            await MainActor.run {
                state.scanProgress = Double(index) / Double(total)
                state.currentOperation = "Creating template: \(prop.displayName)"
            }
            
            if templateManager.createTemplate(from: prop, preview: prop.previewImage) != nil {
                created += 1
            }
        }
        
        await MainActor.run {
            state.isScanning = false
            state.currentOperation = "Created \(created) templates"
            state.scanProgress = 0
        }
        
        print("Created \(created) prop templates from \(total) props")
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
                state.currentOperation = "Backup failed: \(error.localizedDescription)"
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
            let count = try await storage.restoreBackup(from: url) { progress, message in
                Task { @MainActor in
                    state.scanProgress = progress
                    state.currentOperation = message
                }
            }
            
            await MainActor.run {
                state.props = storage.toDiscoveredProps()
                state.currentOperation = "Imported \(count) prop(s)"
            }
        } catch {
            await MainActor.run {
                state.currentOperation = "Restore failed: \(error.localizedDescription)"
            }
        }
        
        await MainActor.run {
            state.isScanning = false
        }
    }
    
    private func selectUnsaved() {
        let unsavedIDs = state.filteredProps
            .filter { !storage.isDuplicate($0) }
            .map { $0.id }
        state.selectedProps = Set(unsavedIDs)
    }
    
    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

// MARK: - Props Gallery State

class PropsGalleryState: ObservableObject {
    @Published var props: [DiscoveredProp] = []
    @Published var selectedProps: Set<String> = []
    @Published var filterText = ""
    @Published var filterType: PropType? = nil
    @Published var filterHasVideo = false
    @Published var isScanning = false
    @Published var scanProgress: Double = 0
    @Published var currentOperation = ""
    @Published var isGeneratingPreviews = false
    @Published var previewProgress: Double = 0
    @Published var isConverting = false
    @Published var conversionProgress: Double = 0
    
    var filteredProps: [DiscoveredProp] {
        props.filter { prop in
            // Text filter
            if !filterText.isEmpty {
                let searchText = filterText.lowercased()
                guard prop.name.lowercased().contains(searchText) ||
                      prop.displayName.lowercased().contains(searchText) ||
                      prop.theme?.lowercased().contains(searchText) == true else {
                    return false
                }
            }
            
            // Type filter
            if let type = filterType, prop.propType != type {
                return false
            }
            
            // Video filter
            if filterHasVideo && !prop.hasVideo {
                return false
            }
            
            return true
        }
    }
    
    var videoCount: Int {
        props.filter { $0.hasVideo }.count
    }
    
    func toggleSelection(_ id: String) {
        if selectedProps.contains(id) {
            selectedProps.remove(id)
        } else {
            selectedProps.insert(id)
        }
    }
    
    func selectAll() {
        selectedProps = Set(filteredProps.map { $0.id })
    }
    
    func clearSelection() {
        selectedProps.removeAll()
    }
}

// MARK: - Backup Document

struct PropsBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }
    
    init() {}
    init(configuration: ReadConfiguration) throws {}
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: Data())
    }
}
