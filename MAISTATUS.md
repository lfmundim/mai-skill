---
name: maistatus
description: Show MAI auto-delegate mode status (ON/OFF) and active model override.
license: MIT
user-invocable: true
allowed-tools:
  - bash
---

# /maistatus

Run both checks and print two lines:

```
Auto-MAI: ON | OFF
Model: <alias>  (override)  OR  Model: MAI-Code-1-Flash  (default)
```

- Auto-MAI: `test -f ~/.local/share/mai-auto.flag && echo ON || echo OFF`
- Model override: `cat ~/.local/share/mai-model.flag 2>/dev/null || echo "(MAI-Code-1-Flash default)"`
