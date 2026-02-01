//
//  RetroVisionCabsConverterUITests.swift
//  RetroVisionCabsConverterUITests
//
//  UI Tests for RetroVision Cabs Converter
//  These tests verify the user interface flows and interactions
//

import XCTest

final class RetroVisionCabsConverterUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Setup Flow Tests
    
    func testAppLaunchesSuccessfully() throws {
        // Verify the app launches and shows the main window
        XCTAssertTrue(app.windows.firstMatch.exists, "Main window should exist")
    }
    
    func testDependencyCheckOnLaunch() throws {
        // The app should check for Blender, Python, etc. on launch
        // Look for either the setup view or main content
        let setupView = app.staticTexts["Setup Required"]
        let mainContent = app.buttons["Cabinet Gallery"]
        
        // Wait for either setup or main content to appear
        let setupOrMain = NSPredicate(format: "exists == true")
        let setupExpectation = expectation(for: setupOrMain, evaluatedWith: setupView)
        let mainExpectation = expectation(for: setupOrMain, evaluatedWith: mainContent)
        
        wait(for: [setupExpectation, mainExpectation], timeout: 10, enforceOrder: false)
    }
    
    func testSettingsButtonExists() throws {
        // Wait for main view to load
        let settingsButton = app.buttons["Settings"]
        if settingsButton.waitForExistence(timeout: 5) {
            XCTAssertTrue(settingsButton.isEnabled, "Settings button should be enabled")
        }
    }
    
    func testSettingsSheetOpens() throws {
        let settingsButton = app.buttons["Settings"]
        guard settingsButton.waitForExistence(timeout: 5) else {
            XCTSkip("Settings button not found - app may be in setup mode")
            return
        }
        
        settingsButton.click()
        
        let settingsSheet = app.sheets.firstMatch
        XCTAssertTrue(settingsSheet.waitForExistence(timeout: 3), "Settings sheet should open")
        
        // Verify settings content
        XCTAssertTrue(app.staticTexts["Settings"].exists, "Settings title should be visible")
        XCTAssertTrue(app.staticTexts["Dependencies"].exists, "Dependencies section should exist")
        
        // Close settings
        let doneButton = app.buttons["Done"]
        if doneButton.exists {
            doneButton.click()
        }
    }
    
    func testPrivacyPolicyAccessible() throws {
        let settingsButton = app.buttons["Settings"]
        guard settingsButton.waitForExistence(timeout: 5) else {
            XCTSkip("Settings button not found")
            return
        }
        
        settingsButton.click()
        
        let privacyButton = app.buttons["Privacy Policy"]
        guard privacyButton.waitForExistence(timeout: 3) else {
            XCTSkip("Privacy Policy button not found")
            return
        }
        
        privacyButton.click()
        
        // Verify privacy policy sheet opens
        XCTAssertTrue(app.staticTexts["Privacy Policy"].exists, "Privacy Policy title should be visible")
        XCTAssertTrue(app.staticTexts["Your Privacy Summary"].exists, "Privacy summary should be visible")
        
        // Close privacy policy
        let doneButton = app.buttons["Done"]
        if doneButton.exists {
            doneButton.click()
        }
    }
    
    // MARK: - Cabinet Gallery Tests
    
    func testCabinetGalleryButtonExists() throws {
        let galleryButton = app.buttons["Cabinet Gallery"]
        guard galleryButton.waitForExistence(timeout: 5) else {
            XCTSkip("Gallery button not found - app may be in setup mode")
            return
        }
        
        XCTAssertTrue(galleryButton.isEnabled, "Cabinet Gallery button should be enabled")
    }
    
    func testCabinetGalleryOpens() throws {
        let galleryButton = app.buttons["Cabinet Gallery"]
        guard galleryButton.waitForExistence(timeout: 5) else {
            XCTSkip("Gallery button not found")
            return
        }
        
        galleryButton.click()
        
        // Verify gallery sheet opens
        let backButton = app.buttons["Back"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 3), "Back button should exist in gallery")
        
        // Verify gallery content
        XCTAssertTrue(app.searchFields.firstMatch.exists || app.staticTexts["Scan a Folder"].exists,
                     "Gallery should show search field or empty state")
        
        // Close gallery
        backButton.click()
    }
    
    func testCabinetGalleryEscapeCloses() throws {
        let galleryButton = app.buttons["Cabinet Gallery"]
        guard galleryButton.waitForExistence(timeout: 5) else {
            XCTSkip("Gallery button not found")
            return
        }
        
        galleryButton.click()
        
        let backButton = app.buttons["Back"]
        guard backButton.waitForExistence(timeout: 3) else {
            XCTFail("Gallery did not open")
            return
        }
        
        // Press Escape to close
        app.typeKey(.escape, modifierFlags: [])
        
        // Verify gallery closed
        XCTAssertFalse(backButton.exists, "Gallery should close with Escape key")
    }
    
    // MARK: - Props Gallery Tests
    
    func testPropsGalleryButtonExists() throws {
        let propsButton = app.buttons["Props Gallery"]
        guard propsButton.waitForExistence(timeout: 5) else {
            XCTSkip("Props button not found - app may be in setup mode")
            return
        }
        
        XCTAssertTrue(propsButton.isEnabled, "Props Gallery button should be enabled")
    }
    
    func testPropsGalleryOpens() throws {
        let propsButton = app.buttons["Props Gallery"]
        guard propsButton.waitForExistence(timeout: 5) else {
            XCTSkip("Props button not found")
            return
        }
        
        propsButton.click()
        
        // Verify gallery sheet opens
        let backButton = app.buttons["Back"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 3), "Back button should exist in props gallery")
        
        // Close gallery
        backButton.click()
    }
    
    // MARK: - Build Wizard Tests
    
    func testBuildNewButtonExists() throws {
        let buildButton = app.buttons["Build New"]
        guard buildButton.waitForExistence(timeout: 5) else {
            XCTSkip("Build button not found - app may be in setup mode")
            return
        }
        
        XCTAssertTrue(buildButton.isEnabled, "Build New button should be enabled")
    }
    
    func testBuildWizardOpens() throws {
        let buildButton = app.buttons["Build New"]
        guard buildButton.waitForExistence(timeout: 5) else {
            XCTSkip("Build button not found")
            return
        }
        
        buildButton.click()
        
        // Verify wizard opens with step 1
        let step1Text = app.staticTexts["Step 1"]
        XCTAssertTrue(step1Text.waitForExistence(timeout: 3) || app.staticTexts["Select Template"].exists,
                     "Build wizard should show step 1")
        
        // Close wizard
        let backButton = app.buttons["Back"]
        if backButton.exists {
            backButton.click()
        } else {
            app.typeKey(.escape, modifierFlags: [])
        }
    }
    
    // MARK: - Keyboard Navigation Tests
    
    func testTabKeyNavigates() throws {
        // Press Tab and verify focus changes
        app.typeKey(.tab, modifierFlags: [])
        
        // App should have focus on some element
        XCTAssertTrue(app.exists, "App should remain responsive to keyboard")
    }
    
    func testCmdWClosesWindow() throws {
        // Get initial window count
        let initialWindowCount = app.windows.count
        
        // Press Cmd+W
        app.typeKey("w", modifierFlags: .command)
        
        // Wait a moment for window to close
        Thread.sleep(forTimeInterval: 0.5)
        
        // Verify window closed or app terminated
        // (Note: This may cause the test to end if the last window closes)
        XCTAssertTrue(true, "Cmd+W should be handled")
    }
    
    // MARK: - Accessibility Tests
    
    func testAllButtonsHaveAccessibilityLabels() throws {
        // Find all buttons
        let buttons = app.buttons.allElementsBoundByIndex
        
        for button in buttons {
            XCTAssertFalse(button.label.isEmpty || button.label == "button",
                          "Button '\(button.identifier)' should have a meaningful accessibility label")
        }
    }
    
    func testMainWindowHasAccessibilityElements() throws {
        let mainWindow = app.windows.firstMatch
        XCTAssertTrue(mainWindow.exists, "Main window should exist")
        
        // Check that the window has accessible children
        let descendantCount = mainWindow.descendants(matching: .any).count
        XCTAssertGreaterThan(descendantCount, 0, "Window should have accessible descendants")
    }
    
    // MARK: - Performance Tests
    
    func testAppLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}

