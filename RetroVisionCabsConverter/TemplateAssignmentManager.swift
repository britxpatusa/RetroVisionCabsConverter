import SwiftUI

/// Manages per-cabinet template assignments
class TemplateAssignmentManager: ObservableObject {
    @Published var assignments: [String: String] = [:]  // cabinetID -> templateID
    
    private let saveKey = "CabinetTemplateAssignments"
    
    init() {
        load()
    }
    
    /// Get the assigned template ID for a cabinet
    func templateID(for cabinetID: String) -> String? {
        assignments[cabinetID]
    }
    
    /// Assign a template to a cabinet
    func assign(templateID: String, to cabinetID: String) {
        assignments[cabinetID] = templateID
        save()
    }
    
    /// Assign same template to multiple cabinets
    func assignToAll(_ cabinetIDs: [String], templateID: String) {
        for id in cabinetIDs {
            assignments[id] = templateID
        }
        save()
    }
    
    /// Remove assignment for a cabinet
    func removeAssignment(for cabinetID: String) {
        assignments.removeValue(forKey: cabinetID)
        save()
    }
    
    /// Check if cabinet has an assigned template
    func hasAssignment(for cabinetID: String) -> Bool {
        assignments[cabinetID] != nil
    }
    
    /// Get cabinets without assignments
    func unassignedCabinets(from cabinets: [CabinetItem]) -> [CabinetItem] {
        cabinets.filter { !hasAssignment(for: $0.id) }
    }
    
    /// Get cabinets with a specific template
    func cabinets(withTemplate templateID: String, from cabinets: [CabinetItem]) -> [CabinetItem] {
        cabinets.filter { assignments[$0.id] == templateID }
    }
    
    private func save() {
        UserDefaults.standard.set(assignments, forKey: saveKey)
    }
    
    private func load() {
        if let saved = UserDefaults.standard.dictionary(forKey: saveKey) as? [String: String] {
            assignments = saved
        }
    }
}

/// View for assigning templates to cabinets after scan
struct TemplateAssignmentView: View {
    @ObservedObject var assignmentManager: TemplateAssignmentManager
    let cabinets: [CabinetItem]
    let templates: [CabinetTemplate]
    @Binding var isPresented: Bool
    
    @State private var selectedTemplateID: String = "upright"
    @State private var selectAll = false
    @State private var selectedCabinets: Set<String> = []
    @State private var showTemplatePreview = false
    
    var unassignedCabinets: [CabinetItem] {
        assignmentManager.unassignedCabinets(from: cabinets)
    }
    
    var selectedTemplate: CabinetTemplate? {
        templates.first { $0.id == selectedTemplateID }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Assign Cabinet Templates")
                    .font(.headline)
                Spacer()
                Text("\(unassignedCabinets.count) unassigned")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Compact template selector
            HStack(spacing: 16) {
                Text("Template:")
                    .fontWeight(.medium)
                
                // Compact picker with icon
                Picker("", selection: $selectedTemplateID) {
                    ForEach(templates) { template in
                        HStack(spacing: 6) {
                            Image(systemName: iconForTemplate(template.id))
                            Text(template.name)
                        }
                        .tag(template.id)
                    }
                }
                .frame(width: 180)
                
                // Preview button
                Button {
                    showTemplatePreview = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "eye")
                        Text("Preview")
                    }
                }
                .help("View all templates")
                
                Spacer()
                
                Toggle("Select All Unassigned", isOn: $selectAll)
                    .onChange(of: selectAll) { _, newValue in
                        if newValue {
                            selectedCabinets = Set(unassignedCabinets.map { $0.id })
                        } else {
                            selectedCabinets.removeAll()
                        }
                    }
            }
            .padding()
            
            Divider()
            
            // Cabinet list
            List(cabinets, selection: $selectedCabinets) { cabinet in
                HStack {
                    VStack(alignment: .leading) {
                        Text(cabinet.id)
                            .fontWeight(.medium)
                        if let templateID = assignmentManager.templateID(for: cabinet.id),
                           let template = templates.first(where: { $0.id == templateID }) {
                            HStack(spacing: 4) {
                                Image(systemName: iconForTemplate(templateID))
                                    .font(.system(size: 10))
                                Text(template.name)
                            }
                            .font(.caption)
                            .foregroundStyle(.green)
                        } else {
                            Text("No template assigned")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    
                    Spacer()
                }
                .tag(cabinet.id)
            }
            
            Divider()
            
            // Actions
            HStack {
                Button("Clear All Assignments") {
                    for cabinet in cabinets {
                        assignmentManager.removeAssignment(for: cabinet.id)
                    }
                }
                .foregroundStyle(.red)
                
                Spacer()
                
                Text("\(selectedCabinets.count) selected")
                    .foregroundStyle(.secondary)
                
                Button("Assign Template") {
                    assignmentManager.assignToAll(Array(selectedCabinets), templateID: selectedTemplateID)
                    selectedCabinets.removeAll()
                    selectAll = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCabinets.isEmpty)
                
                Button("Done") {
                    isPresented = false
                }
            }
            .padding()
        }
        .frame(minWidth: 500, idealWidth: 650, maxWidth: 800, minHeight: 350, idealHeight: 450, maxHeight: 550)
        .onAppear {
            if let first = templates.first {
                selectedTemplateID = first.id
            }
        }
        .sheet(isPresented: $showTemplatePreview) {
            TemplatePreviewWindow(
                templates: templates,
                selectedTemplateID: $selectedTemplateID,
                isPresented: $showTemplatePreview
            )
        }
    }
    
    /// Get appropriate SF Symbol for template type
    func iconForTemplate(_ templateID: String) -> String {
        switch templateID.lowercased() {
        case "upright": return "arcade.stick.console"
        case "neogeo": return "gamecontroller.fill"
        case "vertical": return "rectangle.portrait.fill"
        case "defender": return "display"
        case "driving": return "car.fill"
        case "flightstick": return "airplane"
        case "lightgun": return "scope"
        case "cocktail": return "tablecells"
        default: return "cube.fill"
        }
    }
}

