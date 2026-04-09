# ─── Configuration ────────────────────────────────────────────────────────────
# Set to $true to log raw stdin JSON to statusline.stdin.log (for debugging).
$DebugLog = $false

# ─── Status Line Layout ───────────────────────────────────────────────────────
# Define which segments appear on each output line and in what order.
# Remove or comment out any name to hide that segment.
#
# Line 1 segment names:
#   model              - Active model name
#   context_bar        - Context-window usage bar and percentage
#   tokens             - Cumulative input / output token counts
#   duration           - Total session wall-clock time
#   premium_requests   - Premium request count (p.req.)
#   quota              - Monthly quota pacing bar (fetches GitHub API)
#
# Line 2 segment names:
#   path               - Current workspace / working directory
#   session_name       - Human-readable Copilot session name
#   lines_changed      - Lines added / removed this session (+N -N)
#
# Line 3 segment names:
#   (empty by default — add any segment names you want on a third line)
#
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
)

$Line3Layout = @(
)
# ─────────────────────────────────────────────────────────────────────────────

# Copilot CLI Status Line Script (Windows PowerShell)
#
# Renders up to three configurable status lines from Copilot's JSON payload piped to stdin.
#
# LINE 1: model | context bar % size | in/out/cached tokens | duration | p.req. | quota pace
#         (configurable — see $Line1Layout above)
# LINE 2: cwd path | +lines -lines | session name
#         (configurable — see $Line2Layout above)
# LINE 3: disabled by default
#         (configurable — see $Line3Layout above)
#
# The full stdin payload field reference lives in README.md.

# ─── UTF-8 Encoding ──────────────────────────────────────────────────────────
# Force UTF-8 so the status line runner preserves block characters and emoji.
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

# ─── ANSI Colors ─────────────────────────────────────────────────────────────
$esc = [char]27
$rst = "$esc[0m" # resets color back to default for the subsequent text

# Standard colors (30-37)
# $black = "$esc[30m"
$red = "$esc[31m"
$green = "$esc[32m"
$yellow = "$esc[33m"
# $blue = "$esc[34m"
# $magenta = "$esc[35m"
$cyan = "$esc[36m"
# $white = "$esc[37m"

# Bright/intense colors (90-97)
$dim = "$esc[90m"                          # Bright Black (dark grey)
$brightRed = "$esc[91m"
# $brightGreen = "$esc[92m"
$brightYellow = "$esc[93m"
# $brightBlue = "$esc[94m"
# $brightMagenta = "$esc[95m"
# $brightCyan = "$esc[96m"
$white = "$esc[97m"                        # Bright White

$segmentSeparator = " $dim|$rst "

# ─── Bar Characters ──────────────────────────────────────────────────────────
$filledChar = "█"
$hatchedChar = "░"
$darkShadeChar = "▓"

# ─── Pace Display Labels ─────────────────────────────────────────────────────
# "behind" = under quota pace (good), "ahead" = over quota pace (bad)
$behindText  = "behind"
$onPaceText  = "on pace"
$aheadText   = "ahead"
$behindColor = $green
$onPaceColor = $white   # neutral/informational; white is visually calm
$aheadColor  = $red

# ─── Debug Logging ───────────────────────────────────────────────────────────
$scriptDirectory = Split-Path -Parent $PSCommandPath
$stdinLogPath = Join-Path $scriptDirectory "statusline.stdin.log"

# ═════════════════════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# ═════════════════════════════════════════════════════════════════════════════

# Reads all redirected stdin; returns $null when run directly (no pipe).
function Get-OptionalStdin {
    if ([Console]::IsInputRedirected) {
        try { return [Console]::In.ReadToEnd() } catch { return $null }
    }
    return $null
}

# Parses stdin as JSON object; returns $null for invalid/non-object input.
function ConvertFrom-JsonObjectOrNull([string]$raw) {
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    try {
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($parsed -is [System.Management.Automation.PSCustomObject]) { return $parsed }
    } catch {}
    return $null
}

# Appends timestamped raw stdin to a log file when debug logging is enabled.
function Write-StdinLog([string]$raw) {
    if (-not $script:DebugLog) { return }
    if ([string]::IsNullOrWhiteSpace($raw)) { return }
    try {
        $timestamp = (Get-Date).ToString("s")
        Add-Content -Path $stdinLogPath -Value @("===== $timestamp =====", $raw, "") -Encoding utf8
    } catch {}
}

