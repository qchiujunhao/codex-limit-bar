import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private enum StatusItemPresentation {
        case loading
        case current
        case stale
        case error
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let client = CodexRateLimitClient()
    private let languageSettings = LanguageSettings.shared
    private lazy var popoverController = LimitPopoverController(language: languageSettings.current)
    private var eventMonitor: Any?
    private var currentSnapshot: RateLimitSnapshot?
    private var statusItemPresentation: StatusItemPresentation = .loading
    private let autoShowForTesting = CommandLine.arguments.contains("--show-popover")
    private var didAutoShowForTesting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        configureStatusItem()
        configurePopover()
        configureClient()
        client.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        client.stop()
    }

    private func configureStatusItem() {
        statusItem.autosaveName = "CodexLimitBar.StatusItem"
        statusItem.isVisible = true

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        button.imagePosition = .imageLeft
        button.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        renderStatusItem()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = popoverController

        popoverController.onRefresh = { [weak self] in
            self?.client.refresh()
        }
        popoverController.onQuit = {
            NSApp.terminate(nil)
        }
        popoverController.onLanguageChange = { [weak self] language in
            guard let self else { return }
            self.languageSettings.current = language
            self.popoverController.applyLanguage(language)
            self.renderStatusItem()
        }
    }

    private func configureClient() {
        client.onSnapshotInvalidated = { [weak self] in
            guard let self else { return }
            self.currentSnapshot = nil
            self.statusItemPresentation = .loading
            self.renderStatusItem()
            self.popoverController.clearSnapshot()
        }

        client.onSnapshot = { [weak self] snapshot in
            guard let self else { return }
            self.currentSnapshot = snapshot
            self.statusItemPresentation = .current
            self.renderStatusItem()
            self.popoverController.update(snapshot: snapshot)

            if self.autoShowForTesting, !self.didAutoShowForTesting {
                self.didAutoShowForTesting = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, !self.popover.isShown else { return }
                    self.togglePopover()
                }
            }
        }

        client.onStatus = { [weak self] status in
            guard let self else { return }
            if self.currentSnapshot == nil {
                self.statusItemPresentation = .loading
                self.renderStatusItem()
            }
            self.popoverController.updateStatus(status)
        }

        client.onError = { [weak self] issue in
            guard let self else { return }
            self.statusItemPresentation = self.currentSnapshot == nil ? .error : .stale
            self.renderStatusItem()
            self.popoverController.updateError(issue)
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.popover.performClose(nil)
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func renderStatusItem() {
        guard let button = statusItem.button else { return }
        let language = languageSettings.current
        button.setAccessibilityLabel(Text.statusItemAccessibilityLabel(language))

        switch statusItemPresentation {
        case .loading:
            button.title = " Codex --"
            button.image = makeQuotaBarsImage(fiveHour: nil, weekly: nil, stale: false)
            button.toolTip = Text.statusItemLoadingTooltip(language)
            button.setAccessibilityValue(Text.statusItemLoadingValue(language))
        case .current:
            guard let currentSnapshot else {
                statusItemPresentation = .loading
                renderStatusItem()
                return
            }
            updateStatusItem(snapshot: currentSnapshot, stale: false)
        case .stale:
            guard let currentSnapshot else {
                statusItemPresentation = .error
                renderStatusItem()
                return
            }
            updateStatusItem(snapshot: currentSnapshot, stale: true)
        case .error:
            button.title = Text.statusItemErrorTitle(language)
            button.image = makeQuotaBarsImage(fiveHour: nil, weekly: nil, stale: true)
            button.toolTip = Text.statusItemErrorTooltip(language)
            button.setAccessibilityValue(Text.statusItemErrorValue(language))
        }
    }

    private func updateStatusItem(snapshot: RateLimitSnapshot, stale: Bool) {
        guard let button = statusItem.button else { return }
        let language = languageSettings.current
        let parts = statusParts(snapshot, language: language)
        guard !parts.isEmpty else {
            button.title = Text.statusItemEmptyTitle(language)
            button.image = makeQuotaBarsImage(fiveHour: nil, weekly: nil, stale: stale)
            button.toolTip = Text.statusItemNoWindows(language)
            button.setAccessibilityValue(Text.statusItemNoWindows(language))
            return
        }

        button.title = (stale ? " ! " : " ") + parts.map(\.menuText).joined(separator: "  ")
        button.image = makeQuotaBarsImage(
            fiveHour: snapshot.fiveHourWindow,
            weekly: snapshot.weeklyWindow,
            stale: stale
        )
        let details = parts.map(\.accessibilityText).joined(separator: Text.detailsSeparator(language))
        if stale {
            button.toolTip = Text.staleTooltip(details: details, language: language)
            button.setAccessibilityValue(Text.staleAccessibility(details: details, language: language))
        } else {
            button.toolTip = Text.statusItemTooltip(details: details, language: language)
            button.setAccessibilityValue(details)
        }
    }

    private func statusParts(
        _ snapshot: RateLimitSnapshot,
        language: AppLanguage
    ) -> [(menuText: String, accessibilityText: String)] {
        var parts: [(String, String)] = []
        if let fiveHour = snapshot.fiveHourWindow {
            let remaining = Int(fiveHour.remainingPercent.rounded())
            parts.append((
                String(format: "5h %3d%%", remaining),
                Text.fiveHourAccessibility(remaining, language: language)
            ))
        }
        if let weekly = snapshot.weeklyWindow {
            let remaining = Int(weekly.remainingPercent.rounded())
            let prefix = Text.weeklyAbbreviation(language)
            parts.append((
                String(format: "%@ %3d%%", prefix, remaining),
                Text.weeklyAccessibility(remaining, language: language)
            ))
        }
        return parts
    }

    private func makeQuotaBarsImage(
        fiveHour: RateLimitWindow?,
        weekly: RateLimitWindow?,
        stale: Bool
    ) -> NSImage {
        let size = NSSize(width: 24, height: 13)
        let windows = [fiveHour, weekly].compactMap { $0 }

        let image = NSImage(size: size, flipped: false) { rect in
            guard !windows.isEmpty else {
                let emptyRect = NSRect(x: 1, y: 4, width: rect.width - 2, height: 5)
                NSColor.secondaryLabelColor.withAlphaComponent(0.65).setStroke()
                let outline = NSBezierPath(roundedRect: emptyRect, xRadius: 2.5, yRadius: 2.5)
                outline.lineWidth = 1
                outline.stroke()
                return true
            }

            let barHeight: CGFloat = windows.count == 1 ? 5 : 4
            let spacing: CGFloat = windows.count == 1 ? 0 : 2
            let totalHeight = CGFloat(windows.count) * barHeight + CGFloat(max(0, windows.count - 1)) * spacing
            let startY = (rect.height - totalHeight) / 2

            for (index, window) in windows.enumerated() {
                let trackRect = NSRect(
                    x: 1,
                    y: startY + CGFloat(index) * (barHeight + spacing),
                    width: rect.width - 2,
                    height: barHeight
                )
                let radius = barHeight / 2
                let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: radius, yRadius: radius)
                NSColor.labelColor.withAlphaComponent(0.18).setFill()
                trackPath.fill()

                let fraction = max(0, min(1, window.remainingPercent / 100))
                guard fraction > 0 else { continue }
                let fillRect = NSRect(
                    x: trackRect.minX,
                    y: trackRect.minY,
                    width: trackRect.width * fraction,
                    height: trackRect.height
                )
                NSGraphicsContext.saveGraphicsState()
                trackPath.addClip()
                let color = stale ? NSColor.secondaryLabelColor : RateWindowRowView.color(for: window.remainingPercent)
                color.setFill()
                NSBezierPath(rect: fillRect).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = Text.progressBarAccessibility(languageSettings.current)
        return image
    }
}
