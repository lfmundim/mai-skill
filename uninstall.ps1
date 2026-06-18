#Requires -Version 5.1
<#
.SYNOPSIS
    MAI skill uninstaller for Windows (PowerShell).

.DESCRIPTION
    Removes all MAI skill symlinks installed by install.ps1.

    What this does:
      1. Removes skill symlinks from $HOME\.copilot\skills\ and $HOME\.claude\skills\
         (leaves parent directories — they may contain other skills)
      2. Removes delegate symlinks from $HOME\tools\
         (leaves $HOME\tools\ itself — may contain other tools)
      3. Removes the cached CLI version file written by copilot-delegate

    Nothing from the repo itself is deleted. You can re-run install.ps1 at any time.

    IMPORTANT — Symlink privilege:
      Removing symlinks on Windows also requires Developer Mode or an elevated terminal
      (same privilege that was needed to create them).

.EXAMPLE
    .\uninstall.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "╔══════════════════════════════════════════╗"
Write-Host "║         MAI Skill Uninstaller            ║"
Write-Host "║         Windows / PowerShell             ║"
Write-Host "╚══════════════════════════════════════════╝"
Write-Host ""

# ── Helper: remove a symlink only (never a real file or directory) ────────────
function Remove-Symlink {
    param([string]$Path)

    if (-not (Test-Path $Path -ErrorAction SilentlyContinue)) {
        Write-Host "        (not found — skipping): $Path"
        return
    }

    $item = Get-Item $Path -Force
    if ($item.LinkType -eq 'SymbolicLink') {
        Remove-Item $Path -Force
        Write-Host "        removed: $Path"
    } else {
        # Guard against accidentally deleting real user files
        Write-Host "        [SKIP] $Path exists but is not a symlink — remove manually if needed"
    }
}

# ── Helper: remove an empty directory ────────────────────────────────────────
function Remove-IfEmpty {
    param([string]$Path)
    if (Test-Path $Path) {
        $contents = Get-ChildItem $Path -Force -ErrorAction SilentlyContinue
        if (-not $contents) {
            Remove-Item $Path -Force
            Write-Host "        rmdir (was empty): $Path"
        }
    }
}

# ── Step 1: skill symlinks ─────────────────────────────────────────────────────
Write-Host "[ 1/3 ] Removing skill symlinks ..."
Write-Host ""

$Skills = @(
    "mai",
    "maion",
    "maioff",
    "maistatus",
    "mai-report",
    "mai-model-pick",
    "mai-model-clear"
)

foreach ($skill in $Skills) {
    foreach ($base in "$HOME\.copilot\skills", "$HOME\.claude\skills") {
        $skillDir = "$base\$skill"
        Remove-Symlink -Path "$skillDir\SKILL.md"
        Remove-IfEmpty -Path $skillDir
    }
}

Write-Host ""

# ── Step 2: $HOME\tools symlinks ──────────────────────────────────────────────
Write-Host "[ 2/3 ] Removing `$HOME\tools symlinks ..."
Write-Host ""

Remove-Symlink -Path "$HOME\tools\copilot-delegate"
Remove-Symlink -Path "$HOME\tools\log-review-summary"

Write-Host ""

# ── Step 3: runtime files written by copilot-delegate ─────────────────────────
Write-Host "[ 3/3 ] Removing runtime files ..."
Write-Host ""

# CLI version cache — written after each delegate run to detect silent CLI updates
$cliVerFile = "$HOME\.local\share\copilot-delegate-cli-version"
if (Test-Path $cliVerFile) {
    Remove-Item $cliVerFile -Force
    Write-Host "        removed: $cliVerFile"
} else {
    Write-Host "        (CLI version cache not found — skipping)"
}

# delegate-runs.jsonl is intentionally NOT removed — it is a shared run log
# used by vibe-skill and other delegate tools. Delete manually if desired:
#   Remove-Item "$HOME\.local\share\delegate-runs.jsonl"
Write-Host ""
Write-Host "        NOTE: $HOME\.local\share\delegate-runs.jsonl was NOT removed."
Write-Host "              It is a shared log (used by vibe-skill etc.)."
Write-Host "              Delete manually if you no longer need it."

Write-Host ""
Write-Host "╔══════════════════════════════════════════╗"
Write-Host "║   Uninstall complete.                    ║"
Write-Host "╚══════════════════════════════════════════╝"
Write-Host ""
Write-Host "Repo files are untouched. Re-install anytime:"
Write-Host "  .\install.ps1"
Write-Host ""
