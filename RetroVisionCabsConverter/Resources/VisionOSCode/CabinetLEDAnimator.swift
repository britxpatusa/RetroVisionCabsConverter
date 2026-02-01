//
//  CabinetLEDAnimator.swift
//  VisionOS Arcade Cabinet LED Animation
//
//  Add this file to your VisionOS project to enable T-molding LED animations.
//  Usage:
//    1. Load your USDZ cabinet model
//    2. Call CabinetLEDAnimator.setup(entity:metadataURL:) with the root entity
//    3. The animator will find T-molding meshes and apply LED effects
//

import Foundation
import RealityKit
import SwiftUI
import Combine

// MARK: - LED Configuration from rkmeta.json

public struct LEDEffectConfig: Codable {
    public var enabled: Bool = false
    public var animation: String = "pulse"
    public var speed: Double = 1.0
    
    public init() {}
}

public struct RKMetadata: Codable {
    public var name: String?
    public var rk_contract: RKContract?
    
    public struct RKContract: Codable {
        public var led_effects: LEDEffectConfig?
        public var tmolding_node_name: String?
    }
}

// MARK: - LED Animator

@MainActor
public class CabinetLEDAnimator: ObservableObject {
    
    public static let shared = CabinetLEDAnimator()
    
    @Published public var isAnimating = false
    @Published public var currentColor: SIMD3<Float> = [1, 0, 0]
    
    private var animationTask: Task<Void, Never>?
    private var tmoldingEntities: [Entity] = []
    private var ledConfig: LEDEffectConfig = LEDEffectConfig()
    
    private init() {}
    
    // MARK: - Setup
    
    /// Setup LED animation for a cabinet entity
    /// - Parameters:
    ///   - entity: The root entity of the loaded USDZ cabinet
    ///   - metadataURL: Optional URL to the rkmeta.json file
    public func setup(entity: Entity, metadataURL: URL? = nil) {
        // Load metadata if provided
        if let url = metadataURL {
            loadMetadata(from: url)
        }
        
        // Find T-molding entities
        findTMoldingEntities(in: entity)
        
        // Start animation if enabled
        if ledConfig.enabled && !tmoldingEntities.isEmpty {
            startAnimation()
        }
    }
    
    /// Setup with inline configuration
    public func setup(entity: Entity, enabled: Bool, animation: String, speed: Double, color: SIMD3<Float>) {
        ledConfig.enabled = enabled
        ledConfig.animation = animation
        ledConfig.speed = speed
        currentColor = color
        
        findTMoldingEntities(in: entity)
        
        if enabled && !tmoldingEntities.isEmpty {
            startAnimation()
        }
    }
    
    // MARK: - Metadata Loading
    
