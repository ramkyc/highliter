# Screen Highlighter for macOS Product Specification

## Product definition

Working name: Screen Highlighter for macOS.

This product is a small Mac utility that lets a user draw temporary translucent yellow highlight strokes over anything currently visible on screen, then capture the result using the normal macOS screenshot shortcut and paste that screenshot into WhatsApp or another app. It is intentionally not a file editor, not a screenshot manager, and not a WhatsApp plugin.

## Objective

The product’s core objective is to make visual emphasis faster than file-based annotation workflows. The user should be able to activate it in under a second, drag a highlight over a visible area, take a screenshot, and paste the result directly into a messaging app.

## Success definition

The product is successful if it consistently enables this sequence:

1. User sees content on screen.
2. User invokes the tool instantly.
3. User highlights the target region.
4. User takes a screenshot.
5. User pastes the screenshot into WhatsApp, Slack, Telegram, email, or similar.

## Problem

Current built-in workflows often assume that the user wants to open a file, annotate it, save it, and then share it. That is inefficient for users who only want temporary emphasis and are perfectly happy for the screenshot itself to be the final output.

Your stated preference is specifically to avoid saving or exporting an edited image and to avoid Preview-style file handling for this task. That means the right solution is an ephemeral screen overlay rather than a conventional image editor.

## Target user

### Primary user

A Mac user who frequently shares screenshots, chat snippets, app UIs, images, web pages, or text excerpts and wants to mark them up quickly before sending them.

### User characteristics

- Values speed over edit richness.
- Does not want to manage extra files.
- Is comfortable treating the screenshot as the final artifact.
- Frequently pastes captured content into chat apps.
- Wants a tool that feels lightweight and disposable.

## Use cases

### Primary use cases

- Highlight text or part of an image visible on screen, then screenshot and paste into WhatsApp.
- Highlight a piece of a web page, PDF preview, email, chat thread, or app window without editing the source.
- Add quick emphasis during a call, demo, review, or presentation before capturing a screenshot.
- Draw temporary highlight strokes over anything on the desktop and clear them immediately after use.

### Non-goals

The product should not become a full annotation suite in v1. It should avoid text boxes, shapes, cloud sync, export management, OCR, stickers, filters, or document workflows.

It should also not attempt to insert custom tools into WhatsApp’s own UI. Earlier discussion established that modifying WhatsApp’s internal toolbar is not the practical path; the correct model is a standalone overlay utility.

## Product principles

1. Speed over richness.
2. Temporary by default.
3. Works over anything visible on screen.
4. Screenshot-first, not file-first.
5. Minimal UI and minimal decision-making.

## User stories

- As a user, I want a shortcut that instantly enters highlight mode so I do not have to open an editor.
- As a user, I want the stroke to look like a familiar yellow marker so the highlighted area remains readable underneath.
- As a user, I want to take a regular screenshot after highlighting and paste it directly into a chat app.
- As a user, I want undo and clear so mistakes do not slow me down.
- As a user, I want the tool to stay out of my way when I am not using it.
- As a user, I want it to live in the menu bar so it feels lightweight and always available.

## Product scope

### In scope for MVP

- macOS utility app.
- Menu bar presence.
- Global keyboard shortcut.
- Transparent always-on-top overlay.
- One yellow highlight tool.
- Undo last stroke.
- Clear all strokes.
- Hide or exit overlay.
- Compatibility with normal macOS screenshot capture.

### Out of scope for MVP

- File import or export.
- WhatsApp integration.
- Full image editor.
- Multiple drawing tools beyond the core marker.
- OCR or text recognition.
- Cloud storage or collaboration.
- Embedded screenshot library.

## UX specification

### Primary flow

1. The user sees something on screen they want to highlight.
2. The user presses a global shortcut.
3. A transparent overlay appears over the active display.
4. A tiny floating toolbar appears with the highlighter active by default.
5. The user drags a yellow translucent stroke over the desired area.
6. The user uses the standard macOS screenshot shortcut to capture the highlighted region.
7. The user pastes the screenshot into WhatsApp or another app.
8. The user clears the overlay or exits the mode.

