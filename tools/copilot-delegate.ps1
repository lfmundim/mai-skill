#!/usr/bin/env pwsh
#Requires -Version 5.1
<#
.SYNOPSIS
    MAI delegate runner for Windows — PowerShell port of copilot-delegate.

.DESCRIPTION
    Runs GitHub Copilot CLI in programmatic mode, streams output live via async
    Process events, captures AIC cost via OTel, runs post-execution syntax checks,
    and appends a JSON run log entry — identical behaviour to the bash version.

    Key Windows differences vs the bash version:
      - Uses System.Diagnostics.Process + async OutputDataReceived events for streaming
        and timeout (Start-Job caused copilot to detect no TTY and stall)
      - Writes a temp runner .ps1 so copilot is invoked via & inside a real PS child
        process — avoids all command-line argument escaping issues for complex prompts
      - Prints a heartbeat line every 30s so long-running tasks don't look hung
      - Uses [DateTime]::UtcNow.Ticks for high-precision timing (avoids 'date +%s%N')
      - Detects 'python3' then 'python' — Windows installers often register as 'python'
      - Temp/log paths use $HOME (e.g. C:\Users\you) — consistent with Git Bash paths

    PROMPT SAFETY:
      Prompt is written to a UTF-8 temp file. The runner script reads it via
      [IO.File]::ReadAllText and passes it to copilot -p via PowerShell's & operator,
      which handles braces, quotes, Unicode, emoji, and other special characters.

    VERSION CHECK:
      Stores copilot CLI version in ~/.local/share/copilot-delegate-cli-version and
      warns when it changes — silent CLI auto-updates can silently break flag names.

    POLICY DETECTION:
      Detects enterprise admin policy blocks on --yolo / --allow-tool and surfaces a
      clear remediation message.

    RUN LOG:
      Appends one JSONL entry to ~/.local/share/delegate-runs.jsonl after each run.
      Fields: ts, delegate, workdir, project, executor_model, executor_model_fallback,
              exit_code, timed_out, files_changed, syntax_errors, duration_secs,
              tokens_in, tokens_out, tokens_cached, tokens_reasoning, cost_aic.

.PARAMETER Workdir
    Absolute path to the git repository where Copilot will make changes. Must exist.

.PARAMETER Prompt
    Self-contained task description. Written to a temp file — do not pre-escape it.

.PARAMETER Model
    Executor model ID. Always pass explicitly. Defaults to 'gpt-5-mini' if omitted.

.PARAMETER TimeoutSecs
    Wall-clock kill timeout in seconds. Defaults to 300.

.PARAMETER VerboseOutput
    Show full AIC token breakdown instead of compact summary.
    Also enabled by setting $env:DELEGATE_VERBOSE = 'true' before calling.

.EXAMPLE
    & "$HOME\tools\copilot-delegate.ps1" "C:\projects\myapp" "Add rate limiting to POST /auth" "gpt-5-mini" 300

.EXAMPLE
    # Verify installation works end-to-end:
    & "$HOME\tools\copilot-delegate.ps1" $env:TEMP "Say hello in one sentence." gpt-5-mini 30
#>
param(
    [Parameter(Position = 0, Mandatory = $true)][string]$Workdir,
    [Parameter(Position = 1, Mandatory = $true)][string]$Prompt,
    [Parameter(Position = 2)][string]$Model = 'gpt-5-mini',
    [Parameter(Position = 3)][int]$TimeoutSecs = 300,
    [switch]$VerboseOutput
)

$ErrorActionPreference = 'Stop'

# Also honour the env var SKILL.md sets when the user passes --verbose
if ($env:DELEGATE_VERBOSE -eq 'true') { $VerboseOutput = [switch]$true }

# ── Validate workdir ──────────────────────────────────────────────────────────
if (-not (Test-Path -LiteralPath $Workdir -PathType Container)) {
    Write-Error "ERROR: workdir '$Workdir' does not exist"
    exit 1
}

