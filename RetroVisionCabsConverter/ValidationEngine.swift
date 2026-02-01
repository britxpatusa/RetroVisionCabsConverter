import Foundation

// MARK: - Validation Engine

class ValidationEngine {
    
    // Known model mesh names (standard parts that should exist)
    private let standardMeshNames = [
        "marquee", "bezel", "screen", "joystick", "coinslot",
        "sides", "front", "back", "top", "bottom",
        "control", "panel", "speaker", "coin-door"
    ]
    
    /// Validate a cabinet detail and update validation statuses
    func validate(cabinet: CabinetDetail) -> CabinetDetail {
        var updatedCabinet = cabinet
        
        // Validate each part
        for i in updatedCabinet.parts.indices {
            updatedCabinet.parts[i] = validatePart(
                updatedCabinet.parts[i],
                availableImages: cabinet.imageFiles,
                cabinetPath: cabinet.path
            )
        }
        
        // Check for model file
        if cabinet.modelFile == nil {
            // Look for GLB files
            let glbFiles = cabinet.files.filter { $0.fileType == .model }
            if glbFiles.isEmpty && cabinet.style == nil {
                // No model and no style reference - this might be an error
                // but we allow it if there's a style reference in the model library
            }
        }
        
        // Calculate overall status
        updatedCabinet.overallStatus = calculateOverallStatus(for: updatedCabinet)
        
        return updatedCabinet
    }
    
    /// Validate a single part
    private func validatePart(
        _ part: CabinetPartDetail,
        availableImages: [CabinetFileInfo],
        cabinetPath: String
    ) -> CabinetPartDetail {
        var updatedPart = part
        
        // Check if part has a texture assigned
        if let artFile = part.artFile, !artFile.isEmpty {
            // Check if the file exists
            let fullPath = (cabinetPath as NSString).appendingPathComponent(artFile)
            
            if FileManager.default.fileExists(atPath: fullPath) {
                updatedPart.validationStatus = .valid
            } else {
                // File specified but doesn't exist
                // Try to find a suggestion
                if let suggestion = findBestMatch(for: artFile, in: availableImages) {
                    updatedPart.validationStatus = .suggestion(
                        file: suggestion.file,
                        confidence: suggestion.confidence
                    )
                    updatedPart.suggestedFile = suggestion.file
                } else {
                    updatedPart.validationStatus = .error("Texture file not found: \(artFile)")
                }
            }
        } else {
            // No texture assigned - check if part has material or color
            // CDL allows parts to use material (darkwood, black, plastic, etc.) or color instead of texture
            if let material = part.material, !material.isEmpty {
                // Part uses material preset - this is valid
                updatedPart.validationStatus = .valid
            } else if part.color != nil {
                // Part uses color - this is valid  
                updatedPart.validationStatus = .valid
            } else if partTypicallyNeedsTexture(part.name, type: part.type) {
                // No texture, no material, no color - check for suggestions
                if let suggestion = findBestMatchForPartName(part.name, in: availableImages) {
                    updatedPart.validationStatus = .suggestion(
                        file: suggestion.file,
                        confidence: suggestion.confidence
                    )
                    updatedPart.suggestedFile = suggestion.file
                } else {
                    // No texture and no suggestion - just a warning
                    updatedPart.validationStatus = .warning("No texture assigned")
                }
            } else {
                // Part doesn't typically need a texture (using default material)
                updatedPart.validationStatus = .valid
            }
        }
        
        return updatedPart
    }
    
    /// Determine if a part typically needs a texture
    private func partTypicallyNeedsTexture(_ name: String, type: PartType) -> Bool {
        let lowercaseName = name.lowercased()
        
        // Parts that ALWAYS need textures (marquee/bezel types)
        if type == .marquee || type == .bezel {
            return true
        }
        
        // Parts that typically need textures (artwork panels)
        let texturedParts = [
            "marquee", "bezel", "side-art", "sideart", "art-left", "art-right"
        ]
        
        // Parts that typically DON'T need textures (can use material/color instead)
        // These are structural parts or control interfaces
        let nonTexturedParts = [
            "joystick", "button", "coin", "speaker", "vent", "screw", 
            "handle", "leg", "base", "frame", "front", "back", "top", 
            "bottom", "kick", "panel", "deck", "shell", "housing",
            "molding", "trim", "border", "side"  // sides often use materials
        ]
        
        // Check if name matches non-textured parts first (more specific)
        for nonTexturedPart in nonTexturedParts {
            if lowercaseName == nonTexturedPart || lowercaseName.contains(nonTexturedPart) {
                return false
            }
        }
        
        // Check if name matches textured parts
        for texturedPart in texturedParts {
            if lowercaseName.contains(texturedPart) {
                return true
            }
        }
        
        // Default: parts with explicit "art" or "graphic" in name need textures
        return lowercaseName.contains("-art") || lowercaseName.contains("_art") || lowercaseName.contains("graphic")
    }
    
