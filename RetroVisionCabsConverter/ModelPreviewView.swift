//
//  ModelPreviewView.swift
//  RetroVisionCabsConverter
//
//  3D model preview using SceneKit
//

import SwiftUI
import SceneKit

// MARK: - SceneKit View Wrapper

struct SceneKitView: NSViewRepresentable {
    let scene: SCNScene
    let allowsCameraControl: Bool
    
    init(scene: SCNScene, allowsCameraControl: Bool = true) {
        self.scene = scene
        self.allowsCameraControl = allowsCameraControl
    }
    
    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = scene
        scnView.allowsCameraControl = allowsCameraControl
        scnView.autoenablesDefaultLighting = true
        scnView.backgroundColor = NSColor(calibratedWhite: 0.15, alpha: 1.0)
        
        // Set up camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.automaticallyAdjustsZRange = true
        cameraNode.position = SCNVector3(x: 0, y: 1.5, z: 3)
        cameraNode.look(at: SCNVector3(x: 0, y: 0.5, z: 0))
        scene.rootNode.addChildNode(cameraNode)
        
        // Add ambient light
        let ambientLightNode = SCNNode()
        ambientLightNode.light = SCNLight()
        ambientLightNode.light?.type = .ambient
        ambientLightNode.light?.intensity = 500
        ambientLightNode.light?.color = NSColor.white
        scene.rootNode.addChildNode(ambientLightNode)
        
        // Add directional light
        let directionalLightNode = SCNNode()
        directionalLightNode.light = SCNLight()
        directionalLightNode.light?.type = .directional
        directionalLightNode.light?.intensity = 800
        directionalLightNode.light?.castsShadow = true
        directionalLightNode.position = SCNVector3(x: 2, y: 5, z: 3)
        directionalLightNode.look(at: SCNVector3(x: 0, y: 0, z: 0))
        scene.rootNode.addChildNode(directionalLightNode)
        
        // Add floor for reference
        let floor = SCNFloor()
        floor.reflectivity = 0.1
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(x: 0, y: -0.01, z: 0)
        
        let floorMaterial = SCNMaterial()
        floorMaterial.diffuse.contents = NSColor(calibratedWhite: 0.2, alpha: 1.0)
        floor.materials = [floorMaterial]
        scene.rootNode.addChildNode(floorNode)
        
        return scnView
    }
    
    func updateNSView(_ nsView: SCNView, context: Context) {
        nsView.scene = scene
    }
}

// MARK: - Model Preview Manager

@MainActor
class ModelPreviewManager: ObservableObject {
    @Published var scene: SCNScene?
    @Published var isLoading = false
    @Published var error: String?
    @Published var loadedMeshNames: [String] = []
    
    private var modelNode: SCNNode?
    
