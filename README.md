# mai-skill

**Copilot orchestrates. A cheaper model codes. You review the diff.**

When you type `/mai <instruction>`, Copilot plans the task, selects the cheapest
available model, delegates execution via the Copilot CLI programmatic mode, and reports
the git diff — including real AI Credit (AIC) cost.

The optional `--with-review N` flag adds an automated review loop: Copilot reads the
diff, flags fundamental issues (wrong logic, crashes, broken contracts, security holes),
and re-delegates fixes up to N times — one issue at a time.

---

## How it works

```
User: /mai add rate limiting to POST /auth --with-review 2
  └─ SKILL.md — Copilot plans and writes a self-contained prompt
       └─ model cascade: MAI-Code-1-Flash → gpt-5-mini (fallback)
            └─ ~/tools/copilot-delegate <workdir> <prompt> <model>
                 ├─ version check (warn if CLI changed)
                 ├─ writes prompt to temp file (avoids shell injection)
                 ├─ sets COPILOT_OTEL_FILE_EXPORTER_PATH for AIC capture
                 ├─ runs: copilot -p "$(cat $tmpfile)" --model <model> --yolo
                 ├─ streams output live
                 ├─ detects enterprise policy blocks
                 ├─ runs syntax checks (.py, .js, .cs, .swift, .go, .ts, .rs)
                 ├─ prints git diff --stat
                 ├─ parses OTel for real AIC + token counts
                 └─ appends to ~/.local/share/delegate-runs.jsonl
       └─ [if --with-review N] Copilot reads diff, re-delegates issues, logs summary
```

---

## Prerequisites

