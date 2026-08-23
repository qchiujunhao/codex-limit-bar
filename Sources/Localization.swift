import Foundation

enum AppLanguage: String, CaseIterable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        }
    }

    var locale: Locale {
        switch self {
        case .english:
            return Locale(identifier: "en_US")
        case .simplifiedChinese:
            return Locale(identifier: "zh_Hans_CN")
        }
    }
}

final class LanguageSettings {
    static let shared = LanguageSettings()

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "CodexLimitBar.Language") {
        self.defaults = defaults
        self.key = key
    }

    var current: AppLanguage {
        get {
            guard let storedValue = defaults.string(forKey: key),
                  let language = AppLanguage(rawValue: storedValue) else {
                return .english
            }
            return language
        }
        set {
            defaults.set(newValue.rawValue, forKey: key)
        }
    }
}

enum ClientStatus {
    case connecting
    case refreshing
}

enum ClientIssue {
    case codexNotFound
    case initializationRequestFailed
    case launchFailed(String)
    case initializationHandshakeFailed
    case rateLimitRequestFailed
    case initializationTimedOut
    case rateLimitTimedOut
    case serverStopped
    case serverExited(Int32)
    case loginRequired
    case apiKeyUnsupported
    case missingResponseData
    case noQuotaWindows
    case readFailed(String)
}

enum Text {
    static func popoverTitle(_ language: AppLanguage) -> String {
        language == .english ? "Codex remaining limits" : "Codex 剩余额度"
    }

    static func reading(_ language: AppLanguage) -> String {
        language == .english ? "Reading…" : "正在读取…"
    }

    static func connectingContext(_ language: AppLanguage) -> String {
        language == .english ? "Connecting to the local Codex service" : "连接 Codex 本地数据服务"
    }

    static func refresh(_ language: AppLanguage) -> String {
        language == .english ? "Refresh" : "刷新"
    }

    static func quit(_ language: AppLanguage) -> String {
        language == .english ? "Quit" : "退出"
    }

    static func languageControl(_ language: AppLanguage) -> String {
        language == .english ? "Language" : "语言"
    }

    static func windowTitle(_ kind: QuotaWindowKind, language: AppLanguage) -> String {
        switch (language, kind) {
        case (.english, .fiveHour):
            return "5-hour limit"
        case (.english, .weekly):
            return "Weekly limit"
        case (.simplifiedChinese, .fiveHour):
            return "5 小时额度"
        case (.simplifiedChinese, .weekly):
            return "每周额度"
        }
    }

    static func weeklyAbbreviation(_ language: AppLanguage) -> String {
        language == .english ? "Wk" : "周"
    }

    static func remaining(_ percent: Int, language: AppLanguage) -> String {
        language == .english ? "\(percent)% remaining" : "剩余 \(percent)%"
    }

    static func noResetTime(_ language: AppLanguage) -> String {
        language == .english ? "Reset time unavailable" : "未提供重置时间"
    }

    static func resetDescription(relative: String, absolute: String, language: AppLanguage) -> String {
        language == .english ? "Resets \(relative) · \(absolute)" : "\(relative)重置 · \(absolute)"
    }

    static func noLimitData(_ language: AppLanguage) -> String {
        language == .english ? "No limit data" : "暂无额度数据"
    }

    static func contextForSnapshot(_ snapshot: RateLimitSnapshot, language: AppLanguage) -> String {
        var parts: [String]
        if snapshot.fiveHourWindow == nil, snapshot.weeklyWindow != nil {
            parts = [language == .english ? "5-hour limit is not currently available" : "5 小时额度暂未返回"]
        } else if snapshot.fiveHourWindow != nil, snapshot.weeklyWindow != nil {
            parts = [language == .english ? "Showing 5-hour and weekly limits" : "同时显示 5 小时与每周额度"]
        } else if snapshot.fiveHourWindow != nil, snapshot.weeklyWindow == nil {
            parts = [language == .english ? "Weekly limit is not currently available" : "每周额度暂未返回"]
        } else {
            parts = [language == .english ? "No 5-hour or weekly limit returned" : "当前未返回 5 小时或每周额度"]
        }

        if let plan = snapshot.planType, !plan.isEmpty {
            let planName = plan.uppercased()
            parts.append(language == .english ? "\(planName) plan" : "\(planName) 套餐")
        }
        if let credits = snapshot.resetCreditsAvailable {
            if language == .english {
                parts.append(credits == 1 ? "1 reset available" : "\(credits) resets available")
            } else {
                parts.append("可用重置 \(credits) 次")
            }
        }
        return parts.joined(separator: " · ")
    }

    static func updatedAt(_ time: String, language: AppLanguage) -> String {
        language == .english ? "Updated at \(time)" : "更新于 \(time)"
    }

    static func temporarilyUnavailable(_ language: AppLanguage) -> String {
        language == .english ? "Temporarily unavailable" : "暂时无法读取"
    }

    static func connectionIssueFooter(_ language: AppLanguage) -> String {
        language == .english ? "Connection issue · Click Refresh to retry" : "连接异常 · 可点刷新重试"
    }

    static func status(_ status: ClientStatus, language: AppLanguage) -> String {
        switch (language, status) {
        case (.english, .connecting):
            return "Connecting to Codex…"
        case (.english, .refreshing):
            return "Refreshing…"
        case (.simplifiedChinese, .connecting):
            return "正在连接 Codex…"
        case (.simplifiedChinese, .refreshing):
            return "正在刷新…"
        }
    }

