import AppKit
import SwiftUI

enum IslandPresentation: Equatable {
    case hidden
    case expanded
    case settings
}

enum CompletionGlowStyle: String, CaseIterable, Identifiable {
    case none
    case soft
    case pulse
    case aurora
    case flash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "无"
        case .soft: return "柔光"
        case .pulse: return "脉冲"
        case .aurora: return "极光"
        case .flash: return "闪烁"
        }
    }

    var systemImage: String {
        switch self {
        case .none: return "nosign"
        case .soft: return "sun.max.fill"
        case .pulse: return "waveform.path.ecg"
        case .aurora: return "rainbow"
        case .flash: return "bolt.fill"
        }
    }

    var primaryColor: Color {
        switch self {
        case .none: return Color.white.opacity(0.72)
        case .soft, .pulse: return Color(red: 0.24, green: 0.96, blue: 0.58)
        case .aurora: return Color(red: 0.20, green: 0.90, blue: 1.00)
        case .flash: return .white
        }
    }

    var secondaryColor: Color {
        switch self {
        case .none: return Color.white.opacity(0.36)
        case .soft: return Color(red: 0.24, green: 0.96, blue: 0.58)
        case .pulse: return Color(red: 0.62, green: 1.00, blue: 0.30)
        case .aurora: return Color(red: 0.76, green: 0.32, blue: 1.00)
        case .flash: return Color(red: 0.40, green: 0.86, blue: 1.00)
        }
    }

    var duration: Double {
        switch self {
        case .none: return 0
        case .soft: return 0.95
        case .pulse: return 0.72
        case .aurora: return 1.25
        case .flash: return 0.48
        }
    }
}

@MainActor
final class IslandPresentationModel: ObservableObject {
    @Published var value: IslandPresentation = .hidden
    @Published var completedIndicatorIDs = Set<String>()
    @Published var readCompletedIndicatorIDs = Set<String>()
    @Published var completionGlowActive = false
}

@MainActor
final class IslandSettingsModel: ObservableObject {
    @Published private(set) var maxVisibleTasks: Int
    @Published private(set) var detailCollapseSeconds: Double
    @Published private(set) var includeOrdinaryConversations: Bool
    @Published private(set) var completionSoundName: String
    @Published private(set) var completionVolume: Double
    @Published private(set) var completionGlowStyle: CompletionGlowStyle

    static let noCompletionSound = "无"
    static let completionSounds = [noCompletionSound, "Glass", "Hero", "Ping", "Pop", "Purr"]

    private let maxTasksKey = "maxVisibleActiveTasks"
    private let detailDelayKey = "detailCollapseSeconds"
    private let includeConversationsKey = "includeOrdinaryConversations"
    private let completionSoundKey = "completionSoundName"
    private let completionVolumeKey = "completionVolume"
    private let completionGlowStyleKey = "completionGlowStyle"

    init() {
        let stored = UserDefaults.standard.integer(forKey: maxTasksKey)
        maxVisibleTasks = stored == 0 ? 5 : max(1, min(5, stored))

        let detailDelay = UserDefaults.standard.double(forKey: detailDelayKey)
        detailCollapseSeconds = detailDelay == 0 ? 1 : max(0.5, min(10, detailDelay))

        includeOrdinaryConversations = UserDefaults.standard.bool(forKey: includeConversationsKey)

        let storedSound = UserDefaults.standard.string(forKey: completionSoundKey)
        completionSoundName = Self.completionSounds.contains(storedSound ?? "") ? storedSound! : "Glass"

        if UserDefaults.standard.object(forKey: completionVolumeKey) == nil {
            completionVolume = 0.7
        } else {
            completionVolume = max(0, min(1, UserDefaults.standard.double(forKey: completionVolumeKey)))
        }

        let storedGlowStyle = UserDefaults.standard.string(forKey: completionGlowStyleKey)
        completionGlowStyle = CompletionGlowStyle(rawValue: storedGlowStyle ?? "") ?? .soft
    }

    func setMaxVisibleTasks(_ value: Int) {
        let clamped = max(1, min(5, value))
        maxVisibleTasks = clamped
        UserDefaults.standard.set(clamped, forKey: maxTasksKey)
    }

    func setDetailCollapseSeconds(_ value: Double) {
        let clamped = max(0.5, min(10, value))
        detailCollapseSeconds = clamped
        UserDefaults.standard.set(clamped, forKey: detailDelayKey)
    }

