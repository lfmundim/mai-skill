---
name: mai-model-pick
description: Override the MAI executor model for all subsequent delegations. Usage: /mai-model-pick <model-id>
license: MIT
user-invocable: true
allowed-tools:
  - bash
---

# /mai-model-pick

Extract the model ID from the user's arguments, then run:
`echo <model-id> > ~/.local/share/mai-model.flag`

Confirm: "Model override set to <model-id> — all MAI runs will use this model until /mai-model-clear."

If no model ID provided, remind user of the default cascade:
- `MAI-Code-1-Flash` (primary — may not be available in all environments)
- `gpt-5-mini` (automatic fallback if primary unavailable)
