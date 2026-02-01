//
//  CreatePropTemplateSheet.swift
//  RetroVisionCabsConverter
//
//  UI for creating prop templates from discovered props
//

import SwiftUI

struct CreatePropTemplateSheet: View {
    let prop: DiscoveredProp
    let onSave: (PropTemplate?) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var templateName: String
    @State private var selectedType: PropType
    @State private var selectedPlacement: PlacementHint
    @State private var tags: String
    @State private var author: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    init(prop: DiscoveredProp, onSave: @escaping (PropTemplate?) -> Void) {
        self.prop = prop
        self.onSave = onSave
        _templateName = State(initialValue: prop.displayName)
        _selectedType = State(initialValue: prop.propType)
        _selectedPlacement = State(initialValue: prop.placement)
        _tags = State(initialValue: prop.tags.joined(separator: ", "))
        _author = State(initialValue: prop.author ?? "")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    dismiss()
                    onSave(nil)
                } label: {
                    Label("Cancel", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Text("Create Prop Template")
                    .font(.headline)
                
                Spacer()
                
                Button("Save") {
                    saveTemplate()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(templateName.isEmpty || isSaving)
            }
            .padding()
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 20) {
                    // Preview
                    HStack(spacing: 20) {
                        if let preview = prop.previewImage {
                            Image(nsImage: preview)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 150, height: 150)
                                .cornerRadius(8)
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 150, height: 150)
                                .overlay {
                                    Image(systemName: "cube.transparent")
                                        .font(.system(size: 40))
                                        .foregroundStyle(.secondary)
                                }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Source: \(prop.name)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            if let glb = prop.glbFile {
                                Text("Model: \(glb.lastPathComponent)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Text("Meshes: \(prop.glbMeshNames.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            if prop.videoInfo != nil {
                                Label("Has Video", systemImage: "play.rectangle.fill")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            
                            Text("Dimensions: \(formatDimensions(prop.dimensions))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    
                    // Template Settings
                    GroupBox("Template Settings") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Name:")
                                    .frame(width: 80, alignment: .trailing)
                                TextField("Template name", text: $templateName)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            HStack {
                                Text("Type:")
                                    .frame(width: 80, alignment: .trailing)
                                Picker("", selection: $selectedType) {
                                    ForEach(PropType.allCases, id: \.self) { type in
                                        Text(type.rawValue.capitalized).tag(type)
                                    }
                                }
                                .labelsHidden()
                            }
                            
                            HStack {
                                Text("Placement:")
                                    .frame(width: 80, alignment: .trailing)
                                Picker("", selection: $selectedPlacement) {
                                    ForEach(PlacementHint.allCases, id: \.self) { hint in
                                        Text(hint.rawValue.capitalized).tag(hint)
                                    }
                                }
                                .labelsHidden()
                            }
                            
                            HStack {
                                Text("Author:")
                                    .frame(width: 80, alignment: .trailing)
                                TextField("Author name", text: $author)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            HStack {
                                Text("Tags:")
                                    .frame(width: 80, alignment: .trailing)
                                TextField("Comma-separated tags", text: $tags)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // Mesh Mappings
                    GroupBox("Mesh Mappings (\(prop.meshMappings.count))") {
                        if prop.meshMappings.isEmpty {
                            Text("No texture mappings defined")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(prop.meshMappings.keys.sorted()), id: \.self) { mesh in
                                    HStack {
                                        Text(mesh)
                                            .font(.system(.caption, design: .monospaced))
                                        Spacer()
                                        Text("→")
                                            .foregroundStyle(.secondary)
                                        Text(prop.meshMappings[mesh] ?? "")
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    
                    // All Meshes
                    GroupBox("All Meshes (\(prop.glbMeshNames.count))") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(prop.glbMeshNames, id: \.self) { mesh in
                                    Text(mesh)
                                        .font(.system(.caption2, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.2))
                                        .cornerRadius(4)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    
                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                .padding()
            }
            
            // Footer
            Divider()
            
            HStack {
                Text("Template will be saved to Resources/PropTemplates/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .frame(width: 500, height: 650)
    }
    
    private func saveTemplate() {
        isSaving = true
        errorMessage = nil
        
        // Update prop with edited values
        var modifiedProp = prop
        modifiedProp.propType = selectedType
        modifiedProp.placement = selectedPlacement
        modifiedProp.author = author.isEmpty ? nil : author
        modifiedProp.tags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        // Temporarily set displayName for template creation
        // The template manager will use the provided name
        
        if let template = PropsTemplateManager.shared.createTemplate(from: modifiedProp, preview: prop.previewImage) {
            dismiss()
            onSave(template)
        } else {
            errorMessage = "Failed to create template"
        }
        
        isSaving = false
    }
    
    private func formatDimensions(_ dims: PropDimensions?) -> String {
        guard let d = dims else { return "Unknown" }
        return String(format: "%.1f × %.1f × %.1f m", d.width, d.height, d.depth)
    }
}

// MARK: - Prop Type Selection View

struct PropTypeSelector: View {
    @Binding var selectedType: PropType
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prop Type")
                .font(.headline)
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                ForEach(PropType.allCases, id: \.self) { type in
                    Button {
                        selectedType = type
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: iconFor(type))
                                .font(.title2)
                            Text(type.rawValue.capitalized)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selectedType == type ? Color.accentColor.opacity(0.2) : Color.clear)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedType == type ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private func iconFor(_ type: PropType) -> String {
        type.icon
    }
}
