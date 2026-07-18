import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

enum PhotoImportScope {
    case images
    case videos
    case media

    var filter: PHPickerFilter {
        switch self {
        case .images: .images
        case .videos: .videos
        case .media: .any(of: [.images, .videos])
        }
    }

    var title: String {
        switch self {
        case .images: "从相册选择照片"
        case .videos: "从相册选择视频"
        case .media: "从相册选择照片或视频"
        }
    }
}

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
            Task { @MainActor in
                await importPickerItems(newItems, into: destination, store: store)
                selection.removeAll()
            }
        }
    }
}

struct LibraryImportMenu: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var isFileImporterPresented = false
    @State private var photoSelection: [PhotosPickerItem] = []

    var destination: URL?
    var title = "添加"
    var photoScope: PhotoImportScope = .media
    var prominent = false

    var body: some View {
        Menu {
            Button {
                isFileImporterPresented = true
            } label: {
                Label("从文件选择", systemImage: "folder")
            }

            PhotosPicker(
                selection: $photoSelection,
                maxSelectionCount: 0,
                matching: photoScope.filter
            ) {
                Label(photoScope.title, systemImage: "photo.on.rectangle.angled")
            }
        } label: {
            Label(title, systemImage: "plus")
        }
        .adaptiveGlassButton(prominent: prominent)
        .fileImporter(
            isPresented: $isFileImporterPresented,
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
        .onChange(of: photoSelection) { _, newItems in
            Task { @MainActor in
                await importPickerItems(newItems, into: destination, store: store)
                photoSelection.removeAll()
            }
        }
    }
}

private struct ImportedPickerFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .data) { received in
            let fileExtension = received.file.pathExtension
            let name = fileExtension.isEmpty ? UUID().uuidString : "\(UUID().uuidString).\(fileExtension)"
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}

@MainActor
private func importPickerItems(
    _ items: [PhotosPickerItem],
    into destination: URL?,
    store: LibraryStore
) async {
    for item in items {
        let type = item.supportedContentTypes.first
        let fileExtension = type?.preferredFilenameExtension ?? "jpg"
        let stem = item.itemIdentifier?
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-") ?? UUID().uuidString
        let suggestedName = "\(stem).\(fileExtension)"

        if let file = try? await item.loadTransferable(type: ImportedPickerFile.self) {
            store.importFile(file.url, suggestedName: suggestedName, into: destination)
            try? FileManager.default.removeItem(at: file.url)
        } else if let data = try? await item.loadTransferable(type: Data.self) {
            store.importData(data, suggestedName: suggestedName, into: destination)
        }
    }
}
