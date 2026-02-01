//
//  TemplateMatchView.swift
//  RetroVisionCabsConverter
//
//  UI for template matching and new template creation
//

import SwiftUI

// MARK: - Template Match View

/// Shows template matching results and allows creating new templates
struct TemplateMatchView: View {
    let cabinet: DiscoveredCabinet
    @ObservedObject var templateManager: TemplateManager
    @Binding var selectedTemplateID: String
    var refreshTrigger: UUID = UUID()  // Changes when templates are updated
    let onCreateTemplate: (String, String) -> Void
    
    @State private var matchResults: [TemplateMatchResult] = []
    @State private var isAnalyzing = true
    @State private var showCreateSheet = false
    @State private var newTemplateName = ""
    @State private var newTemplateID = ""
    @State private var newlyCreatedTemplateID: String? = nil  // Track newly created template
    
    var bestMatch: TemplateMatchResult? {
        matchResults.first
    }
    
    var hasGoodMatch: Bool {
        bestMatch?.isGoodMatch ?? false
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Template Matching")
                    .font(.headline)
                
                Spacer()
                
                if isAnalyzing {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Analyzing...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if !isAnalyzing {
                // Dimension info
                if let dims = cabinet.dimensions {
                    HStack(spacing: 16) {
                        dimensionBadge("W", value: dims.width)
                        dimensionBadge("H", value: dims.height)
                        dimensionBadge("D", value: dims.depth)
                    }
                    .padding(.vertical, 4)
                }
                
                // Shape info
                if let shape = cabinet.cabinetShape {
                    HStack(spacing: 8) {
                        Label(shape.type.displayName, systemImage: shapeIcon(for: shape.type))
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.15))
                            .cornerRadius(4)
                        
                        if shape.screenOrientation != .unknown {
                            Text(shape.screenOrientation.rawValue.capitalized)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.purple.opacity(0.15))
                                .cornerRadius(4)
                        }
                        
                        Spacer()
                    }
                }
                
                Divider()
                
                // Match results
                if matchResults.isEmpty {
                    Text("No templates to match against")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(matchResults.prefix(5)) { result in
                                TemplateMatchCard(
                                    result: result,
                                    template: templateManager.template(withId: result.templateID),
                                    isSelected: selectedTemplateID == result.templateID
                                )
                                .onTapGesture {
                                    selectedTemplateID = result.templateID
                                }
                            }
                        }
                    }
                }
                
                // Best match recommendation or create new
                HStack {
                    if let selectedTemplate = templateManager.template(withId: selectedTemplateID) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Using: \(selectedTemplate.name)")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        if let best = bestMatch, best.templateID == selectedTemplateID {
                            Text("(\(Int(best.confidence * 100))% match)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if hasGoodMatch, let best = bestMatch {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Best match: \(best.templateName) (\(Int(best.confidence * 100))%)")
                            .font(.caption)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("No good match found")
                            .font(.caption)
                    }
                    
                    Spacer()
                    
                    Button("Create New Template...") {
                        newTemplateName = cabinet.displayName
                        newTemplateID = cabinet.name.lowercased().replacingOccurrences(of: " ", with: "-")
                        showCreateSheet = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .task {
            await analyzeMatches()
        }
        .onChange(of: refreshTrigger) { _, _ in
            // Re-analyze when templates are refreshed (e.g., after creating a new one)
            Task {
                await analyzeMatches()
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateTemplateSheet(
                cabinet: cabinet,
                templateName: $newTemplateName,
                templateID: $newTemplateID,
                onCreate: { name, id in
                    onCreateTemplate(name, id)
                    showCreateSheet = false
                },
                onCancel: {
                    showCreateSheet = false
                }
            )
        }
    }
    
    private func analyzeMatches() async {
        isAnalyzing = true
        matchResults = await templateManager.matchTemplates(for: cabinet)
        
        // Auto-select best match if confidence is high enough
        if let best = matchResults.first, best.confidence >= 0.6 {
            selectedTemplateID = best.templateID
        }
        
        isAnalyzing = false
    }
    
    private func dimensionBadge(_ label: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(String(format: "%.2f", value))
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(4)
    }
    
    private func shapeIcon(for type: CabinetShape.CabinetType) -> String {
        switch type {
        case .upright: return "arcade.stick.console"
        case .cocktail: return "tablecells"
        case .driving: return "car.fill"
        case .lightgun: return "scope"
        case .flightstick: return "airplane"
        case .neogeo: return "gamecontroller.fill"
        case .pinball: return "circle.grid.3x3"
        case .custom: return "cube.fill"
        }
    }
}

// MARK: - Template Match Card

struct TemplateMatchCard: View {
    let result: TemplateMatchResult
    let template: CabinetTemplate?
    let isSelected: Bool
    
