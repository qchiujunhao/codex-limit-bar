import AppKit

final class LimitBarView: NSView {
    var fraction: Double = 0 {
        didSet {
            fraction = max(0, min(1, fraction))
            needsDisplay = true
        }
    }

    var fillColor: NSColor = .systemGreen {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let trackRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius = min(trackRect.height / 2, 5)
        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: radius, yRadius: radius)
        NSColor.quaternaryLabelColor.setFill()
        trackPath.fill()

        guard fraction > 0 else { return }
        let fillRect = NSRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: trackRect.width * fraction,
            height: trackRect.height
        )
        NSGraphicsContext.saveGraphicsState()
        trackPath.addClip()
        fillColor.setFill()
        NSBezierPath(rect: fillRect).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class RateWindowRowView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let percentLabel = NSTextField(labelWithString: "")
    private let barView = LimitBarView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .labelColor

        detailLabel.font = .systemFont(ofSize: 10.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail

        percentLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        percentLabel.alignment = .right

        [titleLabel, detailLabel, percentLabel, barView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 50),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            percentLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            percentLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: percentLabel.leadingAnchor, constant: -8),
            barView.leadingAnchor.constraint(equalTo: leadingAnchor),
            barView.trailingAnchor.constraint(equalTo: trailingAnchor),
            barView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 7),
            barView.heightAnchor.constraint(equalToConstant: 7),
            detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: barView.bottomAnchor, constant: 5)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(kind: QuotaWindowKind, window: RateLimitWindow, language: AppLanguage) {
        let remaining = window.remainingPercent
        let roundedRemaining = Int(remaining.rounded())
        let title = Text.windowTitle(kind, language: language)
        let resetDescription = Self.resetDescription(window.resetsAt, language: language)

        titleLabel.stringValue = title
        percentLabel.stringValue = Text.remaining(roundedRemaining, language: language)
        detailLabel.stringValue = resetDescription
        barView.fraction = remaining / 100
        barView.fillColor = Self.color(for: remaining)

        let accessibilityText: String
        if language == .english {
            accessibilityText = "\(title), \(roundedRemaining)% remaining, \(resetDescription)"
        } else {
            accessibilityText = "\(title)，剩余 \(roundedRemaining)%，\(resetDescription)"
        }
        setAccessibilityLabel(accessibilityText)
    }

    private static func resetDescription(_ date: Date?, language: AppLanguage) -> String {
        guard let date else { return Text.noResetTime(language) }

        let relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.locale = language.locale
        relativeFormatter.unitsStyle = .full
        let relative = relativeFormatter.localizedString(for: date, relativeTo: Date())

        let absoluteFormatter = DateFormatter()
        absoluteFormatter.locale = language.locale
        switch language {
        case .english:
            absoluteFormatter.dateFormat = "MMM d, h:mm a"
        case .simplifiedChinese:
            absoluteFormatter.dateFormat = "M月d日 HH:mm"
        }
        return Text.resetDescription(
            relative: relative,
            absolute: absoluteFormatter.string(from: date),
            language: language
        )
    }

    static func color(for remaining: Double) -> NSColor {
        switch remaining {
        case 60...:
            return .systemGreen
        case 30..<60:
            return .systemYellow
        case 10..<30:
            return .systemOrange
        default:
            return .systemRed
        }
    }
}

final class LimitPopoverController: NSViewController {
    var onRefresh: (() -> Void)?
    var onQuit: (() -> Void)?
    var onLanguageChange: ((AppLanguage) -> Void)?

    private var language: AppLanguage
    private var latestSnapshot: RateLimitSnapshot?
    private var activeStatus: ClientStatus? = .connecting
    private var activeIssue: ClientIssue?

    private let titleLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let contextLabel = NSTextField(labelWithString: "")
    private let rowsStack = NSStackView()
    private let footerLabel = NSTextField(labelWithString: "")
    private let languagePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let refreshButton = NSButton(title: "", target: nil, action: nil)
    private let quitButton = NSButton(title: "", target: nil, action: nil)

