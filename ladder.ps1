#requires -Version 7.0
# Seeded reasoning battery. Grading is deterministic: no LLM judges.
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Generate', 'Key', 'Verify', 'Compare', 'Staircase',
        'Calibrate', 'Quiz', 'Superiority', 'Scan', 'Bundle', 'Import', 'CheckPrompts',
        'Report', 'Check')]
    [string]$Mode,
    [string]$Seed,
    [Parameter(Mandatory)][string]$Dir,
    [string[]]$BaselineDir,
    [string[]]$Families = @('sat', 'mult', 'track', 'induct', 'deduce', 'code', 'plan'),
    [ValidateRange(2, 30)][int]$MaxLevel = 10,
    [ValidateRange(1, 50)][int]$PerLevel = 5,
    # Output tokens per reply, hidden reasoning included. 0 = no stated limit.
    [ValidateRange(0, 1000000)][int]$Budget = 8000,
    [ValidateRange(1, 30)][int]$Start = 3,
    [ValidateRange(1, 200)][int]$Trials = 12,
    # Test only: Key answers wrongly above this level, so a staircase turns.
    [ValidateRange(0, 100)][int]$KeyUpTo = 0,
    [string]$Frontier,
    [ValidateRange(0.0, 0.5)][double]$Ceiling = 0.10,
    [ValidateRange(1, 200)][int]$PerFamily = 15,
    [string[]]$ReplyFile,
    [string]$Challenger,
    [string]$Challenged,
    [string]$Settings,
    [string]$Operator,
    [string]$Who = '@your-handle'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Self = $PSCommandPath

