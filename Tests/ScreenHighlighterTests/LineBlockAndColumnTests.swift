import XCTest
@testable import ScreenHighlighter

/// Tests multi-line block highlight geometry and column bounds management.
///
/// The line-block feature is the most geometrically complex part of the engine:
/// it converts a two-point drag into a stack of horizontal bands that mimic a
/// real text selection. Most of these tests assert invariants that are invisible
/// during normal use but can silently produce wrong highlights if broken (e.g.,
/// the anchor-drift bug, which created highlights that were too narrow whenever
/// the user dragged leftward or upward).
final class LineBlockAndColumnTests: XCTestCase {

    // MARK: - Band count

    @MainActor
    func testSingleLineDragProducesOneBand() throws {
        let engine = DrawingEngine()
        // Drag is horizontal — stays within one line height
        engine.beginStroke(at: CGPoint(x: 100, y: 100), style: StrokeStyle())
        engine.updateActiveStrokeAsLineBlock(to: CGPoint(x: 300, y: 100), lineHeight: 20)

        let bands = try XCTUnwrap(engine.activeStroke?.bandRanges)
        XCTAssertEqual(bands.count, 1,
                       "A horizontal same-line drag must produce exactly one band")
    }

    @MainActor
    func testMultiLineDragProducesMultipleBands() throws {
        let engine = DrawingEngine()
        // 100 vertical pixels at lineHeight 20 → ~5–6 bands
        engine.beginStroke(at: CGPoint(x: 100, y: 200), style: StrokeStyle())
        engine.updateActiveStrokeAsLineBlock(to: CGPoint(x: 300, y: 100), lineHeight: 20)

        let bands = try XCTUnwrap(engine.activeStroke?.bandRanges)
        XCTAssertGreaterThan(bands.count, 1,
                             "A drag spanning multiple line heights must produce more than one band")
    }

    @MainActor
    func testZeroVerticalDragStillProducesAtLeastOneBand() throws {
        // The engine must always cover at least the anchor's own line even for
        // a tiny accidental drag — "highlights nothing" is never the right outcome.
        let engine = DrawingEngine()
        engine.beginStroke(at: CGPoint(x: 100, y: 100), style: StrokeStyle())
        engine.updateActiveStrokeAsLineBlock(to: CGPoint(x: 101, y: 100), lineHeight: 20)

        let bands = try XCTUnwrap(engine.activeStroke?.bandRanges)
        XCTAssertGreaterThanOrEqual(bands.count, 1,
                                    "Even a near-zero drag must produce at least one band")
    }

    @MainActor
    func testEachBandHasTwoPoints() throws {
        // Each band in bandRanges indexes exactly [start, end] in points.
        let engine = DrawingEngine()
        engine.beginStroke(at: CGPoint(x: 100, y: 200), style: StrokeStyle())
        engine.updateActiveStrokeAsLineBlock(to: CGPoint(x: 300, y: 100), lineHeight: 20)

        let stroke = try XCTUnwrap(engine.activeStroke)
        let bands = try XCTUnwrap(stroke.bandRanges)

        for band in bands {
            XCTAssertEqual(band.count, 2,
                           "Every band range must index exactly two points (start and end)")
        }
    }

    // MARK: - Anchor stability

    @MainActor
    func testAnchorStaysStableAcrossMultipleUpdates() throws {
        // REGRESSION TEST — anchor-drift bug:
        //
        // The old code derived the anchor from `current.points.first` on every
        // call. Since `updateActiveStrokeAsLineBlock` overwrites `points` with
        // band geometry, `current.points.first` was already a band point (the
        // leftmost point of the topmost band) on the second call — drifting
        // left on every update of a leftward/upward drag. This produced narrow,
        // mispositioned highlights.
        //
        // The fix captures the anchor once in a separate `lineBlockAnchor`
        // property that `endStroke` clears but `updateActiveStrokeAsLineBlock`
        // never overwrites.
        let engine = DrawingEngine()
        let anchorX: CGFloat = 100

        engine.beginStroke(at: CGPoint(x: anchorX, y: 200), style: StrokeStyle())

        // Three progressive updates of a leftward + upward drag
        engine.updateActiveStrokeAsLineBlock(to: CGPoint(x: 80, y: 180), lineHeight: 20)
        engine.updateActiveStrokeAsLineBlock(to: CGPoint(x: 60, y: 160), lineHeight: 20)
        engine.updateActiveStrokeAsLineBlock(to: CGPoint(x: 40, y: 140), lineHeight: 20)

        let range = try XCTUnwrap(engine.lineBlockRange,
                                  "lineBlockRange must be set while a gesture is active")
        XCTAssertEqual(range.anchor.x, anchorX, accuracy: 0.1,
                       "Anchor x must remain at the original mouseDown position throughout the drag")
        XCTAssertEqual(range.current.x, 40, accuracy: 0.1,
                       "Current point must reflect the most recent drag position")
    }

