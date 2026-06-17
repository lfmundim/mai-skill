---
name: maioff
description: Disable MAI auto-delegate mode — coding tasks are handled by the orchestrator directly unless /mai is explicitly invoked.
license: MIT
user-invocable: true
allowed-tools:
  - bash
---

# /maioff

Run: `rm -f ~/.local/share/mai-auto.flag`

Then confirm: "Auto-MAI OFF — orchestrator will handle coding tasks directly."