    init(language: AppLanguage) {
        self.language = language
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 250))
        root.translatesAutoresizingMaskIntoConstraints = false
        view = root

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        summaryLabel.font = .monospacedDigitSystemFont(ofSize: 27, weight: .bold)
        summaryLabel.textColor = .labelColor

        contextLabel.font = .systemFont(ofSize: 11)
        contextLabel.textColor = .secondaryLabelColor
        contextLabel.lineBreakMode = .byTruncatingTail

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 5
        rowsStack.distribution = .fill

        footerLabel.font = .systemFont(ofSize: 10.5)
        footerLabel.textColor = .tertiaryLabelColor
        footerLabel.lineBreakMode = .byTruncatingTail

        languagePopUp.addItems(withTitles: AppLanguage.allCases.map(\.displayName))
        languagePopUp.controlSize = .small
        languagePopUp.target = self
        languagePopUp.action = #selector(languageChanged)

        refreshButton.bezelStyle = .rounded
        refreshButton.controlSize = .small
        refreshButton.target = self
        refreshButton.action = #selector(refreshPressed)

        quitButton.bezelStyle = .rounded
        quitButton.controlSize = .small
        quitButton.target = self
        quitButton.action = #selector(quitPressed)

        let buttonStack = NSStackView(views: [languagePopUp, refreshButton, quitButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 6

        [titleLabel, summaryLabel, contextLabel, rowsStack, footerLabel, buttonStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview($0)
        }

        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 360),
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),

            summaryLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            summaryLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            summaryLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            contextLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            contextLabel.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 2),
            contextLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            rowsStack.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            rowsStack.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            rowsStack.topAnchor.constraint(equalTo: contextLabel.bottomAnchor, constant: 15),

            footerLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            footerLabel.trailingAnchor.constraint(lessThanOrEqualTo: buttonStack.leadingAnchor, constant: -8),
            footerLabel.centerYAnchor.constraint(equalTo: buttonStack.centerYAnchor),

            buttonStack.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            buttonStack.topAnchor.constraint(equalTo: rowsStack.bottomAnchor, constant: 13),
            buttonStack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -13)
        ])

        preferredContentSize = NSSize(width: 360, height: 250)
        applyStaticStrings()
        renderCurrentState()
    }

    func applyLanguage(_ language: AppLanguage) {
        self.language = language
        _ = view
        applyStaticStrings()
        renderCurrentState()
    }

    func update(snapshot: RateLimitSnapshot) {
        latestSnapshot = snapshot
        activeStatus = nil
        activeIssue = nil
        _ = view
        renderCurrentState()
    }

    func updateStatus(_ status: ClientStatus) {
        activeStatus = status
        activeIssue = nil
        _ = view
        renderCurrentState()
    }

    func updateError(_ issue: ClientIssue) {
        activeStatus = nil
        activeIssue = issue
        _ = view
        renderCurrentState()
    }

    @objc private func languageChanged() {
        let languages = AppLanguage.allCases
        guard languages.indices.contains(languagePopUp.indexOfSelectedItem) else { return }
        let selectedLanguage = languages[languagePopUp.indexOfSelectedItem]
        language = selectedLanguage
        applyStaticStrings()
        renderCurrentState()
        onLanguageChange?(selectedLanguage)
    }

    @objc private func refreshPressed() {
        onRefresh?()
    }

    @objc private func quitPressed() {
        onQuit?()
    }

    private func applyStaticStrings() {
        titleLabel.stringValue = Text.popoverTitle(language)
        refreshButton.title = Text.refresh(language)
        quitButton.title = Text.quit(language)
        languagePopUp.selectItem(at: AppLanguage.allCases.firstIndex(of: language) ?? 0)
        languagePopUp.toolTip = Text.languageControl(language)
        languagePopUp.setAccessibilityLabel(Text.languageControl(language))
    }

    private func renderCurrentState() {
        clearRows()

        if let snapshot = latestSnapshot {
            renderSnapshot(snapshot)
        } else {
            summaryLabel.stringValue = Text.reading(language)
            contextLabel.stringValue = Text.connectingContext(language)
            footerLabel.stringValue = ""
            resizeForRows(0)
        }

        if let issue = activeIssue {
            if latestSnapshot == nil {
                summaryLabel.stringValue = Text.temporarilyUnavailable(language)
                contextLabel.stringValue = Text.issue(issue, language: language)
            }
            footerLabel.stringValue = Text.connectionIssueFooter(language)
            refreshButton.isEnabled = true
        } else if let status = activeStatus {
            footerLabel.stringValue = Text.status(status, language: language)
            refreshButton.isEnabled = false
        } else {
            refreshButton.isEnabled = true
        }

        contextLabel.toolTip = contextLabel.stringValue
        footerLabel.toolTip = footerLabel.stringValue.isEmpty ? nil : footerLabel.stringValue
    }

    private func renderSnapshot(_ snapshot: RateLimitSnapshot) {
        summaryLabel.stringValue = summaryText(snapshot)
        contextLabel.stringValue = Text.contextForSnapshot(snapshot, language: language)

        let rows = snapshot.quotaWindowsForDisplay()
        for row in rows {
            let rowView = RateWindowRowView(frame: .zero)
            rowView.update(kind: row.kind, window: row.window, language: language)
            rowsStack.addArrangedSubview(rowView)
            rowView.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
        }

        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateFormat = language == .english ? "h:mm:ss a" : "HH:mm:ss"
        footerLabel.stringValue = Text.updatedAt(formatter.string(from: snapshot.fetchedAt), language: language)
        resizeForRows(rows.count)
    }

    private func clearRows() {
        for arrangedView in rowsStack.arrangedSubviews {
            rowsStack.removeArrangedSubview(arrangedView)
            arrangedView.removeFromSuperview()
        }
    }

    private func resizeForRows(_ count: Int) {
        let height = CGFloat(164 + max(1, count) * 55)
        preferredContentSize = NSSize(width: 360, height: min(510, height))
    }

    private func summaryText(_ snapshot: RateLimitSnapshot) -> String {
        var parts: [String] = []
        if let fiveHour = snapshot.fiveHourWindow {
            parts.append("5h \(Int(fiveHour.remainingPercent.rounded()))%")
        }
        if let weekly = snapshot.weeklyWindow {
            let prefix = Text.weeklyAbbreviation(language)
            parts.append("\(prefix) \(Int(weekly.remainingPercent.rounded()))%")
        }
        return parts.isEmpty ? Text.noLimitData(language) : parts.joined(separator: "  ·  ")
    }
}