- [GitHub Copilot CLI](https://githubnext.com/projects/copilot-cli/) installed and authenticated
  (`copilot --version`)
- Claude Code or a Copilot agent with skills enabled
- `python3` available (syntax checks + OTel parsing)
- `git` repository to work in
- `node`, `cargo`, `dotnet`, `swiftc` available for per-language syntax checks (optional)

---

## Installation

Installer scripts are provided at the repo root for both platforms:

| Script | Platform | Notes |
|---|---|---|
| `install.sh` / `uninstall.sh` | Unix, macOS, WSL | `chmod +x` then run |
| `install.ps1` / `uninstall.ps1` | Windows PowerShell | Requires **Developer Mode** or an **elevated (Admin) terminal** for symlink creation |

Both approaches are equivalent — the scripts below show the manual steps for reference.

### Unix (WSL, Linux, macOS)

```bash
# 1. Clone this repo
git clone https://github.com/<your-org>/mai-skill.git
cd mai-skill

# 2. Install the delegate scripts
mkdir -p ~/tools
ln -sf "$(pwd)/tools/copilot-delegate" ~/tools/copilot-delegate
ln -sf "$(pwd)/tools/log-review-summary" ~/tools/log-review-summary
chmod +x ~/tools/copilot-delegate ~/tools/log-review-summary

# 3. Install skills for Copilot CLI and Claude Code
mkdir -p ~/.copilot/skills/mai ~/.claude/skills/mai
ln -sf "$(pwd)/SKILL.md" ~/.copilot/skills/mai/SKILL.md
ln -sf "$(pwd)/SKILL.md" ~/.claude/skills/mai/SKILL.md

for pair in "maion:MAION.md" "maioff:MAIOFF.md" "maistatus:MAISTATUS.md" \
            "mai-report:MAI-REPORT.md" "mai-model-pick:MAI-MODEL-PICK.md" \
            "mai-model-clear:MAI-MODEL-CLEAR.md"; do
  skill="${pair%%:*}"; src="${pair##*:}"
  mkdir -p ~/.copilot/skills/$skill ~/.claude/skills/$skill
  ln -sf "$(pwd)/$src" ~/.copilot/skills/$skill/SKILL.md
  ln -sf "$(pwd)/$src" ~/.claude/skills/$skill/SKILL.md
done
```

Verify with:
```bash
~/tools/copilot-delegate /tmp "Say hello in one sentence." gpt-5-mini 30
```

### Windows (PowerShell)

> **Note:** `copilot-delegate` is a bash script. It runs under **Git Bash** or **WSL** —
> not native PowerShell. The steps below set up the files; execution still goes through bash.
> Symlinks on Windows require **Developer Mode** or an elevated (admin) terminal.

```powershell
# 1. Clone this repo
git clone https://github.com/<your-org>/mai-skill.git
Set-Location mai-skill
$REPO = (Get-Location).Path

# 2. Install the delegate scripts
New-Item -ItemType Directory -Force "$HOME\tools" | Out-Null
New-Item -ItemType SymbolicLink -Force -Path "$HOME\tools\copilot-delegate"     -Target "$REPO\tools\copilot-delegate"
New-Item -ItemType SymbolicLink -Force -Path "$HOME\tools\log-review-summary"   -Target "$REPO\tools\log-review-summary"

# 3. Install skills for Copilot CLI and Claude Code
$skills = [ordered]@{
  "mai"             = "SKILL.md"
  "maion"           = "MAION.md"
  "maioff"          = "MAIOFF.md"
  "maistatus"       = "MAISTATUS.md"
  "mai-report"      = "MAI-REPORT.md"
  "mai-model-pick"  = "MAI-MODEL-PICK.md"
  "mai-model-clear" = "MAI-MODEL-CLEAR.md"
}

foreach ($skill in $skills.Keys) {
  $src = $skills[$skill]
  foreach ($base in "$HOME\.copilot\skills", "$HOME\.claude\skills") {
    $dir = "$base\$skill"
    New-Item -ItemType Directory -Force $dir | Out-Null
    New-Item -ItemType SymbolicLink -Force -Path "$dir\SKILL.md" -Target "$REPO\$src"
  }
}
```

Verify with Git Bash:
```bash
~/tools/copilot-delegate "$TEMP" "Say hello in one sentence." gpt-5-mini 30
```

Or with WSL (if your repo is in WSL's filesystem):
```bash
~/tools/copilot-delegate /tmp "Say hello in one sentence." gpt-5-mini 30
```

### Updating

Because installs use symlinks, a `git pull` is all you need:
```bash
cd mai-skill && git pull
```

---

## Usage

```
/mai add a dark mode toggle to the settings page
/mai the login form is not validating the email field — fix it
/mai add pagination to GET /posts, 20 items per page
/mai refactor the auth middleware into its own module --with-review 3
/mai fix the race condition in the job queue --verbose
```

Flags:

| Flag | Effect |
|---|---|
| `--with-review N` | After execution, review the diff and re-delegate fixes up to N times |
| `--verbose` | Show full AIC breakdown (tokens by type) instead of compact summary |

---

## Model selection

Three-tier cascade — resolved automatically by `copilot-delegate`:

| Tier | Model | Condition |
|---|---|---|
| 1 (override) | model from `/mai-model-pick` | flag file `~/.local/share/mai-model.flag` exists |
| 2 (primary) | `MAI-Code-1-Flash` | default when no override |
| 3 (fallback) | `gpt-5-mini` | primary returned a model-not-found error |

If both primary and fallback are unavailable, delegation is aborted and the orchestrator
handles the task directly. `--model` is always passed explicitly; the executor never
auto-selects.

### Override a model permanently

```
/mai-model-pick MAI-Code-1-Flash    # pin a specific model
/mai-model-pick gpt-5-mini          # force the fallback (e.g. in work environments)
/mai-model-clear                    # revert to the default cascade
/maistatus                          # show current auto-mode and model override
```

---

## Auto-delegate mode

Enable to have every coding request automatically routed through MAI without typing
`/mai` each time:

```
/maion      # enable auto-delegate
/maioff     # disable
/maistatus  # check status + active model
```

When the flag is set, trivial edits (1 file, ≤10 lines, exact location known) are
handled directly — only non-trivial tasks go through the delegate.

---

## AIC reporting

`copilot-delegate` sets `COPILOT_OTEL_FILE_EXPORTER_PATH` on every run and parses the
OpenTelemetry `invoke_agent` span after completion. Real values — no approximation.

```
[aic] 0.2977 AIC  |  ↑12,737 (2,432 cached) • ↓170 (128 reasoning)
[log] → ~/.local/share/delegate-runs.jsonl  (exit 0, 34.2s, 0.2977 AIC)
```

With `--verbose`:
```
[aic] 0.2977 AIC
      ↑ 12,737 tok (2,432 cached) • ↓ 170 tok (128 reasoning)
```

Logged fields per run: `tokens_in`, `tokens_out`, `tokens_cached`, `tokens_reasoning`,
`cost_aic`. See `MAI-REFERENCE.md` for jq queries.

---

## Terminal output

```
=== MAI-DELEGATE START ===
Workdir : /path/to/project
Model   : gpt-5-mini  (fallback — MAI-Code-1-Flash not available)
Timeout : 300s
Prompt  : Stack: Python/Flask. File: app.py ...
==========================
<Copilot CLI output streams here>
=== MAI-DELEGATE DONE (exit: 0) ===
=== SYNTAX OK (2 check(s)) ===

=== UNCOMMITTED CHANGES ===
 app.py | 4 ++--
[aic] 0.2977 AIC  |  ↑12,737 (2,432 cached) • ↓170
[log] → ~/.local/share/delegate-runs.jsonl  (exit 0, 42.1s, 0.2977 AIC)
```

---

## Reporting

Runs are logged to `~/.local/share/delegate-runs.jsonl` — the same log shared by
[vibe-skill](https://github.com/pcx-wave/vibe-skill) and other delegate tools.

```
/mai-report                  # MAI/copilot runs only
/mai-report --since 7        # last 7 days
/mai-report --project myapp  # filter by project
/mai-report --fails          # failures only
/mai-report --all            # compare all delegates (vibe, opencode, etc.)
```

Or directly via `~/tools/delegate-report`:

```bash
~/tools/delegate-report --delegate copilot
~/tools/delegate-report --all
```

Note: `~/tools/delegate-report` is installed by vibe-skill. Without it, query the log
directly with `jq` — see `MAI-REFERENCE.md`.

---

## Slash command reference

| Command | Description |
|---|---|
| `/mai <instruction>` | Delegate a coding task |
| `/mai <instruction> --with-review N` | Delegate + review loop (up to N fix cycles) |
| `/mai <instruction> --verbose` | Show full AIC token breakdown |
| `/maion` | Enable auto-delegate mode |
| `/maioff` | Disable auto-delegate mode |
| `/maistatus` | Show auto-delegate status and active model |
| `/mai-model-pick <model>` | Pin a specific executor model |
| `/mai-model-clear` | Clear model override, revert to cascade default |
| `/mai-report` | Show run stats (AIC, failures, fallback rate) |

---

## Known limitations

- **Enterprise admin policy** — `--yolo` may be blocked in managed Copilot environments.
  The delegate script detects this and surfaces a clear error with the remediation path.
- **MAI-Code-1-Flash rollout** — not yet available to all users or environments.
  The fallback to `gpt-5-mini` is automatic and logged. Use `/mai-model-pick` to
  skip the cascade in environments where you know which model is available.
- **CLI auto-updates** — flag names can change silently. Version check warns on change.
- **AIC unavailable** — if `COPILOT_OTEL_FILE_EXPORTER_PATH` is blocked or OTel is
  disabled by policy, `cost_aic` and token fields fall back to 0.

---

## Inspired by

[vibe-skill](https://github.com/pcx-wave/vibe-skill) — the same orchestration pattern,
adapted for GitHub Copilot CLI and the MAI model family. Shares the same run log format
so cross-delegate reporting works out of the box.

---

## License

MIT
