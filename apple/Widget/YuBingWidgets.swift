import SwiftUI
import WidgetKit

private struct YuBingWidgetEntry: TimelineEntry {
    let date: Date
}

private struct YuBingWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> YuBingWidgetEntry { YuBingWidgetEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (YuBingWidgetEntry) -> Void) {
        completion(YuBingWidgetEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<YuBingWidgetEntry>) -> Void) {
        let entry = YuBingWidgetEntry(date: .now)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1800))))
    }
}

private struct ReadingWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryCircular {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "book.fill")
                    .font(.title2)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("🐟🍪！", systemImage: "book.fill")
                    .font(.headline)
                Spacer(minLength: 0)
                Text("继续阅读")
                    .font(.title2.weight(.bold))
                Text("回到上次阅读位置")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .containerBackground(.background, for: .widget)
        }
    }
}

private struct MusicWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryCircular {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "music.note")
                    .font(.title2)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("鱼饼音乐", systemImage: "waveform")
                    .font(.headline)
                Spacer(minLength: 0)
                Text("打开音乐")
                    .font(.title2.weight(.bold))
                Text("本地无损曲库")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .containerBackground(.background, for: .widget)
        }
    }
}

private struct ReadingWidget: Widget {
    let kind = "YuBingReadingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: YuBingWidgetProvider()) { _ in
            ReadingWidgetView()
                .widgetURL(URL(string: "yubing://reading"))
        }
        .configurationDisplayName("继续阅读")
        .description("从主屏幕或 StandBy 返回上次阅读。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
        .containerBackgroundRemovable()
    }
}

private struct MusicWidget: Widget {
    let kind = "YuBingMusicWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: YuBingWidgetProvider()) { _ in
            MusicWidgetView()
                .widgetURL(URL(string: "yubing://music"))
        }
        .configurationDisplayName("鱼饼音乐")
        .description("快速打开本地音乐曲库。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
        .containerBackgroundRemovable()
    }
}

@main
struct YuBingWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReadingWidget()
        MusicWidget()
    }
}
