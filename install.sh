#!/usr/bin/env bash
# install.sh — MAI skill installer for Unix (Linux, macOS, WSL)
#
# What this does:
#   1. Creates ~/tools/ and symlinks copilot-delegate + log-review-summary into it
#   2. Creates skill directories under ~/.copilot/skills/ and ~/.claude/skills/
#   3. Symlinks each skill's SKILL.md into the appropriate directories
#
# Symlinks mean `git pull` in this repo is all you ever need to update.
# Nothing is copied — everything points back here.
#
# Usage:
#   chmod +x install.sh
#   ./install.sh

set -euo pipefail

# ── Resolve repo root (script's own directory, even if called from elsewhere) ──
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║         MAI Skill Installer              ║"
echo "║         Unix / macOS / WSL               ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "Repo : $REPO_DIR"
echo ""

# ── Step 1: ~/tools ────────────────────────────────────────────────────────────
echo "[ 1/3 ] Setting up ~/tools ..."

mkdir -p "$HOME/tools"

# Symlink the bash delegate runner — used by Unix/macOS/WSL/Git Bash
ln -sf "$REPO_DIR/tools/copilot-delegate"     "$HOME/tools/copilot-delegate"
echo "        → ~/tools/copilot-delegate"

# Symlink the PowerShell delegate — Windows users without Git Bash use this
# (also useful if you run pwsh on Linux/macOS)
ln -sf "$REPO_DIR/tools/copilot-delegate.ps1" "$HOME/tools/copilot-delegate.ps1"
echo "        → ~/tools/copilot-delegate.ps1"

# Symlink the review-summary logger — used by the --with-review loop
ln -sf "$REPO_DIR/tools/log-review-summary"   "$HOME/tools/log-review-summary"
echo "        → ~/tools/log-review-summary"

# Mark executables (symlinks inherit, but the originals need the bit)
chmod +x "$REPO_DIR/tools/copilot-delegate"
chmod +x "$REPO_DIR/tools/log-review-summary"
echo "        chmod +x applied to originals"

echo ""

# ── Step 2: skill directories + symlinks ──────────────────────────────────────
echo "[ 2/3 ] Installing skills ..."
echo ""

# Each entry is "skill-dir-name:source-file-in-repo-root"
SKILLS=(
  "mai:SKILL.md"
  "maion:MAION.md"
  "maioff:MAIOFF.md"
  "maistatus:MAISTATUS.md"
  "mai-report:MAI-REPORT.md"
  "mai-model-pick:MAI-MODEL-PICK.md"
  "mai-model-clear:MAI-MODEL-CLEAR.md"
)

for pair in "${SKILLS[@]}"; do
  skill="${pair%%:*}"
  src="${pair##*:}"

  # Install into both Copilot CLI and Claude Code skill directories
  for base in "$HOME/.copilot/skills" "$HOME/.claude/skills"; do
    dir="$base/$skill"
    mkdir -p "$dir"
    ln -sf "$REPO_DIR/$src" "$dir/SKILL.md"
    echo "        → $dir/SKILL.md"
  done
done

echo ""

# ── Step 3: Verify copilot CLI is reachable ────────────────────────────────────
echo "[ 3/3 ] Checking for Copilot CLI ..."

if command -v copilot &>/dev/null; then
  VER=$(copilot --version 2>/dev/null | head -1 || echo "unknown")
  echo "        copilot found: $VER"
else
  echo "        [WARN] 'copilot' not found in PATH."
  echo "               Install GitHub Copilot CLI and authenticate before using /mai."
fi

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   Installation complete!                 ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "Verify with:"
echo "  ~/tools/copilot-delegate /tmp \"Say hello in one sentence.\" gpt-5-mini 30"
echo ""
echo "Update anytime:"
echo "  cd \"$REPO_DIR\" && git pull"
echo ""
