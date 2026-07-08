# creds.ps1 -- Windows Credential Manager + Git AES-256 sync
# Local:  set / get / delete / list / env  (set/delete auto-push if GITHUB_PAT in WCM)
# Sync:   sync-push [PAT] | sync-pull [PAT] [--overwrite] | sync-status
# 初始化时将 $PREFIX 改为本项目前缀（如 "myapp/"）
param(
    [Parameter(Position=0)][string]$Action,
    [Parameter(Position=1)][string]$Name,
    [Parameter(Position=2)][string]$Value
)

$PREFIX = "{{PREFIX}}/"

if (-not ([System.Management.Automation.PSTypeName]"WinCred").Type) {
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class WinCred {
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool CredRead(string target, uint type, uint flags, out IntPtr pCred);
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool CredWrite([In] ref CREDENTIAL cred, uint flags);
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool CredDelete(string target, uint type, uint flags);
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool CredEnumerate(string filter, uint flags, out uint count, out IntPtr pCreds);
    [DllImport("advapi32.dll")] static extern void CredFree(IntPtr buf);
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct CREDENTIAL {
        public uint Flags; public uint Type;
        [MarshalAs(UnmanagedType.LPWStr)] public string TargetName;
        [MarshalAs(UnmanagedType.LPWStr)] public string Comment;
        public long LastWritten; public uint CredentialBlobSize;
        public IntPtr CredentialBlob; public uint Persist;
        public uint AttributeCount; public IntPtr Attributes;
        [MarshalAs(UnmanagedType.LPWStr)] public string TargetAlias;
        [MarshalAs(UnmanagedType.LPWStr)] public string UserName;
    }
    const uint GENERIC = 1; const uint LOCAL_MACHINE = 2;
    public static bool Write(string target, string password) {
        byte[] blob = Encoding.Unicode.GetBytes(password);
        var c = new CREDENTIAL { Type=GENERIC, TargetName=target, UserName="claude",
            CredentialBlobSize=(uint)blob.Length, CredentialBlob=Marshal.AllocHGlobal(blob.Length), Persist=LOCAL_MACHINE };
        Marshal.Copy(blob, 0, c.CredentialBlob, blob.Length);
        bool ok = CredWrite(ref c, 0); Marshal.FreeHGlobal(c.CredentialBlob); return ok;
    }
    public static string Read(string target) {
        IntPtr p; if (!CredRead(target, GENERIC, 0, out p)) return null;
        var c = (CREDENTIAL)Marshal.PtrToStructure(p, typeof(CREDENTIAL));
        byte[] blob = new byte[c.CredentialBlobSize];
        Marshal.Copy(c.CredentialBlob, blob, 0, blob.Length); CredFree(p);
        return Encoding.Unicode.GetString(blob);
    }
    public static bool Delete(string target) { return CredDelete(target, GENERIC, 0); }
    public static string[] List(string prefix) {
        uint count; IntPtr p;
        string filter = string.IsNullOrEmpty(prefix) ? null : prefix + "*";
        if (!CredEnumerate(filter, 0, out count, out p)) return new string[0];
        var list = new List<string>();
        for (int i = 0; i < (int)count; i++) {
            IntPtr pc = Marshal.ReadIntPtr(p, i * IntPtr.Size);
            var c = (CREDENTIAL)Marshal.PtrToStructure(pc, typeof(CREDENTIAL));
            list.Add(c.TargetName);
        }
        CredFree(p); return list.ToArray();
    }
}
'@
}

function Get-GitHubPat {
    $v = [WinCred]::Read($PREFIX + "GITHUB_PAT")
    if ($v) { return $v }
    $v = [WinCred]::Read("git:https://github.com")
    if ($v) { return $v }
    return $null
}

