//
//  BuildView.swift
//  RetroVisionCabsConverter
//
//  Main view for building new cabinets from templates
//

import SwiftUI
import UniformTypeIdentifiers
import AVKit

struct BuildView: View {
    @StateObject private var templateManager = TemplateManager()
    @StateObject private var processRunner = ProcessRunner()
    @State private var buildConfig = BuildConfiguration()
    @State private var currentStep: BuildStep = .selectTemplate
    @State private var importedFiles: [URL] = []
    @State private var showingFilePicker = false
    @State private var showingFolderPicker = false
    @State private var showingOutputPicker = false
    @State private var isBuilding = false
    @State private var buildError: String?
    @State private var buildSuccess = false
    @State private var showPreview = false
    
    // Conversion state
    @State private var isConverting = false
    @State private var conversionProgress: String = ""
    @State private var conversionSuccess = false
    @State private var outputUsdzPath: URL?
    
    @Environment(\.dismiss) private var dismiss
    
    let paths: RetroVisionPaths
    let onBuildComplete: ((URL) -> Void)?
    
    init(paths: RetroVisionPaths, onBuildComplete: ((URL) -> Void)? = nil) {
        self.paths = paths
        self.onBuildComplete = onBuildComplete
    }
    
    enum BuildStep: Int, CaseIterable {
        case selectTemplate = 0
        case importArtwork = 1
        case configureGame = 2
        case review = 3
        
        var title: String {
            switch self {
            case .selectTemplate: return "Select Template"
            case .importArtwork: return "Import Artwork"
            case .configureGame: return "Configure Game"
            case .review: return "Review & Build"
            }
        }
        
        var icon: String {
            switch self {
            case .selectTemplate: return "square.stack.3d.up"
            case .importArtwork: return "photo.on.rectangle"
            case .configureGame: return "gamecontroller"
            case .review: return "checkmark.circle"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with steps
            stepIndicator
            
            Divider()
            
            // Content area
            Group {
                switch currentStep {
                case .selectTemplate:
                    templateSelectionView
                case .importArtwork:
                    artworkImportView
                case .configureGame:
                    gameConfigView
                case .review:
                    reviewView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // Footer with navigation
            navigationFooter
        }
        .frame(minWidth: 1000, idealWidth: 1200, maxWidth: .infinity,
               minHeight: 700, idealHeight: 850, maxHeight: .infinity)
        .overlay {
            // Progress overlay during build/conversion
            if isBuilding || isConverting {
                buildProgressOverlay
            }
        }
        .alert("Build Error", isPresented: .init(
            get: { buildError != nil },
            set: { if !$0 { buildError = nil } }
        )) {
            Button("OK") { buildError = nil }
        } message: {
            Text(buildError ?? "")
        }
        .alert("Build Complete", isPresented: $buildSuccess) {
            Button("Open Output Folder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: paths.outputUSDZ)
                dismiss()
            }
            if let usdzPath = outputUsdzPath {
                Button("Reveal USDZ") {
                    NSWorkspace.shared.selectFile(usdzPath.path, inFileViewerRootedAtPath: paths.outputUSDZ)
                    dismiss()
                }
            }
            Button("Done") { dismiss() }
        } message: {
            if let usdzPath = outputUsdzPath {
                Text("Cabinet '\(buildConfig.gameName)' has been built and converted to VisionOS format!\n\nOutput: \(usdzPath.lastPathComponent)")
            } else {
                Text("Cabinet '\(buildConfig.gameName)' has been created successfully!")
            }
        }
    }
    
    // MARK: - Build Progress Overlay
    
    private var buildProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .padding(.bottom, 10)
                
                Text(isConverting ? "Converting to VisionOS..." : "Building Cabinet...")
                    .font(.headline)
                
                // Progress log
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(conversionProgress)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("progressEnd")
                    }
                    .frame(width: 400, height: 200)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onChange(of: conversionProgress) { _, _ in
                        withAnimation {
                            proxy.scrollTo("progressEnd", anchor: .bottom)
                        }
                    }
                }
                
                if isConverting {
                    Text("This may take a moment...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(30)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 20)
        }
    }
    
    // MARK: - Step Indicator
    
    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(Array(BuildStep.allCases.enumerated()), id: \.element.rawValue) { index, step in
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(stepColor(for: step))
                            .frame(width: 32, height: 32)
                        
                        if step.rawValue < currentStep.rawValue {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.white)
                                .font(.system(size: 14, weight: .bold))
                        } else {
                            Text("\(index + 1)")
                                .foregroundStyle(step == currentStep ? .white : .secondary)
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    
                    Text(step.title)
                        .font(.subheadline)
                        .fontWeight(step == currentStep ? .semibold : .regular)
                        .foregroundStyle(step == currentStep ? .primary : .secondary)
                }
                .padding(.horizontal, 12)
                
                if step != BuildStep.allCases.last {
                    Rectangle()
                        .fill(step.rawValue < currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 2)
                        .frame(maxWidth: 60)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private func stepColor(for step: BuildStep) -> Color {
        if step.rawValue < currentStep.rawValue {
            return .green
        } else if step == currentStep {
            return .accentColor
        } else {
            return Color.secondary.opacity(0.3)
        }
    }
    
    // MARK: - Template Selection
    
    private var templateSelectionView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("Choose a Cabinet Template")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Select the type of arcade cabinet you want to build")
                        .foregroundStyle(.secondary)
                }
                .padding(.top)
                
