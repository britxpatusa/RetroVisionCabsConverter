//
//  PropGalleryCard.swift
//  RetroVisionCabsConverter
//
//  Individual prop card for the gallery grid
//

import SwiftUI

struct PropGalleryCard: View {
    let prop: DiscoveredProp
    let isSelected: Bool
    var isSaved: Bool = false
    let onSelect: () -> Void
    let onDetail: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 8) {
            // Preview area
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.15))
                
                // Preview image or placeholder
                if let preview = prop.previewImage {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(6)
                        .padding(4)
                } else if prop.previewGenerated {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text("Preview failed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack {
                        Image(systemName: prop.propType.icon)
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text(prop.propType.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Overlay badges
                VStack {
                    HStack {
                        // Video badge
                        if prop.hasVideo {
                            HStack(spacing: 3) {
                                Image(systemName: "video.fill")
                                    .font(.caption2)
                                Text("Video")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.9))
                            .cornerRadius(8)
                            .padding(6)
                        }
                        
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
                        
                        // Selection checkbox
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
            .frame(height: 180)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
            
            // Info section
            VStack(spacing: 4) {
                Text(prop.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                // Type and placement badges
                HStack(spacing: 6) {
                    // Type badge
                    HStack(spacing: 3) {
                        Image(systemName: prop.propType.icon)
                            .font(.system(size: 9))
                        Text(prop.propType.displayName)
                            .font(.caption2)
                    }
                    .foregroundStyle(typeColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(typeColor.opacity(0.15))
                    .cornerRadius(4)
                    
                    // Placement badge
                    HStack(spacing: 3) {
                        Image(systemName: placementIcon)
                            .font(.system(size: 9))
                        Text(prop.placement.displayName)
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                
                // Dimensions
                if let dims = prop.dimensions {
                    Text(dims.displayString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
    
    private var placementIcon: String {
        switch prop.placement {
        case .wall: return "rectangle.portrait.on.rectangle.portrait"
        case .floor: return "square.on.square"
        case .ceiling: return "square.on.square.dashed"
        case .corner: return "square.bottomhalf.filled"
        case .center: return "dot.square"
        case .table: return "tablecells"
        case .freestanding: return "square.stack.3d.up"
        }
    }
}

// MARK: - Preview

#Preview {
    HStack {
        PropGalleryCard(
            prop: {
                var p = DiscoveredProp(
                    id: "cutout1",
                    name: "drwho-cutout",
                    displayName: "Dr. Who Cutout",
                    sourcePath: URL(fileURLWithPath: "/test"),
                    sourceType: .folder
                )
                p.propType = .cutout
                p.placement = .wall
                p.videoInfo = PropVideoInfo(file: URL(fileURLWithPath: "/test.mp4"), format: "mp4", needsConversion: false)
                p.dimensions = PropDimensions(width: 1.2, height: 2.0, depth: 0.1)
                return p
            }(),
            isSelected: false,
            isSaved: false,
            onSelect: {},
            onDetail: {}
        )
        
        PropGalleryCard(
            prop: {
                var p = DiscoveredProp(
                    id: "disco",
                    name: "discostage",
                    displayName: "Disco Stage",
                    sourcePath: URL(fileURLWithPath: "/test"),
                    sourceType: .folder
                )
                p.propType = .stage
                p.placement = .floor
                p.dimensions = PropDimensions(width: 3.0, height: 1.5, depth: 2.0)
                return p
            }(),
            isSelected: true,
            isSaved: true,
            onSelect: {},
            onDetail: {}
        )
    }
    .padding()
    .frame(width: 500)
}
