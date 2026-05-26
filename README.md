# Screen Highlighter for macOS

**Screen Highlighter** is a lightweight, high-performance macOS menu bar utility that lets you draw temporary translucent yellow highlight strokes over anything currently visible on your screen, capture the result using normal macOS screenshot shortcuts, and paste that screenshot directly into WhatsApp, Slack, Telegram, or other applications.

It is intentionally designed as a **screenshot-first, ephemeral drawing overlay**, rather than a file-centric image editor. 

---

## ✨ Features

- **Instant Toggle (`Cmd + Shift + H`)**: A global Carbon background hotkey immediately toggles the drawing canvas overlay from any application.
- **Organic Marker Strokes**: Renders beautiful, soft, 35%-opaque translucent highlights using Core Graphics path-smoothing (quadratic Bezier interpolation).
- **Straight-Line Mode (Shift Key)**: Hold down the `Shift` key while clicking and dragging to lock your highlights to a perfectly straight line, ideal for cleanly underlining or highlighting lines of text.
- **Premium Glassmorphic HUD**: A floating controls panel (using native macOS HUD vibrancy and frosted glass effects) providing smooth hover micro-animations and quick access to **Undo**, **Clear**, and **Close**.
- **Display-Aware Canvas**: Intelligently identifies which screen your cursor is active on and displays the full-screen transparent canvas on that specific monitor.
- **Spaces & Full-Screen Support**: Inherits virtual desktop spaces collection behaviors so it runs seamlessly over games, presentations, and full-screen software.
- **Zero-Config Ephemerality**: Drawing strokes live purely in-memory and are never written to disk, respecting your privacy and keeping your filesystem clean.

---

## 🛠️ Under the Hood: Technical Architecture

Screen Highlighter is written in **Swift 6, SwiftUI, and AppKit**, optimized for modern macOS architectures:

1. **Programmatic AppKit event loop (`main.swift`)**: Boots a pure programmatic AppKit Cocoa execution loop (`app.run()`), preventing early background termination without relying on heavy storyboard wrappers.
2. **ARC Lifetime Protection**: Binds the application delegate to a strong global reference (`globalDelegate`) to prevent Automatic Reference Counting (ARC) from prematurely deallocating it while linked to weak system properties.
3. **Dynamic Pointer Resolution (`dlsym`)**: Avoids compile-time Swift 6 concurrency locks on legacy C global variables (like `kAXTrustedCheckOptionPrompt`) by resolving their memory addresses dynamically at runtime. This bypasses compile-time blocks and resolves EXC_BAD_ACCESS segmentation faults inside `AXIsProcessTrustedWithOptions`.
4. **NSDictionary Toll-Free Bridging**: Leverages single-element Cocoa `NSDictionary` mapping to associate CoreFoundation keys and values cleanly, avoiding compiler-boxing wrapper types (`_SwiftValue` issues) inside C-libraries.

---

## 🚀 Building & Running

### Prerequisites
- A Mac running **macOS 14 (Sonoma)** or later.
- **Xcode 15+** or **Xcode Command Line Tools** (Swift 6 compatible) installed.

### Build and Package Bundle
Run the build script in the terminal:
```bash
./build.sh
```
This compiles the executable using Swift Package Manager under release optimization and packages it into a standard macOS application bundle `build/ScreenHighlighter.app`.

### Launch the App
Start the app:
```bash
open build/ScreenHighlighter.app
```

1. On first launch, the app will prompt you to **Grant Accessibility Permissions** in your Mac's System Settings (required for listening to global hotkeys when the app is in the background).
2. The custom **Highlighter** icon will appear in your system menu bar.
3. Press **`Cmd + Shift + H`** to toggle drawing mode.
4. Draw highlights, capture with **`Cmd + Shift + 4`** (or `Cmd + Shift + 3`), copy, and paste!
5. Press `Esc` or click `Exit` to dismiss the overlay (your highlights are retained on the canvas until you click **Clear**).

---

## 🔬 Unit Tests
Run the automated test suites using Swift Package Manager:
```bash
swift test
```

---

## 📄 License
This project is open-source and available under the [MIT License](LICENSE).
