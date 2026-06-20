import Cocoa
import SwiftUI
import Combine

public final class OverlayWindowController: NSWindowController {
    private let engine: DrawingEngine
    private let onDismiss: () -> Void

    private var canvasView: CanvasView?
    private var toolbarHostingView: NSHostingView<ToolbarView>?
    private var draggableContainer: DraggableContainerView?

    private var modeCancellable: AnyCancellable?
    private var interactivityTimer: Timer?
    private var scrollMonitor: Any?
    private var keyMonitor: Any?

    /// Marks a re-posted scroll CGEvent so we can detect if it bounces back
    /// to our window (e.g. if ignoresMouseEvents was restored before the
    /// window-server routed the re-post) and drop it instead of looping.
    private static let scrollForwardedFlag: Int64 = 0x4849474C

    public init(screen: NSScreen, engine: DrawingEngine, onDismiss: @escaping () -> Void) {
        self.engine = engine
        self.onDismiss = onDismiss

        let window = OverlayWindow(contentRect: screen.frame)
        super.init(window: window)

        setupViews(frame: screen.frame)
        observeDrawMode()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews(frame: NSRect) {
        guard let window = self.window else { return }
        
        let contentView = NSView(frame: NSRect(origin: .zero, size: frame.size))
        window.contentView = contentView
        
        // 1. Create and add CanvasView (covers entire display)
        let canvas = CanvasView(engine: engine)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(canvas)
        self.canvasView = canvas
        
        // 2. Create SwiftUI ToolbarView wrapped in NSHostingView
        let toolbarView = ToolbarView(engine: engine, onExit: onDismiss)
        let hostingView = NSHostingView(rootView: toolbarView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        self.toolbarHostingView = hostingView
        
        // 3. Setup the Draggable Container for the Toolbar
        let toolbarWidth: CGFloat = 340
        let toolbarHeight: CGFloat = 60
        let containerFrame = NSRect(
            x: (frame.size.width - toolbarWidth) / 2.0,
            y: 40,
            width: toolbarWidth,
            height: toolbarHeight
        )
        
        let container = DraggableContainerView(frame: containerFrame)
        contentView.addSubview(container)
        container.addSubview(hostingView)
        self.draggableContainer = container

        // Give the canvas a weak reference to the toolbar container so it can
        // exclude that region from drawing gestures (belt-and-suspenders guard
        // against hit-test edge cases passing toolbar clicks to the canvas).
        canvas.toolbarContainer = container
        
        // 4. Auto Layout Constraints
        NSLayoutConstraint.activate([
            // Canvas covers full screen
            canvas.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: contentView.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            // Hosting view fills the draggable container boundaries
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
    
    public func show() {
        // Always re-enter in drawing mode so the highlighter is active by
        // default, matching the "active immediately on invocation" requirement.
        engine.isDrawModeActive = true

        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        refreshInteractivity()
        startInteractivityMonitoring()
        startScrollPassthrough()
        startKeyMonitor()
    }

    public func hide() {
        stopInteractivityMonitoring()
        stopScrollPassthrough()
        stopKeyMonitor()
        window?.orderOut(nil)
    }

    // MARK: - Click-through / View Mode

    /// Mirrors `engine.isDrawModeActive` so the overlay window's
    /// `ignoresMouseEvents` stays in sync whenever the toolbar toggles modes.
    private func observeDrawMode() {
        modeCancellable = engine.$isDrawModeActive
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshInteractivity()
            }
    }

    /// Polls the cursor position while the overlay is visible so that, in
    /// click-through (view) mode, the toolbar remains clickable even though
    /// the rest of the window passes clicks straight through to apps below.
    /// `NSWindow.ignoresMouseEvents` is an all-or-nothing window property, so
    /// this is the simplest reliable way to keep one small region interactive.
    private func startInteractivityMonitoring() {
        stopInteractivityMonitoring()
        interactivityTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshInteractivity()
            }
        }
    }

    private func stopInteractivityMonitoring() {
        interactivityTimer?.invalidate()
        interactivityTimer = nil
    }

    private func refreshInteractivity() {
        guard let window = self.window as? OverlayWindow else { return }

        if engine.isDrawModeActive {
            // Drawing mode: capture all clicks across the screen so the user
            // can paint highlights anywhere.
            window.ignoresMouseEvents = false
            return
        }

        // Click-through (view) mode: highlights stay visible, but clicks pass
        // straight through to the app underneath everywhere except directly
        // over the floating toolbar, so the user can still reach its buttons
        // (e.g. to switch back to drawing mode or exit).
        guard let container = draggableContainer, let contentView = window.contentView else {
            window.ignoresMouseEvents = true
            return
        }

        let frameInWindow = contentView.convert(container.frame, to: nil)
        let frameOnScreen = window.convertToScreen(frameInWindow)
        let mouseLocation = NSEvent.mouseLocation

        window.ignoresMouseEvents = !frameOnScreen.contains(mouseLocation)
    }

    // MARK: - Scroll Passthrough

    /// Intercepts scroll-wheel events before AppKit dispatches them to the
    /// canvas and forwards them to the app underneath the overlay.
    ///
    /// Why a local monitor instead of overriding NSWindow.sendEvent:
    /// sendEvent re-posts a CGEvent copy → if the copy bounces back before
    /// ignoresMouseEvents is restored, sendEvent fires again → infinite loop
    /// that floods the event queue and freezes the mouse.
    ///
    /// Local monitors run before dispatch, so returning nil here swallows
    /// the event cleanly.  We simultaneously post a flagged copy so the
    /// underlying app receives the scroll.  The flag lets us detect and drop
    /// any copy that bounces back (when ignoresMouseEvents was restored first),
    /// breaking any potential loop.
    private func startScrollPassthrough() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard
                let self = self,
                let win = self.window as? OverlayWindow,
                event.window === win,       // only intercept events aimed at our window
                !win.ignoresMouseEvents     // only in draw mode (click-through already passes through)
            else {
                return event
            }

            // If this is our own re-posted copy bouncing back (race: ignoresMouseEvents
            // was already restored before the window server processed the re-post),
            // drop it silently rather than re-entering the forward loop.
            if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == Self.scrollForwardedFlag {
                return nil
            }

            // Open a brief pass-through window so the re-post is routed to the
            // window below rather than back to us.
            win.ignoresMouseEvents = true
            if let cgCopy = event.cgEvent?.copy() {
                cgCopy.setIntegerValueField(.eventSourceUserData, value: Self.scrollForwardedFlag)
                cgCopy.post(tap: .cghidEventTap)
            }
            // Restore on the next run-loop iteration.  The 30 Hz interactivity
            // timer is a belt-and-suspenders backstop that corrects the state
            // within ≤ 33 ms regardless.
            DispatchQueue.main.async { [weak win] in
                win?.ignoresMouseEvents = false
            }

            return nil  // swallow from our responder chain — canvas never sees it
        }
    }

