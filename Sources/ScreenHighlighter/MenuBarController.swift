import Cocoa

@MainActor
public final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let engine: DrawingEngine
    private let toggleOverlay: () -> Void
    private let quitApp: () -> Void
    
    public init(engine: DrawingEngine, toggleOverlay: @escaping () -> Void, quitApp: @escaping () -> Void) {
        self.engine = engine
        self.toggleOverlay = toggleOverlay
        self.quitApp = quitApp
        
        // 1. Create variable length status item in the system menu bar
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        super.init()
        
        setupMenu()
    }
    
    public func setupMenu() {
        guard let button = statusItem.button else { return }
        
        // 2. Load SF Symbol highlighter icon (isTemplate = true handles Dark Mode auto-inversion)
        if let icon = NSImage(systemSymbolName: "highlighter", accessibilityDescription: "Screen Highlighter") {
            icon.isTemplate = true
            button.image = icon
        }
        
        // 3. Construct dropdown menu items
        let menu = NSMenu()
        
        let toggleItem = NSMenuItem(
            title: "Toggle Overlay",
            action: #selector(toggleClicked),
            keyEquivalent: "h"
        )
        toggleItem.keyEquivalentModifierMask = [.command, .shift]
        toggleItem.target = self
        menu.addItem(toggleItem)
        
        let clearItem = NSMenuItem(
            title: "Clear Highlights",
            action: #selector(clearClicked),
            keyEquivalent: ""
        )
        clearItem.target = self
        menu.addItem(clearItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 4. Conditional accessibility status helper item
        if !PermissionsManager.shared.hasAccessibilityPermission() {
            let permItem = NSMenuItem(
                title: "Grant Accessibility Permissions...",
                action: #selector(permissionClicked),
                keyEquivalent: ""
            )
            permItem.target = self
            menu.addItem(permItem)
            menu.addItem(NSMenuItem.separator())
        }
        
        let quitItem = NSMenuItem(
            title: "Quit Screen Highlighter",
            action: #selector(quitClicked),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc private func toggleClicked() {
        toggleOverlay()
    }
    
    @objc private func clearClicked() {
        engine.clear()
    }
    
    @objc private func permissionClicked() {
        PermissionsManager.shared.requestAccessibilityPermission()
        setupMenu() // Re-evaluate permissions presence
    }
    
    @objc private func quitClicked() {
        quitApp()
    }
}
