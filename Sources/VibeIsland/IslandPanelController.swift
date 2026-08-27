import AppKit
import Combine
import QuartzCore
import SwiftUI
import VibeIslandShared

@MainActor
final class IslandPanelController {
    private let monitor: CodexMonitor
    private let panel: NSPanel
    private let presentationModel = IslandPresentationModel()
    private let settingsModel = IslandSettingsModel()
    private var completionTracker = TaskCompletionTransitionTracker()
    private var taskObserver: AnyCancellable?
    private var settingsObserver: AnyCancellable?
    private var widgetSnapshotObserver: AnyCancellable?
    private var hoverCollapseTask: Task<Void, Never>?
    private var completionGlowTask: Task<Void, Never>?
    private var completionSound: NSSound?
    private let widgetSnapshotServer = WidgetSnapshotServer()

    private let hiddenWidth: CGFloat = 184
    private let baseHiddenSize = NSSize(width: 184, height: 32)
    private let settingsSize = NSSize(width: 410, height: 620)

    private func componentTasks(from tasks: [CodexTaskSnapshot]) -> [CodexTaskSnapshot] {
        guard !settingsModel.includeOrdinaryConversations else { return tasks }
        return tasks.filter { !$0.isOrdinaryConversation }
    }

    private var hiddenSize: NSSize {
        hiddenSize(for: componentTasks(from: monitor.tasks))
    }

    private func hiddenSize(for tasks: [CodexTaskSnapshot]) -> NSSize {
        let hasUnreadCompletedTask = !presentationModel.completedIndicatorIDs
            .subtracting(presentationModel.readCompletedIndicatorIDs)
            .isEmpty
        let showsTaskIndicators = tasks.contains(where: \.isActive)
            || hasUnreadCompletedTask
        return NSSize(width: hiddenWidth, height: showsTaskIndicators ? 42 : 32)
    }

    private var expandedSize: NSSize {
        expandedSize(for: componentTasks(from: monitor.tasks))
    }

    private func expandedSize(for tasks: [CodexTaskSnapshot]) -> NSSize {
        let retainedCompletedCount = tasks.filter {
            $0.state == .completed && presentationModel.completedIndicatorIDs.contains($0.id)
        }.count
        let activeTaskCount = tasks.filter(\.isActive).count
        let visibleRows = max(
            1,
            min(settingsModel.maxVisibleTasks, activeTaskCount + retainedCompletedCount)
        )
        return NSSize(width: 440, height: 284 + CGFloat(visibleRows - 1) * 42)
    }

    private var presentation: IslandPresentation {
        get { presentationModel.value }
        set { presentationModel.value = newValue }
    }

    init(monitor: CodexMonitor) {
        self.monitor = monitor
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: baseHiddenSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configurePanel()
        updateContent()
        observeScreens()
        observeTaskCompletion()
        observeSettings()
        observeWidgetSnapshot()
        widgetSnapshotServer.start()
    }

