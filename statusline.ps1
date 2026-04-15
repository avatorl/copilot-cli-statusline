# ─── Configuration ────────────────────────────────────────────────────────────
# Set to $true to log raw stdin JSON to statusline.stdin.log (for debugging).
$DebugLog = $false

# ─── Status Line Layout ───────────────────────────────────────────────────────
# Define which segments appear on each output line and in what order.
# Remove or comment out any name to hide that segment.
#
# Git refresh config:
#   Git tracking refs are refreshed in the background when git_sync is enabled.
#   The status line never waits for fetch to finish.
$GitFetchRefreshSeconds = 300
$GitFetchLockTimeoutSeconds = 600
#
# Duration fallback config:
#   show-available = show "API X of Y" when both values exist, otherwise show whichever exists
#   require-both   = hide the duration segment unless both API and total durations exist
$DurationFallbackMode = 'show-available'
#
# Line 1 segment names:
#   model              - Active model name
#   context_bar        - Context-window usage bar and percentage
#   last_call_tokens   - Token counts for the most recent call
#   tokens             - Cumulative input / output token counts
#   duration           - API duration plus total session duration
#   premium_requests   - Session/month-used of quota premium requests (p.req.)
#   premium_requests_month - Monthly premium requests used of total
#   quota              - Monthly quota pacing bar (fetches GitHub API)
#
# Line 2 segment names:
#   path               - Current workspace / working directory
#   session_name       - Human-readable Copilot session name
#   repo_name          - Git remote owner/repo from origin
#   git_sync           - Upstream sync / dirty status from git metadata
#   git_detail         - Branch plus staged/unstaged/untracked/conflict counts
#   lines_changed      - Lines added / removed this session (+N -N)
#
# Line 3 segment names:
#   (empty by default — add any segment names you want on a third line)
#
$Line1Layout = @(
    'model'
    'context_bar'
    'last_call_tokens'
    'tokens'
    'duration'
)

$Line2Layout = @(
    'path'
    'lines_changed'
    'session_name'
    'repo_name'
    'git_sync'
    'git_detail'
)

$Line3Layout = @(
    'premium_requests'
    'quota'
)
# ─────────────────────────────────────────────────────────────────────────────

# Copilot CLI Status Line Script (Windows PowerShell)
#
# Renders up to three configurable status lines from Copilot's JSON payload piped to stdin.
#
# LINE 1: model | context bar % size | last-call tokens | in/out/cached tokens | duration
#         (configurable — see $Line1Layout above)
# LINE 2: cwd path | +lines -lines | session name | repo name | git sync | git detail
#         (configurable — see $Line2Layout above)
# LINE 3: session/month-used of quota p.req. | quota pace
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
    if ($totalSeconds -lt 30) { return $null }
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

# Last-call token size segment — shows tokens for the most recent call (input/output)
function Get-LastCallTokensSegment($payload) {
    if ($null -eq $payload -or -not $payload.context_window) { return $null }
    $cw = $payload.context_window
    $in = ConvertTo-NullableInt $cw.last_call_input_tokens
    $out = ConvertTo-NullableInt $cw.last_call_output_tokens
    if ($null -eq $in -and $null -eq $out) { return $null }
    $parts = @()
    if ($in -ne $null) { $parts += Format-ColoredToken 'last in' $in }
    if ($out -ne $null) { $parts += Format-ColoredToken 'out' $out }
    return [string]::Join(' ', $parts)
}


