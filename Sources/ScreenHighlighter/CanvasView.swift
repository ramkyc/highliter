import Cocoa
import Combine

public final class CanvasView: NSView {
    private let engine: DrawingEngine
    private var cancellables = Set<AnyCancellable>()
    public var strokeWidth: CGFloat = 20.0

    // MARK: - Column-definition gesture state

    /// X coordinate (canvas-local) where the column-definition drag began.
    /// Non-nil only while a column-define gesture is in progress.
    private var columnDefineAnchorX: CGFloat?

    /// Most recent X coordinate (canvas-local) of the live column-define drag.
    /// Drives the dashed preview band rendered in `draw(_:)`.
    private var columnDefineCurrentX: CGFloat?
    
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

        // In column-define mode, intercept the gesture entirely — start
        // tracking the column drag without creating any drawing stroke.
        if engine.isColumnDefineMode {
            columnDefineAnchorX = point.x
            columnDefineCurrentX = point.x
            needsDisplay = true
            return
        }

        let style = StrokeStyle(width: strokeWidth, opacity: 0.35, colorHex: engine.activeColorHex)
        engine.beginStroke(at: point, style: style, scopeBounds: lineBlockScopeBounds(forGestureStartingAt: point))
    }

    /// Finds the window under the gesture's starting point and returns its
    /// frame translated into canvas-local coordinates, so `DrawingEngine` —
    /// which only ever deals in canvas-local geometry — can clamp a
    /// multi-line highlight to it without needing to know about screens or
    /// `NSWindow`s. Returns `nil` over bare desktop, leaving the gesture
    /// unconstrained (there's no document to scope it to).
    ///
    /// This only matters for Shift+drag block highlights — single-line
    /// strokes are freehand drawing on the overlay and were never meant to be
    /// confined to a window.
    private func lineBlockScopeBounds(forGestureStartingAt canvasPoint: CGPoint) -> CGRect? {
        guard let screen = window?.screen else {
            return nil
        }
        let frame = screen.frame
        let screenPoint = CGPoint(x: canvasPoint.x + frame.minX, y: canvasPoint.y + frame.minY)
        guard let windowFrame = WindowScopeLocator.frontmostWindowFrame(at: screenPoint) else {
            return nil
        }

        return CGRect(
            x: windowFrame.minX - frame.minX,
            y: windowFrame.minY - frame.minY,
            width: windowFrame.width,
            height: windowFrame.height
        )
    }

    public override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Update the live column-define preview while dragging.
        if engine.isColumnDefineMode {
            columnDefineCurrentX = point.x
            needsDisplay = true
            return
        }

        if event.modifierFlags.contains(.shift) {
            // Shift+drag highlights every line of text between the start and
            // current point — like a multi-line text selection — instead of
            // drawing a single straight line between the two points.
            engine.updateActiveStrokeAsLineBlock(to: point, lineHeight: strokeWidth * 1.3)
        } else {
            engine.appendPoint(point)
        }
    }
    
    public override func mouseUp(with event: NSEvent) {
        // Commit or cancel the column-definition gesture.
        if engine.isColumnDefineMode {
            if let anchorX = columnDefineAnchorX, let currentX = columnDefineCurrentX,
               let bounds = ColumnBounds.make(x1: anchorX, x2: currentX) {
                engine.setColumnBounds(bounds)
            } else {
                // Drag was too small (or just a click) — cancel silently.
                engine.isColumnDefineMode = false
            }
            columnDefineAnchorX = nil
            columnDefineCurrentX = nil
            needsDisplay = true
            return
        }

        let completedStroke = engine.activeStroke
        let dragRange = engine.lineBlockRange
        let dragScope = engine.lineBlockScope
        engine.endStroke()

        // Multi-line block highlights start as an instant heuristic preview
        // (evenly-spaced full-width bands). Once the gesture ends, kick off
        // an async, on-device OCR pass that "snaps" those bands onto the real
        // text lines underneath for pixel-accurate coverage. This silently
        // falls back to the heuristic bands already drawn if Screen Recording
        // permission is missing or no text is found (e.g. an image was
        // highlighted instead of text).
        if let stroke = completedStroke, stroke.bandRanges != nil,
           let range = dragRange, let screen = window?.screen {
            refineLineBlockHighlight(strokeID: stroke.id, anchor: range.anchor, current: range.current, scope: dragScope, on: screen)
        }
    }

    /// Converts a completed block-highlight gesture's anchor (mouseDown) and
    /// release points from canvas-local into global screen coordinates, asks
    /// `TextLineDetector` for the real text lines underneath, and replaces
    /// the heuristic bands with ones that hug those lines precisely.
    ///
    /// The first and last highlighted lines are clipped to the actual drag
    /// endpoints — cursor-to-line-end on the line where the drag started,
    /// line-start-to-cursor on the line where it ended — exactly like a text
    /// selection. Lines strictly in between are highlighted in full. Without
    /// this, a highlight begun mid-line would visibly "jump" to cover that
    /// line's full width, which is what was happening before this fix.
    ///
    /// `scope` is the gesture's window-scope bounds (canvas-local, from
    /// `DrawingEngine.lineBlockScope`/`WindowScopeLocator`), if one was
    /// found. `TextLineDetector` runs OCR over the *entire display* and
    /// merges text fragments that sit at similar heights into single line
    /// rectangles (`mergedIntoLines`) — which means a detected "line" can
    /// span clean across two side-by-side windows (e.g. Terminal text and
    /// Claude chat text at the same row). Clamping the drag geometry to one
    /// window doesn't help with that: the merged rectangle's width comes
    /// from where Vision found text, not from where the cursor went. So
    /// every band built here is additionally clipped to `scope`'s
    /// horizontal extent — the actual fix for "the highlight spans into the
    /// neighboring app's window."
    private func refineLineBlockHighlight(strokeID: UUID, anchor: CGPoint, current: CGPoint, scope: CGRect?, on screen: NSScreen) {
        guard let displayID = screen.cgDirectDisplayID else { return }

        if !PermissionsManager.shared.hasScreenRecordingPermission() {
            // Surface the system prompt once; we don't block or retry here —
            // the user can simply repeat the gesture after granting access in
            // System Settings > Privacy & Security > Screen Recording.
            PermissionsManager.shared.requestScreenRecordingPermission()
            return
        }

        // The canvas fills its window's content view edge to edge, and the
        // overlay window's content rect exactly matches `screen.frame`, so
        // canvas-local (0, 0) corresponds to the global screen point
        // `(screen.frame.minX, screen.frame.minY)`.
        let frame = screen.frame
        let anchorScreen = CGPoint(x: anchor.x + frame.minX, y: anchor.y + frame.minY)
        let currentScreen = CGPoint(x: current.x + frame.minX, y: current.y + frame.minY)

        // Same canvas-local -> global-screen translation as the points
        // above, so OCR-detected line rectangles (already in screen
        // coordinates) can be clipped against it directly.
        let scopeScreen: CGRect? = scope.map {
            CGRect(x: $0.minX + frame.minX, y: $0.minY + frame.minY, width: $0.width, height: $0.height)
        }

        // Convert canvas-local column bounds to screen coordinates so they
        // can be applied directly against Vision's screen-coordinate line
        // rectangles. Only the x-axis matters here; y is unused.
        let columnBoundsScreen: ColumnBounds? = engine.columnBounds.map {
            ColumnBounds(minX: $0.minX + frame.minX, maxX: $0.maxX + frame.minX)
        }

        let region = CGRect(
            x: min(anchorScreen.x, currentScreen.x),
            y: min(anchorScreen.y, currentScreen.y),
            width: max(abs(currentScreen.x - anchorScreen.x), 1),
            height: max(abs(currentScreen.y - anchorScreen.y), 1)
        )

        // A selection's start/end follow reading order, not drag direction:
        // whichever point sits on the visually-higher line begins the range
        // (and on a shared line, the leftmost point does).
        let startPoint: CGPoint
        let endPoint: CGPoint
        if anchorScreen.y > currentScreen.y {
            (startPoint, endPoint) = (anchorScreen, currentScreen)
        } else if anchorScreen.y < currentScreen.y {
            (startPoint, endPoint) = (currentScreen, anchorScreen)
        } else if anchorScreen.x <= currentScreen.x {
            (startPoint, endPoint) = (anchorScreen, currentScreen)
        } else {
            (startPoint, endPoint) = (currentScreen, anchorScreen)
        }

        // Capture value types only (no `self`/`NSScreen`/`NSView` -- none of
        // those are `Sendable`) so the task can safely hop off the main actor
        // while OCR runs, then back on to update the engine.
        let engineRef = engine

        Task { @MainActor in
            guard let lineRects = await TextLineDetector.shared.detectLines(
                overlapping: region,
                displayID: displayID,
                displayFrame: frame
            ), !lineRects.isEmpty else {
                return
            }

            let orderedLines = lineRects.sorted { $0.minY > $1.minY }

            // Find which detected line each end of the range falls on: the
            // line whose vertical extent contains that point, or — if the
            // cursor sat in the gap between lines — the closest one.
            func lineIndex(containing y: CGFloat) -> Int {
                if let exact = orderedLines.firstIndex(where: { $0.minY <= y && y <= $0.maxY }) {
                    return exact
                }
                return orderedLines.indices.min(by: {
                    abs(orderedLines[$0].midY - y) < abs(orderedLines[$1].midY - y)
                }) ?? 0
            }

            let startLineIndex = lineIndex(containing: startPoint.y)
            let endLineIndex = lineIndex(containing: endPoint.y)
            // `startPoint.y >= endPoint.y` by construction, and lines are
            // sorted top-to-bottom, so `startLineIndex <= endLineIndex`
            // should always hold -- but guard the range construction anyway
            // so a tie-break edge case can never produce an invalid range.
            let lineIndexRange = min(startLineIndex, endLineIndex)...max(startLineIndex, endLineIndex)

            var bandPoints: [StrokePoint] = []
            var ranges: [Range<Int>] = []
            for index in lineIndexRange where index < orderedLines.count {
                let rect = orderedLines[index]
                var bandStartX = rect.minX
                var bandEndX = rect.maxX

                // Clip to the window scope FIRST, before cursor-position
                // clipping -- a Vision-merged line can extend past the
                // window's edge into a neighboring app, and the cursor
                // clipping below must operate on the visible (in-window)
                // portion of that line, not the raw merged rectangle.
                if let scopeScreen {
                    bandStartX = max(bandStartX, scopeScreen.minX)
                    bandEndX = min(bandEndX, scopeScreen.maxX)
                    guard bandEndX > bandStartX else { continue }
                }

                // Clamp to the user-defined column bounds when set. This is
                // the primary fix for highlights bleeding into adjacent
                // columns in multi-column layouts (e.g. newspaper PDFs):
                // Vision sometimes reports — or `mergedIntoLines` produces —
                // line rectangles that span multiple columns at the same row.
                // Clipping to the column the user explicitly defined keeps
                // every band inside that column, regardless of how wide the
                // detected line rectangle is.
                if let col = columnBoundsScreen {
                    bandStartX = max(bandStartX, col.minX)
                    bandEndX = min(bandEndX, col.maxX)
                    guard bandEndX > bandStartX else { continue }
                }

                if index == startLineIndex {
                    bandStartX = min(max(startPoint.x, bandStartX), bandEndX)
                }
                if index == endLineIndex {
                    bandEndX = min(max(endPoint.x, bandStartX), bandEndX)
                }
                if bandStartX > bandEndX { swap(&bandStartX, &bandEndX) }
                guard bandEndX - bandStartX > 0.5 else { continue }

                let startIndex = bandPoints.count
                bandPoints.append(StrokePoint(x: bandStartX - frame.minX, y: rect.midY - frame.minY))
                bandPoints.append(StrokePoint(x: bandEndX - frame.minX, y: rect.midY - frame.minY))
                ranges.append(startIndex..<(startIndex + 2))
            }

            engineRef.refineStroke(id: strokeID, points: bandPoints, bandRanges: ranges)
        }
    }

    // MARK: - Core Graphics Rendering
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // MARK: Column guide overlay (rendered beneath all highlights)
        // Wrapped in saveGState/restoreGState so dash patterns and color
        // settings don't bleed into the stroke-rendering loop that follows.

        context.saveGState()
        if let anchorX = columnDefineAnchorX, let currentX = columnDefineCurrentX {
            // Live dashed preview while the user is dragging to define a column.
            let guideMinX = min(anchorX, currentX)
            let guideMaxX = max(anchorX, currentX)
            let fillRect = CGRect(x: guideMinX, y: 0, width: guideMaxX - guideMinX, height: bounds.height)
            NSColor.systemCyan.withAlphaComponent(0.13).setFill()
            NSBezierPath(rect: fillRect).fill()

            // Dashed left and right column edges.
            NSColor.systemCyan.withAlphaComponent(0.80).setStroke()
            let edgePath = NSBezierPath()
            edgePath.lineWidth = 1.5
            let dashPattern: [CGFloat] = [5, 4]
            edgePath.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
            edgePath.move(to: CGPoint(x: guideMinX, y: 0))
            edgePath.line(to: CGPoint(x: guideMinX, y: bounds.height))
            edgePath.move(to: CGPoint(x: guideMaxX, y: 0))
            edgePath.line(to: CGPoint(x: guideMaxX, y: bounds.height))
            edgePath.stroke()
        } else if let col = engine.columnBounds {
            // Persistent subtle guide shown after a column has been set.
            let fillRect = CGRect(x: col.minX, y: 0, width: col.width, height: bounds.height)
            NSColor.systemCyan.withAlphaComponent(0.08).setFill()
            NSBezierPath(rect: fillRect).fill()

            // Solid edges — bright enough to be noticed without distracting from highlights.
            NSColor.systemCyan.withAlphaComponent(0.45).setStroke()
            let edgePath = NSBezierPath()
            edgePath.lineWidth = 1.0
            edgePath.move(to: CGPoint(x: col.minX, y: 0))
            edgePath.line(to: CGPoint(x: col.minX, y: bounds.height))
            edgePath.move(to: CGPoint(x: col.maxX, y: 0))
            edgePath.line(to: CGPoint(x: col.maxX, y: bounds.height))
            edgePath.stroke()
        }
        context.restoreGState()

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

            if let bandRanges = stroke.bandRanges {
                // Multi-line block highlight: draw each band as its own
                // straight segment so lines aren't joined by a connector.
                for range in bandRanges {
                    guard range.count >= 2, range.upperBound <= points.count else { continue }
                    let bandPath = NSBezierPath()
                    bandPath.lineWidth = stroke.style.width
                    bandPath.lineCapStyle = .round
                    bandPath.lineJoinStyle = .round
                    bandPath.move(to: points[range.lowerBound].cgPoint)
                    bandPath.line(to: points[range.lowerBound + 1].cgPoint)
                    bandPath.stroke()
                }
                context.restoreGState()
                continue
            }

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
