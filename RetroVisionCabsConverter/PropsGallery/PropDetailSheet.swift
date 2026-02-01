//
//  PropDetailSheet.swift
//  RetroVisionCabsConverter
//
//  Detailed view of a prop with preview and metadata
//

import SwiftUI
import SceneKit
import AVKit

struct PropDetailSheet: View {
    let prop: DiscoveredProp
    let onClose: () -> Void
    
    @State private var showFullscreen3D = false
    @State private var showVideoPlayer = false
    @State private var showCreateTemplate = false
    @State private var showEditSheet = false
    @State private var showExportSheet = false
    @State private var editableProp: DiscoveredProp
    
    init(prop: DiscoveredProp, onClose: @escaping () -> Void) {
        self.prop = prop
        self.onClose = onClose
        _editableProp = State(initialValue: prop)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content
            HStack(alignment: .top, spacing: 24) {
                // Preview section
                previewSection
                
                // Details panel
                detailsPanel
            }
            .padding(20)
            
            Divider()
            
            // Footer
            footerView
        }
        .frame(minWidth: 700, idealWidth: 850, maxWidth: 1000, minHeight: 500, idealHeight: 650, maxHeight: 800)
        .sheet(isPresented: $showFullscreen3D) {
            PropFullscreen3DViewer(
                prop: prop,
                glbURL: prop.glbFile,
                onClose: { showFullscreen3D = false }
            )
        }
        .sheet(isPresented: $showVideoPlayer) {
            PropVideoPlayerSheet(
                prop: prop,
                videoURL: prop.videoInfo?.file,
                onClose: { showVideoPlayer = false }
            )
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
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
                Text(prop.displayName)
                    .font(.title)
                    .fontWeight(.bold)
                
                HStack(spacing: 16) {
                    // Type badge
                    Label(prop.propType.displayName, systemImage: prop.propType.icon)
                        .foregroundStyle(typeColor)
                    
                    // Placement
                    Label(prop.placement.displayName, systemImage: "location")
                        .foregroundStyle(.secondary)
                    
                    if let author = prop.author {
                        Label(author, systemImage: "person")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }
            .padding(.leading, 12)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Preview Section
    
    private var previewSection: some View {
        VStack(spacing: 12) {
            // Preview image
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(nsColor: .controlBackgroundColor))
                
                if let preview = prop.previewImage {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(12)
                        .padding(8)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: prop.propType.icon)
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        Text("No preview available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Video badge overlay
                if prop.hasVideo {
                    VStack {
                        HStack {
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "video.fill")
                                Text("Video")
                            }
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.blue)
                            .cornerRadius(8)
                            .padding(12)
                        }
                        Spacer()
                    }
                }
            }
            .frame(minWidth: 300, idealWidth: 380, maxWidth: 450, minHeight: 300, idealHeight: 380, maxHeight: 450)
            .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
            
