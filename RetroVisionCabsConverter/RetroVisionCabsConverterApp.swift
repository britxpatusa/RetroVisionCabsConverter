import SwiftUI

@main
struct RetroVisionCabsConverterApp: App {
    @StateObject private var templateManager = TemplateManager()
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // Set up notification for app termination cleanup
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            Self.cleanupOnExit()
        }
        
        // Also ensure temp directories exist on startup
        let paths = RetroVisionPaths.load()
        if paths.isConfigured {
            try? paths.ensureDirectoriesExist()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(after: .newItem) {
                Divider()
                
                Menu("Export Artwork Templates") {
                    ForEach(templateManager.templates) { template in
                        Button("\(template.name)...") {
                            exportArtworkTemplates(for: template)
                        }
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                // Clean up when app goes to background (optional)
                // Self.cleanupOnExit()
            }
        }
    }
    
    /// Cleanup temporary files when app exits
    private static func cleanupOnExit() {
        let paths = RetroVisionPaths.load()
        paths.cleanupAll()
        print("App cleanup completed")
    }
    
    private func exportArtworkTemplates(for template: CabinetTemplate) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose where to save artwork templates for \(template.name)"
        panel.prompt = "Export"
        
        if panel.runModal() == .OK, let url = panel.url {
            let outputFolder = url.appendingPathComponent("\(template.name) Templates")
            
            do {
                try templateManager.generateArtworkGuides(for: template, outputFolder: outputFolder)
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: outputFolder.path)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }
}
