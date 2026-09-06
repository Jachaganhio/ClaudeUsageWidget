import SwiftUI

extension UsageMetric {
    var color: Color {
        guard let percent else { return .secondary }
        switch percent {
        case ..<50: return .green
        case ..<75: return .yellow
        case ..<90: return .orange
        default: return .red
        }
    }
}

struct UsageRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let metric: UsageMetric
    var showReset = true
    var compact = false

    private var percentageColor: Color {
        guard colorScheme == .light, let percent = metric.percent else { return metric.color }
        switch percent {
        case ..<50: return Color(red: 0.08, green: 0.43, blue: 0.21)
        case ..<75: return Color(red: 0.55, green: 0.40, blue: 0.0)
        case ..<90: return Color(red: 0.70, green: 0.30, blue: 0.02)
        default: return Color(red: 0.70, green: 0.15, blue: 0.12)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? (showReset ? 2 : 1) : 3) {
            HStack(spacing: 4) {
                Text(metric.title)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text(metric.percentageText)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(percentageColor)
            }
            .font(.system(size: compact ? (showReset ? 10 : 9) : 11))
            GeometryReader { geometry in
                Capsule().fill(.primary.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule().fill(metric.color.gradient)
                            .frame(width: geometry.size.width * metric.fraction)
                    }
            }
            .frame(height: compact ? (showReset ? 3 : 2) : 5)
            if showReset {
                if let reset = metric.resetsAt {
                    HStack(spacing: 3) {
                        Text("Resets")
                        Text(reset, style: .relative)
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                } else if metric.percent == nil {
                    Text("Not reported by account")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ProviderUsageView: View {
    let usage: ProviderUsage
    var compact = false
    var showReset = true

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 7) {
            HStack(spacing: 5) {
                Circle().fill(usage.name == "Claude" ? Color.orange : Color.teal)
                    .frame(width: 6, height: 6)
                Text(usage.name).font(.system(size: compact ? (showReset ? 12 : 11) : 14, weight: .bold))
                Spacer(minLength: 0)
            }
            if !usage.isEnabled {
                Text("Disabled").font(.caption).foregroundStyle(.secondary)
            } else if let error = usage.error {
                Text(error)
                    .font(.system(size: compact ? 10 : 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(usage.metrics) { metric in
                    UsageRow(metric: metric, showReset: showReset, compact: compact)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct UsageDashboardView: View {
    let snapshot: UsageSnapshot
    var small = false
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: small ? 3 : 8) {
            if large {
                HStack {
                    Text("AI Usage").font(.headline)
                    Spacer()
                    Text("Used").font(.caption).foregroundStyle(.secondary)
                }
            }
            if small || large {
                ProviderUsageView(usage: snapshot.claude, compact: !large, showReset: large)
                Divider()
                ProviderUsageView(usage: snapshot.codex, compact: !large, showReset: large)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    ProviderUsageView(usage: snapshot.claude, compact: true)
                    Divider()
                    ProviderUsageView(usage: snapshot.codex, compact: true)
                }
            }
            if large {
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    Text("Updated")
                    Text(snapshot.date, style: .time)
                    Spacer()
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            }
        }
    }
}
