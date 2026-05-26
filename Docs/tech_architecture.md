This document defines the technical architecture for a macOS utility that lets a user draw temporary translucent yellow highlight strokes over visible screen content, then capture the result with the standard macOS screenshot workflow. The product is intentionally screenshot-first, overlay-based, and ephemeral rather than file-oriented.

# Screen Highlighter for macOS Technical Architecture

## Overview

The architecture should optimize for four things: instant activation, low runtime overhead, simple mental model, and compatibility with standard macOS screenshot capture.

The codebase should remain intentionally narrow in scope so that v1 solves one workflow extremely well: invoke, highlight, screenshot, paste.

## Architecture goals

The app operates as a menu bar utility with one or more transparent overlay windows that sit above normal application windows. The overlay contains the drawing surface and a small floating toolbar. Strokes exist only in memory unless future versions intentionally add persistence.

The design assumes the app will not integrate directly into WhatsApp or any other third-party app UI. Instead, it overlays temporary graphics over any visible content at the macOS windowing layer.

## System context

| Subsystem | Responsibility |
|---|---|
| App shell | App lifecycle, menu bar setup, state ownership |
| Menu bar controller | `NSStatusItem`, menu commands, status visibility |
| Shortcut manager | Global hotkey registration and dispatch |
| Overlay manager | Create, show, hide, and position overlay windows |
| Drawing engine | Stroke capture, smoothing, rendering, undo stack |
| Toolbar controller | Floating control panel behavior and tool commands |
| Permissions manager | Accessibility and screen-related permission handling |
| Screenshot coordinator | Detect and manage interaction with macOS screenshot flow |

These subsystems should communicate through a small shared application state layer and explicit command-style interfaces rather than tightly coupled cross-calls.

## Top-level architecture

The recommended architecture has eight primary subsystems.

The app runs as a standard macOS process with minimal background activity when idle. At rest, only the app shell, menu bar item, and shortcut registration should remain active.

When highlight mode is invoked, the overlay manager creates or reveals the active overlay window, attaches the drawing surface, and activates toolbar state. Drawing remains local to the current process and does not require helper services or background daemons in the MVP.

## Process model

| Layer | Technology |
|---|---|
| Language | Swift |
| App shell | SwiftUI App lifecycle |
| Windowing | AppKit |
| Menu bar integration | `NSStatusItem` / `NSMenu` |
| Overlay windows | `NSWindow` / `NSPanel` |
| Drawing surface | `NSView`-backed canvas or Metal-backed custom view if needed |
| State model | `ObservableObject` / `@MainActor` state store for UI-facing state |
| Global shortcuts | Carbon hotkey APIs or a stable wrapper library |
| Packaging | Sandboxed or non-sandboxed Mac app depending on permission constraints |

SwiftUI should own declarative app structure and settings screens, while AppKit should handle the parts that need precise control over z-order, transparency, input routing, and full-screen/Spaces behavior.

## Recommended technology stack

### Module design

#### 1. App shell

The app shell owns startup, dependency wiring, environment injection, and shutdown. It should instantiate the state store, register menu bar UI, configure shortcut registration, and defer heavy window creation until the user first invokes highlight mode.

Suggested responsibilities:

- Launch app and initialize subsystems.
- Restore user preferences.
- Wire menu actions to commands.
- Maintain high-level mode: idle, overlay active, settings open.

#### 2. Menu bar controller

The menu bar controller wraps `NSStatusItem` and exposes the product as a lightweight utility rather than a dock-centric application. It should provide immediate visibility into whether highlight mode is active and surface a minimal set of commands.

Suggested menu entries:

- Show Highlighter.
- Hide Highlighter.
- Clear Highlights.
- Preferences.
- Quit.

#### 3. Shortcut manager

The shortcut manager is responsible for registering and handling the global hotkey used to show or hide the overlay. It should expose a clean callback or command dispatch interface rather than embedding app logic.

Suggested interface:

```swift
protocol ShortcutManaging {
    func registerToggleShortcut(_ shortcut: Shortcut)
    func unregisterAll()
    var onToggleRequested: (() -> Void)? { get set }
}
```

Implementation should support later extension for undo, clear, and quick-hide shortcuts without architectural changes.

