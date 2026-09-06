import WidgetKit
import SwiftUI

struct ClaudeUsageEntry: TimelineEntry {
    let snapshot: UsageSnapshot
    var date: Date { snapshot.date }
    static var placeholder: Self { Self(snapshot: .preview) }
}

struct ClaudeUsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClaudeUsageEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (ClaudeUsageEntry) -> Void) {
        if context.isPreview { completion(.placeholder); return }
        Task { completion(await load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClaudeUsageEntry>) -> Void) {
        Task {
            let entry = await load()
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(300))))
        }
    }

    private func load() async -> ClaudeUsageEntry {
        do {
            let config = try WidgetConfig.load()
            return await ClaudeUsageEntry(snapshot: UsageClient().fetch(config: config))
        } catch {
            let message = UsageError.invalidConfig.localizedDescription
            return ClaudeUsageEntry(snapshot: UsageSnapshot(date: Date(),
                claude: ProviderUsage(name: "Claude", error: message),
                codex: ProviderUsage(name: "Codex", error: message)))
        }
    }
}

struct ClaudeUsageWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: ClaudeUsageEntry

    var body: some View {
        UsageDashboardView(snapshot: entry.snapshot,
                           small: family == .systemSmall, large: family == .systemLarge)
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct ClaudeUsageWidget: Widget {
    // Preserve the kind so existing desktop widgets upgrade in place.
    let kind = "ClaudeUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClaudeUsageProvider()) { entry in
            ClaudeUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude & Codex Usage")
        .description("Claude, Fable and Codex usage limits and reset times. Percentages show usage consumed.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview("Large", as: .systemLarge) {
    ClaudeUsageWidget()
} timeline: {
    ClaudeUsageEntry.placeholder
}

#Preview("Medium", as: .systemMedium) {
    ClaudeUsageWidget()
} timeline: {
    ClaudeUsageEntry.placeholder
}

#Preview("Small", as: .systemSmall) {
    ClaudeUsageWidget()
} timeline: {
    ClaudeUsageEntry.placeholder
}