# Coerces any numeric type, string, or bool to [int]; returns $null on failure.
function ConvertTo-NullableInt($value) {
    if ($null -eq $value) { return $null }
    if ($value -is [bool]) { return [int]$value }
    if ($value -is [byte] -or $value -is [sbyte] -or
        $value -is [int16] -or $value -is [uint16] -or
        $value -is [int32] -or $value -is [uint32] -or
        $value -is [int64] -or $value -is [uint64]) { return [int]$value }
    if ($value -is [single] -or $value -is [double] -or $value -is [decimal]) { return [int]$value }
    $text = [string]$value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    $number = 0.0
    if ([double]::TryParse($text, [System.Globalization.NumberStyles]::Float,
        [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number)) { return [int]$number }
    return $null
}

# ═════════════════════════════════════════════════════════════════════════════
# FORMATTING FUNCTIONS
# ═════════════════════════════════════════════════════════════════════════════

# Formats token counts compactly: ≥1M → "1.7M", ≥1K → "27K", <1K → "0.7K".
# Uses [math]::Round for correct midpoint rounding.
function Format-CompactTokens($value) {
    $number = ConvertTo-NullableInt $value
    if ($null -eq $number) { return "-" }

    $negative = $number -lt 0
    $absolute = [math]::Abs($number)

    if ($absolute -ge 1000000) {
        $formatted = "$([math]::Round($absolute / 1000000.0, 1))M"
    } elseif ($absolute -ge 1000) {
        $formatted = "$([math]::Round($absolute / 1000.0, 0))K"
    } else {
        $formatted = "$([math]::Round($absolute / 1000.0, 1))K"
    }

    if ($negative) { return "-$formatted" }
    return $formatted
}

# Formats a percentage as a whole number (e.g. 76.5 → "77%").
function Format-PercentDisplay($value) {
    if ($null -eq $value) { return "-" }
    return "$([math]::Round([double]$value))%"
}

# Formats milliseconds as "Xd Xh Xm", rounding to the nearest whole minute.
# Sessions under 30 seconds return empty (not displayed).
function Format-DurationFromMilliseconds($value) {
    $milliseconds = ConvertTo-NullableInt $value
    if ($null -eq $milliseconds) { return $null }

    $totalSeconds = [math]::Max(0, [int][math]::Floor($milliseconds / 1000))
    $totalMinutes = [int][math]::Floor($totalSeconds / 60)

    # Round up if remaining seconds ≥ 30
    if (($totalSeconds % 60) -ge 30) { $totalMinutes++ }

    $days = [int][math]::Floor($totalMinutes / 1440)
    $hours = [int][math]::Floor(($totalMinutes % 1440) / 60)
    $minutes = $totalMinutes % 60

    $parts = @()
    if ($days -gt 0) { $parts += "${days}d" }
    if ($hours -gt 0 -or $parts.Count -gt 0) { $parts += "${hours}h" }
    if ($minutes -gt 0 -or $parts.Count -gt 0) { $parts += "${minutes}m" }
    return [string]::Join(" ", $parts)
}

# ═════════════════════════════════════════════════════════════════════════════
# COLOR FUNCTIONS
# ═════════════════════════════════════════════════════════════════════════════

# Returns ANSI color based on token count thresholds: ≥10M red, ≥1M bright red, ≥100K yellow, ≥10K bright yellow.
function Get-TokenAnsiColor($value) {
    $number = ConvertTo-NullableInt $value
    if ($null -eq $number) { return $null }
    if ($number -ge 10000000) { return $red }
    if ($number -ge 1000000) { return $brightRed }
    if ($number -ge 100000) { return $yellow }
    if ($number -ge 10000) { return $brightYellow }
    return $null
}

# Returns ANSI color for percentage: ≥90% red, ≥75% yellow, otherwise green.
function Get-UsageAnsiColor($value) {
    $number = ConvertTo-NullableInt $value
    if ($null -eq $number) { return $green }
    if ($number -ge 90) { return $red }
    if ($number -ge 75) { return $yellow }
    return $green
}

# ═════════════════════════════════════════════════════════════════════════════
# DISPLAY COMPONENT FUNCTIONS
# ═════════════════════════════════════════════════════════════════════════════

# Formats a token value with prefix, coloring the prefix dim and the value based on thresholds (e.g. "in 2.3M" where "in" is dim).
# Special case: "cached" values use default color (no coloring).
function Format-ColoredToken([string]$prefix, $value) {
    $number = ConvertTo-NullableInt $value
    if ($null -eq $number) { return $null }
    $formattedValue = Format-CompactTokens $number
    $coloredPrefix = "$script:dim$prefix$rst"
    
    # "cached" values use default color (same as duration/p.req.)
    if ($prefix -eq "cached") { return "$coloredPrefix $formattedValue" }
    
    $color = Get-TokenAnsiColor $number
    if ($color) { return "$coloredPrefix $color$formattedValue$rst" }
    return "$coloredPrefix $formattedValue"
}

# Renders a fixed-width 10-char bar chart from a percentage (0–100).
# Works in double precision to avoid int-coercion rounding before the fill calculation.
# Filled portion uses the provided color; unfilled portion is dim grey.
function Get-Bar($value, [string]$ansiColor, [int]$width = 10) {
    # Clamp to [0, 100] without int coercion so fractional percentages round correctly.
    $pct    = if ($null -ne $value) { [math]::Max(0.0, [math]::Min(100.0, [double]$value)) } else { 0.0 }
    # AwayFromZero: 2.5 → 3, 2.4 → 2 (round-half-up for bar charts)
    $filled = [math]::Min($width, [int][math]::Round($pct / 100.0 * $width, [System.MidpointRounding]::AwayFromZero))
    $empty  = $width - $filled

    $filledPart = if ($filled -gt 0) { $script:filledChar * $filled } else { "" }
    $emptyPart  = if ($empty  -gt 0) { $script:filledChar * $empty  } else { "" }
    return "$ansiColor$filledPart$rst$script:dim$emptyPart$rst"
}

# Joins non-empty segments with dim pipe separators.
function Join-StatusSegments([object[]]$segments) {
    $clean = New-Object System.Collections.Generic.List[string]
    foreach ($segment in $segments) {
        if ($null -eq $segment) { continue }
        $text = [string]$segment
        if (-not [string]::IsNullOrWhiteSpace($text)) { $clean.Add($text) }
    }
    return [string]::Join($segmentSeparator, $clean)
}

# ═════════════════════════════════════════════════════════════════════════════
# PAYLOAD EXTRACTION FUNCTIONS
# ═════════════════════════════════════════════════════════════════════════════

# Extracts cwd from payload, falling back to workspace.current_dir then Get-Location.
function Get-WorkspaceDisplayPath($payload) {
    $path = $null
    if ($payload -and $payload.cwd) { $path = [string]$payload.cwd }
    elseif ($payload -and $payload.workspace -and $payload.workspace.current_dir) {
        $path = [string]$payload.workspace.current_dir
    } else { $path = (Get-Location).Path }
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    return ($path -replace '/', '\')
}

# Returns the raw human-readable session name from session_name.
function Get-SessionDisplayName($payload) {
    if ($payload -and $payload.session_name) {
        $name = [string]$payload.session_name
        if (-not [string]::IsNullOrWhiteSpace($name)) { return $name }
    }
    return $null
}

# Returns model.display_name, falling back to model.id.
function Get-ModelDisplayName($payload) {
    if ($payload -and $payload.model) {
        if ($payload.model.display_name) { return [string]$payload.model.display_name }
        if ($payload.model.id) { return [string]$payload.model.id }
    }
    return $null
}

# Returns formatted premium request count from cost.total_premium_requests.
function Get-TotalPremiumRequests($payload) {
    if ($payload -and $payload.cost) {
        $requests = ConvertTo-NullableInt $payload.cost.total_premium_requests
        if ($null -ne $requests) { return $requests }
    }
    return $null
}

# Returns formatted duration string from cost.total_duration_ms.
function Get-TotalDurationDisplay($payload) {
    if ($payload -and $payload.cost) {
        return Format-DurationFromMilliseconds $payload.cost.total_duration_ms
    }
    return $null
}

# Builds context usage segment for line 1: colored/grey bars + "23% 400K".
function Get-ContextUsageSegment($payload) {
    if ($null -eq $payload -or $null -eq $payload.context_window) { return $null }

    $usedPct = ConvertTo-NullableInt $payload.context_window.used_percentage
    $windowSize = ConvertTo-NullableInt $payload.context_window.context_window_size
    if ($null -eq $usedPct -and $null -eq $windowSize) { return $null }

    $segments = New-Object System.Collections.Generic.List[string]
    if ($null -ne $usedPct) {
        $segments.Add((Get-Bar $usedPct (Get-UsageAnsiColor $usedPct)))
        $segments.Add((Format-PercentDisplay $usedPct))
    }
    if ($null -ne $windowSize) {
        $segments.Add((Format-CompactTokens $windowSize))
    }
    return [string]::Join(" ", $segments)
}

# Builds cumulative token segment for line 1: "in 2.3M out 29K cached 5K".
function Get-ContextSummary($payload) {
    if ($null -eq $payload -or $null -eq $payload.context_window) { return $null }

    $inputTokens = ConvertTo-NullableInt $payload.context_window.total_input_tokens
    $outputTokens = ConvertTo-NullableInt $payload.context_window.total_output_tokens
    if ($null -eq $inputTokens -and $null -eq $outputTokens) { return $null }

    $cacheRead = ConvertTo-NullableInt $payload.context_window.total_cache_read_tokens
    $cacheWrite = ConvertTo-NullableInt $payload.context_window.total_cache_write_tokens
    $cachedTokens = if ($null -ne $cacheRead -or $null -ne $cacheWrite) {
        ($cacheRead ?? 0) + ($cacheWrite ?? 0)
    } else { $null }

    $segments = New-Object System.Collections.Generic.List[string]
    $in = Format-ColoredToken "in" $inputTokens
    if ($in) { $segments.Add($in) }
    $out = Format-ColoredToken "out" $outputTokens
    if ($out) { $segments.Add($out) }
    $cached = Format-ColoredToken "cached" $cachedTokens
    if ($cached) { $segments.Add($cached) }
    return [string]::Join(" ", $segments)
}

# Returns green "+N" bright red "-N" from cost.total_lines_added/removed (standard terminal colors).
function Get-LinesChangedStats($payload) {
    if ($null -eq $payload -or $null -eq $payload.cost) { return $null }

    $added = ConvertTo-NullableInt $payload.cost.total_lines_added
    $removed = ConvertTo-NullableInt $payload.cost.total_lines_removed
    if (($null -eq $added -and $null -eq $removed) -or ($added -eq 0 -and $removed -eq 0)) {
        return $null
    }

    $addedStr = if ($null -ne $added) { "$green+$added$rst" } else { "$green+0$rst" }
    $removedStr = if ($null -ne $removed) { "$brightRed-$removed$rst" } else { "$brightRed-0$rst" }
    return "$addedStr $removedStr"
}

# Resolves a GitHub token from supported env vars, plaintext Copilot config, or gh CLI.
function Get-GitHubAccessToken {
    if ($env:COPILOT_GITHUB_TOKEN) { return $env:COPILOT_GITHUB_TOKEN }
    if ($env:GH_TOKEN) { return $env:GH_TOKEN }
    if ($env:GITHUB_TOKEN) { return $env:GITHUB_TOKEN }

    $copilotCfgPath = Join-Path $env:USERPROFILE ".copilot\config.json"
    if (Test-Path $copilotCfgPath) {
        try {
            $copilotCfg = Get-Content $copilotCfgPath -Raw | ConvertFrom-Json

            if ($copilotCfg.last_logged_in_user -and $copilotCfg.copilot_tokens) {
                $key = "$($copilotCfg.last_logged_in_user.host):$($copilotCfg.last_logged_in_user.login)"
                if ($copilotCfg.copilot_tokens.PSObject.Properties.Name -contains $key) {
                    $token = $copilotCfg.copilot_tokens.$key
                    if ($token) { return $token }
                }
            }

            if ($copilotCfg.copilot_tokens) {
                foreach ($property in $copilotCfg.copilot_tokens.PSObject.Properties) {
                    if ($property.Value) { return $property.Value }
                }
            }
        } catch {}
    }

    try {
        $gh = Get-Command gh -ErrorAction Stop
        $token = (& $gh.Source auth token 2>$null | Out-String).Trim()
        if (-not [string]::IsNullOrWhiteSpace($token)) { return $token }
    } catch {}

    return $null
}

# Queries the Copilot quota API; returns a PSCustomObject with UsedPct and Entitlement,
# or $null when the token is unavailable or the API call fails.
function Get-CopilotQuotaData {
    $token = Get-GitHubAccessToken
    if (-not $token) { return $null }

    try {
        $response = Invoke-RestMethod -Uri "https://api.github.com/copilot_internal/user" `
            -Headers @{ "Authorization" = "Bearer $token"; "Accept" = "application/json" } `
            -TimeoutSec 5 -ErrorAction Stop

        $snap = $response.quota_snapshots.premium_interactions
        # Guard: missing or non-numeric percent_remaining must not silently produce UsedPct=100.
        if ($null -eq $snap -or $null -eq $snap.percent_remaining) { return $null }

        $usedPct     = [math]::Round(100 - [double]$snap.percent_remaining, 1)
        $entitlement = if ($null -ne $snap.entitlement -and [double]$snap.entitlement -gt 0) {
            [int]$snap.entitlement
        } else { $null }

        return [PSCustomObject]@{ UsedPct = $usedPct; Entitlement = $entitlement }
    } catch {}

    return $null
}

# Builds the quota pace segment using a month-length calendar overlay.
#
# Bar layout (left→right, always exactly daysInMonth bars):
#   [grey-solid × todayIndex] [green-solid × pastGreenBars]
#   [pace-colored dark shade × 1 (today)] [red-hatched × futureRedBars] [grey-light × remaining]
#
# Pace is computed in fractional days, time-of-day aware. Rounding uses AwayFromZero
# so a deviation rounds to a visible bar only when it reaches 0.5 days of spillover.
# "Spillover" is the deviation that extends beyond today into past/future bar slots.
#
# Parameters:
#   $quotaData — [PSCustomObject]@{ UsedPct; Entitlement } or $null (API unavailable)
function Get-QuotaPaceSegment($quotaData) {
    $now         = Get-Date
    $daysInMonth = [DateTime]::DaysInMonth($now.Year, $now.Month)
    $todayIndex  = $now.Day - 1                        # count of bar slots before today (0-based)
    $todayFrac   = $now.TimeOfDay.TotalHours / 24.0    # 0.0 at midnight → ~1.0 at day end
    $futureCount = $daysInMonth - $now.Day             # count of bar slots after today

    $usedPct     = if ($quotaData) { $quotaData.UsedPct }     else { $null }
    $entitlement = if ($quotaData) { $quotaData.Entitlement } else { $null }

    # ── No data: show a dim calendar with dark-shade today and light future ──
    if ($null -eq $usedPct) {
        $cal = "$dim$($filledChar * $todayIndex)$darkShadeChar$($hatchedChar * $futureCount)$rst"
        return "$cal $dim$($now.Day)/$daysInMonth$rst"
    }

    # Fractional elapsed days since month start (includes partial current day).
    $elapsedFraction = $todayIndex + $todayFrac
    $monthPct        = $elapsedFraction / $daysInMonth * 100.0
    $diff            = [double]$usedPct - $monthPct          # positive = ahead, negative = behind
    $daysDelta       = $daysInMonth * [math]::Abs($diff) / 100.0

    # ── Exceeded: 100%+ quota consumed ───────────────────────────────────────
    if ($usedPct -ge 100) {
        $cal = "$dim$($filledChar * $todayIndex)$rst$red$darkShadeChar$($hatchedChar * $futureCount)$rst"
        return "$cal ${red}🔴 quota exceeded$rst"
    }

    # ── Ahead (over pace, bad): today absorbs the remaining fraction of the day;
    #    any excess spills into future slots as red hatched bars.
    if ($diff -gt 0) {
        $spillover = $daysDelta - (1.0 - $todayFrac)
        $barCount  = [int][math]::Round($spillover, [System.MidpointRounding]::AwayFromZero)
        if ($barCount -gt 0) {
            $futureRedBars = [math]::Min($barCount, $futureCount)
            
            # p.req. hint: requests that exceeded expected pace.
            $pReqHint = ""
            if ($null -ne $entitlement) {
                $pReq = [int][math]::Round($daysDelta / $daysInMonth * $entitlement, [System.MidpointRounding]::AwayFromZero)
                if ($pReq -gt 0) { $pReqHint = " ($pReq p.req.)" }
            }
            
            $cal = "$dim$($filledChar * $todayIndex)$rst$red$darkShadeChar$($hatchedChar * $futureRedBars)$rst$dim$($hatchedChar * ($futureCount - $futureRedBars))$rst"
            return "$cal $red$('{0:0.0}' -f $daysDelta)d $aheadText$pReqHint$rst"
        }
    }

    # ── Behind (under pace, good): today absorbs the elapsed fraction;
    #    any excess spills back into past slots as green solid bars.
    if ($diff -lt 0) {
        $spillover = $daysDelta - $todayFrac
        $barCount  = [int][math]::Round($spillover, [System.MidpointRounding]::AwayFromZero)
        if ($barCount -gt 0) {
            # Cap to available past slots; prevents bars before day 1.
            $pastGreenBars = [math]::Min($barCount, $todayIndex)

            # p.req. hint: requests that could have been consumed but weren't.
            $pReqHint = ""
            if ($null -ne $entitlement) {
                $pReq = [int][math]::Round($daysDelta / $daysInMonth * $entitlement, [System.MidpointRounding]::AwayFromZero)
                if ($pReq -gt 0) { $pReqHint = " ($pReq p.req.)" }
            }

            $cal = "$dim$($filledChar * ($todayIndex - $pastGreenBars))$rst$green$($filledChar * $pastGreenBars)$darkShadeChar$rst$dim$($hatchedChar * $futureCount)$rst"
            return "$cal $green$('{0:0.0}' -f $daysDelta)d $behindText$pReqHint$rst"
        }
    }

    # ── On pace: deviation rounds to zero bars — within half a day of target.
    $cal = "$dim$($filledChar * $todayIndex)$rst$white$darkShadeChar$rst$dim$($hatchedChar * $futureCount)$rst"
    return "$cal $white$onPaceText$rst"
}

# ═════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═════════════════════════════════════════════════════════════════════════════

# Read and log the raw stdin payload.
$rawStdin = Get-OptionalStdin
Write-StdinLog $rawStdin
$contextPayload = ConvertFrom-JsonObjectOrNull $rawStdin

# ─── Fetch quota data once (skipped if 'quota' is not in any layout) ─────────
$allLayoutSegments = $Line1Layout + $Line2Layout + $Line3Layout
$quotaData = if ($allLayoutSegments -contains 'quota') { Get-CopilotQuotaData } else { $null }

# ─── Segment resolver ────────────────────────────────────────────────────────
# Returns the rendered string for a named segment, or $null if unavailable.
function Resolve-Segment([string]$name) {
    switch ($name) {
        'model' {
            $d = Get-ModelDisplayName $contextPayload
            if ($d) { return "$cyan$d$rst" } else { return $null }
        }
        'context_bar' {
            return Get-ContextUsageSegment $contextPayload
        }
        'tokens' {
            return Get-ContextSummary $contextPayload
        }
        'duration' {
            return Get-TotalDurationDisplay $contextPayload
        }
        'premium_requests' {
            $n = Get-TotalPremiumRequests $contextPayload
            if ($null -ne $n) { return "$n p.req." } else { return $null }
        }
        'quota' {
            return Get-QuotaPaceSegment $quotaData
        }
        'path' {
            return Get-WorkspaceDisplayPath $contextPayload
        }
        'session_name' {
            return Get-SessionDisplayName $contextPayload
        }
        'lines_changed' {
            return Get-LinesChangedStats $contextPayload
        }
        default {
            return $null
        }
    }
}

# ─── Build and output each line ──────────────────────────────────────────────
$line1Segments = $Line1Layout | ForEach-Object { Resolve-Segment $_ }
$line2Segments = $Line2Layout | ForEach-Object { Resolve-Segment $_ }
$line3Segments = $Line3Layout | ForEach-Object { Resolve-Segment $_ }

Write-Output (Join-StatusSegments $line1Segments)
Write-Output (Join-StatusSegments $line2Segments)

$line3 = Join-StatusSegments $line3Segments
if (-not [string]::IsNullOrWhiteSpace($line3)) {
    Write-Output $line3
}