function Invoke-AesEncrypt {
    param([string]$PlainText, [string]$Passphrase)
    $salt = [System.Text.Encoding]::UTF8.GetBytes("{{PREFIX}}-secrets")
    $pwd  = [System.Text.Encoding]::UTF8.GetBytes($Passphrase)
    $pdb  = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($pwd, $salt, 100000)
    $key  = $pdb.GetBytes(32); $iv = $pdb.GetBytes(16)
    $aes  = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $key; $aes.IV = $iv
    $aes.Mode    = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $enc    = $aes.CreateEncryptor()
    $plain  = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
    $cipher = $enc.TransformFinalBlock($plain, 0, $plain.Length)
    $aes.Dispose()
    $out = New-Object byte[] ($salt.Length + $iv.Length + $cipher.Length)
    [System.Buffer]::BlockCopy($salt,   0, $out, 0,                          $salt.Length)
    [System.Buffer]::BlockCopy($iv,     0, $out, $salt.Length,               $iv.Length)
    [System.Buffer]::BlockCopy($cipher, 0, $out, $salt.Length + $iv.Length,  $cipher.Length)
    return $out
}

function Invoke-AesDecrypt {
    param([byte[]]$EncBytes, [string]$Passphrase)
    $saltLen = [System.Text.Encoding]::UTF8.GetByteCount("{{PREFIX}}-secrets")
    $salt = New-Object byte[] $saltLen; $iv = New-Object byte[] 16
    [System.Buffer]::BlockCopy($EncBytes, 0,            $salt, 0, $saltLen)
    [System.Buffer]::BlockCopy($EncBytes, $saltLen,     $iv,   0, 16)
    $cipher = New-Object byte[] ($EncBytes.Length - $saltLen - 16)
    [System.Buffer]::BlockCopy($EncBytes, $saltLen + 16, $cipher, 0, $cipher.Length)
    $pwd = [System.Text.Encoding]::UTF8.GetBytes($Passphrase)
    $pdb = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($pwd, $salt, 100000)
    $key = $pdb.GetBytes(32)
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $key; $aes.IV = $iv
    $aes.Mode    = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $dec   = $aes.CreateDecryptor()
    $plain = $dec.TransformFinalBlock($cipher, 0, $cipher.Length)
    $aes.Dispose()
    return [System.Text.Encoding]::UTF8.GetString($plain)
}

function Invoke-SyncPush {
    param([string]$Pat)
    if (-not $Pat) { $Pat = Get-GitHubPat }
    if (-not $Pat) { Write-Error "Usage: creds.ps1 sync-push [<GITHUB_PAT>]  (or store GITHUB_PAT in WCM)"; exit 1 }
    $targets = [WinCred]::List($PREFIX)
    if ($targets.Count -eq 0) { Write-Warning "No local credentials"; return }
    $dict = @{}
    foreach ($t in $targets) { $dict[$t.Substring($PREFIX.Length)] = [WinCred]::Read($t) }
    $json = $dict | ConvertTo-Json -Compress
    Write-Host ("[sync-push] " + $targets.Count + " credentials") -ForegroundColor Cyan
    $encBytes = Invoke-AesEncrypt -PlainText $json -Passphrase $Pat
    $encB64   = [Convert]::ToBase64String($encBytes)
    $repoRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
    if (-not $repoRoot) { Write-Error "Not in a git repo"; exit 1 }
    $repoRoot = $repoRoot.Trim()
    $rnd    = [Guid]::NewGuid().ToString("N").Substring(0, 8)
    $wtPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), ("tp-sec-" + $rnd))
    $branchExists = [string](& git -C $repoRoot branch --list "secrets" 2>$null)
    $remoteBranch = [string](& git -C $repoRoot ls-remote --heads origin secrets 2>$null)
    if (-not $branchExists -and -not $remoteBranch) {
        Write-Host "[sync-push] Creating orphan secrets branch..." -ForegroundColor Yellow
        & git -C $repoRoot worktree add --orphan -b secrets $wtPath 2>$null | Out-Null
        Set-Content -Path (Join-Path $wtPath "secrets.enc") -Value $encB64 -Encoding ascii
        & git -C $wtPath add "secrets.enc" | Out-Null
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm"
        & git -C $wtPath commit -m ("chore: init secrets [" + $ts + "]") | Out-Null
    } else {
        if ($remoteBranch) { & git -C $repoRoot fetch origin "secrets:secrets" 2>$null | Out-Null }
        & git -C $repoRoot worktree add $wtPath secrets 2>$null | Out-Null
        Set-Content -Path (Join-Path $wtPath "secrets.enc") -Value $encB64 -Encoding ascii
        & git -C $wtPath add "secrets.enc" | Out-Null
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm"
        $cnt = $targets.Count
        & git -C $wtPath commit -m ("chore: sync secrets [" + $cnt + " keys " + $ts + "]") | Out-Null
    }
    Write-Host "[sync-push] Pushing to origin/secrets..." -ForegroundColor Cyan
    $pushOut = & git -C $wtPath push origin secrets 2>&1
    $pushOk  = $LASTEXITCODE -eq 0
    & git -C $repoRoot worktree remove $wtPath --force 2>$null | Out-Null
    if ($pushOk) {
        Write-Host ("[sync-push] Done - " + $targets.Count + " keys pushed") -ForegroundColor Green
    } else {
        Write-Error ("push failed: " + ($pushOut -join " ")); exit 1
    }
}