if (-not ('LadderGen.Stats' -as [type])) {
    Add-Type -TypeDefinition (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Families.cs') -Raw)
}

$Scale = @{
    sat    = @{ Base = 10; Growth = 1.3; Unit = 'variables' }
    mult   = @{ Base = 4; Growth = 1.35; Unit = 'digits' }
    track  = @{ Base = 8; Growth = 1.55; Unit = 'operations' }
    induct = @{ Base = 1; Growth = 1.25; Unit = 'rule steps' }
    deduce = @{ Base = 4; Growth = 1.1; Unit = 'people' }
    code   = @{ Base = 3; Growth = 1.4; Unit = 'statements' }
    plan   = @{ Base = 4; Growth = 1.4; Unit = 'moves' }
}
# pwsh -File passes "a,b" as one string, not as an array.
$Families = @($Families -split ',' | Where-Object { $_ })
$unknown = @($Families | Where-Object { -not $Scale.ContainsKey($_) })
if ($unknown) { throw "Unknown family: $($unknown -join ', '). Use: $($Scale.Keys -join ', ')." }
$Tokens = [string[]]('A'..'L')
$ModelNames = '(?i)\b(claude|opus|sonnet|haiku|fable|anthropic|gpt|chatgpt|openai|' +
    'gemini|google|deepmind|llama|meta|mistral|grok|xai|deepseek|qwen)\b'
# Published unbudgeted prompts use this text. Do not change it.
$OpenRules = @'
Rules: no tools, no code execution, no outside help. Reason as long as you need.
End your reply with the answer line in the exact format below.
Only the LAST line that starts with "ANSWER:" is graded.
'@

function Get-Rules([int]$Tokens) {
    if ($Tokens -le 0) { return $OpenRules }
    # Invariant culture: the prompt text must not change with the OS locale.
    $n = $Tokens.ToString('N0', [cultureinfo]::InvariantCulture)
    @"
Rules: no tools, no code execution, no outside help.
Your whole reply, including any hidden reasoning, is limited to $n tokens.
A reply that reaches the limit is cut off there. Leave room for the answer line.
End your reply with the answer line in the exact format below.
Only the LAST line that starts with "ANSWER:" is graded.
"@
}
$Rules = $OpenRules

function Get-Difficulty([string]$Family, [int]$Level) {
    $s = $Scale[$Family]
    $d = 0
    for ($l = 1; $l -le $Level; $l++) {
        $d = [math]::Max($d + 1, [int][math]::Round($s.Base * [math]::Pow($s.Growth, $l - 1)))
    }
    $d
}

function Get-Sha256Hex([string]$Text) {
    $hash = [System.Security.Cryptography.SHA256]::HashData(
        [System.Text.Encoding]::UTF8.GetBytes($Text))
    [Convert]::ToHexString($hash).ToLowerInvariant()
}

function New-Rng([string]$Id) {
    $hash = [System.Security.Cryptography.SHA256]::HashData(
        [System.Text.Encoding]::UTF8.GetBytes("$Seed|$Id"))
    [System.Random]::new([BitConverter]::ToInt32($hash, 0))
}

function New-Sat([System.Random]$Rng, [int]$N) {
    $plant = [bool[]]::new($N + 1)
    foreach ($v in 1..$N) { $plant[$v] = $Rng.Next(2) -eq 1 }
    $clauses = [System.Collections.Generic.List[int[]]]::new()
    $m = [int][math]::Round(4.2 * $N)
    while ($clauses.Count -lt $m) {
        $vars = [System.Collections.Generic.List[int]]::new()
        while ($vars.Count -lt 3) {
            $v = $Rng.Next(1, $N + 1)
            if (-not $vars.Contains($v)) { $vars.Add($v) }
        }
        $lits = [int[]]@(foreach ($v in $vars) {
                if ($Rng.Next(2) -eq 1) { $v } else { -$v } })
        $hits = 0
        foreach ($l in $lits) { if (($l -gt 0) -eq $plant[[math]::Abs($l)]) { $hits++ } }
        # 1-2 true literals only: literal polarity then leaks no planted value.
        if ($hits -in 1, 2) { $clauses.Add($lits) }
    }
    $lines = foreach ($c in $clauses) { '(' + ($c -join ' ') + ')' }
    $key = (1..$N | ForEach-Object { if ($plant[$_]) { $_ } else { -$_ } }) -join ' '
    @{
        N       = $N
        Clauses = $clauses
        Key     = $key
        Prompt  = @"
$Rules

Find a TRUE/FALSE value for each variable x1..x$N that satisfies every clause.
Each clause is an OR of three literals. A negative number is a negated variable.
At least one satisfying assignment exists. There are $($clauses.Count) clauses.

$($lines -join "`n")

Answer format: ANSWER: followed by $N signed integers separated by spaces,
one per variable, positive = TRUE, negative = FALSE. Example: ANSWER: 1 -2 3 ...
"@
    }
}

function New-Digits([System.Random]$Rng, [int]$D) {
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append($Rng.Next(1, 10))
    for ($i = 1; $i -lt $D; $i++) { [void]$sb.Append($Rng.Next(10)) }
    $sb.ToString()
}

function New-Mult([System.Random]$Rng, [int]$D) {
    $a = New-Digits $Rng $D
    $b = New-Digits $Rng $D
    @{
        Key    = ([bigint]::Parse($a) * [bigint]::Parse($b)).ToString()
        Prompt = @"
$Rules

Compute the exact product:

$a * $b

Answer format: ANSWER: followed by the product as a plain integer.
"@
    }
}

function New-Track([System.Random]$Rng, [int]$K) {
    $seq = [string[]]$Tokens.Clone()
    $ops = foreach ($t in 1..$K) {
        switch ($Rng.Next(3)) {
            0 {
                $i = $Rng.Next(1, 13)
                do { $j = $Rng.Next(1, 13) } while ($j -eq $i)
                $tmp = $seq[$i - 1]; $seq[$i - 1] = $seq[$j - 1]; $seq[$j - 1] = $tmp
                "swap $i $j"
            }
            1 {
                $i = $Rng.Next(1, 12)
                $j = $Rng.Next($i + 1, 13)
                [array]::Reverse($seq, $i - 1, $j - $i + 1)
                "reverse $i $j"
            }
            2 {
                $r = $Rng.Next(1, 12)
                $seq = [string[]]($seq[$r..11] + $seq[0..($r - 1)])
                "rotate $r"
            }
        }
    }
    @{
        Key    = $seq -join ' '
        Prompt = @"
$Rules

Start with this sequence (position 1 is the leftmost item):
$($Tokens -join ' ')

Apply these $K operations in order:
- swap i j: exchange the items at positions i and j.
- reverse i j: reverse the items at positions i through j, inclusive.
- rotate r: move the first r items to the end, in the same order.

$(($ops | ForEach-Object -Begin { $n = 0 } -Process { $n++; "$n. $_" }) -join "`n")

Answer format: ANSWER: followed by the final 12 letters separated by spaces.
"@
    }
}

function ConvertFrom-Generated($Generated) {
    @{
        Prompt  = "$Rules`n`n$($Generated.Body)"
        Key     = $Generated.Key
        Checker = $Generated.Check
    }
}

function New-Instance([string]$Family, [int]$Level, [string]$Key, [string]$Id) {
    $d = Get-Difficulty $Family $Level
    $rng = New-Rng $Key
    $inst = switch ($Family) {
        'sat' { New-Sat $rng $d }
        'mult' { New-Mult $rng $d }
        'track' { New-Track $rng $d }
        'induct' { ConvertFrom-Generated ([LadderGen.Induct]::Create($rng, $d)) }
        'deduce' { ConvertFrom-Generated ([LadderGen.Deduce]::Create($rng, $d)) }
        'code' { ConvertFrom-Generated ([LadderGen.Trace]::Create($rng, $d)) }
        'plan' { ConvertFrom-Generated ([LadderGen.Slide]::Create($rng, $d)) }
    }
    $inst.Id = $Id
    $inst.Family = $Family
    $inst.Level = $Level
    $inst.Difficulty = $d
    $inst
}

# Each trial's level follows from the grades of the trials before it, so a
# published run can be checked against the rule. Stops a family at the first
# trial with no answer file, unless OnPending supplies one.
function Get-StairWalk([scriptblock]$OnPending) {
    foreach ($family in $Stair.Families) {
        $level = [int]$Stair.Start
        foreach ($t in 1..[int]$Stair.Trials) {
            $id = '{0}-L{1:d2}-t{2:d2}' -f $family, $level, $t
            $inst = New-Instance $family $level "$($Stair.Run)|$id" $id
            $inst.Trial = $t
            $path = Join-Path $Dir "answers/$id.txt"
            if (-not (Test-Path -LiteralPath $path) -and
                -not ($OnPending -and (& $OnPending $inst $path))) {
                $inst.Pending = $true
                $inst
                break
            }
            $answer = Read-AnswerLine $path
            $inst.Pass = $null -ne $answer -and [bool](Test-Answer $inst $answer)
            $inst.Pending = $false
            $inst
            $level = if ($inst.Pass) { $level + 1 } else { [math]::Max(1, $level - 1) }
        }
    }
}

function Get-Instances {
    if ($Stair) { return Get-StairWalk }
    if ($Quiz) {
        foreach ($f in $Quiz) {
            foreach ($i in 1..$PerFamily) {
                $key = 'quiz-{0}-L{1:d2}-{2}' -f $f.Family, $f.Level, $i
                # Opaque id: the file name must not reveal family or level.
                $id = (Get-Sha256Hex "$Seed|id|$key").Substring(0, 12)
                New-Instance $f.Family $f.Level $key $id
            }
        }
        return
    }
    foreach ($family in $Families) {
        foreach ($level in 1..$MaxLevel) {
            foreach ($i in 1..$PerLevel) {
                $id = '{0}-L{1:d2}-{2}' -f $family, $level, $i
                New-Instance $family $level $id $id
            }
        }
    }
}

function Test-Sat($Inst, [string]$Answer) {
    if ($Answer -notmatch '^\s*-?\d{1,6}(\s+-?\d{1,6})*\s*$') { return $false }
    $nums = [int[]]($Answer.Trim() -split '\s+')
    if ($nums.Count -ne $Inst.N) { return $false }
    $val = [bool[]]::new($Inst.N + 1)
    $seen = [bool[]]::new($Inst.N + 1)
    foreach ($x in $nums) {
        $v = [math]::Abs($x)
        if ($v -lt 1 -or $v -gt $Inst.N -or $seen[$v]) { return $false }
        $seen[$v] = $true
        $val[$v] = $x -gt 0
    }
    foreach ($c in $Inst.Clauses) {
        $ok = $false
        foreach ($l in $c) {
            if (($l -gt 0) -eq $val[[math]::Abs($l)]) { $ok = $true; break }
        }
        if (-not $ok) { return $false }
    }
    $true
}

function Test-Answer($Inst, [string]$Answer) {
    if ($Inst.ContainsKey('Checker')) { return $Inst.Checker.Invoke($Answer) }
    switch ($Inst.Family) {
        'sat' { Test-Sat $Inst $Answer }
        'mult' { ($Answer -replace '[\s,_]', '') -ceq $Inst.Key }
        'track' { (($Answer.Trim() -split '\s+') -join ' ').ToUpperInvariant() -ceq $Inst.Key }
    }
}

function Read-AnswerLine([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $text = Get-Content -LiteralPath $Path -Raw
    if (-not $text) { return $null }
    $found = [regex]::Matches($text, '(?m)^[\s>*`]*ANSWER:\s*(.+?)[\s*`]*$')
    if ($found.Count -eq 0) { return $null }
    $found[$found.Count - 1].Groups[1].Value
}

function Save-Config {
    $cfg = if ($Stair) { $Stair }
    elseif ($Quiz) {
        [ordered]@{
            Kind = 'quiz'; Frontier = $Quiz; PerFamily = $PerFamily; Ceiling = $QuizCeiling
            Budget = $Budget
        }
    }
    else {
        [ordered]@{
            Kind = 'ladder'; Families = $Families; MaxLevel = $MaxLevel; PerLevel = $PerLevel
            Budget = $Budget
        }
    }
    $cfg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Dir 'config.json')
}

function Get-Prop($Object, [string]$Name, $Default = $null) {
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name] -and
        $null -ne $Object.$Name) { return $Object.$Name }
    $Default
}

# Output tokens from meta/<id>.json. Null when no reply has metadata.
function Get-TokenStats([string]$Path, $Rows) {
    $sum = 0.0
    $items = 0
    $solved = 0
    foreach ($r in $Rows) {
        $meta = Join-Path $Path "meta/$($r.Id).json"
        if (-not (Test-Path -LiteralPath $meta)) { continue }
        $m = Get-Content -LiteralPath $meta -Raw | ConvertFrom-Json
        $sum += [double](Get-Prop $m 'outputTokens' 0)
        $items++
        if ("$($r.Pass)" -eq 'True') { $solved++ }
    }
    if ($items -eq 0) { return $null }
    [ordered]@{
        Items = $items; Solved = $solved; OutputTokens = [long]$sum
        PerItem = [math]::Round($sum / $items)
        PerSolved = if ($solved) { [math]::Round($sum / $solved) } else { $null }
    }
}

function Format-Tokens($Value) {
    if ($null -eq $Value) { return 'n/a' }
    ([double]$Value).ToString('N0', [cultureinfo]::InvariantCulture)
}

