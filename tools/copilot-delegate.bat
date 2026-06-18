@echo off
:: copilot-delegate.bat — Windows shim for copilot-delegate.ps1
::
:: When the SKILL.md orchestrator calls ~/tools/copilot-delegate (no extension),
:: Windows resolves .bat before .ps1 in PATHEXT, so this shim is found first.
:: It immediately hands off to copilot-delegate.ps1 in the same directory.
::
:: Usage (called automatically — do not invoke directly):
::   copilot-delegate <workdir> <prompt> <model> [timeout-secs] [--verbose]
::
:: Requires: PowerShell 5.1+ and Python 3 on PATH for AIC logging.
::           See install.ps1 for full setup instructions.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0copilot-delegate.ps1" %*
