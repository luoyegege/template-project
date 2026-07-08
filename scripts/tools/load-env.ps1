# load-env.ps1 — 将 Windows 凭据管理器中的所有 myproject/* 凭据加载为环境变量
# 在需要的 PowerShell 会话中 dot-source 本脚本即可：
#   . .\scripts\tools\load-env.ps1
# 或在 Claude Code 启动前执行，确保各技能能读到环境变量。

$credsScript = Join-Path $PSScriptRoot "creds.ps1"

if (-not (Test-Path $credsScript)) {
    Write-Error "creds.ps1 not found at: $credsScript"
    exit 1
}

$lines = & $credsScript env
if (-not $lines) {
    Write-Host "[load-env] No credentials found in Windows Credential Manager." -ForegroundColor Yellow
    return
}

$count = 0
foreach ($line in $lines) {
    if ($line -match '^\$env:([^=]+)\s*=\s*(.+)$') {
        $key = $Matches[1]
        $val = $Matches[2].Trim("'")
        [System.Environment]::SetEnvironmentVariable($key, $val, "Process")
        Write-Host "  ✓ $key" -ForegroundColor Green
        $count++
    }
}

Write-Host "[load-env] Loaded $count credential(s) as environment variables." -ForegroundColor Cyan