function Get-WilsonUpper([double]$Rate, [double]$N) {
    if ($N -le 0) { return 1.0 }
    $z = 1.96
    $c = $Rate + $z * $z / (2 * $N)
    $s = $z * [math]::Sqrt($Rate * (1 - $Rate) / $N + $z * $z / (4 * $N * $N))
    [math]::Min(1.0, ($c + $s) / (1 + $z * $z / $N))
}

function Get-BaselineDirs {
    if (-not $BaselineDir) { throw 'BaselineDir is required.' }
    # pwsh -File passes "a,b" as one string, not as an array.
    @($BaselineDir -split ',' | Where-Object { $_ })
}

function Get-CiBounds([double[]]$Samples) {
    $sorted = [double[]]($Samples | Sort-Object)
    $sorted[[int]($sorted.Count * 0.025)], $sorted[[int]($sorted.Count * 0.975) - 1]
}

function Get-Curves([string]$Path) {
    $curves = [ordered]@{}
    $rows = Import-Csv -LiteralPath (Join-Path $Path 'results.csv')
    foreach ($fam in $rows | Group-Object Family) {
        $levels = $fam.Group | Group-Object { [int]$_.Level } | Sort-Object { [int]$_.Name }
        $curves[$fam.Name] = @{
            L  = [int[]]@($levels | ForEach-Object { [int]$_.Name })
            D  =[double[]]@($levels | ForEach-Object { [double]$_.Group[0].Difficulty })
            Ok = [int[]]@($levels | ForEach-Object { @($_.Group | Where-Object Pass -EQ 'True').Count })
            N  = [int[]]@($levels | ForEach-Object { $_.Count })
        }
    }
    $curves
}

function Invoke-Self([string[]]$Arguments) {
    $rest = @(if ($Arguments.Count -gt 1) { $Arguments[1..($Arguments.Count - 1)] })
    $out = & pwsh -NoProfile -File $Self -Mode $Arguments[0] @rest *>&1 | Out-String
    [pscustomobject]@{ Ok = $LASTEXITCODE -eq 0; Text = $out.TrimEnd() }
}

function Get-RunSeed([string]$Path) {
    $file = Join-Path $Path 'SEED.txt'
    if (-not (Test-Path -LiteralPath $file)) {
        throw "No SEED.txt in $Path. The seed is not revealed yet."
    }
    (Get-Content -LiteralPath $file -Raw).Trim()
}

function Format-D50([double]$Value, [int]$Censor) {
    $mark = switch ($Censor) { -1 { '<' } 1 { '>' } default { '' } }
    '{0}{1:n1}' -f $mark, $Value
}

$Quiz = $null
$Stair = $null
$QuizCeiling = $Ceiling
if ($Mode -in 'Generate', 'Key', 'Verify', 'Quiz', 'CheckPrompts', 'Staircase' -and -not $Seed) {
    throw 'Seed is required.'
}
$cfgPath = Join-Path $Dir 'config.json'
if ($Mode -eq 'Bundle' -and -not (Test-Path -LiteralPath $cfgPath) -and
    -not $PSBoundParameters.ContainsKey('Budget')) { $Budget = 0 }
if ($Mode -in 'Verify', 'CheckPrompts', 'Staircase', 'Key', 'Bundle' -and
    (Test-Path -LiteralPath $cfgPath)) {
    $cfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json
    # An old config has no Budget: its prompts state no limit.
    $Budget = [int](Get-Prop $cfg 'Budget' 0)
    switch ($cfg.Kind) {
        'quiz' {
            $Quiz = @($cfg.Frontier)
            $PerFamily = $cfg.PerFamily
            $QuizCeiling = Get-Prop $cfg 'Ceiling'
        }
        'staircase' { $Stair = $cfg }
        default {
            $Families = [string[]]$cfg.Families
            $MaxLevel = $cfg.MaxLevel
            $PerLevel = $cfg.PerLevel
        }
    }
}
elseif ($Mode -eq 'Staircase') {
    $Stair = [pscustomobject][ordered]@{
        Kind = 'staircase'; Families = $Families; Start = $Start; Trials = $Trials
        Budget = $Budget; Run = Split-Path $Dir -Leaf
    }
}
if ($Mode -in 'Quiz', 'Key' -and $Frontier) {
    $front = Get-Content -LiteralPath $Frontier -Raw | ConvertFrom-Json
    $Quiz = @($front.Frontier)
    $QuizCeiling = Get-Prop $front 'Ceiling'
    $fb = [int](Get-Prop $front 'Budget' 0)
    if ($PSBoundParameters.ContainsKey('Budget') -and $Budget -ne $fb) {
        throw "The frontier was calibrated with a budget of $fb tokens. Use the same budget."
    }
    $Budget = $fb
    if ($Mode -eq 'Key' -and $front.PSObject.Properties['PerFamily']) { $PerFamily = $front.PerFamily }
}
if ($Mode -eq 'Quiz' -and -not $Quiz) { throw 'Frontier is required: run Calibrate first.' }
$Rules = Get-Rules $Budget