    static func issue(_ issue: ClientIssue, language: AppLanguage) -> String {
        switch language {
        case .english:
            switch issue {
            case .codexNotFound:
                return "Codex was not found. Install or open the ChatGPT/Codex desktop app first."
            case .initializationRequestFailed:
                return "Could not send the Codex initialization request."
            case .launchFailed(let detail):
                return "Could not start the Codex data service: \(detail)"
            case .initializationHandshakeFailed:
                return "Could not complete the Codex initialization handshake."
            case .rateLimitRequestFailed:
                return "Could not request limit data from Codex."
            case .initializationTimedOut:
                return "The Codex connection timed out. Retrying."
            case .rateLimitTimedOut:
                return "Reading Codex limits timed out. Retrying."
            case .serverStopped:
                return "The Codex data service stopped."
            case .serverExited(let status):
                return "The Codex data service exited unexpectedly (\(status))."
            case .loginRequired:
                return "Sign in to ChatGPT/Codex, then click Refresh."
            case .apiKeyUnsupported:
                return "API key sign-in does not include ChatGPT plan limits. Use ChatGPT sign-in instead."
            case .missingResponseData:
                return "Codex did not return limit data."
            case .noQuotaWindows:
                return "This account has no 5-hour or weekly Codex limit to display."
            case .readFailed(let detail):
                return "Could not read Codex limits: \(detail)"
            }
        case .simplifiedChinese:
            switch issue {
            case .codexNotFound:
                return "找不到 Codex。请先安装或打开 ChatGPT/Codex 桌面 App。"
            case .initializationRequestFailed:
                return "无法发送 Codex 初始化请求。"
            case .launchFailed(let detail):
                return "无法启动 Codex 数据服务：\(detail)"
            case .initializationHandshakeFailed:
                return "无法完成 Codex 初始化握手。"
            case .rateLimitRequestFailed:
                return "无法向 Codex 请求额度数据。"
            case .initializationTimedOut:
                return "连接 Codex 超时，正在重试。"
            case .rateLimitTimedOut:
                return "读取 Codex 额度超时，正在重试。"
            case .serverStopped:
                return "Codex 数据服务已停止。"
            case .serverExited(let status):
                return "Codex 数据服务异常退出（\(status)）。"
            case .loginRequired:
                return "请先在 ChatGPT/Codex 中登录，然后点“刷新”。"
            case .apiKeyUnsupported:
                return "API Key 登录不提供 ChatGPT 套餐额度；请改用 ChatGPT 登录。"
            case .missingResponseData:
                return "Codex 没有返回额度数据。"
            case .noQuotaWindows:
                return "当前账户没有可显示的 5 小时或每周 Codex 额度。"
            case .readFailed(let detail):
                return "读取 Codex 额度失败：\(detail)"
            }
        }
    }

    static func statusItemAccessibilityLabel(_ language: AppLanguage) -> String {
        language == .english ? "Codex remaining limits" : "Codex 剩余额度"
    }

    static func statusItemLoadingTooltip(_ language: AppLanguage) -> String {
        language == .english ? "Codex remaining limits: reading" : "Codex 剩余额度：正在读取"
    }

    static func statusItemLoadingValue(_ language: AppLanguage) -> String {
        language == .english ? "Reading" : "正在读取"
    }

    static func statusItemEmptyTitle(_ language: AppLanguage) -> String {
        language == .english ? " Limits --" : " 额度 --"
    }

    static func statusItemNoWindows(_ language: AppLanguage) -> String {
        language == .english ? "Codex did not return a 5-hour or weekly limit" : "Codex 当前未返回 5 小时或每周额度"
    }

    static func statusItemTooltip(details: String, language: AppLanguage) -> String {
        language == .english ? "Codex \(details) (click for details)" : "Codex \(details)（点按查看详情）"
    }

    static func statusItemErrorTitle(_ language: AppLanguage) -> String {
        language == .english ? " Limits ?" : " 额度 ?"
    }

    static func statusItemErrorTooltip(_ language: AppLanguage) -> String {
        language == .english ? "Could not read Codex limits (click for details)" : "无法读取 Codex 剩余额度（点按查看详情）"
    }

    static func statusItemErrorValue(_ language: AppLanguage) -> String {
        language == .english ? "Temporarily unavailable" : "暂时无法读取"
    }

    static func fiveHourAccessibility(_ percent: Int, language: AppLanguage) -> String {
        language == .english ? "5-hour limit: \(percent)% remaining" : "5 小时剩余 \(percent)%"
    }

    static func weeklyAccessibility(_ percent: Int, language: AppLanguage) -> String {
        language == .english ? "Weekly limit: \(percent)% remaining" : "每周剩余 \(percent)%"
    }

    static func detailsSeparator(_ language: AppLanguage) -> String {
        language == .english ? ", " : "，"
    }

    static func staleTooltip(details: String, language: AppLanguage) -> String {
        language == .english
            ? "Codex limit data is stale; last values: \(details) (click for details)"
            : "Codex 额度数据已过期；上次为 \(details)（点按查看详情）"
    }

    static func staleAccessibility(details: String, language: AppLanguage) -> String {
        language == .english ? "Data is stale. Last values: \(details)" : "数据已过期，上次为 \(details)"
    }

    static func progressBarAccessibility(_ language: AppLanguage) -> String {
        language == .english ? "Limit progress bars" : "额度进度条"
    }
}
