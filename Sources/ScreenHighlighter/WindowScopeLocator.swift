import AppKit

/// Locates the on-screen frame of the frontmost window beneath a given
/// screen point, so a multi-line highlight gesture can be confined to the
/// single window/app it started over.
///
/// Without this, a Shift+drag highlight is just geometry laid over a
/// screen-wide transparent overlay: it has no notion of "this text belongs to
/// Terminal" vs. "this text belongs to Finder," so a drag spanning the gap
/// between two windows produces highlight bands in both — visibly "bleeding"
/// across app boundaries. A real text selection never does this; it's always
/// scoped to one document. This locator supplies the missing window boundary
/// so gestures can be clamped to match that expectation.
public enum WindowScopeLocator {
    /// Returns the frame — in AppKit's global, bottom-left-origin screen
    /// coordinate space (the same one `NSScreen.frame` and
    /// `NSEvent.mouseLocation` use) — of the frontmost-app window containing
    /// `screenPoint`, or `nil` if none is found (e.g. the point sits over
    /// bare desktop, or that app has no window there).
    ///
    /// This used to scan the full on-screen window list and take the first
    /// normal-layer match in raw z-order. That's fragile: the list is full of
    /// invisible helper/system windows (menu bar extras, input-method panels,
    /// notification backing stores, ...) that also report `layer == 0` and
    /// often have large bounds — any of them can sort ahead of the actual
    /// visible app window, either swallowing the match (wrong, oversized
    /// scope) or blocking it (no scope at all, leaving the gesture
    /// unconstrained).
    ///
    /// A second attempt anchored on `NSWorkspace.shared.frontmostApplication`
    /// instead — but debug logging proved that's a dead end: clicking the
    /// overlay makes *it* key (`OverlayWindow.canBecomeKey == true`), which
    /// activates ScreenHighlighter itself, so `frontmostApplication` always
    /// reports our own process, never the app beneath the cursor. There is no
    /// ordering trick that fixes this — by the time `mouseDown` fires, the
    /// activation has already happened.
    ///
    /// This version goes back to scanning the real on-screen window list —
    /// `CGWindowListCopyWindowInfo` genuinely does return windows in
    /// front-to-back order, so the first match in that list IS the topmost
    /// window at the point — but fixes the actual problem with the original
    /// attempt: the filtering was too loose. Instead of trying to blacklist
    /// individual helper/system window names (fragile, never complete), this
    /// only considers windows owned by **regular, Dock-visible foreground
    /// apps** (`NSRunningApplication.activationPolicy == .regular`). Menu bar
    /// extras, input-method agents, notification services, Spotlight, and our
    /// own `LSUIElement` accessory app are all `.accessory`/`.prohibited` —
    /// none of them can ever match, by construction — while Terminal, Finder,
    /// Claude, etc. are `.regular` and always will be. This sidesteps the
    /// "who's frontmost" question entirely: we never need to know which app
    /// the user is interacting with, only which real app's window visually
    /// contains the point.
    public static func frontmostWindowFrame(at screenPoint: CGPoint) -> CGRect? {
        let ownPID = ProcessInfo.processInfo.processIdentifier

        // Real, Dock-visible foreground apps only -- this is what excludes
        // menu bar extras, input-method panels, notification backing stores,
        // and our own overlay, without needing to enumerate them by name.
        let regularAppPIDs = Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.processIdentifier != ownPID }
                .map { $0.processIdentifier }
        )

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        // The list is already front-to-back, so the first regular-app,
        // normal-layer, visible, reasonably-sized window whose bounds contain
        // the point is the one beneath the cursor.
        for info in windowInfoList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, regularAppPIDs.contains(ownerPID),
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let quartzFrame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  quartzFrame.width > 50, quartzFrame.height > 50
            else { continue }

            let appKitFrame = convertedToAppKitCoordinates(quartzFrame)
            if appKitFrame.contains(screenPoint) {
                return appKitFrame
            }
        }
        return nil
    }

    /// `CGWindowListCopyWindowInfo` reports bounds in Quartz's global display
    /// coordinate space: origin at the TOP-LEFT of the primary (menu-bar)
    /// display, Y increasing downward. AppKit's global space — the one
    /// `NSScreen.frame` and mouse-location APIs use, and the one the rest of
    /// this app's coordinate math assumes — has its origin at the
    /// BOTTOM-left, Y increasing upward. `NSScreen.screens.first` is always
    /// the primary display and anchors both spaces at x = 0, so flipping only
    /// needs that screen's height.
    private static func convertedToAppKitCoordinates(_ quartzFrame: CGRect) -> CGRect {
        guard let primaryScreenHeight = NSScreen.screens.first?.frame.height else {
            return quartzFrame
        }
        return CGRect(
            x: quartzFrame.minX,
            y: primaryScreenHeight - quartzFrame.maxY,
            width: quartzFrame.width,
            height: quartzFrame.height
        )
    }
}