# ── Default model guard ────────────────────────────────────────────────────────
if (-not $Model) {
    $Model = 'gpt-5-mini'
    Write-Host "[warn] No model specified — defaulting to gpt-5-mini"
}

# ── Detect Python 3 (Windows may register it as 'python', not 'python3') ──────
$pythonCmd = $null
foreach ($candidate in @('python3', 'python')) {
    if (Get-Command $candidate -ErrorAction SilentlyContinue) {
        $ver = & $candidate --version 2>&1
        if ([string]$ver -match 'Python 3') { $pythonCmd = $candidate; break }
    }
}

# ── Model-fallback flag set by orchestrator via env var ───────────────────────
$modelFallback = ($env:DELEGATE_MODEL_FALLBACK -eq 'true')

# ── CLI version check ─────────────────────────────────────────────────────────
# Copilot CLI auto-updates silently. Record the version and warn on change so
# flag-name breakage is caught early instead of producing confusing errors.
$versionFile   = Join-Path $HOME '.local\share\copilot-delegate-cli-version'
$currentVersion = ''
if (Get-Command copilot -ErrorAction SilentlyContinue) {
    $currentVersion = ([string](& copilot --version 2>$null | Select-Object -First 1)).Trim()
}
$versionDir = Split-Path $versionFile
if (-not (Test-Path $versionDir)) { New-Item -ItemType Directory -Force $versionDir | Out-Null }
if ((Test-Path $versionFile) -and $currentVersion) {
    $storedVersion = (Get-Content $versionFile -Raw -ErrorAction SilentlyContinue).Trim()
    if ($storedVersion -and $storedVersion -ne $currentVersion) {
        Write-Host "[WARN] Copilot CLI version changed: $storedVersion -> $currentVersion"
        Write-Host "       Verify --allow-tool and --yolo flags still work — names may have changed."
    }
}
if ($currentVersion) { [IO.File]::WriteAllText($versionFile, $currentVersion) }

# ── Timing — .NET Ticks are 100-nanosecond units ─────────────────────────────
# Multiply by 100 to get nanoseconds, matching bash's 'date +%s%N' precision.
# Only the DELTA matters (duration), so the epoch base is irrelevant.
$startNs = [DateTime]::UtcNow.Ticks * 100L

# ── Capture git state before delegate runs ────────────────────────────────────
Push-Location $Workdir
$gitBefore = (git rev-parse HEAD 2>$null) ?? 'no-git'
$filesBefore = @(
    git diff --name-only 2>$null
    git ls-files --others --exclude-standard 2>$null
) | Where-Object { $_ }
Pop-Location

# ── OTel output file — copilot writes real AIC and token data here ────────────
$otelFile = [IO.Path]::GetTempFileName() + '.jsonl'
Remove-Item ([IO.Path]::GetTempFileName()) -ErrorAction SilentlyContinue  # clean the GetTempFileName side-effect

# ── Write prompt to temp file (avoids argument-length limits + injection) ──────
$promptFile = [IO.Path]::GetTempFileName()
[IO.File]::WriteAllText($promptFile, $Prompt, [Text.Encoding]::UTF8)

# ── Print header ──────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== MAI-DELEGATE START ==="
Write-Host "Workdir : $Workdir"
if ($modelFallback) {
    Write-Host "Model   : $Model  (fallback — MAI-Code-1-Flash not available)"
} else {
    Write-Host "Model   : $Model"
}
Write-Host "Timeout : ${TimeoutSecs}s"
Write-Host "Prompt  : $($Prompt.Substring(0, [Math]::Min(120, $Prompt.Length)))..."
Write-Host "=========================="

