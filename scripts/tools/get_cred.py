"""
get_cred.py — 从 Windows 凭据管理器读取凭据的 Python 帮助函数
=====================================================================
用法（在任意脚本里）：

    import sys, os
    # 找到工具目录并加入 sys.path
    _TOOLS = next(
        (os.path.join(d, "scripts", "tools")
         for d in (os.path.dirname(os.path.abspath(__file__)),
                   *[os.path.dirname(os.path.abspath(__file__))] )
         if os.path.exists(os.path.join(d, "scripts", "tools", "get_cred.py"))),
        None
    )
    if _TOOLS: sys.path.insert(0, _TOOLS)
    from get_cred import get_cred

    api_key = get_cred("GEMINI_API_KEY", required=True)
"""

import os
import subprocess
import sys
from pathlib import Path

# ── 找 creds.ps1（最多向上遍历 6 层）─────────────────────────────────────────

def _find_creds_script() -> str | None:
    cached = os.environ.get("_CREDS_PS1")
    if cached and Path(cached).exists():
        return cached
    here = Path(__file__).resolve().parent
    for _ in range(6):
        candidate = here / "creds.ps1"
        if candidate.exists():
            os.environ["_CREDS_PS1"] = str(candidate)
            return str(candidate)
        here = here.parent
    return None


# ── 公共接口 ─────────────────────────────────────────────────────────────────

def get_cred(name: str, required: bool = False, fallback_env: str | None = None) -> str | None:
    """
    从 Windows 凭据管理器读取凭据。
    优先级：WCM → 环境变量 → None

    :param name:         凭据名（myproject/<name> 中的 <name>）
    :param required:     True 时凭据缺失则打印引导并 sys.exit(1)
    :param fallback_env: WCM 读取失败时尝试的环境变量名（默认同 name）
    """
    creds_script = _find_creds_script()

    if creds_script:
        try:
            res = subprocess.run(
                ["powershell.exe", "-NoProfile", "-File", creds_script, "get", name],
                capture_output=True, text=True, timeout=10
            )
            if res.returncode == 0:
                val = res.stdout.strip()
                if val:
                    return val
        except Exception:
            pass

    # Fallback：环境变量
    env_key = fallback_env or name
    val = os.environ.get(env_key)
    if val:
        return val

    if required:
        _guide(name, creds_script)
        sys.exit(1)

    return None


def _guide(name: str, creds_script: str | None) -> None:
    script = creds_script or "<project>\\scripts\\tools\\creds.ps1"
    print(f"\n❌ 凭据缺失或已过期：{name}", file=sys.stderr)
    print("   请在 PowerShell 中运行：", file=sys.stderr)
    print(f'   powershell -File "{script}" set {name} <你的值>', file=sys.stderr)
    print("   录入后重新运行本脚本。", file=sys.stderr)
    print("   换新设备？运行 setup.ps1 进行一键初始化并按提示录入凭据。", file=sys.stderr)