/// Separate window for template preview
struct TemplatePreviewWindow: View {
    let templates: [CabinetTemplate]
    @Binding var selectedTemplateID: String
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Cabinet Templates")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Template grid
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)
                ], spacing: 16) {
                    ForEach(templates) { template in
                        TemplateSelectionCard(
                            template: template,
                            isSelected: selectedTemplateID == template.id
                        )
                        .onTapGesture {
                            selectedTemplateID = template.id
                        }
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer with selected info
            HStack {
                if let selected = templates.first(where: { $0.id == selectedTemplateID }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Selected: \(selected.name)")
                            .fontWeight(.medium)
                        Text(selected.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Button("Use This Template") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 450, idealWidth: 550, maxWidth: 650, minHeight: 400, idealHeight: 500, maxHeight: 600)
    }
}

/// Visual template selection card with preview and icon
struct TemplateSelectionCard: View {
    let template: CabinetTemplate
    let isSelected: Bool
    
    /// Get appropriate SF Symbol for template type
    var templateIcon: String {
        switch template.id.lowercased() {
        case "upright":
            return "arcade.stick.console"
        case "neogeo":
            return "gamecontroller.fill"
        case "vertical":
            return "rectangle.portrait.fill"
        case "defender":
            return "display"
        case "driving":
            return "car.fill"
        case "flightstick":
            return "airplane"
        case "lightgun":
            return "scope"
        case "cocktail":
            return "tablecells"
        default:
            return "cube.fill"
        }
    }
    
    var body: some View {
        VStack(spacing: 6) {
            // Preview image - prominent
            if let image = template.previewNSImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 100, height: 100)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    )
            }
            
            // Template name
            Text(template.name)
                .font(.caption)
                .fontWeight(isSelected ? .bold : .medium)
                .lineLimit(1)
            
            // Icon underneath
            Image(systemName: templateIcon)
                .font(.system(size: 16))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isSelected ? 2.5 : 1)
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

/// Compact template picker for cabinet list rows
struct CabinetTemplateIndicator: View {
    let cabinetID: String
    let templates: [CabinetTemplate]
    @ObservedObject var assignmentManager: TemplateAssignmentManager
    
    var assignedTemplate: CabinetTemplate? {
        guard let templateID = assignmentManager.templateID(for: cabinetID) else { return nil }
        return templates.first { $0.id == templateID }
    }
    
    /// Get appropriate SF Symbol for template type
    func iconForTemplate(_ templateID: String) -> String {
        switch templateID.lowercased() {
        case "upright": return "arcade.stick.console"
        case "neogeo": return "gamecontroller.fill"
        case "vertical": return "rectangle.portrait.fill"
        case "defender": return "display"
        case "driving": return "car.fill"
        case "flightstick": return "airplane"
        case "lightgun": return "scope"
        case "cocktail": return "tablecells"
        default: return "cube.fill"
        }
    }
    
    var body: some View {
        Menu {
            ForEach(templates) { template in
                Button {
                    assignmentManager.assign(templateID: template.id, to: cabinetID)
                } label: {
                    HStack {
                        Image(systemName: iconForTemplate(template.id))
                        Text(template.name)
                        Spacer()
                        if assignmentManager.templateID(for: cabinetID) == template.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            
            Divider()
            
            Button("Clear", role: .destructive) {
                assignmentManager.removeAssignment(for: cabinetID)
            }
        } label: {
            HStack(spacing: 4) {
                if let template = assignedTemplate {
                    Image(systemName: iconForTemplate(template.id))
                        .font(.system(size: 12))
                    Text(template.name)
                        .font(.caption)
                        .lineLimit(1)
                } else {
                    Image(systemName: "questionmark.square")
                        .foregroundStyle(.orange)
                    Text("None")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.gray.opacity(0.15))
            .cornerRadius(4)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
