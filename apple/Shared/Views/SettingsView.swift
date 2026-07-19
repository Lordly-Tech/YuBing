import SwiftUI
#if os(iOS)
import SafariServices
#endif

struct SettingsView: View {
    var body: some View {
        List {
            aboutSection
            #if !os(watchOS)
            legalSection
            #endif
        }
        .navigationTitle("设置")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var aboutSection: some View {
        Section {
            HStack(spacing: 14) {
                Image("AppIcon")
                    .resizable()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("鱼饼")
                        .font(.headline)
                    Text("版本 \(versionString)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("关于")
        }
    }

    #if !os(watchOS)
    private var legalSection: some View {
        Section {
            Button(action: openPrivacyPolicy) {
                Label("隐私协议", systemImage: "hand.raised")
            }
            .foregroundStyle(.primary)

            Button(action: openTermsOfService) {
                Label("用户协议", systemImage: "doc.text")
            }
            .foregroundStyle(.primary)
        } header: {
            Text("法律信息")
        }
    }

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
        let safari = SFSafariViewController(url: url)
        root.present(safari, animated: true)
        #elseif os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }
    #endif

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
