---
name: mai-report
description: Show MAI usage report — AIC usage, failure stats, model fallback rates. Usage: /mai-report [--since N] [--project NAME] [--fails]
license: MIT
user-invocable: true
allowed-tools:
  - bash
---

# /mai-report

Run `~/tools/delegate-report --delegate copilot` with any flags extracted from the
arguments and display output verbatim.

| User says | Flag |
|-----------|------|
| "last 7 days", "7d" | `--since 7` |
| "last 30 days", "30d" | `--since 30` |
| "project foo" | `--project foo` |
| "only failures", "fails" | `--fails` |
| "all delegates", "compare" | `--all` |
| "delegate foo", "only vibe" | `--delegate foo` |
| (nothing) | `--delegate copilot` (MAI runs only) |

Defaults to MAI (copilot) runs only. The run log is shared across all delegate tools;
`--all` shows every delegate, `--delegate NAME` scopes to a specific one.
