import SwiftUI

struct LyricsEffectsSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var showsResetConfirmation = false

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker("歌词样式", selection: $settings.lyricsStyle) {
                    ForEach(LyricsStyle.allCases) { style in
                        Label(style.title, systemImage: style.systemImage)
                            .tag(style)
                    }
                }

                if settings.lyricsStyle == .textPV {
                    NavigationLink {
                        TextPVSettingsView()
                    } label: {
                        LabeledContent("文字PV设置", value: settings.textPV.style.title)
                    }
                }

                NavigationLink {
                    SkylineLyricsSettingsView()
                } label: {
                    Label("全屏天际歌词", systemImage: "arrow.up.left.and.arrow.down.right")
                }
            } header: {
                Text("歌词样式")
            } footer: {
                Text(settings.lyricsStyle.description)
            }

            Section {
                Toggle(isOn: $settings.lyricsWordByWord) {
                    LyricsSettingRowLabel(
                        title: "逐字动效",
                        detail: "歌词自带逐字时间轴时，按字逐个点亮。"
                    )
                }

                Toggle(isOn: $settings.lyricsPseudoWordByWord) {
                    LyricsSettingRowLabel(
                        title: "模拟逐字",
                        detail: "歌词只有整句时间时，按字数均分模拟逐字进度。"
                    )
                }
            } header: {
                Text("逐字")
            } footer: {
                Text("逐字动效只对本身带逐字时间的歌词生效；其余歌词由模拟逐字接管。两项都关闭时歌词按整句切换。")
            }

            Section {
                Toggle(isOn: $settings.lyricsGlowEnabled) {
                    LyricsSettingRowLabel(
                        title: "逐字辉光",
                        detail: "正在唱到的字带柔光。"
                    )
                }

                if settings.lyricsGlowEnabled {
                    LyricsValueSlider(
                        title: "辉光强度",
                        value: $settings.lyricsGlowIntensity,
                        range: AppSettings.lyricsGlowIntensityRange,
                        step: 0.05,
                        valueText: percentText(settings.lyricsGlowIntensity)
                    )
                }
            } header: {
                Text("辉光")
            }

            Section {
                LyricsValueSlider(
                    title: "每行错峰延迟",
                    value: $settings.lyricsFocusCascadeDelay,
                    range: AppSettings.lyricsFocusCascadeDelayRange,
                    step: 0.005,
                    valueText: millisecondText(settings.lyricsFocusCascadeDelay)
                )

                Toggle(isOn: $settings.lyricsFocusCascadeBounceEnabled) {
                    LyricsSettingRowLabel(
                        title: "错峰轻微回弹",
                        detail: "整段歌词依次移动时带轻微弹性。"
                    )
                }

                LyricsValueSlider(
                    title: "焦点颜色提前",
                    value: $settings.lyricsFocusColorLeadTime,
                    range: AppSettings.lyricsFocusColorLeadTimeRange,
                    step: 0.005,
                    valueText: millisecondText(settings.lyricsFocusColorLeadTime)
                )
            } header: {
                Text("错峰")
            } footer: {
                Text("错峰延迟让每一行依次跟上，数值越大层次越明显。")
            }

            Section {
                LyricsValueSlider(
                    title: "字体大小",
                    value: $settings.lyricsFontSize,
                    range: AppSettings.lyricsFontSizeRange,
                    step: 1,
                    valueText: "\(Int(settings.lyricsFontSize)) \(AppLocalization.string("磅"))"
                )

                LyricsValueSlider(
                    title: "当前歌词放大",
                    value: $settings.lyricsCurrentLineScale,
                    range: AppSettings.lyricsCurrentLineScaleRange,
                    step: 0.01,
                    valueText: percentText(settings.lyricsCurrentLineScale)
                )

                LyricsValueSlider(
                    title: "歌词行距",
                    value: $settings.lyricsLineSpacing,
                    range: AppSettings.lyricsLineSpacingRange,
                    step: 1,
                    valueText: "\(Int(settings.lyricsLineSpacing))"
                )
            } header: {
                Text("排版")
            }

            Section {
                Toggle(isOn: $settings.lyricsTapToSeek) {
                    LyricsSettingRowLabel(
                        title: "点按歌词跳转",
                        detail: "轻点某一行直接跳到该句。"
                    )
                }

                Toggle(isOn: $settings.lyricsTranslationEnabled) {
                    LyricsSettingRowLabel(
                        title: "显示翻译",
                        detail: "有翻译歌词时在原文下方显示。"
                    )
                }
            } header: {
                Text("交互")
            }

            Section {
                Button(role: .destructive) {
                    showsResetConfirmation = true
                } label: {
                    Text("恢复默认歌词动效")
                }
            }
        }
        .navigationTitle("歌词动效")
        .alert("恢复默认歌词动效", isPresented: $showsResetConfirmation) {
            Button("取消", role: .cancel) {}
            Button("恢复", role: .destructive) {
                settings.resetLyricsEffects()
            }
        } message: {
            Text("逐字、辉光、错峰与排版都会回到初始值。")
        }
    }

    private func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func millisecondText(_ value: Double) -> String {
        "\(Int((value * 1_000).rounded())) \(AppLocalization.string("毫秒"))"
    }
}

private struct LyricsSettingRowLabel: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(AppLocalization.string(title))
            Text(AppLocalization.string(detail))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LyricsValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(AppLocalization.string(title))
                Spacer()
                Text(valueText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
                .accessibilityLabel(AppLocalization.string(title))
                .accessibilityValue(valueText)
        }
    }
}