    func loadModel(from url: URL) {
        isLoading = true
        error = nil
        loadedMeshNames = []
        
        Task {
            do {
                let newScene = try await loadGLBModel(url: url)
                await MainActor.run {
                    self.scene = newScene
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func loadGLBModel(url: URL) async throws -> SCNScene {
        // SceneKit can load GLB/GLTF natively on macOS 12+
        let scene = try SCNScene(url: url, options: [
            .checkConsistency: true,
            .flattenScene: false
        ])
        
        // Center and scale the model
        let rootNode = scene.rootNode
        
        // Calculate bounding box
        let (minBound, maxBound) = rootNode.boundingBox
        let centerX = (minBound.x + maxBound.x) / 2
        let centerZ = (minBound.z + maxBound.z) / 2
        
        // Calculate scale to normalize size
        let sizeX = maxBound.x - minBound.x
        let sizeY = maxBound.y - minBound.y
        let sizeZ = maxBound.z - minBound.z
        let maxDimension = max(sizeX, max(sizeY, sizeZ))
        let targetSize: CGFloat = 2.0  // Target 2 units tall
        let scale = maxDimension > 0 ? targetSize / maxDimension : 1.0
        
        // Create a container node for positioning
        let containerNode = SCNNode()
        
        // Move all children to container
        var meshNames: [String] = []
        for child in rootNode.childNodes {
            child.removeFromParentNode()
            containerNode.addChildNode(child)
            collectMeshNames(from: child, into: &meshNames)
        }
        
        // Apply transformations to container
        containerNode.scale = SCNVector3(x: scale, y: scale, z: scale)
        containerNode.position = SCNVector3(
            x: -centerX * scale,
            y: 0,
            z: -centerZ * scale
        )
        
        rootNode.addChildNode(containerNode)
        
        await MainActor.run {
            self.modelNode = containerNode
            self.loadedMeshNames = meshNames.sorted()
        }
        
        return scene
    }
    
    private func collectMeshNames(from node: SCNNode, into names: inout [String]) {
        if node.geometry != nil, let name = node.name, !name.isEmpty {
            names.append(name)
        }
        for child in node.childNodes {
            collectMeshNames(from: child, into: &names)
        }
    }
    
    func applyTexture(_ image: NSImage, toMeshNamed meshName: String) {
        guard let modelNode = modelNode else { return }
        
        applyTextureRecursive(image, toMeshNamed: meshName.lowercased(), in: modelNode)
    }
    
    private func applyTextureRecursive(_ image: NSImage, toMeshNamed meshName: String, in node: SCNNode) {
        if let nodeName = node.name?.lowercased(),
           nodeName.contains(meshName) || meshName.contains(nodeName),
           node.geometry != nil {
            let material = SCNMaterial()
            material.diffuse.contents = image
            material.isDoubleSided = true
            node.geometry?.materials = [material]
        }
        
        for child in node.childNodes {
            applyTextureRecursive(image, toMeshNamed: meshName, in: child)
        }
    }
    
    func applyTexturesFromMappings(_ mappings: [String: ArtworkMapping], template: CabinetTemplate) {
        guard let modelNode = modelNode else { return }
        
        for part in template.allParts {
            if let mapping = mappings[part.id],
               let fileURL = mapping.file,
               let image = NSImage(contentsOf: fileURL) {
                applyTextureRecursive(image, toMeshNamed: part.meshName.lowercased(), in: modelNode)
            }
        }
    }
    
    func resetView() {
        // Re-center camera - would need reference to SCNView
    }
}

// MARK: - Model Preview Window

struct ModelPreviewView: View {
    let modelURL: URL?
    let artworkMappings: [String: ArtworkMapping]
    let template: CabinetTemplate?
    
    @StateObject private var previewManager = ModelPreviewManager()
    @State private var showMeshList = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("3D Preview")
                    .font(.headline)
                
                Spacer()
                
                if previewManager.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                
                Button {
                    showMeshList.toggle()
                } label: {
                    Image(systemName: "list.bullet")
                }
                .help("Show mesh list")
                .popover(isPresented: $showMeshList) {
                    meshListPopover
                }
                
                Button("Close") {
                    dismiss()
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // 3D View
            ZStack {
                if let scene = previewManager.scene {
                    SceneKitView(scene: scene)
                } else if let error = previewManager.error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text("Failed to load model")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if previewManager.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading model...")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No model loaded")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: NSColor(calibratedWhite: 0.15, alpha: 1.0)))
            
            // Footer with controls info
            HStack {
                Label("Rotate: Drag", systemImage: "arrow.triangle.2.circlepath")
                Spacer()
                Label("Zoom: Scroll", systemImage: "arrow.up.left.and.arrow.down.right")
                Spacer()
                Label("Pan: Right-drag", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            loadModel()
        }
    }
    
    private var meshListPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mesh Names")
                .font(.headline)
            
            Divider()
            
            if previewManager.loadedMeshNames.isEmpty {
                Text("No meshes found")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(previewManager.loadedMeshNames, id: \.self) { name in
                            HStack {
                                Circle()
                                    .fill(meshHasTexture(name) ? Color.green : Color.secondary)
                                    .frame(width: 8, height: 8)
                                Text(name)
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .padding()
        .frame(width: 200)
    }
    
    private func meshHasTexture(_ meshName: String) -> Bool {
        guard let template = template else { return false }
        
        for part in template.allParts {
            if part.meshName.lowercased() == meshName.lowercased() ||
               meshName.lowercased().contains(part.meshName.lowercased()) {
                if let mapping = artworkMappings[part.id], mapping.file != nil {
                    return true
                }
            }
        }
        return false
    }
    
    private func loadModel() {
        guard let url = modelURL else { return }
        
        previewManager.loadModel(from: url)
        
        // Apply textures after a delay to ensure model is loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let template = template {
                previewManager.applyTexturesFromMappings(artworkMappings, template: template)
            }
        }
    }
}

// MARK: - Standalone Preview Window

struct ModelPreviewWindow: View {
    let modelPath: String
    let cabinetName: String
    
    @StateObject private var previewManager = ModelPreviewManager()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(cabinetName)
                        .font(.headline)
                    Text("3D Model Preview")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if previewManager.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // 3D View
            ZStack {
                if let scene = previewManager.scene {
                    SceneKitView(scene: scene)
                        .overlay(alignment: .bottomLeading) {
                            meshInfoOverlay
                        }
                } else if let error = previewManager.error {
                    errorView(error)
                } else if previewManager.isLoading {
                    loadingView
                } else {
                    emptyView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: NSColor(calibratedWhite: 0.15, alpha: 1.0)))
            
            // Controls footer
            controlsFooter
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            let url = URL(fileURLWithPath: modelPath)
            previewManager.loadModel(from: url)
        }
    }
    
    private var meshInfoOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Meshes: \(previewManager.loadedMeshNames.count)")
                .font(.caption)
            
            if !previewManager.loadedMeshNames.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(previewManager.loadedMeshNames.prefix(10), id: \.self) { name in
                            Text(name)
                                .font(.system(.caption2, design: .monospaced))
                        }
                        if previewManager.loadedMeshNames.count > 10 {
                            Text("+ \(previewManager.loadedMeshNames.count - 10) more...")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .padding()
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Failed to load model")
                .font(.headline)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Retry") {
                let url = URL(fileURLWithPath: modelPath)
                previewManager.loadModel(from: url)
            }
        }
        .padding()
    }
    
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading model...")
                .foregroundStyle(.secondary)
        }
    }
    
    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No model loaded")
                .foregroundStyle(.secondary)
        }
    }
    
    private var controlsFooter: some View {
        HStack(spacing: 24) {
            controlHint(icon: "arrow.triangle.2.circlepath", text: "Drag to rotate")
            controlHint(icon: "arrow.up.left.and.arrow.down.right", text: "Scroll to zoom")
            controlHint(icon: "arrow.up.and.down.and.arrow.left.and.right", text: "Right-drag to pan")
            
            Spacer()
            
            Text(modelPath)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func controlHint(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Preview

#Preview("Model Preview") {
    ModelPreviewWindow(
        modelPath: "/path/to/model.glb",
        cabinetName: "Test Cabinet"
    )
}
