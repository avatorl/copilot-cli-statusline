# Copilot CLI Status Line

A PowerShell status line for [GitHub Copilot CLI](https://docs.github.com/en/copilot/github-copilot-in-the-cli) that displays real-time session metrics, quota pacing, and workspace info directly in your terminal.

![Windows](https://img.shields.io/badge/platform-Windows-blue)
![PowerShell 7+](https://img.shields.io/badge/PowerShell-7%2B-5391FE)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

## What It Shows

The status line renders two lines at the bottom of your Copilot CLI session:

```
gpt-5.4 (high) | ███░░░░░░░ 22% 400K | 54m | 5 p.req. | in 1.7M out 27K | Q 14% / M 23% | █ █ █ 2.9 days behind
D:\GITHUB\my-project | +695 -146
```

### Line 1 — Session Metrics

| Segment | Description |
|---------|-------------|
| **Model** | Active model display name (e.g. `gpt-5.4 (high)`) |
| **Context Bar** | Visual bar + percentage + window size showing context usage |
| **Duration** | Session wall-clock time (rounded to whole minutes) |
| **Premium Requests** | Count of premium requests used this session |
| **Tokens In/Out** | Cumulative input/output tokens with color thresholds |
| **Q% / M%** | Quota used vs. month elapsed (calendar pacing) |
| **Pace Bars** | Colored blocks showing days ahead/behind quota pace |

### Line 2 — Workspace

| Segment | Description |
|---------|-------------|
| **Path** | Current working directory |
| **Lines Changed** | Lines added (green) and removed (red) this session |

### Color Coding

- **Token counts**: bright yellow ≥10K, yellow ≥100K, red ≥1M
- **Context usage**: green <75%, yellow ≥75%, red ≥90%
- **Pace bars**: green = behind pace (under budget, good), yellow = on pace, red = ahead of pace (over budget)

## Requirements

- **Windows** (uses `.cmd` wrapper)
- **[PowerShell 7+](https://github.com/PowerShell/PowerShell/releases)** (`pwsh.exe`)
- **GitHub Copilot CLI** with the `STATUS_LINE` experimental flag enabled
- A terminal that supports **ANSI escape codes** and **Unicode block characters** (Windows Terminal recommended)

## Installation

### 1. Clone or download this repository

```bash
git clone https://github.com/avatorl/copilot-cli-statusline.git
```

Place the files anywhere on your system, for example:

```
C:\Users\<you>\.copilot\statusline\
├── statusline.ps1
└── statusline.cmd
```

### 2. Update `statusline.cmd` (if needed)

The `.cmd` wrapper uses `%~dp0` to find `statusline.ps1` in the same directory. If your `pwsh.exe` is not at the default location, edit the path in `statusline.cmd`:

```cmd
@echo off
"C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -File "%~dp0statusline.ps1"
```

### 3. Configure Copilot CLI

Edit your Copilot CLI config file at `~/.copilot/config.json`. Add or update these fields:

```jsonc
{
  // Enable experimental features
  "experimental": true,
  "experimental_flags": ["STATUS_LINE"],

  // Point to the statusline.cmd wrapper
  "statusLine": {
    "type": "command",
    "command": "C:\\Users\\<you>\\.copilot\\statusline\\statusline.cmd"
  }
}
```

> **Important**: Use the full absolute path to `statusline.cmd` with double backslashes in JSON.

### 4. Restart Copilot CLI

Launch a new Copilot CLI session. The status line should appear at the bottom of your terminal.

## How It Works

1. Copilot CLI pipes a JSON payload to the script's stdin on each status refresh
2. The script parses session metadata (model, tokens, duration, lines changed, context usage)
3. It fetches your Copilot quota from the GitHub API (`/copilot_internal/user`)
4. It calculates pacing: how your quota usage compares to the calendar month progress
5. It renders two ANSI-colored lines to stdout, which Copilot CLI displays as the status bar

### GitHub Token Resolution

The script resolves a GitHub token for the quota API in this order:

1. `GITHUB_TOKEN` environment variable
2. `GH_TOKEN` environment variable
3. Token from `~/.copilot/config.json` → `copilot_tokens`
4. Git credential store (`git credential fill`)

No additional authentication setup is needed if you're already logged into Copilot CLI.

### Debug Logging

The script logs all raw stdin JSON payloads to `statusline.stdin.log` (in the same directory as the script) for debugging. You can safely delete this file at any time.

## Payload Parameters

The script documents all known stdin payload fields in the header comments of `statusline.ps1`. Fields marked ✅ are actively used; fields marked ○ are available for future enhancements.

## License

[MIT](LICENSE)

(c) Andrzej