    func show() {
        // Do not expose the hosting view until its initial hidden layout has been
        // committed. Otherwise AppKit can briefly draw the hosting view at its
        // intrinsic (expanded) size while restoring/relaunching the app.
        presentation = .hidden
        panel.alphaValue = 0
        position(size: hiddenSize, animated: false)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panel.contentView?.layoutSubtreeIfNeeded()
            self.panel.displayIfNeeded()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.10
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.panel.animator().alphaValue = 1
            }
        }
    }

    private func configurePanel() {
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .none
        panel.alphaValue = 0
    }

    private func updateContent() {
        panel.contentView = NSHostingView(
            rootView: IslandView(
                monitor: monitor,
                presentationModel: presentationModel,
                settingsModel: settingsModel,
                toggle: { [weak self] in self?.toggle() },
                openCodex: { [weak self] in self?.openCodex() },
                showSettings: { [weak self] in self?.showSettings() },
                backFromSettings: { [weak self] in self?.backFromSettings() },
                hoverChanged: { [weak self] isInside in self?.handleHover(isInside) },
                previewCompletionSound: { [weak self] in self?.playCompletionSound() },
                previewCompletionGlow: { [weak self] in self?.pulseCompletionGlow() }
            )
        )
    }

    private func toggle() {
        hoverCollapseTask?.cancel()
        if presentation == .expanded {
            presentation = .hidden
        } else {
            markCompletedTasksAsRead()
            presentation = .expanded
        }
        position(size: size(for: presentation), animated: true)
    }

    private func openCodex() {
        guard let applicationURL = CodexInstallation.applicationURL() else {
            NSSound.beep()
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration,
            completionHandler: nil
        )
    }

    private func showSettings() {
        hoverCollapseTask?.cancel()
        presentation = .settings
        position(size: settingsSize, animated: true)
    }

    private func backFromSettings() {
        hoverCollapseTask?.cancel()
        presentation = .expanded
        position(size: expandedSize, animated: true)
    }

    private func handleHover(_ isInside: Bool) {
        hoverCollapseTask?.cancel()
        guard !isInside else { return }

        let delaySeconds: Double
        switch presentation {
        case .expanded: delaySeconds = settingsModel.detailCollapseSeconds
        case .settings: delaySeconds = 3
        case .hidden: return
        }

        hoverCollapseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            guard self.presentation == .expanded || self.presentation == .settings else { return }
            self.presentation = .hidden
            self.position(size: self.hiddenSize, animated: true)
        }
    }

    private func size(for presentation: IslandPresentation) -> NSSize {
        switch presentation {
        case .hidden: return hiddenSize
        case .expanded: return expandedSize
        case .settings: return settingsSize
        }
    }

    private func position(size: NSSize, animated: Bool) {
        guard let screen = screenForIsland() else { return }
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        guard animated else {
            panel.setFrame(frame, display: true)
            return
        }

        let isExpanding = size.height > panel.frame.height || size.width > panel.frame.width
        NSAnimationContext.runAnimationGroup { context in
            context.duration = isExpanding ? 0.36 : 0.24
            context.allowsImplicitAnimation = true
            context.timingFunction = isExpanding
                ? CAMediaTimingFunction(controlPoints: 0.18, 0.92, 0.22, 1.0)
                : CAMediaTimingFunction(controlPoints: 0.65, 0.0, 0.35, 1.0)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func screenForIsland() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func observeScreens() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.position(size: self.size(for: self.presentation), animated: false)
            }
        }
    }

    private func observeTaskCompletion() {
        taskObserver = monitor.$tasks
            .sink { [weak self] tasks in
                guard let self else { return }
                let tasks = componentTasks(from: tasks)
                let activeIDs = Set(tasks.filter(\.isActive).map(\.id))
                presentationModel.completedIndicatorIDs.subtract(activeIDs)
                presentationModel.readCompletedIndicatorIDs.subtract(activeIDs)

                let availableIDs = Set(tasks.map(\.id))
                presentationModel.completedIndicatorIDs.formIntersection(availableIDs)
                presentationModel.readCompletedIndicatorIDs.formIntersection(availableIDs)

                let newlyCompletedTaskIDs = completionTracker.consume(tasks)
                for taskID in newlyCompletedTaskIDs {
                    showCompletedIndicator(for: taskID)
                }
                if !newlyCompletedTaskIDs.isEmpty {
                    playCompletionSound()
                }
                if presentation == .hidden {
                    position(size: hiddenSize(for: tasks), animated: true)
                } else if presentation == .expanded {
                    position(size: expandedSize(for: tasks), animated: true)
                }
            }
    }

    private func observeSettings() {
        settingsObserver = Publishers.CombineLatest3(
            settingsModel.$includeOrdinaryConversations,
            settingsModel.$maxVisibleTasks,
            settingsModel.$language
        )
        .dropFirst()
        .sink { [weak self] _, _, _ in
            guard let self else { return }
            let tasks = componentTasks(from: monitor.tasks)
            _ = completionTracker.consume(tasks)
            if presentation == .hidden {
                position(size: hiddenSize(for: tasks), animated: true)
            } else if presentation == .expanded {
                position(size: expandedSize(for: tasks), animated: true)
            }
        }
    }

    private func observeWidgetSnapshot() {
        widgetSnapshotObserver = Publishers.CombineLatest3(
            Publishers.CombineLatest4(
                monitor.$quota,
                monitor.$tasks,
                monitor.$isConnected,
                settingsModel.$includeOrdinaryConversations
            ),
            Publishers.CombineLatest(
                presentationModel.$completedIndicatorIDs,
                presentationModel.$readCompletedIndicatorIDs
            ),
            settingsModel.$language
        )
        .sink { [weak self] status, completionState, language in
            guard let self else { return }
            let (quota, tasks, isConnected, includeOrdinaryConversations) = status
            let (completedIndicatorIDs, readCompletedIndicatorIDs) = completionState
            let widgetTasks = tasks.filter {
                includeOrdinaryConversations || !$0.isOrdinaryConversation
            }
            let activeTaskCount = widgetTasks.filter(\.isActive).count
            let unreadCompletedIDs = completedIndicatorIDs.subtracting(readCompletedIndicatorIDs)
            let completedTaskCount = widgetTasks.filter {
                $0.state == .completed && unreadCompletedIDs.contains($0.id)
            }.count
            widgetSnapshotServer.update(
                WidgetStatusSnapshot(
                    updatedAt: .now,
                    remainingPercent: quota.remainingPercent,
                    resetsAt: quota.resetsAt,
                    weeklyRemainingPercent: quota.weeklyRemainingPercent,
                    weeklyResetsAt: quota.weeklyResetsAt,
                    planName: quota.planName,
                    isConnected: isConnected,
                    activeTaskCount: activeTaskCount,
                    completedTaskCount: completedTaskCount,
                    language: language
                )
            )
        }
    }

    private func showCompletedIndicator(for taskID: String) {
        presentationModel.completedIndicatorIDs.insert(taskID)
        presentationModel.readCompletedIndicatorIDs.remove(taskID)
        pulseCompletionGlow()
    }

    private func pulseCompletionGlow() {
        completionGlowTask?.cancel()
        presentationModel.completionGlowActive = false
        completionGlowTask = Task { [weak self] in
            guard !Task.isCancelled, let self else { return }
            await Task.yield()
            let style = settingsModel.completionGlowStyle

            switch style {
            case .none:
                break
            case .soft, .aurora:
                presentationModel.completionGlowActive = true
                try? await Task.sleep(nanoseconds: UInt64(style.duration * 1_000_000_000))
            case .pulse:
                for _ in 0..<2 {
                    presentationModel.completionGlowActive = true
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    guard !Task.isCancelled else { return }
                    presentationModel.completionGlowActive = false
                    try? await Task.sleep(nanoseconds: 110_000_000)
                    guard !Task.isCancelled else { return }
                }
                presentationModel.completionGlowActive = true
                try? await Task.sleep(nanoseconds: 260_000_000)
            case .flash:
                for _ in 0..<2 {
                    presentationModel.completionGlowActive = true
                    try? await Task.sleep(nanoseconds: 90_000_000)
                    guard !Task.isCancelled else { return }
                    presentationModel.completionGlowActive = false
                    try? await Task.sleep(nanoseconds: 70_000_000)
                    guard !Task.isCancelled else { return }
                }
            }

            guard !Task.isCancelled else { return }
            self.presentationModel.completionGlowActive = false
            self.completionGlowTask = nil
        }
    }

    private func playCompletionSound() {
        guard settingsModel.completionVolume > 0,
              settingsModel.completionSoundName != IslandSettingsModel.noCompletionSound else { return }
        completionSound?.stop()
        completionSound = NSSound(named: NSSound.Name(settingsModel.completionSoundName))
        completionSound?.volume = Float(settingsModel.completionVolume)
        if completionSound?.play() != true {
            NSSound.beep()
        }
    }

    private func markCompletedTasksAsRead() {
        presentationModel.readCompletedIndicatorIDs.formUnion(
            presentationModel.completedIndicatorIDs
        )
    }
}
