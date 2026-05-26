import Cocoa
import SwiftUI

public final class OverlayWindowController: NSWindowController {
    private let engine: DrawingEngine
    private let onDismiss: () -> Void
    
    private var canvasView: CanvasView?
    private var toolbarHostingView: NSHostingView<ToolbarView>?
    
    public init(screen: NSScreen, engine: DrawingEngine, onDismiss: @escaping () -> Void) {
        self.engine = engine
        self.onDismiss = onDismiss
        
        let window = OverlayWindow(contentRect: screen.frame)
        super.init(window: window)
        
        setupViews(frame: screen.frame)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews(frame: NSRect) {
        guard let window = self.window else { return }
        
        let contentView = NSView(frame: NSRect(origin: .zero, size: frame.size))
        window.contentView = contentView
        
        // 1. Create and add CanvasView
        let canvas = CanvasView(engine: engine)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(canvas)
        self.canvasView = canvas
        
        // 2. Create SwiftUI ToolbarView wrapped in NSHostingView
        let toolbarView = ToolbarView(engine: engine, onExit: onDismiss)
        let hostingView = NSHostingView(rootView: toolbarView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(hostingView)
        self.toolbarHostingView = hostingView
        
        // 3. Auto Layout Constraints
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: contentView.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            hostingView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40),
            hostingView.heightAnchor.constraint(equalToConstant: 60)
        ])
    }
    
    public func show() {
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
    
    public func hide() {
        window?.orderOut(nil)
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
