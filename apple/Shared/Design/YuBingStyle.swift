import SwiftUI

extension LibraryKind {
    var symbol: String {
        switch self {
        case .novel: "text.book.closed"
        case .comic: "rectangle.stack"
        case .music: "waveform"
        case .video: "play.rectangle"
        case .photo: "photo"
        case .folder: "folder.fill"
        case .file: "doc"
        }
    }

    var tint: Color {
        switch self {
        case .novel: .blue
        case .comic: .orange
        case .music: .pink
        case .video: .purple
        case .photo: .green
        case .folder: .cyan
        case .file: .secondary
        }
    }
}

enum YuBingMetrics {
    static let compactCornerRadius: CGFloat = 8
    static let panelCornerRadius: CGFloat = 12
    static let sidebarWidth: CGFloat = 240
    static let contentMaxWidth: CGFloat = 1180
}

extension View {
    @ViewBuilder
    func adaptiveGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, macOS 26.0, watchOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    @ViewBuilder
    func adaptiveGlassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, macOS 26.0, watchOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }
}

struct AdaptiveGlassGroup<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, watchOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                content
            }
        } else {
            content
        }
    }
}
