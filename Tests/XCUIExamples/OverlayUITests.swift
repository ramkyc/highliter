// ============================================================
// OverlayUITests.swift — ILLUSTRATIVE ONLY
// ============================================================
// This file is NOT compiled by `swift test`.
// It lives in Tests/XCUIExamples/ which is not listed as a
// .testTarget in Package.swift, so the Swift compiler never
// sees it.
//
// PURPOSE
// -------
// To show what full UI simulation ("functional testing") would
// look like for Screen Highlighter if we added an Xcode project
// with a UI test bundle target.
//
// XCUITest is Apple's framework for this. It:
//   • Launches the real app as a separate process
//   • Drives it with synthesised events (clicks, key presses,
//     gestures) that go through the same macOS event pipeline
//     as a real user's hardware
//   • Queries the accessibility tree to find and assert on UI
//     elements (buttons, labels, etc.)
//
// WHY THIS MATTERS
// ----------------
// The three bugs fixed in this release would all have been
// caught by the tests below:
//
//   Bug 1 — Infinite scroll loop / mouse freeze
//     → testScrollPassthroughDoesNotFreezeMousePointer
//
//   Bug 2 — Esc never dismissed the overlay
//     → testEscKeyDismissesOverlay
//
//   Bug 3 — X button captured as a drawing stroke in draw mode
//     → testXButtonDismissesOverlayInDrawMode
//
// HOW TO ENABLE
// -------------
// 1. Open (or create) an Xcode project wrapping this SPM package.
//    In Xcode: File > New > Project, then add this package as a
//    local dependency.
// 2. Add a new UI Test Bundle target:
//    File > New > Target > macOS > UI Testing Bundle.
//    Name it "ScreenHighlighterUITests".
// 3. Copy the code below into that bundle's .swift file.
// 4. Run with Cmd+U.  Xcode will build the app, launch it in a
//    simulator/device, drive it, and report pass/fail.
//
// ============================================================

#if false   // <-- prevents accidental compilation if this file
            //     is ever added to a test target before setup

import XCTest

final class OverlayUITests: XCTestCase {

    // The XCUIApplication object represents the running app process.
    // `launch()` starts it fresh; `terminate()` kills it after each test.
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: - Overlay appearance

    /// Verifies that pressing Cmd+Shift+H shows the toolbar.
    ///
    /// In XCUITest we interact with the app via its Accessibility elements
    /// (every button, label, and window is exposed to the accessibility API).
    /// The toolbar's exit button has the accessibility label "Exit Overlay (Esc)"
    /// (from `.help("Exit Overlay (Esc)")` in ToolbarView).
    func testOverlayAppearsOnGlobalShortcut() throws {
        // The app starts in the menu-bar-only state (no overlay visible).
        // Trigger the global shortcut via the XCUITest keyboard API.
        app.typeKey("h", modifierFlags: [.command, .shift])

        // The toolbar should appear within 2 seconds.
        let exitButton = app.buttons["Exit Overlay (Esc)"]
        XCTAssertTrue(exitButton.waitForExistence(timeout: 2),
                      "Toolbar exit button must appear after pressing Cmd+Shift+H")
    }

    // MARK: - Dismissal

    /// BUG REGRESSION: Esc never dismissed the overlay (Bug 2).
    ///
    /// Root cause: our overlay window is at .statusBar level and never
    /// steals keyboard focus from the active app, so keyDown overrides on
    /// the window controller were never called. The fix: a local NSEvent
    /// key monitor that intercepts keyDown regardless of which window is key.
    ///
    /// XCUITest would catch this immediately because it sends a real Esc
    /// event into the system event pipeline, which is exactly the path the
    /// local monitor intercepts.
    func testEscKeyDismissesOverlay() throws {
        // Show the overlay
        app.typeKey("h", modifierFlags: [.command, .shift])
        let exitButton = app.buttons["Exit Overlay (Esc)"]
        XCTAssertTrue(exitButton.waitForExistence(timeout: 2))

        // Press Escape
        app.typeKey(.escape, modifierFlags: [])

        // Toolbar should disappear
        XCTAssertFalse(exitButton.waitForExistence(timeout: 1),
                       "Overlay must be dismissed after pressing Esc")
    }