function Invoke-SyncPull {
    param([string]$Pat, [bool]$Overwrite = $false)
    if (-not $Pat) { $Pat = Get-GitHubPat }
    if (-not $Pat) { Write-Error "Usage: creds.ps1 sync-pull [<GITHUB_PAT>] [--overwrite]  (or store GITHUB_PAT in WCM)"; exit 1 }
    $repoRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
    if (-not $repoRoot) { Write-Error "Not in a git repo"; exit 1 }
    $repoRoot = $repoRoot.Trim()
    Write-Host "[sync-pull] Fetching origin/secrets..." -ForegroundColor Cyan
    & git -C $repoRoot fetch origin secrets 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Error "fetch failed"; exit 1 }
    $encB64 = (& git -C $repoRoot show "FETCH_HEAD:secrets.enc" 2>&1)
    if ($LASTEXITCODE -ne 0) { Write-Error ("Cannot read secrets.enc: " + $encB64); exit 1 }
    try {
        $encBytes = [Convert]::FromBase64String($encB64.Trim())
        $json     = Invoke-AesDecrypt -EncBytes $encBytes -Passphrase $Pat
        $dict     = $json | ConvertFrom-Json
    } catch {
        Write-Error ("Decryption failed - wrong PAT? " + $_); exit 1
    }
    $imported = 0; $skipped = 0
    foreach ($prop in $dict.PSObject.Properties) {
        $k = $prop.Name; $v = $prop.Value
        $existing = [WinCred]::Read($PREFIX + $k)
        if ($null -ne $existing -and -not $Overwrite) {
            Write-Host ("  skip: " + $k) -ForegroundColor Gray; $skipped++
        } else {
            [WinCred]::Write($PREFIX + $k, $v) | Out-Null
            Write-Host ("  OK: " + $k) -ForegroundColor Green; $imported++
        }
    }
    Write-Host ("[sync-pull] Done - imported " + $imported + ", skipped " + $skipped) -ForegroundColor Green
    if ($skipped -gt 0) { Write-Host "  Tip: add --overwrite to replace existing" -ForegroundColor Gray }
}

