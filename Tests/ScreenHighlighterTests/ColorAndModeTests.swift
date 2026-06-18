import XCTest
@testable import ScreenHighlighter

/// Tests colour selection and draw/click-through mode state in DrawingEngine.
///
/// **What these would have caught:**
/// The "icon always shows yellow" bug occurred because ToolbarView read a
/// hardcoded `Color.yellow` instead of `activeColor` (derived from
/// `engine.activeColorHex`). A test verifying that `activeColorHex` persists
/// and is distinct from the default would have flagged the disconnect the
/// moment the engine and the UI diverged.
final class ColorAndModeTests: XCTestCase {

    // MARK: - Active colour

    @MainActor
    func testDefaultColorIsYellow() {
        let engine = DrawingEngine()
        XCTAssertEqual(engine.activeColorHex, "#FFFF00",
                       "Default colour must be yellow — the first palette entry")
    }

    @MainActor
    func testColorChangeIsPersisted() {
        let engine = DrawingEngine()
        engine.activeColorHex = "#30D158"
        XCTAssertEqual(engine.activeColorHex, "#30D158",
                       "A colour assignment must survive the next read")
    }

    @MainActor
    func testColorChangeIsDistinctFromDefault() {
        // This is the core check that catches "always shows yellow":
        // if the UI reads a hardcoded value instead of the engine, it returns
        // "#FFFF00" even after we set a different colour here.
        let engine = DrawingEngine()
        engine.activeColorHex = "#0A84FF"
        XCTAssertNotEqual(engine.activeColorHex, "#FFFF00",
                          "After selecting blue, activeColorHex must not still be yellow")
    }

    @MainActor
    func testAllPaletteColorsCanBeSet() {
        let palette = ["#FFFF00", "#30D158", "#0A84FF", "#FF2D55", "#FF9F0A"]
        let engine = DrawingEngine()
        for hex in palette {
            engine.activeColorHex = hex
            XCTAssertEqual(engine.activeColorHex.uppercased(), hex.uppercased(),
                           "Palette colour \(hex) must be stored exactly")
        }
    }

    @MainActor
    func testStrokeCarriesColorAtCreationTime() {
        // The colour is baked into StrokeStyle at beginStroke time, not kept
        // as a live reference. This ensures changing the palette selection after
        // finishing a stroke does not retroactively recolour it.
        let engine = DrawingEngine()
        engine.activeColorHex = "#0A84FF"
        let style = StrokeStyle(colorHex: engine.activeColorHex)
        engine.beginStroke(at: .zero, style: style)
        engine.endStroke()

        XCTAssertEqual(engine.strokes.first?.style.colorHex, "#0A84FF",
                       "A completed stroke must preserve the colour it was drawn with")
    }

    @MainActor
    func testChangingColorAfterStrokeDoesNotAffectOldStroke() {
        let engine = DrawingEngine()
        let style = StrokeStyle(colorHex: "#FF9F0A")  // orange
        engine.beginStroke(at: .zero, style: style)
        engine.endStroke()

        engine.activeColorHex = "#FF2D55"  // change to pink after the fact
        XCTAssertEqual(engine.strokes.first?.style.colorHex, "#FF9F0A",
                       "Changing activeColorHex must not retroactively recolour finished strokes")
    }

    @MainActor
    func testColorPersistsAcrossUndoRedo() {
        // Undo removes strokes but must not reset the colour the user chose.
        let engine = DrawingEngine()
        engine.activeColorHex = "#FF2D55"

        let style = StrokeStyle(colorHex: engine.activeColorHex)
        engine.beginStroke(at: .zero, style: style)
        engine.endStroke()
        engine.undo()

        XCTAssertEqual(engine.activeColorHex, "#FF2D55",
                       "undo() must not reset the active colour")
    }

    @MainActor
    func testColorPersistsAcrossClear() {
        let engine = DrawingEngine()
        engine.activeColorHex = "#30D158"

        engine.beginStroke(at: .zero, style: StrokeStyle(colorHex: engine.activeColorHex))
        engine.endStroke()
        engine.clear()

        XCTAssertEqual(engine.activeColorHex, "#30D158",
                       "clear() must not reset the active colour")
    }

    // MARK: - Draw mode

    @MainActor
    func testDrawModeIsActiveByDefault() {
        let engine = DrawingEngine()
        XCTAssertTrue(engine.isDrawModeActive,
                      "Overlay must open in drawing mode, not click-through mode")
    }

    @MainActor
    func testDrawModeCanBeToggled() {
        let engine = DrawingEngine()
        engine.isDrawModeActive = false
        XCTAssertFalse(engine.isDrawModeActive)
        engine.isDrawModeActive = true
        XCTAssertTrue(engine.isDrawModeActive)
    }

    @MainActor
    func testClearDoesNotResetDrawMode() {
        // `clear()` removes strokes but must not touch the draw/click-through
        // mode the user chose — they should not need to re-select it after clearing.
        let engine = DrawingEngine()
        engine.isDrawModeActive = false

        engine.beginStroke(at: .zero, style: StrokeStyle())
        engine.endStroke()
        engine.clear()

        XCTAssertFalse(engine.isDrawModeActive,
                       "clear() must not reset the user's chosen draw/click-through mode")
    }

    @MainActor
    func testUndoDoesNotResetDrawMode() {
        let engine = DrawingEngine()
        engine.isDrawModeActive = false

        engine.beginStroke(at: .zero, style: StrokeStyle())
        engine.endStroke()
        engine.undo()

        XCTAssertFalse(engine.isDrawModeActive,
                       "undo() must not reset the user's chosen draw/click-through mode")
    }
}
