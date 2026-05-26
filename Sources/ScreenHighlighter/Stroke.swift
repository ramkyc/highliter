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
        // Return active yellow highlight color with defined opacity
        if colorHex.uppercased() == "#FFFF00" {
            return NSColor.yellow.withAlphaComponent(opacity)
        }
        // Fallback parser for arbitrary hex if needed
        return NSColor.yellow.withAlphaComponent(opacity)
    }
}

public struct Stroke: Identifiable, Codable, Equatable {
    public let id: UUID
    public var points: [StrokePoint]
    public var style: StrokeStyle
    public let createdAt: Date
    
    public init(id: UUID = UUID(), points: [StrokePoint] = [], style: StrokeStyle = StrokeStyle(), createdAt: Date = Date()) {
        self.id = id
        self.points = points
        self.style = style
        self.createdAt = createdAt
    }
}
