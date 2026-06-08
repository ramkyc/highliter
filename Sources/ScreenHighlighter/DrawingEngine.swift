import Foundation
import Combine
import AppKit

@MainActor
public protocol DrawingEngineProtocol: AnyObject {
    var strokes: [Stroke] { get }
    var activeStroke: Stroke? { get }
    
    func beginStroke(at point: CGPoint, style: StrokeStyle, scopeBounds: CGRect?)
    func appendPoint(_ point: CGPoint)
    func updateActiveStrokeAsLineBlock(to point: CGPoint, lineHeight: CGFloat)
    func refineStroke(id: UUID, points: [StrokePoint], bandRanges: [Range<Int>])
    func endStroke()
    func undo()
    func clear()
}

@MainActor
public final class DrawingEngine: ObservableObject, DrawingEngineProtocol {
    @Published public private(set) var strokes: [Stroke] = []
    @Published public private(set) var activeStroke: Stroke?
    @Published public var activeColorHex: String = "#FFFF00"

    /// Whether the overlay is currently capturing pointer input for drawing.
    /// When `false`, the overlay window becomes click-through (except over the
    /// toolbar) so highlights remain visible while the user interacts with
    /// other apps underneath. Toggled from the toolbar's mode button.
    @Published public var isDrawModeActive: Bool = true

    /// The stable anchor point of the in-progress Shift+drag block-highlight
    /// gesture, in canvas-local coordinates, captured once when the gesture
    /// begins. `updateActiveStrokeAsLineBlock` overwrites `activeStroke.points`
    /// with band geometry on every call, so the original mouseDown location
    /// can't be read back from the stroke itself on later calls — this keeps
    /// it stable for the gesture's whole duration.
    private var lineBlockAnchor: CGPoint?

    /// The anchor and most recent point of the in-progress (or just-completed)
    /// Shift+drag block-highlight gesture, in canvas-local coordinates.
    /// `CanvasView` reads this once the gesture ends to clip an OCR-refined
    /// highlight to the exact range that was dragged across — the way a real
    /// text selection clips its first and last lines to the cursor positions
    /// rather than always covering whole lines.
    public private(set) var lineBlockRange: (anchor: CGPoint, current: CGPoint)?

    /// The bounds (in canvas-local coordinates) of the window the current
    /// gesture started over, captured once at `beginStroke` via
    /// `WindowScopeLocator`. `updateActiveStrokeAsLineBlock` clamps the drag
    /// to these bounds so a multi-line highlight can never bleed past the
    /// edges of the single window/app it began in — matching how a real text
    /// selection is always confined to one document. `nil` when no window
    /// was found under the click (e.g. bare desktop), in which case the drag
    /// is left unconstrained as before.
    ///
    /// Exposed read-only (mirroring `lineBlockRange`) so `CanvasView` can
    /// also clip the *OCR-refined* bands to it in `refineLineBlockHighlight`:
    /// clamping the drag alone isn't sufficient, since Vision can merge text
    /// fragments from a neighboring window at a similar height into a single
    /// wide detected line — without this, that merged rectangle's width
    /// would carry the bleed straight through the gesture-level clamp
    /// untouched.
    public private(set) var lineBlockScope: CGRect?

    public init() {}

    public func beginStroke(at point: CGPoint, style: StrokeStyle, scopeBounds: CGRect? = nil) {
        let firstPoint = StrokePoint(x: point.x, y: point.y)
        activeStroke = Stroke(points: [firstPoint], style: style)
        lineBlockAnchor = nil
        lineBlockRange = nil
        lineBlockScope = scopeBounds
    }

    public func appendPoint(_ point: CGPoint) {
        guard var current = activeStroke else { return }
        let newPoint = StrokePoint(x: point.x, y: point.y)
        current.points.append(newPoint)
        activeStroke = current
    }
    