    func setIncludeOrdinaryConversations(_ value: Bool) {
        includeOrdinaryConversations = value
        UserDefaults.standard.set(value, forKey: includeConversationsKey)
    }

    func setCompletionSoundName(_ value: String) {
        guard Self.completionSounds.contains(value) else { return }
        completionSoundName = value
        UserDefaults.standard.set(value, forKey: completionSoundKey)
    }

    func setCompletionVolume(_ value: Double) {
        let clamped = max(0, min(1, value))
        completionVolume = clamped
        UserDefaults.standard.set(clamped, forKey: completionVolumeKey)
    }

    func setCompletionGlowStyle(_ value: CompletionGlowStyle) {
        completionGlowStyle = value
        UserDefaults.standard.set(value.rawValue, forKey: completionGlowStyleKey)
    }
}

struct IslandView: View {
    @ObservedObject var monitor: CodexMonitor
    @ObservedObject var presentationModel: IslandPresentationModel
    @ObservedObject var settingsModel: IslandSettingsModel
    let toggle: () -> Void
    let openCodex: () -> Void
    let showSettings: () -> Void
    let backFromSettings: () -> Void
    let hoverChanged: (Bool) -> Void
    let previewCompletionSound: () -> Void
    let previewCompletionGlow: () -> Void

    private var presentation: IslandPresentation { presentationModel.value }
    private var usesExpandedShape: Bool {
        presentation == .expanded || presentation == .settings
    }

    private var retainedCompletedTasks: [CodexTaskSnapshot] {
        componentTasks.filter {
            $0.state == .completed && presentationModel.completedIndicatorIDs.contains($0.id)
        }
    }

    private var componentTasks: [CodexTaskSnapshot] {
        guard !settingsModel.includeOrdinaryConversations else { return monitor.tasks }
        return monitor.tasks.filter { !$0.isOrdinaryConversation }
    }

    private var activeComponentTasks: [CodexTaskSnapshot] {
        componentTasks.filter(\.isActive)
    }

    private var visibleStatusTasks: [CodexTaskSnapshot] {
        let limit = settingsModel.maxVisibleTasks
        let activeTasks = Array(activeComponentTasks.prefix(limit))
        let remainingSlots = max(0, limit - activeTasks.count)
        guard remainingSlots > 0 else { return activeTasks }
        return activeTasks + retainedCompletedTasks.prefix(remainingSlots)
    }

    private var indicatorTasks: [CodexTaskSnapshot] {
        visibleStatusTasks.filter {
            $0.isActive || !presentationModel.readCompletedIndicatorIDs.contains($0.id)
        }
    }

    private var glowStyle: CompletionGlowStyle { settingsModel.completionGlowStyle }

