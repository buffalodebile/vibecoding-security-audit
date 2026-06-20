# PowerShell wrapper for security-audit.sh — runs it via Git Bash on Windows.
#
# Run from the root of the project you want to audit. Replace <skill-dir> with
# wherever this skill lives (e.g. $HOME\.claude\skills\web-security-audit):
#   & "<skill-dir>\run.ps1"
#   & "<skill-dir>\run.ps1" --ci
#   & "<skill-dir>\run.ps1" --fix

$ErrorActionPreference = "Stop"

$bashCandidates = @(
    "$env:ProgramFiles\Git\bin\bash.exe",
    "$env:ProgramFiles(x86)\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
)

$bash = $bashCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $bash) {
    Write-Error "Git Bash introuvable. Installez Git for Windows depuis https://git-scm.com/download/win"
    exit 1
}

$scriptPath = Join-Path $PSScriptRoot "security-audit.sh"

if (-not (Test-Path $scriptPath)) {
    Write-Error "security-audit.sh introuvable dans $PSScriptRoot. Re-cloner le skill."
    exit 1
}

# Convertir le path Windows en path bash-friendly
$scriptPathBash = $scriptPath -replace '\\', '/' -replace '^([A-Za-z]):', '/$1'.ToLower()

& $bash -c "bash '$scriptPathBash' $args"
exit $LASTEXITCODE
