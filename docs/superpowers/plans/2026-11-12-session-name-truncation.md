# Session Name Truncation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the `session_name` status-line segment to 50 Unicode text elements so long names do not commonly wrap the workspace row.

**Architecture:** Add one top-level configuration value and one focused truncation helper in `statusline.ps1`. The session-name resolver will first use the existing normalization helper, then truncate by .NET Unicode text-element boundaries before appending an ellipsis. Update README behavior and manual verification guidance in the same change.

**Tech Stack:** PowerShell 7, .NET `System.Globalization.StringInfo`, Git

---

## File Structure

- `statusline.ps1` — status-line configuration and session-name formatting.
- `README.md` — session-name behavior and manual test instructions.

### Task 1: Add Unicode-safe session-name truncation

**Files:**
- Modify: `statusline.ps1:17-34`
- Modify: `statusline.ps1:627-634`
- Test: manual PowerShell stdin payloads

- [ ] **Step 1: Run a boundary-case baseline**

Run from `D:\GITHUB\copilot-cli-statusline`:

```powershell
'{"session_name":"12345678901234567890123456789012345678901234567890","context_window":{"context_window_size":400000,"used_percentage":0}}' | pwsh -NoProfile -File .\statusline.ps1
'{"session_name":"123456789012345678901234567890123456789012345678901","context_window":{"context_window_size":400000,"used_percentage":0}}' | pwsh -NoProfile -File .\statusline.ps1
```

Expected: The 51-character name is currently emitted in full.

- [ ] **Step 2: Add the length configuration**

Add this value near the other top-level display configuration:

```powershell
$SessionNameMaxLength = 50
```

- [ ] **Step 3: Add the minimal Unicode-safe formatter**

Add a helper adjacent to `Get-SessionDisplayName` that:

```powershell
function Format-SessionDisplayName([string]$value) {
    $name = ConvertTo-SafeStatusText $value
    if (-not $name) { return $null }

    $textElements = [System.Globalization.StringInfo]::ParseCombiningCharacters($name)
    if ($textElements.Length -le $script:SessionNameMaxLength) { return $name }

    return $name.Substring(0, $textElements[$script:SessionNameMaxLength - 1]) + '…'
}
```

Update `Get-SessionDisplayName` to return `Format-SessionDisplayName ([string]$payload.session_name)` rather than returning raw input.

- [ ] **Step 4: Run boundary and Unicode tests**

Run:

```powershell
'{"session_name":"12345678901234567890123456789012345678901234567890","context_window":{"context_window_size":400000,"used_percentage":0}}' | pwsh -NoProfile -File .\statusline.ps1
'{"session_name":"123456789012345678901234567890123456789012345678901","context_window":{"context_window_size":400000,"used_percentage":0}}' | pwsh -NoProfile -File .\statusline.ps1
'{"session_name":"1234567890123456789012345678901234567890123456789é","context_window":{"context_window_size":400000,"used_percentage":0}}' | pwsh -NoProfile -File .\statusline.ps1
```

Expected: The 50-text-element name is unchanged; the 51-text-element name ends with `…` and contains 49 original text elements; the combining `é` remains intact and does not render as a detached mark.

- [ ] **Step 5: Commit the implementation**

```powershell
git add statusline.ps1
git commit -m "feat: truncate long session names"
```

### Task 2: Document truncation behavior

**Files:**
- Modify: `README.md:119-133`
- Modify: `README.md:290-301`

- [ ] **Step 1: Update the session-name documentation**

Replace the statement that session names are rendered exactly as supplied with wording that states:

- names are normalized as safe single-line status text;
- the default cap is 50 Unicode text elements;
- longer names use the first 49 text elements plus `…`;
- `$SessionNameMaxLength` can be adjusted near the top of `statusline.ps1`.

- [ ] **Step 2: Update manual testing documentation**

Add a long `session_name` payload example that demonstrates truncation, alongside the existing full-payload test.

- [ ] **Step 3: Re-run manual verification**

Run the full README sample, the over-limit session-name payload, the minimal payload, and empty stdin:

```powershell
'{"cwd":"D:\\TEST","session_name":"123456789012345678901234567890123456789012345678901","model":{"id":"gpt-5.4","display_name":"gpt-5.4 (high)"},"workspace":{"current_dir":"D:\\TEST"},"cost":{"total_duration_ms":3241747,"total_lines_added":100,"total_lines_removed":50,"total_premium_requests":5},"context_window":{"total_input_tokens":1744196,"total_output_tokens":26870,"total_cache_read_tokens":85000,"total_cache_write_tokens":12000,"total_reasoning_tokens":4200,"context_window_size":400000,"used_percentage":22}}' | pwsh -NoProfile -File .\statusline.ps1
'{"context_window":{"context_window_size":400000,"used_percentage":0}}' | pwsh -NoProfile -File .\statusline.ps1
echo $null | pwsh -NoProfile -File .\statusline.ps1
```

Expected: All commands complete without terminal errors; the full payload uses an ellipsis for its long name, while minimal and empty input still render their supported segments.

- [ ] **Step 4: Commit and push documentation**

```powershell
git add README.md
git commit -m "docs: describe session name truncation"
git push
```
