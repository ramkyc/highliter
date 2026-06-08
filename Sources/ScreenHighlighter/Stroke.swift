import Foundation
import AppKit

public struct StrokePoint: Codable, Equatable {
    public let x: CGFloat
    public let y: CGFloat
    public let timestamp: TimeInterval
    
    public init(x: CGFloat, y: CGFloat, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.x = x
        self.y = y
        self.timestamp = timestamp
    }
    
    public var cgPoint: CGPoint {
        return CGPoint(x: x, y: y)
    }
}

public struct StrokeStyle: Codable, Equatable {
    public var width: CGFloat
    public var opacity: CGFloat
    public var colorHex: String
    
    public init(width: CGFloat = 20.0, opacity: CGFloat = 0.35, colorHex: String = "#FFFF00") {
        self.width = width
        self.opacity = opacity
        self.colorHex = colorHex
    }
    
    public var nsColor: NSColor {
        // Dynamically resolve custom hex marker color with defined alpha component
        return NSColor(hex: colorHex)?.withAlphaComponent(opacity) ?? NSColor.yellow.withAlphaComponent(opacity)
    }
}

// MARK: - NSColor Hex Extension
extension NSColor {
    convenience init?(hex: String) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleanHex.hasPrefix("#") {
            cleanHex.remove(at: cleanHex.startIndex)
        }
        
        guard cleanHex.count == 6 else { return nil }
        
        var rgb: UInt64 = 0
        guard Scanner(string: cleanHex).scanHexInt64(&rgb) else { return nil }
        
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}

public struct Stroke: Identifiable, Codable, Equatable {
    public let id: UUID
    public var points: [StrokePoint]
    public var style: StrokeStyle
    public let createdAt: Date

    /// When present, marks this stroke as a set of independent straight-line
    /// "bands" (e.g. a multi-line text-style highlight) rather than one
    /// continuous smoothed path. Each range indexes a `[start, end]` pair in
    /// `points` that should be drawn as its own segment, with no connecting
    /// line drawn between bands. `nil` preserves the normal freehand/curve
    /// rendering used for ordinary strokes.
    public var bandRanges: [Range<Int>]? = nil

    public init(id: UUID = UUID(), points: [StrokePoint] = [], style: StrokeStyle = StrokeStyle(), createdAt: Date = Date(), bandRanges: [Range<Int>]? = nil) {
        self.id = id
        self.points = points
        self.style = style
        self.createdAt = createdAt
        self.bandRanges = bandRanges
    }
}