                if templateManager.isLoading {
                    ProgressView("Loading templates...")
                        .padding(40)
                } else if let error = templateManager.error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(error)
                            .foregroundStyle(.secondary)
                        Button("Retry") {
                            templateManager.refresh()
                        }
                    }
                    .padding(40)
                } else {
                    // Group templates by cabinet type
                    let uprightTemplates = templateManager.templates.filter { $0.cabinetType == "upright" }
                    let specialtyTemplates = templateManager.templates.filter { $0.cabinetType != "upright" }
                    
                    // Upright cabinets
                    if !uprightTemplates.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "rectangle.portrait.fill")
                                    .foregroundStyle(.blue)
                                Text("Upright Cabinets")
                                    .font(.headline)
                                Text("\(uprightTemplates.count) templates")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16)
                            ], spacing: 16) {
                                ForEach(uprightTemplates) { template in
                                    TemplateCard(
                                        template: template,
                                        isSelected: buildConfig.template?.id == template.id
                                    )
                                    .onTapGesture {
                                        withAnimation {
                                            buildConfig.template = template
                                            initializeMappings(for: template)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // Specialty cabinets (cocktail, lightgun, driving, etc.)
                    if !specialtyTemplates.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "arcade.stick")
                                    .foregroundStyle(.purple)
                                Text("Specialty Cabinets")
                                    .font(.headline)
                                Text("Cocktail, Light Gun, Driving & more")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16)
                            ], spacing: 16) {
                                ForEach(specialtyTemplates) { template in
                                    TemplateCard(
                                        template: template,
                                        isSelected: buildConfig.template?.id == template.id
                                    )
                                    .onTapGesture {
                                        withAnimation {
                                            buildConfig.template = template
                                            initializeMappings(for: template)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.bottom)
        }
    }
    
    private func initializeMappings(for template: CabinetTemplate) {
        buildConfig.artworkMappings = [:]
        for part in template.allParts {
            buildConfig.artworkMappings[part.id] = ArtworkMapping(
                id: part.id,
                file: nil,
                status: .unmapped
            )
        }
    }
    
    // MARK: - Artwork Import
    
    private var artworkImportView: some View {
        HSplitView {
            // Left: File list and import
            VStack(alignment: .leading, spacing: 16) {
                Text("Import Your Artwork")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("Add your artwork files and they'll be automatically matched to cabinet parts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // Import options
                GroupBox("Import Options") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Artwork Pack import (primary)
                        HStack {
                            Image(systemName: "shippingbox.fill")
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Import Artwork Pack")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("ZIP file or folder with all artwork")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Button("Import Pack...") {
                                importArtworkPack()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        
                        Divider()
                        
                        // Individual file import
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                                .foregroundStyle(.orange)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Individual Files")
                                    .font(.subheadline)
                                Text("Select specific files")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Button("Add Files...") {
                                showingFilePicker = true
                            }
                            
                            Button("Add Folder...") {
                                showingFolderPicker = true
                            }
                        }
                    }
                    .padding(8)
                }
                
                // Export template link
                if buildConfig.template != nil {
                    HStack {
                        Image(systemName: "arrow.down.doc")
                            .foregroundStyle(.green)
                        Text("Need artwork templates?")
                            .font(.caption)
                        Button("Export Template Pack") {
                            exportTemplateForCurrentTemplate()
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                    }
                    .padding(.horizontal)
                }
                
                // Clear all
                if !importedFiles.isEmpty {
                    HStack {
                        Spacer()
                        Button("Clear All Artwork") {
                            importedFiles = []
                            if let template = buildConfig.template {
                                initializeMappings(for: template)
                            }
                        }
                        .foregroundStyle(.red)
                    }
                }
                
                // Imported files list
                if importedFiles.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No artwork files imported")
                            .foregroundStyle(.secondary)
                        Text("Import an artwork pack or drop files here")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Imported Files (\(importedFiles.count))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        List {
                            ForEach(importedFiles, id: \.path) { file in
                                HStack {
                                    Image(systemName: fileIcon(for: file))
                                        .foregroundStyle(fileColor(for: file))
                                    Text(file.lastPathComponent)
                                        .lineLimit(1)
                                    Spacer()
                                    Button {
                                        importedFiles.removeAll { $0 == file }
                                        remapArtwork()
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .listStyle(.inset)
                    }
                }
            }
            .frame(minWidth: 350, idealWidth: 400)
            .padding()
            
            // Right: Mapping preview
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Part Mappings")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    // Set all missing to black button
                    if !buildConfig.missingParts.isEmpty {
                        Button {
                            setAllMissingToBlack()
                        } label: {
                            Label("Fill Missing with Black", systemImage: "square.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Set all missing artwork to solid black")
                    }
                    
                    Text("\(buildConfig.mappedCount)/\(buildConfig.totalPartsCount) mapped")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if let template = buildConfig.template {
                    List {
                        Section("Required Parts") {
                            ForEach(template.requiredParts) { part in
                                PartMappingRow(
                                    part: part,
                                    mapping: buildConfig.artworkMappings[part.id],
                                    onSelect: { selectFileForPart(part) },
                                    onRotationChange: { rotation in
                                        updatePartTransform(partId: part.id, rotation: rotation)
                                    },
                                    onFlipChange: { invertX, invertY in
                                        updatePartFlip(partId: part.id, invertX: invertX, invertY: invertY)
                                    },
                                    onUseDefaultBlack: { useBlack in
                                        setUseDefaultBlack(partId: part.id, useBlack: useBlack)
                                    }
                                )
                            }
                        }
                        
                        let optionalParts = template.parts.filter { !$0.required }
                        if !optionalParts.isEmpty {
                            Section("Optional Parts") {
                                ForEach(optionalParts) { part in
                                    PartMappingRow(
                                        part: part,
                                        mapping: buildConfig.artworkMappings[part.id],
                                        onSelect: { selectFileForPart(part) },
                                        onRotationChange: { rotation in
                                            updatePartTransform(partId: part.id, rotation: rotation)
                                        },
                                        onFlipChange: { invertX, invertY in
                                            updatePartFlip(partId: part.id, invertX: invertX, invertY: invertY)
                                        },
                                        onUseDefaultBlack: { useBlack in
                                            setUseDefaultBlack(partId: part.id, useBlack: useBlack)
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 400, idealWidth: 500)
            .padding()
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderImport(result)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
            return true
        }
    }
    
    private func selectFileForPart(_ part: TemplatePart) {
        // Show file picker for manual selection
        let panel = NSOpenPanel()
        
        // Allow videos for marquee parts
        if part.type == .marquee {
            panel.allowedContentTypes = [.image, .movie, .mpeg4Movie]
            panel.message = "Select artwork or video for \(part.displayName)"
        } else {
            panel.allowedContentTypes = [.image]
            panel.message = "Select artwork for \(part.displayName)"
        }
        
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK, let url = panel.url {
            buildConfig.artworkMappings[part.id] = ArtworkMapping(
                id: part.id,
                file: url,
                status: .manuallyMapped
            )
            
            // Add to imported files if not already there
            if !importedFiles.contains(url) {
                importedFiles.append(url)
            }
        }
    }
    
    // MARK: - Import Artwork Pack
    
    private func importArtworkPack() {
        guard let template = buildConfig.template else { return }
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.folder, .zip, .archive]
        panel.message = "Select artwork pack folder or ZIP file"
        panel.prompt = "Import"
        
        if panel.runModal() == .OK, let url = panel.url {
            // Import using template manager
            let mappings = templateManager.importArtworkPack(from: url, for: template)
            
            // Update build config with imported mappings
            for (partId, mapping) in mappings {
                if mapping.file != nil {
                    buildConfig.artworkMappings[partId] = mapping
                    
                    // Add to imported files list
                    if let file = mapping.file, !importedFiles.contains(file) {
                        importedFiles.append(file)
                    }
                }
            }
            
            // Show import result
            let importedCount = mappings.values.filter { $0.file != nil }.count
            let totalParts = template.allParts.count
            
            let alert = NSAlert()
            alert.messageText = "Artwork Import Complete"
            alert.informativeText = "Matched \(importedCount) of \(totalParts) cabinet parts.\n\n" +
                (importedCount < totalParts ? "Some parts still need artwork assigned." : "All parts have artwork!")
            alert.alertStyle = importedCount == totalParts ? .informational : .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    private func exportTemplateForCurrentTemplate() {
        guard let template = buildConfig.template else { return }
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose where to save artwork templates for \(template.name)"
        panel.prompt = "Export"
        
        if panel.runModal() == .OK, let url = panel.url {
            let outputFolder = url.appendingPathComponent("\(template.name) Templates")
            
            do {
                try templateManager.generateArtworkGuides(for: template, outputFolder: outputFolder)
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: outputFolder.path)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }
    
    private func fileIcon(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "tiff", "bmp":
            return "photo"
        case "mp4", "mov", "m4v":
            return "film"
        default:
            return "doc"
        }
    }
    
    private func fileColor(for url: URL) -> Color {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png":
            return .blue
        case "jpg", "jpeg":
            return .orange
        case "mp4", "mov", "m4v":
            return .purple
        default:
            return .gray
        }
    }
    
    private func updatePartTransform(partId: String, rotation: Int) {
        if var mapping = buildConfig.artworkMappings[partId] {
            mapping.rotation = rotation
            buildConfig.artworkMappings[partId] = mapping
        }
    }
    
    private func updatePartFlip(partId: String, invertX: Bool, invertY: Bool) {
        if var mapping = buildConfig.artworkMappings[partId] {
            mapping.invertX = invertX
            mapping.invertY = invertY
            buildConfig.artworkMappings[partId] = mapping
        }
    }
    
    private func setUseDefaultBlack(partId: String, useBlack: Bool) {
        if var mapping = buildConfig.artworkMappings[partId] {
            mapping.useDefaultBlack = useBlack
            mapping.status = useBlack ? .defaultBlack : .unmapped
            // Clear file if using default black
            if useBlack {
                mapping.file = nil
            }
            buildConfig.artworkMappings[partId] = mapping
        } else {
            // Create new mapping with default black
            buildConfig.artworkMappings[partId] = ArtworkMapping(
                id: partId,
                file: nil,
                status: useBlack ? .defaultBlack : .unmapped,
                useDefaultBlack: useBlack
            )
        }
    }
    
    private func setAllMissingToBlack() {
        guard let template = buildConfig.template else { return }
        
        for part in template.parts {
            if let mapping = buildConfig.artworkMappings[part.id] {
                if !mapping.hasContent {
                    setUseDefaultBlack(partId: part.id, useBlack: true)
                }
            } else {
                setUseDefaultBlack(partId: part.id, useBlack: true)
            }
        }
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                if !importedFiles.contains(url) {
                    importedFiles.append(url)
                }
            }
            remapArtwork()
        case .failure(let error):
            buildError = error.localizedDescription
        }
    }
    
    private func handleFolderImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let folderURL = urls.first else { return }
            
            let fm = FileManager.default
            let imageExtensions = ["png", "jpg", "jpeg", "tiff", "bmp"]
            
            if let contents = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) {
                for fileURL in contents {
                    if imageExtensions.contains(fileURL.pathExtension.lowercased()) {
                        if !importedFiles.contains(fileURL) {
                            importedFiles.append(fileURL)
                        }
                    }
                }
            }
            remapArtwork()
        case .failure(let error):
            buildError = error.localizedDescription
        }
    }
    
    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }
                
                DispatchQueue.main.async {
                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                        if isDirectory.boolValue {
                            // It's a folder
                            let imageExtensions = ["png", "jpg", "jpeg", "tiff", "bmp"]
                            if let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                                for fileURL in contents {
                                    if imageExtensions.contains(fileURL.pathExtension.lowercased()) {
                                        if !importedFiles.contains(fileURL) {
                                            importedFiles.append(fileURL)
                                        }
                                    }
                                }
                            }
                        } else {
                            // It's a file
                            let imageExtensions = ["png", "jpg", "jpeg", "tiff", "bmp"]
                            if imageExtensions.contains(url.pathExtension.lowercased()) {
                                if !importedFiles.contains(url) {
                                    importedFiles.append(url)
                                }
                            }
                        }
                    }
                    remapArtwork()
                }
            }
        }
    }
    
    private func remapArtwork() {
        guard let template = buildConfig.template else { return }
        buildConfig.artworkMappings = templateManager.autoMapArtwork(
            files: importedFiles,
            template: template
        )
    }
    
    // MARK: - Game Configuration
    
    private var gameConfigView: some View {
        Form {
            Section("Game Information") {
                TextField("Game Name", text: $buildConfig.gameName)
                    .textFieldStyle(.roundedBorder)
                
                TextField("ROM Name (optional)", text: $buildConfig.romName)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Year (optional)", text: $buildConfig.year)
                    .textFieldStyle(.roundedBorder)
            }
            
            Section("Screen Video (Optional)") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        if let videoURL = buildConfig.videoFile {
                            Image(systemName: "film.fill")
                                .foregroundStyle(.blue)
                            Text(videoURL.lastPathComponent)
                                .lineLimit(1)
                            Spacer()
                            Button("Remove") {
                                buildConfig.videoFile = nil
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Image(systemName: "film")
                                .foregroundStyle(.secondary)
                            Text("No video selected")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Add Video...") {
                                let panel = NSOpenPanel()
                                panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
                                panel.allowsMultipleSelection = false
                                panel.message = "Select a video for the cabinet screen"
                                if panel.runModal() == .OK {
                                    buildConfig.videoFile = panel.url
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    
                    // Video preview
                    if let videoURL = buildConfig.videoFile {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Preview")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            ScreenVideoPreview(url: videoURL, orientation: buildConfig.template?.crtOrientation ?? "vertical")
                                .frame(height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    
                    Text("This video will play on the cabinet's screen. Supported formats: MP4, MOV")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // T-Molding Configuration
            if let tMoldingConfig = buildConfig.template?.tMolding {
                Section("T-Molding / Edge Trim") {
                    VStack(alignment: .leading, spacing: 16) {
                        // Enable toggle
                        Toggle("Add T-Molding", isOn: $buildConfig.tMoldingSettings.enabled)
                        
                        if buildConfig.tMoldingSettings.enabled {
                            // Color selection
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Color")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 8) {
                                    ForEach(tMoldingConfig.colorOptions) { option in
                                        TMoldingColorButton(
                                            colorOption: option,
                                            isSelected: buildConfig.tMoldingSettings.colorHex == option.hex,
                                            onSelect: {
                                                buildConfig.tMoldingSettings.colorHex = option.hex
                                                buildConfig.tMoldingSettings.colorName = option.name
                                            }
                                        )
                                    }
                                }
                            }
                            
                            Divider()
                            
                            // LED option
                            if tMoldingConfig.supportsLED == true {
                                VStack(alignment: .leading, spacing: 12) {
                                    Toggle(isOn: $buildConfig.tMoldingSettings.ledEnabled) {
                                        HStack {
                                            Image(systemName: "lightbulb.led.fill")
                                                .foregroundStyle(.yellow)
                                            Text("LED Effect")
                                                .fontWeight(.medium)
                                        }
                                    }
                                    
                                    if buildConfig.tMoldingSettings.ledEnabled {
                                        // Animation style
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Animation Style")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            
                                            Picker("", selection: $buildConfig.tMoldingSettings.ledAnimation) {
                                                Text("Pulse (Breathing)").tag("pulse")
                                                Text("Chase (Running)").tag("chase")
                                                Text("Rainbow (Color Cycle)").tag("rainbow")
                                                Text("Flash (Strobe)").tag("flash")
                                            }
                                            .pickerStyle(.segmented)
                                        }
                                        
                                        // Speed control
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text("Animation Speed")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                Spacer()
                                                Text(String(format: "%.1fx", buildConfig.tMoldingSettings.ledSpeed))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Slider(value: $buildConfig.tMoldingSettings.ledSpeed, in: 0.5...3.0, step: 0.5)
                                        }
                                        
                                        // Preview
                                        TMoldingLEDPreview(settings: buildConfig.tMoldingSettings)
                                            .frame(height: 40)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            Section("Output Location") {
                HStack {
                    if let outputURL = buildConfig.outputFolder {
                        Image(systemName: "folder")
                            .foregroundStyle(.blue)
                        Text(outputURL.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("Default: Cabinets folder")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Choose...") {
                        showingOutputPicker = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .fileImporter(
            isPresented: $showingOutputPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                buildConfig.outputFolder = url
            }
        }
    }
    
    // MARK: - Review
    
    private var reviewView: some View {
        HSplitView {
            // Left: Summary
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Template info
                    GroupBox("Template") {
                        HStack {
                            Image(systemName: "square.stack.3d.up")
                                .font(.title)
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading) {
                                Text(buildConfig.template?.name ?? "None")
                                    .font(.headline)
                                Text(buildConfig.template?.description ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                    }
                    
                    // Game info
                    GroupBox("Game") {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Name", value: buildConfig.gameName)
                            if !buildConfig.romName.isEmpty {
                                LabeledContent("ROM", value: buildConfig.romName)
                            }
                            if !buildConfig.year.isEmpty {
                                LabeledContent("Year", value: buildConfig.year)
                            }
                            if let video = buildConfig.videoFile {
                                LabeledContent("Video", value: video.lastPathComponent)
                            }
                        }
                        .padding(8)
                    }
                    
                    // Artwork summary
                    GroupBox("Artwork (\(buildConfig.mappedCount)/\(buildConfig.totalPartsCount))") {
                        VStack(alignment: .leading, spacing: 4) {
                            if let template = buildConfig.template {
                                ForEach(template.parts) { part in
                                    HStack {
                                        Image(systemName: buildConfig.artworkMappings[part.id]?.file != nil ? "checkmark.circle.fill" : "circle.dashed")
                                            .foregroundStyle(buildConfig.artworkMappings[part.id]?.file != nil ? .green : .secondary)
                                        Text(part.displayName)
                                            .font(.caption)
                                        Spacer()
                                        if let file = buildConfig.artworkMappings[part.id]?.file {
                                            Text(file.lastPathComponent)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }
                    
                    // Artwork completion status
                    if !buildConfig.allArtworkProvided {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Missing Artwork - All Pieces Required", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                    .font(.subheadline)
                                
                                Text("The model cannot be built until artwork is provided for all pieces:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                ForEach(buildConfig.missingParts) { part in
                                    HStack {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.red)
                                        Text(part.displayName)
                                            .font(.caption)
                                    }
                                }
                                
                                // Progress bar
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Completion:")
                                            .font(.caption)
                                        Spacer()
                                        Text("\(buildConfig.mappedCount)/\(buildConfig.totalPartsCount)")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    ProgressView(value: buildConfig.artworkProgress)
                                        .tint(buildConfig.allArtworkProvided ? .green : .orange)
                                }
                                .padding(.top, 4)
                            }
                            .padding(8)
                        }
                    } else {
                        GroupBox {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("All artwork provided")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(buildConfig.mappedCount)/\(buildConfig.totalPartsCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                        }
                    }
                }
                .padding()
            }
            .frame(minWidth: 380, idealWidth: 450)
            
            // Right: 3D Preview
            VStack {
                HStack {
                    Text("3D Preview")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button {
                        showPreview = true
                    } label: {
                        Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .disabled(buildConfig.template?.modelPath == nil)
                }
                
                // Embedded preview
                if let modelPath = buildConfig.template?.modelPath {
                    ModelPreviewView(
                        modelURL: URL(fileURLWithPath: modelPath),
                        artworkMappings: buildConfig.artworkMappings,
                        template: buildConfig.template
                    )
                    .cornerRadius(12)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.1))
                        .overlay {
                            VStack(spacing: 12) {
                                Image(systemName: "cube.transparent")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.secondary)
                                Text("Select a template to preview")
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
            }
            .padding()
            .frame(minWidth: 450, idealWidth: 550)
        }
        .sheet(isPresented: $showPreview) {
            if let modelPath = buildConfig.template?.modelPath {
                ModelPreviewView(
                    modelURL: URL(fileURLWithPath: modelPath),
                    artworkMappings: buildConfig.artworkMappings,
                    template: buildConfig.template
                )
                .frame(minWidth: 900, idealWidth: 1100, maxWidth: .infinity,
                       minHeight: 700, idealHeight: 850, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Navigation Footer
    
    private var navigationFooter: some View {
        VStack(spacing: 8) {
            // Block reason message
            if let reason = nextStepBlockReason {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.orange)
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Spacer()
                }
                .padding(.horizontal)
            }
            
            // Navigation buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                // Artwork progress indicator (on import step)
                if currentStep == .importArtwork {
                    HStack(spacing: 4) {
                        Text("\(buildConfig.mappedCount)/\(buildConfig.totalPartsCount)")
                            .font(.caption)
                            .fontWeight(.medium)
                        ProgressView(value: buildConfig.artworkProgress)
                            .frame(width: 100)
                            .tint(buildConfig.allArtworkProvided ? .green : .orange)
                    }
                }
                
                if currentStep != .selectTemplate {
                    Button("Back") {
                        withAnimation {
                            currentStep = BuildStep(rawValue: currentStep.rawValue - 1) ?? .selectTemplate
                        }
                    }
                }
                
                if currentStep == .review {
                    Button("Build Cabinet") {
                        buildCabinet()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!buildConfig.isValid || isBuilding)
                } else {
                    Button("Next") {
                        withAnimation {
                            currentStep = BuildStep(rawValue: currentStep.rawValue + 1) ?? .review
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canProceedToNextStep)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding(.top, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private var canProceedToNextStep: Bool {
        switch currentStep {
        case .selectTemplate:
            return buildConfig.template != nil
        case .importArtwork:
            // Require all required artwork before proceeding
            return buildConfig.allArtworkProvided
        case .configureGame:
            return !buildConfig.gameName.isEmpty
        case .review:
            return buildConfig.isValid
        }
    }
    
    private var nextStepBlockReason: String? {
        switch currentStep {
        case .selectTemplate:
            return buildConfig.template == nil ? "Select a template to continue" : nil
        case .importArtwork:
            if !buildConfig.allArtworkProvided {
                return "Provide artwork for all \(buildConfig.totalPartsCount) pieces (\(buildConfig.mappedCount) done)"
            }
            return nil
        case .configureGame:
            return buildConfig.gameName.isEmpty ? "Enter a game name to continue" : nil
        case .review:
            return buildConfig.isValid ? nil : "Complete all required fields"
        }
    }
    
    // MARK: - Pre-Build Validation
    
    struct ValidationIssue: Identifiable {
        let id = UUID()
        let severity: Severity
        let message: String
        let fix: String?
        
        enum Severity {
            case error, warning
            
            var icon: String {
                switch self {
                case .error: return "xmark.circle.fill"
                case .warning: return "exclamationmark.triangle.fill"
                }
            }
            
            var color: Color {
                switch self {
                case .error: return .red
                case .warning: return .orange
                }
            }
        }
    }
    
    private func validateBuild() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        
        // 1. Check game name for spaces/special characters
        let trimmedName = buildConfig.gameName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName != buildConfig.gameName {
            issues.append(ValidationIssue(
                severity: .warning,
                message: "Game name has leading/trailing spaces",
                fix: "Name will be trimmed automatically"
            ))
            // Auto-fix
            buildConfig.gameName = trimmedName
        }
        
        if buildConfig.gameName.isEmpty {
            issues.append(ValidationIssue(
                severity: .error,
                message: "Game name is required",
                fix: nil
            ))
        }
        
        // Check for problematic characters in game name
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        if buildConfig.gameName.rangeOfCharacter(from: invalidChars) != nil {
            issues.append(ValidationIssue(
                severity: .error,
                message: "Game name contains invalid characters (/ \\ : * ? \" < > |)",
                fix: "Remove special characters from the game name"
            ))
        }
        
        // 2. Check template and model file
        guard let template = buildConfig.template else {
            issues.append(ValidationIssue(
                severity: .error,
                message: "No template selected",
                fix: "Go back and select a cabinet template"
            ))
            return issues
        }
        
        if let modelPath = template.modelPath {
            if !FileManager.default.fileExists(atPath: modelPath) {
                issues.append(ValidationIssue(
                    severity: .error,
                    message: "Template model file not found: \(modelPath)",
                    fix: "Template may be corrupted - try reinstalling"
                ))
            }
        } else {
            issues.append(ValidationIssue(
                severity: .error,
                message: "Template has no model file configured",
                fix: "Template configuration is invalid"
            ))
        }
        
        // 3. Check artwork files exist
        for (partId, mapping) in buildConfig.artworkMappings {
            if let file = mapping.file {
                // Check file exists
                if !FileManager.default.fileExists(atPath: file.path) {
                    let partName = template.parts.first { $0.id == partId }?.displayName ?? partId
                    issues.append(ValidationIssue(
                        severity: .error,
                        message: "Artwork file not found for '\(partName)': \(file.lastPathComponent)",
                        fix: "Re-import the artwork file"
                    ))
                }
                
                // Check for spaces in filename
                let filename = file.lastPathComponent
                if filename.hasPrefix(" ") || filename.hasSuffix(" ") || filename.contains("  ") {
                    let partName = template.parts.first { $0.id == partId }?.displayName ?? partId
                    issues.append(ValidationIssue(
                        severity: .warning,
                        message: "Artwork file '\(filename)' for '\(partName)' has problematic spaces",
                        fix: "File will be renamed to remove extra spaces"
                    ))
                }
                
                // Check for space before extension (common issue)
                if filename.contains(" .") {
                    let partName = template.parts.first { $0.id == partId }?.displayName ?? partId
                    issues.append(ValidationIssue(
                        severity: .error,
                        message: "Artwork file '\(filename)' for '\(partName)' has a space before the extension",
                        fix: "Rename the file to remove the space before the extension"
                    ))
                }
            }
        }
        
        // 4. Check video file if present
        if let videoFile = buildConfig.videoFile {
            if !FileManager.default.fileExists(atPath: videoFile.path) {
                issues.append(ValidationIssue(
                    severity: .error,
                    message: "Video file not found: \(videoFile.lastPathComponent)",
                    fix: "Re-import the video file"
                ))
            }
            
            let videoFilename = videoFile.lastPathComponent
            if videoFilename.contains(" .") {
                issues.append(ValidationIssue(
                    severity: .error,
                    message: "Video file '\(videoFilename)' has a space before the extension",
                    fix: "Rename the file to remove the space before the extension"
                ))
            }
        }
        
        // 5. Check output location
        if let outputFolder = buildConfig.outputFolder {
            var isDirectory: ObjCBool = false
            if !FileManager.default.fileExists(atPath: outputFolder.path, isDirectory: &isDirectory) {
                issues.append(ValidationIssue(
                    severity: .warning,
                    message: "Output folder does not exist",
                    fix: "Folder will be created automatically"
                ))
            } else if !isDirectory.boolValue {
                issues.append(ValidationIssue(
                    severity: .error,
                    message: "Output path is not a folder",
                    fix: "Select a different output location"
                ))
            }
        }
        
        return issues
    }
    
    private func sanitizeFilename(_ filename: String) -> String {
        // Remove leading/trailing spaces
        var result = filename.trimmingCharacters(in: .whitespaces)
        
        // Fix space before extension
        if let dotIndex = result.lastIndex(of: ".") {
            let beforeDot = result[..<dotIndex]
            let afterDot = result[dotIndex...]
            result = beforeDot.trimmingCharacters(in: .whitespaces) + afterDot
        }
        
        // Replace multiple spaces with single
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        
        return result
    }
    
    // MARK: - Build
    
    private func buildCabinet() {
        guard let template = buildConfig.template else { return }
        
        // Run validation
        let issues = validateBuild()
        let errors = issues.filter { $0.severity == .error }
        
        if !errors.isEmpty {
            // Show error alert
            var errorMessage = "Please fix the following issues before building:\n\n"
            for error in errors {
                errorMessage += "• \(error.message)\n"
                if let fix = error.fix {
                    errorMessage += "  Fix: \(fix)\n"
                }
            }
            buildError = errorMessage
            return
        }
        
        // Show warnings if any
        let warnings = issues.filter { $0.severity == .warning }
        if !warnings.isEmpty {
            conversionProgress = "⚠️ Warnings (auto-fixed):\n"
            for warning in warnings {
                conversionProgress += "• \(warning.message)\n"
            }
            conversionProgress += "\n"
        }
        
        isBuilding = true
        
        Task {
            do {
                // Determine output folder
                let outputFolder = buildConfig.outputFolder ?? URL(fileURLWithPath: paths.ageCabinetsRoot)
                let cabinetFolderName = buildConfig.gameName.replacingOccurrences(of: " ", with: "_")
                let cabinetFolder = outputFolder.appendingPathComponent(cabinetFolderName)
                
                // Create cabinet folder
                try FileManager.default.createDirectory(at: cabinetFolder, withIntermediateDirectories: true)
                
                await MainActor.run {
                    conversionProgress = "Creating cabinet folder...\n"
                }
                
                // Copy artwork files (with sanitized names)
                for (_, mapping) in buildConfig.artworkMappings {
                    if let sourceFile = mapping.file {
                        let safeFilename = sanitizeFilename(sourceFile.lastPathComponent)
                        let destFile = cabinetFolder.appendingPathComponent(safeFilename)
                        try? FileManager.default.copyItem(at: sourceFile, to: destFile)
                    }
                }
                
                await MainActor.run {
                    conversionProgress += "Copying artwork files...\n"
                }
                
                // Copy video if present
                if let videoFile = buildConfig.videoFile {
                    let destVideo = cabinetFolder.appendingPathComponent(videoFile.lastPathComponent)
                    try? FileManager.default.copyItem(at: videoFile, to: destVideo)
                    await MainActor.run {
                        conversionProgress += "Copying video file...\n"
                    }
                }
                
                // Copy model file (with safe name)
                if let modelPath = template.modelPath {
                    let modelURL = URL(fileURLWithPath: modelPath)
                    let safeModelName = cabinetFolderName.replacingOccurrences(of: " ", with: "_")
                    let destModel = cabinetFolder.appendingPathComponent("\(safeModelName).glb")
                    try? FileManager.default.copyItem(at: modelURL, to: destModel)
                    await MainActor.run {
                        conversionProgress += "Copying 3D model...\n"
                    }
                }
                
                // Generate description.yaml
                let yaml = generateDescriptionYAML()
                let yamlPath = cabinetFolder.appendingPathComponent("description.yaml")
                try yaml.write(to: yamlPath, atomically: true, encoding: .utf8)
                
                await MainActor.run {
                    conversionProgress += "Generated cabinet definition\n\n"
                }
                
                buildConfig.outputFolder = cabinetFolder
                
                // Now convert to USDZ
                await MainActor.run {
                    isBuilding = false
                    isConverting = true
                    conversionProgress += "Converting to VisionOS format...\n"
                }
                
                // Run conversion
                await withCheckedContinuation { continuation in
                    processRunner.convertSingleCabinet(
                        cabinetPath: cabinetFolder.path,
                        paths: paths,
                        onProgress: { progress in
                            Task { @MainActor in
                                self.conversionProgress += progress
                            }
                        },
                        completion: { result in
                            Task { @MainActor in
                                self.isConverting = false
                                
                                switch result {
                                case .success(let usdzURL):
                                    self.outputUsdzPath = usdzURL
                                    self.conversionSuccess = true
                                    self.buildSuccess = true
                                    self.onBuildComplete?(cabinetFolder)
                                    
                                    // Copy VisionOS LED animation code to output folder
                                    self.copyVisionOSCodeToOutput(outputFolder: usdzURL.deletingLastPathComponent())
                                    
                                case .failure(let error):
                                    self.buildError = error.localizedDescription
                                }
                                
                                continuation.resume()
                            }
                        }
                    )
                }
                
            } catch {
                await MainActor.run {
                    isBuilding = false
                    isConverting = false
                    buildError = error.localizedDescription
                }
            }
        }
    }
    
    // MARK: - VisionOS Code Export
    
    /// Copy VisionOS LED animation Swift code to the output folder
    private func copyVisionOSCodeToOutput(outputFolder: URL) {
        let fm = FileManager.default
        
        // Create VisionOSCode subfolder in output
        let visionOSCodeFolder = outputFolder.appendingPathComponent("VisionOSCode")
        
        do {
            // Create folder if it doesn't exist
            if !fm.fileExists(atPath: visionOSCodeFolder.path) {
                try fm.createDirectory(at: visionOSCodeFolder, withIntermediateDirectories: true)
            }
            
            // Find the bundled VisionOS code
            if let bundleCodeURL = Bundle.main.url(forResource: "CabinetLEDAnimator", withExtension: "swift", subdirectory: "VisionOSCode") {
                let destURL = visionOSCodeFolder.appendingPathComponent("CabinetLEDAnimator.swift")
                
                // Remove existing if present
                if fm.fileExists(atPath: destURL.path) {
                    try fm.removeItem(at: destURL)
                }
                
                try fm.copyItem(at: bundleCodeURL, to: destURL)
                print("Copied VisionOS LED animation code to: \(destURL.path)")
            } else {
                // Fallback: try to find it in configured Resources folder
                let configPaths = RetroVisionPaths.load()
                let resourcesPath = "\(configPaths.visionOSCodeDirectory)/CabinetLEDAnimator.swift"
                if fm.fileExists(atPath: resourcesPath) {
                    let destURL = visionOSCodeFolder.appendingPathComponent("CabinetLEDAnimator.swift")
                    
                    if fm.fileExists(atPath: destURL.path) {
                        try fm.removeItem(at: destURL)
                    }
                    
                    try fm.copyItem(atPath: resourcesPath, toPath: destURL.path)
                    print("Copied VisionOS LED animation code (configured path) to: \(destURL.path)")
                }
            }
            
            // Create a README in the VisionOS folder
            let readmeContent = """
            # VisionOS LED Animation Code
            
            This folder contains Swift code for animating T-molding LEDs in your VisionOS app.
            
            ## Files
            
            - **CabinetLEDAnimator.swift** - RealityKit-based LED animation controller
            
            ## Usage
            
            1. Add `CabinetLEDAnimator.swift` to your VisionOS Xcode project
            2. Load your cabinet USDZ model using RealityKit
            3. Call the animator to enable LED effects:
            
            ```swift
            import RealityKit
            
            // In your RealityView:
            RealityView { content in
                if let entity = try? await Entity(named: "YourCabinet.usdz") {
                    content.add(entity)
                    
                    // Enable LED animation
                    await MainActor.run {
                        CabinetLEDAnimator.shared.setup(
                            entity: entity,
                            metadataURL: Bundle.main.url(
                                forResource: "YourCabinet.rkmeta",
                                withExtension: "json"
                            )
                        )
                    }
                }
            }
            ```
            
            The animator will automatically find T-molding meshes and apply the LED effects
            specified in the rkmeta.json file (pulse, rainbow, chase, or flash animations).
            
            ## LED Settings
            
            LED settings are stored in the `.rkmeta.json` file that accompanies each USDZ:
            
            ```json
            {
                "rk_contract": {
                    "led_effects": {
                        "enabled": true,
                        "animation": "rainbow",
                        "speed": 1.0
                    }
                }
            }
            ```
            
            ## Requirements
            
            - VisionOS 1.0+
            - RealityKit
            - SwiftUI
            """
            
            let readmeURL = visionOSCodeFolder.appendingPathComponent("README.md")
            try readmeContent.write(to: readmeURL, atomically: true, encoding: .utf8)
            
        } catch {
            print("Warning: Failed to copy VisionOS code: \(error)")
        }
    }
    
    private func generateDescriptionYAML() -> String {
        guard let template = buildConfig.template else { return "" }
        
        // Sanitize the game name (remove spaces, use underscore for folder name)
        let sanitizedGameName = buildConfig.gameName.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeGameName = sanitizedGameName.replacingOccurrences(of: " ", with: "_")
        
        var yaml = """
        name: \(sanitizedGameName)
        """
        
        if !buildConfig.year.isEmpty {
            yaml += "\nyear: \(buildConfig.year)"
        }
        
        if !buildConfig.romName.isEmpty {
            yaml += "\nrom: \(buildConfig.romName)"
        }
        
        yaml += "\nmaterial: \(template.defaultMaterial ?? "black")"
        
        yaml += "\n\nmodel:\n  file: \(safeGameName).glb"
        
        if let videoFile = buildConfig.videoFile {
            yaml += "\n\nvideo:\n  file: \(videoFile.lastPathComponent)"
            // Apply recommended transform based on CRT orientation
            if template.crtOrientation.lowercased().hasPrefix("horiz") {
                yaml += "\n  invertx: true"
            }
        }
        
        yaml += "\n\ncrt:\n  orientation: \(template.crtOrientation)"
        
        yaml += "\n\nparts:"
        
        for part in template.parts {
            guard let mapping = buildConfig.artworkMappings[part.id],
                  mapping.hasContent else {
                continue
            }
            
            yaml += "\n  - name: \(part.meshName)"
            
            if part.type != .texture {
                yaml += "\n    type: \(part.type.descriptionPartType.rawValue)"
            }
            
            if let file = mapping.file {
                // Has artwork file - sanitize filename
                let safeFilename = sanitizeFilename(file.lastPathComponent)
                yaml += "\n    art:\n      file: \(safeFilename)"
                
                // Add transform settings
                // Apply flipHorizontal from template definition (e.g., right side panel)
                let shouldFlipX = mapping.invertX || (part.flipHorizontal == true)
                if shouldFlipX {
                    yaml += "\n      invertx: true"
                }
                if mapping.invertY {
                    yaml += "\n      inverty: true"
                }
                if mapping.rotation != 0 {
                    yaml += "\n      rotate: \(mapping.rotation)"
                }
                
                if let color = part.defaultColor {
                    yaml += "\n    color:"
                    yaml += "\n      r: \(color.r)"
                    yaml += "\n      g: \(color.g)"
                    yaml += "\n      b: \(color.b)"
                    if let intensity = color.intensity {
                        yaml += "\n      intensity: \(intensity)"
                    }
                }
            } else if mapping.useDefaultBlack {
                // Using default black color - no artwork file
                yaml += "\n    color:"
                yaml += "\n      r: 13"
                yaml += "\n      g: 13"
                yaml += "\n      b: 13"
                yaml += "\n      name: default-black"
                yaml += "\n    material: black"
            }
        }
        
        // Add T-Molding configuration
        if template.tMolding != nil && buildConfig.tMoldingSettings.enabled {
            yaml += "\n\nt-molding:"
            yaml += "\n  enabled: true"
            
            // Parse hex color to RGB
            let hex = buildConfig.tMoldingSettings.colorHex.replacingOccurrences(of: "#", with: "")
            if let rgb = UInt64(hex, radix: 16) {
                let r = Int((rgb & 0xFF0000) >> 16)
                let g = Int((rgb & 0x00FF00) >> 8)
                let b = Int(rgb & 0x0000FF)
                yaml += "\n  color:"
                yaml += "\n    r: \(r)"
                yaml += "\n    g: \(g)"
                yaml += "\n    b: \(b)"
                yaml += "\n    name: \(buildConfig.tMoldingSettings.colorName)"
            }
            
            // LED settings
            if buildConfig.tMoldingSettings.ledEnabled {
                yaml += "\n  led:"
                yaml += "\n    enabled: true"
                yaml += "\n    animation: \(buildConfig.tMoldingSettings.ledAnimation)"
                yaml += "\n    speed: \(buildConfig.tMoldingSettings.ledSpeed)"
            }
        }
        
        return yaml
    }
}

// MARK: - Template Card

struct TemplateCard: View {
    let template: CabinetTemplate
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            // Icon/Preview
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorForCabinetType.opacity(0.1))
                    .frame(height: 120)
                    .overlay {
                        Image(systemName: iconForTemplate)
                            .font(.system(size: 40))
                            .foregroundStyle(isSelected ? .blue : colorForCabinetType)
                    }
                
                // Parts count badge
                Text("\(template.allParts.count) parts")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(colorForCabinetType.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(4)
                    .padding(6)
            }
            
            VStack(spacing: 4) {
                Text(template.name)
                    .font(.headline)
                
                Text(cabinetTypeLabel)
                    .font(.caption)
                    .foregroundStyle(colorForCabinetType)
                
                Text("\(template.requiredParts.count) required, \(template.allParts.count - template.requiredParts.count) optional")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        )
        .cornerRadius(12)
    }
    
    private var cabinetTypeLabel: String {
        switch template.cabinetType?.lowercased() ?? "" {
        case "upright": return "Upright Cabinet"
        case "cocktail": return "Cocktail Table"
        case "lightgun": return "Light Gun Cabinet"
        case "driving": return "Driving Cabinet"
        case "specialty": return "Specialty Cabinet"
        default: return "Arcade Cabinet"
        }
    }
    
    private var colorForCabinetType: Color {
        switch template.cabinetType?.lowercased() ?? "" {
        case "upright": return .blue
        case "cocktail": return .orange
        case "lightgun": return .red
        case "driving": return .green
        case "specialty": return .purple
        default: return .secondary
        }
    }
    
    private var iconForTemplate: String {
        let cabinetType = template.cabinetType ?? template.id
        switch cabinetType.lowercased() {
        case "upright": return "rectangle.portrait"
        case "cocktail": return "rectangle.split.2x1"
        case "lightgun": return "scope"
        case "driving": return "steeringwheel"
        case "specialty": return "bicycle"
        default:
            // Fallback based on template id/name
            if template.name.lowercased().contains("pac") { return "face.smiling" }
            if template.name.lowercased().contains("invader") { return "ant" }
            if template.name.lowercased().contains("defender") { return "airplane" }
            if template.name.lowercased().contains("duck") { return "hare" }
            if template.name.lowercased().contains("paper") { return "bicycle" }
            if template.name.lowercased().contains("world") || template.name.lowercased().contains("cup") { return "soccerball" }
            return "arcade.stick"
        }
    }
}

// MARK: - Part Mapping Row

struct PartMappingRow: View {
    let part: TemplatePart
    let mapping: ArtworkMapping?
    let onSelect: () -> Void
    var onRotationChange: ((Int) -> Void)?
    var onFlipChange: ((Bool, Bool) -> Void)?
    var onUseDefaultBlack: ((Bool) -> Void)?
    
    @State private var isExpanded = false
    
    private var isVideo: Bool {
        guard let file = mapping?.file else { return false }
        let ext = file.pathExtension.lowercased()
        return ext == "mp4" || ext == "mov" || ext == "m4v"
    }
    
    private var isUsingDefaultBlack: Bool {
        mapping?.useDefaultBlack ?? false
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack(spacing: 12) {
                // Preview thumbnail
                artworkThumbnail
                
                // Part info
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(part.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        if part.required {
                            Text("Required")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.2))
                                .cornerRadius(4)
                        }
                        
                        if part.type == .marquee {
                            Text("Supports Video")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.purple.opacity(0.2))
                                .cornerRadius(4)
                        }
                        
                        if isUsingDefaultBlack {
                            Text("Default Black")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.gray.opacity(0.3))
                                .cornerRadius(4)
                        }
                    }
                    
                    Text("\(part.dimensions.displayString) px")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let file = mapping?.file {
                        Text(file.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                    } else if isUsingDefaultBlack {
                        Text("Solid black color")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // Status indicator
                Image(systemName: mapping?.status.icon ?? "circle.dashed")
                    .foregroundStyle(mapping?.status.color ?? .secondary)
                    .font(.title3)
                
                // Default black toggle (when no file selected)
                if mapping?.file == nil {
                    Button {
                        onUseDefaultBlack?(!isUsingDefaultBlack)
                    } label: {
                        Label(isUsingDefaultBlack ? "Using Black" : "Use Black", 
                              systemImage: isUsingDefaultBlack ? "checkmark.square.fill" : "square")
                    }
                    .buttonStyle(.bordered)
                    .tint(isUsingDefaultBlack ? .gray : nil)
                    .controlSize(.small)
                }
                
                // Select button
                Button {
                    onSelect()
                } label: {
                    Label("Select", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                // Expand/collapse for preview
                if mapping?.file != nil {
                    Button {
                        withAnimation {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Expanded preview and controls
            if isExpanded, mapping?.file != nil {
                VStack(spacing: 12) {
                    // Large preview
                    artworkPreviewLarge
                    
                    // Transform controls
                    transformControls
                }
                .padding(.top, 8)
                .padding(.leading, 60)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(mapping?.file != nil ? Color.green.opacity(0.05) : Color.clear)
        )
    }
    
    // MARK: - Artwork Thumbnail
    
    private var artworkThumbnail: some View {
        Group {
            if let file = mapping?.file {
                if isVideo {
                    // Video thumbnail
                    videoThumbnail(url: file)
                } else {
                    // Image thumbnail with transforms
                    imageThumbnail(url: file)
                }
            } else if isUsingDefaultBlack {
                // Default black solid
                defaultBlackThumbnail
            } else {
                // Placeholder showing expected shape
                placeholderThumbnail
            }
        }
        .frame(width: 50, height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isUsingDefaultBlack ? Color.gray : Color.secondary.opacity(0.3), lineWidth: isUsingDefaultBlack ? 2 : 1)
        )
    }
    
    private var defaultBlackThumbnail: some View {
        ZStack {
            Color.black
            Image(systemName: "square.fill")
                .font(.caption)
                .foregroundStyle(.gray)
        }
    }
    
    private func imageThumbnail(url: URL) -> some View {
        Group {
            if let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .rotationEffect(.degrees(Double(mapping?.rotation ?? 0)))
                    .scaleEffect(x: (mapping?.invertX ?? false) ? -1 : 1, 
                                y: (mapping?.invertY ?? false) ? -1 : 1)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func videoThumbnail(url: URL) -> some View {
        ZStack {
            Color.black
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(.white)
        }
    }
    
    private var placeholderThumbnail: some View {
        ZStack {
            Color.secondary.opacity(0.1)
            VStack(spacing: 2) {
                Image(systemName: part.type == .marquee ? "sparkles.rectangle.stack" : "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Large Preview
    
    private var artworkPreviewLarge: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview (as \(part.displayName))")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if let file = mapping?.file {
                if isVideo {
                    // Video player preview
                    VideoPreviewPlayer(url: file)
                        .frame(height: 150)
                        .aspectRatio(part.dimensions.aspectRatio, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    // Image preview with part shape
                    imagePreviewWithShape(url: file)
                }
            }
        }
    }
    
    private func imagePreviewWithShape(url: URL) -> some View {
        Group {
            if let nsImage = NSImage(contentsOf: url) {
                VStack(spacing: 4) {
                    // Preview in part's aspect ratio
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: CGFloat(part.dimensions.width) / 4, 
                               height: CGFloat(part.dimensions.height) / 4)
                        .clipped()
                        .rotationEffect(.degrees(Double(mapping?.rotation ?? 0)))
                        .scaleEffect(x: (mapping?.invertX ?? false) ? -1 : 1, 
                                    y: (mapping?.invertY ?? false) ? -1 : 1)
                        .clipShape(partShape)
                        .overlay(
                            partShape
                                .stroke(partBorderColor, lineWidth: 2)
                        )
                        .shadow(radius: 4)
                    
                    // Orientation indicator
                    HStack {
                        Image(systemName: "arrow.up")
                            .font(.caption2)
                        Text("Top")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private var partShape: some Shape {
        RoundedRectangle(cornerRadius: part.type == .bezel ? 12 : 4)
    }
    
    private var partBorderColor: Color {
        switch part.type {
        case .marquee: return .purple
        case .bezel: return .blue
        default: return .gray
        }
    }
    
    // MARK: - Transform Controls
    
    private var transformControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Orientation & Transform")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 16) {
                // Rotation picker
                VStack(alignment: .leading, spacing: 4) {
                    Label("Rotation", systemImage: "rotate.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Picker("", selection: Binding(
                        get: { mapping?.rotation ?? 0 },
                        set: { onRotationChange?($0) }
                    )) {
                        Text("0°").tag(0)
                        Text("90°").tag(90)
                        Text("180°").tag(180)
                        Text("270°").tag(270)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
                
                Divider()
                    .frame(height: 40)
                
                // Flip controls
                VStack(alignment: .leading, spacing: 4) {
                    Label("Flip", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 12) {
                        Toggle(isOn: Binding(
                            get: { mapping?.invertX ?? false },
                            set: { onFlipChange?($0, mapping?.invertY ?? false) }
                        )) {
                            Label("Horizontal", systemImage: "arrow.left.arrow.right")
                        }
                        .toggleStyle(.checkbox)
                        
                        Toggle(isOn: Binding(
                            get: { mapping?.invertY ?? false },
                            set: { onFlipChange?(mapping?.invertX ?? false, $0) }
                        )) {
                            Label("Vertical", systemImage: "arrow.up.arrow.down")
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                
                Spacer()
                
                // Transform summary
                if let mapping = mapping, (mapping.rotation != 0 || mapping.invertX || mapping.invertY) {
                    VStack(alignment: .trailing) {
                        Text("Applied:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(transformDescription(mapping))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func transformDescription(_ mapping: ArtworkMapping) -> String {
        var parts: [String] = []
        if mapping.rotation != 0 { parts.append("Rotate \(mapping.rotation)°") }
        if mapping.invertX { parts.append("Flip H") }
        if mapping.invertY { parts.append("Flip V") }
        return parts.isEmpty ? "None" : parts.joined(separator: ", ")
    }
}

// MARK: - Video Preview Player

struct VideoPreviewPlayer: View {
    let url: URL
    @State private var player: AVPlayer?
    
    var body: some View {
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
                    .onAppear {
                        player.play()
                        player.isMuted = true
                    }
                    .onDisappear {
                        player.pause()
                    }
            } else {
                Color.black
                ProgressView()
                    .tint(.white)
            }
        }
        .onAppear {
            player = AVPlayer(url: url)
            // Loop the video
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player?.currentItem,
                queue: .main
            ) { _ in
                player?.seek(to: .zero)
                player?.play()
            }
        }
    }
}

// MARK: - Screen Video Preview

struct ScreenVideoPreview: View {
    let url: URL
    let orientation: String
    
    @State private var player: AVPlayer?
    @State private var isPlaying = true
    
    private var isVertical: Bool {
        orientation.lowercased().hasPrefix("vert")
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Video player
            ZStack {
                Color.black
                
                if let player = player {
                    VideoPlayer(player: player)
                        .aspectRatio(isVertical ? 3.0/4.0 : 4.0/3.0, contentMode: .fit)
                } else {
                    ProgressView()
                        .tint(.white)
                }
                
                // Play/Pause overlay
                VStack {
                    Spacer()
                    HStack {
                        Button {
                            isPlaying.toggle()
                            if isPlaying {
                                player?.play()
                            } else {
                                player?.pause()
                            }
                        } label: {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.title)
                                .foregroundStyle(.white)
                                .shadow(radius: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        
                        Spacer()
                    }
                }
            }
            .aspectRatio(isVertical ? 3.0/4.0 : 4.0/3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue, lineWidth: 2)
            )
            
            // Info
            VStack(alignment: .leading, spacing: 8) {
                Label("Screen Orientation", systemImage: "rectangle.portrait.rotate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(isVertical ? "Vertical (3:4)" : "Horizontal (4:3)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Divider()
                
                Label("Video will be displayed on the cabinet screen", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if isVertical {
                    Text("Games like Pac-Man, Galaga")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Games like Street Fighter, NBA Jam")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 200)
        }
        .onAppear {
            player = AVPlayer(url: url)
            player?.isMuted = true
            player?.play()
            
            // Loop
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player?.currentItem,
                queue: .main
            ) { _ in
                player?.seek(to: .zero)
                player?.play()
            }
        }
        .onDisappear {
            player?.pause()
        }
    }
}

// MARK: - T-Molding Color Button

struct TMoldingColorButton: View {
    let colorOption: TMoldingColorOption
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(colorOption.color)
                    .frame(width: 40, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                    )
                    .shadow(color: isSelected ? .accentColor.opacity(0.5) : .clear, radius: 4)
                
                Text(colorOption.name)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - T-Molding LED Preview

struct TMoldingLEDPreview: View {
    let settings: TMoldingSettings
    
    @State private var animationPhase: Double = 0
    
    private var baseColor: Color {
        settings.color
    }
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(0..<20, id: \.self) { index in
                    let ledColor = colorForLED(at: index, total: 20)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(ledColor)
                        .shadow(color: ledColor.opacity(0.8), radius: 4)
                }
            }
            .padding(4)
            .background(Color.black)
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func colorForLED(at index: Int, total: Int) -> Color {
        let normalizedIndex = Double(index) / Double(total)
        let phase = animationPhase
        
        switch settings.ledAnimation {
        case "pulse":
            // All LEDs pulse together
            let brightness = (sin(phase * .pi * 2) + 1) / 2
            return baseColor.opacity(0.3 + brightness * 0.7)
            
        case "chase":
            // LEDs light up in sequence
            let position = fmod(phase, 1.0)
            let distance = abs(normalizedIndex - position)
            let intensity = max(0, 1 - distance * 5)
            return baseColor.opacity(0.2 + intensity * 0.8)
            
        case "rainbow":
            // Rainbow color cycle
            let hue = fmod(normalizedIndex + phase, 1.0)
            return Color(hue: hue, saturation: 1, brightness: 1)
            
        case "flash":
            // Strobe effect
            let on = Int(phase * 4) % 2 == 0
            return on ? baseColor : baseColor.opacity(0.1)
            
        default:
            return baseColor
        }
    }
    
    private func startAnimation() {
        let duration = 2.0 / settings.ledSpeed
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            animationPhase = 1.0
        }
    }
}

// MARK: - Preview

#Preview {
    BuildView(paths: RetroVisionPaths())
}
