import Observation

@MainActor
@Observable
final class AppSettings {
    var playerBackgroundBlur = 90.0
    var playerBackgroundSaturation = 0.82
    var shrinksPausedArtwork = true

    var lyricsFontSize = 25.0
    var lyricsCurrentLineScale = 1.2
    var lyricsLineSpacing = 27.0
    var lyricsBlurIntensity = 0.8
    var lyricsDistanceBlurScale = 0.65
    var lyricsHiddenInterfaceBlurScale = 0.6
    var lyricsDimAmount = 1.0
    var lyricsTapToSeek = true
    var lyricsWordByWord = true
    var lyricsPseudoWordByWord = true
    var lyricsGlowEnabled = true
    var lyricsGlowIntensity = 1.0
    var lyricsTranslationEnabled = true
    var lyricsTranslationFontScale = 0.62
    var lyricsTranslationOpacity = 0.66
    var lyricsAutoFollow = true
    var lyricsFollowDelay = 3.0
    var lyricsFocusPosition = 0.28
    var lyricsFocusCascadeDelay = 0.025
    var lyricsFocusCascadeBounceEnabled = true
    var lyricsFocusColorLeadTime = 0.06
    var lyricsAdvanceTime = 0.2

    static let lyricsFocusPositionRange: ClosedRange<Double> = 0...1
    static let lyricsCurrentLineScaleRange: ClosedRange<Double> = 1.0...2.0
    static let lyricsFocusColorLeadTimeRange: ClosedRange<Double> = 0...1
}
