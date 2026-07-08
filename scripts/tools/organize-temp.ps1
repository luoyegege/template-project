# organize-temp.ps1 — Temp 文件管理（根目录兜底归类 + 回收站）
# Stop hook 调用：① 根目录散落文件按扩展名归类（兜底，仅管根目录漏网文件）
#                 ② 子目录超期文件移入 _recycle/  ③ _recycle/ 超期彻底删除
# 设计原则（方案A）：脚本应通过 temppath helper 直接写入子目录，子目录内文件
#   一律不搬动——会话报的路径 == 文件真实位置。本脚本只兜底根目录散落文件。
# 路径无关：基于 $PSScriptRoot 推导项目根目录，可移植到任何项目

$ProjectRoot = Split-Path (Split-Path $PSScriptRoot)
$TempRoot = Join-Path $ProjectRoot "Temp"

if (-not (Test-Path $TempRoot)) { exit 0 }

# 回收站：子目录中超过 N 天未修改的文件移入 _recycle/（只移不删，保留结构）
$RecycleDays = 30
$RecycleRoot = Join-Path $TempRoot "_recycle"

# 自动清理：_recycle/ 中未修改超过 N 天的文件彻底删除（爷已授权）
# 60 天 = 30天未动进回收站 + 30天回收站滞留
$PurgeDays = 60

$TypeMap = @{}
$TypeMap['.png']  = 'images'
$TypeMap['.jpg']  = 'images'
$TypeMap['.jpeg'] = 'images'
$TypeMap['.gif']  = 'images'
$TypeMap['.webp'] = 'images'
$TypeMap['.svg']  = 'images'
$TypeMap['.ico']  = 'images'
$TypeMap['.bmp']  = 'images'
$TypeMap['.json'] = 'data'
$TypeMap['.csv']  = 'data'
$TypeMap['.xlsx'] = 'data'
$TypeMap['.xls']  = 'data'
$TypeMap['.txt']  = 'data'
$TypeMap['.md']   = 'data'
$TypeMap['.xml']  = 'data'
$TypeMap['.yaml'] = 'data'
$TypeMap['.yml']  = 'data'
$TypeMap['.html'] = 'pages'
$TypeMap['.py']   = 'scripts'
$TypeMap['.js']   = 'scripts'
$TypeMap['.ts']   = 'scripts'
$TypeMap['.ps1']  = 'scripts'
$TypeMap['.sh']   = 'scripts'
$TypeMap['.bat']  = 'scripts'
$TypeMap['.css']  = 'scripts'
$TypeMap['.log']  = 'logs'

# 需要纠错的子目录（排除不参与归类的目录）
$ManagedDirs = @('images', 'pages', 'data', 'scripts', 'logs')

function Move-ToCorrectDir($file, [ref]$counter) {
    $ext = $file.Extension.ToLower()
    $target = $TypeMap[$ext]
    if (-not $target) { return }

    $currentDir = Split-Path $file.FullName
    $currentDirName = Split-Path $currentDir -Leaf
    if ($currentDirName -eq $target) { return }

    $destDir = Join-Path $TempRoot $target
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    $destPath = Join-Path $destDir $file.Name
    if (Test-Path $destPath) {
        $destPath = Join-Path $destDir ("{0}_{1}{2}" -f $file.BaseName, (Get-Date -Format 'yyyyMMdd_HHmmss'), $file.Extension)
    }

    Move-Item -Path $file.FullName -Destination $destPath -Force
    $counter.Value++
}

$moved = 0

# Pass 1: 根目录散落文件归类（兜底——正常情况脚本应直接写子目录，不经此步）
$files = Get-ChildItem -Path $TempRoot -File -ErrorAction SilentlyContinue
foreach ($f in $files) {
    Move-ToCorrectDir $f ([ref]$moved)
}

if ($moved -gt 0) {
    Write-Host "organize-temp: moved $moved file(s) from root"
}

# Pass 3: 回收站 — 子目录中超期未修改的文件移入 _recycle/（保留子目录结构）
$cutoff = (Get-Date).AddDays(-$RecycleDays)
$recycled = 0

foreach ($dir in $ManagedDirs) {
    $dirPath = Join-Path $TempRoot $dir
    if (-not (Test-Path $dirPath)) { continue }
    $oldFiles = Get-ChildItem -Path $dirPath -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $cutoff }
    foreach ($f in $oldFiles) {
        $destDir = Join-Path $RecycleRoot $dir
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        $destPath = Join-Path $destDir $f.Name
        if (Test-Path $destPath) {
            $destPath = Join-Path $destDir ("{0}_{1}{2}" -f $f.BaseName, (Get-Date -Format 'yyyyMMdd_HHmmss'), $f.Extension)
        }
        Move-Item -Path $f.FullName -Destination $destPath -Force
        $recycled++
    }
}

if ($recycled -gt 0) {
    Write-Host "organize-temp: recycled $recycled file(s) (>$RecycleDays days) to _recycle/"
}

# Pass 4: 自动清理 — _recycle/ 中未修改超过 $PurgeDays 天的文件彻底删除（爷已授权）
if (Test-Path $RecycleRoot) {
    $purgeCutoff = (Get-Date).AddDays(-$PurgeDays)
    $purgeFiles = Get-ChildItem -Path $RecycleRoot -File -Recurse -ErrorAction SilentlyContinue |
                  Where-Object { $_.LastWriteTime -lt $purgeCutoff }
    $purged = 0
    foreach ($f in $purgeFiles) {
        Remove-Item -Path $f.FullName -Force -ErrorAction SilentlyContinue
        $purged++
    }
    # 清理 _recycle/ 下变空的子目录
    Get-ChildItem -Path $RecycleRoot -Directory -Recurse -ErrorAction SilentlyContinue |
        Where-Object { (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue).Count -eq 0 } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    if ($purged -gt 0) {
        Write-Host "organize-temp: purged $purged file(s) (>$PurgeDays days) from _recycle/"
    }
}
