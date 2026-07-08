# Claude Code 项目模具（template-project）

新卫星项目的**极简模具**。clone 后按 `BOOTSTRAP.md` 完成初始化即可独立运行。
技能不随项目走，而是由设备级**共享池**联合加载；Dashboard 由主控 CC-project 统一承载，本模具不含 Dashboard。

---

## 三层架构

| 层 | 位置 | 职责 |
|----|------|------|
| Agent 基础层 | `~/.claude/`（设备级） | SessionStart hook 按 cwd 联合 `~/.claude/skills` = 共享池 ∪ 当前项目 |
| 共享技能池 | `~/ClaudeAI/shared-skills/`（独立仓） | 全设备通用技能来源（clone 即有），同名共享池优先 |
| 卫星项目（本模具） | `~/ClaudeAI/<项目>/` | 只放**本项目专属**技能到 `skills/`；默认空，纯吃共享池 |
| 主控 CC-project | `~/ClaudeAI/CC-project/` | 承载全项目 Dashboard，自动扫描聚合各卫星项目 |

### 配置分层（跨设备安全）

| 文件 | 追踪方式 | 内容 |
|------|---------|------|
| `.claude/settings.json` | git 追踪 | 机器无关：权限、hooks（`$CLAUDE_PROJECT_DIR` 变量） |
| `~/.claude/settings.local.json` | 设备级、gitignored | 机器特定：绝对路径、additionalDirectories、SessionStart 技能联合 hook |
| `config/CLAUDE.md` | git 追踪 | Agent 人设 + 行为准则 + 技能路由指针 |

### 自动化 Hooks

- **PermissionRequest** — 权限请求自动允许（bypass 模式）
- **Stop** — 会话结束时：① 整理 Temp 目录 ② git auto-save + push origin main

### 凭证管理（WCM + AES-256 同步）

```powershell
scripts/tools/creds.ps1 set <KEY> "<VALUE>"     # 写入本机 WCM
scripts/tools/creds.ps1 sync-push <PAT>          # 加密推到 GitHub secrets 分支
scripts/tools/creds.ps1 sync-pull <PAT>          # 新设备拉取恢复
```

---

## 快速开始

```powershell
# 1. Clone
git clone https://github.com/luoyegege/template-project.git my-new-project
cd my-new-project

# 2. 初始化环境（生成 ~/.bashrc + settings.local.json，含 SessionStart 技能联合 hook）
pwsh -File scripts/tools/init-env.ps1

# 3. 按 BOOTSTRAP.md 替换占位符，然后删除 BOOTSTRAP.md
```

技能会由 SessionStart hook 自动联合出来（共享池 ∪ 本项目 skills/），无需手动拉取。

---

## 目录结构

```
project/
├── CLAUDE.md                   → @config/CLAUDE.md（引用）
├── BOOTSTRAP.md                初始化指引（完成后删除）
├── config/
│   ├── CLAUDE.md               Agent 人设 + 行为准则
│   └── skill-routing.md        技能路由表（共享池技能）
├── .claude/
│   ├── settings.json           权限 + Hooks（git 追踪）
│   └── tasks_config.json       定时任务注册表（初始为空）
├── .codex/
│   └── config.toml             Codex CLI 配置
├── scripts/tools/
│   ├── init-env.ps1            环境初始化（唯一入口）
│   ├── setup.ps1               首次引导
│   ├── creds.ps1               凭证管理 + AES-256 同步
│   ├── organize-temp.ps1       Temp 自动归类
│   └── lib/                    公共 helper（temppath 等）
├── skills/                     本项目专属技能（默认空，只有 .gitkeep）
├── assets/                     正式资源
└── Temp/                       临时文件（gitignored）
    ├── pages/ images/ data/ scripts/ logs/
```

---

## 添加技能

- **通用技能**（跨项目可复用）→ 推到共享池 `~/ClaudeAI/shared-skills/skills/`（用 `update-shared.ps1`），所有项目自动获得。
- **本项目专属技能** → 用 skill-creator 写入本项目 `skills/<技能名>/`，并在 `config/skill-routing.md` 追加分组。

> 不要手写到 `~/.claude/skills/` —— 那是每次 SessionStart 联合重建的，会被覆盖。

---

## Temp 命名规范

所有临时文件统一格式：`{正式文件名}-demo-v{N}.{ext}`（如 `Temp/pages/report-demo-v3.html`）。

---

仓库：[luoyegege/template-project](https://github.com/luoyegege/template-project)