    private var completionOverlay: some ShapeStyle {
        LinearGradient(
            colors: [glowStyle.primaryColor, glowStyle.secondaryColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: usesExpandedShape ? 28 : 18, style: .continuous)
                .fill(Color.black)
                .overlay {
                    RoundedRectangle(cornerRadius: usesExpandedShape ? 28 : 18, style: .continuous)
                        .fill(
                            completionOverlay
                                .opacity(presentationModel.completionGlowActive ? overlayOpacity(for: glowStyle) : 0)
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: usesExpandedShape ? 28 : 18, style: .continuous)
                        .strokeBorder(completionOverlay, lineWidth: 12)
                        .blur(radius: 7)
                        .opacity(presentationModel.completionGlowActive ? 0.72 : 0)
                        .clipShape(
                            RoundedRectangle(cornerRadius: usesExpandedShape ? 28 : 18, style: .continuous)
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: usesExpandedShape ? 28 : 18, style: .continuous)
                        .strokeBorder(
                            presentationModel.completionGlowActive
                                ? glowStyle.primaryColor.opacity(glowStyle == .flash ? 1 : 0.88)
                                : Color.white.opacity(usesExpandedShape ? 0.10 : 0),
                            lineWidth: presentationModel.completionGlowActive ? borderWidth(for: glowStyle) : 1
                        )
                }

            switch presentation {
            case .expanded:
                expandedContent
                    .transition(islandExpansionTransition)
            case .hidden:
                ActiveTaskIndicators(tasks: indicatorTasks)
            case .settings:
                settingsContent
                    .transition(islandExpansionTransition)
            }
        }
        // The window's top-center point stays fixed while AppKit changes its
        // frame. Aligning and clipping here makes the content reveal downward
        // from the physical island instead of scaling around the view's center.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            if presentation == .hidden || presentation == .expanded {
                toggle()
            }
        }
        .onHover(perform: hoverChanged)
        .animation(.spring(response: 0.36, dampingFraction: 0.88), value: presentation)
        .animation(.easeOut(duration: 0.32), value: presentationModel.completionGlowActive)
        .animation(.easeOut(duration: 0.22), value: glowStyle)
        .help("点击展开")
    }

    private var islandExpansionTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.78, anchor: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .top))
        )
    }

    private func overlayOpacity(for style: CompletionGlowStyle) -> Double {
        switch style {
        case .none: return 0
        case .soft: return 0.13
        case .pulse: return 0.22
        case .aurora: return 0.20
        case .flash: return 0.32
        }
    }

    private func borderWidth(for style: CompletionGlowStyle) -> CGFloat {
        switch style {
        case .none: return 1
        case .soft: return 1.5
        case .pulse: return 2.5
        case .aurora: return 2
        case .flash: return 3
        }
    }

    private var expandedContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                statusDot
                Text("\(min(activeComponentTasks.count, settingsModel.maxVisibleTasks)) ACTIVE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Color.white.opacity(0.54))

                Spacer(minLength: 92)

                Button(action: showSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("设置")

                Button {
                    monitor.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("立即刷新")

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("退出 Vibe Island")
            }
            .padding(.horizontal, 22)
            .padding(.top, 17)
            .frame(height: 50, alignment: .top)

            VStack(spacing: 16) {
                quotaSection
                Divider().overlay(Color.white.opacity(0.09))
                taskSection
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
        }
        .foregroundStyle(.white)
    }

    private var quotaSection: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("剩余额度")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    DotMatrixText(
                        text: "\(monitor.quota.remainingPercent)%",
                        dotSize: 3.4,
                        dotSpacing: 0.95
                    )
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("刷新倒计时")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        openCodexButton
                        Text(monitor.quota.compactResetCountdown(relativeTo: monitor.now))
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                    }
                }
            }

            DotMatrixProgressBar(progress: Double(monitor.quota.remainingPercent) / 100)

            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                    Image(systemName: "calendar.day.timeline.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.66))
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text("DAILY BUDGET")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(Color.white.opacity(0.36))
                    Text("平均每天还可用")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.66))
                }
                Spacer()
                if let daily = monitor.quota.averageDailyAllowance(relativeTo: monitor.now) {
                    Text("\(daily)% / 天")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.90))
                } else {
                    Text("等待同步")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(0.035))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    }
            }
        }
    }

    private var openCodexButton: some View {
        Button(action: openCodex) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.forward.app.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("打开 Codex")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Color.white.opacity(0.86))
            .padding(.horizontal, 8)
            .frame(height: 24)
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
        .help("打开或切换到 Codex")
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TASK STATUS")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                if let plan = monitor.quota.planName {
                    Text(plan.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.36))
                }
            }

            if visibleStatusTasks.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: monitor.isConnected ? "checkmark.circle" : "wifi.slash")
                    Text(monitor.errorMessage ?? "当前没有执行中的任务")
                        .lineLimit(1)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            } else {
                ForEach(visibleStatusTasks) { task in
                    HStack(spacing: 9) {
                        Circle()
                            .fill(task.state.color)
                            .frame(width: 7, height: 7)
                            .shadow(color: task.state.color.opacity(0.55), radius: 3)
                        Text(task.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(statusLabel(for: task))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundStyle(task.state.color)
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(task.state.color.opacity(0.10))
                                    .overlay {
                                        Capsule(style: .continuous)
                                            .stroke(task.state.color.opacity(0.24), lineWidth: 1)
                                    }
                            }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(task.state.color.opacity(0.035))
                    }
                }
            }
        }
    }

    private func statusLabel(for task: CodexTaskSnapshot) -> String {
        guard task.state == .completed else { return task.state.matrixLabel }
        return presentationModel.readCompletedIndicatorIDs.contains(task.id) ? "已读" : "已完成"
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("SETTINGS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.0)
                Spacer()
                Button(action: backFromSettings) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                        Text("返回")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(Color.white.opacity(0.88))
                    .padding(.horizontal, 10)
                    .frame(minWidth: 64)
                    .frame(height: 32)
                    .contentShape(Rectangle())
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.white.opacity(0.09))
                            .overlay {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                            }
                    }
                }
                .buttonStyle(.plain)
                .help("返回状态详情")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("同时执行任务显示上限")
                    .font(.system(size: 12, weight: .semibold))
                Text("控制详情列表和刘海下方任务短条的最大数量")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.42))
            }

            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { count in
                    Button {
                        settingsModel.setMaxVisibleTasks(count)
                    } label: {
                        Text("\(count)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .foregroundStyle(
                                settingsModel.maxVisibleTasks == count ? Color.black : Color.white.opacity(0.60)
                            )
                            .background {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(
                                        settingsModel.maxVisibleTasks == count
                                            ? Color(red: 0.24, green: 0.96, blue: 0.58)
                                            : Color.white.opacity(0.10)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                                    }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("将普通对话纳入状态岛")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("开启后，普通对话也会显示并提醒")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.56))
                }
                Spacer(minLength: 8)
                conversationInclusionButton
            }
            .padding(.horizontal, 12)
            .frame(height: 58)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    }
            }

            Text("AUTO COLLAPSE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Color.white.opacity(0.52))

            VStack(spacing: 9) {
                delayInputRow(
                    title: "详情页自动收回",
                    range: "0.5–10 秒",
                    value: Binding(
                        get: { settingsModel.detailCollapseSeconds },
                        set: { settingsModel.setDetailCollapseSeconds($0) }
                    )
                )
            }

            Text("COMPLETION EFFECT")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Color.white.opacity(0.52))

            HStack(spacing: 8) {
                ForEach(CompletionGlowStyle.allCases) { style in
                    glowStyleButton(style)
                }
            }

            Text("COMPLETION SOUND")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Color.white.opacity(0.52))

            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    ForEach(IslandSettingsModel.completionSounds, id: \.self) { sound in
                        soundChoiceButton(sound)
                    }
                }

                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.72))
                    HighContrastVolumeSlider(
                        value: Binding(
                            get: { settingsModel.completionVolume },
                            set: { settingsModel.setCompletionVolume($0) }
                        ),
                        onCommit: previewCompletionSound
                    )
                    .frame(height: 22)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.72))
                    Text("\(Int((settingsModel.completionVolume * 100).rounded()))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(width: 36, alignment: .trailing)
                }
            }
            .padding(12)
            .frame(height: 96)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .foregroundStyle(.white)
    }

    private var conversationInclusionButton: some View {
        let isOn = settingsModel.includeOrdinaryConversations
        return Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                settingsModel.setIncludeOrdinaryConversations(!isOn)
            }
        } label: {
            HStack(spacing: 7) {
                Text(isOn ? "已开启" : "已关闭")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30)
                ZStack {
                    Capsule(style: .continuous)
                        .fill(
                            isOn
                                ? Color(red: 0.24, green: 0.96, blue: 0.58)
                                : Color.white.opacity(0.14)
                        )
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(
                                    isOn
                                        ? Color(red: 0.42, green: 1.00, blue: 0.68)
                                        : Color.white.opacity(0.30),
                                    lineWidth: 1
                                )
                        }
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.42), radius: 2, y: 1)
                        .padding(3)
                        .offset(x: isOn ? 9 : -9)
                }
                .frame(width: 42, height: 24)
            }
            .frame(height: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("将普通对话纳入状态岛")
        .accessibilityValue(isOn ? "已开启" : "已关闭")
        .help(isOn ? "点击关闭普通对话提醒" : "点击开启普通对话提醒")
    }

    private func soundChoiceButton(_ sound: String) -> some View {
        let isSelected = settingsModel.completionSoundName == sound
        return Button {
            settingsModel.setCompletionSoundName(sound)
            previewCompletionSound()
        } label: {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .black))
                }
                Text(sound)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSelected
                            ? Color(red: 0.24, green: 0.96, blue: 0.58).opacity(0.22)
                            : Color.white.opacity(0.08)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                isSelected
                                    ? Color(red: 0.24, green: 0.96, blue: 0.58)
                                    : Color.white.opacity(0.16),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("提示音 \(sound)")
        .accessibilityValue(isSelected ? "已选择" : "未选择")
        .help("选择并试听 \(sound)")
    }

    private func glowStyleButton(_ style: CompletionGlowStyle) -> some View {
        let isSelected = settingsModel.completionGlowStyle == style
        return Button {
            settingsModel.setCompletionGlowStyle(style)
            previewCompletionGlow()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: style.systemImage)
                    .font(.system(size: 12, weight: .bold))
                Text(style.title)
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.86))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(style.primaryColor) : AnyShapeStyle(Color.white.opacity(0.10)))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(isSelected ? style.secondaryColor : Color.white.opacity(0.16), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .help("选择并预览\(style.title)完成光效")
    }

    private func delayInputRow(
        title: String,
        range: String,
        value: Binding<Double>
    ) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Text(range)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.34))
            }
            Spacer()
            TextField(
                "",
                value: value,
                format: .number.precision(.fractionLength(1))
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, 9)
            .frame(width: 64, height: 28)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    }
            }
            Text("S")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.36))
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.025))
        }
    }

    private var statusDot: some View {
        let state = activeComponentTasks.first?.state
            ?? componentTasks.first?.state
            ?? (monitor.isConnected ? .idle : .unknown)
        return ZStack {
            if state == .running {
                Circle().fill(state.color.opacity(0.30)).frame(width: 14, height: 14)
            }
            Circle().fill(state.color).frame(width: 7, height: 7)
        }
    }
}

