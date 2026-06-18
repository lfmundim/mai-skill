#Requires -Version 5.1
<#
.SYNOPSIS
    MAI skill installer for Windows (PowerShell).

.DESCRIPTION
    Sets up the MAI skill for GitHub Copilot CLI and Claude Code on Windows.

    What this does:
      1. Creates $HOME\tools\ and symlinks copilot-delegate + log-review-summary into it
      2. Creates skill directories under $HOME\.copilot\skills\ and $HOME\.claude\skills\
      3. Symlinks each skill's SKILL.md into the appropriate directories

    Symlinks mean `git pull` in this repo is all you ever need to update.
    Nothing is copied — everything points back to this repo.

    IMPORTANT — Symlink privilege:
      Windows requires one of the following to create symlinks:
        a) Run this script in an elevated (Administrator) terminal, OR
        b) Enable Developer Mode in Settings → System → For Developers

    NOTE — Execution policy:
      If PowerShell blocks the script, run first:
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned

    NOTE — copilot-delegate is a bash script:
      It runs via Git Bash or WSL — not native PowerShell.
      After install, invoke it with:
        bash "$HOME\tools\copilot-delegate" ...

.EXAMPLE
    .\install.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Resolve repo root (script's own directory) ────────────────────────────────
$RepoDir = $PSScriptRoot

Write-Host ""
Write-Host "╔══════════════════════════════════════════╗"
Write-Host "║         MAI Skill Installer              ║"
Write-Host "║         Windows / PowerShell             ║"
Write-Host "╚══════════════════════════════════════════╝"
Write-Host ""
Write-Host "Repo : $RepoDir"
Write-Host ""

# ── Helper: create a symlink, with a clear error if privilege is missing ──────
function New-Symlink {
    param(
        [string]$Path,   # where the symlink will live
        [string]$Target  # what it points to
    )

    # Remove a stale link at the same path before re-creating
    if (Test-Path $Path) {
        $item = Get-Item $Path -Force
        if ($item.LinkType -eq 'SymbolicLink') {
            Remove-Item $Path -Force
        } else {
            Write-Warning "  [SKIP] $Path exists and is not a symlink — remove manually if needed"
            return
        }
    }

    try {
        New-Item -ItemType SymbolicLink -Path $Path -Target $Target -Force | Out-Null
        Write-Host "        -> $Path"
    } catch [System.UnauthorizedAccessException] {
        Write-Host ""
        Write-Host "  [ERROR] Cannot create symlink at: $Path"
        Write-Host "          Windows requires Developer Mode OR an elevated (Admin) terminal."
        Write-Host "          Enable Developer Mode: Settings -> System -> For Developers"
        Write-Host "          Or re-run this script as Administrator."
        Write-Host ""
        exit 1
    }
}

# ── Step 1: $HOME\tools ───────────────────────────────────────────────────────
Write-Host "[ 1/3 ] Setting up $HOME\tools ..."
Write-Host ""

New-Item -ItemType Directory -Force "$HOME\tools" | Out-Null

# Bash delegate (used by Git Bash / WSL users)
New-Symlink -Path "$HOME\tools\copilot-delegate"      -Target "$RepoDir\tools\copilot-delegate"

# PowerShell delegate — native Windows port, used when there is no Git Bash / WSL
New-Symlink -Path "$HOME\tools\copilot-delegate.ps1"  -Target "$RepoDir\tools\copilot-delegate.ps1"

# .bat shim — lets the orchestrator call '~/tools/copilot-delegate' (no extension)
# on Windows; cmd.exe and PowerShell resolve .bat before .ps1 via PATHEXT
New-Symlink -Path "$HOME\tools\copilot-delegate.bat"  -Target "$RepoDir\tools\copilot-delegate.bat"

# The review-summary logger — used by the --with-review loop
New-Symlink -Path "$HOME\tools\log-review-summary"    -Target "$RepoDir\tools\log-review-summary"

Write-Host ""

# ── Step 2: skill directories + symlinks ──────────────────────────────────────
Write-Host "[ 2/3 ] Installing skills ..."
Write-Host ""

# Each key is the skill directory name; value is the source file in the repo root
$Skills = [ordered]@{
    "mai"             = "SKILL.md"
    "maion"           = "MAION.md"
    "maioff"          = "MAIOFF.md"
    "maistatus"       = "MAISTATUS.md"
    "mai-report"      = "MAI-REPORT.md"
    "mai-model-pick"  = "MAI-MODEL-PICK.md"
    "mai-model-clear" = "MAI-MODEL-CLEAR.md"
}

foreach ($skill in $Skills.Keys) {
    $src = $Skills[$skill]

    # Install into both Copilot CLI and Claude Code skill directories
    foreach ($base in "$HOME\.copilot\skills", "$HOME\.claude\skills") {
        $dir = "$base\$skill"
        New-Item -ItemType Directory -Force $dir | Out-Null
        New-Symlink -Path "$dir\SKILL.md" -Target "$RepoDir\$src"
    }
}

Write-Host ""

# ── Step 3: Verify copilot CLI is reachable ────────────────────────────────────
Write-Host "[ 3/3 ] Checking for Copilot CLI ..."

$copilot = Get-Command copilot -ErrorAction SilentlyContinue
if ($copilot) {
    $ver = & copilot --version 2>$null | Select-Object -First 1
    Write-Host "        copilot found: $ver"
} else {
    Write-Host "        [WARN] 'copilot' not found in PATH."
    Write-Host "               Install GitHub Copilot CLI and authenticate before using /mai."
}

Write-Host ""
Write-Host "╔══════════════════════════════════════════╗"
Write-Host "║   Installation complete!                 ║"
Write-Host "╚══════════════════════════════════════════╝"
Write-Host ""
Write-Host "copilot-delegate is a bash script. Run it via Git Bash or WSL:"
Write-Host ""
Write-Host "  # Git Bash:"
Write-Host "  bash `"`$HOME\tools\copilot-delegate`" `"`$env:TEMP`" `"Say hello in one sentence.`" gpt-5-mini 30"
Write-Host ""
Write-Host "Update anytime:"
Write-Host "  cd `"$RepoDir`""
Write-Host "  git pull"
Write-Host ""
