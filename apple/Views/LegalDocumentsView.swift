import SwiftUI

enum LegalDocument: String, Identifiable {
    case privacyPolicy
    case termsOfService

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacyPolicy: "隐私协议"
        case .termsOfService: "用户协议"
        }
    }

    var summary: String {
        switch self {
        case .privacyPolicy:
            "说明鱼饼如何在本地处理你导入的内容、权限和同步数据。"
        case .termsOfService:
            "说明鱼饼的使用规则、责任边界和内容归属。"
        }
    }

    var effectiveDate: String { "2026 年 7 月 23 日" }
    var updatedDate: String { "2026 年 7 月 23 日" }

    var sections: [LegalDocumentSection] {
        switch self {
        case .privacyPolicy:
            return [
                LegalDocumentSection(
                    title: "适用范围",
                    paragraphs: [
                        "本隐私协议适用于鱼饼 YuBing 的 iPhone、iPad、Mac 和 Apple Watch 版本。我们会按照本协议及适用法律处理你在使用本应用时产生或导入的数据。",
                        "当前版本主要在你的设备本地运行，不要求你注册账号，也不以广告追踪或跨应用画像为目的收集信息。"
                    ]
                ),
                LegalDocumentSection(
                    title: "我们处理的信息",
                    paragraphs: [
                        "本应用主要处理你主动导入、创建或生成的内容，这些内容只用于实现资料库、阅读、播放和同步等功能。"
                    ],
                    bullets: [
                        "你导入或创建的文件、照片、视频、音频、书籍、封面、歌词、书签、收藏、最近打开记录和阅读进度。",
                        "你在播放、阅读和管理文件时产生的本地状态，例如播放进度、播放速度、循环或随机设置、睡眠定时、封面缓存和阅读统计。",
                        "当你使用系统音乐库、相册、文件选择器或相机扫描等功能时，你主动授权并选中的内容及其必要元数据。"
                    ]
                ),
                LegalDocumentSection(
                    title: "权限说明",
                    bullets: [
                        "相机：仅在你使用扫描文档或二维码等功能时调用。",
                        "照片：仅用于从相册选择封面或导入照片、视频。",
                        "媒体库：仅用于扫描和导入本机音乐。",
                        "本地网络：仅用于在同一 Wi-Fi 下接收文件。",
                        "Apple Watch 同步：仅用于在你的 iPhone 与 Apple Watch 之间传输内容和阅读状态。"
                    ]
                ),
                LegalDocumentSection(
                    title: "本地存储与共享",
                    paragraphs: [
                        "你导入到应用中的内容会保存在本机资料库或应用容器中，收藏、最近打开、阅读记录、封面缓存和偏好设置也会本地保存。",
                        "当你使用同一 Wi-Fi 传输或 Apple Watch 同步时，相关文件会在你的设备之间流转，不会主动上传到我们自有服务器。"
                    ],
                    bullets: [
                        "系统备份、iCloud 备份或你手动分享文件的行为由你自己的设备设置决定。"
                    ]
                ),
                LegalDocumentSection(
                    title: "在线音乐服务",
                    paragraphs: [
                        "当你打开音乐发现、在线歌单或专辑，或播放在线曲目时，应用会直接向网易云音乐及其图片服务发送只读请求。请求可能包含歌单、专辑或歌曲标识、内容分类以及网络服务正常工作所需的设备和网络信息。",
                        "这些请求不会经过鱼饼自有服务器；第三方如何处理请求与日志由其服务条款和隐私规则决定。你不使用在线音乐功能时，鱼饼不会为该功能主动发起内容请求。"
                    ]
                ),
                LegalDocumentSection(
                    title: "信息安全",
                    paragraphs: [
                        "我们会尽力使用系统提供的安全机制保护你的数据，但任何电子存储和传输方式都无法做到绝对安全。请妥善保管设备和备份。"
                    ]
                ),
                LegalDocumentSection(
                    title: "你的权利",
                    bullets: [
                        "你可以在系统设置中随时关闭相应权限。",
                        "你可以在应用内删除、移动或导出你的本地文件。",
                        "如果你不再使用本应用，也可以通过删除应用和相关备份来清除本机数据。"
                    ]
                ),
                LegalDocumentSection(
                    title: "变更与联系",
                    paragraphs: [
                        "我们可能会根据功能变化或法律要求更新本协议。更新后会在应用内展示。",
                        "如有问题，请通过 App Store 开发者页面联系。"
                    ]
                )
            ]

        case .termsOfService:
            return [
                LegalDocumentSection(
                    title: "接受协议",
                    paragraphs: [
                        "使用鱼饼 YuBing 即表示你已阅读并同意本协议。若你不同意，请停止使用本应用。"
                    ]
                ),
                LegalDocumentSection(
                    title: "服务说明",
                    paragraphs: [
                        "本应用提供本地文件管理、阅读、音乐播放、在线音乐发现、图片/视频查看、局域网传输和 Apple Watch 同步等功能。",
                        "不同设备、系统版本和文件格式的可用性可能不同，部分功能依赖系统权限、网络环境、第三方音乐服务、本地文件格式或 Apple Watch 配对状态。"
                    ],
                    bullets: [
                        "本应用当前不提供账号体系或强制云端同步服务。",
                        "本应用的部分能力依赖 Apple 提供的系统服务和你自己的设备设置。"
                    ]
                ),
                LegalDocumentSection(
                    title: "用户责任",
                    bullets: [
                        "你应确保导入、分享、传输和播放的内容拥有合法来源或相关授权。",
                        "你不得使用本应用存储、传播或处理违法、侵权、恶意、欺诈或其他被禁止的内容。",
                        "你不得利用本应用攻击第三方服务、绕过音乐内容的付费或版权限制，或实施其他违法行为。"
                    ]
                ),
                LegalDocumentSection(
                    title: "内容与数据",
                    paragraphs: [
                        "你对自己的内容和备份负责。应用中的收藏、阅读进度、播放记录和本地设置属于本地数据，因误删、设备故障、系统异常或第三方应用行为造成的损失请自行备份。"
                    ]
                ),
                LegalDocumentSection(
                    title: "知识产权",
                    paragraphs: [
                        "鱼饼源代码依照 GNU General Public License version 3 发布，你可以在该许可证范围内使用、研究、修改和分发。MeloX 及其他第三方代码、资源和品牌仍受各自许可证与权利声明约束。你保留自己导入内容的权利。"
                    ]
                ),
                LegalDocumentSection(
                    title: "免责声明",
                    bullets: [
                        "本应用按现状提供，不保证完全兼容所有文件、编码、字幕、封面或播放环境。",
                        "因网络、系统、权限、苹果服务变更或设备硬件问题导致的中断、延迟或数据损失，开发者在法律允许范围内不承担超出强制法律规定的责任。"
                    ]
                ),
                LegalDocumentSection(
                    title: "协议变更与终止",
                    paragraphs: [
                        "我们可能会随版本更新调整功能和条款。若你继续使用更新后的版本，即视为接受相应调整。",
                        "对于严重违反本协议或适用法律的行为，开发者可限制相关功能或停止提供部分服务。"
                    ]
                ),
                LegalDocumentSection(
                    title: "联系",
                    paragraphs: [
                        "如对本协议有疑问，请通过 App Store 开发者页面联系。"
                    ]
                )
            ]
        }
    }
}

struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                ForEach(Array(document.sections.enumerated()), id: \.offset) { index, section in
                    if index > 0 {
                        Divider()
                    }
                    LegalDocumentSectionView(section: section)
                }

                Divider()

                Text("如有疑问，请通过 App Store 开发者页面联系我们。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .textSelection(.enabled)
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(document.title)
                .font(.largeTitle.weight(.bold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(document.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Label("生效日期 \(document.effectiveDate)", systemImage: "calendar")
                Label("更新日期 \(document.updatedDate)", systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct LegalDocumentSectionView: View {
    let section: LegalDocumentSection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.title3.weight(.semibold))

            ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !section.bullets.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(section.bullets.enumerated()), id: \.offset) { _, bullet in
                        LegalBulletRow(text: bullet)
                    }
                }
                .padding(.top, 2)
            }
        }
    }
}

private struct LegalBulletRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("•")
                .font(.body.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 12, alignment: .leading)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LegalDocumentSection {
    let title: String
    let paragraphs: [String]
    let bullets: [String]

    init(title: String, paragraphs: [String] = [], bullets: [String] = []) {
        self.title = title
        self.paragraphs = paragraphs
        self.bullets = bullets
    }
}
