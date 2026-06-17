# MAI — Reference

Not loaded at runtime. Read this when troubleshooting, querying logs, or looking up
full details for items summarised in SKILL.md.

---

## Known Limits — Full Details

### 1. `--yolo` / `--allow-tool` blocked by enterprise admin policy

Copilot CLI's `--yolo` flag (auto-approve all tool calls) and `--allow-tool` (whitelist
specific tools) may be disabled by enterprise admin policy in managed GitHub Copilot
environments. When blocked:

- The CLI exits non-zero immediately or after the first tool attempt.
- Output contains phrases like "admin policy", "not permitted", "tool blocked".
- `copilot-delegate` detects this via exit code and output pattern matching and prints
  a clear `[ERROR] Enterprise admin policy` message.

**There is no workaround from the delegate script.** The user must either:
1. Request the policy exception from their GitHub organization admin.
2. Run Copilot interactively (without `--yolo`) and approve tool calls manually.

### 2. Copilot CLI auto-updates without deprecation warnings

GitHub Copilot CLI (the `copilot` binary) updates silently. Flag names, output format,
and streaming behaviour can change between versions without notice.

`copilot-delegate` records the CLI version after every run in
`~/.local/share/copilot-delegate-cli-version` and prints a `[WARN]` if the version
changed since the last run. When this warning appears:

1. Verify that `--allow-tool='write,shell'` is still a valid flag in the new version.
2. Verify that `--yolo` still works as expected.
3. Run a short test: `copilot -p "Say hello in one sentence." --model gpt-5-mini --allow-all-tools --yolo`

### 3. MAI-Code-1-Flash rolling out gradually

`MAI-Code-1-Flash` is rolling out to users gradually and may not be available in all
accounts or enterprise environments. The Copilot CLI has no `models list` command.

Fallback cascade (handled automatically by `copilot-delegate`):
1. Try requested model (default: `MAI-Code-1-Flash`)
2. If model-not-found error → retry with `gpt-5-mini`
3. If `gpt-5-mini` also fails → abort delegation (exit 1); orchestrator handles task directly

`DELEGATE_MODEL_FALLBACK=true` is set whenever the primary model was unavailable — recorded in the run log.
Override permanently with `/mai-model-pick <alias>` to skip the cascade overhead.

### 4. AIC and token counts via OpenTelemetry

`copilot-delegate` sets `COPILOT_OTEL_FILE_EXPORTER_PATH` to a temp file on every run.
After the run it parses the `invoke_agent` span for real values:

| OTel attribute | Meaning |
|---|---|
| `github.copilot.nano_aiu` | AI Credits in nano-units → divide by 1e9 for AIC |
| `gen_ai.usage.input_tokens` | Input tokens (full context) |
| `gen_ai.usage.output_tokens` | Output tokens generated |
| `gen_ai.usage.cache_read_input_tokens` | Tokens served from cache |
| `gen_ai.usage.reasoning_output_tokens` | Internal reasoning tokens (o-series models) |

Example output:
```
[aic] 0.2977 AIC  |  ↑12,737 (2,432 cached) • ↓170 (128 reasoning)
```

---

## AIC Reporting Methodology

The OTel `invoke_agent` span is the top-level span aggregating all LLM calls in one
agent invocation. It carries the sum of token usage and the total `github.copilot.nano_aiu`
for the run. No log polling, no approximation.

### Planning phase

Runs inside the orchestrator session — not a `copilot-delegate` call, so no OTel file is
written for planning. To track planning AIC interactively:

```
/usage   → AIC used in the current session so far
/context → context-window token breakdown
```

Delta between pre- and post-planning `/usage` readings = planning-phase cost.

---

## Run Log Fields

Every run appends one JSON entry to `~/.local/share/delegate-runs.jsonl`.
The log is shared with vibe, opencode, and gemini delegates.

### Execution entry (`"type"` absent)

