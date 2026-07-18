import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject private var store: WatchLibraryStore
    @EnvironmentObject private var player: WatchAudioPlayer

    var body: some View {
        NavigationStack {
            List {
                if let current = player.currentItem {
                    Section {
                        NavigationLink {
                            WatchNowPlayingView(startingItem: current)
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                                    .foregroundStyle(.pink)
                                    .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(current.displayName).lineLimit(1)
                                    Text("正在播放").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    destinationRow("文件", symbol: "folder", count: store.items.count) {
                        WatchFileBrowserView()
                    }
                    destinationRow("阅读", symbol: "books.vertical", count: store.items(of: [.novel, .comic, .photo]).count) {
                        WatchReadingLibraryView()
                    }
                    destinationRow("音乐", symbol: "music.note.list", count: store.items(of: [.music]).count) {
                        WatchMusicLibraryView()
                    }
                    destinationRow("图库", symbol: "photo.on.rectangle.angled", count: store.items(of: [.photo, .video]).count) {
                        WatchGalleryView()
                    }
                }

                if !store.recents.isEmpty {
                    Section("最近") {
                        ForEach(store.recents.prefix(4)) { item in
                            NavigationLink {
                                WatchItemDestination(item: item)
                            } label: {
                                WatchFileRow(item: item)
                            }
                        }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(store.transferStatus, systemImage: "iphone.and.arrow.forward")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Label(store.totalBytes.watchFormattedFileSize, systemImage: "internaldrive")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .navigationTitle("鱼饼")
            .alert(item: $store.alert) { alert in
                Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("好")))
            }
        }
    }

    private func destinationRow<Destination: View>(
        _ title: String,
        symbol: String,
        count: Int,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct WatchFileRow: View {
    let item: WatchLibraryItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.kind.symbol)
                .foregroundStyle(item.kind.tint)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .lineLimit(1)
                Text(item.isDirectory ? item.kind.title : item.byteCount.watchFormattedFileSize)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