# Renders a fixed-width 10-char bar chart from a percentage (0–100).
# Works in double precision to avoid int-coercion rounding before the fill calculation.
# Filled portion uses solid blocks; unfilled portion uses dim hatched blocks.
function Get-Bar($value, [string]$ansiColor, [int]$width = 10) {
    # Clamp to [0, 100] without int coercion so fractional percentages round correctly.
    $pct    = if ($null -ne $value) { [math]::Max(0.0, [math]::Min(100.0, [double]$value)) } else { 0.0 }
    # AwayFromZero: 2.5 → 3, 2.4 → 2 (round-half-up for bar charts)
    $filled = [math]::Min($width, [int][math]::Round($pct / 100.0 * $width, [System.MidpointRounding]::AwayFromZero))
    $empty  = $width - $filled

    $filledPart = if ($filled -gt 0) { $script:filledChar * $filled } else { "" }
    $emptyPart  = if ($empty  -gt 0) { $script:hatchedChar * $empty  } else { "" }
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

# Returns the preferred git command path for the workspace.
# Use workspace.current_dir when available so git caches stay stable across cwd changes inside a repo.
function Get-GitWorkspacePath($payload) {
    $path = $null
    if ($payload -and $payload.workspace -and $payload.workspace.current_dir) {
        $path = [string]$payload.workspace.current_dir
    } else {
        $path = Get-WorkspaceDisplayPath $payload
    }

    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    return ($path -replace '/', '\')
}

# Returns the local cache root used for small statusline state files.
function Get-StatuslineStateRoot() {
    $basePath = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($basePath)) {
        $basePath = [System.IO.Path]::GetTempPath().TrimEnd('\')
    }
    return Join-Path $basePath 'copilot-cli-statusline'
}

# Returns a lowercase SHA-256 hex string for cache-key-safe filenames.
function Get-Sha256Hex([string]$text) {
    if ([string]::IsNullOrEmpty($text)) { return $null }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    $hashBytes = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant()
}

# Returns the repo-scoped marker base path used by background git refresh.
function Get-GitFetchMarkerBasePath([string]$workspacePath) {
    if ([string]::IsNullOrWhiteSpace($workspacePath)) { return $null }

    $cacheKey = Get-Sha256Hex $workspacePath.ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($cacheKey)) { return $null }

    return Join-Path (Join-Path (Get-StatuslineStateRoot) 'git-fetch') $cacheKey
}

# Returns the age of a marker file in seconds, or $null when it does not exist.
function Get-FileAgeSeconds([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    if (-not (Test-Path -LiteralPath $path)) { return $null }

    try {
        $item = Get-Item -LiteralPath $path -ErrorAction Stop
        return [double]([DateTimeOffset]::UtcNow - [DateTimeOffset]$item.LastWriteTimeUtc).TotalSeconds
    } catch {
        return $null
    }
}

# Starts a repo-scoped background fetch when tracking refs are stale.
# Rendering always uses local git data immediately and never waits on the network.
function Start-GitFetchRefreshInBackground($gitSnapshot) {
    if ($null -eq $gitSnapshot -or -not $gitSnapshot.IsGitRepo) { return }
    if ([string]::IsNullOrWhiteSpace($gitSnapshot.Upstream)) { return }
    if ($script:GitFetchRefreshSeconds -le 0) { return }

    $workspacePath = $gitSnapshot.WorkspacePath
    $markerBasePath = Get-GitFetchMarkerBasePath $workspacePath
    if ([string]::IsNullOrWhiteSpace($workspacePath) -or [string]::IsNullOrWhiteSpace($markerBasePath)) { return }

    $markerDirectory = Split-Path -Parent $markerBasePath
    if ([string]::IsNullOrWhiteSpace($markerDirectory)) { return }

    try {
        if (-not (Test-Path -LiteralPath $markerDirectory)) {
            New-Item -ItemType Directory -Path $markerDirectory -Force | Out-Null
        }
    } catch {
        return
    }

    $attemptPath = "$markerBasePath.attempt"
    $successPath = "$markerBasePath.success"
    $lockPath = "$markerBasePath.lock"

    $lockAgeSeconds = Get-FileAgeSeconds $lockPath
    if ($null -ne $lockAgeSeconds -and $lockAgeSeconds -lt $script:GitFetchLockTimeoutSeconds) { return }
    if ($null -ne $lockAgeSeconds) {
        try { Remove-Item -LiteralPath $lockPath -Force -ErrorAction Stop } catch {}
    }

    $attemptAgeSeconds = Get-FileAgeSeconds $attemptPath
    $successAgeSeconds = Get-FileAgeSeconds $successPath
    $attemptIsFresh = ($null -ne $attemptAgeSeconds -and $attemptAgeSeconds -lt $script:GitFetchRefreshSeconds)
    $successIsFresh = ($null -ne $successAgeSeconds -and $successAgeSeconds -lt $script:GitFetchRefreshSeconds)
    if ($attemptIsFresh -or $successIsFresh) { return }

    $timestamp = [DateTimeOffset]::UtcNow.ToString('o')
    try {
        Set-Content -Path $attemptPath -Value $timestamp -Encoding ascii
        Set-Content -Path $lockPath -Value $timestamp -Encoding ascii
    } catch {
        return
    }

    $escapedWorkspacePath = $workspacePath.Replace('"', '""')
    $escapedSuccessPath = $successPath.Replace('"', '""')
    $escapedLockPath = $lockPath.Replace('"', '""')
    $cmdCommand = "git -C ""$escapedWorkspacePath"" fetch --quiet --no-tags --prune 1>nul 2>nul && (copy /y nul ""$escapedSuccessPath"" >nul) & del /q ""$escapedLockPath"" >nul 2>nul"

    try {
        Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d', '/c', $cmdCommand) -WindowStyle Hidden | Out-Null
    } catch {
        try { Remove-Item -LiteralPath $lockPath -Force -ErrorAction Stop } catch {}
    }
}

# Parses a git remote URL into host/owner/repo parts.
# Supports SSH and URL forms such as:
#   git@github.com:owner/repo.git
#   https://github.com/owner/repo.git
#   ssh://git@github.com/owner/repo.git
function ConvertFrom-GitRemoteUrl([string]$remoteUrl) {
    if ([string]::IsNullOrWhiteSpace($remoteUrl)) { return $null }
    $trimmed = $remoteUrl.Trim()

    $sshMatch = [regex]::Match($trimmed, '^(?:[^@]+@)?([^:]+):(.+?)(?:\.git)?/?$')
    if (-not $trimmed.Contains('://') -and $sshMatch.Success) {
        $pathSegments = $sshMatch.Groups[2].Value.Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)
        if ($pathSegments.Length -lt 2) { return $null }

        $repo = $pathSegments[$pathSegments.Length - 1]
        $owner = [string]::Join('/', $pathSegments[0..($pathSegments.Length - 2)])
        if ([string]::IsNullOrWhiteSpace($owner) -or [string]::IsNullOrWhiteSpace($repo)) { return $null }

        return [PSCustomObject]@{
            Host      = $sshMatch.Groups[1].Value
            Owner     = $owner
            Repo      = $repo
            OwnerRepo = "$owner/$repo"
        }
    }

    $uri = $null
    if (-not [System.Uri]::TryCreate($trimmed, [System.UriKind]::Absolute, [ref]$uri)) { return $null }
    if ($uri.Scheme -notin @('http', 'https', 'ssh', 'git')) { return $null }

    $cleanPath = $uri.AbsolutePath.Trim('/').TrimEnd('/')
    if ($cleanPath.EndsWith('.git')) {
        $cleanPath = $cleanPath.Substring(0, $cleanPath.Length - 4)
    }

    $segments = $cleanPath.Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)
    if ($segments.Length -lt 2) { return $null }

    $repo = $segments[$segments.Length - 1]
    $owner = [string]::Join('/', $segments[0..($segments.Length - 2)])
    if ([string]::IsNullOrWhiteSpace($owner) -or [string]::IsNullOrWhiteSpace($repo)) { return $null }

    return [PSCustomObject]@{
        Host      = $uri.Host
        Owner     = $owner
        Repo      = $repo
        OwnerRepo = "$owner/$repo"
    }
}

