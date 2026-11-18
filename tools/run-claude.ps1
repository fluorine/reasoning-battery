#requires -Version 7.0
# Runs ladder prompts through headless Claude Code with every tool disabled.
# Resumable. Exits after each spending chunk so the operator can check usage.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$LadderDir,
    [Parameter(Mandatory)][string[]]$RunDir,
    [Parameter(Mandatory)][string]$SeedFile,
    [string]$Model = 'claude-opus-5-5',
    [ValidateSet('low', 'medium', 'high', 'xhigh', 'max')][string]$Effort = 'high',
    [ValidateRange(1, 16)][int]$Parallel = 6,
    [double]$ChunkUsd = 10,
    [ValidateRange(1, 5)][int]$StopAfter = 2,
    [double]$Ceiling = 0.10,
    [int]$TimeoutMinutes = 40,
    [string]$SystemPrompt = 'You are a helpful assistant.'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ladderScript = Join-Path $PSScriptRoot '..\ladder.ps1'
$claude = (Get-Command claude).Source
$seed = (Get-Content -LiteralPath $SeedFile -Raw).Trim()
$cfg = Get-Content -LiteralPath (Join-Path $LadderDir 'config.json') -Raw | ConvertFrom-Json
$promptDir = Join-Path $LadderDir 'prompts'
$RunDir = @($RunDir -split ',' | Where-Object { $_ })
# A directory with no CLAUDE.md, settings or git repo above it.
$neutral = Join-Path $env:TEMP 'battery-neutral'
New-Item -ItemType Directory -Force $neutral | Out-Null

foreach ($r in $RunDir) {
    foreach ($sub in 'answers', 'meta') {
        New-Item -ItemType Directory -Force (Join-Path $r $sub) | Out-Null
    }
    Copy-Item -LiteralPath (Join-Path $LadderDir 'config.json') -Destination $r -Force
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
        pwsh -NoProfile -File $ladderScript -Mode Verify -Seed $seed -Dir $r | Out-Null
        $results = @(Import-Csv -LiteralPath (Join-Path $r 'results.csv'))
        $items = foreach ($family in $cfg.Families) {
            $level = Get-NextLevel $r $family $results
            if ($null -eq $level) { continue }
            foreach ($i in 1..$cfg.PerLevel) {
                $id = '{0}-L{1:d2}-{2}' -f $family, $level, $i
                if (-not (Test-Path (Join-Path $r "answers\$id.txt")) -and -not $Skip["$r|$id"]) {
                    [pscustomobject]@{ Run = $r; Id = $id }
                }
            }
        }
        if ($items) { return @($items) }
    }
    @()
}

$argLine = ('-p --model {0} --effort {1} --tools "" --strict-mcp-config --setting-sources "" ' +
    '--no-session-persistence --output-format json --system-prompt "{2}"') -f
    $Model, $Effort, $SystemPrompt.Replace('"', '\"')
$env:CLAUDE_CODE_MAX_OUTPUT_TOKENS = '64000'

$spent = 0.0
$skip = @{}
while ($true) {
    $pending = Get-Pending $skip
    if (-not $pending) {
        'STATUS: DONE'
        break
    }
    $wave = $pending | Select-Object -First $Parallel
    $out = $wave | ForEach-Object -ThrottleLimit $Parallel -Parallel {
        $item = $_
        $prompt = Join-Path $using:promptDir "$($item.Id).txt"
        $res = $null
        $err = ''
        $cost = 0.0
        for ($attempt = 1; $attempt -le 3 -and -not $res; $attempt++) {
            $tmp = Join-Path $env:TEMP ("battery-{0}" -f [guid]::NewGuid().ToString('n'))
            $p = Start-Process -FilePath $using:claude -ArgumentList $using:argLine `
                -RedirectStandardInput $prompt -RedirectStandardOutput "$tmp.out" `
                -RedirectStandardError "$tmp.err" -WorkingDirectory $using:neutral `
                -NoNewWindow -PassThru
            if (-not $p.WaitForExit($using:TimeoutMinutes * 60000)) {
                $p.Kill($true)
                $err = 'timeout'
            }
            else {
                try {
                    $j = Get-Content -LiteralPath "$tmp.out" -Raw | ConvertFrom-Json
                    $cost += [double]$j.total_cost_usd
                    if ($j.is_error) { $err = "$($j.result)" } else { $res = $j }
                }
                catch { $err = 'unreadable output: ' + (Get-Content "$tmp.err" -Raw) }
            }
            Remove-Item "$tmp.out", "$tmp.err" -ErrorAction SilentlyContinue
            if (-not $res -and $attempt -lt 3) { Start-Sleep -Seconds (60 * $attempt) }
        }
        $metaPath = Join-Path $item.Run "meta\$($item.Id).json"
        if ($res) {
            $raw = [string]$res.result
            # Email addresses are personal data: the replies are published.
            $clean = [regex]::Replace($raw, '[\w.+-]+@[\w-]+(\.[\w-]+)+', '[redacted-email]')
            $sha = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData(
                    [System.Text.Encoding]::UTF8.GetBytes($raw))).ToLowerInvariant()
            Set-Content -LiteralPath (Join-Path $item.Run "answers\$($item.Id).txt") -Value $clean `
                -Encoding utf8NoBOM -NoNewline
            [ordered]@{
                id = $item.Id; model = ($res.modelUsage.PSObject.Properties.Name -join ',')
                costUsd = $cost; durationMs = $res.duration_ms
                outputTokens = $res.usage.output_tokens
                thinkingTokens = $res.usage.output_tokens_details.thinking_tokens
                rawSha256 = $sha; redacted = $clean -ne $raw
            } | ConvertTo-Json | Set-Content -LiteralPath $metaPath -Encoding utf8NoBOM
        }
        [pscustomobject]@{ Run = $item.Run; Id = $item.Id; Ok = [bool]$res; Cost = $cost; Error = $err }
    }
    foreach ($o in $out) {
        $spent += $o.Cost
        if (-not $o.Ok) {
            $skip["$($o.Run)|$($o.Id)"] = $true
            "ERROR $($o.Id) in $(Split-Path $o.Run -Leaf): $($o.Error)"
        }
    }
    '{0:HH:mm} wave of {1} done, chunk spend {2:n2} USD' -f (Get-Date), @($wave).Count, $spent
    if ($spent -ge $ChunkUsd) {
        'STATUS: CHUNK'
        break
    }
}
foreach ($r in $RunDir) {
    $n = @(Get-ChildItem (Join-Path $r 'answers') -File).Count
    $c = (Get-ChildItem (Join-Path $r 'meta') -File | ForEach-Object {
            (Get-Content $_.FullName -Raw | ConvertFrom-Json).costUsd } | Measure-Object -Sum).Sum
    '{0}: {1} replies, total {2:n2} USD' -f (Split-Path $r -Leaf), $n, $c
}
