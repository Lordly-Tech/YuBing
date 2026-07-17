import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct FileImportButton: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var isImporterPresented = false

    var destination: URL?
    var title = "导入文件"
    var prominent = false

    var body: some View {
        Button {
            isImporterPresented = true
        } label: {
            Label(title, systemImage: "square.and.arrow.down")
        }
        .adaptiveGlassButton(prominent: prominent)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                store.importFiles(urls, into: destination)
            case .failure(let error):
                store.alert = LibraryAlert(title: "无法导入", message: error.localizedDescription)
            }
        }
    }
}

struct PhotoImportButton: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var selection: [PhotosPickerItem] = []

    var destination: URL?

    var body: some View {
        PhotosPicker(selection: $selection, maxSelectionCount: 0, matching: .images) {
            Label("从照片导入", systemImage: "photo.badge.plus")
        }
        .adaptiveGlassButton()
        .onChange(of: selection) { _, newItems in
            Task {
                for item in newItems {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                    let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                    let stem = item.itemIdentifier?.replacingOccurrences(of: "/", with: "-") ?? UUID().uuidString
                    store.importData(data, suggestedName: "\(stem).\(ext)", into: destination)
                }
                selection.removeAll()
            }
        }
    }
}