# Returns git remote metadata for the current workspace by reading origin.
# The status line hides git-derived segments when the directory is not a repo or origin is missing.
function Get-GitOriginRemoteData($payload) {
    $workspacePath = Get-GitWorkspacePath $payload
    if ([string]::IsNullOrWhiteSpace($workspacePath)) { return $null }

    try {
        $remoteUrl = (& git -C $workspacePath remote get-url origin 2>$null | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($remoteUrl)) { return $null }
        return ConvertFrom-GitRemoteUrl $remoteUrl
    } catch {}

    return $null
}

# Builds a shared local git snapshot from one cheap status command.
# This is the preferred source for fast git-backed segments such as sync state because it
# provides branch, upstream, ahead/behind, and dirty-state information from one local call.
function Get-GitStatusSnapshot($payload) {
    $workspacePath = Get-GitWorkspacePath $payload
    if ([string]::IsNullOrWhiteSpace($workspacePath)) { return $null }

    $output = $null
    try {
        $output = (& git -C $workspacePath status --porcelain=2 --branch 2>$null | Out-String)
    } catch {
        $output = $null
    }

    if ([string]::IsNullOrWhiteSpace($output)) {
        return [PSCustomObject]@{
            WorkspacePath = $workspacePath
            IsGitRepo     = $false
            Branch        = $null
            Upstream      = $null
            Ahead         = $null
            Behind        = $null
            HasStaged     = $false
            HasUnstaged   = $false
            HasUntracked  = $false
            StagedCount   = 0
            UnstagedCount = 0
            UntrackedCount = 0
            ConflictCount = 0
            IsDirty       = $false
        }
    }

    $snapshot = [PSCustomObject]@{
        WorkspacePath = $workspacePath
        IsGitRepo     = $true
        Branch        = $null
        Upstream      = $null
        Ahead         = $null
        Behind        = $null
        HasStaged     = $false
        HasUnstaged   = $false
        HasUntracked  = $false
        StagedCount   = 0
        UnstagedCount = 0
        UntrackedCount = 0
        ConflictCount = 0
        IsDirty       = $false
    }

    foreach ($rawLine in ($output -split "`r?`n")) {
        $line = $rawLine.TrimEnd()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        $branchHeadMatch = [regex]::Match($line, '^# branch\.head (.+)$')
        if ($branchHeadMatch.Success) {
            $snapshot.Branch = $branchHeadMatch.Groups[1].Value
            continue
        }

        $upstreamMatch = [regex]::Match($line, '^# branch\.upstream (.+)$')
        if ($upstreamMatch.Success) {
            $snapshot.Upstream = $upstreamMatch.Groups[1].Value
            continue
        }

        $aheadBehindMatch = [regex]::Match($line, '^# branch\.ab \+(\d+) -(\d+)$')
        if ($aheadBehindMatch.Success) {
            $snapshot.Ahead = [int]$aheadBehindMatch.Groups[1].Value
            $snapshot.Behind = [int]$aheadBehindMatch.Groups[2].Value
            continue
        }

        if ($line.StartsWith('? ')) {
            $snapshot.HasUntracked = $true
            $snapshot.UntrackedCount++
            $snapshot.IsDirty = $true
            continue
        }

        if ($line.StartsWith('u ')) {
            $snapshot.HasStaged = $true
            $snapshot.HasUnstaged = $true
            $snapshot.ConflictCount++
            $snapshot.IsDirty = $true
            continue
        }

        if ($line.StartsWith('1 ') -or $line.StartsWith('2 ')) {
            if ($line.Length -ge 4) {
                $indexStatus = $line.Substring(2, 1)
                $workTreeStatus = $line.Substring(3, 1)

                if ($indexStatus -ne '.') {
                    $snapshot.HasStaged = $true
                    $snapshot.StagedCount++
                }
                if ($workTreeStatus -ne '.') {
                    $snapshot.HasUnstaged = $true
                    $snapshot.UnstagedCount++
                }
                if ($snapshot.HasStaged -or $snapshot.HasUnstaged) { $snapshot.IsDirty = $true }
            }
        }
    }

    return $snapshot
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

# Returns premium request count from cost.total_premium_requests.
function Get-TotalPremiumRequests($payload) {
    if ($payload -and $payload.cost) {
        $requests = ConvertTo-NullableInt $payload.cost.total_premium_requests
        if ($null -ne $requests) { return $requests }
    }
    return $null
}

# Returns formatted duration string from cost.total_api_duration_ms and cost.total_duration_ms.
function Get-TotalDurationDisplay($payload) {
    if ($payload -and $payload.cost) {
        $apiMs = ConvertTo-NullableInt $payload.cost.total_api_duration_ms
        $totalMs = ConvertTo-NullableInt $payload.cost.total_duration_ms

        $apiStr = if ($null -ne $apiMs) { Format-DurationFromMilliseconds $apiMs } else { $null }
        $totalStr = if ($null -ne $totalMs) { Format-DurationFromMilliseconds $totalMs } else { $null }
        $mode = [string]$script:DurationFallbackMode

        if ($apiStr -and $totalStr) {
            return "$dim" + "API" + "$rst " + "$cyan$apiStr$rst $dim" + "of" + "$rst $totalStr"
        }

        if ($mode -eq 'require-both') { return $null }
        if ($totalStr) { return $totalStr }
        if ($apiStr) { return "$dim" + "API" + "$rst " + "$cyan$apiStr$rst" }
    }
    return $null
}

# Builds the upstream sync segment from the local git snapshot.
# A green circle and "synced" label mean the local branch matches the local tracking ref and the working tree is clean.
# A dim circle means the branch is not in the fully synced/clean state.
# Status labels render in the default value color unless the repo is fully synced and clean.
function Get-GitSyncSegment($gitSnapshot) {
    if ($null -eq $gitSnapshot -or -not $gitSnapshot.IsGitRepo) { return $null }

    $dirty = $gitSnapshot.IsDirty
    $dirtyTextSuffix = if ($dirty) { ' dirty' } else { '' }

    if ([string]::IsNullOrWhiteSpace($gitSnapshot.Upstream)) {
        return "$dim⚪$rst no upstream$dirtyTextSuffix"
    }

    $ahead = if ($null -ne $gitSnapshot.Ahead) { [int]$gitSnapshot.Ahead } else { 0 }
    $behind = if ($null -ne $gitSnapshot.Behind) { [int]$gitSnapshot.Behind } else { 0 }

    # Fully synced and clean: green
    if ($ahead -eq 0 -and $behind -eq 0) {
        if (-not $dirty) {
            return "$green🟢 synced$rst"
        } else {
            # Synced but working tree has local edits: dim circle with default-color label.
            return "$dim⚪$rst synced dirty"
        }
    }

    if ($ahead -gt 0 -and $behind -gt 0) {
        return "$dim⚪$rst diverged $ahead/$behind$dirtyTextSuffix"
    }
    if ($ahead -gt 0) {
        return "$dim⚪$rst ahead $ahead$dirtyTextSuffix"
    }
    if ($behind -gt 0) {
        return "$dim⚪$rst behind $behind$dirtyTextSuffix"
    }

    return "$dim⚪$rst no upstream$dirtyTextSuffix"
}

# Builds a compact git detail segment: branch name plus local change counts when present.
function Get-GitDetailSegment($gitSnapshot) {
    if ($null -eq $gitSnapshot -or -not $gitSnapshot.IsGitRepo) { return $null }

    $parts = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($gitSnapshot.Branch) -and $gitSnapshot.Branch -ne '(unknown)') {
        $parts.Add([string]$gitSnapshot.Branch)
    }
    if ($gitSnapshot.ConflictCount -gt 0) {
        $parts.Add("$brightRed!$($gitSnapshot.ConflictCount)$rst")
    }
    if ($gitSnapshot.StagedCount -gt 0) {
        $parts.Add("$green+$($gitSnapshot.StagedCount)$rst")
    }
    if ($gitSnapshot.UnstagedCount -gt 0) {
        $parts.Add("$yellow~$($gitSnapshot.UnstagedCount)$rst")
    }
    if ($gitSnapshot.UntrackedCount -gt 0) {
        $parts.Add("$dim?$($gitSnapshot.UntrackedCount)$rst")
    }

    if ($parts.Count -eq 0) { return $null }
    return [string]::Join(' ', $parts)
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

# Queries the Copilot quota API; returns a PSCustomObject with:
#   UsedPct      - monthly premium quota consumed as a percentage
#   UsedRequests - monthly premium requests used (derived from entitlement + remaining %)
#   Entitlement  - monthly premium request budget
# Returns $null when the token is unavailable or the API call fails.
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

        $percentRemaining = [double]$snap.percent_remaining
        $usedPct          = [math]::Round(100 - $percentRemaining, 1)
        $entitlement = if ($null -ne $snap.entitlement -and [double]$snap.entitlement -gt 0) {
            [int]$snap.entitlement
        } else { $null }
        $usedRequests = if ($null -ne $entitlement) {
            [int][math]::Round($entitlement * (100.0 - $percentRemaining) / 100.0, [System.MidpointRounding]::AwayFromZero)
        } else { $null }

        return [PSCustomObject]@{
            UsedPct      = $usedPct
            UsedRequests = $usedRequests
            Entitlement  = $entitlement
        }
    } catch {}

    return $null
}

