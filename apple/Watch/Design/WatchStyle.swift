import SwiftUI

extension WatchLibraryKind {
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

extension View {
    @ViewBuilder
    func watchGlass<S: Shape>(in shape: S) -> some View {
        if #available(watchOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    @ViewBuilder
    func watchGlassButton(prominent: Bool = false) -> some View {
        if #available(watchOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }
}
