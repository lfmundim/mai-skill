---
name: mai-model-clear
description: Clear the MAI model override and revert to the default cascade (MAI-Code-1-Flash → gpt-5-mini).
license: MIT
user-invocable: true
allowed-tools:
  - bash
---

# /mai-model-clear

Run: `rm -f ~/.local/share/mai-model.flag`

Confirm: "Model override cleared — MAI will use MAI-Code-1-Flash (with gpt-5-mini fallback)."