private struct HighContrastVolumeSlider: NSViewRepresentable {
    @Binding var value: Double
    let onCommit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> VolumeSliderNSView {
        let slider = VolumeSliderNSView()
        slider.value = value
        slider.onValueChanged = { [weak coordinator = context.coordinator] value in
            coordinator?.setValue(value)
        }
        slider.onCommit = { [weak coordinator = context.coordinator] in
            coordinator?.commit()
        }
        return slider
    }

    func updateNSView(_ nsView: VolumeSliderNSView, context: Context) {
        context.coordinator.parent = self
        guard !nsView.isDragging else { return }
        nsView.value = value
    }

    final class Coordinator {
        var parent: HighContrastVolumeSlider

        init(parent: HighContrastVolumeSlider) {
            self.parent = parent
        }

        func setValue(_ value: Double) {
            parent.value = value
        }

        func commit() {
            parent.onCommit()
        }
    }
}

private final class VolumeSliderNSView: NSView {
    var value: Double = 0 {
        didSet {
            value = max(0, min(1, value))
            needsDisplay = true
            setAccessibilityValue(value)
        }
    }
    var onValueChanged: ((Double) -> Void)?
    var onCommit: (() -> Void)?
    private(set) var isDragging = false

    private let knobSize: CGFloat = 18

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("完成提示音音量")
        setAccessibilityMinValue(0)
        setAccessibilityMaxValue(1)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 170, height: 22)
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let trackRect = NSRect(
            x: knobSize / 2,
            y: bounds.midY - 3,
            width: max(1, bounds.width - knobSize),
            height: 6
        )
        NSColor.white.withAlphaComponent(0.24).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: 3, yRadius: 3).fill()

        let progressRect = NSRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: max(0, trackRect.width * value),
            height: trackRect.height
        )
        NSColor(red: 0.24, green: 0.96, blue: 0.58, alpha: 1).setFill()
        NSBezierPath(roundedRect: progressRect, xRadius: 3, yRadius: 3).fill()

        let knobRect = NSRect(
            x: trackRect.minX + trackRect.width * value - knobSize / 2,
            y: bounds.midY - knobSize / 2,
            width: knobSize,
            height: knobSize
        )
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: knobRect).fill()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isDragging = true
        updateValue(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        updateValue(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        updateValue(with: event)
        isDragging = false
        onCommit?()
    }

    override func keyDown(with event: NSEvent) {
        let step = event.modifierFlags.contains(.shift) ? 0.01 : 0.05
        switch event.keyCode {
        case 123, 125:
            setValue(value - step, commit: true)
        case 124, 126:
            setValue(value + step, commit: true)
        default:
            super.keyDown(with: event)
        }
    }

    private func updateValue(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let travel = max(1, bounds.width - knobSize)
        setValue((location.x - knobSize / 2) / travel, commit: false)
    }

    private func setValue(_ newValue: Double, commit: Bool) {
        value = max(0, min(1, newValue))
        onValueChanged?(value)
        if commit { onCommit?() }
    }
}

private struct ActiveTaskIndicators: View {
    let tasks: [CodexTaskSnapshot]

    var body: some View {
        VStack {
            Spacer()
            if !tasks.isEmpty {
                HStack(spacing: 5) {
                    ForEach(tasks) { task in
                        Capsule(style: .continuous)
                            .fill(task.state.color)
                            .frame(width: 20, height: 3)
                            .shadow(color: task.state.color.opacity(0.55), radius: 3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 20)
                .padding(.bottom, 5)
            }
        }
    }
}