    private func stopScrollPassthrough() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }

    // MARK: - Keyboard Controls

    /// A local key monitor intercepts key events before AppKit dispatches
    /// them to the responder chain.  This is more reliable than overriding
    /// keyDown on the window controller because:
    ///   • Our overlay is at .statusBar level but does not steal keyboard focus
    ///     from the browser/app the user is reading — key events keep going to
    ///     that app's key window, so keyDown on our controller never fires.
    ///   • A local monitor fires for any key event that enters our process,
    ///     regardless of which window is key.
    private func startKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            switch event.keyCode {
            case 53: // Esc
                self.engine.clearColumnBounds()
                self.onDismiss()
                return nil
            case 51: // Delete / Backspace — clear all strokes
                self.engine.clear()
                return nil
            default:
                break
            }

            // Cmd+Z — undo last stroke
            if flags == .command,
               let chars = event.charactersIgnoringModifiers,
               chars.lowercased() == "z" {
                self.engine.undo()
                return nil
            }

            return event
        }
    }

    private func stopKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}

// MARK: - Draggable Container View
class DraggableContainerView: NSView {
    private var dragStartLocation: NSPoint = .zero
    
    override func mouseDown(with event: NSEvent) {
        dragStartLocation = event.locationInWindow
    }
    
    override func mouseDragged(with event: NSEvent) {
        let currentLocation = event.locationInWindow
        let deltaX = currentLocation.x - dragStartLocation.x
        let deltaY = currentLocation.y - dragStartLocation.y
        
        var newFrame = self.frame
        newFrame.origin.x += deltaX
        newFrame.origin.y += deltaY
        
        // Constrain dragging bounds within the screen boundaries
        if let superview = self.superview {
            let maxOffsetX = superview.bounds.width - newFrame.width
            let maxOffsetY = superview.bounds.height - newFrame.height
            newFrame.origin.x = max(10, min(newFrame.origin.x, maxOffsetX - 10))
            newFrame.origin.y = max(10, min(newFrame.origin.y, maxOffsetY - 10))
        }
        
        self.frame = newFrame
        dragStartLocation = currentLocation
    }
}
