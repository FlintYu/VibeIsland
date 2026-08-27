import Foundation
import SwiftUI
import WidgetKit

private struct StatusEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetStatusSnapshot
    let isAppAvailable: Bool
}

private struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(
            date: .now,
            snapshot: WidgetStatusSnapshot(
                updatedAt: .now,
                remainingPercent: 47,
                resetsAt: Date().addingTimeInterval(2 * 3_600),
                weeklyRemainingPercent: 90,
                weeklyResetsAt: Date().addingTimeInterval(4 * 86_400 + 2 * 3_600),
                planName: "plus",
                isConnected: true,
                activeTaskCount: 2,
                completedTaskCount: 7
            ),
            isAppAvailable: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        context.isPreview ? completion(placeholder(in: context)) : loadSnapshot(completion: completion)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        loadSnapshot { entry in
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(5 * 60))))
        }
    }

    private func loadSnapshot(completion: @escaping (StatusEntry) -> Void) {
        guard let url = URL(
            string: "http://127.0.0.1:\(VibeIslandWidgetConstants.loopbackPort)/snapshot"
        ) else {
            completion(StatusEntry(date: .now, snapshot: .placeholder, isAppAvailable: false))
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 1.5
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let load = WidgetStatusLoad.resolve(responseData: data)
            completion(StatusEntry(
                date: .now,
                snapshot: load.snapshot,
                isAppAvailable: load.isAppAvailable
            ))
        }.resume()
    }
}

private struct VibeIslandWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatusEntry

    private let accent = Color(red: 0.30, green: 0.96, blue: 0.67)
    private let purple = Color(red: 0.64, green: 0.40, blue: 1.0)
    private var language: AppLanguage { entry.snapshot.language }

    private func t(_ chinese: String, _ english: String) -> String {
        language == .chinese ? chinese : english
    }

    var body: some View {
        Group {
            if entry.isAppAvailable { statusContent } else { disconnectedContent }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [.black, Color(red: 0.035, green: 0.055, blue: 0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var statusContent: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 10) {
            quotaPanel
            summaryCards
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, family == .systemSmall ? 11 : 12)
    }

    private var quotaPanel: some View {
        VStack(spacing: 0) {
            quotaRow
            Spacer(minLength: family == .systemSmall ? 7 : 10)
            DotMatrixProgressBar(
                progress: Double(entry.snapshot.remainingPercent) / 100,
                progressAccessibilityLabel: t("5 小时剩余额度进度", "5-hour quota remaining progress")
            )
        }
        .frame(maxWidth: .infinity, minHeight: family == .systemSmall ? 58 : 62)
    }

    private var quotaRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(t("5 小时额度", "5-HOUR LIMIT")).sectionLabelStyle()
                DotMatrixText(
                    text: "\(entry.snapshot.remainingPercent)%",
                    dotSize: family == .systemSmall ? 2.35 : 3.0,
                    dotSpacing: family == .systemSmall ? 0.7 : 0.85
                )
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                Text(t("5 小时刷新", "5-HOUR RESET")).sectionLabelStyle()
                HStack(spacing: family == .systemSmall ? 4 : 6) {
                    openCodexLink
                    Text(resetCountdown)
                        .font(.system(size: family == .systemSmall ? 11 : 15, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
        }
    }

    private var openCodexLink: some View {
        Link(destination: URL(string: "vibeisland://open-codex")!) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.forward.app.fill")
                    .font(.system(size: 8, weight: .bold))
                if family != .systemSmall {
                    Text("Codex")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundStyle(Color.white.opacity(0.82))
            .padding(.horizontal, family == .systemSmall ? 5 : 7)
            .frame(height: 20)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.09))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t("打开 Codex", "Open Codex"))
    }

    private var summaryCards: some View {
        HStack(spacing: family == .systemSmall ? 5 : 8) {
            weeklyCard
            taskCard
        }
        .frame(height: family == .systemSmall ? 54 : 56)
    }

    private var weeklyCard: some View {
        HStack(spacing: family == .systemSmall ? 6 : 12) {
            summaryMetric(
                title: t("剩余额度", "QUOTA LEFT"),
                value: entry.snapshot.weeklyRemainingPercent.map { "\($0)%" } ?? "--",
                color: accent
            )
            summaryMetric(
                title: t("剩余时间", "TIME LEFT"),
                value: weeklyTimeRemaining,
                color: accent
            )
        }
        .summaryCardStyle()
    }

    private var taskCard: some View {
        HStack(spacing: family == .systemSmall ? 6 : 12) {
            summaryMetric(
                title: t("进行中", "ACTIVE"),
                value: "\(entry.snapshot.activeTaskCount)",
                color: purple
            )
            summaryMetric(
                title: t("已完成", "COMPLETED"),
                value: "\(entry.snapshot.completedTaskCount)",
                color: accent
            )
        }
        .summaryCardStyle()
    }

    private func summaryMetric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .summaryLabelStyle(size: family == .systemSmall ? 8 : 9)
            DotMatrixText(
                text: value,
                dotSize: family == .systemSmall ? 1.45 : 1.8,
                dotSpacing: 0.42,
                color: color
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resetCountdown: String {
        countdown(to: entry.snapshot.resetsAt)
    }

    private var weeklyTimeRemaining: String {
        guard let resetsAt = entry.snapshot.weeklyResetsAt else { return "--" }
        let seconds = max(0, Int(resetsAt.timeIntervalSince(entry.date)))
        let days = seconds / 86_400
        var hours = (seconds % 86_400) / 3_600
        if seconds > 0 && days == 0 && hours == 0 {
            hours = 1
        }
        return "\(days)D\(hours)H"
    }

    private func countdown(to resetDate: Date?) -> String {
        guard let resetDate else {
            return t("等待同步", "Waiting to sync")
        }
        let seconds = max(0, Int(resetDate.timeIntervalSince(entry.date)))
        if seconds == 0 { return t("即将刷新", "Refreshing soon") }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if language == .english {
            if days > 0 { return "\(days)d \(hours)h" }
            if hours > 0 { return "\(hours)h \(minutes)m" }
            return "\(max(1, minutes))m"
        }
        if days > 0 { return "\(days)天 \(hours)小时" }
        if hours > 0 { return "\(hours)小时 \(minutes)分钟" }
        return "\(max(1, minutes))分钟"
    }

    private var disconnectedContent: some View {
        VStack(spacing: 10) {
            Image(systemName: "wave.3.right.circle.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(accent)
            Text(t("打开 Vibe Island", "Open Vibe Island"))
                .font(.system(size: 14, weight: .bold))
            Text(t("启动后自动同步 Codex 状态", "Launch the app to sync Codex status"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
    }
}

private extension View {
    func sectionLabelStyle() -> some View {
        font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
    }

    func summaryLabelStyle(size: CGFloat) -> some View {
        font(.system(size: size, weight: .bold, design: .monospaced))
            .tracking(0.3)
            .foregroundStyle(Color.white.opacity(0.48))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    func summaryCardStyle() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.035))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    }
            }
        }
}

private struct VibeIslandStatusWidget: Widget {
    let kind = VibeIslandWidgetConstants.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatusProvider()) { entry in
            VibeIslandWidgetView(entry: entry)
        }
        .configurationDisplayName("Vibe Island Status")
        .description("Codex quota, reset time, and task status / Codex 额度、刷新时间与任务状态。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct VibeIslandWidgetBundle: WidgetBundle {
    var body: some Widget {
        VibeIslandStatusWidget()
    }
}
