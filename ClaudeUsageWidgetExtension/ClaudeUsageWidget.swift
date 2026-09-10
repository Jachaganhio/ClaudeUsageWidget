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
            // Reset boundaries get their own future entries so WidgetKit can switch to a
            // neutral "Refreshing…" state exactly on time, without waiting on a real reload
            // (which macOS may delay well past the reset). See UsageSnapshot.upcomingResets.
            let boundaries = entry.snapshot.upcomingResets
            let entries = [entry] + boundaries.map { ClaudeUsageEntry(snapshot: entry.snapshot.clearingResetsPast($0)) }
            let regularReload = Date().addingTimeInterval(300)
            // Also ask the system to try a real reload shortly after the soonest reset, so
            // fresh percentages replace the stale ones as quickly as the OS allows.
            let nextReload = boundaries.first.map { min(regularReload, $0.addingTimeInterval(5)) } ?? regularReload
            completion(Timeline(entries: entries, policy: .after(nextReload)))
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
