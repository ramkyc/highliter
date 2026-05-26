import SwiftUI

public struct ToolbarView: View {
    @ObservedObject var engine: DrawingEngine
    var onExit: () -> Void
    
    @State private var isHovered: [String: Bool] = [:]
    
    // Premium glowing colors mapping hex to SwiftUI Colors
    private static let paletteColors: [(String, Color)] = [
        ("#FFFF00", Color.yellow),
        ("#30D158", Color.green),
        ("#0A84FF", Color.blue),
        ("#FF2D55", Color.pink),
        ("#FF9F0A", Color.orange)
    ]
    
    public init(engine: DrawingEngine, onExit: @escaping () -> Void) {
        self.engine = engine
        self.onExit = onExit
    }
    
    public var body: some View {
        HStack(spacing: 14) {
            // Interactive Glowing Color Palette
            HStack(spacing: 8) {
                ForEach(Self.paletteColors, id: \.0) { hex, color in
                    Circle()
                        .fill(color)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: engine.activeColorHex.uppercased() == hex.uppercased() ? 1.5 : 0)
                                .frame(width: 20, height: 20)
                                .shadow(color: color.opacity(0.8), radius: engine.activeColorHex.uppercased() == hex.uppercased() ? 4 : 0)
                        )
                        .scaleEffect(isHovered[hex, default: false] ? 1.2 : 1.0)
                        .animation(.spring(response: 0.2, dampingFraction: 0.5), value: isHovered[hex, default: false])
                        .onTapGesture {
                            engine.activeColorHex = hex
                        }
                        .onHover { hovering in
                            isHovered[hex] = hovering
                        }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.08))
            .cornerRadius(8)
            
            Divider()
                .frame(width: 1, height: 16)
                .background(Color.white.opacity(0.2))
            
            // Undo Button
            Button(action: {
                engine.undo()
            }) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(engine.strokes.isEmpty ? Color.white.opacity(0.25) : Color.white)
            }
            .buttonStyle(.plain)
            .disabled(engine.strokes.isEmpty)
            .help("Undo (Cmd+Z)")
            .scaleEffect(isHovered["undo", default: false] && !engine.strokes.isEmpty ? 1.15 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.5), value: isHovered["undo", default: false])
            .onHover { hovering in
                isHovered["undo"] = hovering
            }
            
            // Clear Button
            Button(action: {
                engine.clear()
            }) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(engine.strokes.isEmpty ? Color.white.opacity(0.25) : Color.red.opacity(0.85))
            }
            .buttonStyle(.plain)
            .disabled(engine.strokes.isEmpty)
            .help("Clear All")
            .scaleEffect(isHovered["clear", default: false] && !engine.strokes.isEmpty ? 1.15 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.5), value: isHovered["clear", default: false])
            .onHover { hovering in
                isHovered["clear"] = hovering
            }
            
            Divider()
                .frame(width: 1, height: 16)
                .background(Color.white.opacity(0.2))
            
            // Exit Button
            Button(action: onExit) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            .help("Exit Overlay (Esc)")
            .scaleEffect(isHovered["exit", default: false] ? 1.15 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.5), value: isHovered["exit", default: false])
            .onHover { hovering in
                isHovered["exit"] = hovering
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .padding(8)
    }
}

// SwiftUI Frosted Glass Bridge
public struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    public init(material: NSVisualEffectView.Material, blendingMode: NSVisualEffectView.BlendingMode) {
        self.material = material
        self.blendingMode = blendingMode
    }
    
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
