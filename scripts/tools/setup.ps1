# setup.ps1 — 新设备初始化脚本（git clone 后运行一次）
# 包含：1) 注册 Temp 自动清理任务  2) 引导录入凭据

Write-Host "`n=== template-project 初始化 ===" -ForegroundColor Cyan

# ── 1. 注册 Temp 自动清理任务 ────────────────────────────────────────────────
Write-Host "`n[1/2] 注册 Temp 自动清理任务计划..." -ForegroundColor Yellow
$taskName   = "CleanTemplateProjectTemp"
$scriptPath = Join-Path $PSScriptRoot "cleanup-temp.ps1"

$action   = New-ScheduledTaskAction -Execute 'pwsh.exe' `
                -Argument "-NoProfile -WindowStyle Hidden -File `"$scriptPath`""
$trigger  = New-ScheduledTaskTrigger -Daily -At "03:23"
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
                -StartWhenAvailable -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Settings $settings -Force | Out-Null
Write-Host "  OK 任务 '$taskName' 已注册（每天 03:23）" -ForegroundColor Green

# ── 2. 引导录入凭据 ──────────────────────────────────────────────────────────
Write-Host "`n[2/2] 凭据初始化..." -ForegroundColor Yellow
$credsScript = Join-Path $PSScriptRoot "creds.ps1"
Write-Host "  凭据管理工具：$credsScript" -ForegroundColor Gray
Write-Host ""

Write-Host "  是否从 Git secrets 分支自动拉取凭据？" -ForegroundColor White
Write-Host "  （需要 GitHub PAT，省去手动逐条录入）" -ForegroundColor Gray
$choice = Read-Host "  输入 y 自动拉取，直接回车跳过"

if ($choice -eq "y" -or $choice -eq "Y") {
    $pat = Read-Host "  请输入 GitHub PAT（输入不回显）" -AsSecureString
    $patPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pat)
    )
    Write-Host ""
    & pwsh -NoProfile -File "$credsScript" sync-pull $patPlain
    Write-Host ""
    Write-Host "  OK 凭据拉取完成，可运行 list 确认：" -ForegroundColor Green
    Write-Host "    pwsh -File `"$credsScript`" list" -ForegroundColor Gray
} else {
    Write-Host ""
    Write-Host "  请按需录入本项目所需凭据（示例，按实际替换）：" -ForegroundColor White
    Write-Host '    creds.ps1 set ANTHROPIC_API_KEY  [Anthropic Key]' -ForegroundColor Gray
    Write-Host '    creds.ps1 set GITHUB_PAT         [GitHub PAT]' -ForegroundColor Gray
    Write-Host ""
    Write-Host "  录完后可同步到云端：" -ForegroundColor White
    Write-Host '    creds.ps1 sync-push [GITHUB_PAT]' -ForegroundColor Gray
    Write-Host ""
    Write-Host "  查看已存储：  creds.ps1 list" -ForegroundColor Gray
}

Write-Host "`n=== 初始化完成 ===" -ForegroundColor Cyan
