import SwiftUI
import UniformTypeIdentifiers

// MARK: - Media Inspector View

struct MediaInspectorView: View {
    @Binding var detail: CabinetDetail
    @Binding var isPresented: Bool
    let overrideManager: MediaOverrideManager
    var onSave: (() -> Void)?
    
    @State private var selectedPartIndex: Int?
    @State private var selectedSection: InspectorSection = .parts
    @State private var hasChanges = false
    @State private var showingFilePicker = false
    @State private var filePickerPartIndex: Int?
    @State private var showingVideoPicker = false
    
    enum InspectorSection {
        case parts
        case video
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Main content
            HSplitView {
                // Sidebar with sections
                sidebarList
                    .frame(minWidth: 200, maxWidth: 300)
                
                // Detail/Editor
                switch selectedSection {
                case .parts:
                    if let index = selectedPartIndex, index < detail.parts.count {
                        partEditor(for: index)
                    } else {
                        emptyState
                    }
                case .video:
                    videoEditor
                }
            }
            
            Divider()
            
            // Footer
            footer
        }
        .frame(minWidth: 700, minHeight: 500)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [UTType.image],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Media Inspector")
                    .font(.headline)
                Text(detail.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if hasChanges {
                Text("Unsaved changes")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
    }
    
    // MARK: - Sidebar List
    
    private var sidebarList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Video section
            VStack(alignment: .leading, spacing: 0) {
                Text("Video")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)
                
                Button {
                    selectedSection = .video
                    selectedPartIndex = nil
                } label: {
                    HStack {
                        Circle()
                            .fill(detail.videoStatus.color)
                            .frame(width: 8, height: 8)
                        
                        VStack(alignment: .leading) {
                            Text("Screen Video")
                                .font(.subheadline)
                            
                            if let video = detail.videoDetail, video.hasVideo {
                                Text(video.file ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("No video")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if overrideManager.hasVideoOverride(cabinetPath: detail.path) {
                            Image(systemName: "pencil.circle.fill")
                                .foregroundStyle(.blue)
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal)
                    .background(selectedSection == .video ? Color.accentColor.opacity(0.2) : Color.clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // Parts section
            Text("Parts")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            
            List(selection: $selectedPartIndex) {
                ForEach(Array(detail.parts.enumerated()), id: \.offset) { index, part in
                    HStack {
                        // Status indicator
                        Circle()
                            .fill(part.validationStatus.color)
                            .frame(width: 8, height: 8)
                        
                        VStack(alignment: .leading) {
                            Text(part.name)
                                .font(.subheadline)
                            
                            if let artFile = part.artFile {
                                Text(artFile)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("No texture")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        // Override indicator
                        if overrideManager.hasOverride(
                            cabinetPath: detail.path,
                            partName: part.name
                        ) {
                            Image(systemName: "pencil.circle.fill")
                                .foregroundStyle(.blue)
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(index)
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selectedPartIndex) { _, newValue in
                if newValue != nil {
                    selectedSection = .parts
                }
            }
        }
    }
    
    // MARK: - Video Editor
    
    private var videoEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Screen Video")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Video displayed on the cabinet screen behind the bezel")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Divider()
                
                // Current video
                GroupBox("Current Video") {
                    VStack(alignment: .leading, spacing: 12) {
                        if let video = detail.videoDetail, video.hasVideo {
                            HStack(alignment: .top, spacing: 16) {
                                // Video thumbnail
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.blue.opacity(0.2))
                                    .frame(width: 80, height: 60)
                                    .overlay {
                                        Image(systemName: video.isValid ? "play.circle.fill" : "exclamationmark.triangle.fill")
                                            .font(.title)
                                            .foregroundStyle(video.isValid ? .blue : .red)
                                    }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(video.file ?? "Unknown")
                                            .font(.subheadline)
                                        
                                        if let ext = video.fileExtension {
                                            Text(ext.uppercased())
                                                .font(.caption2)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 2)
                                                .background(Color.blue.opacity(0.2))
                                                .cornerRadius(4)
                                        }
                                    }
                                    
                                    // Status
                                    HStack(spacing: 4) {
                                        Image(systemName: video.validationStatus.icon)
                                        Text(video.validationStatus.message)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(video.validationStatus.color)
                                }
                                
                                Spacer()
                            }
                        } else {
                            HStack {
                                Image(systemName: "film.fill")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                
                                VStack(alignment: .leading) {
                                    Text("No video configured")
                                        .font(.subheadline)
                                    Text("The screen will be static")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding()
                        }
                        
                        // Action buttons
                        HStack {
                            Button {
                                showingVideoPicker = true
                            } label: {
                                Label("Choose Video...", systemImage: "folder")
                            }
                            
                            if detail.videoDetail?.hasVideo == true {
                                Button(role: .destructive) {
                                    clearVideo()
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                            
                            Spacer()
                        }
                    }
                    .padding(8)
                }
                
                // Transform options
                if detail.videoDetail?.hasVideo == true {
                    GroupBox("Video Transform") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Adjust video orientation to match your screen")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 20) {
                                Toggle(isOn: Binding(
                                    get: { detail.videoDetail?.invertX ?? false },
                                    set: { newValue in
                                        setVideoTransform(invertX: newValue, invertY: detail.videoDetail?.invertY ?? false)
                                    }
                                )) {
                                    Label("Flip Horizontal", systemImage: "arrow.left.arrow.right")
                                }
                                .toggleStyle(.checkbox)
                                
                                Toggle(isOn: Binding(
                                    get: { detail.videoDetail?.invertY ?? false },
                                    set: { newValue in
                                        setVideoTransform(invertX: detail.videoDetail?.invertX ?? false, invertY: newValue)
                                    }
                                )) {
                                    Label("Flip Vertical", systemImage: "arrow.up.arrow.down")
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                        .padding(8)
                    }
                }
                
                // Available videos
                GroupBox("Available Videos") {
                    let videos = detail.videoFiles
                    
                    if videos.isEmpty {
                        Text("No video files found in cabinet folder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(8)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(videos) { file in
                                selectableVideoRow(file: file)
                            }
                        }
                        .padding(8)
                    }
                }
                
                // Supported formats info
                GroupBox("Supported Formats") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Common video formats:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            ForEach(["MP4", "MKV", "MOV", "WEBM"], id: \.self) { format in
                                Text(format)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }
                    }
                    .padding(8)
                }
            }
            .padding()
        }
        .fileImporter(
            isPresented: $showingVideoPicker,
            allowedContentTypes: [UTType.movie, UTType.video, UTType.mpeg4Movie, UTType.quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            handleVideoSelection(result)
        }
    }
    
    private func selectableVideoRow(file: CabinetFileInfo) -> some View {
        let isSelected = detail.videoDetail?.file == file.filename
        
        return Button {
            applyVideo(file.filename)
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "film")
                    .foregroundStyle(isSelected ? .green : .blue)
                
                Text(file.filename)
                    .font(.subheadline)
                
                Spacer()
                
                Text((file.filename as NSString).pathExtension.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(isSelected ? Color.green.opacity(0.1) : Color.secondary.opacity(0.05))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
    
    private func applyVideo(_ filename: String) {
        overrideManager.setVideoOverride(
            cabinetPath: detail.path,
            file: filename,
            invertX: detail.videoDetail?.invertX,
            invertY: detail.videoDetail?.invertY
        )
        
        let config = VideoConfig(
            file: filename,
            invertX: detail.videoDetail?.invertX ?? false,
            invertY: detail.videoDetail?.invertY ?? false
        )
        detail.videoDetail = VideoDetail(from: config, cabinetPath: detail.path)
        
        hasChanges = true
    }
    
    private func clearVideo() {
        overrideManager.setVideoOverride(cabinetPath: detail.path, file: nil)
        detail.videoDetail = nil
        hasChanges = true
    }
    
    private func setVideoTransform(invertX: Bool, invertY: Bool) {
        overrideManager.setVideoTransform(cabinetPath: detail.path, invertX: invertX, invertY: invertY)
        
        if var video = detail.videoDetail {
            video.invertX = invertX
            video.invertY = invertY
            detail.videoDetail = video
        }
        
        hasChanges = true
    }
    
    private func handleVideoSelection(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result,
              let url = urls.first else {
            return
        }
        
        // Copy file to cabinet folder if needed
        let filename = url.lastPathComponent
        let destPath = (detail.path as NSString).appendingPathComponent(filename)
        
        if !FileManager.default.fileExists(atPath: destPath) {
            do {
                _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }
                try FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: destPath))
                
                // Add to files list
                let newFile = CabinetFileInfo(filename: filename, cabinetPath: detail.path)
                detail.files.append(newFile)
            } catch {
                print("Failed to copy video: \(error)")
                return
            }
        }
        
        applyVideo(filename)
    }
    
    // MARK: - Part Editor
    
    private func partEditor(for index: Int) -> some View {
        let part = detail.parts[index]
        
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Part header
                VStack(alignment: .leading, spacing: 4) {
                    Text(part.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    HStack {
                        Label(part.type.rawValue, systemImage: "tag")
                        
                        if let material = part.material {
                            Label(material, systemImage: "paintbrush")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                
                Divider()
                
                // Current texture
                GroupBox("Current Texture") {
                    VStack(alignment: .leading, spacing: 12) {
                        if let artFile = part.artFile, !artFile.isEmpty {
                            HStack(alignment: .top, spacing: 16) {
                                // Thumbnail
                                texturePreview(for: part)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(artFile)
                                        .font(.subheadline)
                                    
                                    // Status
                                    HStack {
                                        Image(systemName: part.validationStatus.icon)
                                        Text(part.validationStatus.message)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(part.validationStatus.color)
                                }
                                
                                Spacer()
                            }
                        } else {
                            HStack {
                                Image(systemName: "photo.badge.plus")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                
                                VStack(alignment: .leading) {
                                    Text("No texture assigned")
                                        .font(.subheadline)
                                    Text("This part uses material color only")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding()
                        }
                        
                        // Action buttons
                        HStack {
                            Button {
                                filePickerPartIndex = index
                                showingFilePicker = true
                            } label: {
                                Label("Choose File...", systemImage: "folder")
                            }
                            
                            if part.artFile != nil {
                                Button(role: .destructive) {
                                    clearTexture(at: index)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                            
                            Spacer()
                        }
                    }
                    .padding(8)
                }
                
                // Texture Transform Options
                if part.artFile != nil {
                    GroupBox("Texture Transform") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Adjust texture orientation")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            // Rotation picker
                            HStack {
                                Label("Rotation:", systemImage: "rotate.right")
                                    .font(.subheadline)
                                
                                Picker("", selection: Binding(
                                    get: { part.artRotation },
                                    set: { setPartRotation(at: index, rotation: $0) }
                                )) {
                                    Text("0°").tag(0)
                                    Text("90°").tag(90)
                                    Text("180°").tag(180)
                                    Text("270°").tag(270)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 180)
                            }
                            
                            Divider()
                            
                            // Flip toggles
                            HStack(spacing: 20) {
                                Toggle(isOn: Binding(
                                    get: { part.artInvertX },
                                    set: { setPartFlip(at: index, invertX: $0, invertY: part.artInvertY) }
                                )) {
                                    Label("Flip Horizontal", systemImage: "arrow.left.arrow.right")
                                }
                                .toggleStyle(.checkbox)
                                
                                Toggle(isOn: Binding(
                                    get: { part.artInvertY },
                                    set: { setPartFlip(at: index, invertX: part.artInvertX, invertY: $0) }
                                )) {
                                    Label("Flip Vertical", systemImage: "arrow.up.arrow.down")
                                }
                                .toggleStyle(.checkbox)
                            }
                            
                            // Transform preview
                            if part.artRotation != 0 || part.artInvertX || part.artInvertY {
                                HStack {
                                    Image(systemName: "info.circle")
                                        .foregroundStyle(.blue)
                                    Text("Transform: \(transformDescription(for: part))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.top, 4)
                            }
                        }
                        .padding(8)
                    }
                }
                
                // Suggestions
                if case .suggestion(let file, let confidence) = part.validationStatus {
                    GroupBox("Suggestion") {
                        HStack {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(.orange)
                            
                            VStack(alignment: .leading) {
                                Text("Found a potential match:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Text(file)
                                    .font(.subheadline)
                                
                                Text("\(Int(confidence * 100))% match")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Button("Apply") {
                                applyTexture(file, at: index)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(8)
                    }
                }
                
                // Available files
                GroupBox("Available Images") {
                    let unassigned = detail.unassignedImages
                    
                    if unassigned.isEmpty {
                        Text("No unassigned images available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(8)
                    } else {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 80))
                        ], spacing: 8) {
                            ForEach(unassigned) { file in
                                selectableFileThumb(file: file, partIndex: index)
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .padding()
        }
    }
    
    private func texturePreview(for part: CabinetPartDetail) -> some View {
        Group {
            if let fullPath = part.artFullPath,
               FileManager.default.fileExists(atPath: fullPath),
               let nsImage = NSImage(contentsOfFile: fullPath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 150, maxHeight: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 2)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 100, height: 100)
                    .overlay {
                        VStack {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title)
                            Text("Not Found")
                                .font(.caption)
                        }
                        .foregroundStyle(.red)
                    }
            }
        }
    }
    
    private func selectableFileThumb(file: CabinetFileInfo, partIndex: Int) -> some View {
        Button {
            applyTexture(file.filename, at: partIndex)
        } label: {
            VStack(spacing: 4) {
                if let nsImage = NSImage(contentsOfFile: file.fullPath) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 60, height: 60)
                }
                
                Text(file.filename)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 70)
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack {
            Image(systemName: "sidebar.left")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            
            Text("Select a part to edit")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        HStack {
            Button("Reset All") {
                resetAllOverrides()
            }
            .disabled(!hasChanges)
            
            Spacer()
            
            Button("Cancel") {
                isPresented = false
            }
            .keyboardShortcut(.escape)
            
            Button("Save") {
                saveChanges()
            }
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
            .disabled(!hasChanges)
        }
        .padding()
    }
    
    // MARK: - Actions
    
    private func applyTexture(_ filename: String, at index: Int) {
        // Save override
        overrideManager.setOverride(
            cabinetPath: detail.path,
            partName: detail.parts[index].name,
            newArtFile: filename
        )
        
        // Update local state
        let currentPart = detail.parts[index]
        let fullPath = (detail.path as NSString).appendingPathComponent(filename)
        
        // Create a new CabinetPartDetail with updated art
        detail.parts[index] = CabinetPartDetail(
            from: CabinetPart(
                name: currentPart.name,
                type: currentPart.type,
                art: ArtConfig(file: filename),
                material: currentPart.material,
                color: currentPart.color
            ),
            cabinetPath: detail.path
        )
        detail.parts[index].validationStatus = FileManager.default.fileExists(atPath: fullPath) ? .valid : .error("File not found")
        
        // Update file assignments
        updateFileAssignments()
        
        hasChanges = true
    }
    
    private func clearTexture(at index: Int) {
        overrideManager.setOverride(
            cabinetPath: detail.path,
            partName: detail.parts[index].name,
            newArtFile: nil
        )
        
        let part = detail.parts[index]
        detail.parts[index] = CabinetPartDetail(
            from: CabinetPart(
                name: part.name,
                type: part.type,
                art: nil,
                material: part.material,
                color: part.color
            ),
            cabinetPath: detail.path
        )
        
        updateFileAssignments()
        hasChanges = true
    }
    
    private func setPartRotation(at index: Int, rotation: Int) {
        var part = detail.parts[index]
        part.artRotation = rotation
        detail.parts[index] = part
        
        overrideManager.setPartTransform(
            cabinetPath: detail.path,
            partName: part.name,
            rotation: rotation,
            invertX: part.artInvertX,
            invertY: part.artInvertY
        )
        
        hasChanges = true
    }
    
    private func setPartFlip(at index: Int, invertX: Bool, invertY: Bool) {
        var part = detail.parts[index]
        part.artInvertX = invertX
        part.artInvertY = invertY
        detail.parts[index] = part
        
        overrideManager.setPartTransform(
            cabinetPath: detail.path,
            partName: part.name,
            rotation: part.artRotation,
            invertX: invertX,
            invertY: invertY
        )
        
        hasChanges = true
    }
    
    private func transformDescription(for part: CabinetPartDetail) -> String {
        var parts: [String] = []
        if part.artRotation != 0 { parts.append("\(part.artRotation)°") }
        if part.artInvertX { parts.append("Flip H") }
        if part.artInvertY { parts.append("Flip V") }
        return parts.joined(separator: ", ")
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        guard let index = filePickerPartIndex,
              case .success(let urls) = result,
              let url = urls.first else {
            return
        }
        
        // Copy file to cabinet folder if needed
        let filename = url.lastPathComponent
        let destPath = (detail.path as NSString).appendingPathComponent(filename)
        
        if !FileManager.default.fileExists(atPath: destPath) {
            do {
                _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }
                try FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: destPath))
            } catch {
                print("Failed to copy file: \(error)")
                return
            }
        }
        
        applyTexture(filename, at: index)
    }
    
    private func updateFileAssignments() {
        let assignedFiles = Set(detail.parts.compactMap { $0.artFile })
        
        for i in detail.files.indices {
            detail.files[i].isAssigned = assignedFiles.contains(detail.files[i].filename)
            detail.files[i].assignedToPart = detail.parts.first { $0.artFile == detail.files[i].filename }?.name
        }
    }
    
    private func resetAllOverrides() {
        overrideManager.clearOverrides(for: detail.path)
        hasChanges = false
        // Trigger reload
        onSave?()
    }
    
    private func saveChanges() {
        overrideManager.save()
        hasChanges = false
        onSave?()
        isPresented = false
    }
}

// MARK: - Preview

#Preview {
    MediaInspectorView(
        detail: .constant(CabinetDetail(path: "/mock")),
        isPresented: .constant(true),
        overrideManager: MediaOverrideManager()
    )
}
