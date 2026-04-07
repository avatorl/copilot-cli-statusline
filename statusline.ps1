# ─── Configuration ────────────────────────────────────────────────────────────
# Set to $true to log raw stdin JSON to statusline.stdin.log (for debugging).
$DebugLog = $false

# Copilot CLI Status Line Script (Windows PowerShell)
#
# Renders a two-line status bar from Copilot's JSON payload piped to stdin.
#
# LINE 1: model | context bar % size | duration | p.req. | in/out tokens | Q/M% | pace bars
# LINE 2: cwd path | +lines -lines
#
# ─── STDIN PAYLOAD PARAMETERS ────────────────────────────────────────────────
#
# The Copilot CLI pipes a JSON object to stdin on each status refresh.
# Two payload shapes exist: a minimal one (context-only) and a full one.
#
# Top-level fields:
#   cwd                         string   Current working directory              ✅ USED (line 2 path)
#   session_id                  string   Unique session identifier              ○  available
#   session_name                string   Human-readable session name            ○  available
#   transcript_path             string   Path to session transcript folder      ○  available
#   version                     string   Copilot CLI version (e.g. "1.0.20")   ○  available
#
# model:
#   model.id                    string   Model identifier (e.g. "gpt-5.4")     ✅ USED (fallback name)
#   model.display_name          string   Friendly model name                    ✅ USED (line 1 model)
#
# workspace:
#   workspace.current_dir       string   Workspace root directory               ✅ USED (fallback for cwd)
#
# cost:
#   cost.total_api_duration_ms  int      Cumulative API call time in ms         ○  available
#   cost.total_lines_added      int      Total lines added this session         ✅ USED (line 2 green +N)
#   cost.total_lines_removed    int      Total lines removed this session       ✅ USED (line 2 red -N)
#   cost.total_duration_ms      int      Total session wall-clock time in ms    ✅ USED (line 1 duration)
#   cost.total_premium_requests int      Premium request count this session     ✅ USED (line 1 p.req.)
#
# context_window:
#   context_window.total_input_tokens       int   Cumulative input tokens       ✅ USED (line 1 "in")
#   context_window.total_output_tokens      int   Cumulative output tokens      ✅ USED (line 1 "out")
#   context_window.total_cache_read_tokens  int   Tokens served from cache      ○  available
#   context_window.total_cache_write_tokens int   Tokens written to cache       ○  available
#   context_window.total_tokens             int   Sum of input + output tokens  ○  available
#   context_window.context_window_size      int   Max context window size       ✅ USED (line 1 size)
#   context_window.used_percentage          int   % of context window used      ✅ USED (line 1 bar + %)
#   context_window.remaining_percentage     int   % of context window free      ○  available
#   context_window.remaining_tokens         int   Tokens still available        ○  available
#   context_window.last_call_input_tokens   int   Input tokens in last call     ○  available
#   context_window.last_call_output_tokens  int   Output tokens in last call    ○  available
#
# context_window.current_usage:
#   current_usage.input_tokens              int   Raw input tokens used         ○  available
#   current_usage.output_tokens             int   Raw output tokens used        ○  available
#   current_usage.cache_creation_input_tokens int  Cache creation tokens        ○  available
#   current_usage.cache_read_input_tokens   int   Cache read tokens             ○  available
#
# External API (not from stdin):
#   GitHub Copilot quota API → percent_remaining                               ✅ USED (Q% / M% + pace)
#
# ─── END PARAMETERS ──────────────────────────────────────────────────────────

# ─── UTF-8 Encoding ──────────────────────────────────────────────────────────
# Force UTF-8 so the status line runner preserves block characters and emoji.
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

# ─── ANSI Colors ─────────────────────────────────────────────────────────────
$esc = [char]27
$rst = "$esc[0m"
$dim = "$esc[90m"
$cyan = "$esc[36m"
$green = "$esc[32m"
$yellow = "$esc[33m"
$brightYellow = "$esc[93m"
$red = "$esc[31m"
$segmentSeparator = " $dim|$rst "

# ─── Bar Chart Characters ────────────────────────────────────────────────────
$filledChar = "█"
$unfilledChar = "░"

# ─── Pace Display Labels ─────────────────────────────────────────────────────
# "behind" = under quota pace (good), "ahead" = over quota pace (bad)
$onPaceIcon = "🟡"
$behindText = "behind"
$onPaceText = "on pace"
$aheadText = "ahead"
$behindColor = $green
$onPaceColor = $yellow
$aheadColor = $red

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

