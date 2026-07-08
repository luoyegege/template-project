"""temppath — Temp 输出路径统一解析器（方案 A 唯一路径来源）

所有项目脚本输出文件到 Temp 时，统一调用 temp_path() 获取最终路径，
直接写入对应子目录，不写 Temp 根目录。这样 organize-temp 永不需要"搬运"，
会话报给用户的路径 == 文件真实位置（路径绝对稳定）。

用法：
    from temppath import temp_path        # 若 lib 在 sys.path
    # 或：
    import sys; sys.path.insert(0, str(Path(__file__).resolve().parents[N] / "scripts" / "tools" / "lib"))
    from temppath import temp_path

    out = temp_path("data", "prerelease_cards.xlsx")   # -> <root>/Temp/data/prerelease_cards.xlsx
    out = temp_path("images", "banner.png")            # -> <root>/Temp/images/banner.png
    sub = temp_path("data", "_share/foo.json")         # 支持子路径，自动建中间目录

category 限定为 5 类标准子目录，传其他值会报错（强制规范）：
    images / pages / data / scripts / logs
"""
from pathlib import Path

VALID_CATEGORIES = ("images", "pages", "data", "scripts", "logs")

# 扩展名 → 推荐 category（供 guess_category 与 organize-temp 共用同一套映射）
EXT_CATEGORY = {
    ".png": "images", ".jpg": "images", ".jpeg": "images", ".gif": "images",
    ".webp": "images", ".svg": "images", ".ico": "images", ".bmp": "images",
    ".html": "pages",
    ".json": "data", ".csv": "data", ".xlsx": "data", ".xls": "data",
    ".txt": "data", ".md": "data", ".xml": "data", ".yaml": "data", ".yml": "data",
    ".py": "scripts", ".js": "scripts", ".ts": "scripts", ".ps1": "scripts",
    ".sh": "scripts", ".bat": "scripts", ".css": "scripts",
    ".log": "logs",
}


def find_project_root(start: Path | None = None) -> Path:
    """向上查找含 .claude 目录的项目根，移动无关。"""
    start = (start or Path(__file__)).resolve()
    for p in [start, *start.parents]:
        if (p / ".claude").is_dir():
            return p
    return start.parents[3]  # 兜底：lib 在 scripts/tools/lib/ 下，根在 parents[3]


def guess_category(filename: str) -> str:
    """按扩展名推断 category，未知归 data。"""
    return EXT_CATEGORY.get(Path(filename).suffix.lower(), "data")


def temp_path(category: str, filename: str, root: Path | None = None) -> Path:
    """返回 Temp/<category>/<filename> 的绝对路径，自动创建中间目录。

    category 必须是 5 类标准子目录之一；filename 可含子路径（如 "_share/x.json"）。
    """
    if category not in VALID_CATEGORIES:
        raise ValueError(
            f"category 必须是 {VALID_CATEGORIES} 之一，收到 {category!r}。"
            f"（如不确定用 guess_category(filename)）"
        )
    root = root or find_project_root()
    dest = root / "Temp" / category / filename
    dest.parent.mkdir(parents=True, exist_ok=True)
    return dest
