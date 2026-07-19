import SwiftUI

#if os(iOS)
import MediaPlayer
import SafariServices
#endif

#if os(macOS)
import AppKit
#endif

struct MoreView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: AudioPlayerController
    @AppStorage(AppLocalization.preferenceKey) private var appLanguageRaw = AppLanguage.system.rawValue

    #if os(iOS)
    @State private var musicAuthorization = MPMediaLibrary.authorizationStatus()
    #endif

    var body: some View {
        List {
            featuresSection
            identitySection
            languageSection
            librarySection
            permissionSection
            legalSection
        }
        .navigationTitle("更多")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        #if os(iOS)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                musicAuthorization = MPMediaLibrary.authorizationStatus()
            }
        }
        #endif
    }

    @Environment(\.scenePhase) private var scenePhase

    private var featuresSection: some View {
        Section("功能") {
            NavigationLink {
                FileBrowserView()
            } label: {
                MoreRowLabel(title: "文件管理", systemImage: "folder", tint: .blue)
            }

            NavigationLink {
                FavoriteLibraryView()
            } label: {
                MoreRowLabel(title: "收藏", systemImage: "star", tint: .yellow)
            }

            #if os(iOS)
            NavigationLink {
                WatchTransferView()
            } label: {
                MoreRowLabel(title: "传到 Watch", systemImage: "applewatch.radiowaves.left.and.right", tint: .orange)
            }
            #endif
        }
    }

    private var identitySection: some View {
        Section {
            HStack(spacing: 16) {
                Image("AppIcon")
                    .resizable()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("鱼饼")
                        .font(.title3.weight(.bold))
                    Text("阅读与媒体资料库")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(versionString)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
        }
    }

    private var languageSection: some View {
        Section {
            Picker(selection: $appLanguageRaw) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.label).tag(language.rawValue)
                }
            } label: {
                MoreRowLabel(title: "应用语言", subtitle: languageSummary, systemImage: "globe", tint: .blue)
            }
            .pickerStyle(.inline)
        } header: {
            Text("语言")
        } footer: {
            Text("不在列表内的系统语言将使用 English。")
        }
    }

    private var librarySection: some View {
        Section("资料库") {
            LabeledContent {
                Text(store.totalBytes.formattedFileSize)
                    .foregroundStyle(.secondary)
            } label: {
                MoreRowLabel(title: "已用空间", systemImage: "internaldrive", tint: .orange)
            }

            LabeledContent {
                Text("\(store.items.filter { !$0.isDirectory }.count)")
                    .foregroundStyle(.secondary)
            } label: {
                MoreRowLabel(title: "资料库项目", systemImage: "tray.full", tint: .green)
            }

            LabeledContent {
                Text("\(store.favorites.count)")
                    .foregroundStyle(.secondary)
            } label: {
                MoreRowLabel(title: "收藏项目", systemImage: "star", tint: .yellow)
            }
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        #if os(iOS)
        Section("权限") {
            Button(action: openSystemSettings) {
                MoreButtonRow(
                    title: "系统音乐库",
                    subtitle: AppLocalization.string("打开系统设置"),
                    systemImage: "music.note.house",
                    tint: .pink,
                    value: musicAuthorizationTitle
                )
            }
            .buttonStyle(.plain)
        }
        #endif
    }

    private var legalSection: some View {
        Section("法律信息") {
            Button(action: openPrivacyPolicy) {
                MoreButtonRow(
                    title: "隐私协议",
                    systemImage: "hand.raised",
                    tint: .purple
                )
            }
            .buttonStyle(.plain)

            Button(action: openTermsOfService) {
                MoreButtonRow(
                    title: "用户协议",
                    systemImage: "doc.text",
                    tint: .teal
                )
            }
            .buttonStyle(.plain)
        }
    }

    #if os(iOS)
    private var musicAuthorizationTitle: String {
        switch musicAuthorization {
        case .authorized: AppLocalization.string("已允许")
        case .denied: AppLocalization.string("已拒绝")
        case .restricted: AppLocalization.string("受限制")
        case .notDetermined: AppLocalization.string("未询问")
        @unknown default: AppLocalization.string("未知")
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
    #endif

    private func openPrivacyPolicy() {
        openURL("https://lordly-tech.github.io/yubing/privacy")
    }

    private func openTermsOfService() {
        openURL("https://lordly-tech.github.io/yubing/terms")
    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        #if os(iOS)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        root.present(SFSafariViewController(url: url), animated: true)
        #elseif os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    private var languageSummary: String {
        if selectedLanguage == .system {
            return "\(AppLocalization.string("当前使用"))：\(selectedLanguage.resolvedName)"
        }
        return selectedLanguage.resolvedName
    }
}

private struct MoreRowLabel: View {
    let title: LocalizedStringKey
    var subtitle: String? = nil
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            MoreIcon(systemImage: systemImage, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, subtitle == nil ? 2 : 4)
    }
}

private struct MoreButtonRow: View {
    let title: LocalizedStringKey
    var subtitle: String? = nil
    let systemImage: String
    let tint: Color
    var value: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            MoreIcon(systemImage: systemImage, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 10)
            if let value {
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, subtitle == nil ? 2 : 4)
    }
}

private struct MoreIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}
