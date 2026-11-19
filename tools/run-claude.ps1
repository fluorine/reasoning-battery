#requires -Version 7.0
# Runs battery prompts through headless Claude Code with every tool disabled.
# Resumable. Exits after each spending chunk so the operator can check usage.
[CmdletBinding()]
param(
    # Problem directory with config.json and prompts/. Not used with -Staircase.
    [string]$LadderDir,
    [Parameter(Mandatory)][string[]]$RunDir,
    # Ladder and staircase runs grade between replies, so they need the seed.
    [string]$SeedFile,
    # Run every prompt in a quiz with no stopping rule.
    [switch]$All,
    # Each RunDir is a staircase run made with ladder.ps1 -Mode Staircase.
    [switch]$Staircase,
    [string]$Model = 'claude-opus-5-5',
    [ValidateSet('low', 'medium', 'high', 'xhigh', 'max')][string]$Effort = 'high',
    # Output tokens per reply. Default: the Budget in config.json.
    [ValidateRange(-1, 1000000)][int]$Budget = -1,
    [ValidateRange(1, 16)][int]$Parallel = 7,
    [double]$ChunkUsd = 4,
    [ValidateRange(1, 5)][int]$StopAfter = 2,
    [double]$Ceiling = 0.10,
    [int]$TimeoutMinutes = 40,
    [string]$SystemPrompt = 'You are a helpful assistant.'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ladderScript = Join-Path $PSScriptRoot '..\ladder.ps1'
$claude = (Get-Command claude).Source
$RunDir = @($RunDir -split ',' | Where-Object { $_ })
if (-not $All -and -not $SeedFile) { throw 'SeedFile is required for a ladder or staircase run.' }
if (-not $Staircase -and -not $LadderDir) { throw 'LadderDir is required.' }
$seed = if ($SeedFile) { (Get-Content -LiteralPath $SeedFile -Raw).Trim() }
$cfgFile = if ($Staircase) { Join-Path $RunDir[0] 'config.json' } else { Join-Path $LadderDir 'config.json' }
if (-not (Test-Path -LiteralPath $cfgFile)) {
    throw "No $cfgFile. For a staircase, run ladder.ps1 -Mode Staircase first."
}
$cfg = Get-Content -LiteralPath $cfgFile -Raw | ConvertFrom-Json
$cfgBudget = if ($cfg.PSObject.Properties['Budget']) { [int]$cfg.Budget } else { 0 }
if ($Budget -lt 0) { $Budget = $cfgBudget }
elseif ($Budget -ne $cfgBudget) {
    throw "The prompts state a budget of $cfgBudget tokens, not $Budget."
}
# Prompts with no stated budget keep the earlier 64,000-token cap.
$cap = if ($Budget -gt 0) { $Budget } else { 64000 }
# A cut reply has no cost report. This estimate errs high.
$cutCostUsd = 0.01 + 2.2e-5 * $cap
# A directory with no CLAUDE.md, settings or git repo above it.
$neutral = Join-Path $env:TEMP 'battery-neutral'
New-Item -ItemType Directory -Force $neutral | Out-Null

foreach ($r in $RunDir) {
    foreach ($sub in 'answers', 'meta') {
        New-Item -ItemType Directory -Force (Join-Path $r $sub) | Out-Null
    }
    if (-not $Staircase) {
        Copy-Item -LiteralPath (Join-Path $LadderDir 'config.json') -Destination $r -Force
    }
}

function Get-NextLevel([string]$Run, [string]$Family, $Results) {
    $streak = 0
    foreach ($level in 1..$cfg.MaxLevel) {
        $ids = 1..$cfg.PerLevel | ForEach-Object { '{0}-L{1:d2}-{2}' -f $Family, $level, $_ }
        $done = @($ids | Where-Object { Test-Path (Join-Path $Run "answers\$_.txt") })
        if ($done.Count -lt $ids.Count) { return $level }
        $ok = @($Results | Where-Object {
                $_.Family -eq $Family -and [int]$_.Level -eq $level -and $_.Pass -eq 'True' }).Count
        if ($ok / $cfg.PerLevel -le $Ceiling) { $streak++ } else { $streak = 0 }
        if ($streak -ge $StopAfter) { return $null }
    }
    $null
}

function Get-Pending([hashtable]$Skip) {
    # Finish one run before the next, so a budget stop leaves whole runs.
    foreach ($r in $RunDir) {
        $ids = if ($All) {
            Get-ChildItem -LiteralPath $promptDir -Filter *.txt | ForEach-Object BaseName
        }
        elseif ($Staircase) {
            # ladder.ps1 grades the replies so far and writes the next prompts.
            $out = pwsh -NoProfile -File $ladderScript -Mode Staircase -Seed $seed -Dir $r
            if ($LASTEXITCODE -ne 0) { throw "Staircase failed for ${r}:`n$($out -join "`n")" }
            $out | Where-Object { $_ -match '^PENDING (\S+)$' } | ForEach-Object { $Matches[1] }
        }
        else {
            pwsh -NoProfile -File $ladderScript -Mode Verify -Seed $seed -Dir $r | Out-Null
            $results = @(Import-Csv -LiteralPath (Join-Path $r 'results.csv'))
            foreach ($family in $cfg.Families) {
                $level = Get-NextLevel $r $family $results
                if ($null -eq $level) { continue }
                foreach ($i in 1..$cfg.PerLevel) { '{0}-L{1:d2}-{2}' -f $family, $level, $i }
            }
        }
        $prompts = if ($Staircase) { Join-Path $r 'prompts' } else { $promptDir }
        $items = foreach ($id in $ids) {
            if (-not (Test-Path (Join-Path $r "answers\$id.txt")) -and -not $Skip["$r|$id"]) {
                [pscustomobject]@{ Run = $r; Id = $id; Prompt = Join-Path $prompts "$id.txt" }
            }
        }
        if ($items) { return @($items) }
    }
    @()
}

$promptDir = if ($LadderDir) { Join-Path $LadderDir 'prompts' }
$argLine = ('-p --model {0} --effort {1} --tools "" --strict-mcp-config --setting-sources "" ' +
    '--no-session-persistence --output-format stream-json --verbose --system-prompt "{2}"') -f
    $Model, $Effort, $SystemPrompt.Replace('"', '\"')
# Caps one API call. Claude Code then continues in a new call: see Test-Cut.
$env:CLAUDE_CODE_MAX_OUTPUT_TOKENS = "$cap"

$runOne = {
    param($Item, $Claude, $ArgLine, $Neutral, $TimeoutMinutes, $Cap, $CutCostUsd, $Model)
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $limitText = 'Output token limit hit'

    function Read-Events([string]$Path) {
        if (-not (Test-Path -LiteralPath $Path)) { return @() }
        # The writer still holds the file open.
        $fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        try { $text = [IO.StreamReader]::new($fs).ReadToEnd() } finally { $fs.Dispose() }
        foreach ($line in $text -split "`n") {
            if (-not $line.Trim()) { continue }
            try { $line | ConvertFrom-Json -Depth 30 } catch { }
        }
    }
    # A cut reply keeps the text written before the cap and is graded as it is.
    function Test-Cut($Events) {
        foreach ($e in $Events) {
            if ($e.type -eq 'user' -and ($e | ConvertTo-Json -Depth 30 -Compress) -match $limitText) {
                return $true
            }
        }
        $false
    }

    $res = $null
    $err = ''
    $cost = 0.0
    for ($attempt = 1; $attempt -le 3 -and -not $res; $attempt++) {
        $tmp = Join-Path $env:TEMP ("battery-{0}" -f [guid]::NewGuid().ToString('n'))
        $started = Get-Date
        $p = Start-Process -FilePath $Claude -ArgumentList $ArgLine `
            -RedirectStandardInput $Item.Prompt -RedirectStandardOutput "$tmp.out" `
            -RedirectStandardError "$tmp.err" -WorkingDirectory $Neutral -NoNewWindow -PassThru
        $cut = $false
        $timedOut = $false
        while (-not $p.WaitForExit(1500)) {
            if (Test-Cut @(Read-Events "$tmp.out")) { $cut = $true; break }
            if (((Get-Date) - $started).TotalMinutes -gt $TimeoutMinutes) { $timedOut = $true; break }
        }
        if ($cut -or $timedOut) { try { $p.Kill($true) } catch { } ; $p.WaitForExit() }
        $events = @(Read-Events "$tmp.out")
        if (-not $cut) { $cut = Test-Cut $events }
        $final = @($events | Where-Object type -EQ 'result') | Select-Object -Last 1
        if ($cut) {
            # Keep only the text of the first call, before the limit message.
            $text = foreach ($e in $events) {
                if ($e.type -eq 'user') { break }
                if ($e.type -eq 'assistant') {
                    foreach ($c in @($e.message.content)) { if ($c.type -eq 'text') { $c.text } }
                }
            }
            $cost += $CutCostUsd
            $res = [pscustomobject]@{
                Text = ($text -join ''); Cut = $true; CostUsd = $null; EstimateUsd = $CutCostUsd
                OutputTokens = $Cap; ThinkingTokens = $null; Model = $Model
                DurationMs = [int]((Get-Date) - $started).TotalMilliseconds
            }
        }
        elseif ($timedOut) { $err = 'timeout' }
        elseif (-not $final) { $err = 'no result event: ' + (Get-Content "$tmp.err" -Raw) }
        else {
            $cost += [double]$final.total_cost_usd
            if ($final.is_error) { $err = "$($final.result)" }
            else {
                $res = [pscustomobject]@{
                    Text = [string]$final.result; Cut = $false; CostUsd = [double]$final.total_cost_usd
                    EstimateUsd = $null; OutputTokens = $final.usage.output_tokens
                    ThinkingTokens = $final.usage.output_tokens_details.thinking_tokens
                    Model = ($final.modelUsage.PSObject.Properties.Name -join ',')
                    DurationMs = $final.duration_ms
                }
            }
        }
        Remove-Item "$tmp.out", "$tmp.err" -ErrorAction SilentlyContinue
        if (-not $res -and $attempt -lt 3) { Start-Sleep -Seconds (60 * $attempt) }
    }
    if ($res) {
        $raw = $res.Text
        # Email addresses are personal data: the replies are published.
        $clean = [regex]::Replace($raw, '[\w.+-]+@[\w-]+(\.[\w-]+)+', '[redacted-email]')
        $sha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
                [Text.Encoding]::UTF8.GetBytes($raw))).ToLowerInvariant()
        [ordered]@{
            id = $Item.Id; model = $res.Model; budget = $Cap; cutAtBudget = $res.Cut
            costUsd = $res.CostUsd; costEstimateUsd = $res.EstimateUsd; durationMs = $res.DurationMs
            outputTokens = $res.OutputTokens; thinkingTokens = $res.ThinkingTokens
            rawSha256 = $sha; redacted = $clean -ne $raw
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Item.Run "meta\$($Item.Id).json") -Encoding utf8NoBOM
        # The answer file goes last: its presence marks the trial as done.
        Set-Content -LiteralPath (Join-Path $Item.Run "answers\$($Item.Id).txt") -Value $clean `
            -Encoding utf8NoBOM -NoNewline
    }
    [pscustomobject]@{
        Run = $Item.Run; Id = $Item.Id; Ok = [bool]$res; Cut = $res -and $res.Cut
        Tokens = if ($res) { $res.OutputTokens } else { 0 }; Cost = $cost; Error = $err
    }
}

$spent = 0.0
$skip = @{}
$running = @{}
$stopping = $false
while ($true) {
    if (-not $stopping) {
        foreach ($item in Get-Pending $skip) {
            $key = "$($item.Run)|$($item.Id)"
            if ($running.ContainsKey($key) -or $running.Count -ge $Parallel) { continue }
            $running[$key] = Start-ThreadJob -ScriptBlock $runOne -ArgumentList $item, $claude, $argLine,
                $neutral, $TimeoutMinutes, $cap, $cutCostUsd, $Model
        }
    }
    if ($running.Count -eq 0) { break }
    $finished = Wait-Job -Job @($running.Values) -Any
    foreach ($key in @($running.Keys)) {
        $job = $running[$key]
        if ($job.State -notin 'Completed', 'Failed') { continue }
        $running.Remove($key)
        $o = Receive-Job $job -ErrorAction Continue | Select-Object -Last 1
        Remove-Job $job
        if (-not $o) { $skip[$key] = $true; "ERROR $key`: job failed"; continue }
        $spent += $o.Cost
        if (-not $o.Ok) {
            $skip[$key] = $true
            "ERROR $($o.Id) in $(Split-Path $o.Run -Leaf): $($o.Error)"
        }
        else {
            '{0:HH:mm} {1,-16} {2,6} tokens{3}  chunk spend {4:n2} USD' -f (Get-Date), $o.Id, $o.Tokens,
            $(if ($o.Cut) { ' (cut at budget)' } else { '' }), $spent
        }
    }
    if ($spent -ge $ChunkUsd) { $stopping = $true }
}
if ($stopping) { 'STATUS: CHUNK' }
elseif ($skip.Count) { "STATUS: ERRORS ($($skip.Count) items failed, run again to retry)" }
else { 'STATUS: DONE' }
foreach ($r in $RunDir) {
    $metas = @(Get-ChildItem (Join-Path $r 'meta') -File | ForEach-Object {
            Get-Content $_.FullName -Raw | ConvertFrom-Json })
    $c = ($metas | ForEach-Object {
            if ($_.PSObject.Properties['costUsd'] -and $null -ne $_.costUsd) { $_.costUsd }
            elseif ($_.PSObject.Properties['costEstimateUsd']) { $_.costEstimateUsd } } |
        Measure-Object -Sum).Sum
    '{0}: {1} replies, total {2:n2} USD (cut replies estimated)' -f (Split-Path $r -Leaf), $metas.Count, $c
}
