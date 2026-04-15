# Copilot CLI Status Line

A Windows PowerShell status line for [GitHub Copilot CLI](https://docs.github.com/en/copilot/github-copilot-in-the-cli). It keeps the most useful session details visible in the terminal: model, context usage, token totals, session duration, premium requests, quota pace, current folder, session name, git repo/sync status, and lines changed.

![Windows](https://img.shields.io/badge/platform-Windows-blue)
![PowerShell 7+](https://img.shields.io/badge/PowerShell-7%2B-5391FE)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

<img width="1905" height="181" alt="Status line screenshot" src="./assets/readme-statusline.png" />

## Quick Start

### Requirements

- **Windows**
- **[PowerShell 7+](https://github.com/PowerShell/PowerShell/releases)** (`pwsh.exe`)
- **GitHub Copilot CLI** with the `STATUS_LINE` experimental flag enabled
- A terminal that supports ANSI color and Unicode block characters

### 1. Clone or copy the files

```bash
git clone https://github.com/avatorl/copilot-cli-statusline.git
```

You only need these two files at runtime:

```text
C:\Users\alex\.copilot\statusline\
├── statusline.ps1
└── statusline.cmd
```

### 2. Check `statusline.cmd`

The wrapper starts PowerShell and loads `statusline.ps1` from the same folder:

```cmd
@echo off
REM Adjust the path below if PowerShell 7 is installed elsewhere.
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
    "command": "C:\\Users\\alex\\.copilot\\statusline\\statusline.cmd"
  }
}
```

Use an absolute path and escape backslashes in JSON.

### 4. Restart Copilot CLI

Start a new Copilot CLI session. The status line should appear automatically.

## What the Default Status Line Shows

The script can render up to **three configurable lines**. By default it uses the first two and leaves the third line empty.

Typical layout using segment names:

```text
Line 1: model | context_bar | tokens | duration | premium_requests | quota
Line 2: path | lines_changed | session_name | repo_name git_sync
```

Rendered example with quota data available:

```text
gpt-5.4 (high) | [context bar] 22% 400K | in 1.7M out 27K cached 97K | 54m | 5/342 of 1500 p.req. | [quota calendar] 3.2d behind (160 p.req.)
D:\GITHUB\my-project | +100 -50 | Fix quota bar math | avatorl/copilot-cli-statusline 🟢 synced
```

Rendered example when quota lookup is unavailable:

```text
gpt-5.4 (high) | [context bar] 22% 400K | in 1.7M out 27K cached 97K | 54m | 5/? of ? p.req. | [quota calendar] 15/30
D:\GITHUB\my-project | +100 -50 | Fix quota bar math | avatorl/copilot-cli-statusline 🟢 synced
```

**Note:** bracketed labels such as `[context bar]` and `[quota calendar]` are readable stand-ins for the real Unicode/ANSI chart output used by the script.

### Line 1: session overview

| Segment | Meaning | Notes |
|---------|---------|-------|
| **Model** | The active model | Rendered in cyan |
| **Context usage** | How full the current context window is | Shows a 10-cell bar, rounded percent, and window size |
| **Tokens** | Total input, output, and cached tokens so far | `cached` = cache reads + cache writes |
| **Duration** | How long the session has been running | Hidden under 30 seconds |
| **Premium requests** | `session/month-used of quota p.req.` | Session count, monthly used count, and monthly quota in one compact segment |
| **Quota pace** | Whether you are under, on, or over monthly quota pace | Uses a compact month-shaped calendar |

### Line 2: workspace overview

| Segment | Meaning | Notes |
|---------|---------|-------|
| **Path** | Current working folder | Uses `cwd`, then `workspace.current_dir`, then `Get-Location` |
| **Lines changed** | Added and removed lines in this session | Green `+N`, bright red `-N` |
| **Session name** | Copilot's human-readable session title | Rendered exactly as Copilot sends it |
| **Repo name** | Git remote path from `origin` | Shows `owner/repo`; hidden when the folder is not a git repo or `origin` is missing |
| **Git sync** | Whether the current branch matches its local tracking ref and whether the working tree is dirty | Rendered immediately after repo name with no pipe separator; green `🟢 synced`, dim grey `⚪ ahead N`, `⚪ behind N`, `⚪ diverged A/B`, or `⚪ no upstream`, with `dirty` appended when local edits, staged changes, or untracked files exist; hidden outside git repos. Tracking refs refresh in the background when stale, so the status line does not pause on network calls |

### Line 3: optional

Line 3 is empty by default. You can move any supported segment there if you want more space.

## Understanding Premium Request Numbers

The premium request display is the easiest part to misread:

- `5/342 of 1500 p.req.` means **5 premium requests in this session**, **342 used this month**, and **1500 available for the month**
- The **left** number comes from the Copilot CLI session payload: `cost.total_premium_requests`
- The **middle** number comes from the live GitHub Copilot quota API and shows monthly used requests
- The **`of`** number comes from the same quota API and shows the monthly entitlement

That means the session count and monthly values can move independently.

Examples:

- `5/342 of 1500 p.req.` — all values are available
- `5/? of ? p.req.` — session count is available, monthly quota lookup failed
- `?/342 of 1500 p.req.` — session payload does not include the session count yet, but quota lookup succeeded

## Understanding the Quota Pace Bar

The quota segment compares **how much of the month has passed** with **how much premium quota you have used**.

- **behind** = under quota pace (**good**)
- **on pace** = close to target
- **ahead** = over quota pace (**bad**)

Legend:

| Symbol | Meaning |
|--------|---------|
| `█` | Past day outside the pace deviation |
| Green `█` | Behind-pace spillover into earlier days |
| `▓` | Today |
| Red `░` | Ahead-of-pace spillover into future days |
| `░` | Future day outside the pace deviation |
| `🔴 quota exceeded` | Monthly quota is at or above 100% |

If the quota API returns a monthly entitlement, the pace label also includes an estimated premium-request hint such as `(381 p.req.)`.

- For **behind**, that hint is how many premium requests you are still under pace by
- For **ahead**, that hint is how many premium requests you are over pace by

If quota lookup is unavailable, the script falls back to a dim `day/month` indicator after the calendar.

## Customizing the Layout

At the top of `statusline.ps1`, edit these arrays:

```powershell
$Line1Layout = @(
    'model'
    'context_bar'
    'tokens'
    'duration'
    'premium_requests'
    'quota'
)

$Line2Layout = @(
    'path'
    'lines_changed'
    'session_name'
    'repo_name'
    'git_sync'
)

$Line3Layout = @(
)
```

You can also tune background git refresh near the top of the script:

```powershell
$GitFetchRefreshSeconds = 300
$GitFetchLockTimeoutSeconds = 600
```

- `GitFetchRefreshSeconds` = how often `git_sync` may refresh tracking refs for a repo
- `GitFetchLockTimeoutSeconds` = when to treat an old background-fetch lock as stale

You can:

- remove a segment to hide it
- reorder entries to change display order
- move a segment between lines
- keep `$Line3Layout` empty to suppress the third line

### Available segment names

| Segment name | Default line | What it shows |
|--------------|--------------|---------------|
| `model` | 1 | Active model name |
| `context_bar` | 1 | Context usage bar, percent, and size |
| `tokens` | 1 | Input, output, and cached token totals |
| `duration` | 1 | Session wall-clock time |
| `premium_requests` | 1 | Session/month-used of quota premium requests |
| `premium_requests_month` | 1 | Monthly premium requests used out of total |
| `quota` | 1 | Monthly quota pacing indicator |
| `path` | 2 | Current working directory |
| `session_name` | 2 | Copilot session name |
| `repo_name` | 2 | Git remote owner/repo from `origin` |
| `git_sync` | 2 | Local tracking-ref sync state with optional dirty suffix (`🟢 synced`, `⚪ ahead N`, `⚪ behind N`, `⚪ diverged A/B`, `⚪ no upstream`, each optionally ending in `dirty`) |
| `lines_changed` | 2 | Added and removed lines |

If `premium_requests`, `premium_requests_month`, and `quota` are all removed from every layout, the script skips the quota API call entirely.

## Color Rules

| Area | Rule |
|------|------|
| Context bar | Green under 75%, yellow at 75%+, red at 90%+ |
| Unused context cells | Dim grey |
| Token values | Bright yellow at 10K+, yellow at 100K+, bright red at 1M+, red at 10M+ |
| `cached` token value | Uses the default text color |
| Quota pace | Green behind, white on pace, red ahead |
| Lines changed | Added lines are green; removed lines are bright red |
| Git sync | Green for `🟢 synced`; dim grey for `⚪ ahead N`, `⚪ behind N`, `⚪ diverged A/B`, `⚪ no upstream`, and the `dirty` suffix |

## Local Testing

There is no automated test suite. Test by piping sample payloads into `statusline.ps1`.

```powershell
# Full payload
'{"cwd":"D:\\TEST","session_name":"Fix quota bar math","model":{"id":"gpt-5.4","display_name":"gpt-5.4 (high)"},"workspace":{"current_dir":"D:\\TEST"},"cost":{"total_duration_ms":3241747,"total_lines_added":100,"total_lines_removed":50,"total_premium_requests":5},"context_window":{"total_input_tokens":1744196,"total_output_tokens":26870,"total_cache_read_tokens":85000,"total_cache_write_tokens":12000,"context_window_size":400000,"used_percentage":22}}' | pwsh -NoProfile -File .\statusline.ps1

# Minimal payload
'{"context_window":{"context_window_size":400000,"used_percentage":0}}' | pwsh -NoProfile -File .\statusline.ps1

# Empty stdin
echo $null | pwsh -NoProfile -File .\statusline.ps1
```

**Important:** those sample JSON payloads only control the session-side values. If the script can reach the quota API, the monthly premium-request count and quota pace still reflect your real account.

## How Quota Lookup Works

Quota-based segments use `https://api.github.com/copilot_internal/user`.

The script looks for a token in this order:

1. `COPILOT_GITHUB_TOKEN`
2. `GH_TOKEN`
3. `GITHUB_TOKEN`
4. `~/.copilot/config.json` → `copilot_tokens`
5. `gh auth token`

Notes:

- Quota lookup is optional. The rest of the status line still works without it.
- Quota-based segments can still render even when the session payload is minimal or empty, because they come from the live quota API.
- `repo_name` is resolved locally with `git remote get-url origin`, using `workspace.current_dir` when available.
- `git_sync` is resolved with `git status --porcelain=2 --branch`, using `workspace.current_dir` when available.
- When `git_sync` is enabled and the repo has an upstream, the script may start a detached `git fetch --quiet --no-tags --prune` when cached tracking refs are stale. The current render still uses local data immediately.
- The script does **not** read Windows Credential Manager directly.
- `gh auth token` is used as a fallback when available.

## Fast Git-Backed Ideas

These are the low-cost git signals that fit the current fast-refresh goal:

| Idea | Best local git source | Why it is fast |
|------|------------------------|----------------|
| `repo_name` | `git remote get-url origin` | Single local config lookup |
| `git_sync` | Background `git fetch --quiet --no-tags --prune` + `git status --porcelain=2 --branch` | Uses local status immediately and refreshes tracking refs asynchronously when stale |
| `git_branch` | `git status --porcelain=2 --branch` | Same snapshot as `git_sync` |
| `git_dirty` | `git status --porcelain=2 --branch` | Same snapshot as `git_sync`; can detect staged/unstaged/untracked state |
| `git_sha` | `git rev-parse --short HEAD` | Cheap local ref lookup |
| `git_root` | `git rev-parse --show-toplevel` | Cheap local repo-root lookup |

### What `git_sync` means

- `🟢 synced` means the current branch matches its **local tracking ref**
- `🟢 synced dirty` means the branch matches its local tracking ref, but the working tree has local edits, staged changes, or untracked files
- `⚪ ahead 2` means the branch is ahead of the local tracking ref by 2 commits
- `⚪ behind 3` means the branch is behind the local tracking ref by 3 commits
- `⚪ diverged 2/3` means the branch is both ahead and behind
- `⚪ no upstream` means no tracking branch is configured
- Any non-green state can also end in `dirty` when the working tree is not clean

**Important:** `🟢 synced` still does **not** mean "guaranteed current on GitHub right now." The script refreshes tracking refs in the background on a repo-based timer, not on every status-line refresh, and it does not call `git ls-remote` or the GitHub API.

## Debug Logging

`statusline.ps1` includes a top-level switch:

```powershell
$DebugLog = $false
```

When enabled, raw stdin payloads are appended to `statusline.stdin.log` next to the script.

## Payload Fields Used by the Script

Copilot CLI sends a JSON payload to stdin on each refresh. Two payload shapes are common:

- **Minimal payload**: usually just `context_window` when a session starts
- **Full payload**: includes model, workspace, cost, and context fields

`Used now` shows whether the current script reads that field:

- **✅** = currently used
- **○** = available in the payload but not currently used

### Top-level fields

| Field | Type | Used now | Meaning |
|-------|------|----------|---------|
| `cwd` | `string` | ✅ | Current working directory |
| `session_id` | `string` | ○ | Unique session identifier |
| `session_name` | `string` | ✅ | Human-readable session name |
| `transcript_path` | `string` | ○ | Path to the session transcript folder |
| `version` | `string` | ○ | Copilot CLI version |

### `model`

| Field | Type | Used now | Meaning |
|-------|------|----------|---------|
| `model.id` | `string` | ✅ | Model identifier such as `gpt-5.4` |
| `model.display_name` | `string` | ✅ | Friendly display name |

### `workspace`

| Field | Type | Used now | Meaning |
|-------|------|----------|---------|
| `workspace.current_dir` | `string` | ✅ | Workspace root directory |

### `cost`

| Field | Type | Used now | Meaning |
|-------|------|----------|---------|
| `cost.total_api_duration_ms` | `int` | ○ | Cumulative API call time in milliseconds |
| `cost.total_lines_added` | `int` | ✅ | Total lines added in this session |
| `cost.total_lines_removed` | `int` | ✅ | Total lines removed in this session |
| `cost.total_duration_ms` | `int` | ✅ | Total session wall-clock time in milliseconds |
| `cost.total_premium_requests` | `int` | ✅ | Premium request count for this session |

### `context_window`

| Field | Type | Used now | Meaning |
|-------|------|----------|---------|
| `context_window.total_input_tokens` | `int` | ✅ | Cumulative input tokens |
| `context_window.total_output_tokens` | `int` | ✅ | Cumulative output tokens |
| `context_window.total_cache_read_tokens` | `int` | ✅ | Tokens served from cache |
| `context_window.total_cache_write_tokens` | `int` | ✅ | Tokens written to cache |
| `context_window.total_tokens` | `int` | ○ | Sum of input and output tokens |
| `context_window.context_window_size` | `int` | ✅ | Max context window size |
| `context_window.used_percentage` | `int` | ✅ | Percent of context window used |
| `context_window.remaining_percentage` | `int` | ○ | Percent of context window free |
| `context_window.remaining_tokens` | `int` | ○ | Tokens still available |
| `context_window.last_call_input_tokens` | `int` | ○ | Input tokens in the last call |
| `context_window.last_call_output_tokens` | `int` | ○ | Output tokens in the last call |

### `context_window.current_usage`

| Field | Type | Used now | Meaning |
|-------|------|----------|---------|
| `context_window.current_usage.input_tokens` | `int` | ○ | Raw input tokens used |
| `context_window.current_usage.output_tokens` | `int` | ○ | Raw output tokens used |
| `context_window.current_usage.cache_creation_input_tokens` | `int` | ○ | Cache creation tokens |
| `context_window.current_usage.cache_read_input_tokens` | `int` | ○ | Cache read tokens |

### External API used by the script

| Source | Used now | Meaning |
|--------|----------|---------|
| `quota_snapshots.premium_interactions.percent_remaining` | ✅ | Remaining premium quota percentage |
| `quota_snapshots.premium_interactions.entitlement` | ✅ | Monthly premium request budget used for monthly totals and pace hints |

## License

[MIT](LICENSE)
