import Cocoa
import Combine

public final class CanvasView: NSView {
    private let engine: DrawingEngine
    private var cancellables = Set<AnyCancellable>()
    public var strokeWidth: CGFloat = 20.0
    
    public init(engine: DrawingEngine) {
        self.engine = engine
        super.init(frame: .zero)
        
        // This ensures the canvas has a transparent background
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
        
        setupObservation()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupObservation() {
        // Redraw whenever the drawing engine state updates
        engine.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.needsDisplay = true
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Mouse Event Handling
    
    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let style = StrokeStyle(width: strokeWidth, opacity: 0.35, colorHex: "#FFFF00")
        engine.beginStroke(at: point, style: style)
    }
    
    public override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        engine.appendPoint(point)
    }
    
    public override func mouseUp(with event: NSEvent) {
        engine.endStroke()
    }
    
    // MARK: - Core Graphics Rendering
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Render completed strokes plus active drawing path
        var allStrokes = engine.strokes
        if let active = engine.activeStroke {
            allStrokes.append(active)
        }
        
        for stroke in allStrokes {
            let points = stroke.points
            guard !points.isEmpty else { continue }
            
            context.saveGState()
            
            // Set stroke attributes
            let color = stroke.style.nsColor
            color.setStroke()
            
            context.setBlendMode(.normal)
            
            let path = NSBezierPath()
            path.lineWidth = stroke.style.width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            
            path.move(to: points[0].cgPoint)
            
            if points.count == 1 {
                // Tiny nudge to draw a circular dot if the user just clicked
                path.line(to: CGPoint(x: points[0].x + 0.1, y: points[0].y))
            } else if points.count == 2 {
                path.line(to: points[1].cgPoint)
            } else {
                // Organic curve smoothing via quadratic Bezier paths
                path.move(to: points[0].cgPoint)
                for i in 1..<points.count - 1 {
                    let p0 = points[i].cgPoint
                    let p1 = points[i + 1].cgPoint
                    let mid = CGPoint(x: (p0.x + p1.x) / 2.0, y: (p0.y + p1.y) / 2.0)
                    path.curve(to: mid, controlPoint1: p0, controlPoint2: p0)
                }
                if let last = points.last?.cgPoint {
                    path.line(to: last)
                }
            }
            
            path.stroke()
            context.restoreGState()
        }
    }
}
