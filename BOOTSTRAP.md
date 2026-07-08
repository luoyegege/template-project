# BOOTSTRAP.md - 新项目初始化指引

_从 template-project 复制的新项目。按以下步骤完成初始化。_

> **架构提醒（新架构：共享池 ∪ 项目）**
> 本模具的 `skills/` 是**空的**（只有 `.gitkeep`）。技能不再逐项目全量复制，而是由设备级
> **共享池**（`~/ClaudeAI/shared-skills/skills`）通过全局 symlink 联合加载。
> SessionStart hook（在设备级 `~/.claude/settings.local.json`）按 cwd 自动重建
> `~/.claude/skills` = 共享池 ∪ 当前项目 `skills/`（同名共享池优先）。
> 新项目**默认只吃共享池**；只有本项目专属的技能才放进本项目 `skills/`。
> Dashboard 是**主控 CC-project 的专属职责**，本模具不含 Dashboard，新项目会被 CC 自动扫描聚合。

## 第一步：替换占位符

全局搜索并替换以下占位符：

| 占位符 | 替换为 | 示例 |
|--------|--------|------|
| `{{PROJECT_NAME}}` | 项目名称 | `Auto-Project` |
| `{{PROJECT_DESCRIPTION}}` | 一句话项目描述 | `大神自动化运营` |

涉及文件：
- `config/CLAUDE.md`
- `.codex/config.toml`

## 第二步：初始化环境

```powershell
# 生成本项目 .claude/settings.local.json（机器特定路径 + additionalDirectories）+ Temp 子目录
pwsh -File scripts/tools/init-env.ps1
```

> **技能联合 hook 是设备级、一次性的**：`~/.claude/settings.local.json` 里的 SessionStart hook
> （调用 `~/.claude/resolve-skills.ps1`）按 cwd 把 `~/.claude/skills` 重建为「共享池 ∪ 当前项目 skills/」。
> 该 hook 每台设备只需装一次（首次搭建 CC-project / my-project 时已装）。新项目**无需重复配置**，
> 在本项目目录启动 Claude Code 即自动联合。若是全新设备，参考主控 CC-project 的设备级配置补装。

## 第三步：登记到 CC-project（可选）

若希望本项目出现在主控 CC 的全项目 Dashboard / 会话管理里，在
`~/ClaudeAI/CC-project/scripts/tools/projects.json` 的 `projects` 数组追加一条：

```json
{ "name": "{{PROJECT_NAME}}", "rel_path": "{{PROJECT_NAME}}", "skills_dir": "skills",
  "tasks_config": ".claude/tasks_config.json",
  "session_dir": "C--Users-<用户>-ClaudeAI-{{PROJECT_NAME}}" }
```

## 第四步：在 GitHub 创建仓库

```bash
git init
git add -A
git commit -m "init: 从 template-project 初始化"
gh repo create luoyegege/{{PROJECT_NAME}} --private --source=. --push
```

## 第五步：验证

- [ ] `pwsh -File scripts/tools/creds.ps1` 打印用法
- [ ] `pwsh -File scripts/tools/organize-temp.ps1` 无报错
- [ ] Claude Code 在项目目录启动，hooks 正常触发
- [ ] `~/.claude/skills` 已联合出共享池技能（`ls ~/.claude/skills`）

## 第六步：初始化完成

删除本文件（BOOTSTRAP.md），项目正式启用。

---

_模板来源：luoyegege/template-project_
