import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let playerBackgroundBlur = "yubing.playerBackgroundBlur"
        static let playerBackgroundSaturation = "yubing.playerBackgroundSaturation"
        static let shrinksPausedArtwork = "yubing.shrinksPausedArtwork"
        static let lyricsFontSize = "yubing.lyricsFontSize"
        static let lyricsCurrentLineScale = "yubing.lyricsCurrentLineScale"
        static let lyricsLineSpacing = "yubing.lyricsLineSpacing"
        static let lyricsBlurIntensity = "yubing.lyricsBlurIntensity"
        static let lyricsDistanceBlurScale = "yubing.lyricsDistanceBlurScale"
        static let lyricsHiddenInterfaceBlurScale = "yubing.lyricsHiddenInterfaceBlurScale"
        static let lyricsDimAmount = "yubing.lyricsDimAmount"
        static let lyricsTapToSeek = "yubing.lyricsTapToSeek"
        static let lyricsWordByWord = "yubing.lyricsWordByWord"
        static let lyricsPseudoWordByWord = "yubing.lyricsPseudoWordByWord"
        static let lyricsGlowEnabled = "yubing.lyricsGlowEnabled"
        static let lyricsGlowIntensity = "yubing.lyricsGlowIntensity"
        static let lyricsTranslationEnabled = "yubing.lyricsTranslationEnabled"
        static let lyricsTranslationFontScale = "yubing.lyricsTranslationFontScale"
        static let lyricsTranslationOpacity = "yubing.lyricsTranslationOpacity"
        static let lyricsAutoFollow = "yubing.lyricsAutoFollow"
        static let lyricsFollowDelay = "yubing.lyricsFollowDelay"
        static let lyricsFocusPosition = "yubing.lyricsFocusPosition"
        static let lyricsFocusCascadeDelay = "yubing.lyricsFocusCascadeDelay"
        static let lyricsFocusCascadeBounceEnabled = "yubing.lyricsFocusCascadeBounceEnabled"
        static let lyricsFocusColorLeadTime = "yubing.lyricsFocusColorLeadTime"
        static let lyricsAdvanceTime = "yubing.lyricsAdvanceTime"
    }

    private let defaults: UserDefaults

    var playerBackgroundBlur: Double {
        didSet { defaults.set(playerBackgroundBlur, forKey: Key.playerBackgroundBlur) }
    }

    var playerBackgroundSaturation: Double {
        didSet { defaults.set(playerBackgroundSaturation, forKey: Key.playerBackgroundSaturation) }
    }

    var shrinksPausedArtwork: Bool {
        didSet { defaults.set(shrinksPausedArtwork, forKey: Key.shrinksPausedArtwork) }
    }

    var lyricsFontSize: Double {
        didSet { defaults.set(lyricsFontSize, forKey: Key.lyricsFontSize) }
    }

    var lyricsCurrentLineScale: Double {
        didSet { defaults.set(lyricsCurrentLineScale, forKey: Key.lyricsCurrentLineScale) }
    }

    var lyricsLineSpacing: Double {
        didSet { defaults.set(lyricsLineSpacing, forKey: Key.lyricsLineSpacing) }
    }

    var lyricsBlurIntensity: Double {
        didSet { defaults.set(lyricsBlurIntensity, forKey: Key.lyricsBlurIntensity) }
    }

    var lyricsDistanceBlurScale: Double {
        didSet { defaults.set(lyricsDistanceBlurScale, forKey: Key.lyricsDistanceBlurScale) }
    }

    var lyricsHiddenInterfaceBlurScale: Double {
        didSet {
            defaults.set(
                lyricsHiddenInterfaceBlurScale,
                forKey: Key.lyricsHiddenInterfaceBlurScale
            )
        }
    }

    var lyricsDimAmount: Double {
        didSet { defaults.set(lyricsDimAmount, forKey: Key.lyricsDimAmount) }
    }

    var lyricsTapToSeek: Bool {
        didSet { defaults.set(lyricsTapToSeek, forKey: Key.lyricsTapToSeek) }
    }

    var lyricsWordByWord: Bool {
        didSet { defaults.set(lyricsWordByWord, forKey: Key.lyricsWordByWord) }
    }

    var lyricsPseudoWordByWord: Bool {
        didSet { defaults.set(lyricsPseudoWordByWord, forKey: Key.lyricsPseudoWordByWord) }
    }

    var lyricsGlowEnabled: Bool {
        didSet { defaults.set(lyricsGlowEnabled, forKey: Key.lyricsGlowEnabled) }
    }

    var lyricsGlowIntensity: Double {
        didSet { defaults.set(lyricsGlowIntensity, forKey: Key.lyricsGlowIntensity) }
    }

    var lyricsTranslationEnabled: Bool {
        didSet { defaults.set(lyricsTranslationEnabled, forKey: Key.lyricsTranslationEnabled) }
    }

    var lyricsTranslationFontScale: Double {
        didSet { defaults.set(lyricsTranslationFontScale, forKey: Key.lyricsTranslationFontScale) }
    }

    var lyricsTranslationOpacity: Double {
        didSet { defaults.set(lyricsTranslationOpacity, forKey: Key.lyricsTranslationOpacity) }
    }

    var lyricsAutoFollow: Bool {
        didSet { defaults.set(lyricsAutoFollow, forKey: Key.lyricsAutoFollow) }
    }

    var lyricsFollowDelay: Double {
        didSet { defaults.set(lyricsFollowDelay, forKey: Key.lyricsFollowDelay) }
    }

    var lyricsFocusPosition: Double {
        didSet { defaults.set(lyricsFocusPosition, forKey: Key.lyricsFocusPosition) }
    }

    var lyricsFocusCascadeDelay: Double {
        didSet { defaults.set(lyricsFocusCascadeDelay, forKey: Key.lyricsFocusCascadeDelay) }
    }

    var lyricsFocusCascadeBounceEnabled: Bool {
        didSet {
            defaults.set(
                lyricsFocusCascadeBounceEnabled,
                forKey: Key.lyricsFocusCascadeBounceEnabled
            )
        }
    }

    var lyricsFocusColorLeadTime: Double {
        didSet { defaults.set(lyricsFocusColorLeadTime, forKey: Key.lyricsFocusColorLeadTime) }
    }

    var lyricsAdvanceTime: Double {
        didSet { defaults.set(lyricsAdvanceTime, forKey: Key.lyricsAdvanceTime) }
    }

    static let lyricsFocusPositionRange: ClosedRange<Double> = 0...1
    static let lyricsCurrentLineScaleRange: ClosedRange<Double> = 1.0...2.0
    static let lyricsFocusColorLeadTimeRange: ClosedRange<Double> = 0...1
    static let lyricsFocusCascadeDelayRange: ClosedRange<Double> = 0...0.05
    static let lyricsGlowIntensityRange: ClosedRange<Double> = 0...2
    static let lyricsFontSizeRange: ClosedRange<Double> = 20...36
    static let lyricsLineSpacingRange: ClosedRange<Double> = 12...40

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        playerBackgroundBlur = Self.double(defaults, Key.playerBackgroundBlur, 90)
        playerBackgroundSaturation = Self.double(defaults, Key.playerBackgroundSaturation, 0.82)
        shrinksPausedArtwork = Self.bool(defaults, Key.shrinksPausedArtwork, true)
        lyricsFontSize = Self.double(defaults, Key.lyricsFontSize, 25)
        lyricsCurrentLineScale = Self.double(defaults, Key.lyricsCurrentLineScale, 1.2)
        lyricsLineSpacing = Self.double(defaults, Key.lyricsLineSpacing, 27)
        lyricsBlurIntensity = Self.double(defaults, Key.lyricsBlurIntensity, 0.8)
        lyricsDistanceBlurScale = Self.double(defaults, Key.lyricsDistanceBlurScale, 0.65)
        lyricsHiddenInterfaceBlurScale = Self.double(
            defaults,
            Key.lyricsHiddenInterfaceBlurScale,
            0.6
        )
        lyricsDimAmount = Self.double(defaults, Key.lyricsDimAmount, 1)
        lyricsTapToSeek = Self.bool(defaults, Key.lyricsTapToSeek, true)
        lyricsWordByWord = Self.bool(defaults, Key.lyricsWordByWord, true)
        lyricsPseudoWordByWord = Self.bool(defaults, Key.lyricsPseudoWordByWord, true)
        lyricsGlowEnabled = Self.bool(defaults, Key.lyricsGlowEnabled, true)
        lyricsGlowIntensity = Self.double(defaults, Key.lyricsGlowIntensity, 1)
        lyricsTranslationEnabled = Self.bool(defaults, Key.lyricsTranslationEnabled, true)
        lyricsTranslationFontScale = Self.double(defaults, Key.lyricsTranslationFontScale, 0.62)
        lyricsTranslationOpacity = Self.double(defaults, Key.lyricsTranslationOpacity, 0.66)
        lyricsAutoFollow = Self.bool(defaults, Key.lyricsAutoFollow, true)
        lyricsFollowDelay = Self.double(defaults, Key.lyricsFollowDelay, 3)
        lyricsFocusPosition = Self.double(defaults, Key.lyricsFocusPosition, 0.28)
        lyricsFocusCascadeDelay = Self.double(defaults, Key.lyricsFocusCascadeDelay, 0.025)
        lyricsFocusCascadeBounceEnabled = Self.bool(
            defaults,
            Key.lyricsFocusCascadeBounceEnabled,
            true
        )
        lyricsFocusColorLeadTime = Self.double(defaults, Key.lyricsFocusColorLeadTime, 0.06)
        lyricsAdvanceTime = max(Self.double(defaults, Key.lyricsAdvanceTime, 0.55), 0.55)
    }

    func resetLyricsEffects() {
        lyricsWordByWord = true
        lyricsPseudoWordByWord = true
        lyricsGlowEnabled = true
        lyricsGlowIntensity = 1
        lyricsFontSize = 25
        lyricsLineSpacing = 27
        lyricsCurrentLineScale = 1.2
        lyricsFocusCascadeDelay = 0.025
        lyricsFocusCascadeBounceEnabled = true
        lyricsTranslationEnabled = true
        lyricsTapToSeek = true
    }

    private static func double(
        _ defaults: UserDefaults,
        _ key: String,
        _ fallback: Double
    ) -> Double {
        defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
    }

    private static func bool(
        _ defaults: UserDefaults,
        _ key: String,
        _ fallback: Bool
    ) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }
}
