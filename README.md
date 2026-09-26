# Codex Limit Bar

[简体中文](README.zh-CN.md)

An unofficial native macOS menu bar app for checking Codex 5-hour and weekly usage limits at a glance.

English is the default interface language. Open the popover and use the language menu to switch the entire interface to Simplified Chinese; the choice is saved locally.

## Display format

The menu bar shows Codex's 5-hour and weekly limits:

- When both windows are available: `5h 80%  Wk 43%`
- When the 5-hour window is temporarily unavailable: `Wk 43%`
- When the 5-hour window returns, it appears again on the next refresh.

## Features

- Shows remaining Codex limits and color-coded progress bars in the macOS menu bar
- Displays the 5-hour and weekly limits separately
- Hides the 5-hour item when Codex does not return that window
- Switches between English and Simplified Chinese instantly, with English as the default
- Shows reset times, plan information, and available reset credits
- Refreshes automatically every 60 seconds and supports manual refresh
- Follows desktop account changes on the next refresh; click **Refresh** to sync immediately
- Retries automatically after connection failures or timeouts
- Keeps the last successful values and shows `!` when they are stale
- Does not read, copy, or save ChatGPT login tokens
- Native AppKit app for Apple Silicon and Intel Macs

## Requirements

- macOS 13 or later
- ChatGPT/Codex desktop app or Codex CLI installed and signed in

## Download and install

Download `Codex-Limit-Bar.zip` from the repository's [Releases](../../releases) page, unzip it, and run `Codex Limit Bar.app`.

The current build uses ad-hoc signing and is not notarized. If macOS blocks the first launch, right-click the app in Finder and choose **Open**.

The app has no Dock icon. Click the menu bar item, then choose **Quit** to exit. The language menu is at the bottom of the same popover.

## Data source and privacy

The app reads limit information through the official local Codex App Server `account/rateLimits/read` method. `usedPercent`, window durations, and reset times come from that response. Authentication is handled by the local ChatGPT/Codex sign-in state.

The app does not independently read, copy, or save login tokens, and it does not send limit data to third-party services. See the [OpenAI Codex App Server documentation](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt).

The language choice is stored locally in `UserDefaults`.

## Build from source

Install Xcode or the Xcode Command Line Tools, then run:

```bash
./scripts/test.sh
./scripts/build.sh
```

Build artifacts:

- `dist/Codex Limit Bar.app`
- `dist/Codex-Limit-Bar.zip`

The build script creates a Universal Binary for `arm64` and `x86_64`, with macOS 13 as the minimum deployment target.

## macOS menu bar limitation

macOS manages the app menu on the left and the status area on the right separately. An independent app can only create a status item in the right-side area; it cannot be pinned next to the current app's **Help** menu. Hold Command and drag the status item to adjust its position among the other status items.

## Troubleshooting

- `?%`: The app has not read data successfully yet. Confirm that ChatGPT/Codex is signed in, then open the popover and click **Refresh**.
- `!`: The app is showing the last successful values while reconnecting.
- After switching accounts in the desktop app: wait for the next automatic refresh (about 60 seconds), or click **Refresh**. Each refresh reconnects to Codex and checks the account before reading limits. Old values are cleared when the account changes, cannot be identified, or requires sign-in. Authentication failures get one quick retry, then resume on the regular refresh schedule.
- Missing status item: macOS may temporarily hide status items when the menu bar is full.
- API key sign-in: ChatGPT plan limits require ChatGPT sign-in; API key mode does not provide those plan-limit windows.

## Disclaimer

This is an unofficial community project and is not affiliated with or endorsed by OpenAI. Codex, ChatGPT, and OpenAI are trademarks of OpenAI.