function Invoke-SyncStatus {
    $repoRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
    if (-not $repoRoot) { Write-Error "Not in a git repo"; exit 1 }
    $repoRoot = $repoRoot.Trim()
    $localTargets = [WinCred]::List($PREFIX)
    $localKeys    = $localTargets | ForEach-Object { $_.Substring($PREFIX.Length) }
    $hasRemote = $false; $lastCommit = "(unavailable)"
    & git -C $repoRoot fetch origin secrets 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $hasRemote  = $true
        $lastCommit = (& git -C $repoRoot log FETCH_HEAD --oneline -1 2>$null).Trim()
    }
    Write-Host ""
    Write-Host "=== Credential Sync Status ===" -ForegroundColor Cyan
    Write-Host ("Local WCM (" + $localKeys.Count + " keys):") -ForegroundColor White
    foreach ($k in $localKeys) { Write-Host ("  - " + $k) -ForegroundColor Gray }
    Write-Host "Remote secrets branch:" -ForegroundColor White
    if ($hasRemote) {
        Write-Host ("  Last commit : " + $lastCommit) -ForegroundColor Gray
        Write-Host  "  secrets.enc : exists (AES-256, run sync-pull to import)" -ForegroundColor Gray
    } else {
        Write-Host "  Not found - run: creds.ps1 sync-push <PAT>" -ForegroundColor Yellow
    }
    Write-Host ""
}

switch ($Action) {
    "set" {
        if (-not $Name -or -not $Value) { Write-Error "Usage: creds.ps1 set <NAME> <VALUE>"; exit 1 }
        $ok = [WinCred]::Write($PREFIX + $Name, $Value)
        if (-not $ok) { Write-Error ("Failed: " + $Name); exit 1 }
        Write-Host ("OK Saved: " + $Name) -ForegroundColor Green
        if (Get-GitHubPat) { Invoke-SyncPush }
    }
    "get" {
        if (-not $Name) { Write-Error "Usage: creds.ps1 get <NAME>"; exit 1 }
        $val = [WinCred]::Read($PREFIX + $Name)
        if ($null -eq $val) { Write-Error ("Not found: " + $Name); exit 1 }
        $val
    }
    "delete" {
        if (-not $Name) { Write-Error "Usage: creds.ps1 delete <NAME>"; exit 1 }
        $ok = [WinCred]::Delete($PREFIX + $Name)
        if (-not $ok) { Write-Error ("Not found: " + $Name); exit 1 }
        Write-Host ("OK Deleted: " + $Name) -ForegroundColor Yellow
        if (Get-GitHubPat) { Invoke-SyncPush }
    }
    "list" {
        $targets = [WinCred]::List($PREFIX)
        if ($targets.Count -eq 0) { Write-Host "(no credentials stored yet)"; exit 0 }
        Write-Host ("`nStored credentials (" + $PREFIX + "*):") -ForegroundColor Cyan
        foreach ($t in $targets) {
            $short = $t.Substring($PREFIX.Length)
            $val   = [WinCred]::Read($t)
            $mask  = if ($val.Length -le 4) { "****" } else { $val.Substring(0,4) + ("*" * [Math]::Min(8, $val.Length-4)) }
            Write-Host ("  {0,-30} {1}" -f $short, $mask) -ForegroundColor White
        }
        Write-Host ""
    }
    "env" {
        $targets = [WinCred]::List($PREFIX)
        foreach ($t in $targets) {
            $k = $t.Substring($PREFIX.Length)
            $v = [WinCred]::Read($t)
            if ($v) { Write-Output ("`$env:" + $k + " = " + [char]39 + $v + [char]39) }
        }
    }
    "sync-push"   { Invoke-SyncPush -Pat $Name }
    "sync-pull" {
        if ($Name -eq "--overwrite") { Invoke-SyncPull -Pat "" -Overwrite $true }
        else { Invoke-SyncPull -Pat $Name -Overwrite ($Value -eq "--overwrite") }
    }
    "sync-status" { Invoke-SyncStatus }
    default {
        Write-Host "creds.ps1 -- WCM + Git AES-256 sync"
        Write-Host "Local : set / get / delete / list / env"
        Write-Host "Sync  : sync-push [PAT] | sync-pull [PAT] [--overwrite] | sync-status"
        Write-Host "        PAT optional - auto-reads GITHUB_PAT or git:https://github.com from WCM"
    }
}
