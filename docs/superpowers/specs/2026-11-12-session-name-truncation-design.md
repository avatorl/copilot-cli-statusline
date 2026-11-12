# Session Name Truncation Design

## Goal

Prevent long Copilot session names from causing the status line's workspace row to wrap.

## Design

Add a `$SessionNameMaxLength = 50` configuration value alongside the existing status-line layout settings. `Get-SessionDisplayName` will pass the payload's `session_name` through `ConvertTo-SafeStatusText`, then apply the limit only when the normalized name exceeds it.

Names of 50 or fewer Unicode text elements remain unchanged. A text element is a base character plus its combining marks, as identified by .NET's `StringInfo.ParseCombiningCharacters`; this prevents truncation from splitting a combined character or surrogate pair. Longer names are rendered as the first 49 text elements followed by a Unicode ellipsis (`…`), for a maximum of 50 text elements. Missing, whitespace-only, or control-character-only names continue to omit the segment.

The truncation is isolated to the `session_name` segment. It does not alter payload parsing, layout behavior, or any other status-line segment.

## Documentation and Validation

Update the README to state that session names are normalized and capped at 50 visible characters, with an ellipsis for truncation. Extend the manual test guidance to cover names below, at, and above the configured limit.

Validate the script by piping representative JSON payloads for all three boundary cases and confirming that the rendered name does not wrap or exceed the configured limit.
