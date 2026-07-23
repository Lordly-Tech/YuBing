import SwiftUI

struct LocalAlbumDetailView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    let album: MusicAlbum

    @State private var searchQuery = ""
    @State private var addToPlaylistItem: LibraryItem?
    @State private var artworkPalette: ArtworkDetailPalette?
    @State private var blurredBackdropImage: CGImage?

    var body: some View {
        AlbumDetailContent(
            album: album,
            tracks: album.tracks,
            palette: resolvedPalette,
            blurredBackdropImage: blurredBackdropImage,
            searchQuery: searchQuery,
            addToPlaylistItem: $addToPlaylistItem
        )
        .navigationTitle("")
        .environment(\.colorScheme, resolvedPalette.colorScheme)
        #if os(iOS)
        .searchable(
            text: $searchQuery,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("在专辑中搜索")
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(resolvedPalette.colorScheme, for: .navigationBar, .tabBar)
        #else
        .searchable(
            text: $searchQuery,
            prompt: Text("在专辑中搜索")
        )
        #endif
        .sheet(item: $addToPlaylistItem) { item in
            AddToLocalPlaylistSheet(item: item)
        }
        .immersiveSplitDetail()
        .task(id: album.id) {
            let assets = await ArtworkAccentColorProvider.shared.detailAssets(
                for: album.artworkData,
                fallbackPrefersDarkAppearance: systemColorScheme == .dark
            )
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                artworkPalette = assets.palette
                blurredBackdropImage = assets.blurredBackdropImage
            }
        }
    }

    private var resolvedPalette: ArtworkDetailPalette {
        artworkPalette
            ?? .fallback(prefersDarkAppearance: systemColorScheme == .dark)
    }
}