# Returns ANSI color based on token count thresholds: ≥1M red, ≥100K yellow, ≥10K bright yellow.
function Get-TokenAnsiColor($value) {
    $number = ConvertTo-NullableInt $value
    if ($null -eq $number) { return $null }
    if ($number -ge 1000000) { return $red }
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

# Formats a token value with prefix, coloring only the value (e.g. "in 2.3M" where only "2.3M" is colored).
function Format-ColoredToken([string]$prefix, $value) {
    $number = ConvertTo-NullableInt $value
    if ($null -eq $number) { return $null }
    $formattedValue = Format-CompactTokens $number
    $color = Get-TokenAnsiColor $number
    if ($color) { return "$prefix $color$formattedValue$rst" }
    return "$prefix $formattedValue"
}

# Renders a fixed-width 10-char bar chart from a percentage (0-100).
# Filled portion uses the provided color, unfilled portion is grey.
function Get-Bar($value, [string]$ansiColor, [int]$width = 10) {
    $number = ConvertTo-NullableInt $value
    if ($null -eq $number) { $number = 0 }
    $number = [math]::Max(0, [math]::Min(100, $number))

    $filled = [math]::Min($width, [int](($number * $width + 50) / 100))
    $empty = $width - $filled

    $filledPart = if ($filled -gt 0) { $script:filledChar * $filled } else { "" }
    $emptyPart = if ($empty -gt 0) { $script:filledChar * $empty } else { "" }
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

# Builds context usage segment for line 1: "████░░░░░░ 23% 400K".
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

# Builds cumulative token segment for line 1: "in 2.3M out 29K".
function Get-ContextSummary($payload) {
    if ($null -eq $payload -or $null -eq $payload.context_window) { return $null }

    $inputTokens = ConvertTo-NullableInt $payload.context_window.total_input_tokens
    $outputTokens = ConvertTo-NullableInt $payload.context_window.total_output_tokens
    if ($null -eq $inputTokens -and $null -eq $outputTokens) { return $null }

    $segments = New-Object System.Collections.Generic.List[string]
    $in = Format-ColoredToken "in" $inputTokens
    if ($in) { $segments.Add($in) }
    $out = Format-ColoredToken "out" $outputTokens
    if ($out) { $segments.Add($out) }
    return [string]::Join(" ", $segments)
}

# Returns green "+N" red "-N" from cost.total_lines_added/removed.
function Get-LinesChangedStats($payload) {
    if ($null -eq $payload -or $null -eq $payload.cost) { return $null }

    $added = ConvertTo-NullableInt $payload.cost.total_lines_added
    $removed = ConvertTo-NullableInt $payload.cost.total_lines_removed
    if (($null -eq $added -and $null -eq $removed) -or ($added -eq 0 -and $removed -eq 0)) {
        return $null
    }

    $addedStr = if ($null -ne $added) { "$green+$added$rst" } else { "$green+0$rst" }
    $removedStr = if ($null -ne $removed) { "$red-$removed$rst" } else { "$red-0$rst" }
    return "$addedStr $removedStr"
}

# ═════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═════════════════════════════════════════════════════════════════════════════

# Read and log the raw stdin payload.
$rawStdin = Get-OptionalStdin
Write-StdinLog $rawStdin
$contextPayload = ConvertFrom-JsonObjectOrNull $rawStdin

# ─── Line 1: Session metadata ───────────────────────────────────────────────
$line1Segments = New-Object System.Collections.Generic.List[string]

$modelDisplayName = Get-ModelDisplayName $contextPayload
if ($modelDisplayName) { $line1Segments.Add("$cyan$modelDisplayName$rst") }

$contextUsageSegment = Get-ContextUsageSegment $contextPayload
if ($contextUsageSegment) { $line1Segments.Add($contextUsageSegment) }

$durationDisplay = Get-TotalDurationDisplay $contextPayload
if ($durationDisplay) { $line1Segments.Add($durationDisplay) }

$totalPremiumRequests = Get-TotalPremiumRequests $contextPayload
if ($null -ne $totalPremiumRequests) { $line1Segments.Add("$totalPremiumRequests p.req.") }

# ─── Quota pacing (fetched from GitHub API) ──────────────────────────────────
$usedPct = $null
try {
    # Resolve a GitHub token from env vars, Copilot config, or git credential store.
    $token = $null
    if ($env:GITHUB_TOKEN) {
        $token = $env:GITHUB_TOKEN
    } elseif ($env:GH_TOKEN) {
        $token = $env:GH_TOKEN
    } else {
        $copilotCfgPath = Join-Path $env:USERPROFILE ".copilot\config.json"
        if (Test-Path $copilotCfgPath) {
            try {
                $copilotCfg = Get-Content $copilotCfgPath -Raw | ConvertFrom-Json
                if ($copilotCfg.last_logged_in_user -and $copilotCfg.copilot_tokens) {
                    $key = "$($copilotCfg.last_logged_in_user.host):$($copilotCfg.last_logged_in_user.login)"
                    if ($copilotCfg.copilot_tokens.PSObject.Properties.Name -contains $key) {
                        $token = $copilotCfg.copilot_tokens.$key
                    }
                }
                if (-not $token -and $copilotCfg.copilot_tokens) {
                    foreach ($property in $copilotCfg.copilot_tokens.PSObject.Properties) {
                        if ($property.Value) { $token = $property.Value; break }
                    }
                }
            } catch {}
        }
    }
    if (-not $token) {
        try {
            $git = Get-Command git -ErrorAction Stop
            $token = ("url=https://github.com" | & $git.Source credential fill 2>$null |
                Select-String "^password=").ToString().Split("=", 2)[1]
        } catch {}
    }

    # Query Copilot quota API for premium usage percentage.
    if ($token) {
        $quota = Invoke-RestMethod -Uri "https://api.github.com/copilot_internal/user" `
            -Headers @{ "Authorization" = "Bearer $token"; "Accept" = "application/json" } `
            -TimeoutSec 5 -ErrorAction Stop
        $usedPct = [math]::Round(100 - $quota.quota_snapshots.premium_interactions.percent_remaining, 1)
    }
} catch {}

# ─── Calendar pacing calculation ─────────────────────────────────────────────
$now = Get-Date
$daysInMonth = [DateTime]::DaysInMonth($now.Year, $now.Month)
$elapsedDays = $now.Day
$monthPct = [math]::Round($elapsedDays / $daysInMonth * 100, 1)

# Calendar pace visualization: elapsed days as solid grey █, remaining as hatched ░,
# with colored filled bars overlaid showing days ahead/behind quota pace.
# Today is always included in the colored section.
# Behind (green): colored bars include today and N-1 days before.
# Ahead (red): colored bars include today and N-1 days after.
# On pace (<1 day): today's bar is yellow.
if ($null -ne $usedPct) {
    $diff = $usedPct - $monthPct
    $daysDelta = [math]::Round($daysInMonth * ([math]::Abs($diff) / 100.0), 1)
    $barCount = [int][math]::Ceiling($daysDelta)
    $todayIndex = $elapsedDays - 1  # 0-based position of today

    if ($diff -lt 0 -and $daysDelta -ge 1) {
        # Behind (good): green bars include today and days before
        $actualBars = [math]::Min($barCount, $elapsedDays)  # include today
        $solidLeft = $elapsedDays - $actualBars
        $hatchedRight = $daysInMonth - $elapsedDays
        $paceCalendar = "$dim$("█" * $solidLeft)$rst$behindColor$("█" * $actualBars)$rst$dim$("░" * $hatchedRight)$rst"
        $paceSegment = "$paceCalendar $behindColor$('{0:0.0}' -f $daysDelta) days $behindText$rst"
    } elseif ($diff -gt 0 -and $daysDelta -ge 1) {
        # Ahead (bad): red bars include today and days after
        $maxBars = $daysInMonth - $elapsedDays + 1  # include today
        $actualBars = [math]::Min($barCount, $maxBars)
        $solidLeft = $elapsedDays - 1
        $hatchedRight = $daysInMonth - $elapsedDays - $actualBars + 1
        $paceCalendar = "$dim$("█" * $solidLeft)$rst$aheadColor$("█" * $actualBars)$rst$dim$("░" * $hatchedRight)$rst"
        $paceSegment = "$paceCalendar $aheadColor$('{0:0.0}' -f $daysDelta) days $aheadText$rst"
    } else {
        # On pace (within 1 day): mark today with yellow, rest is grey
        $solidLeft = $elapsedDays - 1
        $hatchedRight = $daysInMonth - $elapsedDays
        $paceCalendar = "$dim$("█" * $solidLeft)$rst$onPaceColor█$rst$dim$("░" * $hatchedRight)$rst"
        $paceSegment = "$paceCalendar $onPaceColor$onPaceIcon $onPaceText$rst"
    }
} else {
    $paceSegment = "$dim($elapsedDays/$daysInMonth)$rst"
}

# ─── Previous pace visualization (commented out) ────────────────────────────
# Pace bars: one colored block per day ahead/behind, with text label.
# if ($null -ne $usedPct) {
#     $diff = $usedPct - $monthPct
#     $daysDelta = [math]::Round($daysInMonth * ([math]::Abs($diff) / 100.0), 1)
#     $barCount = [int][math]::Ceiling($daysDelta)
#     if ($diff -lt 0 -and $daysDelta -ge 1) {
#         $bars = ("█" * $barCount) -replace '(?<=.)(?=.)', " "
#         $paceSegment = "$behindColor$bars $('{0:0.0}' -f $daysDelta) days $behindText$rst"
#     } elseif ($diff -gt 0 -and $daysDelta -ge 1) {
#         $bars = ("█" * $barCount) -replace '(?<=.)(?=.)', " "
#         $paceSegment = "$aheadColor$bars $('{0:0.0}' -f $daysDelta) days $aheadText$rst"
#     } else {
#         $paceSegment = "$onPaceColor$onPaceIcon $onPaceText$rst"
#     }
# } else {
#     $paceSegment = "$dim($elapsedDays/$daysInMonth)$rst"
# }

# Append token summary and pace to line 1.
$contextSegment = Get-ContextSummary $contextPayload
$line1Segments.Add($contextSegment)
$line1Segments.Add($paceSegment)
$line1 = Join-StatusSegments $line1Segments

# ─── Line 2: Path and lines changed ─────────────────────────────────────────
$workspaceDisplayPath = Get-WorkspaceDisplayPath $contextPayload
$line2Parts = @($workspaceDisplayPath)
$linesChanged = Get-LinesChangedStats $contextPayload
if ($linesChanged) { $line2Parts += $linesChanged }

# ─── Output ──────────────────────────────────────────────────────────────────
Write-Output $line1
Write-Output ($line2Parts -join " | ")