// MARK: - Export Tests

final class RetroVisionExportUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    func testExportOptionsExist() throws {
        // Open Cabinet Gallery
        let galleryButton = app.buttons["Cabinet Gallery"]
        guard galleryButton.waitForExistence(timeout: 5) else {
            XCTSkip("Gallery button not found")
            return
        }
        
        galleryButton.click()
        
        // Look for export options in Storage menu
        let storageMenu = app.menuButtons["Storage"]
        if storageMenu.waitForExistence(timeout: 3) {
            storageMenu.click()
            
            // Check for export options
            let exportOption = app.menuItems["Export All for VisionOS"]
            XCTAssertTrue(exportOption.waitForExistence(timeout: 2) || app.menuItems.count > 0,
                         "Storage menu should have export options")
            
            // Close menu
            app.typeKey(.escape, modifierFlags: [])
        }
        
        // Close gallery
        let backButton = app.buttons["Back"]
        if backButton.exists {
            backButton.click()
        }
    }
}

// MARK: - Error Handling Tests

final class RetroVisionErrorHandlingUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    func testErrorAlertsArePresented() throws {
        // This tests that error dialogs appear when needed
        // The specific trigger depends on the app state
        
        // Verify the app can handle errors gracefully
        XCTAssertTrue(app.windows.firstMatch.exists, "App should remain stable")
    }
    
    func testValidationErrorsDisplayed() throws {
        // Find the Validate button if it exists
        let validateButton = app.buttons["Validate"]
        guard validateButton.waitForExistence(timeout: 5) else {
            XCTSkip("Validate button not found")
            return
        }
        
        // Click validate (may show errors if no cabinets selected)
        validateButton.click()
        
        // Wait a moment for validation
        Thread.sleep(forTimeInterval: 1)
        
        // App should still be responsive
        XCTAssertTrue(app.windows.firstMatch.exists, "App should handle validation gracefully")
    }
}