### Secondary flows

- If the user makes a mistake, Undo removes the most recent stroke.
- If the toolbar is in the way, it can be moved or collapsed.
- If the user wants a clean screen immediately after capture, the app may auto-clear on exit or after capture in a later version.

### Interaction expectations

The product must require almost no setup. The highlight tool should be active by default when invoked, without forcing the user to choose mode, color, or width every time.

The user should feel like they are drawing directly over the screen, not into a separate app window. This distinction is critical to the product experience.

## Interface specification

### Main surfaces

| Surface | Purpose |
|---|---|
| Menu bar icon | Access, status, preferences, quit |
| Overlay canvas | Full-screen temporary drawing layer |
| Floating toolbar | Minimal active controls during highlighting |
| Preferences window | Shortcut and behavior settings |
| First-run onboarding | Permission explanation and quick tutorial |

### Floating toolbar

The toolbar should be intentionally sparse.

Recommended controls:

- Yellow highlighter indicator.
- Undo.
- Clear all.
- Hide toolbar.
- Exit overlay.

Optional controls for later versions:

- Brush width selector.
- Redo.
- Auto-clear toggle.

### Menu bar menu

Suggested entries:

- Show Highlighter.
- Clear Highlights.
- Preferences.
- Quit.

## Visual design

### Highlight appearance

The highlight should look like a regular office yellow marker, not a hard digital paint line. It should preserve legibility underneath and visually signal emphasis rather than obscuring content.

| Attribute | Recommendation |
|---|---|
| Color | Warm marker yellow |
| Opacity | 30 to 45% |
| Width | 18 to 28 px |
| Edge quality | Softened, slightly organic |
| Blend mode | Standard alpha blending |

### Toolbar appearance

The toolbar should feel native to macOS, ideally using a compact translucent panel aesthetic. It should be visually present but not prominent enough to distract from the highlighted content.

## Functional requirements

### Invocation

The app must support a global keyboard shortcut to enter and exit highlight mode. The shortcut must be configurable, though the product should ship with a sensible default.

The app must also be discoverable from the menu bar at all times while running.

### Overlay behavior

The app must create a transparent, always-on-top overlay over the current display. The overlay must preserve visibility of all underlying screen content while accepting pointer input for drawing.

The overlay must support at least these states:

- Hidden.
- Visible and ready for drawing.
- Visible but passive, if a later click-through mode is introduced.

### Drawing behavior

The user must be able to click and drag to create smooth freehand strokes. Strokes must render with minimal latency so the drawing feels directly attached to pointer motion.

Each stroke should be modeled as a sequence of points with associated style attributes. A smoothing pass should be used so highlights do not appear jagged.

### Editing controls

The app must support:

- Undo last stroke.
- Clear all strokes.
- Exit overlay.

Redo is optional but desirable if implementation effort is low.

### Screenshot compatibility

The app does not need its own screenshot engine in v1. Instead, it must work cleanly with the standard macOS screenshot workflow so that the captured result includes the highlight overlay.

This is one of the most important technical validation points in the project. If overlay behavior conflicts with the screenshot UI, a later capture-helper mode may be necessary.

### Persistence model

By default, the app should not save highlighted results to disk. Stroke data should remain in memory for the active session only.

Optional later behavior:

- Retain last highlights until cleared.
- Auto-clear after capture.

## Technical specification

### Platform and stack

Recommended implementation:

- macOS desktop utility.
- Swift with SwiftUI for app shell and settings.
- AppKit interop for transparent windows, overlay control, and advanced window behavior.

### Suggested architecture

| Module | Responsibility |
|---|---|
| App shell | Lifecycle, menu bar, preferences |
| Shortcut manager | Global hotkey registration |
| Overlay window manager | Transparent top-level windows |
| Drawing engine | Pointer tracking and stroke rendering |
| Stroke model | Path points, width, opacity, color |
| Toolbar controller | Overlay controls and commands |
| Permissions manager | First-run access and permission checks |
| Screenshot coordinator | Compatibility handling with system screenshots |

