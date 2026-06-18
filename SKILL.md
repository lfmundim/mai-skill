---
name: mai
description: >
  Delegate a coding task to a cheap Copilot model and supervise the result via git diff.
  Trigger: /mai <instruction> [--with-review N]. Copilot orchestrates, a cheaper model codes.
license: MIT
user-invocable: true
allowed-tools:
  - bash
  - read_file
  - grep
---

# MAI Orchestrator

## /maion | /maioff | /maistatus

Toggle auto-delegate mode — MAI automatically handles coding tasks without requiring `/mai` each time.

| Command | Action |
|---------|--------|
| `/maion` | `touch ~/.local/share/mai-auto.flag` → confirm "Auto-MAI ON" |
| `/maioff` | `rm -f ~/.local/share/mai-auto.flag` → confirm "Auto-MAI OFF" |
| `/maistatus` | report auto-mode (ON/OFF) **and** active model override |

For `/maistatus`, run both checks and print two lines:
```
Auto-MAI: ON | OFF
Model: <alias>  (override)  OR  Model: MAI-Code-1-Flash  (default)
```

### Auto-mode pre-filter (when flag is set)

When `mai-auto.flag` exists, apply this gate **before** loading the full skill:

| Task signal | Action |
|---|---|
| 1 file, ≤10 lines, exact location already known | Edit directly — do NOT invoke the skill |
| Logic non-trivial, location unclear, multiple files, or >1 change | Invoke `/mai` as normal |

---

## /mai-report

If the user invokes `/mai-report`, run `~/tools/delegate-report --delegate copilot` with any
flags extracted from the arguments, display output verbatim, and stop.

| User says | Flag |
|-----------|------|
| "last 7 days", "7d" | `--since 7` |
| "last 30 days", "30d" | `--since 30` |
| "project foo" | `--project foo` |
| "only failures", "fails" | `--fails` |
| "all delegates", "compare" | `--all` |
| "delegate foo", "only vibe" | `--delegate foo` |
| (nothing) | `--delegate copilot` (MAI runs only) |

---

## /mai-model-pick | /mai-model-clear

Override the executor model for all subsequent delegations without editing config files.

| Command | Action |
|---------|--------|
| `/mai-model-pick <alias>` | `echo <alias> > ~/.local/share/mai-model.flag` → confirm |
| `/mai-model-clear` | `rm -f ~/.local/share/mai-model.flag` → confirm "back to MAI-Code-1-Flash default" |

Run the bash command, print one confirmation line showing the active model, and stop.

---

When the user invokes `/mai <instruction> [--with-review N]`, Copilot plans the task,
delegates execution to a cheaper model via `~/tools/copilot-delegate`, and optionally
reviews and re-delegates up to N times.

---

## Known Limits

Hard constraints — not config options. Full details in `MAI-REFERENCE.md`.

- **`--yolo` / `--allow-tool` blocked by enterprise admin policy** → detect exit code and
  output; surface clearly with actionable message.
- **Copilot CLI auto-updates without deprecation warnings** → version check on every run;
  warn if CLI version changed since last run.
- **MAI-Code-1-Flash is rolling out gradually** → fallback to `gpt-5-mini`, then to the
  calling model (with a user-visible warning). Always pass `--model` explicitly.

---

## Step 1 — Detect workdir

1. `git rev-parse --show-toplevel` in the current directory.
2. If ambiguous or no git repo → ask the user.

---

## Step 2 — Parse flags

Extract `--with-review N` and `--verbose` from the user's instruction string before planning.

| Input | Parsed |
|---|---|
| `/mai add pagination --with-review 3` | instruction: "add pagination", review_limit: 3, verbose: false |
| `/mai fix the login form --verbose` | instruction: "fix the login form", review_limit: 0, verbose: true |
| `/mai refactor auth --with-review 2 --verbose` | instruction: "refactor auth", review_limit: 2, verbose: true |

Remove both flags from the instruction before passing it to the planning step.

When `--verbose` is set, export `DELEGATE_VERBOSE=true` before every `copilot-delegate` call.

---

## Step 2.5 — Planning AIC baseline (always)

Run `/usage` in the orchestrator session **before** writing any prompt to capture the
pre-planning AIC value. After the prompt is written and before delegating, run `/usage`
again to get the post-planning value.

Planning-phase AIC ≈ post − pre reading.

**Reporting:**
- Always: `Planning: ~X.XXXX AIC` (one line in the final report)
- `--verbose`: also show token counts from `/context`

Note: execution-phase AIC is captured automatically via OTel in `copilot-delegate`
and reported as `[aic] X.XXXX AIC  |  ↑N (Ncached) • ↓N`.

---

## Step 3 — Select executor model

Model selection follows a three-tier cascade. `copilot-delegate` handles tiers 2 and 3
automatically via retry on model-not-found errors; the orchestrator selects the initial model.

**Tier 1 — model override flag (user-set via `/mai-model-pick`):**
```bash
cat ~/.local/share/mai-model.flag 2>/dev/null
```
If the file exists and is non-empty, use that model. Set `FALLBACK=false`, `OVERRIDE=true`.

