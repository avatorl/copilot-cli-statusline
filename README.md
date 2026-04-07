# Copilot CLI Status Line

A Windows PowerShell status line for [GitHub Copilot CLI](https://docs.github.com/en/copilot/github-copilot-in-the-cli) that renders live session metrics, workspace stats, and Copilot quota pacing directly in the terminal.

![Windows](https://img.shields.io/badge/platform-Windows-blue)
![PowerShell 7+](https://img.shields.io/badge/PowerShell-7%2B-5391FE)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

## What It Shows

The current script renders **two lines**:

```text
gpt-5.4 (high) | ██████████ 22% 400K | in 1.7M out 27K | 54m | 5 p.req. | Quota: ████████░░░░░░░░░░░░░░░░░░░░░░ 3.2 days behind
D:\GITHUB\my-project | +695 -146
```

### Line 1 — Session Status

| Segment | Description |
|---------|-------------|
| **Model** | `model.display_name`, falling back to `model.id` |
| **Context usage** | 10-cell bar, rounded percent used, and context window size |
| **Tokens** | Cumulative `in` / `out` token totals |
| **Duration** | Session wall-clock time rounded to whole minutes |
| **Premium requests** | `cost.total_premium_requests` |
| **Quota** | Month calendar overlay showing quota pace relative to the current day |

### Line 2 — Workspace Status

| Segment | Description |
|---------|-------------|
| **Path** | `cwd`, falling back to `workspace.current_dir` |
| **Lines changed** | `+added` in green and `-removed` in red from the Copilot payload |

## Quota Calendar

The quota segment renders the current month as a compact calendar:

- **Solid grey `█`** = elapsed days
- **Hatched grey `░`** = remaining days
- **Green overlay** = behind quota pace (good)
- **Red overlay** = ahead of quota pace
- **Yellow today bar + `on pace`** = within 1 day of pace

The colored section always includes **today**. For example, **3 days behind** colors today plus the two preceding days.

If the quota API is unavailable, the script falls back to a dim `Quota: day/month` indicator.

## Color Rules

- **Context bar**: green under 75%, yellow at 75%+, red at 90%+
- **Unused context bar cells**: solid grey
- **Token values only** are colored: bright yellow at 10K+, yellow at 100K+, red at 1M+
- **Quota pace**: green = behind, yellow = on pace, red = ahead

## Requirements

- **Windows**
- **[PowerShell 7+](https://github.com/PowerShell/PowerShell/releases)** (`pwsh.exe`)
- **GitHub Copilot CLI** with the `STATUS_LINE` experimental flag enabled
- A terminal with ANSI color and Unicode block character support (Windows Terminal works well)

## Installation

### 1. Clone or copy the files

```bash
git clone https://github.com/avatorl/copilot-cli-statusline.git
```

Example destination:

```text
C:\Users\<you>\.copilot\statusline\
├── statusline.ps1
└── statusline.cmd
```

### 2. Verify `statusline.cmd`

The wrapper locates `statusline.ps1` from its own directory using `%~dp0`. If PowerShell 7 is installed in a different location, update the `pwsh.exe` path:

```cmd
@echo off
"C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -File "%~dp0statusline.ps1"
```

### 3. Configure Copilot CLI

Edit `~/.copilot/config.json`:

```jsonc
{
  "experimental": true,
  "experimental_flags": ["STATUS_LINE"],
  "statusLine": {
    "type": "command",
    "command": "C:\\Users\\<you>\\.copilot\\statusline\\statusline.cmd"
  }
}
```

Use an absolute path and escape backslashes in JSON.

### 4. Restart Copilot CLI

Start a new Copilot CLI session and the status line should appear automatically.

## Local Testing

There is no automated test suite. The script is intended to be tested by piping sample payloads into `statusline.ps1`.

```powershell
# Full payload
'{"cwd":"D:\\TEST","model":{"id":"gpt-5.4","display_name":"gpt-5.4 (high)"},"workspace":{"current_dir":"D:\\TEST"},"cost":{"total_duration_ms":3241747,"total_lines_added":100,"total_lines_removed":50,"total_premium_requests":5},"context_window":{"total_input_tokens":1744196,"total_output_tokens":26870,"context_window_size":400000,"used_percentage":22}}' | pwsh -NoProfile -File .\statusline.ps1

# Minimal payload
'{"context_window":{"context_window_size":400000,"used_percentage":0}}' | pwsh -NoProfile -File .\statusline.ps1

# Empty stdin
echo $null | pwsh -NoProfile -File .\statusline.ps1
```

## How It Works

1. Copilot CLI pipes a JSON payload to stdin on each refresh.
2. `statusline.ps1` parses the payload and extracts model, token, duration, path, and lines-changed data.
3. The script fetches quota data from `https://api.github.com/copilot_internal/user`.
4. Quota usage is compared against calendar progress for the current month.
5. Two ANSI-colored lines are written to stdout for Copilot CLI to render.

### GitHub Token Resolution

The quota API token is resolved in this order:

1. `GITHUB_TOKEN`
2. `GH_TOKEN`
3. `~/.copilot/config.json` → `copilot_tokens`
4. `git credential fill`

### Debug Logging

`statusline.ps1` has a top-level `$DebugLog` switch. It is currently **off by default**:

```powershell
$DebugLog = $false
```

When enabled, raw stdin payloads are appended to `statusline.stdin.log` next to the script.

## Payload Parameters

The header comment in `statusline.ps1` lists all known stdin payload fields and marks which ones are currently used.

## License

[MIT](LICENSE)