### Overlay implementation

The overlay should likely be implemented as a borderless transparent window at a high window level. It must appear above ordinary apps and feel like a screen layer rather than a standard app window.

For v1, active-display-only behavior is enough. Multi-display support can come later once coordinate management is robust.

### Drawing engine details

Recommended stroke model:

```text
Stroke
- id
- points
- color
- opacity
- width
- timestamp
```

Rendering must be smooth and immediate on normal Macs. A simple in-memory stroke stack is sufficient for undo in v1.

## Preferences

| Preference | Default |
|---|---|
| Global shortcut | Preconfigured sensible default |
| Stroke width | Default marker width |
| Auto-clear on exit | On |
| Launch at login | Off |
| Active display only | On |
| Toolbar position memory | On |

## Permissions

The app should minimize permissions as much as possible to reduce user trust friction. If accessibility permissions are needed for global shortcuts or advanced interactions, the onboarding must explain clearly why they are required.

The onboarding message should also make it explicit that the app does not upload or store screen content by default. This matters because the app is visually present over potentially sensitive content.

## Performance requirements

- Overlay appears within 300 ms after invocation.
- Drawing latency is low enough to feel immediate.
- CPU usage at idle is near zero.
- Memory footprint remains lightweight for a menu bar app.
- Performance remains smooth with dozens of strokes visible.

## Accessibility requirements

- Keyboard support for show, hide, undo, clear, and quit.
- Accessible labels for toolbar controls.
- Toolbar visibility and contrast that work in light and dark appearance modes.
- Optional larger toolbar scale in settings for users who need it.

## Privacy and security

The privacy model should be minimal by design:

- No cloud sync in v1.
- No saved annotated files by default.
- No telemetry by default, or opt-in only if added later.
- No inspection or transmission of screen contents.

## Edge cases

Key cases that must be validated early:

- Whether the overlay is included reliably in system screenshots.
- Full-screen apps and macOS Spaces behavior.
- Multi-monitor coordinate offsets.
- Retina scaling effects on stroke width.
- Ensuring the toolbar does not get unintentionally captured in screenshots.
- Ensuring overlay interaction ends cleanly and does not block normal clicks afterward.

## Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| macOS screenshot UI conflicts with overlay | High | Test very early; add capture-helper fallback if needed |
| Drawing feels laggy | High | Keep feature scope tiny and optimize the drawing path first |
| Permissions feel intrusive | Medium | Minimize permissions and explain them clearly |
| Toolbar gets in the way | Medium | Make it movable or collapsible |
| Scope expands too quickly | High | Keep v1 centered on one tool only |
| Users expect export features | Low | Position product clearly as screenshot-first |

## Release plan

### MVP

The MVP should include:

- One yellow highlighter.
- Menu bar app.
- Global shortcut.
- Transparent overlay on active display.
- Undo.
- Clear all.
- No save or export.

### Version 1.1

Potential upgrades:

- Redo.
- Adjustable width.
- Multi-display support.
- Auto-clear after screenshot.
- Better toolbar hiding behavior during capture.

### Version 2

Possible expansions:

- More colors.
- Straight-line highlight mode.
- Temporary spotlight effect around the target area.
- Timed fade-out of highlights.
- Built-in clipboard-oriented capture assistance.

## Recommended MVP definition

The narrowest and best MVP is this:

- A menu bar Mac app.
- A global shortcut.
- A transparent overlay.
- A single yellow translucent highlighter.
- Undo and clear.
- Designed specifically for highlight, screenshot, paste.

That version is the closest match to your stated workflow and gives the best chance of feeling genuinely faster than Preview, file annotation, or chat-app editors.

## Product positioning

This product should be positioned as a temporary emphasis tool for screenshots, not as an image editor. That wording keeps the promise clear and prevents user expectations from drifting toward a much larger and more complicated annotation app.