    @MainActor
    func testBandHorizontalExtentMatchesAnchorToCurrent() throws {
        // Each band is a horizontal segment from min(anchorX, currentX)
        // to max(anchorX, currentX). This verifies that relationship.
        let engine = DrawingEngine()
        let anchorX: CGFloat = 50
        let currentX: CGFloat = 250

        engine.beginStroke(at: CGPoint(x: anchorX, y: 200), style: StrokeStyle())
        engine.updateActiveStrokeAsLineBlock(to: CGPoint(x: currentX, y: 200), lineHeight: 20)

        let points = try XCTUnwrap(engine.activeStroke?.points)
        XCTAssertFalse(points.isEmpty)

        let minPX = points.map(\.x).min() ?? 0
        let maxPX = points.map(\.x).max() ?? 0
        XCTAssertEqual(minPX, anchorX, accuracy: 0.1,
                       "Left edge of every band must be min(anchorX, currentX)")
        XCTAssertEqual(maxPX, currentX, accuracy: 0.1,
                       "Right edge of every band must be max(anchorX, currentX)")
    }

    @MainActor
    func testRightwardAndLeftwardDragProduceSameExtent() throws {
        // Direction of drag must not affect band width — only its horizontal span.
        let engine1 = DrawingEngine()
        engine1.beginStroke(at: CGPoint(x: 100, y: 150), style: StrokeStyle())
        engine1.updateActiveStrokeAsLineBlock(to: CGPoint(x: 400, y: 150), lineHeight: 20)

        let engine2 = DrawingEngine()
        engine2.beginStroke(at: CGPoint(x: 400, y: 150), style: StrokeStyle())
        engine2.updateActiveStrokeAsLineBlock(to: CGPoint(x: 100, y: 150), lineHeight: 20)

        let pts1 = try XCTUnwrap(engine1.activeStroke?.points)
        let pts2 = try XCTUnwrap(engine2.activeStroke?.points)

        let min1 = pts1.map(\.x).min() ?? 0; let max1 = pts1.map(\.x).max() ?? 0
        let min2 = pts2.map(\.x).min() ?? 0; let max2 = pts2.map(\.x).max() ?? 0

        XCTAssertEqual(min1, min2, accuracy: 0.1, "Min x must be the same regardless of drag direction")
        XCTAssertEqual(max1, max2, accuracy: 0.1, "Max x must be the same regardless of drag direction")
    }

    // MARK: - Scope clamping

    @MainActor
    func testScopeClampingConstrainsDragEndpoint() throws {
        // A highlight must never bleed past the window it began in, even when
        // the cursor strays outside the window mid-drag.
        let scope = CGRect(x: 200, y: 0, width: 600, height: 1000)  // x: 200…800

        let engine = DrawingEngine()
        engine.beginStroke(at: CGPoint(x: 400, y: 300), style: StrokeStyle(), scopeBounds: scope)
        engine.updateActiveStrokeAsLineBlock(to: CGPoint(x: 1200, y: 200), lineHeight: 20)

        let range = try XCTUnwrap(engine.lineBlockRange)
        XCTAssertEqual(range.current.x, scope.maxX, accuracy: 0.1,
                       "Drag endpoint must clamp to scope.maxX (800) when dragged beyond it")
    }

    @MainActor
    func testScopeClampingLeftEdge() throws {
        let scope = CGRect(x: 200, y: 0, width: 600, height: 1000)  // x: 200…800

        let engine = DrawingEngine()
        engine.beginStroke(at: CGPoint(x: 400, y: 300), style: StrokeStyle(), scopeBounds: scope)
        engine.updateActiveStrokeAsLineBlock(to: CGPoint(x: 50, y: 200), lineHeight: 20)

        let range = try XCTUnwrap(engine.lineBlockRange)
        XCTAssertEqual(range.current.x, scope.minX, accuracy: 0.1,
                       "Drag endpoint must clamp to scope.minX (200) when dragged beyond the left edge")
    }

    @MainActor
    func testNilScopeLeavesEndpointUnclamped() throws {
        let engine = DrawingEngine()
        engine.beginStroke(at: CGPoint(x: 100, y: 300), style: StrokeStyle(), scopeBounds: nil)
        engine.updateActiveStrokeAsLineBlock(to: CGPoint(x: 9999, y: 200), lineHeight: 20)

        let range = try XCTUnwrap(engine.lineBlockRange)
        XCTAssertEqual(range.current.x, 9999, accuracy: 0.1,
                       "Without a scope, the drag endpoint must be left unchanged")
    }

    // MARK: - lineBlockRange lifecycle

