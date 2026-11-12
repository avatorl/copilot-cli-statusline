# Session Name Truncation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dynamically fit the `session_name` segment into the remaining terminal columns on its status-line row, with a 50-text-element fallback when width is unavailable.

**Architecture:** Keep `Get-SessionDisplayName` responsible only for safe text normalization. Build the line-two segments first, calculate terminal-cell widths after stripping ANSI CSI SGR sequences, and use the remaining columns to truncate only the session-name segment at Unicode text-element boundaries. Preserve the 50-text-element setting as the fallback when no positive console width is available.

**Tech Stack:** PowerShell 7, .NET `System.Globalization.StringInfo`, Git

---

## File Structure

- `statusline.ps1` — status-line configuration and session-name formatting.
- `README.md` — session-name behavior and manual test instructions.

### Task 1: Add terminal-width-aware session-name fitting

**Files:**
- Modify: `statusline.ps1:17-34`
- Modify: `statusline.ps1:625-665`
- Modify: `statusline.ps1:1150-1175`
- Test: manual PowerShell stdin payloads

- [ ] **Step 1: Run a long-name baseline**

Run from `D:\GITHUB\copilot-cli-statusline`:

```powershell
'{"session_name":"123456789012345678901234567890123456789012345678901","context_window":{"context_window_size":400000,"used_percentage":0}}' | pwsh -NoProfile -File .\statusline.ps1
```

Expected: The current fixed-cap implementation shortens the name without considering the available terminal columns.

- [ ] **Step 2: Preserve the fallback configuration**

Keep this value near the other top-level display configuration and document it in a nearby comment as the width-unavailable fallback:

```powershell
$SessionNameMaxLength = 50
```

- [ ] **Step 3: Add ANSI-safe terminal-cell measurement helpers**

Add focused helpers adjacent to `ConvertTo-SafeStatusText` that:

```powershell
function Get-StatusLineWindowWidth {
    try {
        $width = [Console]::WindowWidth
        if ($width -gt 0) { return $width }
    } catch {}
    return $null
}
```

Implement the supporting helpers to:

- remove ANSI CSI SGR sequences before measurement;
- enumerate text elements with `StringInfo.ParseCombiningCharacters`;
- count controls/combining marks as 0 columns, East Asian wide/full-width characters and emoji as 2, all others as 1, and an emoji-containing text element as 2;
- calculate a string's total terminal-cell width;
- return the longest prefix of complete text elements that fits a supplied cell budget, reserving 1 column for `…` when truncation is needed.
- add a separate text-element fallback helper: a value longer than `$SessionNameMaxLength` text elements uses the first `$SessionNameMaxLength - 1` text elements plus `…`. Do not treat the fallback as a terminal-cell budget.

Keep `Get-SessionDisplayName` limited to `ConvertTo-SafeStatusText`; do not truncate there.

- [ ] **Step 4: Integrate dynamic fitting into line construction**

Revise `Build-StatusLine` so that, when the layout contains `session_name`:

- it resolves all segments first;
- it constructs the candidate list from non-empty segments only, using the normalized session name;
- it calculates the width of fixed segments plus exactly the separators `Join-StatusSegments` would render between those non-empty segments, including the separator beside the session name;
- it uses a positive `[Console]::WindowWidth` to derive the session-name column budget, otherwise the separate `$SessionNameMaxLength` text-element fallback;
- it replaces the session name with a fitted value, or removes that segment when no columns remain;
- it finally delegates the rendered segment list to `Join-StatusSegments`.

Do not change other segment text, layout settings, or separator rendering.

- [ ] **Step 5: Run focused manual verification**

Run long ASCII, combining-character, CJK, and emoji payloads through `statusline.ps1`, plus minimal and empty input. In an interactive terminal, resize the terminal narrow and wide, then confirm:

- the name grows on wider terminals;
- the name shortens with `…` on narrow terminals;
- combining characters, CJK, and emoji sequences are not split;
- fixed segments and separators are included in the budget;
- no session-name segment is emitted when no columns remain;
- noninteractive or unavailable width uses the 50-text-element fallback.

For deterministic width behavior, make the fitting helper accept an explicit nullable column-budget parameter. Invoke it with controlled zero, one-column, narrow, wide, and `$null` values from a `pwsh -NoProfile -Command` harness after dot-sourcing the script. Verify zero omits the segment and one renders only `…`. Production line construction passes the actual console-derived budget.

Also run:

```powershell
git diff --check
```

- [ ] **Step 6: Commit the implementation**

```powershell
git add statusline.ps1
git commit -m "feat: fit session names to terminal width"
```

### Task 2: Document truncation behavior

**Files:**
- Modify: `README.md:119-133`
- Modify: `README.md:280-300`

- [ ] **Step 1: Update the session-name documentation**

Replace the fixed-cap wording with behavior that states:

- names are normalized as safe single-line status text;
- names are dynamically fitted to the terminal's remaining columns after other line-two segments and separators;
- longer names use `…` without splitting Unicode text elements;
- `$SessionNameMaxLength` is the fallback cap when the terminal width is unavailable.

- [ ] **Step 2: Update manual testing documentation**

Add a long `session_name` payload example that demonstrates truncation, alongside the existing full-payload test.

- [ ] **Step 3: Re-run manual verification**

Run the full README sample, the over-limit session-name payload, the minimal payload, and empty stdin:

```powershell
'{"cwd":"D:\\TEST","session_name":"123456789012345678901234567890123456789012345678901","model":{"id":"gpt-5.4","display_name":"gpt-5.4 (high)"},"workspace":{"current_dir":"D:\\TEST"},"cost":{"total_duration_ms":3241747,"total_lines_added":100,"total_lines_removed":50,"total_premium_requests":5},"context_window":{"total_input_tokens":1744196,"total_output_tokens":26870,"total_cache_read_tokens":85000,"total_cache_write_tokens":12000,"total_reasoning_tokens":4200,"context_window_size":400000,"used_percentage":22}}' | pwsh -NoProfile -File .\statusline.ps1
'{"context_window":{"context_window_size":400000,"used_percentage":0}}' | pwsh -NoProfile -File .\statusline.ps1
echo $null | pwsh -NoProfile -File .\statusline.ps1
```

Expected: All commands complete without terminal errors; interactive renders fit the session name to their terminal width, while noninteractive renders use the fallback cap; minimal and empty input still render their supported segments.

- [ ] **Step 4: Commit and push documentation**

```powershell
git add README.md
git commit -m "docs: describe session name truncation"
git push
```
