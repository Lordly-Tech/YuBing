import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case english = "en"

    var id: String { rawValue }

    var localeIdentifier: String {
        self == .system ? AppLocalization.preferredLanguageIdentifier() : rawValue
    }

    var resolvedName: String {
        AppLocalization.languageName(for: localeIdentifier)
    }

    var label: LocalizedStringKey {
        switch self {
        case .system: "跟随系统"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .english: "English"
        }
    }
}

enum AppLocalization {
    static let preferenceKey = "app.language"
    static let supportedIdentifiers = ["zh-Hans", "zh-Hant", "ja", "ko", "en"]
    /// 与 Localizable.xcstrings 的 sourceLanguage 保持一致。
    static let sourceIdentifier = "zh-Hans"

    static var selectedLanguage: AppLanguage {
        let rawValue = UserDefaults.standard.string(forKey: preferenceKey) ?? AppLanguage.system.rawValue
        return AppLanguage(rawValue: rawValue) ?? .system
    }

    static func preferredLanguageIdentifier() -> String {
        // Locale.preferredLanguages 是「系统偏好 ∩ App 本地化」后的结果，
        // 一旦 bundle 里缺某个本地化，它就会被替换成同语族的其他变体
        // （简体中文被换成 zh-Hant 就是这么来的）。
        // 因此优先读取未经过滤的原始系统列表。
        let rawList = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? []
        return preferredLanguageIdentifier(from: rawList + Locale.preferredLanguages)
    }

    static func preferredLanguageIdentifier(from preferredLanguages: [String]) -> String {
        for preferred in preferredLanguages {
            let subtags = preferred
                .replacingOccurrences(of: "_", with: "-")
                .lowercased()
                .split(separator: "-")
                .map(String.init)
            guard let language = subtags.first else { continue }
            switch language {
            case "zh": return chineseIdentifier(subtags: subtags)
            case "ja": return "ja"
            case "ko": return "ko"
            case "en": return "en"
            default: continue
            }
        }
        return "en"
    }

    private static func chineseIdentifier(subtags: [String]) -> String {
        let scriptSubtags: Set<String> = ["hans", "hant"]
        if let script = subtags.first(where: { scriptSubtags.contains($0) }) {
            return script == "hant" ? "zh-Hant" : "zh-Hans"
        }
        let traditionalRegions: Set<String> = ["tw", "hk", "mo"]
        if subtags.dropFirst().contains(where: { traditionalRegions.contains($0) }) {
            return "zh-Hant"
        }
        return "zh-Hans"
    }

    static func languageName(for identifier: String) -> String {
        switch identifier {
        case "zh-Hans": return "简体中文"
        case "zh-Hant": return "繁體中文"
        case "ja": return "日本語"
        case "ko": return "한국어"
        default: return "English"
        }
    }

    /// 源语言即简体中文，所以回退链是「选定语言 → 简体中文源串 → key 本身」。
    /// 不再回退到英文，避免中文界面出现中英混排。
    static func string(_ key: String) -> String {
        let identifier = selectedLanguage.localeIdentifier
        if identifier == sourceIdentifier {
            return localizedString(key, language: sourceIdentifier) ?? key
        }
        if let value = localizedString(key, language: identifier), value != key {
            return value
        }
        return localizedString(key, language: sourceIdentifier) ?? key
    }

    private static func localizedString(_ key: String, language: String) -> String? {
        guard supportedIdentifiers.contains(language),
              let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return nil }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
