//
//  CabinetExportSheet.swift
//  RetroVisionCabsConverter
//
//  Export cabinets for VisionOS with options
//

import SwiftUI
import AppKit

struct CabinetExportSheet: View {
    let cabinet: CabinetItem
    let onClose: () -> Void
    
    @State private var exportOptions = VisionOSCabinetExporter.ExportOptions()
    @State private var outputFolder: URL?
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var exportStatus = ""
    @State private var exportResult: CabinetExportResult?
    @State private var exportError: String?
    
    var body: some View {
        VStack(spacing: 0) {
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
            footerView
        }
        .frame(width: 550, height: 550)
        .onAppear {
            let paths = RetroVisionPaths.load()
            outputFolder = URL(fileURLWithPath: paths.workspaceRoot).appendingPathComponent("Output/VisionOS_Cabinets")
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
            
            Text("Export Cabinet for VisionOS")
                .font(.headline)
            
            Spacer()
            
            Color.clear.frame(width: 80)
        }
        .padding()
    }
    
    // MARK: - Options View
    
    private var optionsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Cabinet summary
                GroupBox("Cabinet") {
                    HStack(spacing: 16) {
                        if let preview = cabinet.preview {
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
                                    Image(systemName: "arcade.stick.console")
                                        .font(.title)
                                }
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text(cabinet.name)
                                .font(.headline)
                            
                            if let template = cabinet.matchedTemplate {
                                Label("Template: \(template)", systemImage: "doc.text")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            HStack(spacing: 12) {
                                Label("3D Model", systemImage: "cube")
                                    .foregroundStyle(.green)
                                if hasVideo {
                                    Label("Video", systemImage: "film")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .font(.caption)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
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
                if hasVideo {
                    GroupBox("Video Conversion") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Codec:")
                                    .frame(width: 60, alignment: .trailing)
                                Picker("", selection: $exportOptions.videoCodec) {
                                    ForEach(VisionOSCabinetExporter.ExportOptions.VideoCodec.allCases, id: \.self) {
                                        Text($0.rawValue).tag($0)
                                    }
                                }
                                .labelsHidden()
                                
                                if exportOptions.videoCodec == .hevc {
                                    Label("Recommended", systemImage: "star.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }
                            
                            HStack {
                                Text("Quality:")
                                    .frame(width: 60, alignment: .trailing)
                                Picker("", selection: $exportOptions.videoQuality) {
                                    ForEach(VisionOSCabinetExporter.ExportOptions.VideoQuality.allCases, id: \.self) {
                                        Text($0.rawValue).tag($0)
                                    }
                                }
                                .labelsHidden()
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                // Export options
                GroupBox("Export Options") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Include Swift code (interactive cabinet)", isOn: $exportOptions.includeSwiftCode)
                        Toggle("Include CRT shader effect", isOn: $exportOptions.includeCRTShader)
                        Toggle("Include README documentation", isOn: $exportOptions.includeReadme)
                    }
                    .padding(.vertical, 8)
                }
                
                if let error = exportError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            .padding(20)
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
            Text("\(Int(exportProgress * 100))%")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
    
    // MARK: - Success View
    
    private func successView(_ result: CabinetExportResult) -> some View {
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
                    Label(model.lastPathComponent, systemImage: "cube")
                }
                if let video = result.videoPath {
                    Label(video.lastPathComponent, systemImage: "film")
                }
                if let swift = result.swiftCodePath {
                    Label(swift.lastPathComponent, systemImage: "swift")
                }
                if let shader = result.shaderPath {
                    Label(shader.lastPathComponent, systemImage: "sparkles")
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
    
    // MARK: - Helpers
    
    private var hasVideo: Bool {
        let folderPath = URL(fileURLWithPath: cabinet.path)
        let videoExtensions = ["mp4", "m4v", "mov", "mkv"]
        
        if let contents = try? FileManager.default.contentsOfDirectory(at: folderPath, includingPropertiesForKeys: nil) {
            return contents.contains { videoExtensions.contains($0.pathExtension.lowercased()) }
        }
        return false
    }
    
    private func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        
        if panel.runModal() == .OK {
            outputFolder = panel.url
        }
    }
    
    private func startExport() {
        guard let output = outputFolder else { return }
        
        isExporting = true
        exportError = nil
        
        Task {
            do {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                
                let result = try await VisionOSCabinetExporter.shared.exportCabinet(
                    cabinet,
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
                    exportError = error.localizedDescription
                    isExporting = false
                }
            }
        }
    }
}

// MARK: - Batch Cabinet Export Sheet

struct BatchCabinetExportSheet: View {
    let cabinets: [CabinetItem]
    let onClose: () -> Void
    
    @State private var exportOptions = VisionOSCabinetExporter.ExportOptions()
    @State private var outputFolder: URL?
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var currentCabinet = ""
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
                
                Text("Export \(cabinets.count) Cabinets for VisionOS")
                    .font(.headline)
                
                Spacer()
                
                Color.clear.frame(width: 80)
            }
            .padding()
            
            Divider()
            
            if isExporting {
                VStack(spacing: 20) {
                    Spacer()
                    ProgressView().scaleEffect(1.5)
                    Text("Exporting: \(currentCabinet)").font(.headline)
                    ProgressView(value: exportProgress).frame(width: 300)
                    Text("\(completedCount) of \(cabinets.count)").foregroundStyle(.secondary)
                    Spacer()
                }
            } else if isComplete {
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)
                    Text("Export Complete!").font(.title2).fontWeight(.bold)
                    
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
                        // Cabinets list
                        GroupBox("Cabinets to Export (\(cabinets.count))") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(cabinets) { cabinet in
                                        VStack(spacing: 4) {
                                            if let preview = cabinet.preview {
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
                                                        Image(systemName: "arcade.stick.console")
                                                            .font(.caption)
                                                    }
                                            }
                                            Text(cabinet.name)
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
                        
                        // Options
                        GroupBox("Export Options") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Video Codec:")
                                    Picker("", selection: $exportOptions.videoCodec) {
                                        ForEach(VisionOSCabinetExporter.ExportOptions.VideoCodec.allCases, id: \.self) {
                                            Text($0.rawValue).tag($0)
                                        }
                                    }
                                    .labelsHidden()
                                }
                                
                                Toggle("Include Swift code", isOn: $exportOptions.includeSwiftCode)
                                Toggle("Include CRT shader", isOn: $exportOptions.includeCRTShader)
                                Toggle("Include README", isOn: $exportOptions.includeReadme)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(20)
                }
            }
            
            Divider()
            
            HStack {
                Spacer()
                if isComplete {
                    Button("Done") { onClose() }
                        .buttonStyle(.borderedProminent)
                } else if !isExporting {
                    Button("Export All") { startBatchExport() }
                        .buttonStyle(.borderedProminent)
                        .disabled(outputFolder == nil)
                }
            }
            .padding()
        }
        .frame(width: 600, height: 550)
        .onAppear {
            let paths = RetroVisionPaths.load()
            outputFolder = URL(fileURLWithPath: paths.workspaceRoot).appendingPathComponent("Output/VisionOS_Cabinets")
        }
    }
    
    private func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
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
            
            let results = await VisionOSCabinetExporter.shared.exportCabinets(
                cabinets,
                to: output,
                options: exportOptions
            ) { progress, status in
                Task { @MainActor in
                    exportProgress = progress
                    currentCabinet = status
                }
            }
            
            await MainActor.run {
                completedCount = results.filter { $0.success }.count
                failedCount = results.count - completedCount
                isExporting = false
                isComplete = true
            }
        }
    }
}
