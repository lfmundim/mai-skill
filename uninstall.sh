#!/usr/bin/env bash
# uninstall.sh — MAI skill uninstaller for Unix (Linux, macOS, WSL)
#
# What this does:
#   1. Removes skill symlinks from ~/.copilot/skills/ and ~/.claude/skills/
#      (leaves the parent directories — they may contain other skills)
#   2. Removes delegate symlinks from ~/tools/
#      (leaves ~/tools/ itself — may contain other tools)
#   3. Removes the cached CLI version file written by copilot-delegate
#
# Nothing from the repo itself is deleted. You can re-run install.sh at any time.
#
# Usage:
#   chmod +x uninstall.sh
#   ./uninstall.sh

set -euo pipefail

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║         MAI Skill Uninstaller            ║"
echo "║         Unix / macOS / WSL               ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── Helper: remove a symlink only (never a real file) ─────────────────────────
remove_symlink() {
  local path="$1"
  if [ -L "$path" ]; then
    rm "$path"
    echo "        removed: $path"
  elif [ -e "$path" ]; then
    # Bail if something that isn't a symlink is sitting at that path —
    # we don't want to silently delete user files.
    echo "        [SKIP] $path exists but is not a symlink — remove manually if needed"
  fi
}

# ── Step 1: skill symlinks ─────────────────────────────────────────────────────
echo "[ 1/3 ] Removing skill symlinks ..."
echo ""

SKILLS=(
  "mai"
  "maion"
  "maioff"
  "maistatus"
  "mai-report"
  "mai-model-pick"
  "mai-model-clear"
)

for skill in "${SKILLS[@]}"; do
  for base in "$HOME/.copilot/skills" "$HOME/.claude/skills"; do
    remove_symlink "$base/$skill/SKILL.md"
    # Remove the skill directory only if it is now empty
    if [ -d "$base/$skill" ] && [ -z "$(ls -A "$base/$skill" 2>/dev/null)" ]; then
      rmdir "$base/$skill"
      echo "        rmdir: $base/$skill (was empty)"
    fi
  done
done

echo ""

# ── Step 2: ~/tools symlinks ───────────────────────────────────────────────────
echo "[ 2/3 ] Removing ~/tools symlinks ..."
echo ""

remove_symlink "$HOME/tools/copilot-delegate"
remove_symlink "$HOME/tools/copilot-delegate.ps1"
remove_symlink "$HOME/tools/log-review-summary"

echo ""

# ── Step 3: runtime files written by copilot-delegate ─────────────────────────
echo "[ 3/3 ] Removing runtime files ..."
echo ""

# CLI version cache — written after each delegate run to detect silent CLI updates
CLI_VER_FILE="$HOME/.local/share/copilot-delegate-cli-version"
if [ -f "$CLI_VER_FILE" ]; then
  rm "$CLI_VER_FILE"
  echo "        removed: $CLI_VER_FILE"
else
  echo "        (CLI version cache not found — skipping)"
fi

# delegate-runs.jsonl is intentionally NOT removed — it is a shared run log
# used by vibe-skill and other delegate tools. Delete manually if desired:
#   rm ~/.local/share/delegate-runs.jsonl
echo ""
echo "        NOTE: ~/.local/share/delegate-runs.jsonl was NOT removed."
echo "              It is a shared log (used by vibe-skill etc.)."
echo "              Delete manually if you no longer need it."

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   Uninstall complete.                    ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "Repo files are untouched. Re-install anytime:"
echo "  ./install.sh"
echo ""