#### 4. Overlay manager

The overlay manager is the core infrastructure component. It creates and owns one or more transparent top-level windows, one per active display in future versions, with v1 allowed to target only the currently active display.

Responsibilities:

- Discover active screens.
- Create borderless transparent windows.
- Set appropriate window level to stay above normal apps.
- Configure collection behavior for Spaces and full-screen modes as needed.
- Show and hide overlay windows with minimal latency.
- Manage click acceptance and possible future click-through state.

A recommended internal model is:

```swift
final class OverlayManager {
    private var overlayWindows: [NSScreen: OverlayWindowController]
    func show(on screen: NSScreen)
    func hideAll()
    func clearAllStrokes()
    func setDrawingEnabled(_ enabled: Bool)
}
```

#### 5. Overlay window controller

Each overlay window controller owns a single overlay window, the drawing canvas view, and the floating toolbar anchor for its screen. This screen-local ownership avoids excessive global branching and simplifies future multi-display support.

Responsibilities:

- Instantiate a transparent `NSWindow` or `NSPanel`.
- Attach content view hierarchy.
- Host drawing canvas.
- Position toolbar without obstructing likely capture regions.
- Relay commands to the drawing engine.

#### 6. Drawing engine

The drawing engine handles stroke capture, smoothing, rendering, undo, and clear operations. It must feel immediate and low-latency because the perceived quality of the entire product depends heavily on stroke responsiveness.

The simplest viable design is an in-memory stroke list rendered into a dedicated canvas view. Each stroke is appended when pointer interaction completes; a temporary active stroke is rendered during drag.

Suggested model:

```swift
struct StrokePoint {
    let x: CGFloat
    let y: CGFloat
    let timestamp: TimeInterval
}

struct StrokeStyle {
    let color: NSColor
    let width: CGFloat
    let opacity: CGFloat
}

struct Stroke {
    let id: UUID
    let points: [StrokePoint]
    let style: StrokeStyle
    let createdAt: Date
}
```

Recommended engine interface:

```swift
protocol DrawingEngine {
    func beginStroke(at point: CGPoint)
    func appendPoint(_ point: CGPoint)
    func endStroke()
    func undo()
    func clear()
    var strokes: [Stroke] { get }
    var activeStroke: Stroke? { get }
}
```

#### 7. Canvas view

The canvas view is the input and rendering surface. In v1 it can be implemented as a custom `NSView` subclass backed by Core Graphics or Core Animation. If profiling later shows rendering or smoothing issues, a Metal-backed renderer can be introduced without redesigning the surrounding modules.

The canvas view should:

- Accept mouse down, drag, and mouse up events.
- Convert window coordinates into local canvas coordinates.
- Forward points to the drawing engine.
- Invalidate only the needed regions if practical, though full redraw may be acceptable at MVP scale.

#### 8. Toolbar controller

The toolbar controller manages the floating toolbar’s presentation and commands. This controller should remain intentionally thin and should not own drawing state directly; it should dispatch commands through the overlay manager or shared app command layer.

Toolbar commands:

- Undo.
- Clear.
- Hide toolbar.
- Exit highlight mode.

Potential future commands:

- Width adjustment.
- Redo.
- Auto-clear toggle.

#### 9. Permissions manager

The permissions manager centralizes checks for any accessibility or related permissions required by shortcut registration or advanced interaction behavior. The MVP should deliberately minimize permissions, but centralizing this logic prevents permission checks from leaking into UI components.

Responsibilities:

- Check current permission state.
- Trigger onboarding or explanation UI.
- Deep-link user to system settings if needed.
- Expose a simple state model such as authorized, needs prompt, or denied.

#### 10. Screenshot coordinator

This subsystem exists because screenshot compatibility is a critical product constraint. Even if it is small in v1, it should be architecturally explicit because screenshot behavior can become the main integration risk.

Responsibilities:

- Verify overlay visibility during standard screenshot capture.
- Optionally observe shortcut conflicts if a custom capture helper is added later.
- Support later fallback modes such as delayed self-hide or temporary toolbar suppression.

## State architecture