switch ($Mode) {
    { $_ -in 'Generate', 'Quiz' } {
        $promptDir = Join-Path $Dir 'prompts'
        New-Item -ItemType Directory -Force $promptDir | Out-Null
        New-Item -ItemType Directory -Force (Join-Path $Dir 'answers') | Out-Null
        Save-Config
        $count = 0
        foreach ($inst in Get-Instances) {
            if ($inst.Prompt -match $ModelNames) {
                throw "Prompt $($inst.Id) names a model or vendor: '$($Matches[0])'."
            }
            $path = Join-Path $promptDir "$($inst.Id).txt"
            Set-Content -LiteralPath $path -Value $inst.Prompt -Encoding utf8NoBOM
            $count++
        }
        "Wrote $count prompts to $promptDir"
        "Seed commitment, SHA-256: $(Get-Sha256Hex $Seed)"
    }
    'Key' {
        $answerDir = Join-Path $Dir 'answers'
        if ((Test-Path $answerDir) -and (Get-ChildItem $answerDir -File)) {
            throw "$answerDir is not empty. Use a separate directory for the key."
        }
        New-Item -ItemType Directory -Force $answerDir | Out-Null
        Save-Config
        if ($Stair) {
            $write = {
                param($inst, $path)
                $a = if ($KeyUpTo -le 0 -or $inst.Level -le $KeyUpTo) { $inst.Key } else { 'none' }
                Set-Content -LiteralPath $path -Value "ANSWER: $a" -Encoding utf8NoBOM
                $true
            }
            $n = @(Get-StairWalk $write).Count
            "Wrote $n staircase answers to $answerDir"
            return
        }
        foreach ($inst in Get-Instances) {
            $path = Join-Path $answerDir "$($inst.Id).txt"
            Set-Content -LiteralPath $path -Value "ANSWER: $($inst.Key)" -Encoding utf8NoBOM
        }
        "Wrote reference answers to $answerDir"
    }
    'Staircase' {
        foreach ($sub in 'prompts', 'answers') {
            New-Item -ItemType Directory -Force (Join-Path $Dir $sub) | Out-Null
        }
        if (-not (Test-Path -LiteralPath $cfgPath)) { Save-Config }
        $done = 0
        $pending = foreach ($inst in Get-StairWalk) {
            $path = Join-Path $Dir "prompts/$($inst.Id).txt"
            if (-not (Test-Path -LiteralPath $path)) {
                if ($inst.Prompt -match $ModelNames) {
                    throw "Prompt $($inst.Id) names a model or vendor: '$($Matches[0])'."
                }
                Set-Content -LiteralPath $path -Value $inst.Prompt -Encoding utf8NoBOM
            }
            if ($inst.Pending) { $inst.Id } else { $done++ }
        }
        foreach ($id in $pending) { "PENDING $id" }
        $total = @($Stair.Families).Count * [int]$Stair.Trials
        'Trials done: {0} of {1}. Seed SHA-256: {2}' -f $done, $total, (Get-Sha256Hex $Seed)
    }
    'Verify' {
        $answerDir = Join-Path $Dir 'answers'
        $rows = foreach ($inst in Get-Instances) {
            if ($Stair) {
                if ($inst.Pending) { continue }
                [pscustomobject]@{
                    Id = $inst.Id; Family = $inst.Family; Level = $inst.Level
                    Difficulty = $inst.Difficulty; Trial = $inst.Trial; Pass = $inst.Pass
                }
                continue
            }
            $answer = Read-AnswerLine (Join-Path $answerDir "$($inst.Id).txt")
            $pass = $null -ne $answer -and [bool](Test-Answer $inst $answer)
            [pscustomobject]@{
                Id = $inst.Id; Family = $inst.Family; Level = $inst.Level
                Difficulty = $inst.Difficulty; Pass = $pass
            }
        }
        if (-not $rows) { throw "No graded replies in $answerDir." }
        $rows | Export-Csv -LiteralPath (Join-Path $Dir 'results.csv') -NoTypeInformation
        if ($Quiz) {
            foreach ($g in $rows | Group-Object Family) {
                $ok = @($g.Group | Where-Object Pass).Count
                '{0,-7} level {1,2}  {2,3}/{3} correct ({4:p0})' -f $g.Name,
                    $g.Group[0].Level, $ok, $g.Count, ($ok / $g.Count)
            }
        }
        else {
            $curves = Get-Curves $Dir
            foreach ($family in $curves.Keys) {
                $c = $curves[$family]
                $censor = 0
                $d50 = [LadderGen.Stats]::D50($c.D, $c.Ok, $c.N, [ref]$censor)
                '{0,-7} d50 {1,7} {2,-11} | correct per level: {3}' -f $family,
                    (Format-D50 $d50 $censor), $Scale[$family].Unit, ($c.Ok -join ' ')
            }
        }
        'TOTAL  {0}/{1} correct. Seed SHA-256: {2}' -f @($rows | Where-Object Pass).Count,
            $rows.Count, (Get-Sha256Hex $Seed)
    }
    'Compare' {
        $reps = 2000
        $candidate = Get-Curves $Dir
        $baselines = @(Get-BaselineDirs | ForEach-Object { Get-Curves $_ })
        $logSamples = [System.Collections.Generic.List[double[]]]::new()
        $logPoint = 0.0
        $anyWorse = $false
        foreach ($family in $candidate.Keys) {
            if (@($baselines | Where-Object { -not $_.Contains($family) }).Count) {
                "skip    $family is missing from a baseline."
                continue
            }
            $c = $candidate[$family]
            $cc = 0
            $dc = [LadderGen.Stats]::D50($c.D, $c.Ok, $c.N, [ref]$cc)
            $db = 0.0
            $bc = 0
            foreach ($b in $baselines) {
                $x = 0
                $v = [LadderGen.Stats]::D50($b[$family].D, $b[$family].Ok, $b[$family].N, [ref]$x)
                if ($v -gt $db) { $db = $v; $bc = $x }
            }
            $samples = [LadderGen.Stats]::BootRatios($c.D, $c.Ok, $c.N,
                [double[][]]@($baselines | ForEach-Object { , $_[$family].D }),
                [int[][]]@($baselines | ForEach-Object { , $_[$family].Ok }),
                [int[][]]@($baselines | ForEach-Object { , $_[$family].N }), $reps, 7)
            $sorted = $samples | Sort-Object
            $lo = $sorted[[int]($reps * 0.025)]
            $hi = $sorted[[int]($reps * 0.975) - 1]
            if ($hi -lt 1) { $anyWorse = $true }
            $logSamples.Add([double[]]@($samples | ForEach-Object { [math]::Log($_) }))
            $logPoint += [math]::Log($dc / $db)
            $note = @()
            if ($cc -eq 1) { $note += 'candidate above scale: raise MaxLevel' }
            if ($bc -eq 1) { $note += 'baseline above scale: raise MaxLevel' }
            if ($cc -eq -1 -or $bc -eq -1) { $note += 'below scale' }
            '{0,-7} d50 {1,7} vs {2,7}  score {3,5:p0}  95% CI {4:p0}-{5:p0} {6}' -f $family,
                (Format-D50 $dc $cc), (Format-D50 $db $bc), ($dc / $db), $lo, $hi, ($note -join '; ')
        }
        $f = $logSamples.Count
        if ($f -eq 0) { throw 'No family is in both the candidate and every baseline.' }
        $geo = foreach ($r in 0..($reps - 1)) {
            $s = 0.0
            foreach ($ls in $logSamples) { $s += $ls[$r] }
            [math]::Exp($s / $f)
        }
        $geo = $geo | Sort-Object
        $glo = $geo[[int]($reps * 0.025)]
        $ghi = $geo[[int]($reps * 0.975) - 1]
        'OVERALL score {0:p0}  95% CI {1:p0}-{2:p0}  (100% = best baseline)' -f
            [math]::Exp($logPoint / $f), $glo, $ghi
        if ($glo -gt 1 -and -not $anyWorse) { 'VERDICT: superior on this battery' }
        else { 'VERDICT: not shown' }
    }
    'Calibrate' {
        $dirs = @(Get-BaselineDirs)
        $cfgs = @($dirs | ForEach-Object {
                Get-Content -LiteralPath (Join-Path $_ 'config.json') -Raw | ConvertFrom-Json })
        if ($cfgs[0].Kind -eq 'staircase') {
            if (@($cfgs | Where-Object Kind -NE 'staircase').Count) {
                throw 'Do not mix staircase and ladder runs.'
            }
            $bud = @($cfgs | ForEach-Object { [int](Get-Prop $_ 'Budget' 0) } | Sort-Object -Unique)
            if ($bud.Count -ne 1) { throw "The runs have different budgets: $($bud -join ', ')." }
            $rows = @(foreach ($d in $dirs) {
                    foreach ($r in Import-Csv -LiteralPath (Join-Path $d 'results.csv')) {
                        $r | Add-Member -NotePropertyName Dir -NotePropertyValue $d -PassThru
                    } })
            $front = foreach ($fam in $rows | Group-Object Family) {
                $family = $fam.Name
                $levels = @($fam.Group | Group-Object { [int]$_.Level } | Sort-Object { [int]$_.Name })
                $L = [int[]]@($levels | ForEach-Object { [int]$_.Name })
                $D = [double[]]@($levels | ForEach-Object { [double]$_.Group[0].Difficulty })
                $ok = [int[]]@($levels | ForEach-Object { @($_.Group | Where-Object Pass -EQ 'True').Count })
                $n = [int[]]@($levels | ForEach-Object { $_.Count })
                $censor = 0
                $d50 = if ($L.Count -ge 2) { [LadderGen.Stats]::D50($D, $ok, $n, [ref]$censor) }
                else { $censor = if ($ok[0] / $n[0] -ge 0.5) { 1 } else { -1 }; $D[0] }
                if ($censor -ne 0) {
                    Write-Warning "${family}: the 50% point is outside the levels that the staircase visited. Run more trials."
                }
                # The level whose difficulty is nearest to d50 on a log scale.
                $level = 1..30 | Sort-Object {
                    [math]::Abs([math]::Log((Get-Difficulty $family $_) / $d50)) } | Select-Object -First 1
                $fit = [LadderGen.Stats]::Monotone($ok, $n)
                $i = [array]::IndexOf($L, $level)
                $rate = $null
                $hi = 1.0
                if ($i -ge 0) {
                    $rate = $fit[$i]
                    # The bound uses the count pooled by the isotonic fit.
                    $pooled = 0
                    for ($j = 0; $j -lt $L.Count; $j++) {
                        if ([math]::Abs($fit[$j] - $rate) -lt 1e-9) { $pooled += $n[$j] }
                    }
                    $hi = Get-WilsonUpper $rate $pooled
                }
                else {
                    Write-Warning "${family}: level $level was not visited. Its challenger rate is unknown (bound set to 100%)."
                }
                $tok = $null
                foreach ($d in $dirs) {
                    $t = Get-TokenStats $d @($fam.Group | Where-Object Dir -EQ $d)
                    if ($t) {
                        if (-not $tok) { $tok = @{ Sum = 0.0; Items = 0; Solved = 0 } }
                        $tok.Sum += $t.OutputTokens; $tok.Items += $t.Items; $tok.Solved += $t.Solved
                    }
                }
                [ordered]@{
                    Family = $family; Level = $level; Difficulty = Get-Difficulty $family $level
                    Unit = $Scale[$family].Unit; D50 = [math]::Round($d50, 2); D50Censor = $censor
                    Rate = if ($null -ne $rate) { [math]::Round($rate, 3) } else { $null }
                    RateHi = [math]::Round($hi, 3); Trials = ($n | Measure-Object -Sum).Sum
                    TokensPerItem = if ($tok) { [math]::Round($tok.Sum / $tok.Items) } else { $null }
                    TokensPerSolved = if ($tok -and $tok.Solved) { [math]::Round($tok.Sum / $tok.Solved) } else { $null }
                }
            }
            New-Item -ItemType Directory -Force $Dir | Out-Null
            $out = Join-Path $Dir 'frontier.json'
            [ordered]@{
                Kind = 'staircase'; Budget = $bud[0]; Target = 0.5
                Runs = @($dirs | ForEach-Object { Split-Path $_ -Leaf }); Frontier = @($front)
            } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $out
            foreach ($f in $front) {
                $r = if ($null -ne $f.Rate) { ([double]$f.Rate).ToString('p0') } else { 'n/a' }
                ('{0,-7} level {1,2} = {2,4} {3,-11} d50 {4,7}  fit {5,4} (95% upper {6:p0})  ' +
                    'tokens per item {7}, per solved {8}') -f $f.Family, $f.Level, $f.Difficulty, $f.Unit,
                (Format-D50 $f.D50 $f.D50Censor), $r, $f.RateHi, (Format-Tokens $f.TokensPerItem),
                (Format-Tokens $f.TokensPerSolved)
            }
            "Wrote $out"
            return
        }
        $runs = @($dirs | ForEach-Object { Get-Curves $_ })
        $front = foreach ($family in $runs[0].Keys) {
            if (@($runs | Where-Object { -not $_.Contains($family) }).Count) { continue }
            $levels = $runs[0][$family]
            $fits = @($runs | ForEach-Object {
                    , [LadderGen.Stats]::Monotone($_[$family].Ok, $_[$family].N) })
            $hit = $null
            $worst = 1.0
            for ($i = 0; $i -lt $levels.L.Count; $i++) {
                $worst = ($fits | ForEach-Object { $_[$i] } | Measure-Object -Maximum).Maximum
                if ($worst -le $Ceiling) { $hit = $i; break }
            }
            if ($null -eq $hit) {
                Write-Warning "${family}: baseline success stays above $($Ceiling.ToString('p0')). Raise MaxLevel."
                continue
            }
            [ordered]@{
                Family = $family; Level = $levels.L[$hit]; Difficulty = $levels.D[$hit]
                Unit = $Scale[$family].Unit; BaselineRate = [math]::Round($worst, 3)
            }
        }
        if (-not $front) { throw 'No family has a level at or below the ceiling.' }
        New-Item -ItemType Directory -Force $Dir | Out-Null
        $out = Join-Path $Dir 'frontier.json'
        @{ Ceiling = $Ceiling; Frontier = @($front) } | ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath $out
        foreach ($f in $front) {
            '{0,-7} level {1,2} = {2,4} {3,-11} worst baseline run {4:p0}' -f $f.Family,
                $f.Level, $f.Difficulty, $f.Unit, $f.BaselineRate
        }
        "Wrote $out"
    }
    'Superiority' {
        $cfgQ = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json
        if ($cfgQ.Kind -ne 'quiz') { throw 'Dir must be a graded quiz directory.' }
        $cand = @(Import-Csv -LiteralPath (Join-Path $Dir 'results.csv'))
        $ceil = Get-Prop $cfgQ 'Ceiling'
        # Uncontrolled: assume the top of the challenger's calibration CI.
        $bound = @{}
        foreach ($f in $cfgQ.Frontier) {
            $h = Get-Prop $f 'RateHi'
            if ($null -ne $h) { $bound[$f.Family] = [double]$h }
        }
        $assume = if ($bound.Count) { 'bound' } else { 'ceiling' }
        if ($assume -eq 'ceiling') { $ceil = [double]$(if ($null -ne $ceil) { $ceil } else { 0.10 }) }
        $controlled = [bool]$BaselineDir
        $chal = @{}
        if ($controlled) {
            $best = $null
            $bestOk = -1
            foreach ($b in Get-BaselineDirs) {
                $r = @(Import-Csv -LiteralPath (Join-Path $b 'results.csv'))
                $k = @($r | Where-Object Pass -EQ 'True').Count
                if ($k -gt $bestOk) { $best = $r; $bestOk = $k }
            }
            foreach ($r in $best) { $chal[$r.Id] = $r.Pass -eq 'True' }
            if ($chal.Count -ne $cand.Count) { throw 'The quiz directories hold different items.' }
        }
        else {
            # No control: the assumed score is subtracted later.
            foreach ($r in $cand) { $chal[$r.Id] = $false }
        }

        $groups = @($cand | Group-Object Family | ForEach-Object { , @($_.Name, $_.Group) })
        $groups += , @('OVERALL', $cand)
        $bootSeed = 11
        $result = foreach ($g in $groups) {
            $rows = @($g[1])
            $a = [bool[]]@($rows | ForEach-Object { $_.Pass -eq 'True' })
            $b = [bool[]]@($rows | ForEach-Object {
                    if (-not $chal.ContainsKey($_.Id)) { throw "Baseline lacks item $($_.Id)." }
                    $chal[$_.Id] })
            $failed = 0
            $beyond = 0
            for ($i = 0; $i -lt $a.Count; $i++) {
                if (-not $b[$i]) { $failed++; if ($a[$i]) { $beyond++ } }
            }
            $lo, $hi = Get-CiBounds ([LadderGen.Stats]::BootPairedDiff($a, $b, 2000, $bootSeed++))
            $ra = @($a | Where-Object { $_ }).Count / $a.Count
            $rb = @($b | Where-Object { $_ }).Count / $b.Count
            if (-not $controlled) {
                $rb = if ($assume -eq 'ceiling') { $ceil } else {
                    ($rows | ForEach-Object {
                            if (-not $bound.ContainsKey($_.Family)) { throw "No bound for $($_.Family)." }
                            $bound[$_.Family] } | Measure-Object -Average).Average
                }
                $lo -= $rb; $hi -= $rb
            }
            [pscustomobject]@{
                Label = $g[0]; N = $a.Count; Baseline = $rb; Candidate = $ra
                Points = ($ra - $rb) * 100; Lo = $lo * 100; Hi = $hi * 100
                Beyond = if ($failed -and $controlled) { $beyond / $failed } else { [double]::NaN }
            }
        }
        'Superiority = candidate success - baseline success on the frontier quiz, in points.'
        if (-not $controlled -and $assume -eq 'ceiling') {
            'UNCONTROLLED: no baseline run on this quiz. Baseline set to the {0:p0} ceiling.' -f $ceil
        }
        elseif (-not $controlled) {
            ('UNCONTROLLED: no baseline run on this quiz. Baseline set to the upper end of ' +
                'its calibration 95% CI in each family, a conservative value.')
        }
        foreach ($x in $result) {
            $beyond = if ([double]::IsNaN($x.Beyond)) { 'n/a' } else { $x.Beyond.ToString('p0') }
            ('{0,-8} n={1,-4} baseline {2,4:p0}  candidate {3,4:p0}  superiority {4,4:+0;-0;0} ' +
                '(95% CI {5:+0;-0;0} to {6:+0;-0;0})  solved {7} of baseline failures') -f
            $x.Label, $x.N, $x.Baseline, $x.Candidate, $x.Points, $x.Lo, $x.Hi, $beyond
        }
        $all = $result[-1]
        $verdict = if ($all.Lo -gt 0) { 'superior' } else { 'not shown' }
        [ordered]@{
            Controlled = $controlled; Assumed = $(if ($controlled) { 'none' } else { $assume })
            Ceiling = $ceil; Verdict = $verdict
            Rows = @($result | ForEach-Object {
                    [ordered]@{
                        Label = $_.Label; N = $_.N
                        Baseline = [math]::Round($_.Baseline, 4); Candidate = [math]::Round($_.Candidate, 4)
                        Points = [math]::Round($_.Points, 1); Lo = [math]::Round($_.Lo, 1)
                        Hi = [math]::Round($_.Hi, 1)
                    } })
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $Dir 'superiority.json')
        if ($controlled -and $assume -eq 'ceiling' -and $all.Baseline -gt $ceil) {
            Write-Warning ((
                    'Baseline scored {0:p0} on this quiz, above the {1:p0} ceiling. ' +
                    'Calibrate again with more problems per level.') -f $all.Baseline, $ceil)
        }
        if ($controlled -and $assume -eq 'bound') {
            foreach ($x in $result | Where-Object { $_.Label -ne 'OVERALL' }) {
                if ($x.Baseline -gt $bound[$x.Label]) {
                    Write-Warning ((
                            '{0}: baseline scored {1:p0}, above the upper end of its calibration ' +
                            '({2:p0}). The frontier is easier for it than calibrated. ' +
                            'Sharpen the calibration with more trials.') -f $x.Label, $x.Baseline,
                        $bound[$x.Label])
                }
            }
        }
        if ($controlled -and $all.Baseline -ge 0.9) {
            Write-Warning 'Baseline is near 100%. The quiz cannot show a gain.'
        }
        foreach ($x in $result | Where-Object { $_.Label -ne 'OVERALL' -and $_.Candidate -ge 0.9 }) {
            Write-Warning "$($x.Label): candidate is near 100%. Its superiority there is a lower bound."
        }
        if ($all.Lo -gt 0) {
            'VERDICT: candidate superior by {0:n0} points (95% CI {1:n0} to {2:n0})' -f
                $all.Points, $all.Lo, $all.Hi
        }
        else { 'VERDICT: superiority not shown' }
    }
    'Scan' {
        $checks = [ordered]@{
            'invisible or bidi characters'   =
                '[\u200B-\u200F\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF]|\uDB40[\uDC00-\uDC7F]'
            'names a model or vendor'        = $ModelNames
            'addresses the test or graders'  =
                '(?i)\b(grader|graders|evaluator|auditor|judge|benchmark|test author|' +
                'baseline|candidate|challenger|superiority)\b'
            'long encoded-looking token'     =
                '(?=[A-Za-z0-9+/]*[A-Za-z])(?=[A-Za-z0-9+/]*\d)[A-Za-z0-9+/]{40,}'
        }
        $files = @(Get-ChildItem -LiteralPath (Join-Path $Dir 'answers') -File)
        $flagged = 0
        foreach ($file in $files) {
            $text = Get-Content -LiteralPath $file.FullName -Raw
            if (-not $text) { continue }
            $why = @(foreach ($name in $checks.Keys) {
                    if ([regex]::IsMatch($text, $checks[$name])) { $name } })
            $last = [regex]::Matches($text, '(?m)^[\s>*`]*ANSWER:[^\r\n]*')
            if ($last.Count -and $text.Substring($last[$last.Count - 1].Index +
                    $last[$last.Count - 1].Length).Trim()) {
                $why += 'text after the answer line'
            }
            if ($why) { $flagged++; '{0}  {1}' -f $file.Name, ($why -join '; ') }
        }
        'Scanned {0} replies. Flagged {1} for auditor review.' -f $files.Count, $flagged
    }
    'Bundle' {
        $prompts = @(Get-ChildItem -LiteralPath (Join-Path $Dir 'prompts') -Filter *.txt |
                Sort-Object Name)
        if (-not $prompts) { throw "No prompts in $Dir. Run Generate or Quiz first." }
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine(@"
# Problem set

This file holds $($prompts.Count) independent problems. Each problem is complete in
itself. The problems have no connection to each other.

How to answer:

1. Do not use tools, code execution, search or outside help.
2. For each problem, start a new line with the marker ITEM and the problem's id,
   for example: ITEM $($prompts[0].BaseName)
3. After the marker, write your work, then the answer line in the exact format
   that the problem asks for. In each problem's section, only the last line that
   starts with "ANSWER:" is graded.
4. Answer as many problems as you can, in any order. A problem with no answer
   counts as wrong. If you stop early, the next message will ask you to continue.
$(if ($Budget -gt 0) { @"
5. Each problem states a token limit. Keep your work on each problem, including
   any hidden reasoning, within that limit.

"@ })
"@)
        foreach ($p in $prompts) {
            $text = Get-Content -LiteralPath $p.FullName -Raw
            if ($text -match $ModelNames) {
                throw "Prompt $($p.BaseName) names a model or vendor: '$($Matches[0])'."
            }
            [void]$sb.AppendLine("----- PROBLEM $($p.BaseName) -----")
            [void]$sb.AppendLine($text.TrimEnd())
            [void]$sb.AppendLine("----- END OF PROBLEM $($p.BaseName) -----")
            [void]$sb.AppendLine()
        }
        $out = Join-Path $Dir 'bundle.md'
        Set-Content -LiteralPath $out -Value $sb.ToString() -Encoding utf8NoBOM -NoNewline
        'Wrote {0} problems to {1} ({2:n0} KB)' -f $prompts.Count, $out, ((Get-Item $out).Length / 1KB)
    }
    'CheckPrompts' {
        $bad = 0
        $n = 0
        $seen = @{}
        foreach ($inst in Get-Instances) {
            $n++
            $path = Join-Path $Dir "prompts/$($inst.Id).txt"
            # Git and the OS may change line endings, so compare without them.
            $want = ($inst.Prompt -replace '\r\n', "`n").TrimEnd()
            $have = if (Test-Path -LiteralPath $path) {
                ((Get-Content -LiteralPath $path -Raw) -replace '\r\n', "`n").TrimEnd()
            }
            if ($have -cne $want) { $bad++; "MISMATCH $($inst.Id)" }
            $seen[$inst.Id] = $true
        }
        if ($Stair) {
            # A prompt off the path: a trial was skipped or resampled.
            foreach ($p in Get-ChildItem -LiteralPath (Join-Path $Dir 'prompts') -Filter *.txt) {
                if (-not $seen.ContainsKey($p.BaseName)) { $bad++; "EXTRA $($p.BaseName)" }
            }
        }
        'Checked {0} prompts against the seed. Mismatches: {1}.' -f $n, $bad
    }
    'Import' {
        if (-not $ReplyFile) { throw 'ReplyFile is required.' }
        $ReplyFile = @($ReplyFile -split ',' | Where-Object { $_ })
        $known = @{}
        foreach ($p in Get-ChildItem -LiteralPath (Join-Path $Dir 'prompts') -Filter *.txt) {
            $known[$p.BaseName] = $true
        }
        $answerDir = Join-Path $Dir 'answers'
        New-Item -ItemType Directory -Force $answerDir | Out-Null
        $found = @{}
        $unknown = 0
        foreach ($f in $ReplyFile) {
            $text = Get-Content -LiteralPath $f -Raw
            $marks = [regex]::Matches($text, '(?m)^[\s#>*`]*ITEM\s+([A-Za-z0-9-]+)[\s*`:]*$')
            for ($i = 0; $i -lt $marks.Count; $i++) {
                $id = $marks[$i].Groups[1].Value
                if (-not $known.ContainsKey($id)) { $unknown++; continue }
                $start = $marks[$i].Index + $marks[$i].Length
                $end = if ($i + 1 -lt $marks.Count) { $marks[$i + 1].Index } else { $text.Length }
                # A later section for the same id replaces the earlier one.
                $found[$id] = $text.Substring($start, $end - $start).Trim()
            }
        }
        foreach ($id in $found.Keys) {
            Set-Content -LiteralPath (Join-Path $answerDir "$id.txt") -Value $found[$id] `
                -Encoding utf8NoBOM -NoNewline
        }
        'Imported {0} of {1} problems. Unknown ids skipped: {2}. Missing: {3}.' -f $found.Count,
            $known.Count, $unknown, ($known.Count - $found.Count)
    }
    'Report' {
        foreach ($p in 'Challenger', 'Challenged', 'Settings', 'Operator') {
            if (-not (Get-Variable $p -ValueOnly)) { throw "$p is required." }
        }
        $seedText = if ($Seed) { $Seed } else { Get-RunSeed $Dir }
        $cand = Join-Path $Dir 'candidate'
        $base = Join-Path $Dir 'baseline'
        $hasBase = Test-Path -LiteralPath (Join-Path $base 'answers')
        $sides = @($cand) + @(if ($hasBase) { $base })
        foreach ($s in $sides) {
            Copy-Item -LiteralPath (Join-Path $Dir 'quiz/config.json') -Destination $s -Force
            $v = Invoke-Self 'Verify', '-Seed', $seedText, '-Dir', $s
            if (-not $v.Ok) { throw "Verify failed for ${s}:`n$($v.Text)" }
        }
        $supArgs = @('Superiority', '-Dir', $cand) + @(if ($hasBase) { '-BaselineDir', $base })
        $sup = Invoke-Self $supArgs
        if (-not $sup.Ok) { throw "Superiority failed:`n$($sup.Text)" }
        $scan = ($sides | ForEach-Object {
                "$(Split-Path $_ -Leaf):`n" + (Invoke-Self 'Scan', '-Dir', $_).Text }) -join "`n`n"
        $sj = Get-Content -LiteralPath (Join-Path $cand 'superiority.json') -Raw | ConvertFrom-Json
        $all = $sj.Rows[-1]
        $leaf = Split-Path (Resolve-Path -LiteralPath $Dir) -Leaf
        $date = if ($leaf -match '\d{4}-\d{2}-\d{2}') { $Matches[0] } else { Get-Date -Format 'yyyy-MM-dd' }
        $control = if ($hasBase) { 'yes' } else { Get-Prop $sj 'Assumed' 'ceiling' }
        $quizCfg = Get-Content -LiteralPath (Join-Path $Dir 'quiz/config.json') -Raw | ConvertFrom-Json
        $tokens = [ordered]@{}
        foreach ($s in $sides) {
            $side = if ($s -eq $cand) { 'Candidate' } else { 'Baseline' }
            $tokens[$side] = Get-TokenStats $s @(Import-Csv -LiteralPath (Join-Path $s 'results.csv'))
        }
        $perSolved = foreach ($side in 'Baseline', 'Candidate') {
            if ($tokens.Contains($side) -and $tokens[$side]) { Format-Tokens $tokens[$side].PerSolved }
            else { 'n/a' }
        }
        $row = ('| {0} | `{1}` | `{2}` | {3} | {4} | {5} | {6:p0} | {7:p0} | {8:+0;-0;0} | ' +
            '{9:+0;-0;0} to {10:+0;-0;0} | {13} | {11} | 0 | [folder](runs/{12}/) |') -f $date, $Challenger,
            $Challenged, $Settings, $Operator, $control, [double]$all.Baseline, [double]$all.Candidate,
            [double]$all.Points, [double]$all.Lo, [double]$all.Hi, $sj.Verdict, $leaf, ($perSolved -join ' / ')
        [ordered]@{
            Date = $date; Challenger = $Challenger; Challenged = $Challenged; Settings = $Settings
            Operator = $Operator; Control = $control; Budget = [int](Get-Prop $quizCfg 'Budget' 0)
            SeedSha256 = (Get-Sha256Hex $seedText); Verdict = $sj.Verdict; Rows = $sj.Rows
            Tokens = $tokens
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Dir 'result.json')
        $tokLines = foreach ($side in $tokens.Keys) {
            $t = $tokens[$side]
            if ($t) {
                '| Output tokens, {0} | {1} per item, {2} per solved item ({3} items) |' -f $side.ToLower(),
                    (Format-Tokens $t.PerItem), (Format-Tokens $t.PerSolved), $t.Items
            }
            else { '| Output tokens, {0} | n/a (no meta/ files) |' -f $side.ToLower() }
        }
        $budgetText = if ($quizCfg.PSObject.Properties['Budget'] -and [int]$quizCfg.Budget -gt 0) {
            '{0} tokens per reply' -f (Format-Tokens $quizCfg.Budget)
        }
        else { 'none stated' }
        $md = @"
# Result

| Item | Value |
|---|---|
| Date | $date |
| Challenger | ``$Challenger`` |
| Challenged | ``$Challenged`` |
| Settings | $Settings |
| Operator | $Operator |
| Control | $control |
| Budget | $budgetText |
| Seed SHA-256 | ``$(Get-Sha256Hex $seedText)`` |
| Verdict | $($sj.Verdict) |
$($tokLines -join "`n")

## Superiority

``````text
$($sup.Text)
``````

## Signal scan

``````text
$scan
``````

## README row

``````markdown
$row
``````
"@
        Set-Content -LiteralPath (Join-Path $Dir 'RESULT.md') -Value $md -Encoding utf8NoBOM
        "Wrote RESULT.md and result.json in $Dir"
        'Add this row to the Challenges table in README.md:'
        $row
    }
    'Check' {
        $steps = [System.Collections.Generic.List[object]]::new()
        function Add-Step([string]$Name, [bool]$Ok, [string]$Detail) {
            $steps.Add([pscustomobject]@{ Step = $Name; Ok = $Ok; Detail = $Detail })
        }
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("battery-check-" + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory $tmp | Out-Null
        $flagged = 0
        try {
            $seedText = Get-RunSeed $Dir
            $hash = Get-Sha256Hex $seedText
            $commit = Get-Content -LiteralPath (Join-Path $Dir 'COMMITMENT.md') -Raw
            Add-Step 'Seed matches commitment' ($commit -match $hash) $hash

            $isQuiz = Test-Path -LiteralPath (Join-Path $Dir 'quiz')
            # A staircase run holds its own prompts: the path depends on grades.
            $stairs = @(Get-ChildItem -LiteralPath $Dir -Directory -Filter 'stair*' | ForEach-Object Name)
            $problemDirs = @(if ($isQuiz) { Join-Path $Dir 'quiz' }
                elseif ($stairs) { $stairs | ForEach-Object { Join-Path $Dir $_ } }
                else { Join-Path $Dir 'ladder' })
            foreach ($pd in $problemDirs) {
                $cp = Invoke-Self 'CheckPrompts', '-Seed', $seedText, '-Dir', $pd
                $label = if ($stairs) { "Prompts match seed: $(Split-Path $pd -Leaf)" } else { 'Prompts match seed' }
                Add-Step $label ($cp.Ok -and $cp.Text -match 'Mismatches: 0\.') ($cp.Text -split "`n")[-1]
            }

            $sides = if ($isQuiz) {
                @('candidate', 'baseline') | Where-Object {
                    Test-Path -LiteralPath (Join-Path $Dir "$_/answers") }
            }
            elseif ($stairs) { $stairs }
            else {
                Get-ChildItem -LiteralPath $Dir -Directory | Where-Object Name -Match '^(base|pilot)' |
                    ForEach-Object Name
            }
            foreach ($s in $sides) {
                $copy = Join-Path $tmp $s
                New-Item -ItemType Directory $copy | Out-Null
                Copy-Item -LiteralPath (Join-Path $Dir "$s/answers") -Destination $copy -Recurse
                $metaDir = Join-Path $Dir "$s/meta"
                if (Test-Path -LiteralPath $metaDir) { Copy-Item -LiteralPath $metaDir -Destination $copy -Recurse }
                $cfgFrom = if ($stairs) { Join-Path $Dir "$s/config.json" }
                else { Join-Path $problemDirs[0] 'config.json' }
                Copy-Item -LiteralPath $cfgFrom -Destination $copy
                $v = Invoke-Self 'Verify', '-Seed', $seedText, '-Dir', $copy
                if ($stairs) {
                    $walked = @{}
                    foreach ($r in Import-Csv -LiteralPath (Join-Path $copy 'results.csv')) { $walked[$r.Id] = $true }
                    $off = @(Get-ChildItem -LiteralPath (Join-Path $copy 'answers') -File |
                            Where-Object { -not $walked.ContainsKey($_.BaseName) }).Count
                    $sc = Get-Content -LiteralPath $cfgFrom -Raw | ConvertFrom-Json
                    $want = @($sc.Families).Count * [int]$sc.Trials
                    $pathText = '{0} of {1} trials on the path, {2} replies off it' -f $walked.Count, $want, $off
                    Add-Step "Staircase follows rule: $s" ($v.Ok -and $off -eq 0) $pathText
                }
                $mine = @{}
                foreach ($r in Import-Csv -LiteralPath (Join-Path $copy 'results.csv')) { $mine[$r.Id] = $r.Pass }
                $theirsPath = Join-Path $Dir "$s/results.csv"
                $diff = if (Test-Path -LiteralPath $theirsPath) {
                    @(Import-Csv -LiteralPath $theirsPath | Where-Object { $mine[$_.Id] -ne $_.Pass }).Count
                }
                else { -1 }
                $detail = if ($diff -lt 0) { 'published results.csv missing' } else { "$diff items differ" }
                Add-Step "Grades reproduce: $s" ($v.Ok -and $diff -eq 0) $detail
                $sc = Invoke-Self 'Scan', '-Dir', (Join-Path $Dir $s)
                if ($sc.Text -match 'Flagged (\d+)') { $flagged += [int]$Matches[1] }
            }

            if ($isQuiz) {
                $cand = Join-Path $tmp 'candidate'
                $supArgs = @('Superiority', '-Dir', $cand) +
                    @(if ($sides -contains 'baseline') { '-BaselineDir', (Join-Path $tmp 'baseline') })
                $sup = Invoke-Self $supArgs
                $resPath = Join-Path $Dir 'result.json'
                $ok = $false
                $detail = 'result.json missing'
                if ($sup.Ok -and (Test-Path -LiteralPath $resPath)) {
                    $mineJ = Get-Content -LiteralPath (Join-Path $cand 'superiority.json') -Raw | ConvertFrom-Json
                    $pub = Get-Content -LiteralPath $resPath -Raw | ConvertFrom-Json
                    $a = $mineJ.Rows[-1]
                    $b = $pub.Rows[-1]
                    $ok = $mineJ.Verdict -eq $pub.Verdict -and $a.Points -eq $b.Points -and
                        $a.Lo -eq $b.Lo -and $a.Hi -eq $b.Hi
                    $detail = '{0:+0;-0;0} points ({1:+0;-0;0} to {2:+0;-0;0}), {3}' -f
                        [double]$a.Points, [double]$a.Lo, [double]$a.Hi, $mineJ.Verdict
                }
                Add-Step 'Superiority reproduces result.json' $ok $detail
            }
            else {
                $cal = Join-Path $tmp 'cal'
                $bases = ($sides | ForEach-Object { Join-Path $tmp $_ }) -join ','
                $c = Invoke-Self 'Calibrate', '-Dir', $cal, '-BaselineDir', $bases
                $pubPath = Join-Path $Dir 'frontier.json'
                $ok = $false
                $detail = 'frontier.json missing'
                $stopped = Join-Path $Dir 'STOPPED.md'
                if (-not (Test-Path -LiteralPath $pubPath) -and (Test-Path -LiteralPath $stopped)) {
                    $ok = $true
                    $detail = 'none: the run was stopped (STOPPED.md)'
                }
                elseif ($c.Ok -and (Test-Path -LiteralPath $pubPath)) {
                    $key = { param($f) (@($f.Frontier) | Sort-Object Family |
                                ForEach-Object { "$($_.Family)=$($_.Level)" }) -join ' ' }
                    $mineF = & $key (Get-Content -LiteralPath (Join-Path $cal 'frontier.json') -Raw | ConvertFrom-Json)
                    $pubF = & $key (Get-Content -LiteralPath $pubPath -Raw | ConvertFrom-Json)
                    $ok = $mineF -eq $pubF
                    $detail = $mineF
                }
                Add-Step 'Frontier reproduces frontier.json' $ok $detail
            }
        }
        catch { Add-Step 'Check ran to the end' $false $_.Exception.Message }
        finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }

        $steps | ForEach-Object { '{0,-4} {1,-36} {2}' -f $(if ($_.Ok) { 'OK' } else { 'FAIL' }), $_.Step, $_.Detail }
        "Scan flagged $flagged replies for review."
        $allOk = -not ($steps | Where-Object { -not $_.Ok })
        $outcome = if ($allOk) { 'reproduced' } else { 'differs' }
        ''
        'Add this row to VERIFICATIONS.md in the folder:'
        '| {0} | {1} | check | all | {2} | Scan flagged {3} replies |' -f (Get-Date -Format 'yyyy-MM-dd'),
            $Who, $outcome, $flagged
        if (-not $allOk) { exit 1 }
    }
}
