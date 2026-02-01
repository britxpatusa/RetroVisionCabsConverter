# VisionOS Props Integration Guide

This guide explains how to use the exported props from RetroVisionCabsConverter in your VisionOS app.

## Overview

When you export a prop for VisionOS, you get:
- A USDZ 3D model optimized for RealityKit
- Video files converted to HEVC (H.265) for Apple Silicon
- Audio files in original format
- **Interactive Swift code** with gesture support
- A JSON configuration file
- Integration documentation

## Interactive Features (Apple HIG Compliant)

All exported props include full interaction support following [Apple's Human Interface Guidelines for visionOS](https://developer.apple.com/design/human-interface-guidelines/spatial-interactions):

| Gesture | Action | Description |
|---------|--------|-------------|
| **Drag** | Move | Drag the prop freely in 3D space |
| **Two-finger Rotate** | Spin | Rotate the prop around its center |
| **Pinch** | Scale | Resize from 10% to 500% of original |
| **Look (Gaze)** | Highlight | Subtle hover effect when looking at prop |
| **Tap** | Select | Select the prop for focused interaction |

### Accessibility
- Full VoiceOver support with descriptive labels
- Accessibility traits for assistive technologies
- Proper focus management

## Export Output Structure

```
/Output/VisionOS_Props/
└── discostage/
    ├── Assets/
    │   ├── Models/
    │   │   └── discostage.usdz      # 3D model for RealityKit
    │   ├── Video/
    │   │   └── disco.mp4            # HEVC video (VisionOS optimized)
    │   ├── Textures/
    │   │   └── cutout2.png          # Texture files
    │   └── Audio/
    │       └── (audio files if any)
    ├── prop_config.json             # Configuration metadata
    ├── PropDiscostage.swift         # Ready-to-use Swift code
    └── README.md                    # Prop-specific documentation
```

## Step-by-Step Integration

### Step 1: Add Files to Your Xcode Project

1. Open your VisionOS project in Xcode
2. Right-click on your project in the navigator
3. Select **Add Files to "YourProject"...**
4. Navigate to the exported prop folder
5. Select the `Assets` folder and the `.swift` file
6. Check **Copy items if needed**
7. Check your app target
8. Click **Add**

### Step 2: Add Required Frameworks

Ensure your project links these frameworks:
- RealityKit
- AVFoundation (for video/audio)
- SwiftUI

### Step 3: Use Interactive View (Recommended)

Each exported prop includes both interactive and static views:

```swift
import SwiftUI
import RealityKit

struct ContentView: View {
    var body: some View {
        // Interactive - users can drag, rotate, and scale
        PropDiscostageView()
    }
}
```

### Step 4: Use Static View (Display Only)

For props that shouldn't be moved by users:

```swift
struct ContentView: View {
    var body: some View {
        // Static - no interaction, display only
        PropDiscostageStaticView()
    }
}
```

### Step 5: Add Control Ornament

Add a floating control panel for reset/play buttons:

```swift
struct ContentView: View {
    @StateObject private var prop = PropDiscostage()
    
    var body: some View {
        RealityView { content in
            if let entity = prop.entity {
                content.add(entity)
            }
        }
        .task { await prop.load() }
        .ornament(attachmentAnchor: .scene(.bottom)) {
            PropDiscostageControls(prop: prop)
        }
    }
}
```

### Step 6: Multiple Props with Interaction

```swift
import SwiftUI
import RealityKit

struct ArcadeRoomView: View {
    @StateObject private var discostage = PropDiscostage()
    @StateObject private var drwho = PropCutoutDrwho()
    
    var body: some View {
        RealityView { content in
            // Load props
            await discostage.load()
            await drwho.load()
            
            // Position props
            if let entity = discostage.entity {
                entity.position = [0, 0, -2]
                content.add(entity)
            }
            
            if let entity = drwho.entity {
                entity.position = [-1.5, 0, -2]
                content.add(entity)
            }
            
            // Start videos
            discostage.playVideo()
            drwho.playVideo()
        }
        // Add gestures for all props
        .gesture(DragGesture().targetedToAnyEntity().onChanged { value in
            // Drag handling is built into each prop
        })
        .onDisappear {
            discostage.cleanup()
            drwho.cleanup()
        }
    }
}
```

### Step 7: Programmatic Movement

```swift
// Move prop with animation
prop.moveTo(SIMD3<Float>(0, 1, -2), animated: true)

// Make prop face a point
prop.lookAt(SIMD3<Float>(0, 0, 0))

// Reset to original transform
prop.resetTransform()

// Scale programmatically (0.1 to 5.0)
prop.handleScale(1.5)  // 150% size
```

## Video Playback

### Automatic Playback

Videos are configured to loop automatically. The generated code handles this.

### Manual Control

```swift
// Play
discostage.playVideo()

// Pause
discostage.pauseVideo()

// Toggle
discostage.toggleVideo()
```

### Applying Video to Model Surface

The generated code attempts to apply the video to the appropriate mesh. If you need to customize:

```swift
// After loading
if let entity = prop.entity {
    entity.visit { entity in
        if let modelEntity = entity as? ModelEntity,
           modelEntity.name.contains("screen") {
            // Apply custom video material
            modelEntity.components[VideoPlayerComponent.self] = 
                VideoPlayerComponent(avPlayer: prop.videoPlayer!)
        }
    }
}
```

## Audio Playback

```swift
// Play all audio files
prop.playAudio()

// Stop all audio
prop.stopAudio()
```

## Configuration JSON

The `prop_config.json` file contains all metadata:

```json
{
  "id": "discostage_12345",
  "name": "Disco Stage",
  "type": "stage",
  "placement": "floor",
  "model": {
    "file": "discostage.usdz",
    "scale": 1.0
  },
  "video": {
    "file": "disco.mp4",
    "width": 1920,
    "height": 1080,
    "loop": true,
    "autoplay": true,
    "meshTarget": "screen"
  },
  "interaction": {
    "blockers": ["blocker1"],
    "triggers": []
  },
  "dimensions": {
    "width": 2.5,
    "height": 1.5,
    "depth": 1.0
  }
}
```

## Loading Props Dynamically

If you want to load props based on the JSON config:

```swift
import Foundation
import RealityKit

class DynamicPropLoader {
    func loadProp(from configURL: URL) async throws -> Entity {
        let data = try Data(contentsOf: configURL)
        let config = try JSONDecoder().decode(VisionOSPropConfig.self, from: data)
        
        // Get model path
        let modelURL = configURL.deletingLastPathComponent()
            .appendingPathComponent("Assets/Models/\(config.model?.file ?? "")")
        
        let entity = try await Entity(contentsOf: modelURL)
        
        // Apply scale
        if let scale = config.model?.scale {
            entity.scale = SIMD3(repeating: scale)
        }
        
        return entity
    }
}
```

## Placement Hints

Use the `placement` field to position props appropriately:

| Placement | Description | Example Position |
|-----------|-------------|------------------|
| `floor` | Ground level | y = 0 |
| `wall` | Mounted on wall | Against wall, y = 1.5 |
| `ceiling` | Hanging | y = 2.5 |
| `corner` | In corner | Near room corner |
| `center` | Room center | x = 0, z = 0 |
| `table` | On surface | y = 0.8 (table height) |

## Blockers and Triggers

### Blockers
Blocker meshes prevent the player from walking through the prop:

```swift
// The prop entity includes collision shapes for blockers
entity.visit { entity in
    if entity.name.contains("blocker") {
        entity.components[CollisionComponent.self] = CollisionComponent(
            shapes: [.generateConvex(from: entity as! ModelEntity)]
        )
    }
}
```

### Triggers
Trigger meshes detect when the player enters an area:

```swift
// Add a trigger volume
if let trigger = entity.findEntity(named: "trigger") as? ModelEntity {
    trigger.components[TriggerComponent.self] = TriggerComponent(
        onEnter: {
            print("Player entered trigger zone")
        }
    )
}
```

## Video Codec Information

### HEVC (H.265) - Recommended
- Best compression for file size
- Hardware-accelerated on Apple Silicon
- Uses `hvc1` tag for Apple compatibility

### H.264 - Compatible
- Widely compatible
- Larger files than HEVC
- Good for older hardware

### ProRes - High Quality
- Minimal compression artifacts
- Very large files
- Best for editing or archival

## Troubleshooting

### Video Not Playing
1. Ensure the video file is in the app bundle
2. Check the file extension matches
3. Verify video codec is supported (HEVC or H.264)

### Model Not Loading
1. Verify .usdz file is in the bundle
2. Check file permissions
3. Ensure model path is correct

### Audio Not Playing
1. Check AVAudioSession category
2. Verify audio file format
3. Ensure volume is not muted

### Performance Tips
- Use HEVC video for smaller files
- Keep polygon counts reasonable
- Use texture atlases when possible
- Preload props before showing

## Example VisionOS App

```swift
import SwiftUI

@main
struct ArcadeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        
        ImmersiveSpace(id: "ArcadeRoom") {
            ArcadeRoomView()
        }
    }
}

struct ContentView: View {
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    
    var body: some View {
        Button("Enter Arcade") {
            Task {
                await openImmersiveSpace(id: "ArcadeRoom")
            }
        }
    }
}
```

## Support

For issues with prop conversion or export:
1. Check the conversion logs in the app
2. Verify source files are valid
3. Ensure Blender is installed at `/Applications/Blender.app`
4. Ensure FFmpeg is installed for video conversion

---

*Generated by RetroVisionCabsConverter*
