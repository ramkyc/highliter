import Cocoa
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState!
    private var engine: DrawingEngine!
    private var overlayManager: OverlayManager!
    private var shortcutManager: ShortcutManager!
    private var menuBarController: MenuBarController!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("DEBUG: applicationDidFinishLaunching started")
        
        print("DEBUG: Setting activation policy")
        NSApp.setActivationPolicy(.accessory)
        
        print("DEBUG: Initializing AppState")
        appState = AppState()
        
        print("DEBUG: Initializing DrawingEngine")
        engine = DrawingEngine()
        
        print("DEBUG: Initializing OverlayManager")
        overlayManager = OverlayManager(engine: engine)
        
        print("DEBUG: Initializing ShortcutManager")
        shortcutManager = ShortcutManager()
        
        print("DEBUG: Initializing MenuBarController")
        menuBarController = MenuBarController(
            engine: engine,
            toggleOverlay: { [weak self] in
                self?.toggleOverlay()
            },
            quitApp: {
                NSApp.terminate(nil)
            }
        )
        
        print("DEBUG: Registering shortcuts")
        shortcutManager.registerToggleShortcut { [weak self] in
            self?.toggleOverlay()
        }
        
        print("DEBUG: Checking permissions")
        if !PermissionsManager.shared.hasAccessibilityPermission() {
            print("Screen Highlighter: Accessibility permissions required for global shortcuts.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                PermissionsManager.shared.requestAccessibilityPermission()
            }
        } else {
            print("Screen Highlighter: Accessibility permissions authorized.")
        }
        
        print("DEBUG: applicationDidFinishLaunching completed")
    }
    
    func toggleOverlay() {
        if appState.isOverlayVisible {
            hideOverlay()
        } else {
            showOverlay()
        }
    }
    
    private func showOverlay() {
        appState.isOverlayVisible = true
        overlayManager.show(onDismiss: { [weak self] in
            self?.hideOverlay()
        })
    }
    
    private func hideOverlay() {
        appState.isOverlayVisible = false
        overlayManager.hideAll()
        
        if UserPreferences.autoClearOnExit {
            engine.clear()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        shortcutManager?.unregisterAll()
    }
}

// MARK: - AppKit Bootstrap Entry Point
print("DEBUG: Program entry point started")

// Global strong reference to keep the AppDelegate alive under ARC (NSApplication.delegate is weak)
var globalDelegate: AppDelegate?

autoreleasepool {
    print("DEBUG: Inside autoreleasepool")
    let app = NSApplication.shared
    print("DEBUG: NSApplication.shared fetched")
    let delegate = AppDelegate()
    print("DEBUG: AppDelegate instantiated")
    
    // Keep it alive!
    globalDelegate = delegate
    app.delegate = delegate
    print("DEBUG: AppDelegate set as delegate")
    
    print("DEBUG: Running app.run()")
    app.run()
}
print("DEBUG: Program entry point completed")
