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

    static var selectedLanguage: AppLanguage {
        let rawValue = UserDefaults.standard.string(forKey: preferenceKey) ?? AppLanguage.system.rawValue
        return AppLanguage(rawValue: rawValue) ?? .system
    }

    static func preferredLanguageIdentifier() -> String {
        preferredLanguageIdentifier(from: Locale.preferredLanguages)
    }

    static func preferredLanguageIdentifier(from preferredLanguages: [String]) -> String {
        for preferred in preferredLanguages {
            let identifier = preferred.lowercased()
            if identifier.hasPrefix("zh") {
                if identifier.contains("hant") ||
                    identifier.contains("-tw") || identifier.contains("_tw") ||
                    identifier.contains("-hk") || identifier.contains("_hk") ||
                    identifier.contains("-mo") || identifier.contains("_mo") {
                    return "zh-Hant"
                }
                return "zh-Hans"
            }
            if identifier.hasPrefix("ja") { return "ja" }
            if identifier.hasPrefix("ko") { return "ko" }
            if identifier.hasPrefix("en") { return "en" }
        }
        return "en"
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

    static func string(_ key: String) -> String {
        let identifier = selectedLanguage.localeIdentifier
        if identifier == "zh-Hans" {
            return localizedString(key, language: identifier) ?? key
        }
        if let value = localizedString(key, language: identifier), value != key || identifier == "zh-Hans" {
            return value
        }
        return localizedString(key, language: "en") ?? key
    }

    private static func localizedString(_ key: String, language: String) -> String? {
        guard supportedIdentifiers.contains(language),
              let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return nil }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
