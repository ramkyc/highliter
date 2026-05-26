import Cocoa

@MainActor
public final class OverlayManager {
    private let engine: DrawingEngine
    private var windowControllers: [NSScreen: OverlayWindowController] = [:]
    
    public init(engine: DrawingEngine) {
        self.engine = engine
    }
    
    public func show(onDismiss: @escaping () -> Void) {
        // 1. Locate active monitor containing mouse pointer
        let screens = NSScreen.screens
        let mouseLocation = NSEvent.mouseLocation
        
        let activeScreen = screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } 
            ?? NSScreen.main 
            ?? screens.first
        
        guard let screen = activeScreen else {
            print("Error: No screen detected to render overlay canvas.")
            return
        }
        
        // 2. Clear out any outdated or misplaced window active instances
        hideAll()
        
        // 3. Obtain or instantiate the window controller for the target screen
        let controller = windowControllers[screen] ?? OverlayWindowController(screen: screen, engine: engine, onDismiss: onDismiss)
        windowControllers[screen] = controller
        
        controller.show()
    }
    
    public func hideAll() {
        for controller in windowControllers.values {
            controller.hide()
        }
    }
    
    public func clearAll() {
        engine.clear()
    }
}
