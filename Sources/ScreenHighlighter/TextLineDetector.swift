import AppKit
import Vision

/// Detects the on-screen bounding boxes of text lines within a region by
/// capturing the display and running on-device OCR via the Vision framework.
///
/// All capture and recognition happens locally on the Mac — nothing is saved
/// to disk or transmitted anywhere. The detector exists purely to let the
/// multi-line highlight gesture "snap" its heuristic bands onto the real
/// positions of the text underneath, shortly after the user finishes dragging.
///
/// Declared as an `actor` so the (synchronous, potentially slow) capture and
/// recognition work runs off the main thread automatically, keeping the UI
/// responsive while OCR completes.
public actor TextLineDetector {
    public static let shared = TextLineDetector()

    private init() {}

    /// Returns the bounding boxes — expressed in the same coordinate space as
    /// `NSScreen.frame` (origin at the bottom-left, Y increasing upward) — of
    /// every text line that overlaps `region`.
    ///
    /// Returns `nil` if the display couldn't be captured (e.g. Screen
    /// Recording permission hasn't been granted), and an empty array if
    /// capture and recognition both succeeded but no text lines were found
    /// overlapping the region (e.g. the user highlighted an image).
    ///
    /// - Parameters:
    ///   - region: The dragged rectangle, in global screen coordinates.
    ///   - displayID: The Core Graphics display ID to capture. Callers derive
    ///     this from `NSScreen` on the main actor and pass the plain value in,
    ///     since `NSScreen` itself isn't `Sendable`.
    ///   - displayFrame: That same screen's `frame`, also extracted on the
    ///     main actor — needed to map Vision's normalized coordinates back
    ///     onto real screen coordinates.
    public func detectLines(overlapping region: CGRect, displayID: CGDirectDisplayID, displayFrame: CGRect) async -> [CGRect]? {
        guard let cgImage = captureDisplayImage(displayID: displayID) else { return nil }

        let normalizedBoxes = await recognizedLineBoundingBoxes(in: cgImage)
        guard !normalizedBoxes.isEmpty else { return [] }

        // Vision expresses each line's bounding box as a normalized rect
        // (0...1) with the origin at the BOTTOM-LEFT of the image — the same
        // convention AppKit uses for `NSScreen.frame`. Because the captured
        // image corresponds 1:1 to the full display, a simple linear scale
        // maps Vision's coordinates straight onto screen coordinates with no
        // axis-flipping required.
        let rawLineRects = normalizedBoxes.map { box -> CGRect in
            CGRect(
                x: displayFrame.minX + box.minX * displayFrame.width,
                y: displayFrame.minY + box.minY * displayFrame.height,
                width: box.width * displayFrame.width,
                height: box.height * displayFrame.height
            )
        }

        let lineRects = mergedIntoLines(rawLineRects)
        return lineRects.filter { $0.intersects(region) }
    }

    /// Vision sometimes reports a single visual line of text as several
    /// adjacent observations — e.g. splitting at large word gaps or distinct
    /// fonts/styles within the same line. Left as-is, that produces multiple
    /// partial highlight bands per line instead of one continuous band
    /// (visible as "starts from the middle" gaps). This merges observations
    /// that are both vertically aligned (within 60% of the shorter box's
    /// height — comfortably less than the gap between distinct lines) AND
    /// horizontally close (a small, inter-word-sized gap) into a single
    /// combined per-line rectangle.
    ///
    /// The horizontal-proximity check matters just as much as the vertical
    /// one: without it, two *unrelated* fragments that merely happen to sit
    /// at a similar row height — e.g. a paragraph line in the main content
    /// pane and an unrelated label in a sidebar several hundred points to its
    /// right, both inside the same app window — get unioned into one
    /// rectangle spanning the empty gap between them. That produced a
    /// highlight band that "leaked" past the end of the visible text into
    /// blank space toward the window edge, even though the cross-window
    /// scope clip (which only trims at the *window* boundary) had nothing to
    /// catch, since both fragments were legitimately inside the same window.
    /// Real text on one visual line never has a gap larger than a few
    /// character-widths between adjacent runs, so capping the merge distance
    /// at a small multiple of the line height reliably distinguishes "still
    /// the same line of text" from "two unrelated regions that happen to
    /// align vertically."
    private func mergedIntoLines(_ rects: [CGRect]) -> [CGRect] {
        guard !rects.isEmpty else { return [] }
        let sorted = rects.sorted { $0.midY > $1.midY }

        var merged: [CGRect] = []
        for rect in sorted {
            if let last = merged.last {
                let verticalTolerance = min(last.height, rect.height) * 0.6
                let verticallyAligned = abs(last.midY - rect.midY) <= verticalTolerance

                // Gap between the two rects' nearest horizontal edges (zero,
                // or effectively negative, if they already overlap).
                let horizontalGap = max(rect.minX, last.minX) > min(rect.maxX, last.maxX)
                    ? max(rect.minX - last.maxX, last.minX - rect.maxX)
                    : 0
                let horizontalTolerance = min(last.height, rect.height) * 2.5
                let horizontallyClose = horizontalGap <= horizontalTolerance

                if verticallyAligned && horizontallyClose {
                    merged[merged.count - 1] = last.union(rect)
                    continue
                }
            }
            merged.append(rect)
        }
        return merged
    }

    /// Captures the full contents of the given display as a single image.
    ///
    /// `CGDisplayCreateImage` was deprecated in macOS 14 in favor of
    /// ScreenCaptureKit's async APIs, but it remains fully functional and is
    /// far simpler to reason about for a one-shot, single-display capture: it
    /// needs no shareable-content discovery, content filters, or stream
    /// configuration, and it sidesteps ScreenCaptureKit's separate
    /// top-left-origin `sourceRect` coordinate space entirely. We accept the
    /// deprecation warning in exchange for a much smaller surface for
    /// coordinate-conversion bugs.
    private func captureDisplayImage(displayID: CGDirectDisplayID) -> CGImage? {
        return CGDisplayCreateImage(displayID)
    }

    /// Runs Vision's text-line recognizer over the captured image and returns
    /// each result's normalized `boundingBox` (0...1, origin at bottom-left).
    ///
    /// We extract just the `CGRect` geometry *inside* the completion handler,
    /// before resuming the continuation, rather than returning the
    /// `VNRecognizedTextObservation`s themselves: those aren't `Sendable`, so
    /// handing them across the continuation's isolation boundary would risk a
    /// data race (and fail Swift 6's strict checking). `CGRect` is a simple,
    /// `Sendable` value type, so this sidesteps the issue entirely.
    private func recognizedLineBoundingBoxes(in cgImage: CGImage) async -> [CGRect] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let boxes = ((request.results as? [VNRecognizedTextObservation]) ?? []).map(\.boundingBox)
                continuation.resume(returning: boxes)
            }
            // We only need each line's geometry, not its recognized text, so
            // favor speed over accuracy and skip language post-processing.
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }
}

extension NSScreen {
    /// The Core Graphics display ID backing this screen — needed to target a
    /// specific physical display for capture. `nil` only in the unlikely case
    /// the device description is missing the screen-number key.
    public var cgDirectDisplayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
