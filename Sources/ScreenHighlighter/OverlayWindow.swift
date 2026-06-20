import Cocoa

public final class OverlayWindow: NSWindow {
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        self.isReleasedWhenClosed = false
        // statusBar level ensures the overlay is above ordinary app windows, but fully captureable by screenshot tools.
        self.level = .statusBar
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        // Initial state: capture clicks for drawing. OverlayWindowController
        // toggles this at runtime to enter click-through "view" mode, which
        // keeps highlights visible while letting clicks reach apps below.
        self.ignoresMouseEvents = false
        
        // Ensure the window displays on all virtual desktops (Spaces) and full-screen games/apps
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.acceptsMouseMovedEvents = true
        
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
    }
    
    public override var canBecomeKey: Bool {
        return true
    }

    public override var canBecomeMain: Bool {
        return false
    }
}
