import Cocoa
import ApplicationServices

@MainActor
public final class PermissionsManager {
    public static let shared = PermissionsManager()
    
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
}