    @MainActor
    func testLineBlockRangeClearedAfterEndStroke() throws {
        let engine = DrawingEngine()
        engine.beginStroke(at: CGPoint(x: 100, y: 200), style: StrokeStyle())
        engine.updateActiveStrokeAsLineBlock(to: CGPoint(x: 300, y: 100), lineHeight: 20)
        XCTAssertNotNil(engine.lineBlockRange, "lineBlockRange must be set while gesture is active")

        engine.endStroke()
        XCTAssertNil(engine.lineBlockRange,
                     "lineBlockRange must be nil after endStroke so the next gesture starts clean")
    }

    @MainActor
    func testLineBlockRangeClearedAfterClear() {
        let engine = DrawingEngine()
        engine.beginStroke(at: CGPoint(x: 100, y: 200), style: StrokeStyle())
        engine.updateActiveStrokeAsLineBlock(to: CGPoint(x: 300, y: 100), lineHeight: 20)

        engine.clear()
        XCTAssertNil(engine.lineBlockRange)
    }

    // MARK: - Column bounds

    @MainActor
    func testColumnBoundsNilByDefault() {
        let engine = DrawingEngine()
        XCTAssertNil(engine.columnBounds)
        XCTAssertFalse(engine.isColumnDefineMode)
    }

    @MainActor
    func testColumnBoundsMakeRejectsNarrowDrag() {
        // Drags of ≤ 4 pt are almost certainly accidental clicks, not column definitions.
        XCTAssertNil(ColumnBounds.make(x1: 100, x2: 104),
                     "A drag of exactly 4pt must be rejected (guard is > 4, not >= 4)")
        XCTAssertNil(ColumnBounds.make(x1: 100, x2: 100),
                     "A zero-width drag must return nil")
        XCTAssertNil(ColumnBounds.make(x1: 100, x2: 103))
    }

    @MainActor
    func testColumnBoundsMakeAcceptsJustAboveThreshold() {
        // abs(x1 - x2) = 5 > 4 → valid
        XCTAssertNotNil(ColumnBounds.make(x1: 100, x2: 105))
    }

    @MainActor
    func testColumnBoundsMakeProducesCorrectMinMax() {
        let ltr = ColumnBounds.make(x1: 200, x2: 800)!
        XCTAssertEqual(ltr.minX, 200)
        XCTAssertEqual(ltr.maxX, 800)
        XCTAssertEqual(ltr.width, 600, accuracy: 0.01)

        // Dragging right-to-left must yield the same column as left-to-right
        let rtl = ColumnBounds.make(x1: 800, x2: 200)!
        XCTAssertEqual(rtl.minX, 200, "Right-to-left drag must give same minX")
        XCTAssertEqual(rtl.maxX, 800, "Right-to-left drag must give same maxX")
    }

    @MainActor
    func testSetColumnBoundsStoresAndExitsDefineMode() throws {
        let engine = DrawingEngine()
        engine.isColumnDefineMode = true
        let bounds = try XCTUnwrap(ColumnBounds.make(x1: 100, x2: 600))
        engine.setColumnBounds(bounds)

        XCTAssertNotNil(engine.columnBounds)
        XCTAssertEqual(engine.columnBounds?.minX, 100)
        XCTAssertFalse(engine.isColumnDefineMode,
                       "setColumnBounds must automatically exit column-define mode")
    }

    @MainActor
    func testClearColumnBoundsRemovesAndExitsDefineMode() {
        let engine = DrawingEngine()
        engine.isColumnDefineMode = true
        engine.clearColumnBounds()

        XCTAssertNil(engine.columnBounds)
        XCTAssertFalse(engine.isColumnDefineMode,
                       "clearColumnBounds must exit column-define mode")
    }

    @MainActor
    func testClearStrokesPreservesColumnBounds() throws {
        // The user explicitly defined a column. Clearing highlights must not
        // discard it — they would need to redefine it after every clear, which
        // is tedious when reviewing a page column-by-column.
        let engine = DrawingEngine()
        let bounds = try XCTUnwrap(ColumnBounds.make(x1: 100, x2: 500))
        engine.setColumnBounds(bounds)

        engine.beginStroke(at: .zero, style: StrokeStyle())
        engine.endStroke()
        engine.clear()

        XCTAssertNotNil(engine.columnBounds,
                        "Column bounds must survive clear() — the user set them intentionally")
        XCTAssertEqual(engine.columnBounds?.minX, 100)
        XCTAssertEqual(engine.columnBounds?.maxX, 500)
    }

    @MainActor
    func testUndoDoesNotAffectColumnBounds() throws {
        let engine = DrawingEngine()
        let bounds = try XCTUnwrap(ColumnBounds.make(x1: 150, x2: 750))
        engine.setColumnBounds(bounds)

        engine.beginStroke(at: .zero, style: StrokeStyle())
        engine.endStroke()
        engine.undo()

        XCTAssertNotNil(engine.columnBounds,
                        "undo() must not clear column bounds")
    }
}