    /// Find best matching file for a given filename
    private func findBestMatch(for filename: String, in availableImages: [CabinetFileInfo]) -> (file: String, confidence: Double)? {
        let targetName = (filename as NSString).deletingPathExtension.lowercased()
        
        var bestMatch: (file: String, confidence: Double)?
        
        for image in availableImages where !image.isAssigned {
            let imageName = (image.filename as NSString).deletingPathExtension.lowercased()
            let confidence = calculateSimilarity(targetName, imageName)
            
            if confidence > 0.5 {
                if bestMatch == nil || confidence > bestMatch!.confidence {
                    bestMatch = (image.filename, confidence)
                }
            }
        }
        
        return bestMatch
    }
    
    /// Find best matching file for a part name
    private func findBestMatchForPartName(_ partName: String, in availableImages: [CabinetFileInfo]) -> (file: String, confidence: Double)? {
        let targetName = partName.lowercased()
        
        var bestMatch: (file: String, confidence: Double)?
        
        for image in availableImages where !image.isAssigned {
            let imageName = (image.filename as NSString).deletingPathExtension.lowercased()
            
            // Check for exact or partial match
            var confidence = 0.0
            
            if imageName == targetName {
                confidence = 1.0
            } else if imageName.contains(targetName) || targetName.contains(imageName) {
                confidence = 0.8
            } else {
                confidence = calculateSimilarity(targetName, imageName)
            }
            
            if confidence > 0.4 {
                if bestMatch == nil || confidence > bestMatch!.confidence {
                    bestMatch = (image.filename, confidence)
                }
            }
        }
        
        return bestMatch
    }
    
    /// Calculate string similarity using Levenshtein distance
    private func calculateSimilarity(_ str1: String, _ str2: String) -> Double {
        let len1 = str1.count
        let len2 = str2.count
        
        if len1 == 0 || len2 == 0 {
            return 0.0
        }
        
        // Check for substring match first
        if str1.contains(str2) || str2.contains(str1) {
            let minLen = min(len1, len2)
            let maxLen = max(len1, len2)
            return Double(minLen) / Double(maxLen)
        }
        
        // Levenshtein distance
        let arr1 = Array(str1)
        let arr2 = Array(str2)
        
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: len2 + 1), count: len1 + 1)
        
        for i in 0...len1 {
            matrix[i][0] = i
        }
        for j in 0...len2 {
            matrix[0][j] = j
        }
        
        for i in 1...len1 {
            for j in 1...len2 {
                let cost = arr1[i - 1] == arr2[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }
        
        let distance = matrix[len1][len2]
        let maxLen = max(len1, len2)
        
        return 1.0 - (Double(distance) / Double(maxLen))
    }
    
    /// Calculate overall validation status for a cabinet
    private func calculateOverallStatus(for cabinet: CabinetDetail) -> ValidationStatus {
        if !cabinet.hasDescription {
            return .error("No description.yaml found")
        }
        
        let errors = cabinet.parts.filter { $0.validationStatus.isError }
        let warnings = cabinet.parts.filter { $0.validationStatus.isWarning || $0.validationStatus.hasSuggestion }
        
        if !errors.isEmpty {
            return .error("\(errors.count) missing texture(s)")
        }
        
        if !warnings.isEmpty {
            return .warning("\(warnings.count) part(s) need attention")
        }
        
        return .valid
    }
    
    // MARK: - Batch Validation
    
    /// Validate multiple cabinets and return summary
    func validateBatch(_ cabinets: [CabinetDetail]) -> ValidationSummary {
        var ready = 0
        var warnings = 0
        var errors = 0
        var issues: [ValidationIssue] = []
        
        for cabinet in cabinets {
            switch cabinet.overallStatus {
            case .valid:
                ready += 1
            case .warning(let msg):
                warnings += 1
                issues.append(ValidationIssue(
                    cabinetName: cabinet.name,
                    severity: .warning,
                    message: msg
                ))
            case .error(let msg):
                errors += 1
                issues.append(ValidationIssue(
                    cabinetName: cabinet.name,
                    severity: .error,
                    message: msg
                ))
            case .suggestion:
                warnings += 1
            }
        }
        
        return ValidationSummary(
            totalCount: cabinets.count,
            readyCount: ready,
            warningCount: warnings,
            errorCount: errors,
            issues: issues
        )
    }
}

// MARK: - Validation Summary

struct ValidationSummary {
    let totalCount: Int
    let readyCount: Int
    let warningCount: Int
    let errorCount: Int
    let issues: [ValidationIssue]
    
    var canProceed: Bool {
        errorCount == 0
    }
    
    var hasWarnings: Bool {
        warningCount > 0
    }
}

struct ValidationIssue: Identifiable {
    let id = UUID()
    let cabinetName: String
    let severity: Severity
    let message: String
    
    enum Severity {
        case warning
        case error
    }
}
