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
    }

    public func hide() {
        stopInteractivityMonitoring()
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

    // MARK: - Keyboard Controls
    
    public override func keyDown(with event: NSEvent) {
        let keyCode = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        
        // ESC key (Escape to Exit)
        if keyCode == 53 {
            onDismiss()
            return
        }
        
        // Command + Z (Undo last stroke)
        if flags == .command, let chars = event.charactersIgnoringModifiers, chars.lowercased() == "z" {
            engine.undo()
            return
        }
        
        // Backspace / Delete (Clear all strokes)
        if keyCode == 51 {
            engine.clear()
            return
        }
        
        super.keyDown(with: event)
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