    /// Reshapes the active stroke into a stack of horizontal highlight bands
    /// spanning from the stroke's anchor point to `point`, mimicking how a
    /// multi-line text selection covers every line between two points rather
    /// than drawing one straight line between them.
    ///
    /// `lineHeight` controls the vertical spacing between bands; each band is
    /// rendered as an independent straight segment (see `Stroke.bandRanges`)
    /// so consecutive lines aren't joined by a diagonal connector.
    public func updateActiveStrokeAsLineBlock(to point: CGPoint, lineHeight: CGFloat) {
        guard var current = activeStroke else { return }
        guard lineHeight > 0 else { return }

        // Capture the gesture's anchor exactly once — `current.points` is
        // about to be overwritten with band geometry below, so the original
        // mouseDown location can't be read back from the stroke on later
        // calls. Without this, a leftward-and-downward drag would silently
        // corrupt the anchor on every update (it would drift toward the
        // band's top-left corner instead of staying at mouseDown).
        let anchorPoint: CGPoint
        if let stable = lineBlockAnchor {
            anchorPoint = stable
        } else if let first = current.points.first {
            anchorPoint = first.cgPoint
            lineBlockAnchor = anchorPoint
        } else {
            return
        }
        // Clamp the live drag point to the window the gesture started in —
        // like a real text selection, a highlight should never bleed past
        // the edges of the document/app it began over, even if the cursor
        // strays beyond them mid-drag (e.g. onto the desktop or a different
        // app's window). The anchor is always inside the scope already
        // (the gesture started there), so clamping just this point keeps
        // every band that follows fully within bounds — no extra checks
        // needed downstream, including in the OCR refinement pass that reads
        // `lineBlockRange` off this same clamped point.
        let clampedPoint: CGPoint
        if let scope = lineBlockScope {
            clampedPoint = CGPoint(
                x: min(max(point.x, scope.minX), scope.maxX),
                y: min(max(point.y, scope.minY), scope.maxY)
            )
        } else {
            clampedPoint = point
        }

        lineBlockRange = (anchor: anchorPoint, current: clampedPoint)

        let minX = min(anchorPoint.x, clampedPoint.x)
        let maxX = max(anchorPoint.x, clampedPoint.x)
        let topY = max(anchorPoint.y, clampedPoint.y)
        let bottomY = min(anchorPoint.y, clampedPoint.y)

        var bandPoints: [StrokePoint] = []
        var ranges: [Range<Int>] = []

        // Walk downward from the topmost line to the bottommost line,
        // laying down one full-width band per line height. A small epsilon
        // ensures the final (possibly partial) line is still included.
        var y = topY
        let epsilon: CGFloat = lineHeight * 0.5
        while y >= bottomY - epsilon {
            let startIndex = bandPoints.count
            bandPoints.append(StrokePoint(x: minX, y: y))
            bandPoints.append(StrokePoint(x: maxX, y: y))
            ranges.append(startIndex..<(startIndex + 2))
            y -= lineHeight
        }

        // Always cover at least the anchor's own line, even for tiny drags.
        if bandPoints.isEmpty {
            bandPoints = [StrokePoint(x: minX, y: topY), StrokePoint(x: maxX, y: topY)]
            ranges = [0..<2]
        }

        current.points = bandPoints
        current.bandRanges = ranges
        activeStroke = current
    }
    
    /// Replaces a previously-completed stroke's geometry in place.
    ///
    /// Used to "snap" a heuristic multi-line highlight onto the precise
    /// positions of the real text lines underneath, once an async on-device
    /// OCR pass finishes shortly after the gesture ends. No-ops if the stroke
    /// was undone or cleared in the meantime, or if the replacement geometry
    /// is empty (callers should simply leave the heuristic bands in place
    /// rather than calling this when OCR finds nothing).
    public func refineStroke(id: UUID, points: [StrokePoint], bandRanges: [Range<Int>]) {
        guard !points.isEmpty, !bandRanges.isEmpty else { return }
        guard let index = strokes.firstIndex(where: { $0.id == id }) else { return }
        strokes[index].points = points
        strokes[index].bandRanges = bandRanges
    }

    public func endStroke() {
        guard let finalStroke = activeStroke else { return }
        // Only keep strokes that have actual movement
        if finalStroke.points.count >= 1 {
            strokes.append(finalStroke)
        }
        activeStroke = nil
        // `CanvasView.mouseUp` reads `lineBlockRange` before calling
        // `endStroke()`, so it's safe to clear gesture-scoped state here.
        lineBlockAnchor = nil
        lineBlockRange = nil
        lineBlockScope = nil
    }

    public func undo() {
        guard !strokes.isEmpty else { return }
        strokes.removeLast()
    }

    public func clear() {
        strokes.removeAll()
        activeStroke = nil
        lineBlockAnchor = nil
        lineBlockRange = nil
        lineBlockScope = nil
    }
}