# ── Helper: run copilot as a real child process, stream output, enforce timeout ─
#
# WHY NOT Start-Job:
#   Start-Job creates a background PowerShell process with no console attached.
#   The Copilot CLI detects the missing TTY and either buffers all output until
#   exit or stalls waiting for interactive input — both look like a hang to the user.
#
# HOW THIS WORKS:
#   1. A temp runner .ps1 is written containing the copilot invocation. This
#      sidesteps all ProcessStartInfo.Arguments escaping headaches — paths and
#      model names are embedded with PS single-quote escaping; the prompt content
#      is read from $PFile at runtime by the runner via [IO.File]::ReadAllText.
#   2. System.Diagnostics.Process launches powershell.exe -File <runner> with
#      stdout/stderr redirected and async OutputDataReceived events enabled.
#      WaitForExit(150ms) loops until done or timeout.
#   3. [Console]::WriteLine in the event handler is thread-safe — output appears
#      immediately as copilot emits it, no polling lag.
#   4. A heartbeat line prints every 30s during long silent runs ("Copilot still
#      running… Ns elapsed") so users can distinguish "working" from "hung".
#
# AllowFlags controls --allow-tool vs --allow-all-tools (used on the gpt-5-mini retry).
function Invoke-CopilotWithTimeout {
    param(
        [string]$WDir,
        [string]$PFile,
        [string]$Mdl,
        [string]$Otel,
        [int]$Secs,
        [string[]]$AllowFlags = @('--allow-all-tools')
    )

    # Escape single quotes in path values so they embed safely in the runner script.
    # Windows paths never contain single quotes normally, but guard anyway.
    $safeWDir  = $WDir  -replace "'", "''"
    $safePFile = $PFile -replace "'", "''"
    $safeMdl   = $Mdl   -replace "'", "''"
    $safeOtel  = $Otel  -replace "'", "''"
    $allowStr  = $AllowFlags -join ' '

    # The runner script: runs copilot inside a real PS child process so copilot
    # inherits a proper parent context and does not detect a missing console.
    $runnerBody = @"
`$ErrorActionPreference = 'Continue'
`$env:COPILOT_OTEL_FILE_EXPORTER_PATH = '$safeOtel'
Set-Location '$safeWDir'
`$p = [IO.File]::ReadAllText('$safePFile', [Text.Encoding]::UTF8)
& copilot -p `$p --model '$safeMdl' $allowStr --yolo 2>&1
exit `$LASTEXITCODE
"@
    $runnerFile = [IO.Path]::GetTempFileName() + '.ps1'
    [IO.File]::WriteAllText($runnerFile, $runnerBody, [Text.Encoding]::UTF8)

    # Pick the right PS executable (pwsh for PS 7+, powershell for PS 5.1)
    $psExe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $psExe
    $psi.Arguments              = "-NoProfile -ExecutionPolicy Bypass -File `"$runnerFile`""
    $psi.UseShellExecute        = $false   # required for output redirection
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow         = $false   # inherit parent console so ANSI colours work

    # ConcurrentQueue preserves insertion order (ConcurrentBag does not)
    $outputQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

    $outId = "MAI-Out-$(Get-Random)"
    $errId = "MAI-Err-$(Get-Random)"

    # Event handler — called from the async output thread.
    # [Console]::WriteLine is thread-safe; writing directly to stdout bypasses
    # PS's output buffering so lines appear immediately.
    $handler = {
        $data = $EventArgs.Data
        if ($null -ne $data) {
            [Console]::WriteLine($data)
            $Event.MessageData.Enqueue($data)
        }
    }

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    Register-ObjectEvent -InputObject $proc -EventName 'OutputDataReceived' `
        -SourceIdentifier $outId -Action $handler -MessageData $outputQueue | Out-Null
    Register-ObjectEvent -InputObject $proc -EventName 'ErrorDataReceived' `
        -SourceIdentifier $errId -Action $handler -MessageData $outputQueue | Out-Null

    $proc.Start() | Out-Null
    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()

    $sw       = [Diagnostics.Stopwatch]::StartNew()
    $timedOut = $false
    $lastBeat = -1

    # Loop: WaitForExit(150ms) returns $false when still running, $true when done.
    while (-not $proc.WaitForExit(150)) {
        $elapsed = [int]$sw.Elapsed.TotalSeconds
        if ($elapsed -ge $Secs) {
            try { $proc.Kill() } catch {}
            $timedOut = $true
            break
        }
        # Heartbeat every 30s — distinguishes "copilot working silently" from "frozen"
        $beat = [Math]::Floor($elapsed / 30)
        if ($elapsed -ge 30 -and $beat -ne $lastBeat) {
            $lastBeat = $beat
            [Console]::WriteLine("[wait] Copilot still running... (${elapsed}s elapsed, timeout ${Secs}s)")
        }
    }

    # Second WaitForExit() with no timeout ensures all async output callbacks finish.
    # This is the standard .NET pattern for Process + BeginOutputReadLine.
    $proc.WaitForExit()
    Start-Sleep -Milliseconds 200   # final drain window for event handlers

    $exitCode = if ($timedOut) { 124 } else { $proc.ExitCode }

    # Clean up event subscriptions and temp runner
    Unregister-Event -SourceIdentifier $outId -ErrorAction SilentlyContinue
    Unregister-Event -SourceIdentifier $errId -ErrorAction SilentlyContinue
    Get-Job | Where-Object { $_.Name -in @($outId, $errId) } |
        Remove-Job -Force -ErrorAction SilentlyContinue
    $proc.Dispose()
    Remove-Item $runnerFile -ErrorAction SilentlyContinue

    # Drain queue into an ordered list for pattern matching
    $lines = [Collections.Generic.List[string]]::new()
    $item  = $null
    while ($outputQueue.TryDequeue([ref]$item)) { $lines.Add($item) }

    return @{ ExitCode = $exitCode; TimedOut = $timedOut; Output = $lines -join "`n" }
}

