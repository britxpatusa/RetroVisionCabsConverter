//
//  PropEditSheet.swift
//  RetroVisionCabsConverter
//
//  Edit prop properties like name, type, placement, etc.
//

import SwiftUI

struct PropEditSheet: View {
    @Binding var prop: DiscoveredProp
    let onSave: () -> Void
    let onCancel: () -> Void
    
    @State private var editedName: String
    @State private var editedType: PropType
    @State private var editedPlacement: PlacementHint
    @State private var editedAuthor: String
    @State private var editedTags: String
    @State private var editedMeshMappings: [EditableMeshMapping]
    
    init(prop: Binding<DiscoveredProp>, onSave: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self._prop = prop
        self.onSave = onSave
        self.onCancel = onCancel
        
        let p = prop.wrappedValue
        _editedName = State(initialValue: p.displayName)
        _editedType = State(initialValue: p.propType)
        _editedPlacement = State(initialValue: p.placement)
        _editedAuthor = State(initialValue: p.author ?? "")
        _editedTags = State(initialValue: p.tags.joined(separator: ", "))
        _editedMeshMappings = State(initialValue: p.glbMeshNames.map { mesh in
            EditableMeshMapping(
                meshName: mesh,
                textureFile: p.meshMappings[mesh] ?? "",
                isEnabled: p.meshMappings[mesh] != nil
            )
        })
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Basic Info
                    basicInfoSection
                    
                    // Type & Placement
                    typeSection
                    
                    // Mesh Mappings
                    meshMappingsSection
                    
                    // Video Info (read-only)
                    if prop.videoInfo != nil {
                        videoInfoSection
                    }
                }
                .padding(20)
            }
            
            Divider()
            
            // Footer
            footerView
        }
        .frame(width: 600, height: 700)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Button {
                onCancel()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Cancel")
                }
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.escape)
            
            Spacer()
            
            Text("Edit Prop")
                .font(.headline)
            
            Spacer()
            
            Button("Save Changes") {
                saveChanges()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding()
    }
    
    // MARK: - Basic Info
    
    private var basicInfoSection: some View {
        GroupBox("Basic Information") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Display Name:")
                        .frame(width: 100, alignment: .trailing)
                    TextField("Prop name", text: $editedName)
                        .textFieldStyle(.roundedBorder)
                }
                
                HStack {
                    Text("Author:")
                        .frame(width: 100, alignment: .trailing)
                    TextField("Author name", text: $editedAuthor)
                        .textFieldStyle(.roundedBorder)
                }
                
                HStack {
                    Text("Tags:")
                        .frame(width: 100, alignment: .trailing)
                    TextField("Comma-separated tags", text: $editedTags)
                        .textFieldStyle(.roundedBorder)
                }
                
                HStack {
                    Text("Source:")
                        .frame(width: 100, alignment: .trailing)
                    Text(prop.sourcePath.lastPathComponent)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Type Section
    
    private var typeSection: some View {
        GroupBox("Classification") {
            VStack(alignment: .leading, spacing: 16) {
                // Type picker with icons
                VStack(alignment: .leading, spacing: 8) {
                    Text("Prop Type")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 8) {
                        ForEach(PropType.allCases, id: \.self) { type in
                            Button {
                                editedType = type
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: type.icon)
                                        .font(.title3)
                                    Text(type.displayName)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(editedType == type ? Color.accentColor.opacity(0.2) : Color.clear)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(editedType == type ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Divider()
                
                // Placement picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Placement Hint")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 8) {
                        ForEach(PlacementHint.allCases, id: \.self) { placement in
                            Button {
                                editedPlacement = placement
                            } label: {
                                Text(placement.displayName)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(editedPlacement == placement ? Color.accentColor : Color.gray.opacity(0.2))
                                    .foregroundColor(editedPlacement == placement ? .white : .primary)
                                    .cornerRadius(16)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Mesh Mappings
    
    private var meshMappingsSection: some View {
        GroupBox("Mesh Texture Mappings") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Map textures to mesh names in the 3D model")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if editedMeshMappings.isEmpty {
                    Text("No meshes found in model")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach($editedMeshMappings) { $mapping in
                        HStack(spacing: 12) {
                            Toggle("", isOn: $mapping.isEnabled)
                                .labelsHidden()
                            
                            Text(mapping.meshName)
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 150, alignment: .leading)
                            
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                            
                            if mapping.isEnabled {
                                Picker("Texture", selection: $mapping.textureFile) {
                                    Text("None").tag("")
                                    ForEach(availableTextures, id: \.self) { texture in
                                        Text(texture).tag(texture)
                                    }
                                }
                                .labelsHidden()
                            } else {
                                Text("Not mapped")
                                    .foregroundStyle(.tertiary)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Video Info
    
    private var videoInfoSection: some View {
        GroupBox("Video Information") {
            if let video = prop.videoInfo {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("File:", systemImage: "film")
                            .frame(width: 100, alignment: .leading)
                        Text(video.file.lastPathComponent)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Label("Format:", systemImage: "doc")
                            .frame(width: 100, alignment: .leading)
                        Text(video.format)
                            .foregroundStyle(.secondary)
                        
                        if video.isVisionOSCompatible {
                            Label("VisionOS Ready", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        } else {
                            Label("Needs Conversion", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            // Reset button
            Button {
                resetToOriginal()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            if hasChanges {
                Text("Unsaved changes")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
    }
    
    // MARK: - Helpers
    
    private var availableTextures: [String] {
        prop.textureFiles.map { $0.lastPathComponent }
    }
    
    private var hasChanges: Bool {
        editedName != prop.displayName ||
        editedType != prop.propType ||
        editedPlacement != prop.placement ||
        editedAuthor != (prop.author ?? "") ||
        editedTags != prop.tags.joined(separator: ", ")
    }
    
    private func saveChanges() {
        prop.displayName = editedName
        prop.propType = editedType
        prop.placement = editedPlacement
        prop.author = editedAuthor.isEmpty ? nil : editedAuthor
        prop.tags = editedTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        // Update mesh mappings
        prop.meshMappings = [:]
        for mapping in editedMeshMappings where mapping.isEnabled && !mapping.textureFile.isEmpty {
            prop.meshMappings[mapping.meshName] = mapping.textureFile
        }
        
        onSave()
    }
    
    private func resetToOriginal() {
        editedName = prop.displayName
        editedType = prop.propType
        editedPlacement = prop.placement
        editedAuthor = prop.author ?? ""
        editedTags = prop.tags.joined(separator: ", ")
        editedMeshMappings = prop.glbMeshNames.map { mesh in
            EditableMeshMapping(
                meshName: mesh,
                textureFile: prop.meshMappings[mesh] ?? "",
                isEnabled: prop.meshMappings[mesh] != nil
            )
        }
    }
}

// MARK: - Editable Mesh Mapping

struct EditableMeshMapping: Identifiable {
    let id = UUID()
    var meshName: String
    var textureFile: String
    var isEnabled: Bool
}

// MARK: - Video Export Options View

struct VideoExportOptionsView: View {
    @Binding var codec: VisionOSPropExporter.ExportOptions.VideoCodec
    @Binding var quality: VisionOSPropExporter.ExportOptions.VideoQuality
    
    var body: some View {
        GroupBox("Video Conversion Options") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Codec:")
                        .frame(width: 80, alignment: .trailing)
                    
                    Picker("", selection: $codec) {
                        ForEach(VisionOSPropExporter.ExportOptions.VideoCodec.allCases, id: \.self) { c in
                            Text(c.rawValue).tag(c)
                        }
                    }
                    .labelsHidden()
                    
                    codecBadge
                }
                
                HStack {
                    Text("Quality:")
                        .frame(width: 80, alignment: .trailing)
                    
                    Picker("", selection: $quality) {
                        ForEach(VisionOSPropExporter.ExportOptions.VideoQuality.allCases, id: \.self) { q in
                            Text(q.rawValue).tag(q)
                        }
                    }
                    .labelsHidden()
                }
                
                // Info text
                Text(codecDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(.vertical, 8)
        }
    }
    
    @ViewBuilder
    private var codecBadge: some View {
        switch codec {
        case .hevc:
            Label("Recommended", systemImage: "star.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .h264:
            Label("Compatible", systemImage: "checkmark")
                .font(.caption)
                .foregroundStyle(.blue)
        case .prores:
            Label("Large Files", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
    
    private var codecDescription: String {
        switch codec {
        case .hevc:
            return "HEVC (H.265) offers the best compression and quality for VisionOS. Hardware-accelerated on Apple Silicon."
        case .h264:
            return "H.264 is widely compatible but produces larger files than HEVC for the same quality."
        case .prores:
            return "ProRes provides the highest quality but creates very large files. Best for archival or editing."
        }
    }
}
