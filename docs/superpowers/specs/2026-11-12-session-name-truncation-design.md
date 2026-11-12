# Session Name Truncation Design

## Goal

Prevent long Copilot session names from causing the status line's workspace row to wrap while preserving more of the name on wider terminals.

## Design

Keep `$SessionNameMaxLength = 50` alongside the existing status-line layout settings as a fallback for hosts whose terminal width is unavailable. `Get-SessionDisplayName` will normalize the payload's `session_name` with `ConvertTo-SafeStatusText`, without applying a fixed truncation limit.

When building a line that contains `session_name`, resolve its other segments first. Remove ANSI CSI SGR escape sequences from their rendered output and calculate their terminal-cell widths. Form the complete candidate line by including every non-empty segment and every separator that `Join-StatusSegments` would render, including the separator adjacent to `session_name`; subtract the candidate's non-session width from `[Console]::WindowWidth`. The remaining column budget determines the session-name content length. The current session segment has no additional prefix or suffix; if one is added in future, its rendered width must also be reserved before truncation. A missing, zero, or negative window width is unavailable and falls back to `$SessionNameMaxLength`.

Terminal-cell width follows a compact `wcwidth`-style policy: controls and combining marks occupy zero columns; East Asian wide/full-width characters and emoji occupy two columns; all other characters, including East Asian ambiguous-width characters, occupy one column. .NET's `StringInfo.ParseCombiningCharacters` defines the atomic extended-grapheme boundaries used for truncation, covering ZWJ, flag, keycap, and modifier sequences. A text element containing an emoji is measured as two columns. This policy applies to both fixed segments and the session name.

Names that fit within the available budget remain unchanged. Longer names use as many complete Unicode text elements as will fit, reserving one terminal column for a Unicode ellipsis (`…`). A text element is a base character plus its combining marks, as identified by .NET's `StringInfo.ParseCombiningCharacters`; this prevents truncation from splitting a combined character or surrogate pair. If no session-name space remains, omit the segment; if only one column remains, render only the ellipsis. When the fallback is used, the limit includes the ellipsis: names longer than 50 text elements render as the first 49 text elements plus `…`.

The dynamic calculation is isolated to status-line rendering. It does not alter payload parsing or the content of any other segment.

## Documentation and Validation

Update the README to state that session names are normalized, dynamically fitted to the terminal's available width, and use the 50-text-element setting only when that width is unavailable. Extend manual test guidance to cover a narrow terminal, a wide terminal, the unavailable-width fallback, combined text, CJK, and emoji.

Validate the script by piping representative JSON payloads in narrow and wide terminal contexts, plus the unavailable-width fallback, and confirm the rendered name stays within its computed budget.