# ── First invocation ──────────────────────────────────────────────────────────
$run = Invoke-CopilotWithTimeout -WDir $Workdir -PFile $promptFile -Mdl $Model `
                                  -Otel $otelFile -Secs $TimeoutSecs

$copilotExit = $run.ExitCode
$timedOut    = $run.TimedOut
$outputText  = $run.Output

# ── Model-not-found cascade → retry with gpt-5-mini ──────────────────────────
# The orchestrator tries MAI-Code-1-Flash first; if unavailable, fall back here.
$modelNotFoundRx = 'model not found|unknown model|invalid model|model.*not available|no such model|model.*not supported'
if (($outputText -imatch $modelNotFoundRx) -and $Model -ne 'gpt-5-mini') {
    Write-Host ""
    Write-Host "[warn] Model '$Model' not available — retrying with gpt-5-mini"
    $Model         = 'gpt-5-mini'
    $modelFallback = $true

    $run2        = Invoke-CopilotWithTimeout -WDir $Workdir -PFile $promptFile -Mdl $Model `
                                              -Otel $otelFile -Secs $TimeoutSecs `
                                              -AllowFlags @('--allow-all-tools')
    $copilotExit = $run2.ExitCode
    $timedOut    = $run2.TimedOut
    $outputText  = $run2.Output

    if ($outputText -imatch $modelNotFoundRx) {
        Write-Host ""
        Write-Host "  Neither MAI-Code-1-Flash nor gpt-5-mini were available. Delegation aborted."
        Write-Host "  Override permanently: /mai-model-pick <alias>"
        Remove-Item $promptFile, $otelFile -ErrorAction SilentlyContinue
        exit 1
    }
} elseif (($outputText -imatch $modelNotFoundRx) -and $Model -eq 'gpt-5-mini') {
    Write-Host ""
    Write-Host "  Neither MAI-Code-1-Flash nor gpt-5-mini were available. Delegation aborted."
    Write-Host "  Override permanently: /mai-model-pick <alias>"
    Remove-Item $promptFile, $otelFile -ErrorAction SilentlyContinue
    exit 1
}

Write-Host ""

# ── Enterprise policy detection ───────────────────────────────────────────────
$policyRx = 'admin policy|not permitted|tool.{0,20}blocked|blocked by.{0,20}policy|permission denied|tool.*not allowed|yolo.*not allowed|allow-tool.*not allowed'
if ($outputText -imatch $policyRx) {
    Write-Host "[ERROR] Enterprise admin policy is blocking --yolo or --allow-tool."
    Write-Host "        These flags require explicit permission in managed Copilot environments."
    Write-Host "        Action: contact your administrator, or check your organization's Copilot policy settings."
    Write-Host "        Workaround: run copilot interactively (without --yolo) and approve each tool call manually."
}

if ($timedOut) {
    Write-Host "=== MAI-DELEGATE TIMEOUT (>${TimeoutSecs}s) — killed ==="
} else {
    Write-Host "=== MAI-DELEGATE DONE (exit: $copilotExit) ==="
}

# ── Determine which files changed during the run ──────────────────────────────
Push-Location $Workdir
$filesAfter = @(
    git diff --name-only 2>$null
    git ls-files --others --exclude-standard 2>$null
) | Where-Object { $_ }
Pop-Location

# New files = in filesAfter but not in filesBefore
$beforeSet    = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($f in $filesBefore) { $beforeSet.Add($f) | Out-Null }
$changedFiles = $filesAfter | Where-Object { -not $beforeSet.Contains($_) }

# ── Post-run syntax checks ────────────────────────────────────────────────────
# Calls python3/python to run the same per-language checks as the bash version.
# Writes changed filenames to an env var; Python reads them.
$syntaxErrors = 0
if ($pythonCmd -and $changedFiles) {
    $env:DELEGATE_CHANGED = $changedFiles -join "`n"

    $syntaxScript = @'
