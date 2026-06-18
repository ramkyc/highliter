import XCTest
@testable import ScreenHighlighter

/// Tests the value-type data model: StrokePoint, StrokeStyle, Stroke,
/// and the NSColor hex-parsing extension.
///
/// These are the lowest-level tests in the suite — they verify that the
/// building blocks are correct before testing higher-level engine behaviour.
/// Failures here almost always indicate a source change that broke serialisation
/// compatibility (StrokePoint/Stroke are Codable) or colour rendering.
final class StrokeModelTests: XCTestCase {

    // MARK: - StrokeStyle defaults

    func testStrokeStyleDefaults() {
        let style = StrokeStyle()
        XCTAssertEqual(style.width, 20.0)
        XCTAssertEqual(style.opacity, 0.35)
        XCTAssertEqual(style.colorHex, "#FFFF00")
    }

    func testStrokeStyleCustomInit() {
        let style = StrokeStyle(width: 10, opacity: 0.5, colorHex: "#0A84FF")
        XCTAssertEqual(style.width, 10.0)
        XCTAssertEqual(style.opacity, 0.5)
        XCTAssertEqual(style.colorHex, "#0A84FF")
    }

    // MARK: - StrokeStyle.nsColor

    func testNSColorIsNonNilForValidHex() {
        let palettes = ["#FFFF00", "#30D158", "#0A84FF", "#FF2D55", "#FF9F0A"]
        for hex in palettes {
            let style = StrokeStyle(colorHex: hex)
            XCTAssertNotNil(style.nsColor,
                            "Palette colour \(hex) must produce a non-nil NSColor")
        }
    }

    func testNSColorFallsBackToYellowForInvalidHex() {
        // When the hex string can't be parsed, nsColor falls back to yellow
        // with the requested opacity — it must not return nil or crash.
        let style = StrokeStyle(colorHex: "NOT_A_COLOR")
        XCTAssertNotNil(style.nsColor,
                        "An invalid hex must fall back gracefully rather than returning nil")
    }

    func testNSColorOpacityIsApplied() {
        let style = StrokeStyle(width: 20, opacity: 0.5, colorHex: "#FFFF00")
        let color = style.nsColor
        // alphaComponent should reflect the opacity set in StrokeStyle
        XCTAssertEqual(color.alphaComponent, 0.5, accuracy: 0.01)
    }

    // MARK: - NSColor(hex:)

    func testHexParserStripsHashPrefix() {
        XCTAssertNotNil(NSColor(hex: "#FFFF00"),
                        "Hex string with '#' prefix must be parsed correctly")
    }

    func testHexParserWorksWithoutHashPrefix() {
        XCTAssertNotNil(NSColor(hex: "FFFF00"),
                        "Hex string without '#' prefix must also be parsed correctly")
    }

    func testHexParserIsCaseInsensitive() {
        // The extension uppercases before parsing, so lower-case is valid.
        XCTAssertNotNil(NSColor(hex: "#ffff00"))
        XCTAssertNotNil(NSColor(hex: "ffff00"))
    }

    func testHexParserRequiresSixDigits() {
        XCTAssertNil(NSColor(hex: "#FFF"),
                     "Three-char shorthand is not supported — must return nil")
        XCTAssertNil(NSColor(hex: "FFFFF"),
                     "Five-char string must return nil")
        XCTAssertNil(NSColor(hex: "#FFFFFFF"),
                     "Seven-char string must return nil")
    }

    func testHexParserRejectsEmptyString() {
        XCTAssertNil(NSColor(hex: ""))
        XCTAssertNil(NSColor(hex: "#"))
    }

    func testHexParserRejectsInvalidCharacters() {
        XCTAssertNil(NSColor(hex: "ZZZZZZ"),
                     "Non-hex characters must cause the parser to return nil")
        XCTAssertNil(NSColor(hex: "GG1122"))
    }

    // MARK: - StrokePoint

    func testStrokePointCGPointRoundtrip() {
        let pt = StrokePoint(x: 123.45, y: 678.9)
        XCTAssertEqual(pt.cgPoint.x, 123.45, accuracy: 0.001)
        XCTAssertEqual(pt.cgPoint.y, 678.9, accuracy: 0.001)
    }

    func testStrokePointEqualityIncludesTimestamp() {
        let ts: TimeInterval = 1_000_000
        let p1 = StrokePoint(x: 10, y: 20, timestamp: ts)
        let p2 = StrokePoint(x: 10, y: 20, timestamp: ts)
        XCTAssertEqual(p1, p2)
    }

    func testStrokePointInequalOnCoordinates() {
        let ts: TimeInterval = 1_000_000
        XCTAssertNotEqual(
            StrokePoint(x: 10, y: 20, timestamp: ts),
            StrokePoint(x: 10, y: 99, timestamp: ts)
        )
    }