**Tier 2 — default primary:**
- No flag file → `EXECUTOR_MODEL="MAI-Code-1-Flash"`, `FALLBACK=false`
- If the delegate exits with a model-not-found error → retry with `EXECUTOR_MODEL="gpt-5-mini"`, `FALLBACK=true`

**If gpt-5-mini also fails:** do NOT delegate further. The delegate script exits non-zero and prints:
```
⚠ Neither MAI-Code-1-Flash nor gpt-5-mini were available. Delegation aborted.
  Override permanently: /mai-model-pick <alias>
```
The orchestrator then handles the task directly without context-switching.

Always pass `--model` explicitly to `copilot-delegate`. Never omit it or rely on Copilot auto-select silently.

---

## Step 4 — Decompose the task

**Critical rule**: keep tasks **atomic and focused** — one objective, one prompt.

| Size | Definition | Approach |
|------|-----------|----------|
| **Trivial** | 1 file, change is obvious and location is known | **Skip delegation — edit directly** |
| **Simple** | 1 file, non-trivial logic or unknown location | 1 delegate call |
| **Medium** | 2–3 related files, 1 objective | 1 structured delegate call |
| **Complex** | >3 files OR business logic OR DB migrations | **Break into sequential sub-tasks** |

**Decomposition for complex tasks:**
```
Sub-task 1: Explore / read relevant files (read-only, no writes)
Sub-task 2: Implement change A in file X
Sub-task 3: Implement change B in file Y
Sub-task 4: Verify / test
```
Check `git diff --stat` between each sub-task before launching the next.

---

## Step 5 — Write the executor prompt

The prompt must be **self-contained**.

**Structure:**
```
Stack: <language/framework, e.g. Python/Flask, TypeScript/Next.js>
Key files: <file> (<role>), <file> (<role>)

TASK: [one single imperative — what to do, not how]

CONSTRAINTS:
- [what must not break]
- [expected format or signature if relevant]

VERIFY: grep for "<symbol>" in <file> and confirm it exists.
```

**Formulation rules:**
- One task per prompt — never "also do X and Y"
- Name the exact files to modify
- Include a grep-based verification criterion (not a file re-read)
- Language: English
- If a specific function signature is required, include it verbatim
- For write/modify tasks, append:
  ```
  OUTPUT FORMAT:
  Modified: <file>
  Does: <one line>
  No other prose.
  ```

**Shell safety:** the delegate script writes the prompt to a temp file to avoid shell
injection. Never interpolate prompts with Python code, curly braces, or special chars
directly into bash heredocs yourself.

---

## Step 6 — Launch the delegate

**Detect the platform first, then use the matching invocation below.**

### Unix / macOS / WSL / Git Bash

```bash
~/tools/copilot-delegate "<workdir>" "<prompt>" "<model>" [timeout-secs]
```

**Example:**
```bash
~/tools/copilot-delegate "/path/to/project" "Stack: Python/Flask. File: app.py\n\nTASK: Add rate limiting..." "gpt-5-mini" 300
```

**Background launch:**
```bash
~/tools/copilot-delegate "/path/to/project" "<prompt>" "gpt-5-mini" > /tmp/mai_out.txt 2>&1 &
# Monitor with: tail -f /tmp/mai_out.txt
```

### Windows (native PowerShell — no Git Bash / WSL)

```powershell
& "$HOME\tools\copilot-delegate.ps1" -Workdir "<workdir>" -Prompt "<prompt>" -Model "<model>" -TimeoutSecs <secs>
```

**Example:**
```powershell
& "$HOME\tools\copilot-delegate.ps1" -Workdir "C:\projects\myapp" -Prompt "Stack: Python/Flask. File: app.py`n`nTASK: Add rate limiting..." -Model "gpt-5-mini" -TimeoutSecs 300
```

| Argument | Default | Notes |
|---|---|---|
| `workdir` (both) | — | Absolute path, must exist |
| `prompt` (both) | — | Self-contained task description |
| `model` (both) | — | Always explicit — use EXECUTOR_MODEL from Step 3 |
| `timeout-secs` / `-TimeoutSecs` | `300` | Wall-clock kill timer |

---

## Step 7 — Supervise output

The script prints live:
```
=== MAI-DELEGATE START ===
Workdir : /path/to/project
Model   : gpt-5-mini  (fallback — MAI-Code-1-Flash not available)
Timeout : 300s
Prompt  : Stack: Python/Flask. File: app.py ...
==========================
<copilot output streams here>
=== MAI-DELEGATE DONE (exit: 0) ===
=== SYNTAX OK (2 check(s)) ===

=== UNCOMMITTED CHANGES ===
 app.py | 4 ++--
[log] → ~/.local/share/delegate-runs.jsonl  (exit 0, 42.1s)
```

**Red flags to act on immediately:**

| Flag | Meaning | Action |
|---|---|---|
| `[ERROR] Enterprise policy` | `--yolo` or `--allow-tool` blocked | Surface to user; cannot proceed without admin policy change |
| `exit: 124` | Timeout — task too large | Decompose, reduce scope, re-delegate |
| `exit: non-zero` | Delegate failed | Read diff, correct prompt, retry up to 3× |
| `=== SYNTAX ERRORS ===` | Post-run syntax check failed | Fix before committing or re-delegating |
| 0 files changed | Wrote nothing | Check diff; fix prompt imperative |