            // Action buttons
            HStack(spacing: 12) {
                if prop.glbFile != nil {
                    Button {
                        showFullscreen3D = true
                    } label: {
                        Label("View 3D Model", systemImage: "rotate.3d")
                    }
                    .buttonStyle(.bordered)
                }
                
                if prop.hasVideo {
                    Button {
                        showVideoPlayer = true
                    } label: {
                        Label("Play Video", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
    
    // MARK: - Details Panel
    
    private var detailsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Dimensions
                if let dims = prop.dimensions {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Dimensions", systemImage: "ruler")
                                .font(.headline)
                            
                            HStack(spacing: 16) {
                                dimensionItem("Width", dims.width)
                                dimensionItem("Height", dims.height)
                                dimensionItem("Depth", dims.depth)
                            }
                            
                            if dims.isFlat {
                                Label("Flat/Panel", systemImage: "rectangle.portrait")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
                
                // Video info
                if let video = prop.videoInfo {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Video", systemImage: "video")
                                .font(.headline)
                            
                            HStack {
                                Text("Format:")
                                    .foregroundStyle(.secondary)
                                Text(video.formatDisplayName)
                                    .fontWeight(.medium)
                                
                                if !video.isVisionOSCompatible {
                                    Label("Needs conversion", systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                } else {
                                    Label("VisionOS Compatible", systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }
                            .font(.caption)
                            
                            Text(video.file.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Audio info
                if prop.hasAudio {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Audio", systemImage: "speaker.wave.2")
                                .font(.headline)
                            
                            ForEach(prop.audioFiles, id: \.path) { audio in
                                Text(audio.lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                // Assets
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Assets", systemImage: "folder")
                            .font(.headline)
                        
                        // Model
                        if let glb = prop.glbFile {
                            HStack {
                                Image(systemName: "cube.fill")
                                    .foregroundStyle(.blue)
                                Text(glb.lastPathComponent)
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                            .font(.caption)
                        }
                        
                        // Textures
                        if !prop.textureFiles.isEmpty {
                            Divider()
                            ForEach(prop.textureFiles.prefix(5), id: \.path) { texture in
                                HStack {
                                    Image(systemName: "photo")
                                        .foregroundStyle(.purple)
                                    Text(texture.lastPathComponent)
                                    Spacer()
                                }
                                .font(.caption)
                            }
                            if prop.textureFiles.count > 5 {
                                Text("+ \(prop.textureFiles.count - 5) more...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        // Mesh names
                        if !prop.glbMeshNames.isEmpty {
                            Divider()
                            Text("Meshes: \(prop.glbMeshNames.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            ForEach(prop.glbMeshNames.prefix(5), id: \.self) { mesh in
                                Text("• \(mesh)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                // Tags
                if !prop.tags.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Tags", systemImage: "tag")
                                .font(.headline)
                            
                            FlowLayout(spacing: 6) {
                                ForEach(prop.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.gray.opacity(0.2))
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 250, idealWidth: 320, maxWidth: 400)
    }
    
    private func dimensionItem(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(String(format: "%.2f m", value))
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
        }
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            // Source info
            HStack(spacing: 4) {
                Image(systemName: prop.sourceType == .zip ? "doc.zipper" : "folder")
                Text(prop.sourcePath.lastPathComponent)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            
            Spacer()
            
            Button {
                showEditSheet = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .buttonStyle(.bordered)
            
            Button {
                showExportSheet = true
            } label: {
                Label("Export for VisionOS", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            
            Button {
                showCreateTemplate = true
            } label: {
                Label("Create Template", systemImage: "doc.badge.plus")
            }
            .buttonStyle(.bordered)
            
            Button("Done") {
                onClose()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .sheet(isPresented: $showCreateTemplate) {
            CreatePropTemplateSheet(prop: editableProp) { template in
                if let t = template {
                    print("Created template: \(t.name)")
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            PropEditSheet(prop: $editableProp) {
                showEditSheet = false
            } onCancel: {
                showEditSheet = false
            }
        }
        .sheet(isPresented: $showExportSheet) {
            PropExportSheet(prop: editableProp) {
                showExportSheet = false
            }
        }
    }
    
    private var typeColor: Color {
        switch prop.propType {
        case .cutout: return .purple
        case .stage: return .orange
        case .decoration: return .blue
        case .videoDisplay: return .cyan
        case .furniture: return .brown
        case .lighting: return .yellow
        case .wall: return .pink
        case .floor: return .mint
        case .unknown: return .gray
        }
    }
}

// MARK: - Flow Layout for Tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return CGSize(width: proposal.width ?? 0, height: result.height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var positions: [CGPoint] = []
        var height: CGFloat = 0
        
        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var maxHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > width && x > 0 {
                    x = 0
                    y += maxHeight + spacing
                    maxHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                maxHeight = max(maxHeight, size.height)
                x += size.width + spacing
            }
            
            height = y + maxHeight
        }
    }
}

// MARK: - Fullscreen 3D Viewer

struct PropFullscreen3DViewer: View {
    let prop: DiscoveredProp
    let glbURL: URL?
    let onClose: () -> Void
    
    @State private var scene: SCNScene?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
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
                
                VStack(alignment: .leading) {
                    Text(prop.displayName)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Drag to rotate • Scroll to zoom")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 12)
                
                Spacer()
                
                if let glbURL = glbURL {
                    Button {
                        NSWorkspace.shared.open(glbURL)
                    } label: {
                        Label("Open in Finder", systemImage: "folder")
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
                        Text("Loading 3D model...")
                            .font(.headline)
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
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let scene = scene {
                    GallerySceneView(scene: scene)
                }
            }
        }
        .frame(minWidth: 700, idealWidth: 900, maxWidth: 1200, minHeight: 500, idealHeight: 700, maxHeight: 900)
        .onAppear {
            loadModel()
        }
    }
    
    private func loadModel() {
        guard let glbURL = glbURL else {
            errorMessage = "No 3D model file available"
            isLoading = false
            return
        }
        
        Task.detached {
            // Convert GLB to USDZ using Blender
            let configPaths = RetroVisionPaths.load()
            let tempDir = URL(fileURLWithPath: configPaths.viewerTempDir)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let outputPath = tempDir.appendingPathComponent("prop_\(UUID().uuidString).usdz")
            
            let script = """
            import bpy
            
            bpy.ops.object.select_all(action='SELECT')
            bpy.ops.object.delete()
            
            bpy.ops.import_scene.gltf(filepath='\(glbURL.path)')
            
            bpy.ops.wm.usd_export(
                filepath='\(outputPath.path)',
                export_materials=True,
                evaluation_mode='RENDER'
            )
            """
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/Applications/Blender.app/Contents/MacOS/Blender")
            process.arguments = ["-b", "--factory-startup", "--python-expr", script]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            
            do {
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: outputPath.path) {
                    let loadedScene = try SCNScene(url: outputPath, options: [.checkConsistency: true])
                    loadedScene.background.contents = NSColor(calibratedRed: 0.1, green: 0.12, blue: 0.15, alpha: 1.0)
                    
                    await MainActor.run {
                        self.scene = loadedScene
                        self.isLoading = false
                    }
                } else {
                    await MainActor.run {
                        self.errorMessage = "Conversion failed"
                        self.isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Video Player Sheet

struct PropVideoPlayerSheet: View {
    let prop: DiscoveredProp
    let videoURL: URL?
    let onClose: () -> Void
    
    @State private var player: AVPlayer?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    player?.pause()
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
                    Text("\(prop.displayName) - Video")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if let video = prop.videoInfo {
                        HStack(spacing: 12) {
                            Text(video.file.lastPathComponent)
                            Text(video.formatDisplayName)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(video.isVisionOSCompatible ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                                .cornerRadius(4)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 12)
                
                Spacer()
            }
            .padding()
            
            Divider()
            
            // Video player
            if let url = videoURL, let player = player {
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    Text("Video not available")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 600, idealWidth: 800, maxWidth: 1200, minHeight: 400, idealHeight: 600, maxHeight: 900)
        .onAppear {
            if let url = videoURL {
                player = AVPlayer(url: url)
                player?.play()
            }
        }
        .onDisappear {
            player?.pause()
        }
    }
}