    var confidenceColor: Color {
        switch result.confidence {
        case 0.8...: return .green
        case 0.6..<0.8: return .yellow
        case 0.4..<0.6: return .orange
        default: return .red
        }
    }
    
    var body: some View {
        VStack(spacing: 6) {
            // Preview or icon
            if let image = template?.previewNSImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                    .cornerRadius(4)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "cube.fill")
                            .foregroundStyle(.secondary)
                    )
            }
            
            // Name
            Text(result.templateName)
                .font(.caption)
                .fontWeight(isSelected ? .bold : .medium)
                .lineLimit(1)
            
            // Confidence
            HStack(spacing: 4) {
                Circle()
                    .fill(confidenceColor)
                    .frame(width: 8, height: 8)
                Text("\(Int(result.confidence * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        )
    }
}

// MARK: - Create Template Sheet

struct CreateTemplateSheet: View {
    let cabinet: DiscoveredCabinet
    @Binding var templateName: String
    @Binding var templateID: String
    let onCreate: (String, String) -> Void
    let onCancel: () -> Void
    
    @State private var isCreating = false
    @State private var error: String?
    
    var isValid: Bool {
        !templateName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !templateID.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                // Back/Cancel button
                Button {
                    onCancel()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Cancel")
                    }
                }
                .buttonStyle(.bordered)
                
                Image(systemName: "plus.square.on.square")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .padding(.leading, 12)
                
                VStack(alignment: .leading) {
                    Text("Create New Template")
                        .font(.headline)
                    Text("From: \(cabinet.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Content
            VStack(alignment: .leading, spacing: 16) {
                // Info
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("This will create a reusable template from this cabinet's 3D model", systemImage: "info.circle")
                            .font(.callout)
                        
                        if let dims = cabinet.dimensions {
                            HStack {
                                Text("Dimensions:")
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.2f × %.2f × %.2f", dims.width, dims.height, dims.depth))
                                    .font(.system(.body, design: .monospaced))
                            }
                            .font(.caption)
                        }
                        
                        if let shape = cabinet.cabinetShape {
                            HStack {
                                Text("Type:")
                                    .foregroundStyle(.secondary)
                                Text(shape.type.displayName)
                            }
                            .font(.caption)
                        }
                        
                        Text("Meshes: \(cabinet.glbMeshNames.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(4)
                }
                
                // Name field
                VStack(alignment: .leading, spacing: 4) {
                    Text("Template Name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g., Classic Upright", text: $templateName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: templateName) { _, newValue in
                            // Auto-generate ID from name
                            templateID = newValue.lowercased()
                                .replacingOccurrences(of: " ", with: "-")
                                .filter { $0.isLetter || $0.isNumber || $0 == "-" }
                        }
                }
                
                // ID field
                VStack(alignment: .leading, spacing: 4) {
                    Text("Template ID")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g., classic-upright", text: $templateID)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Text("Used internally and for file naming")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                if let error = error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                
                Spacer()
            }
            .padding()
            
            Divider()
            
            // Footer
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Create Template") {
                    onCreate(templateName.trimmingCharacters(in: .whitespaces),
                            templateID.trimmingCharacters(in: .whitespaces))
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid || isCreating)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 400, idealWidth: 480, maxWidth: 550, minHeight: 350, idealHeight: 420, maxHeight: 500)
    }
}

// MARK: - Template Selection with Auto-Match

/// Wrapper view that shows template picker with auto-matching
struct TemplateSelectionView: View {
    let cabinet: DiscoveredCabinet
    @ObservedObject var templateManager: TemplateManager
    @Binding var selectedTemplateID: String
    
    @State private var showMatchDetails = false
    @State private var isCreatingTemplate = false
    @State private var creationError: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Auto-match section
            TemplateMatchView(
                cabinet: cabinet,
                templateManager: templateManager,
                selectedTemplateID: $selectedTemplateID,
                onCreateTemplate: { name, id in
                    createTemplate(name: name, id: id)
                }
            )
            
            // Manual template picker
            if !templateManager.templates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Or select manually:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(templateManager.templates) { template in
                                TemplatePickerCard(
                                    template: template,
                                    isSelected: selectedTemplateID == template.id
                                )
                                .onTapGesture {
                                    selectedTemplateID = template.id
                                }
                            }
                        }
                    }
                }
            }
            
            if isCreatingTemplate {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Creating template...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if let error = creationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
    
    private func createTemplate(name: String, id: String) {
        isCreatingTemplate = true
        creationError = nil
        
        Task {
            do {
                let newTemplate = try await templateManager.createTemplate(from: cabinet, name: name, id: id)
                await MainActor.run {
                    selectedTemplateID = newTemplate.id
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
