import Foundation
import SwiftUI
import WidgetKit

private struct StatusEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetStatusSnapshot
}

private struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(
            date: .now,
            snapshot: WidgetStatusSnapshot(
                updatedAt: .now,
                remainingPercent: 47,
                resetsAt: Date().addingTimeInterval(4 * 86_400 + 2 * 3_600),
                dailyAllowancePercent: 11,
                planName: "plus",
                isConnected: true,
                activeTaskCount: 2,
                completedTaskCount: 7
            )
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
            completion(StatusEntry(date: .now, snapshot: .placeholder))
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 1.5
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let snapshot = data.flatMap { try? JSONDecoder().decode(WidgetStatusSnapshot.self, from: $0) }
                ?? .placeholder
            completion(StatusEntry(date: .now, snapshot: snapshot))
        }.resume()
    }
}

private struct VibeIslandWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatusEntry

    private let accent = Color(red: 0.30, green: 0.96, blue: 0.67)
    private let purple = Color(red: 0.64, green: 0.40, blue: 1.0)

    var body: some View {
        Group {
            if entry.snapshot.isConnected { statusContent } else { disconnectedContent }
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
            DotMatrixProgressBar(progress: Double(entry.snapshot.remainingPercent) / 100)
        }
        .frame(maxWidth: .infinity, minHeight: family == .systemSmall ? 58 : 62)
    }

    private var quotaRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("剩余额度").sectionLabelStyle()
                DotMatrixText(
                    text: "\(entry.snapshot.remainingPercent)%",
                    dotSize: family == .systemSmall ? 2.35 : 3.0,
                    dotSpacing: family == .systemSmall ? 0.7 : 0.85
                )
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                Text("刷新倒计时").sectionLabelStyle()
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
        .accessibilityLabel("打开 Codex")
    }

    private var summaryCards: some View {
        HStack(spacing: family == .systemSmall ? 5 : 8) {
            dailyCard
            taskCard
        }
        .frame(height: family == .systemSmall ? 54 : 56)
    }

    private var dailyCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("平均每天使用")
                .summaryLabelStyle(size: family == .systemSmall ? 8 : 9)
            HStack(alignment: .bottom, spacing: 4) {
                if let daily = entry.snapshot.dailyAllowancePercent {
                    DotMatrixText(
                        text: "\(daily)%",
                        dotSize: family == .systemSmall ? 1.45 : 1.8,
                        dotSpacing: 0.42,
                        color: accent
                    )
                } else {
                    Text("--")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
                Text("/ 天")
                    .font(.system(size: family == .systemSmall ? 8 : 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.48))
            }
        }
        .summaryCardStyle()
    }

    private var taskCard: some View {
        HStack(spacing: family == .systemSmall ? 6 : 12) {
            taskMetric(title: "进行中", count: entry.snapshot.activeTaskCount, color: purple)
            taskMetric(title: "已完成", count: entry.snapshot.completedTaskCount, color: accent)
        }
        .summaryCardStyle()
    }

    private func taskMetric(title: String, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .summaryLabelStyle(size: family == .systemSmall ? 8 : 9)
            DotMatrixText(
                text: "\(count)",
                dotSize: family == .systemSmall ? 1.45 : 1.8,
                dotSpacing: 0.42,
                color: color
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resetCountdown: String {
        guard let resetsAt = entry.snapshot.resetsAt else { return "等待同步" }
        let seconds = max(0, Int(resetsAt.timeIntervalSince(entry.date)))
        if seconds == 0 { return "即将刷新" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)天 \(hours)小时" }
        if hours > 0 { return "\(hours)小时 \(minutes)分钟" }
        return "\(max(1, minutes))分钟"
    }

    private var disconnectedContent: some View {
        VStack(spacing: 10) {
            Image(systemName: "wave.3.right.circle.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(accent)
            Text("打开 Vibe Island")
                .font(.system(size: 14, weight: .bold))
            Text("启动后自动同步 Codex 状态")
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
        .configurationDisplayName("Vibe Island 状态")
        .description("查看 Codex 剩余额度、刷新时间及进行中和已完成的任务数量。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct VibeIslandWidgetBundle: WidgetBundle {
    var body: some Widget {
        VibeIslandStatusWidget()
    }
}
