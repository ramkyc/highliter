import Foundation
import Combine
import AppKit

@MainActor
public protocol DrawingEngineProtocol: AnyObject {
    var strokes: [Stroke] { get }
    var activeStroke: Stroke? { get }
    
    func beginStroke(at point: CGPoint, style: StrokeStyle)
    func appendPoint(_ point: CGPoint)
    func endStroke()
    func undo()
    func clear()
}

@MainActor
public final class DrawingEngine: ObservableObject, DrawingEngineProtocol {
    @Published public private(set) var strokes: [Stroke] = []
    @Published public private(set) var activeStroke: Stroke?
    @Published public var activeColorHex: String = "#FFFF00"
    
    public init() {}
    
    public func beginStroke(at point: CGPoint, style: StrokeStyle) {
        let firstPoint = StrokePoint(x: point.x, y: point.y)
        activeStroke = Stroke(points: [firstPoint], style: style)
    }
    
    public func appendPoint(_ point: CGPoint) {
        guard var current = activeStroke else { return }
        let newPoint = StrokePoint(x: point.x, y: point.y)
        current.points.append(newPoint)
        activeStroke = current
    }
    
    public func endStroke() {
        guard let finalStroke = activeStroke else { return }
        // Only keep strokes that have actual movement
        if finalStroke.points.count >= 1 {
            strokes.append(finalStroke)
        }
        activeStroke = nil
    }
    
    public func undo() {
        guard !strokes.isEmpty else { return }
        strokes.removeLast()
    }
    
    public func clear() {
        strokes.removeAll()
        activeStroke = nil
    }
}
