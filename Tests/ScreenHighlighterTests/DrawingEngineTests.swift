import XCTest
@testable import ScreenHighlighter

final class DrawingEngineTests: XCTestCase {
    
    @MainActor
    func testStrokeLifecycle() {
        let engine = DrawingEngine()
        let style = StrokeStyle(width: 15.0, opacity: 0.4, colorHex: "#FFFF00")
        
        // Assert initial state
        XCTAssertTrue(engine.strokes.isEmpty)
        XCTAssertNil(engine.activeStroke)
        
        // 1. Begin stroke
        engine.beginStroke(at: CGPoint(x: 100, y: 100), style: style)
        XCTAssertNotNil(engine.activeStroke)
        XCTAssertEqual(engine.activeStroke?.points.count, 1)
        XCTAssertEqual(engine.activeStroke?.points.first?.cgPoint, CGPoint(x: 100, y: 100))
        
        // 2. Append points
        engine.appendPoint(CGPoint(x: 110, y: 110))
        engine.appendPoint(CGPoint(x: 120, y: 120))
        XCTAssertEqual(engine.activeStroke?.points.count, 3)
        
        // 3. End stroke
        engine.endStroke()
        XCTAssertNil(engine.activeStroke)
        XCTAssertEqual(engine.strokes.count, 1)
        XCTAssertEqual(engine.strokes.first?.points.count, 3)
    }
    
    @MainActor
    func testUndoBehavior() {
        let engine = DrawingEngine()
        let style = StrokeStyle()
        
        // Add two strokes
        engine.beginStroke(at: CGPoint(x: 10, y: 10), style: style)
        engine.appendPoint(CGPoint(x: 15, y: 15))
        engine.endStroke()
        
        engine.beginStroke(at: CGPoint(x: 20, y: 20), style: style)
        engine.appendPoint(CGPoint(x: 25, y: 25))
        engine.endStroke()
        
        XCTAssertEqual(engine.strokes.count, 2)
        
        // Undo last stroke
        engine.undo()
        XCTAssertEqual(engine.strokes.count, 1)
        
        // Undo again
        engine.undo()
        XCTAssertTrue(engine.strokes.isEmpty)
        
        // Undo on empty has no effect
        engine.undo()
        XCTAssertTrue(engine.strokes.isEmpty)
    }
    
    @MainActor
    func testClearStrokes() {
        let engine = DrawingEngine()
        let style = StrokeStyle()
        
        engine.beginStroke(at: CGPoint(x: 10, y: 10), style: style)
        engine.appendPoint(CGPoint(x: 15, y: 15))
        engine.endStroke()
        
        engine.beginStroke(at: CGPoint(x: 20, y: 20), style: style)
        engine.endStroke()
        
        XCTAssertFalse(engine.strokes.isEmpty)
        
        engine.clear()
        XCTAssertTrue(engine.strokes.isEmpty)
        XCTAssertNil(engine.activeStroke)
    }
}