import os, shutil, subprocess

changed = [f for f in os.environ.get('DELEGATE_CHANGED', '').splitlines() if f.strip()]
errors  = 0
checked = 0

def has(cmd):
    return shutil.which(cmd) is not None

def check(cmd, label):
    global errors, checked
    r = subprocess.run(cmd, capture_output=True, text=True)
    checked += 1
    if r.returncode != 0:
        errors += 1
        msg = (r.stderr or r.stdout).strip().split('\n')[0][:120]
        print(f'  [SYNTAX ERROR] {label}: {msg}')

for f in changed:
    if not os.path.isfile(f):
        continue
    if f.endswith('.py'):
        check(['python3', '-m', 'py_compile', f], f)
    elif f.endswith(('.js', '.mjs', '.cjs')) and has('node'):
        check(['node', '--check', f], f)
    elif f.endswith('.swift') and has('swiftc'):
        check(['swiftc', '-typecheck', f], f)

live = [f for f in changed if os.path.isfile(f)]
if any(f.endswith('.go') for f in live) and has('go'):
    check(['go', 'vet', './...'], 'go vet')
if any(f.endswith('.rs') for f in live) and has('cargo'):
    check(['cargo', 'check', '--quiet'], 'cargo check')
if any(f.endswith('.cs') for f in live) and has('dotnet'):
    check(['dotnet', 'build', '--no-restore', '-v', 'q'], 'dotnet build')
if any(f.endswith(('.ts', '.tsx')) for f in live):
    import pathlib
    if has('tsc') and pathlib.Path('tsconfig.json').exists():
        check(['tsc', '--noEmit', '--skipLibCheck'], 'tsc --noEmit')

if checked > 0:
    if errors == 0:
        print(f'=== SYNTAX OK ({checked} check(s)) ===')
    else:
        print(f'=== SYNTAX ERRORS: {errors} in {checked} check(s) — fix before committing ===')

# Write error count to stdout as a sentinel the caller can parse
print(f'##SYNTAX-ERRORS:{errors}##')
'@

    $syntaxFile = [IO.Path]::GetTempFileName() + '.py'
    [IO.File]::WriteAllText($syntaxFile, $syntaxScript, [Text.Encoding]::UTF8)

    Push-Location $Workdir
    $syntaxOutput = & $pythonCmd $syntaxFile 2>&1
    Pop-Location

    Remove-Item $syntaxFile -ErrorAction SilentlyContinue
    Remove-Item Env:\DELEGATE_CHANGED -ErrorAction SilentlyContinue

    foreach ($line in $syntaxOutput) {
        $s = [string]$line
        if ($s -match '^##SYNTAX-ERRORS:(\d+)##$') { $syntaxErrors = [int]$Matches[1] }
        else { Write-Host $s }
    }
}