# Builds the monthly premium requests segment: "123 of 1500".
# The value is account-level monthly usage from the live quota API, not the session payload.
# Falls back to "? of ?" when quota data is unavailable or incomplete.
function Get-MonthlyPremiumRequestsSegment($quotaData) {
    if ($null -eq $quotaData -or $null -eq $quotaData.UsedRequests -or $null -eq $quotaData.Entitlement) {
        return "? of ?"
    }
    return "$($quotaData.UsedRequests) of $($quotaData.Entitlement)"
}

# Converts a pace delta into an estimated premium-request count such as " (160 p.req.)".
# Used only when the quota API returned an entitlement value.
function Get-PremiumRequestPaceHint($daysDelta, $entitlement, $daysInMonth) {
    if ($null -eq $entitlement) { return "" }

    $pReq = [int][math]::Round($daysDelta / $daysInMonth * $entitlement, [System.MidpointRounding]::AwayFromZero)
    if ($pReq -le 0) { return "" }
    return " ($pReq p.req.)"
}

# Builds the combined premium requests segment: "2/338 of 1500 p.req.".
# Left side = this session's premium requests from Copilot CLI payload.
# Middle = account-wide monthly used premium requests from the live quota API.
# "of" value = monthly premium request budget from the live quota API.
# Slash separators use the same dim color as token labels such as "in" and "out".
function Get-PremiumRequestsSegment($payload, $quotaData) {
    $sessionRequests = Get-TotalPremiumRequests $payload
    $monthUsed = if ($quotaData) { $quotaData.UsedRequests } else { $null }
    $entitlement = if ($quotaData) { $quotaData.Entitlement } else { $null }

    if ($null -eq $sessionRequests -and $null -eq $monthUsed -and $null -eq $entitlement) {
        return $null
    }

    $slash = "$dim/$rst"
    $sessionText = if ($null -ne $sessionRequests) { "$sessionRequests" } else { "?" }
    $monthUsedText = if ($null -ne $monthUsed) { "$monthUsed" } else { "?" }
    $entitlementText = if ($null -ne $entitlement) { "$entitlement" } else { "?" }
    return "$sessionText$slash$monthUsedText of $entitlementText p.req."
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
#   $quotaData — [PSCustomObject]@{ UsedPct; UsedRequests; Entitlement } or $null (API unavailable)
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
            $pReqHint = Get-PremiumRequestPaceHint $daysDelta $entitlement $daysInMonth
            
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
            $pReqHint = Get-PremiumRequestPaceHint $daysDelta $entitlement $daysInMonth

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

# ─── Fetch quota data once (skipped if quota-based segments are not in any layout) ─
# Quota-based segments can still render even when stdin is minimal or missing because they
# come from the live Copilot quota API rather than the session payload.
$allLayoutSegments = $Line1Layout + $Line2Layout + $Line3Layout
$quotaData = if (($allLayoutSegments -contains 'quota') -or
    ($allLayoutSegments -contains 'premium_requests') -or
    ($allLayoutSegments -contains 'premium_requests_month')) {
    Get-CopilotQuotaData
} else {
    $null
}

# ─── Fetch local git data once (skipped if git-based segments are not in any layout) ──
$gitSnapshot = if (($allLayoutSegments -contains 'git_sync') -or
    ($allLayoutSegments -contains 'git_detail') -or
    ($allLayoutSegments -contains 'repo_name')) {
    Get-GitStatusSnapshot $contextPayload
} else {
    $null
}

if (($allLayoutSegments -contains 'git_sync') -and $gitSnapshot) {
    Start-GitFetchRefreshInBackground $gitSnapshot
}

$gitRemoteData = if (($allLayoutSegments -contains 'repo_name') -and $gitSnapshot -and $gitSnapshot.IsGitRepo) {
    Get-GitOriginRemoteData $contextPayload
} else {
    $null
}

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
        'last_call_tokens' {
            return Get-LastCallTokensSegment $contextPayload
        }
        'tokens' {
            return Get-ContextSummary $contextPayload
        }
        'duration' {
            return Get-TotalDurationDisplay $contextPayload
        }
        'premium_requests' {
            return Get-PremiumRequestsSegment $contextPayload $quotaData
        }
        'premium_requests_month' {
            return Get-MonthlyPremiumRequestsSegment $quotaData
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
        'repo_name' {
            if ($gitRemoteData) { return $gitRemoteData.OwnerRepo }
            return $null
        }
        'git_sync' {
            return Get-GitSyncSegment $gitSnapshot
        }
        'git_detail' {
            return Get-GitDetailSegment $gitSnapshot
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

$line1 = Join-StatusSegments $line1Segments
$line2 = Join-StatusSegments $line2Segments
$line3 = Join-StatusSegments $line3Segments

if (-not [string]::IsNullOrWhiteSpace($line1)) {
    Write-Output $line1
}
if (-not [string]::IsNullOrWhiteSpace($line2)) {
    Write-Output $line2
}
if (-not [string]::IsNullOrWhiteSpace($line3)) {
    Write-Output $line3
}
