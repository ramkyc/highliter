import Foundation
import Combine

@MainActor
public final class AppState: ObservableObject {
    @Published public var isOverlayVisible: Bool = false
    @Published public var hasPermissions: Bool = false
    
    public init() {
        self.hasPermissions = PermissionsManager.shared.hasAccessibilityPermission()
    }
    
    public func checkPermissions() {
        self.hasPermissions = PermissionsManager.shared.hasAccessibilityPermission()
    }
}

public struct UserPreferences {
    /// Preserves drawings until the user clicks "Clear" in the toolbar, per user's explicit instruction.
    public static let autoClearOnExit: Bool = false
}