| Field | Type | Description |
|---|---|---|
| `ts` | string | ISO 8601 UTC timestamp |
| `delegate` | string | `"copilot"` |
| `workdir` | string | Absolute project path |
| `project` | string | `basename(workdir)` |
| `executor_model` | string | Model passed to `--model` (e.g. `MAI-Code-1-Flash`) |
| `executor_model_fallback` | bool | `true` if gpt-5-mini was used because MAI-Code-1-Flash was unavailable |
| `exit_code` | int | 0=success · 124=timeout · other=error |
| `timed_out` | bool | `true` if `exit_code == 124` |
| `files_changed` | int | Files modified (git diff count) |
| `syntax_errors` | int | Syntax errors detected post-run |
| `duration_secs` | float | Wall-clock duration |
| `tokens_in` | int | Input tokens (from OTel `gen_ai.usage.input_tokens`; 0 if OTel unavailable) |
| `tokens_out` | int | Output tokens (from OTel `gen_ai.usage.output_tokens`) |
| `tokens_cached` | int | Cache-hit input tokens (`gen_ai.usage.cache_read_input_tokens`) |
| `tokens_reasoning` | int | Reasoning tokens (`gen_ai.usage.reasoning_output_tokens`; 0 for non-o-series) |
| `cost_aic` | float | AI Credits used (`github.copilot.nano_aiu / 1e9`; 0 if OTel unavailable) |
| `failure_reason` | string | `ok` \| `wrote_nothing` \| `timeout` \| `exit_error` \| `syntax_error` |
| `wrote_nothing` | bool | Compatibility field — `true` when `failure_reason` is a write-failure class |

### Review summary entry (`"type": "review_summary"`)

Appended by `~/tools/log-review-summary` after the `--with-review N` loop.

| Field | Type | Description |
|---|---|---|
| `ts` | string | ISO 8601 UTC timestamp |
| `delegate` | string | `"copilot"` |
| `type` | string | `"review_summary"` |
| `workdir` | string | Absolute project path |
| `project` | string | `basename(workdir)` |
| `review_iterations_allowed` | int | N from `--with-review N` |
| `review_iterations_used` | int | How many review iterations actually ran |
| `review_issues_found` | int | Fundamental issues identified by review |
| `review_issues_fixed` | int | Issues that were re-delegated and resolved |
| `review_issues_remaining` | int | Unresolved issues after loop exhaustion |

---

## jq Queries

```bash
# All copilot runs
jq 'select(.delegate == "copilot" and (.type // "") == "")' ~/.local/share/delegate-runs.jsonl

# Success rate for copilot
jq -r 'select(.delegate == "copilot" and (.type // "") == "") | .exit_code' \
  ~/.local/share/delegate-runs.jsonl | sort | uniq -c

# Runs using fallback model (MAI-Code-1-Flash not available — gpt-5-mini or calling model used)
jq 'select(.delegate == "copilot" and .executor_model_fallback == true)' \
  ~/.local/share/delegate-runs.jsonl

# See which fallback model was actually used
jq 'select(.delegate == "copilot" and .executor_model_fallback == true) | {ts, executor_model}' \
  ~/.local/share/delegate-runs.jsonl

# Review summaries only
jq 'select(.delegate == "copilot" and .type == "review_summary")' \
  ~/.local/share/delegate-runs.jsonl

# Review fix rate (issues_fixed / issues_found)
jq -r 'select(.delegate == "copilot" and .type == "review_summary") |
  [.review_issues_found, .review_issues_fixed] | @tsv' \
  ~/.local/share/delegate-runs.jsonl | \
  awk '{f+=$1; x+=$2} END {printf "Found: %d  Fixed: %d  Rate: %.0f%%\n", f, x, x/f*100}'

# Failures only
jq 'select(.delegate == "copilot" and .failure_reason != "ok" and (.type // "") == "")' \
  ~/.local/share/delegate-runs.jsonl

# Average duration
jq -r 'select(.delegate == "copilot" and (.type // "") == "") | .duration_secs' \
  ~/.local/share/delegate-runs.jsonl | \
  awk '{s+=$1; n++} END {printf "Avg duration: %.1fs over %d runs\n", s/n, n}'
```

---

## Orchestration Chain — Failure Points

`Copilot models list → copilot-delegate → Copilot CLI → write/shell tools → git diff → JSONL log`

| Link | Failure mode | Symptom |
|---|---|---|
| `copilot models list` | Auth expired, no internet, slow API | Model check hangs or returns empty — assume fallback |
| `copilot-delegate` | Wrong workdir, missing CLI | Immediate exit 1, no output |
| Copilot CLI | Auth expired, update broke flags | Immediate non-zero exit, check `[WARN]` lines |
| write/shell tools | Admin policy blocks `--allow-tool` | `[ERROR] Enterprise admin policy` printed |
| git diff | Not a git repo | Git commands fail silently; files_changed shows 0 |
| JSONL log | `~/.local/share/` not writable | Silent log skip; `/mai-report` misses the run |

When a run produces unexpected results, work down this list.

---

## Delegate Report

MAI runs use the shared `~/tools/delegate-report` from vibe-skill (same JSONL log).
Filter to copilot runs:

```bash
~/tools/delegate-report --delegate copilot
~/tools/delegate-report --delegate copilot --since 7
~/tools/delegate-report --delegate copilot --fails
~/tools/delegate-report --all   # compare across all delegates
```

If vibe-skill is not installed, query the log directly with jq (see section above).