    func testStrokePointInequalOnTimestamp() {
        // Equatable is synthesised over all stored fields, including timestamp.
        let p1 = StrokePoint(x: 10, y: 20, timestamp: 1_000_000)
        let p2 = StrokePoint(x: 10, y: 20, timestamp: 2_000_000)
        XCTAssertNotEqual(p1, p2)
    }

    func testStrokePointCoordinatesPreserveSign() {
        // Negative coordinates are valid (canvas origin is bottom-left on macOS).
        let pt = StrokePoint(x: -50.5, y: -100.25)
        XCTAssertEqual(pt.x, -50.5, accuracy: 0.001)
        XCTAssertEqual(pt.y, -100.25, accuracy: 0.001)
    }

    // MARK: - Stroke

    func testStrokeDefaultInit() {
        let stroke = Stroke()
        XCTAssertTrue(stroke.points.isEmpty)
        XCTAssertNil(stroke.bandRanges,
                     "bandRanges must be nil for a plain freehand stroke")
    }

    func testEachStrokeGetsUniqueID() {
        // 100 strokes → 100 distinct UUIDs.
        let ids = (0..<100).map { _ in Stroke().id }
        XCTAssertEqual(Set(ids).count, 100,
                       "Each Stroke() call must produce a unique UUID")
    }

    func testStrokeEqualityOnSameID() {
        let id = UUID()
        let s1 = Stroke(id: id)
        let s2 = Stroke(id: id)
        XCTAssertEqual(s1, s2)
    }

    func testStrokeInequalityOnDifferentIDs() {
        XCTAssertNotEqual(Stroke(), Stroke())
    }

    func testStrokeWithBandRanges() {
        let bands: [Range<Int>] = [0..<2, 2..<4]
        let points = [
            StrokePoint(x: 0, y: 100), StrokePoint(x: 200, y: 100),
            StrokePoint(x: 0, y: 80),  StrokePoint(x: 200, y: 80)
        ]
        let stroke = Stroke(points: points, bandRanges: bands)
        XCTAssertEqual(stroke.bandRanges?.count, 2)
        XCTAssertEqual(stroke.points.count, 4)
    }

    // MARK: - refineStroke (engine integration)

    @MainActor
    func testRefineStrokeReplacesPoints() throws {
        let engine = DrawingEngine()
        engine.beginStroke(at: CGPoint(x: 10, y: 10), style: StrokeStyle())
        engine.appendPoint(CGPoint(x: 50, y: 50))
        engine.endStroke()
        let id = try XCTUnwrap(engine.strokes.first?.id)

        // Simulate OCR replacing the heuristic geometry with precise text-line positions
        let refined = [StrokePoint(x: 100, y: 200), StrokePoint(x: 400, y: 200)]
        engine.refineStroke(id: id, points: refined, bandRanges: [0..<2])

        XCTAssertEqual(engine.strokes.first?.points.count, 2)
        let firstPoint = try XCTUnwrap(engine.strokes.first?.points.first)
        XCTAssertEqual(firstPoint.x, 100, accuracy: 0.1)
        XCTAssertEqual(engine.strokes.first?.bandRanges?.count, 1)
    }

    @MainActor
    func testRefineStrokePreservesStyleAndID() throws {
        let engine = DrawingEngine()
        let style = StrokeStyle(colorHex: "#FF2D55")
        engine.beginStroke(at: .zero, style: style)
        engine.endStroke()
        let id = try XCTUnwrap(engine.strokes.first?.id)

        engine.refineStroke(id: id, points: [StrokePoint(x: 1, y: 2)], bandRanges: [0..<1])

        XCTAssertEqual(engine.strokes.first?.id, id,
                       "refineStroke must not change the stroke's ID")
        XCTAssertEqual(engine.strokes.first?.style.colorHex, "#FF2D55",
                       "refineStroke must not change the stroke's style")
    }

    @MainActor
    func testRefineStrokeNoOpsOnUnknownID() throws {
        let engine = DrawingEngine()
        engine.beginStroke(at: CGPoint(x: 10, y: 10), style: StrokeStyle())
        engine.appendPoint(CGPoint(x: 50, y: 50))
        engine.endStroke()
        let original = engine.strokes.first?.points

        engine.refineStroke(id: UUID(), points: [StrokePoint(x: 999, y: 999)], bandRanges: [0..<1])
        XCTAssertEqual(engine.strokes.first?.points, original,
                       "refineStroke with an unknown ID must not touch any stroke")
    }

    @MainActor
    func testRefineStrokeNoOpsOnEmptyInput() throws {
        let engine = DrawingEngine()
        engine.beginStroke(at: CGPoint(x: 10, y: 10), style: StrokeStyle())
        engine.appendPoint(CGPoint(x: 50, y: 50))
        engine.endStroke()
        let id = try XCTUnwrap(engine.strokes.first?.id)
        let originalCount = engine.strokes.first?.points.count

        engine.refineStroke(id: id, points: [], bandRanges: [])
        XCTAssertEqual(engine.strokes.first?.points.count, originalCount,
                       "refineStroke with empty points must leave the stroke geometry unchanged")
    }
}
