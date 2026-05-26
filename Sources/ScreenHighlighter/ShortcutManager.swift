import Carbon
import Cocoa

@MainActor
public final class ShortcutManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var onTrigger: (() -> Void)?
    
    public init() {}
    
    public func registerToggleShortcut(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        
        // 1. Install event handler spec to listen for Hot Key Pressed events
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        
        // C-style callback function to receive Carbon global events
        let handlerCallback: EventHandlerUPP = { (inHandlerCallRef, inEvent, inUserData) -> OSStatus in
            if let userData = inUserData {
                // Route the unmanaged raw pointer back to Swift ShortcutManager instance
                let manager = Unmanaged<ShortcutManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.trigger()
                }
            }
            return noErr
        }
        
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handlerCallback,
            1,
            &eventSpec,
            selfPointer,
            &eventHandlerRef
        )
        
        if status != noErr {
            print("Error: Failed to install event handler for Carbon hotkeys (OSStatus: \(status))")
        }
        
        // 2. Register global hotkey: Command + Shift + H
        // Keycode for "H" on US QWERTY layout is 4.
        // Modifiers: cmdKey (Command) and shiftKey (Shift).
        let hKeyCode: UInt32 = 4
        let cmdShiftModifiers: UInt32 = UInt32(cmdKey | shiftKey)
        
        // 'HK01' in UInt32 format (OSType ID)
        let hotKeyID = EventHotKeyID(
            signature: OSType(1212887089),
            id: 1
        )
        
        let regStatus = RegisterEventHotKey(
            hKeyCode,
            cmdShiftModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if regStatus != noErr {
            print("Warning: Failed to register global hotkey Cmd+Shift+H. Permissions may be missing (OSStatus: \(regStatus))")
        } else {
            print("Successfully registered global background hotkey: Cmd + Shift + H")
        }
    }
    
    public func unregisterAll() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
    }
    
    public func trigger() {
        self.onTrigger?()
    }
    
    deinit {
        // unregisterAll must be bypassed or run safely, but in Swift 6 `@MainActor` deinit is nonisolated.
        // Since we already unregister on app lifecycle close, let's keep this clean or wrap it.
    }
}
