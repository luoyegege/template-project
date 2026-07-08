# init-env.ps1 — 统一初始化本地环境配置
# 代理由 cc-switch 统一管理（127.0.0.1:15721），此脚本不再写入代理 env。
# 若 settings.json 不存在（新设备），从模板创建（cc-switch 默认值）。
# 若 settings.json 已存在，不覆盖 env 段，只更新 .claude/settings.local.json。
#
# 用法：
#   powershell -File '<repo>\scripts\tools\init-env.ps1'
#
# 行为：
#   ~/.bashrc                    — 从模板全量生成（含 CLAUDE_PROJECT_ROOT）
#   ~/.claude/settings.json      — 若不存在：从模板创建（cc-switch 默认）；已存在：不动
#   .claude/settings.local.json  — 全量生成（机器特定路径，gitignored）

param(
    [string]$Proxy = ""
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding            = [System.Text.Encoding]::UTF8

$root        = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$rootUnix    = $root -replace '\\', '/'
$tplDir      = "$root\scripts\tools\templates"
$bashrcOut   = "$env:USERPROFILE\.bashrc"
$settingsOut = "$env:USERPROFILE\.claude\settings.json"
$localOut    = "$root\.claude\settings.local.json"
$utf8NoBom   = New-Object System.Text.UTF8Encoding $false

function Read-Utf8([string]$path) {
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

function Write-Utf8([string]$path, [string]$content) {
    [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}

Write-Host "项目根：$root" -ForegroundColor Cyan

# ── 生成 ~/.bashrc ────────────────────────────────────────
$bashrcTpl = Read-Utf8 "$tplDir\bashrc.template"
$rendered  = $bashrcTpl -replace '\{\{PROJECT_ROOT_UNIX\}\}', $rootUnix
Write-Utf8 $bashrcOut $rendered
Write-Host "✓ ~/.bashrc 已生成" -ForegroundColor Green

# ── 生成 ~/.claude/settings.json（仅新设备，已存在则跳过）────
if (Test-Path $settingsOut) {
    Write-Host "✓ ~/.claude/settings.json 已存在，由 cc-switch 管理，跳过" -ForegroundColor Yellow
} else {
    $settingsTpl = Read-Utf8 "$tplDir\settings.template.json"
    Write-Utf8 $settingsOut $settingsTpl
    Write-Host "✓ ~/.claude/settings.json 已从模板创建（cc-switch 默认）" -ForegroundColor Green
    Write-Host "  请启动 cc-switch 后再启动 Claude Code" -ForegroundColor Yellow
}

# ── 生成 .claude/settings.local.json（机器特定，gitignored）────
$localSettings = [ordered]@{
    skipDangerousModePermissionPrompt = $true
    permissions = [ordered]@{
        allow = @(
            "Write", "Edit", "Read",
            "Bash",
            "Bash(opencli browser:*)",
            "Bash(echo `"---exit: `$?`")",
            "Edit($root\.claude\**)",
            "Write($root\.claude\**)",
            "Read($root\.claude\**)"
        )
        defaultMode           = "bypassPermissions"
        additionalDirectories = @(
            "$env:USERPROFILE\.claude",
            $root
        )
    }
}
Write-Utf8 $localOut ($localSettings | ConvertTo-Json -Depth 10)
Write-Host "✓ .claude/settings.local.json 已生成" -ForegroundColor Green

# ── 创建 Temp 子目录结构 ────────────────────────────────────
$tempDirs = @('images', 'pages', 'data', 'scripts', 'logs')
foreach ($d in $tempDirs) {
    $p = Join-Path $root "Temp\$d"
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}
Write-Host "✓ Temp/ 子目录已就绪（images/pages/data/scripts/logs）" -ForegroundColor Green

# ── 创建 docs/pages/ ─────────────────────────────────────────
$docsPages = Join-Path $root "docs\pages"
if (-not (Test-Path $docsPages)) { New-Item -ItemType Directory -Path $docsPages -Force | Out-Null }
Write-Host "✓ docs/pages/ 已就绪" -ForegroundColor Green

Write-Host ""
Write-Host "完成！重启后生效：" -ForegroundColor Yellow
Write-Host "  Git Bash：source ~/.bashrc"
Write-Host "  Claude  ：Stop-Process -Name Claude -Force"
Write-Host ""
