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
            valueRow(title: "歌手", value: song.artistText)
            Divider().overlay(.white.opacity(0.12))
            valueRow(title: "专辑", value: song.albumText)

            if let year = song.metadata.year {
                Divider().overlay(.white.opacity(0.12))
                valueRow(title: "发行年份", value: year)
            }

            if let genre = song.metadata.genre {
                Divider().overlay(.white.opacity(0.12))
                valueRow(title: "流派", value: genre)
            }

            if !song.metadata.qualityDescription.isEmpty {
                Divider().overlay(.white.opacity(0.12))
                valueRow(title: "音频", value: song.metadata.qualityDescription)
            }
        }
        .padding(.horizontal, 16)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 16))
    }

    private func valueRow(title: String, value: String) -> some View {
        LabeledContent(title, value: value)
            .frame(minHeight: 46)
    }
}
