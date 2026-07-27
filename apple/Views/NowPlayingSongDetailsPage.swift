import SwiftUI

struct NowPlayingSongDetailsPage: View {
    let song: NowPlayingSong
    @Binding var showsSleepTimer: Bool
    let showsArtworkToggle: Bool
    let artworkNamespace: Namespace.ID
    let onShowArtwork: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if showsArtworkToggle {
                    detailsHeader
                }

                HStack {
                    Text("歌曲资料")
                        .font(.title2.bold())

                    Spacer()

                    NowPlayingSongActions(
                        song: song,
                        showsSleepTimer: $showsSleepTimer,
                        isShowingDetails: true,
                        onToggleDetails: onShowArtwork
                    )
                }

                detailsCard
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
    }

    private var detailsHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            Button(action: onShowArtwork) {
                ArtworkImage(data: song.artworkData, cornerRadius: 10)
                    .matchedGeometryEffect(
                        id: song.id,
                        in: artworkNamespace,
                        properties: .frame
                    )
                    .frame(width: 82, height: 82)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回封面")
            .accessibilityHint("轻点切换回大封面")

            VStack(alignment: .leading, spacing: 5) {
                Text(song.name)
                    .font(.title3.bold())
                    .lineLimit(2)

                Text(song.artistText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(detailRows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Divider().overlay(.white.opacity(0.12))
                }
                valueRow(title: row.title, value: row.value)
            }
        }
        .padding(.horizontal, 16)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 16))
    }

    private var detailRows: [SongDetailRow] {
        let metadata = song.metadata
        let candidates: [(String, String?)] = [
            ("标题", song.name),
            ("歌手", song.artistText),
            ("作曲", metadata.composer),
            ("唱片集", song.albumText),
            ("发行年份", metadata.year),
            ("流派", metadata.genre),
            ("格式", song.item.fileExtension.uppercased()),
            ("比特率", metadata.bitRateDescription),
            ("声道", metadata.channelDescription),
            ("采样率", metadata.sampleRateDescription)
        ]

        return candidates.compactMap { title, value in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return SongDetailRow(title: title, value: trimmed)
        }
    }

    private func valueRow(title: String, value: String) -> some View {
        LabeledContent(AppLocalization.string(title), value: value)
            .frame(minHeight: 46)
    }
}

private struct SongDetailRow: Identifiable {
    let id = UUID()
    let title: String
    let value: String
}