---

## Step 8 — Review loop (only when `--with-review N` was passed)

This step runs after Step 7 completes (exit 0 or non-zero).

```
review_allowed  = N       (from --with-review N)
review_used     = 0
issues_found    = 0
issues_fixed    = 0
```

**For each review iteration (while review_used < review_allowed):**

1. Read the full `git diff` since the start of this `/mai` session.

2. Evaluate the diff for **fundamental issues only**:
   - Wrong logic (does the wrong thing)
   - Crash-causing gaps (missing nil check, unhandled exception path, etc.)
   - Broken contracts (wrong function signature, changed public API, wrong return type)
   - Wrong scope (modified the wrong file or the wrong section)
   - Security holes (injection, credential leak, unvalidated input)

3. **Do NOT flag:**
   - Style, naming, or formatting
   - Missing comments or docstrings
   - Subjective improvements
   - Minor inefficiencies

4. If **no fundamental issues** → break out of loop.

5. If **fundamental issue found**:
   - `issues_found += 1`
   - Write a fix prompt targeting **one issue at a time** (same self-contained format as Step 5)
   - Re-delegate via `~/tools/copilot-delegate`
   - `review_used += 1`
   - If exit 0 and issue resolved: `issues_fixed += 1`
   - Continue to next iteration

6. After the loop, call the review logger.

Unix / Git Bash:
```bash
python3 ~/tools/log-review-summary \
  --workdir "$WORKDIR" \
  --allowed "$review_allowed" \
  --used "$review_used" \
  --found "$issues_found" \
  --fixed "$issues_fixed" \
  --remaining "$((issues_found - issues_fixed))"
```

Windows (PowerShell):
```powershell
$remaining = $issues_found - $issues_fixed
& python "$HOME\tools\log-review-summary" `
  --workdir $WORKDIR --allowed $review_allowed --used $review_used `
  --found $issues_found --fixed $issues_fixed --remaining $remaining
```

---

## Step 9 — Report to the user

```
✓ MAI finished — <1-line summary>

Executor : <model>  [fallback → gpt-5-mini]
Files    : path/to/file.ext (+X / -Y lines)
AIC      : Planning ~X.XXXX | Execution X.XXXX  (↑N tok, Ncached cached • ↓N tok)

[--verbose adds]:
  Planning  : pre X.XXXX AIC → post X.XXXX AIC  (Δ+X.XXXX AIC)
  Execution : X.XXXX AIC  |  ↑N tok (Ncached cached) • ↓N tok (N reasoning)

[If review ran]:
Review: <review_used>/<review_allowed> iteration(s)
  Issues found: <N>  Fixed: <M>  Remaining: <R>

[If problem]:
⚠ <description> — completing manually / relaunching?

Ready to commit?
```

---

## Orchestration rules

- **Plan before delegating** — Copilot writes the prompt; the executor implements it.
- **Always pass `--model` explicitly** — never let Copilot auto-select for execution.
- **Decompose before delegating** — one task, one prompt.
- **Check diff between sub-tasks** — never launch the next one blind.
- **Max 3 delegate attempts** per sub-task before escalating to the user.
- **Review finds, not fixes directly** — Copilot does not edit code during review; it re-delegates.
- **One issue at a time in review** — never bundle multiple fix instructions into one re-delegation prompt.
- **Grep to verify** — always use grep to confirm changes, not file re-read.
- **Surface policy blocks clearly** — if `--yolo` / `--allow-tool` is blocked, say so explicitly and stop.

---

## Run Log

Every run appends one JSON entry to `~/.local/share/delegate-runs.jsonl`.
Log fields → see `MAI-REFERENCE.md`.

```bash
~/tools/delegate-report --delegate copilot            # copilot/mai runs only
~/tools/delegate-report --delegate copilot --since 7  # last 7 days
~/tools/delegate-report --delegate copilot --fails    # failures only
~/tools/delegate-report --all                         # all delegates (shared log)
```

The log is shared with sister delegates (vibe, opencode, gemini).

---

## See Also

- `MAI-REFERENCE.md` — log fields, jq queries, full failure details, AIC methodology
- `examples/good-prompts.md` — prompt patterns that work reliably
- `examples/anti-patterns.md` — what fails and why, with fixes
- [vibe-skill](https://github.com/pcx-wave/vibe-skill) — sister delegate using Mistral Vibe

---

## Installation (Copilot CLI)

```bash
mkdir -p ~/tools ~/.copilot/skills/mai
ln -sf "$(pwd)/tools/copilot-delegate" ~/tools/copilot-delegate
ln -sf "$(pwd)/tools/log-review-summary" ~/tools/log-review-summary
chmod +x ~/tools/copilot-delegate ~/tools/log-review-summary
ln -sf "$(pwd)/SKILL.md" ~/.copilot/skills/mai/SKILL.md
```
