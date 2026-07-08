# cleanup-temp.ps1 — 清理项目 Temp 目录
# 路径通过 $PSScriptRoot 动态推算，无需硬编码，在任意设备上均可运行
#
# 清理规则：
#   .html                       → 永久保留
#   playwright_profile/ skills/ → 永久保留（目录级别）
#   .log                        → 超过 60 天删除
#   .png .py .js .bat .ps1      → 超过 30 天删除
#   其他文件                     → 超过 30 天删除

$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$tempDir     = Join-Path $projectRoot "Temp"
$now         = Get-Date

$keepForever_dirs = @("playwright_profile", "skills")

if (-not (Test-Path $tempDir)) {
    Write-Host "Temp dir not found: $tempDir"
    exit 0
}

$deleted = 0

Get-ChildItem $tempDir -Recurse -File | ForEach-Object {
    $file = $_

    # 跳过永久保留目录下的文件
    $relPath = $file.FullName.Substring($tempDir.Length).TrimStart('\','/')
    $topDir  = $relPath.Split([IO.Path]::DirectorySeparatorChar)[0]
    if ($keepForever_dirs -contains $topDir) { return }

    $ext     = $file.Extension.ToLower()
    $ageDays = ($now - $file.LastWriteTime).TotalDays

    $maxDays = switch ($ext) {
        ".html" { [int]::MaxValue }   # 永久保留
        ".log"  { 60 }
        { $_ -in ".png",".py",".js",".bat",".ps1" } { 30 }
        default { 30 }
    }

    if ($ageDays -gt $maxDays) {
        Remove-Item $file.FullName -Force
        $deleted++
    }
}

# 清除空子目录（排除永久保留目录）
Get-ChildItem $tempDir -Recurse -Directory |
    Where-Object { $keepForever_dirs -notcontains $_.Name } |
    Sort-Object FullName -Descending |
    Where-Object { (Get-ChildItem $_.FullName -Recurse -File).Count -eq 0 } |
    Remove-Item -Force -Recurse

Write-Host "[$(Get-Date -f 'yyyy-MM-dd HH:mm')] Temp cleanup: removed $deleted file(s). ($tempDir)"
