import SwiftUI

// MARK: - Cabinet Detail View

struct CabinetDetailView: View {
    let detail: CabinetDetail
    @Binding var showMediaInspector: Bool
    var onApplySuggestion: ((String, String) -> Void)?
    @State private var showModelPreview = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                headerSection
                
                Divider()
                
                // Status summary
                statusSection
                
                if detail.hasDescription {
                    Divider()
                    
                    // Video section
                    videoSection
                    
                    Divider()
                    
                    // Parts section
                    partsSection
                    
                    Divider()
                    
                    // Files section
                    filesSection
                }
            }
            .padding()
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(detail.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // Preview 3D button
                if hasModelFile {
                    Button {
                        showModelPreview = true
                    } label: {
                        Label("Preview 3D", systemImage: "cube")
                    }
                    .buttonStyle(.bordered)
                }
                
                statusBadge(for: detail.overallStatus)
            }
            
            HStack(spacing: 16) {
                if let year = detail.year {
                    Label(year, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if let rom = detail.rom {
                    Label(rom, systemImage: "cpu")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if let style = detail.style {
                    Label(style, systemImage: "cube")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if let material = detail.material {
                Label("Material: \(material)", systemImage: "paintbrush")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showModelPreview) {
            if let modelPath = modelFilePath {
                ModelPreviewWindow(
                    modelPath: modelPath,
                    cabinetName: detail.name
                )
            }
        }
    }
    
    private var hasModelFile: Bool {
        modelFilePath != nil
    }
    
    private var modelFilePath: String? {
        // Check for model file in cabinet folder
        let fm = FileManager.default
        
        // First check if modelFile is specified
        if let modelFile = detail.modelFile {
            let path = (detail.path as NSString).appendingPathComponent(modelFile)
            if fm.fileExists(atPath: path) {
                return path
            }
        }
        
        // Look for GLB files in the folder
        if let contents = try? fm.contentsOfDirectory(atPath: detail.path) {
            for file in contents {
                if file.lowercased().hasSuffix(".glb") || file.lowercased().hasSuffix(".gltf") {
                    return (detail.path as NSString).appendingPathComponent(file)
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Status Section
    
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.headline)
            
            if !detail.hasDescription {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("No description.yaml found in this folder")
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            } else {
                HStack(spacing: 20) {
                    statusCounter(
                        count: detail.readyParts.count,
                        label: "Ready",
                        color: .green
                    )
                    
                    statusCounter(
                        count: detail.warningCount,
                        label: "Warnings",
                        color: .yellow
                    )
                    
                    statusCounter(
                        count: detail.errorCount,
                        label: "Errors",
                        color: .red
                    )
                }
                
                if !detail.unassignedImages.isEmpty {
                    HStack {
                        Image(systemName: "photo.badge.plus")
                            .foregroundStyle(.orange)
                        Text("\(detail.unassignedImages.count) unassigned image(s) available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
    
    private func statusCounter(count: Int, label: String, color: Color) -> some View {
        VStack {
            Text("\(count)")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(count > 0 ? color : .secondary)
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Video Section
    
    private var videoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Video")
                    .font(.headline)
                
                Spacer()
                
                if let video = detail.videoDetail {
                    HStack(spacing: 4) {
                        Image(systemName: video.validationStatus.icon)
                        Text(video.hasVideo ? (video.isValid ? "Ready" : "Missing") : "None")
                    }
                    .font(.caption)
                    .foregroundStyle(video.validationStatus.color)
                }
            }
            
            if let video = detail.videoDetail, video.hasVideo {
                // Video configured
                VideoConfigCard(video: video, availableVideos: detail.videoFiles)
            } else {
                // No video configured
                noVideoView
            }
        }
    }
    
    private var noVideoView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "film.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("No video configured")
                        .font(.subheadline)
                    Text("The screen will display a static image or color")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            
            // Show available video files
            if !detail.videoFiles.isEmpty {
                Text("Available videos:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                ForEach(detail.videoFiles) { file in
                    HStack {
                        Image(systemName: "film")
                            .foregroundStyle(.blue)
                        Text(file.filename)
                            .font(.caption)
                        Spacer()
                        Text(file.fileType.rawValue.uppercased())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(6)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(4)
                }
            }
        }
    }
    
    // MARK: - Parts Section
    
    private var partsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Parts")
                    .font(.headline)
                
                Spacer()
                
                Text("\(detail.parts.count) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if detail.parts.isEmpty {
                Text("No parts defined")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(detail.parts) { part in
                        PartRowView(
                            part: part,
                            onApplySuggestion: { suggestedFile in
                                onApplySuggestion?(part.name, suggestedFile)
                            }
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Files Section
    
    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Files")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    showMediaInspector = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            
            // Image files
            if !detail.imageFiles.isEmpty {
                Text("Images")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 80, maximum: 100))
                ], spacing: 8) {
                    ForEach(detail.imageFiles) { file in
                        FileThumbView(file: file)
                    }
                }
            }
            
            // Model files
            let modelFiles = detail.files.filter { $0.fileType == .model }
            if !modelFiles.isEmpty {
                Text("Models")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                
                ForEach(modelFiles) { file in
                    HStack {
                        Image(systemName: file.fileType.icon)
                            .foregroundStyle(.blue)
                        Text(file.filename)
                            .font(.caption)
                        
                        Spacer()
                        
                        if file.isAssigned {
                            Text("In use")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(6)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func statusBadge(for status: ValidationStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
            Text(status.isValid ? "Ready" : status.isError ? "Issues" : "Warnings")
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.color.opacity(0.2))
        .foregroundStyle(status.color)
        .cornerRadius(8)
    }
}

// MARK: - Part Row View

struct PartRowView: View {
    let part: CabinetPartDetail
    var onApplySuggestion: ((String) -> Void)?
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            thumbnailView
            
            // Part info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(part.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if part.type != .default {
                        Text(part.type.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                if let artFile = part.artFile {
                    Text(artFile)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(part.material != nil ? "Material: \(part.material!)" : "No texture")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Status indicator
            statusIndicator
        }
        .padding(8)
        .background(backgroundForStatus)
        .cornerRadius(8)
        .onHover { isHovered = $0 }
    }
    
    private var thumbnailView: some View {
        Group {
            if let fullPath = part.artFullPath,
               FileManager.default.fileExists(atPath: fullPath),
               let nsImage = NSImage(contentsOfFile: fullPath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(materialColor)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: part.hasTexture ? "photo" : "paintbrush.fill")
                            .foregroundStyle(.white.opacity(0.5))
                    }
            }
        }
    }
    
    private var materialColor: Color {
        switch part.material?.lowercased() {
        case "black": return Color(white: 0.1)
        case "plastic": return Color(white: 0.2)
        case "lightwood": return Color(red: 0.65, green: 0.55, blue: 0.40)
        case "darkwood": return Color(red: 0.22, green: 0.16, blue: 0.10)
        default: return Color(white: 0.3)
        }
    }
    
    private var statusIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: part.validationStatus.icon)
                .foregroundStyle(part.validationStatus.color)
            
            if case .suggestion(let file, _) = part.validationStatus {
                Button {
                    onApplySuggestion?(file)
                } label: {
                    Text("Use")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
    }
    
    private var backgroundForStatus: Color {
        switch part.validationStatus {
        case .error:
            return Color.red.opacity(0.1)
        case .warning, .suggestion:
            return Color.orange.opacity(0.1)
        default:
            return Color.secondary.opacity(isHovered ? 0.15 : 0.05)
        }
    }
}

// MARK: - File Thumbnail View

struct FileThumbView: View {
    let file: CabinetFileInfo
    
    var body: some View {
        VStack(spacing: 4) {
            // Thumbnail
            if let nsImage = NSImage(contentsOfFile: file.fullPath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(file.isAssigned ? Color.green : Color.clear, lineWidth: 2)
                    )
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .overlay {
                        Image(systemName: file.fileType.icon)
                            .foregroundStyle(.secondary)
                    }
            }
            
            // Filename
            Text(file.filename)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 70)
            
            // Assignment status
            if file.isAssigned {
                Text(file.assignedToPart ?? "Used")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else {
                Text("Unused")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - Video Config Card

struct VideoConfigCard: View {
    let video: VideoDetail
    let availableVideos: [CabinetFileInfo]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main video info
            HStack(spacing: 12) {
                // Video icon/thumbnail
                videoThumbnail
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(video.file ?? "Unknown")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
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
                    
                    // Transform options
                    if video.invertX || video.invertY {
                        HStack(spacing: 8) {
                            if video.invertX {
                                Label("Flip H", systemImage: "arrow.left.arrow.right")
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.2))
                                    .cornerRadius(4)
                            }
                            if video.invertY {
                                Label("Flip V", systemImage: "arrow.up.arrow.down")
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .padding(8)
            .background(videoBackground)
            .cornerRadius(8)
            
            // Other available videos
            if availableVideos.count > 1 {
                let otherVideos = availableVideos.filter { $0.filename != video.file }
                if !otherVideos.isEmpty {
                    Text("Other videos in folder:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ForEach(otherVideos) { file in
                        HStack {
                            Image(systemName: "film")
                                .foregroundStyle(.secondary)
                            Text(file.filename)
                                .font(.caption)
                            Spacer()
                        }
                        .padding(4)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(4)
                    }
                }
            }
        }
    }
    
    private var videoThumbnail: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.blue.opacity(0.2))
            .frame(width: 60, height: 45)
            .overlay {
                Image(systemName: video.isValid ? "play.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(video.isValid ? .blue : .red)
            }
    }
    
    private var videoBackground: Color {
        if video.validationStatus.isError {
            return Color.red.opacity(0.1)
        }
        return Color.secondary.opacity(0.1)
    }
}

// MARK: - Preview

#Preview {
    let mockDetail = CabinetDetail(path: "/mock/path/1942")
    CabinetDetailView(detail: mockDetail, showMediaInspector: .constant(false))
        .frame(width: 400, height: 600)
}
