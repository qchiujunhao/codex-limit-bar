import Foundation

func assertEqual(_ actual: Int, _ expected: Int, _ message: String) {
    guard actual == expected else {
        fputs("FAIL: \(message) — got \(actual), expected \(expected)\n", stderr)
        exit(1)
    }
}

func assertEqual(_ actual: String, _ expected: String, _ message: String) {
    guard actual == expected else {
        fputs("FAIL: \(message) — got \(actual), expected \(expected)\n", stderr)
        exit(1)
    }
}

@main
enum ModelTests {
    static func main() throws {
        let multiBucketResponse: [String: Any] = [
            "result": [
                "rateLimits": [
                    "limitId": "codex",
                    "primary": ["usedPercent": 10, "windowDurationMins": 300, "resetsAt": 1_900_000_000],
                    "secondary": ["usedPercent": 35, "windowDurationMins": 10_080, "resetsAt": 1_900_100_000]
                ],
                "rateLimitsByLimitId": [
                    "codex": [
                        "limitId": "codex",
                        "planType": "plus",
                        "primary": ["usedPercent": 10, "windowDurationMins": 300, "resetsAt": 1_900_000_000],
                        "secondary": ["usedPercent": 35, "windowDurationMins": 10_080, "resetsAt": 1_900_100_000]
                    ],
                    "codex_other": [
                        "limitId": "codex_other",
                        "limitName": "Fast",
                        "primary": ["usedPercent": 42, "windowDurationMins": 60, "resetsAt": 1_900_200_000]
                    ]
                ],
                "rateLimitResetCredits": ["availableCount": 2]
            ],
        ]

        let snapshot = try RateLimitSnapshot.parse(from: multiBucketResponse)
        assertEqual(snapshot.buckets.count, 2, "multi-bucket parsing")
        assertEqual(Int(snapshot.fiveHourWindow?.remainingPercent ?? -1), 90, "five-hour window parsing")
        assertEqual(Int(snapshot.weeklyWindow?.remainingPercent ?? -1), 65, "weekly window parsing")
        assertEqual(snapshot.quotaWindowsForDisplay().count, 2, "only five-hour and weekly windows appear")
        assertEqual(snapshot.resetCreditsAvailable ?? -1, 2, "reset credit count")

        let fallbackResponse: [String: Any] = [
            "result": [
                "rateLimits": [
                    "limitId": "codex",
                    "primary": ["usedPercent": 107, "windowDurationMins": 15]
                ]
            ]
        ]

        let fallback = try RateLimitSnapshot.parse(from: fallbackResponse)
        assertEqual(fallback.buckets.count, 1, "fallback bucket parsing")
        assertEqual(Int(fallback.mainBucket?.primary?.remainingPercent ?? -1), 0, "remaining percentage clamps at zero")
        assertEqual(fallback.quotaWindowsForDisplay().count, 0, "unrelated windows stay hidden")

        let weeklyOnlyResponse: [String: Any] = [
            "result": [
                "rateLimits": [
                    "limitId": "codex",
                    "primary": ["usedPercent": 57, "windowDurationMins": 10_080]
                ]
            ]
        ]

        let weeklyOnly = try RateLimitSnapshot.parse(from: weeklyOnlyResponse)
        assertEqual(weeklyOnly.fiveHourWindow == nil ? 1 : 0, 1, "missing five-hour window stays hidden")
        assertEqual(Int(weeklyOnly.weeklyWindow?.remainingPercent ?? -1), 43, "weekly-only window parsing")
        assertEqual(weeklyOnly.quotaWindowsForDisplay().count, 1, "weekly-only display")

        let suiteName = "app.codexlimitbar.tests.\(UUID().uuidString)"
        guard let testDefaults = UserDefaults(suiteName: suiteName) else {
            fputs("FAIL: could not create isolated defaults\n", stderr)
            exit(1)
        }
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        let settingsKey = "language"
        let settings = LanguageSettings(defaults: testDefaults, key: settingsKey)
        assertEqual(settings.current.rawValue, "en", "English is the explicit default language")

        testDefaults.set("invalid", forKey: settingsKey)
        assertEqual(settings.current.rawValue, "en", "invalid language values fall back to English")

        settings.current = .simplifiedChinese
        let reloadedSettings = LanguageSettings(defaults: testDefaults, key: settingsKey)
        assertEqual(reloadedSettings.current.rawValue, "zh-Hans", "language choice persists")
        assertEqual(Text.windowTitle(.weekly, language: .english), "Weekly limit", "English strings")
        assertEqual(Text.windowTitle(.weekly, language: .simplifiedChinese), "每周额度", "Chinese strings")

        print("ModelTests passed")
    }
}
