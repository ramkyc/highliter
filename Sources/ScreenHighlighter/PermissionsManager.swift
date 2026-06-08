import Cocoa
import ApplicationServices

@MainActor
public final class PermissionsManager {
    public static let shared = PermissionsManager()

    /// Tracks whether we've already surfaced the system Screen Recording
    /// prompt this session, so an OCR-eligible gesture performed repeatedly
    /// before the user responds doesn't re-trigger the dialog.
    private var hasRequestedScreenRecording = false

    public init() {}

    /// Checks if accessibility permission is granted, without prompting the user.
    public func hasAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }
    
    /// Requests accessibility permissions, displaying the native macOS system dialog if not granted.
    @discardableResult
    public func requestAccessibilityPermission() -> Bool {
        // 1. Dynamically locate the global pointer of kAXTrustedCheckOptionPrompt
        // This avoids Swift 6 compile-time concurrency checks while getting the exact memory address
        // required by the legacy C API's pointer-equality lookup.
        let RTLD_LAZY = Int32(1)
        guard let handle = dlopen(nil, RTLD_LAZY) else {
            print("Error: dlopen failed to load main image.")
            return false
        }
        defer { dlclose(handle) }
        
        guard let symbol = dlsym(handle, "kAXTrustedCheckOptionPrompt") else {
            print("Error: dlsym failed to locate kAXTrustedCheckOptionPrompt symbol.")
            return false
        }
        
        // kAXTrustedCheckOptionPrompt is a CFStringRef*, which maps to UnsafePointer<CFString>
        let ptr = symbol.assumingMemoryBound(to: CFString.self)
        let promptKey = ptr.pointee as NSString
        
        // 2. Safely construct the single-element Cocoa dictionary using the authentic key
        let value = kCFBooleanTrue as AnyObject
        let options = NSDictionary(object: value, forKey: promptKey) as CFDictionary
        
        // 3. Guarantee options dictionary remains allocated for the duration of the C-call
        return withExtendedLifetime(options) {
            return AXIsProcessTrustedWithOptions(options)
        }
    }

    // MARK: - Screen Recording (required for OCR-based line detection)

    /// Checks if Screen Recording permission is granted, without prompting.
    /// This TCC permission is required to capture display pixels for the
    /// on-device OCR pass that snaps multi-line highlights onto real text
    /// lines; it is unrelated to (and separate from) Accessibility access.
    public func hasScreenRecordingPermission() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }

    /// Requests Screen Recording permission, surfacing the native system
    /// prompt the first time it's called in a session. Subsequent calls while
    /// the decision is still pending return the current status without
    /// re-prompting, so a user who hasn't responded yet isn't nagged on every
    /// Shift+drag gesture.
    @discardableResult
    public func requestScreenRecordingPermission() -> Bool {
        guard !hasRequestedScreenRecording else { return hasScreenRecordingPermission() }
        hasRequestedScreenRecording = true
        return CGRequestScreenCaptureAccess()
    }
}

