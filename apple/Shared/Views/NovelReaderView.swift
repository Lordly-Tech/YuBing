import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

private enum ReaderAppearance: String, CaseIterable, Identifiable {
    case system
    case paper
    case night

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "自动"
        case .paper: "纸张"
        case .night: "夜间"
        }
    }

    var background: Color {
        switch self {
        case .system:
            #if os(macOS)
            Color(nsColor: .textBackgroundColor)
            #else
            Color(uiColor: .systemBackground)
            #endif
        case .paper: Color(red: 0.94, green: 0.91, blue: 0.82)
        case .night: Color(red: 0.06, green: 0.065, blue: 0.075)
        }
    }

    var foreground: Color {
        switch self {
        case .system: .primary
        case .paper: Color(red: 0.18, green: 0.16, blue: 0.12)
        case .night: Color(white: 0.88)
        }
    }
}

struct NovelReaderView: View {
    @EnvironmentObject private var store: LibraryStore
    #if os(iOS)
    @EnvironmentObject private var watchTransfer: WatchTransferService
    #endif

    let item: LibraryItem

    @State private var content = ""
    @State private var loadError: String?
    @State private var fontSize: Double = 19
    @State private var lineSpacing: Double = 8
    @State private var appearance: ReaderAppearance = .system
    @State private var isSettingsPresented = false

    var body: some View {
        ZStack {
            appearance.background.ignoresSafeArea()
            if let loadError {
                ContentUnavailableView("无法读取文本", systemImage: "text.badge.xmark", description: Text(loadError))
            } else if content.isEmpty {
                ProgressView("正在打开")
            } else {
                ScrollView {
                    Text(content)
                        .font(.system(size: fontSize, design: .serif))
                        .foregroundStyle(appearance.foreground)
                        .lineSpacing(lineSpacing)
                        .textSelection(.enabled)
                        .frame(maxWidth: 720, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 34)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(item.displayName)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.toggleFavorite(item)
                } label: {
                    Label("收藏", systemImage: store.isFavorite(item) ? "star.fill" : "star")
                }
                #if os(iOS)
                Button {
                    watchTransfer.send([item])
                } label: {
                    Label("发送到 Apple Watch", systemImage: "applewatch.radiowaves.left.and.right")
                }
                #endif
                Button {
                    isSettingsPresented.toggle()
                } label: {
                    Label("阅读设置", systemImage: "textformat.size")
                }
                .popover(isPresented: $isSettingsPresented) { settings }
            }
        }
        .task { loadText() }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("阅读设置")
                .font(.headline)
            Picker("外观", selection: $appearance) {
                ForEach(ReaderAppearance.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 7) {
                Text("字号 \(Int(fontSize))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $fontSize, in: 14...32, step: 1)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("行距 \(Int(lineSpacing))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $lineSpacing, in: 2...16, step: 1)
            }
        }
        .padding(20)
        .frame(width: 310)
    }

    private func loadText() {
        do {
            var encoding = String.Encoding.utf8
            content = try String(contentsOf: item.url, usedEncoding: &encoding)
        } catch {
            loadError = error.localizedDescription
        }
    }
}
