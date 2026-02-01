import SwiftUI

// MARK: - Cabinet Gallery Card

/// Individual cabinet card for the gallery grid
struct CabinetGalleryCard: View {
    let cabinet: DiscoveredCabinet
    let isSelected: Bool
    var isSaved: Bool = false
    let onSelect: () -> Void
    let onDetail: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 8) {
            // Preview image area
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.15))
                
                // Preview image or placeholder
                if let preview = cabinet.previewImage {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(6)
                        .padding(4)
                } else if cabinet.previewGenerated {
                    // Failed to generate
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text("Preview failed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // Generating
                    VStack {
                        ProgressView()
                        Text("Generating...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Selection checkbox and saved badge overlay
                VStack {
                    HStack {
                        // Saved badge
                        if isSaved {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                Text("Saved")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.9))
                            .cornerRadius(8)
                            .padding(6)
                        }
                        
                        Spacer()
                        
                        Button {
                            onSelect()
                        } label: {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundStyle(isSelected ? .white : .gray)
                                .background(
                                    Circle()
                                        .fill(isSelected ? Color.accentColor : Color.black.opacity(0.5))
                                        .frame(width: 26, height: 26)
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                    }
                    Spacer()
                }
                
                // Hover overlay
                if isHovered {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.3))
                    
                    Button {
                        onDetail()
                    } label: {
                        Label("View Details", systemImage: "info.circle")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.9))
                            .foregroundStyle(.primary)
                            .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 200)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
            
            // Cabinet info
            VStack(spacing: 4) {
                Text(cabinet.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                // Completeness bar
                HStack(spacing: 4) {
                    ProgressView(value: cabinet.completenessScore)
                        .tint(completenessColor)
                        .frame(height: 4)
                    
                    Text("\(Int(cabinet.completenessScore * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
                
                // Template badge
                HStack(spacing: 4) {
                    Image(systemName: templateIcon)
                        .font(.system(size: 9))
                    Text(cabinet.suggestedTemplateID.capitalized)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: isSelected ? 2 : 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
    
    private var completenessColor: Color {
        switch cabinet.completenessScore {
        case 1.0: return .green
        case 0.75...: return .yellow
        case 0.5...: return .orange
        default: return .red
        }
    }
    
    private var templateIcon: String {
        switch cabinet.suggestedTemplateID.lowercased() {
        case "upright": return "arcade.stick.console"
        case "neogeo": return "gamecontroller.fill"
        case "vertical": return "rectangle.portrait.fill"
        case "driving": return "car.fill"
        case "flightstick": return "airplane"
        case "lightgun": return "scope"
        case "cocktail": return "tablecells"
        default: return "cube.fill"
        }
    }
}

// MARK: - Preview

#Preview {
    HStack {
        CabinetGalleryCard(
            cabinet: DiscoveredCabinet(
                id: "galaga",
                name: "galaga",
                displayName: "Galaga",
                sourcePath: URL(fileURLWithPath: "/test"),
                sourceType: .folder
            ),
            isSelected: false,
            isSaved: false,
            onSelect: {},
            onDetail: {}
        )
        
        CabinetGalleryCard(
            cabinet: DiscoveredCabinet(
                id: "pacman",
                name: "pacman",
                displayName: "Pac-Man",
                sourcePath: URL(fileURLWithPath: "/test"),
                sourceType: .zip
            ),
            isSelected: true,
            isSaved: true,
            onSelect: {},
            onDetail: {}
        )
    }
    .padding()
    .frame(width: 400)
}
