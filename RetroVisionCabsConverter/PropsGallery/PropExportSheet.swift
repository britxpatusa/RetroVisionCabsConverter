//
//  PropExportSheet.swift
//  RetroVisionCabsConverter
//
//  Export prop for VisionOS with options
//

import SwiftUI
import AppKit

struct PropExportSheet: View {
    let prop: DiscoveredProp
    let onClose: () -> Void
    
    @State private var exportOptions = VisionOSPropExporter.ExportOptions()
    @State private var outputFolder: URL?
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var exportStatus = ""
    @State private var exportResult: PropExportResult?
    @State private var exportError: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            if isExporting {
                exportingView
            } else if let result = exportResult, result.success {
                successView(result)
            } else {
                optionsView
            }
            
            Divider()
            
            // Footer
            footerView
        }
        .frame(width: 550, height: 500)
        .onAppear {
            // Set default output folder
            let paths = RetroVisionPaths.load()
            outputFolder = URL(fileURLWithPath: paths.workspaceRoot).appendingPathComponent("Output/VisionOS_Props")
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
                    Text("Cancel")
                }
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.escape)
            
            Spacer()
            
            Text("Export for VisionOS")
                .font(.headline)
            
            Spacer()
            
            // Placeholder for symmetry
            Color.clear.frame(width: 80)
        }
        .padding()
    }
    
    // MARK: - Options View
    
    private var optionsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Prop summary
                propSummary
                
                // Output location
                outputLocationSection
                
                // Video options
                if prop.videoInfo != nil {
                    VideoExportOptionsView(
                        codec: $exportOptions.videoCodec,
                        quality: $exportOptions.videoQuality
                    )
                }
                
                // Export options
                exportOptionsSection
                
                if let error = exportError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            .padding(20)
        }
    }
    
    private var propSummary: some View {
        GroupBox("Prop Summary") {
            HStack(spacing: 16) {
                if let preview = prop.previewImage {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .cornerRadius(8)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 80, height: 80)
                        .overlay {
                            Image(systemName: prop.propType.icon)
                                .font(.title)
                                .foregroundStyle(.secondary)
                        }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(prop.displayName)
                        .font(.headline)
                    
                    HStack(spacing: 12) {
                        Label(prop.propType.displayName, systemImage: prop.propType.icon)
                        Label(prop.placement.displayName, systemImage: "location")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    
                    HStack(spacing: 12) {
                        if prop.glbFile != nil {
                            Label("3D Model", systemImage: "cube")
                                .foregroundStyle(.green)
                        }
                        if prop.videoInfo != nil {
                            Label("Video", systemImage: "film")
                                .foregroundStyle(.blue)
                        }
                        if !prop.audioFiles.isEmpty {
                            Label("Audio", systemImage: "speaker.wave.2")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                }
                
                Spacer()
            }
            .padding(.vertical, 8)
        }
    }
    
    private var outputLocationSection: some View {
        GroupBox("Output Location") {
            HStack {
                if let folder = outputFolder {
                    Text(folder.path)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Select output folder")
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button("Browse...") {
                    selectOutputFolder()
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 8)
        }
    }
    
    private var exportOptionsSection: some View {
        GroupBox("Export Options") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Include Swift code for RealityKit", isOn: $exportOptions.includeSwiftCode)
                Toggle("Include README documentation", isOn: $exportOptions.includeReadme)
                
                if exportOptions.includeSwiftCode {
                    Text("Swift code will include a ready-to-use class for loading the prop in VisionOS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Exporting View
    
    private var exportingView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ProgressView()
                .scaleEffect(1.5)
            
            Text(exportStatus)
                .font(.headline)
            
            ProgressView(value: exportProgress)
                .frame(width: 300)
            
            Text("\(Int(exportProgress * 100))% complete")
                .foregroundStyle(.secondary)
            
            Spacer()
        }
    }
    
    // MARK: - Success View
    
    private func successView(_ result: PropExportResult) -> some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            
            Text("Export Complete!")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 8) {
                if let model = result.modelPath {
                    Label("Model: \(model.lastPathComponent)", systemImage: "cube")
                }
                if let video = result.videoPath {
                    Label("Video: \(video.lastPathComponent)", systemImage: "film")
                }
                if let swift = result.swiftCodePath {
                    Label("Swift: \(swift.lastPathComponent)", systemImage: "swift")
                }
                if let readme = result.readmePath {
                    Label("README: \(readme.lastPathComponent)", systemImage: "doc.text")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            
            HStack(spacing: 16) {
                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: result.outputFolder.path)
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                
                if let swift = result.swiftCodePath {
                    Button {
                        NSWorkspace.shared.open(swift)
                    } label: {
                        Label("Open Swift File", systemImage: "swift")
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            Spacer()
        }
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            if exportResult?.success == true {
                Button("Export Another") {
                    exportResult = nil
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
            
            if !isExporting && exportResult == nil {
                Button("Export") {
                    startExport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(outputFolder == nil)
                .keyboardShortcut(.return, modifiers: .command)
            } else if exportResult?.success == true {
                Button("Done") {
                    onClose()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
    
    // MARK: - Actions
    
    private func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Output Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK {
            outputFolder = panel.url
        }
    }
    
    private func startExport() {
        guard let output = outputFolder else { return }
        
        isExporting = true
        exportError = nil
        exportProgress = 0
        exportStatus = "Starting export..."
        
        Task {
            do {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                
                let result = try await VisionOSPropExporter.shared.exportProp(
                    prop,
                    to: output,
                    options: exportOptions
                ) { progress, status in
                    Task { @MainActor in
                        exportProgress = progress
                        exportStatus = status
                    }
                }
                
                await MainActor.run {
                    exportResult = result
                    isExporting = false
                }
            } catch {
                await MainActor.run {
                    exportError = "Export failed: \(error.localizedDescription)"
                    isExporting = false
                }
            }
        }
    }
}

// MARK: - Batch Export Sheet

struct BatchPropExportSheet: View {
    let props: [DiscoveredProp]
    let onClose: () -> Void
    
    @State private var exportOptions = VisionOSPropExporter.ExportOptions()
    @State private var outputFolder: URL?
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var currentProp = ""
    @State private var completedCount = 0
    @State private var failedCount = 0
    @State private var isComplete = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    onClose()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Cancel")
                    }
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Text("Export \(props.count) Props for VisionOS")
                    .font(.headline)
                
                Spacer()
                
                Color.clear.frame(width: 80)
            }
            .padding()
            
            Divider()
            
            if isExporting {
                VStack(spacing: 20) {
                    Spacer()
                    
                    ProgressView()
                        .scaleEffect(1.5)
                    
                    Text("Exporting: \(currentProp)")
                        .font(.headline)
                    
                    ProgressView(value: exportProgress)
                        .frame(width: 300)
                    
                    Text("\(completedCount) of \(props.count) complete")
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
            } else if isComplete {
                VStack(spacing: 20) {
                    Spacer()
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)
                    
                    Text("Batch Export Complete!")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    HStack(spacing: 20) {
                        VStack {
                            Text("\(completedCount)")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundStyle(.green)
                            Text("Successful")
                                .font(.caption)
                        }
                        
                        if failedCount > 0 {
                            VStack {
                                Text("\(failedCount)")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.red)
                                Text("Failed")
                                    .font(.caption)
                            }
                        }
                    }
                    
                    if let folder = outputFolder {
                        Button {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
                        } label: {
                            Label("Show in Finder", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Props list
                        GroupBox("Props to Export (\(props.count))") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(props) { prop in
                                        VStack(spacing: 4) {
                                            if let preview = prop.previewImage {
                                                Image(nsImage: preview)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                                    .frame(width: 50, height: 50)
                                                    .cornerRadius(6)
                                            } else {
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(Color.gray.opacity(0.2))
                                                    .frame(width: 50, height: 50)
                                                    .overlay {
                                                        Image(systemName: prop.propType.icon)
                                                            .font(.caption)
                                                    }
                                            }
                                            Text(prop.displayName)
                                                .font(.caption2)
                                                .lineLimit(1)
                                                .frame(width: 60)
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                        
                        // Output location
                        GroupBox("Output Location") {
                            HStack {
                                if let folder = outputFolder {
                                    Text(folder.path)
                                        .font(.system(.caption, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                
                                Spacer()
                                
                                Button("Browse...") {
                                    selectOutputFolder()
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        
                        // Video options
                        let hasVideo = props.contains { $0.videoInfo != nil }
                        if hasVideo {
                            VideoExportOptionsView(
                                codec: $exportOptions.videoCodec,
                                quality: $exportOptions.videoQuality
                            )
                        }
                        
                        // Export options
                        GroupBox("Export Options") {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Include Swift code", isOn: $exportOptions.includeSwiftCode)
                                Toggle("Include README", isOn: $exportOptions.includeReadme)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(20)
                }
            }
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                
                if isComplete {
                    Button("Done") {
                        onClose()
                    }
                    .buttonStyle(.borderedProminent)
                } else if !isExporting {
                    Button("Export All") {
                        startBatchExport()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(outputFolder == nil)
                }
            }
            .padding()
        }
        .frame(width: 600, height: 550)
        .onAppear {
            let paths = RetroVisionPaths.load()
            outputFolder = URL(fileURLWithPath: paths.workspaceRoot).appendingPathComponent("Output/VisionOS_Props")
        }
    }
    
    private func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Output Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        
        if panel.runModal() == .OK {
            outputFolder = panel.url
        }
    }
    
    private func startBatchExport() {
        guard let output = outputFolder else { return }
        
        isExporting = true
        completedCount = 0
        failedCount = 0
        
        Task {
            try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            
            for (index, prop) in props.enumerated() {
                await MainActor.run {
                    currentProp = prop.displayName
                    exportProgress = Double(index) / Double(props.count)
                }
                
                do {
                    _ = try await VisionOSPropExporter.shared.exportProp(
                        prop,
                        to: output,
                        options: exportOptions
                    ) { _, _ in }
                    
                    await MainActor.run {
                        completedCount += 1
                    }
                } catch {
                    await MainActor.run {
                        failedCount += 1
                    }
                }
            }
            
            await MainActor.run {
                isExporting = false
                isComplete = true
            }
        }
    }
}
