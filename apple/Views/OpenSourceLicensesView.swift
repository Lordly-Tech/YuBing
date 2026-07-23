import SwiftUI

struct OpenSourceLicensesView: View {
    var body: some View {
        List {
            Section("鱼饼") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("GNU General Public License version 3")
                        .font(.headline)
                    Text("鱼饼的源代码可以依照 GPL-3.0 使用、研究、修改和分发。衍生作品与分发行为须遵守许可证的源代码提供和声明保留要求。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                Link(destination: URL(string: "https://github.com/Lordly-Tech/YuBing")!) {
                    Label("查看源代码", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }

            Section("MeloX") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("播放器、横屏布局、歌词动效、发现和专辑体验改编自 youshen2/MeloX。")
                        .font(.subheadline)
                    Text("MeloX 以 GPL-3.0 发布；鱼饼未包含其 EVA 歌词样式和全屏天际歌词。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                Link(destination: URL(string: "https://github.com/youshen2/MeloX")!) {
                    Label("打开 MeloX 项目", systemImage: "arrow.up.right.square")
                }
            }

            Section("上游致谢") {
                OpenSourceLink(
                    title: "BetterLyrics",
                    url: "https://github.com/jayfunc/BetterLyrics"
                )
                OpenSourceLink(
                    title: "Lyricify-Lyrics-Helper",
                    url: "https://github.com/WXRIW/Lyricify-Lyrics-Helper"
                )
                OpenSourceLink(
                    title: "YesPlayMusic",
                    url: "https://github.com/qier222/YesPlayMusic"
                )
            }

            Section("许可证全文") {
                NavigationLink("GNU GPL version 3") {
                    BundledTextDocumentView(
                        title: "GNU GPL version 3",
                        resource: "MeloX-GPL-3.0",
                        fileExtension: "txt"
                    )
                }
                NavigationLink("第三方说明") {
                    BundledTextDocumentView(
                        title: "第三方说明",
                        resource: "ThirdPartyNotices",
                        fileExtension: "md"
                    )
                }
            }
        }
        .navigationTitle("开源与许可证")
    }
}

private struct OpenSourceLink: View {
    let title: String
    let url: String

    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct BundledTextDocumentView: View {
    let title: String
    let resource: String
    let fileExtension: String

    private var content: String {
        guard let url = Bundle.main.url(forResource: resource, withExtension: fileExtension),
              let value = try? String(contentsOf: url, encoding: .utf8) else {
            return "无法读取文档。"
        }
        return value
    }

    var body: some View {
        ScrollView {
            Text(content)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
        }
        .textSelection(.enabled)
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