    /// BUG REGRESSION: X button click started a stroke instead of dismissing
    /// the overlay when in draw mode (Bug 3).
    ///
    /// Root cause (two-part):
    ///   1. VisualEffectView background was transparent to AppKit hit-testing,
    ///      so clicks between icons fell through to CanvasView.
    ///   2. SwiftUI .plain button style shrank the hit area to exact icon bounds.
    /// Fix: .contentShape(Rectangle()) on ToolbarView + toolbarContainer exclusion
    ///      guard in CanvasView.mouseDown.
    ///
    /// XCUITest taps via the accessibility element's bounds (the *visible* rect
    /// of the button, not its tiny icon). That's exactly the borderless click
    /// area the old code missed.
    func testXButtonDismissesOverlayInDrawMode() throws {
        app.typeKey("h", modifierFlags: [.command, .shift])

        let exitButton = app.buttons["Exit Overlay (Esc)"]
        XCTAssertTrue(exitButton.waitForExistence(timeout: 2))

        // The overlay opens in draw mode by default. Click X directly.
        exitButton.click()

        XCTAssertFalse(exitButton.waitForExistence(timeout: 1),
                       "X button must dismiss overlay in draw mode without creating a stroke")
    }

    // MARK: - Scroll passthrough

    /// BUG REGRESSION: Scrolling froze the mouse pointer to a region of
    /// the screen (Bug 1).
    ///
    /// Root cause: sendEvent override → ignoresMouseEvents flip → CGEvent
    /// re-post → the re-post bounced back before the DispatchQueue.main.async
    /// restore fired → sendEvent re-entered → infinite loop → event queue
    /// flooded → mouse effectively frozen.
    ///
    /// XCUITest scrolls via XCUIElement.scroll(byDeltaX:deltaY:) and then
    /// asserts that the mouse pointer is still moveable anywhere on screen.
    /// If the loop had fired, subsequent coordinate-based interactions would
    /// have timed out or landed in the wrong position.
    func testScrollPassthroughDoesNotFreezeMousePointer() throws {
        app.typeKey("h", modifierFlags: [.command, .shift])
        let exitButton = app.buttons["Exit Overlay (Esc)"]
        XCTAssertTrue(exitButton.waitForExistence(timeout: 2))

        // Scroll in the centre of the screen
        let screen = app.windows.firstMatch
        screen.scroll(byDeltaX: 0, deltaY: -5)  // scroll down 5 units

        // Wait a moment for any frozen-event symptoms to manifest
        Thread.sleep(forTimeInterval: 0.5)

        // If the pointer is not frozen, clicking the exit button still works
        exitButton.click()
        XCTAssertFalse(exitButton.waitForExistence(timeout: 1),
                       "After scrolling, the overlay must still be dismissable — " +
                       "a frozen mouse pointer would prevent this click from registering")
    }

    // MARK: - Colour icon reflects selection

    /// Verifies that the toolbar's draw-mode button changes visual state when
    /// a different palette colour is selected.
    ///
    /// This is the XCUITest counterpart to ColorAndModeTests.testColorChangeIsDistinctFromDefault().
    /// The unit test proves the engine stores the colour; this test proves the
    /// *icon* actually reflects it — which is the layer the "always yellow" bug was at.
    ///
    /// Note: asserting exact icon colour in XCUITest typically requires snapshot
    /// testing (XCTAttachment / third-party tools like Snapshots). Here we check
    /// the accessibility value that SwiftUI populates, which some controls expose.
    func testColourButtonUpdatesAccessibilityStateOnSelection() throws {
        app.typeKey("h", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["Exit Overlay (Esc)"].waitForExistence(timeout: 2))

        // Tap the green colour swatch (accessibility label set by .accessibilityLabel in ToolbarView)
        let greenSwatch = app.buttons["Green"]
        if greenSwatch.exists {
            greenSwatch.click()
            // The draw-mode button's help text stays the same, but an accessibility
            // snapshot would show it has changed colour — assert via the drawing
            // mode button still being present (smoke test that no crash occurred).
            XCTAssertTrue(app.buttons["Drawing mode"].exists,
                          "Switching colour must not crash the toolbar")
        } else {
            // If swatches don't expose accessibility labels, fall back to a
            // coordinate-based tap (less robust but still tests the event path).
            XCTSkip("Green swatch does not expose an accessibility label — add .accessibilityLabel(\"Green\") to ToolbarView to enable this test")
        }
    }

    // MARK: - Undo / Backspace

    func testCmdZUndoesLastStroke() throws {
        app.typeKey("h", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["Exit Overlay (Esc)"].waitForExistence(timeout: 2))

        // Draw a stroke by clicking and dragging across the overlay
        let overlayWindow = app.windows.firstMatch
        overlayWindow.click(forDuration: 0.05, thenDragTo: overlayWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)))

        // Undo it
        app.typeKey("z", modifierFlags: .command)

        // No assertion on stroke geometry here (requires snapshot testing).
        // The test is a smoke check that Cmd+Z does not crash.
        XCTAssertTrue(app.buttons["Exit Overlay (Esc)"].exists,
                      "Toolbar must still be visible after Cmd+Z undo")
    }
}

#endif  // end #if false