    private func loadMetadata(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let metadata = try JSONDecoder().decode(RKMetadata.self, from: data)
            
            if let ledEffects = metadata.rk_contract?.led_effects {
                ledConfig = ledEffects
            }
        } catch {
            print("CabinetLEDAnimator: Failed to load metadata: \(error)")
        }
    }
    
    // MARK: - Entity Discovery
    
    private func findTMoldingEntities(in entity: Entity) {
        tmoldingEntities.removeAll()
        
        // Search for T-molding by name patterns
        let patterns = ["t-molding", "t_molding", "tmolding", "t-mold", "tmold", "led", "trim"]
        
        findEntitiesRecursive(entity, patterns: patterns)
        
        print("CabinetLEDAnimator: Found \(tmoldingEntities.count) T-molding entities")
    }
    
    private func findEntitiesRecursive(_ entity: Entity, patterns: [String]) {
        let nameLower = entity.name.lowercased()
        
        for pattern in patterns {
            if nameLower.contains(pattern) {
                tmoldingEntities.append(entity)
                break
            }
        }
        
        for child in entity.children {
            findEntitiesRecursive(child, patterns: patterns)
        }
    }
    
    // MARK: - Animation Control
    
    public func startAnimation() {
        guard !isAnimating else { return }
        isAnimating = true
        
        animationTask = Task {
            await runAnimationLoop()
        }
        
        print("CabinetLEDAnimator: Started \(ledConfig.animation) animation at \(ledConfig.speed)x speed")
    }
    
    public func stopAnimation() {
        isAnimating = false
        animationTask?.cancel()
        animationTask = nil
    }
    
    public func setColor(_ color: SIMD3<Float>) {
        currentColor = color
        updateMaterials(emissionColor: color, emissionStrength: 2.0)
    }
    
    // MARK: - Animation Loop
    
    private func runAnimationLoop() async {
        let startTime = Date()
        let baseSpeed = ledConfig.speed
        
        while isAnimating && !Task.isCancelled {
            let elapsed = Date().timeIntervalSince(startTime) * baseSpeed
            
            switch ledConfig.animation.lowercased() {
            case "pulse":
                animatePulse(time: elapsed)
            case "rainbow":
                animateRainbow(time: elapsed)
            case "chase":
                animateChase(time: elapsed)
            case "flash":
                animateFlash(time: elapsed)
            default:
                animatePulse(time: elapsed)
            }
            
            try? await Task.sleep(nanoseconds: 33_333_333) // ~30 FPS
        }
    }
    
    // MARK: - Animation Types
    
    private func animatePulse(time: Double) {
        // Smooth sine wave pulse
        let intensity = Float(0.5 + 0.5 * sin(time * 2 * .pi))
        let strength = 0.5 + intensity * 2.5
        updateMaterials(emissionColor: currentColor, emissionStrength: strength)
    }
    
    private func animateRainbow(time: Double) {
        // Cycle through hue
        let hue = Float(time.truncatingRemainder(dividingBy: 3.0) / 3.0)
        let color = hsvToRGB(h: hue, s: 1.0, v: 1.0)
        updateMaterials(emissionColor: color, emissionStrength: 2.5)
    }
    
    private func animateChase(time: Double) {
        // Quick on/off chasing pattern
        let phase = time.truncatingRemainder(dividingBy: 1.0)
        let strength: Float = phase < 0.5 ? 3.0 : 0.3
        updateMaterials(emissionColor: currentColor, emissionStrength: strength)
    }
    
    private func animateFlash(time: Double) {
        // Rapid strobe
        let phase = time.truncatingRemainder(dividingBy: 0.2)
        let strength: Float = phase < 0.1 ? 3.5 : 0.1
        updateMaterials(emissionColor: currentColor, emissionStrength: strength)
    }
    
    // MARK: - Material Updates
    
    private func updateMaterials(emissionColor: SIMD3<Float>, emissionStrength: Float) {
        for entity in tmoldingEntities {
            guard var modelComponent = entity.components[ModelComponent.self] else { continue }
            
            var newMaterials: [Material] = []
            
            for material in modelComponent.materials {
                if var pbrMaterial = material as? PhysicallyBasedMaterial {
                    // Update emission
                    pbrMaterial.emissiveColor = .init(color: .init(emissionColor), texture: nil)
                    pbrMaterial.emissiveIntensity = emissionStrength
                    newMaterials.append(pbrMaterial)
                } else if var simpleMaterial = material as? SimpleMaterial {
                    // SimpleMaterial doesn't have emission, create PBR
                    var pbrMaterial = PhysicallyBasedMaterial()
                    pbrMaterial.baseColor = simpleMaterial.color
                    pbrMaterial.emissiveColor = .init(color: .init(emissionColor), texture: nil)
                    pbrMaterial.emissiveIntensity = emissionStrength
                    newMaterials.append(pbrMaterial)
                } else {
                    newMaterials.append(material)
                }
            }
            
            modelComponent.materials = newMaterials
            entity.components[ModelComponent.self] = modelComponent
        }
    }
    
    // MARK: - Helpers
    
    private func hsvToRGB(h: Float, s: Float, v: Float) -> SIMD3<Float> {
        let c = v * s
        let x = c * (1 - abs((h * 6).truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        
        var r: Float = 0, g: Float = 0, b: Float = 0
        
        switch h * 6 {
        case 0..<1: (r, g, b) = (c, x, 0)
        case 1..<2: (r, g, b) = (x, c, 0)
        case 2..<3: (r, g, b) = (0, c, x)
        case 3..<4: (r, g, b) = (0, x, c)
        case 4..<5: (r, g, b) = (x, 0, c)
        default:    (r, g, b) = (c, 0, x)
        }
        
        return [r + m, g + m, b + m]
    }
}

// MARK: - SwiftUI Integration

/// A view modifier that sets up LED animation on a RealityKit entity
public struct LEDAnimationModifier: ViewModifier {
    let entity: Entity?
    let metadataURL: URL?
    
    public func body(content: Content) -> some View {
        content
            .onAppear {
                if let entity = entity {
                    Task { @MainActor in
                        CabinetLEDAnimator.shared.setup(entity: entity, metadataURL: metadataURL)
                    }
                }
            }
            .onDisappear {
                CabinetLEDAnimator.shared.stopAnimation()
            }
    }
}

public extension View {
    /// Enable LED animation for a cabinet entity
    func cabinetLEDAnimation(entity: Entity?, metadataURL: URL? = nil) -> some View {
        modifier(LEDAnimationModifier(entity: entity, metadataURL: metadataURL))
    }
}

// MARK: - Usage Example
/*
 
 // In your VisionOS app:
 
 import SwiftUI
 import RealityKit
 
 struct CabinetView: View {
     @State private var cabinetEntity: Entity?
     
     var body: some View {
         RealityView { content in
             // Load the cabinet USDZ
             if let entity = try? await Entity(named: "MyCabinet.usdz") {
                 content.add(entity)
                 cabinetEntity = entity
             }
         }
         .cabinetLEDAnimation(
             entity: cabinetEntity,
             metadataURL: Bundle.main.url(forResource: "MyCabinet.rkmeta", withExtension: "json")
         )
     }
 }
 
 // Or manually:
 
 struct ManualLEDView: View {
     var body: some View {
         RealityView { content in
             if let entity = try? await Entity(named: "Cabinet.usdz") {
                 content.add(entity)
                 
                 // Setup LED animation manually
                 await MainActor.run {
                     CabinetLEDAnimator.shared.setup(
                         entity: entity,
                         enabled: true,
                         animation: "rainbow",
                         speed: 1.0,
                         color: [1, 0, 0] // Red
                     )
                 }
             }
         }
     }
 }
 
 */