# ── Git summary ───────────────────────────────────────────────────────────────
Push-Location $Workdir
$gitAfter = (git rev-parse HEAD 2>$null) ?? 'no-git'

if ($gitBefore -ne 'no-git' -and $gitAfter -ne 'no-git' -and $gitBefore -ne $gitAfter) {
    Write-Host ""
    Write-Host "=== COMMITS CREATED ==="
    git log "$gitBefore..$gitAfter" --oneline
    Write-Host ""
    Write-Host "=== DIFF STAT ==="
    git diff "$gitBefore..$gitAfter" --stat
} else {
    Write-Host ""
    Write-Host "=== UNCOMMITTED CHANGES ==="
    git diff --stat -- $Workdir 2>$null
    git status --short -- $Workdir 2>$null
}
Pop-Location

# ── AIC report + run log via Python ───────────────────────────────────────────
$endNs          = [DateTime]::UtcNow.Ticks * 100L
$filesChanged   = ($changedFiles | Measure-Object).Count
$isVerbose      = $VerboseOutput.IsPresent

# Pass all context as env vars — same pattern as the bash version
$env:DELEGATE_WORKDIR          = $Workdir
$env:DELEGATE_EXIT             = [string]$copilotExit
$env:DELEGATE_TIMEOUT          = [string]$TimeoutSecs
$env:DELEGATE_MODEL            = $Model
$env:DELEGATE_MODEL_FALLBACK   = [string]$modelFallback
$env:DELEGATE_FILES_CHANGED    = [string]$filesChanged
$env:DELEGATE_SYNTAX_ERRORS    = [string]$syntaxErrors
$env:DELEGATE_START_NS         = [string]$startNs
$env:DELEGATE_END_NS           = [string]$endNs
$env:DELEGATE_OTEL_FILE        = $otelFile
$env:VERBOSE                   = if ($isVerbose) { 'true' } else { 'false' }

$logScript = @'
import json, os
from pathlib import Path
from datetime import datetime, timezone

LOG     = Path.home() / '.local' / 'share' / 'delegate-runs.jsonl'
LOG.parent.mkdir(parents=True, exist_ok=True)
verbose = os.environ.get('VERBOSE', 'false').lower() == 'true'

start_ns = int(os.environ.get('DELEGATE_START_NS', 0) or 0)
end_ns   = int(os.environ.get('DELEGATE_END_NS',   0) or 0)
duration = round((end_ns - start_ns) / 1e9, 1) if start_ns and end_ns else 0

exit_code     = int(os.environ.get('DELEGATE_EXIT', 0) or 0)
timed_out     = exit_code == 124
files_changed = int(os.environ.get('DELEGATE_FILES_CHANGED', 0) or 0)
syntax_errors = int(os.environ.get('DELEGATE_SYNTAX_ERRORS', 0) or 0)
workdir       = os.environ.get('DELEGATE_WORKDIR', '')
model         = os.environ.get('DELEGATE_MODEL', '')
fallback      = os.environ.get('DELEGATE_MODEL_FALLBACK', 'false').lower() == 'true'
otel_file     = os.environ.get('DELEGATE_OTEL_FILE', '')

# ── Parse OTel span for real AIC + token counts ───────────────────────────────
tokens_in = tokens_out = tokens_cached = tokens_reasoning = 0
cost_aic  = 0.0

