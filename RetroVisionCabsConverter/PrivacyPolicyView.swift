//
//  PrivacyPolicyView.swift
//  RetroVisionCabsConverter
//
//  In-app privacy policy display
//

import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Privacy Policy")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape)
            }
            .padding()
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Last Updated
                    Text("Last Updated: January 30, 2026")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // Summary Section
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Your Privacy Summary", systemImage: "checkmark.shield.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                PrivacySummaryRow(icon: "checkmark.circle.fill", text: "All data processed locally on your device", isPositive: true)
                                PrivacySummaryRow(icon: "checkmark.circle.fill", text: "No personal information collected", isPositive: true)
                                PrivacySummaryRow(icon: "checkmark.circle.fill", text: "No analytics or tracking", isPositive: true)
                                PrivacySummaryRow(icon: "checkmark.circle.fill", text: "No internet access required", isPositive: true)
                                PrivacySummaryRow(icon: "checkmark.circle.fill", text: "No data shared with third parties", isPositive: true)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // Information We Don't Collect
                    PrivacySection(
                        title: "Information We Do NOT Collect",
                        icon: "hand.raised.fill",
                        items: [
                            "No personal data collection",
                            "No analytics services or tracking",
                            "No account required",
                            "No network transmission of your data",
                            "No advertisements"
                        ]
                    )
                    
                    // Local Data
                    PrivacySection(
                        title: "Information Stored Locally",
                        icon: "internaldrive.fill",
                        items: [
                            "Cabinet asset files (3D models, images, videos)",
                            "Converted output files (USDZ, Swift code)",
                            "Temporary processing files",
                            "User preferences (folder paths, settings)"
                        ]
                    )
                    
                    // Third Party Tools
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Third-Party Tools", systemImage: "puzzlepiece.fill")
                                .font(.headline)
                            
                            Text("The app uses these tools, which you install separately:")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                ThirdPartyToolRow(name: "Blender", url: "blender.org", description: "3D model conversion")
                                ThirdPartyToolRow(name: "FFmpeg", url: "ffmpeg.org", description: "Video conversion")
                                ThirdPartyToolRow(name: "Python", url: "python.org", description: "Script execution")
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // File Access
                    PrivacySection(
                        title: "File System Access",
                        icon: "folder.fill",
                        items: [
                            "User-selected folders only",
                            "External volumes (when you choose)",
                            "Temporary directories for processing",
                            "All access is user-initiated"
                        ]
                    )
                    
                    // Data Security
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Data Security", systemImage: "lock.shield.fill")
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("• All processing occurs locally on your device")
                                Text("• No data is transmitted over the internet")
                                Text("• Temporary files are created with appropriate permissions")
                                Text("• ZIP files are validated before extraction")
                            }
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // Contact
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Contact", systemImage: "envelope.fill")
                                .font(.headline)
                            
                            Text("Questions about this privacy policy?")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            
                            Link(destination: URL(string: "mailto:support@RetroVision.pro")!) {
                                Text("support@RetroVision.pro")
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()
        }
        .frame(width: 550, height: 650)
    }
}

// MARK: - Supporting Views

private struct PrivacySummaryRow: View {
    let icon: String
    let text: String
    let isPositive: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(isPositive ? .green : .red)
            Text(text)
                .font(.callout)
        }
    }
}

private struct PrivacySection: View {
    let title: String
    let icon: String
    let items: [String]
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: icon)
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                            Text(item)
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

private struct ThirdPartyToolRow: View {
    let name: String
    let url: String
    let description: String
    
    var body: some View {
        HStack {
            Text("•")
            Text(name)
                .fontWeight(.medium)
            Text("-")
            Text(description)
                .foregroundStyle(.secondary)
            Spacer()
            Link(url, destination: URL(string: "https://\(url)")!)
                .font(.caption)
        }
        .font(.callout)
    }
}

// MARK: - Preview

#Preview {
    PrivacyPolicyView()
}