A small shared application state model should track high-level state only. Fine-grained rendering details should remain inside the drawing engine or screen-local controllers.

Suggested app state:

```swift
@MainActor
final class AppState: ObservableObject {
    @Published var overlayVisible: Bool = false
    @Published var activeScreenID: String?
    @Published var toolbarVisible: Bool = true
    @Published var permissionsStatus: PermissionsStatus = .unknown
    @Published var preferences: UserPreferences = .default
}
```

This keeps the top-level state easy to reason about while avoiding misuse of a global store for every stroke point.

## Event flow

### Activation flow

1. User presses global shortcut.
2. Shortcut manager emits toggle event.
3. App shell checks current overlay state.
4. Overlay manager shows overlay on the active screen.
5. Toolbar becomes visible with highlighter ready.
6. App state updates to `overlayVisible = true`.

### Drawing flow

1. Canvas view receives mouse down.
2. Canvas starts a new active stroke.
3. Drag events append points to active stroke.
4. Canvas redraws active stroke continuously.
5. Mouse up finalizes stroke into the completed stroke list.
6. Undo stack implicitly updates via the appended stroke collection.

### Undo flow

1. User presses Undo in toolbar or shortcut.
2. Toolbar controller dispatches undo command.
3. Drawing engine removes the most recent completed stroke.
4. Canvas redraws.

### Exit flow

1. User chooses Exit or presses the toggle shortcut again.
2. Overlay manager hides overlay windows.
3. If preference is enabled, drawing engine clears session strokes.
4. App state updates to `overlayVisible = false`.

## Windowing model

The app’s windowing behavior will determine whether the product feels truly overlay-like.

Recommended characteristics for overlay windows:

- Borderless.
- Transparent background.
- Non-activating if possible, though this may need trade-offs depending on input handling.
- High enough level to remain above regular application windows.
- Configured for relevant Spaces/full-screen collection behavior.

Careful testing is needed around:

- Full-screen apps.
- Mission Control and Spaces transitions.
- Multiple monitors with different scaling.
- Screenshot UI interaction.

## Rendering strategy

A Core Graphics path-based renderer is likely sufficient for MVP. Each stroke can be converted into a smoothed `NSBezierPath` or `CGPath` and drawn with a translucent yellow color.

Suggested rendering approach:

- Keep completed strokes in an array.
- Keep one active in-progress stroke.
- Redraw on drag updates.
- Use round line caps and joins.
- Apply alpha between 0.30 and 0.45.
- Use line smoothing to avoid jagged artifacts.

If softness is important, a slightly blurred compositing layer or shadow-like edge treatment can be introduced, but MVP should prefer simple reliable rendering over visual over-engineering.

## Coordinate systems

Coordinate handling must be explicitly designed early because multi-display and Retina mismatches can cause subtle bugs.

Requirements:

- Normalize input events into canvas-local coordinates.
- Keep stroke models resolution-independent where possible.
- Handle backing scale factors correctly so width feels consistent on Retina and non-Retina displays.
- Prevent coordinate drift if the active screen changes or windows are recreated.

## Persistence model

MVP persistence should be ephemeral and memory-only. The app should not store annotated images and should store only lightweight preferences such as shortcuts, toolbar position, and width defaults.

| Data | Persistence |
|---|---|
| User shortcut | Persist |
| Toolbar position | Persist |
| Stroke width preference | Persist |
| Current session strokes | Memory only |
| Captured image outputs | Do not store |

## Preferences architecture

Preferences should be modeled as a single serializable settings object owned by the app shell and injected into subsystems that need it.

Suggested model:

```swift
struct UserPreferences: Codable {
    var toggleShortcut: Shortcut
    var defaultStrokeWidth: CGFloat
    var autoClearOnExit: Bool
    var activeDisplayOnly: Bool
    var rememberToolbarPosition: Bool

    static let `default`: UserPreferences = ...
}
```

## Error handling strategy

The app should avoid modal error spam because it is a quick-utility product. User-visible errors should be rare, concise, and actionable.

Examples:

- Shortcut registration failed.
- Required permissions not granted.
- Overlay could not be shown on the selected display.

Recommended UX pattern:

- Menu bar warning state or non-blocking banner in settings.
- Single explanatory prompt on first failure.
- Clear next step: retry, open settings, or reset shortcut.

## Security and privacy architecture

This product should process everything locally and keep its trust posture simple. The architecture should not include networking code in the MVP.

Privacy design rules:

- No transmission of screen contents.
- No cloud dependencies.
- No telemetry by default.
- Minimal permissions.
- Clear explanation of what the overlay can and cannot access.

## Testing strategy

### Unit tests

Unit-test the logic-heavy components:

- Drawing engine stroke lifecycle.
- Undo/clear behavior.
- Preference serialization.
- Shortcut parsing and validation.

### Integration tests

Integration-test subsystem interactions:

- Shortcut toggles overlay visibility.
- Toolbar actions reach drawing engine.
- Overlay creation on app launch and repeated reuse.
- Preference changes propagate correctly.

### Manual QA

Manual QA is especially important for:

- Screenshot inclusion of overlay.
- Full-screen apps.
- Multi-monitor setups.
- Retina and non-Retina displays.
- Dark and light system appearance.
- Toolbar placement and accidental capture in screenshots.

## Performance engineering notes

The app must feel instant. That means avoiding unnecessary overlay recreation, minimizing idle work, and keeping rendering logic simple.

Performance recommendations:

- Lazily create overlay window on first use, then reuse it.
- Keep stroke structures lightweight.
- Redraw only during active drawing or explicit edits.
- Avoid polling loops.
- Keep idle CPU effectively zero.

## Suggested project structure

```text
ScreenHighlighter/
├── App/
│   ├── ScreenHighlighterApp.swift
│   ├── AppState.swift
│   └── DependencyContainer.swift
├── MenuBar/
│   └── MenuBarController.swift
├── Shortcuts/
│   ├── Shortcut.swift
│   └── ShortcutManager.swift
├── Overlay/
│   ├── OverlayManager.swift
│   ├── OverlayWindowController.swift
│   ├── OverlayWindow.swift
│   └── ToolbarController.swift
├── Drawing/
│   ├── DrawingEngine.swift
│   ├── Stroke.swift
│   ├── CanvasView.swift
│   └── StrokeSmoother.swift
├── Permissions/
│   └── PermissionsManager.swift
├── Screenshot/
│   └── ScreenshotCoordinator.swift
├── Preferences/
│   ├── UserPreferences.swift
│   └── PreferencesView.swift
└── Tests/
    ├── DrawingEngineTests.swift
    ├── OverlayManagerTests.swift
    └── PreferencesTests.swift
```

## MVP implementation order

### Phase 1: Feasibility spike

Build a minimal proof of concept with:

- One transparent overlay window.
- One custom canvas view.
- One yellow stroke style.
- Manual show/hide trigger.
- Manual screenshot validation.

This phase should answer the highest-risk question first: whether the overlay can be captured cleanly in the standard screenshot workflow.

### Phase 2: Core architecture

Add:

- Menu bar integration.
- Shortcut manager.
- App state container.
- Undo and clear.
- Preferences scaffolding.

### Phase 3: Product polish

Add:

- Better toolbar behavior.
- Onboarding and permissions UX.
- Performance tuning.
- Edge-case handling for Spaces/full-screen.

## Open technical questions

These questions should be resolved during prototyping:

1. Which window level reliably preserves visibility without breaking screenshot capture?
2. Can the overlay remain non-activating while still accepting drawing input comfortably?
3. Should toolbar rendering live inside the same overlay window or in a separate floating panel?
4. Is Core Graphics sufficient for smooth marker rendering, or is Metal needed for polish?
5. What is the cleanest way to keep the toolbar out of the captured region?
6. How should the app behave when the user invokes screenshot mode while mid-stroke?

## Final architecture recommendation

The strongest v1 architecture is a narrow, modular Swift macOS menu bar app with an AppKit-managed transparent overlay window, a lightweight in-memory drawing engine, and explicit separation between overlay control, drawing logic, preferences, and screenshot coordination.

This architecture is intentionally optimized for the exact workflow established in the conversation: no file editing, no save/export ceremony, no WhatsApp integration, and no unnecessary product surface beyond highlight, screenshot, paste.