if otel_file:
    try:
        for line in Path(otel_file).read_text(errors='replace').splitlines():
            if not line.strip():
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if obj.get('type') == 'span' and obj.get('name', '').startswith('invoke_agent'):
                attrs            = obj.get('attributes', {})
                tokens_in        = attrs.get('gen_ai.usage.input_tokens', 0)
                tokens_out       = attrs.get('gen_ai.usage.output_tokens', 0)
                tokens_cached    = attrs.get('gen_ai.usage.cache_read_input_tokens', 0)
                tokens_reasoning = attrs.get('gen_ai.usage.reasoning_output_tokens', 0)
                nano_aiu         = attrs.get('github.copilot.nano_aiu', 0)
                cost_aic         = round(nano_aiu / 1e9, 4) if nano_aiu else 0.0
                break
    except Exception:
        pass

# ── Print AIC summary ─────────────────────────────────────────────────────────
if cost_aic > 0 or tokens_in > 0:
    if verbose:
        print(f'[aic] {cost_aic:.4f} AIC')
        print(f'      up {tokens_in:,} tok ({tokens_cached:,} cached)  down {tokens_out:,} tok', end='')
        if tokens_reasoning:
            print(f' ({tokens_reasoning:,} reasoning)', end='')
        print()
    else:
        r = f' ({tokens_reasoning:,} reasoning)' if tokens_reasoning else ''
        print(f'[aic] {cost_aic:.4f} AIC  |  up{tokens_in:,} ({tokens_cached:,} cached) down{tokens_out:,}{r}')
else:
    print('[aic] OTel data not available — AIC unknown')

# ── Classify run outcome ──────────────────────────────────────────────────────
if timed_out:              reason = 'timeout'
elif exit_code not in (0, 124): reason = 'exit_error'
elif syntax_errors > 0:    reason = 'syntax_error'
elif files_changed == 0 and exit_code == 0: reason = 'wrote_nothing'
else:                      reason = 'ok'

entry = {
    'ts':                      datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'delegate':                'copilot',
    'workdir':                 workdir,
    'project':                 os.path.basename(workdir.rstrip('/').rstrip('\\')),
    'executor_model':          model,
    'executor_model_fallback': fallback,
    'exit_code':               exit_code,
    'timed_out':               timed_out,
    'files_changed':           files_changed,
    'syntax_errors':           syntax_errors,
    'duration_secs':           duration,
    'tokens_in':               tokens_in,
    'tokens_out':              tokens_out,
    'tokens_cached':           tokens_cached,
    'tokens_reasoning':        tokens_reasoning,
    'cost_aic':                cost_aic,
    'failure_reason':          reason,
    'wrote_nothing':           reason in ('wrote_nothing', 'silent_exit', 'near_empty'),
}

with open(LOG, 'a') as f:
    f.write(json.dumps(entry) + '\n')

reason_str = f'  {reason}' if reason != 'ok' else ''
print(f'[log] -> {LOG}  (exit {exit_code}, {duration}s, {cost_aic:.4f} AIC{reason_str})')
'@

if ($pythonCmd) {
    $logFile = [IO.Path]::GetTempFileName() + '.py'
    [IO.File]::WriteAllText($logFile, $logScript, [Text.Encoding]::UTF8)
    & $pythonCmd $logFile
    Remove-Item $logFile -ErrorAction SilentlyContinue
} else {
    Write-Host "[warn] Python not found — AIC report and run log skipped."
    Write-Host "       Install Python 3 and ensure it is on PATH."
}

# ── Clean up delegate env vars and temp files ─────────────────────────────────
foreach ($v in @('DELEGATE_WORKDIR','DELEGATE_EXIT','DELEGATE_TIMEOUT','DELEGATE_MODEL',
                  'DELEGATE_MODEL_FALLBACK','DELEGATE_FILES_CHANGED','DELEGATE_SYNTAX_ERRORS',
                  'DELEGATE_START_NS','DELEGATE_END_NS','DELEGATE_OTEL_FILE','VERBOSE')) {
    Remove-Item "Env:\$v" -ErrorAction SilentlyContinue
}
Remove-Item $promptFile, $otelFile -ErrorAction SilentlyContinue

exit $copilotExit
