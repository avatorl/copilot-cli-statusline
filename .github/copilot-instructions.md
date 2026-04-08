# Copilot Instructions

## Project Overview

This is a single-script PowerShell project — `statusline.ps1` renders a two-line ANSI status bar for GitHub Copilot CLI. Copilot pipes a JSON payload to stdin on each refresh; the script parses it, fetches quota data from the GitHub API, and writes colored text to stdout.

`statusline.cmd` is a thin CMD wrapper that launches `pwsh.exe` with the script. It exists because Copilot CLI's `statusLine.command` config expects a `.cmd`/`.exe` on Windows.

The repository copy at `D:\GITHUB\copilot-cli-statusline` is the source of truth. Keep edits in this repo and do not mirror changes to `C:\Users\a\.copilot` or any other copy unless the user explicitly asks.

## Architecture

The script is a single-file pipeline with no module dependencies:

1. **Stdin → Parse** — `Get-OptionalStdin` reads piped JSON, `ConvertFrom-JsonObjectOrNull` parses it. Two payload shapes exist: minimal (context_window only, at session start) and full (all fields).
2. **Format** — Utility functions (`Format-CompactTokens`, `Format-DurationFromMilliseconds`, etc.) convert raw values to display strings. All rounding uses `[math]::Round` with explicit floating-point division — never integer arithmetic.
3. **Color** — Threshold-based ANSI coloring via `Get-TokenAnsiColor` and `Get-UsageAnsiColor`. Raw escape codes, no external module.
4. **Quota API** — Fetches `https://api.github.com/copilot_internal/user` with a token resolved from env vars → config.json → git credential store. Calculates quota vs. calendar pacing.
5. **Render** — Segments joined with dim pipe separators (`Join-StatusSegments`), two lines written to stdout.

All known stdin payload fields are documented in the header of `statusline.ps1` with ✅/○ markers showing which are used.

## Key Conventions

- **Pace labels are inverted by design**: "behind" (green) = under quota pace (good), "ahead" (red) = over pace (bad). Do not "fix" this — it's the intended UX.
- **`ConvertTo-NullableInt`** is the standard way to extract numeric values from the payload. It handles nulls, type coercion, and string parsing. Always use it instead of direct casts.
- **Null propagation**: Functions return `$null` for missing data. `Join-StatusSegments` filters out nulls/empty strings, so missing segments are silently omitted rather than causing errors.
- **UTF-8 without BOM** is forced at script start for Unicode block characters (█ ░) and emoji to render correctly.
- **No external modules** — the script must remain dependency-free. Use only .NET BCL and built-in PowerShell cmdlets.
- **README must stay in sync with script behavior**: whenever `statusline.ps1` changes output, labels, colors, bar semantics, quota logic, token handling, or testing instructions, update `README.md` in the same task before finishing.

## Testing

There is no test framework. To test manually:

```powershell
# Full payload
'{"cwd":"D:\\TEST","model":{"id":"gpt-5.4","display_name":"gpt-5.4 (high)"},"workspace":{"current_dir":"D:\\TEST"},"cost":{"total_duration_ms":3241747,"total_lines_added":100,"total_lines_removed":50,"total_premium_requests":5},"context_window":{"total_input_tokens":1744196,"total_output_tokens":26870,"context_window_size":400000,"used_percentage":22}}' | pwsh -NoProfile -File statusline.ps1

# Minimal payload (session start)
'{"context_window":{"context_window_size":400000,"used_percentage":0}}' | pwsh -NoProfile -File statusline.ps1

# Empty stdin
echo $null | pwsh -NoProfile -File statusline.ps1
```

Debug payloads are logged to `statusline.stdin.log` next to the script when `$DebugLog` is enabled. It is currently off by default.
