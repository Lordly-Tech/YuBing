import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum LyricsRefreshRate: Int, CaseIterable, Identifiable {
    case fps30 = 30
    case fps60 = 60
    case fps90 = 90
    case fps120 = 120

    static let defaultValue = LyricsRefreshRate.fps60
    static let lowPowerValue = LyricsRefreshRate.fps30

    var id: Int { rawValue }

    var title: String {
        "\(rawValue) FPS"
    }

    var minimumInterval: TimeInterval {
        1.0 / Double(rawValue)
    }

    /// Highest supported rate that the given display can actually deliver.
    static func supported(forDisplayRefreshRate refreshRate: Int) -> LyricsRefreshRate {
        allCases
            .sorted { $0.rawValue < $1.rawValue }
            .last { $0.rawValue <= refreshRate }
            ?? defaultValue
    }
}

private struct EffectiveLyricsRefreshRateKey: EnvironmentKey {
    static let defaultValue = LyricsRefreshRate.defaultValue
}

extension EnvironmentValues {
    var effectiveLyricsRefreshRate: LyricsRefreshRate {
        get { self[EffectiveLyricsRefreshRateKey.self] }
        set { self[EffectiveLyricsRefreshRateKey.self] = newValue }
    }
}

extension View {
    /// Publishes the frame rate the word-by-word lyrics should animate at.
    ///
    /// Without this the environment keeps its 60 FPS default, which halves the
    /// sweep rate on a 120 Hz display and reads as stutter.
    func resolvedLyricsRefreshRate() -> some View {
        modifier(ResolvedLyricsRefreshRateModifier())
    }
}

private struct ResolvedLyricsRefreshRateModifier: ViewModifier {
    @State private var displayRefreshRate = LyricsRefreshRateProbe.displayRefreshRate()
    @State private var isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var resolvedRate: LyricsRefreshRate {
        isLowPowerModeEnabled
            ? .lowPowerValue
            : .supported(forDisplayRefreshRate: displayRefreshRate)
    }

    func body(content: Content) -> some View {
        content
            .environment(\.effectiveLyricsRefreshRate, resolvedRate)
            .onAppear {
                displayRefreshRate = LyricsRefreshRateProbe.displayRefreshRate()
                isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .NSProcessInfoPowerStateDidChange
                )
            ) { _ in
                isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
    }
}

private enum LyricsRefreshRateProbe {
    @MainActor
    static func displayRefreshRate() -> Int {
        #if os(iOS)
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let rate = scenes
            .map(\.screen.maximumFramesPerSecond)
            .max()
        return rate ?? LyricsRefreshRate.defaultValue.rawValue
        #elseif os(macOS)
        let rate = NSScreen.main?.maximumFramesPerSecond
        return rate ?? LyricsRefreshRate.defaultValue.rawValue
        #else
        return LyricsRefreshRate.defaultValue.rawValue
        #endif
    }
}
