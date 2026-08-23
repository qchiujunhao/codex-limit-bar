import Foundation

struct RateLimitWindow {
    let usedPercent: Double
    let windowDurationMinutes: Int?
    let resetsAt: Date?

    var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }
}

struct RateLimitBucket {
    let id: String
    let name: String?
    let planType: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?

    var windows: [RateLimitWindow] {
        [primary, secondary].compactMap { $0 }
    }
}

enum QuotaWindowKind {
    case fiveHour
    case weekly
}

struct DisplayWindow {
    let kind: QuotaWindowKind
    let window: RateLimitWindow
}

struct RateLimitSnapshot {
    let buckets: [RateLimitBucket]
    let fetchedAt: Date
    let resetCreditsAvailable: Int?

    var mainBucket: RateLimitBucket? {
        buckets.first(where: { $0.id == "codex" }) ?? buckets.first
    }

    var fiveHourWindow: RateLimitWindow? {
        mainBucket?.windows.first(where: { $0.windowDurationMinutes == 300 })
    }

    var weeklyWindow: RateLimitWindow? {
        mainBucket?.windows.first(where: { $0.windowDurationMinutes == 10_080 })
    }

    var planType: String? {
        mainBucket?.planType
    }

    func quotaWindowsForDisplay() -> [DisplayWindow] {
        var rows: [DisplayWindow] = []

        if let fiveHourWindow {
            rows.append(DisplayWindow(kind: .fiveHour, window: fiveHourWindow))
        }
        if let weeklyWindow {
            rows.append(DisplayWindow(kind: .weekly, window: weeklyWindow))
        }

        return rows
    }

    static func parse(from response: [String: Any]) throws -> RateLimitSnapshot {
        guard let result = response["result"] as? [String: Any] else {
            throw RateLimitParseError.missingResult
        }

        var buckets: [RateLimitBucket] = []

        if let byID = result["rateLimitsByLimitId"] as? [String: Any] {
            for (fallbackID, rawValue) in byID {
                guard let dictionary = rawValue as? [String: Any] else { continue }
                if let bucket = parseBucket(dictionary, fallbackID: fallbackID) {
                    buckets.append(bucket)
                }
            }
        }

        if buckets.isEmpty,
           let dictionary = result["rateLimits"] as? [String: Any],
           let bucket = parseBucket(dictionary, fallbackID: "codex") {
            buckets.append(bucket)
        }

        guard !buckets.isEmpty else {
            throw RateLimitParseError.missingLimits
        }

        buckets.sort {
            if $0.id == "codex" { return true }
            if $1.id == "codex" { return false }
            return $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending
        }

        let resetCredits: Int?
        if let rawCredits = result["rateLimitResetCredits"] as? [String: Any] {
            resetCredits = integer(rawCredits["availableCount"])
        } else {
            resetCredits = nil
        }

        return RateLimitSnapshot(
            buckets: buckets,
            fetchedAt: Date(),
            resetCreditsAvailable: resetCredits
        )
    }

    private static func parseBucket(_ dictionary: [String: Any], fallbackID: String) -> RateLimitBucket? {
        let id = (dictionary["limitId"] as? String) ?? fallbackID
        let name = dictionary["limitName"] as? String
        let planType = dictionary["planType"] as? String
        let primary = parseWindow(dictionary["primary"])
        let secondary = parseWindow(dictionary["secondary"])

        guard primary != nil || secondary != nil else { return nil }

        return RateLimitBucket(
            id: id,
            name: name,
            planType: planType,
            primary: primary,
            secondary: secondary
        )
    }

    private static func parseWindow(_ rawValue: Any?) -> RateLimitWindow? {
        guard let dictionary = rawValue as? [String: Any],
              let usedPercent = number(dictionary["usedPercent"]) else {
            return nil
        }

        let duration = integer(dictionary["windowDurationMins"])
        let resetTimestamp = number(dictionary["resetsAt"])
        let resetDate = resetTimestamp.map { Date(timeIntervalSince1970: $0) }

        return RateLimitWindow(
            usedPercent: usedPercent,
            windowDurationMinutes: duration,
            resetsAt: resetDate
        )
    }

    private static func number(_ rawValue: Any?) -> Double? {
        if let value = rawValue as? NSNumber { return value.doubleValue }
        if let value = rawValue as? String { return Double(value) }
        return nil
    }

    private static func integer(_ rawValue: Any?) -> Int? {
        if let value = rawValue as? NSNumber { return value.intValue }
        if let value = rawValue as? String { return Int(value) }
        return nil
    }

}

enum RateLimitParseError: LocalizedError {
    case missingResult
    case missingLimits

    var errorDescription: String? {
        switch self {
        case .missingResult:
            return "Codex did not return limit data."
        case .missingLimits:
            return "This account has no Codex limit windows to display."
        }
    }
}
