/**
 * get_cred.js — 从 Windows 凭据管理器读取凭据的 Node.js 帮助函数
 * ==================================================================
 * 用法：
 *   const { getCred } = require('../../scripts/tools/get_cred');
 *   const apiKey = getCred('ARK_API_KEY', { required: true });
 *
 * 优先级：WCM → process.env → null
 */

'use strict';

const { execFileSync } = require('child_process');
const path = require('path');
const fs   = require('fs');

// ── 找 creds.ps1（从本文件向上最多 6 层）────────────────────────────────────

function _findCredsScript() {
  if (process.env._CREDS_PS1 && fs.existsSync(process.env._CREDS_PS1)) {
    return process.env._CREDS_PS1;
  }
  let dir = __dirname;
  for (let i = 0; i < 6; i++) {
    const candidate = path.join(dir, 'creds.ps1');
    if (fs.existsSync(candidate)) {
      process.env._CREDS_PS1 = candidate;
      return candidate;
    }
    dir = path.dirname(dir);
  }
  return null;
}

// ── 公共接口 ─────────────────────────────────────────────────────────────────

/**
 * 从 Windows 凭据管理器读取凭据。
 * @param {string} name           凭据名（myproject/<name> 中的 <name>）
 * @param {object} opts
 * @param {boolean} opts.required  true 时缺失则打印引导并 process.exit(1)
 * @param {string}  opts.fallbackEnv 环境变量备用名（默认同 name）
 * @returns {string|null}
 */
function getCred(name, { required = false, fallbackEnv = null } = {}) {
  const credsScript = _findCredsScript();

  if (credsScript) {
    try {
      const val = execFileSync(
        'powershell.exe',
        ['-NoProfile', '-File', credsScript, 'get', name],
        { encoding: 'utf8', timeout: 10000 }
      ).trim();
      if (val) return val;
    } catch (_) { /* fallthrough */ }
  }

  // Fallback：环境变量
  const envKey = fallbackEnv || name;
  if (process.env[envKey]) return process.env[envKey];

  if (required) {
    _guide(name, credsScript);
    process.exit(1);
  }

  return null;
}

function _guide(name, credsScript) {
  const script = credsScript || String.raw`<project>\scripts\tools\creds.ps1`;
  console.error(`\n❌ 凭据缺失或已过期：${name}`);
  console.error(`   请在 PowerShell 中运行：`);
  console.error(`   powershell -File "${script}" set ${name} <你的值>`);
  console.error(`   录入后重新运行本脚本。`);
  console.error(`   换新设备？运行 setup.ps1 进行一键初始化并按提示录入凭据。`);
}

module.exports = { getCred };
