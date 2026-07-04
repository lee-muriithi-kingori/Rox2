/*
 * Rox2 WebUI - extracted from index.html so reviewers can read this
 * separately from the markup. All UI behavior lives here.
 *
 * No global dependencies. Uses the WebView-supplied exec API
 * (window.ksu.exec / window.apatch.exec) when available, falls back
 * to read-only mode in a plain browser, and tries Shizuku first if
 * exposed by the host.
 */
(function () {
  'use strict';

  const MOD = 'Rox2';
  const MOD_PATH = '/data/adb/modules/' + MOD;
  const LOG_PATH = '/data/local/tmp/Rox2.log';
  const ALLOWLIST_PATH = MOD_PATH + '/allowlist.json';

  const MANAGER_PKGS = new Set([
    'com.topjohnwu.magisk', 'me.weishu.kernelsu', 'me.bmax.apatch',
    'org.lsposed.manager', 'de.robv.android.xposed.installer'
  ]);

  // ---------- manager / exec detection ----------
  function detectManager() {
    if (typeof window.ksu    !== 'undefined') return 'kernelsu';
    if (typeof window.apatch !== 'undefined') return 'apatch';
    return 'browser';
  }
  const mgr = detectManager();
  const readOnly = mgr === 'browser';

  async function exec(cmd) {
    if (window.shizuku && typeof window.shizuku.exec === 'function') {
      try {
        const r = await window.shizuku.exec(cmd, { stdin:'', redirect:false });
        return { errno: 0, stdout: (r || '').toString(), stderr: '' };
      } catch (e) { /* fall through */ }
    }
    try {
      if (window.ksu)    return await window.ksu.exec(cmd);
      if (window.apatch) return await window.apatch.exec(cmd);
    } catch (e) {
      return { errno: -1, stdout: '', stderr: (e && e.message) || 'exec failed' };
    }
    return { errno: -1, stdout: '', stderr: 'No exec API' };
  }

  // ---------- toast ----------
  function toast(msg, kind) {
    const el = document.createElement('div');
    el.className = 'toast ' + (kind || 'success');
    el.textContent = msg;
    document.getElementById('toasts').appendChild(el);
    setTimeout(() => el.remove(), 3000);
  }

  // ---------- config helpers ----------
  async function readConfig(key, defaultValue) {
    if (readOnly) {
      try {
        const r = await fetch(MOD_PATH + '/.' + key);
        if (r.ok) { const t = await r.text(); return t.trim() || defaultValue || ''; }
      } catch (e) {}
      return defaultValue || '';
    }
    const r = await exec('cat "' + MOD_PATH + '/.' + key + '" 2>/dev/null');
    if (r.errno === 0 && r.stdout) return r.stdout.trim();
    return defaultValue || '';
  }

  async function writeConfig(key, value) {
    const r = await exec(
      'echo ' + JSON.stringify(String(value)) + ' > "' + MOD_PATH + '/.' + key +
      '" && chmod 644 "' + MOD_PATH + '/.' + key + '"'
    );
    return r.errno === 0;
  }

  // ---------- allowlist ----------
  async function loadAllowlist() {
    let raw = '';
    if (readOnly) {
      try {
        const r = await fetch(ALLOWLIST_PATH);
        if (r.ok) raw = await r.text();
      } catch (e) {}
    } else {
      const r = await exec('cat "' + ALLOWLIST_PATH + '" 2>/dev/null');
      if (r.errno === 0) raw = r.stdout;
    }
    if (!raw) raw = '{"allow":[],"deny_root_manager":true,"version":1}';
    let allow = [];
    try {
      const j = JSON.parse(raw);
      if (Array.isArray(j.allow)) allow = j.allow.slice();
    } catch (e) {}
    return { allow: allow, raw: raw };
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"]/g, c => (
      { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]
    ));
  }

  function renderAllowlist(allowlist) {
    const ul = document.getElementById('allowList');
    const cnt = document.getElementById('allowCount');
    ul.innerHTML = '';
    cnt.textContent = allowlist.allow.length;
    const sorted = allowlist.allow.slice().sort();
    sorted.forEach(pkg => {
      const isMgr = MANAGER_PKGS.has(pkg);
      const tag = isMgr
        ? '<span class="app-tag mgr">Root manager</span>'
        : '<span class="app-tag allow">Allowed</span>';
      const row = document.createElement('div');
      row.className = 'app-item';
      row.innerHTML =
        '<div class="app-pkg">' +
          '<div class="app-pkg-name">' + escapeHtml(pkg.split('.').pop()) + '</div>' +
          '<div class="app-pkg-meta">' + escapeHtml(pkg) + '</div>' +
        '</div>' + tag +
        '<button class="btn secondary" data-rm="' + escapeHtml(pkg) + '" style="width:auto;padding:6px 10px">Remove</button>';
      ul.appendChild(row);
    });
    ul.querySelectorAll('[data-rm]').forEach(b => {
      b.addEventListener('click', () => removeFromAllowlist(b.dataset.rm));
    });
  }

  async function saveAllowlist(list) {
    const deny = document.getElementById('t_hide_mgr')?.checked !== false;
    const payload = JSON.stringify(
      { allow: list, deny_root_manager: deny, version: 1 },
      null, 2
    );
    if (readOnly) { toast('Read-only', 'warn'); return false; }
    const r = await exec(
      'cat > ' + ALLOWLIST_PATH + " <<'__JSON__'\n" + payload + '\n__JSON__\n' +
      'chmod 644 ' + ALLOWLIST_PATH
    );
    return r.errno === 0;
  }

  async function addToAllowlist(raw) {
    const pkg = (raw || '').trim();
    if (!pkg || !/^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+$/.test(pkg)) {
      toast('Invalid package id', 'warn'); return;
    }
    const cur = await loadAllowlist();
    if (cur.allow.indexOf(pkg) >= 0) { toast('Already on allowlist', 'warn'); return; }
    cur.allow.push(pkg);
    if (await saveAllowlist(cur.allow)) {
      renderAllowlist(cur);
      toast('Allowed ' + pkg, 'success');
    } else {
      toast('Failed to save', 'error');
    }
  }

  async function removeFromAllowlist(pkg) {
    const cur = await loadAllowlist();
    cur.allow = cur.allow.filter(p => p !== pkg);
    if (await saveAllowlist(cur.allow)) {
      renderAllowlist(cur);
      toast('Removed ' + pkg, 'success');
    } else {
      toast('Failed to save', 'error');
    }
  }

  async function clearAllowlist() {
    if (!confirm('Clear the allowlist? Root managers will stay auto-allowed (unless "Hide manager app" is on).')) return;
    const cur = await loadAllowlist();
    cur.allow = cur.allow.filter(p => MANAGER_PKGS.has(p));
    if (await saveAllowlist(cur.allow)) {
      renderAllowlist(cur);
      toast('Allowlist cleared', 'success');
    }
  }

  // ---------- installed apps ----------
  async function refreshInstalled() {
    if (readOnly) { toast('Browser mode — install list unavailable', 'warn'); return; }
    const r = await exec('pm list packages 2>/dev/null | sed "s/^package://"');
    if (r.errno !== 0) { toast('pm failed', 'error'); return; }
    const installed = r.stdout.split('\n').filter(Boolean);
    document.getElementById('installedCount').textContent = installed.length;
    const cur = await loadAllowlist();
    const allowSet = new Set(cur.allow);
    const ul = document.getElementById('installedList');
    ul.innerHTML = '';
    installed.sort().forEach(pkg => {
      const isAllowed = allowSet.has(pkg);
      const isMgr = MANAGER_PKGS.has(pkg);
      let tag;
      if (isMgr)          tag = '<span class="app-tag mgr">Manager</span>';
      else if (isAllowed) tag = '<span class="app-tag allow">allow</span>';
      else                tag = '<span class="app-tag deny">deny</span>';
      const row = document.createElement('div');
      row.className = 'app-item';
      row.innerHTML =
        '<div class="app-pkg">' +
          '<div class="app-pkg-name">' + escapeHtml(pkg.split('.').pop()) + '</div>' +
          '<div class="app-pkg-meta">' + escapeHtml(pkg) + '</div>' +
        '</div>' + tag +
        '<button class="btn secondary" data-toggle="' + escapeHtml(pkg) + '" style="width:auto;padding:6px 10px">' +
          (isAllowed ? 'Remove' : 'Add') +
        '</button>';
      ul.appendChild(row);
    });
    ul.querySelectorAll('[data-toggle]').forEach(b => {
      b.addEventListener('click', () => {
        const pkg = b.dataset.toggle;
        if (allowSet.has(pkg)) removeFromAllowlist(pkg);
        else addToAllowlist(pkg);
        setTimeout(refreshInstalled, 400);
      });
    });
  }

  // ---------- logs ----------
  async function loadLogs() {
    const v = document.getElementById('logViewer');
    if (readOnly) {
      v.textContent = 'Open the WebUI from a root manager for live logs.';
      return;
    }
    const r = await exec('tail -80 ' + LOG_PATH + ' 2>/dev/null || echo "no logs yet"');
    v.innerHTML = (r.stdout || 'No logs')
      .split('\n')
      .map(line => {
        let cls = '';
        if (/\[ERROR\]/.test(line))         cls = 'error';
        else if (/\[WARN\]/.test(line))    cls = 'warn';
        else if (/\[INFO\]/.test(line))    cls = 'info';
        return '<div class="' + cls + '">' + escapeHtml(line) + '</div>';
      })
      .join('');
    v.scrollTop = v.scrollHeight;
  }

  async function clearLogs() {
    if (readOnly) { toast('Read-only', 'warn'); return; }
    const r = await exec('echo > ' + LOG_PATH);
    if (r.errno === 0) { toast('Logs cleared', 'success'); loadLogs(); }
  }

  async function applyHide() {
    if (readOnly) { toast('Read-only', 'warn'); return; }
    toast('Re-applying...', 'success');
    const r = await exec('sh "' + MOD_PATH + '/hide_root.sh"');
    toast(r.errno === 0 ? 'Done' : 'Failed', r.errno === 0 ? 'success' : 'error');
    loadLogs();
  }

  // ---------- toggles ----------
  async function loadToggles() {
    for (const id of ['t_spoof', 't_keystore', 't_zygisk', 't_hide_mgr']) {
      if (readOnly) continue;
      const v = await readConfig('flag_' + id, '1');
      document.getElementById(id).checked = (v === '1');
    }
    const sd = await readConfig('post_fs_data_done', '0');
    document.getElementById('statusBadge').textContent = (sd === '1') ? 'ready' : 'rebooting';
  }

  async function saveToggles() {
    if (readOnly) { toast('Read-only', 'warn'); return; }
    for (const id of ['t_spoof','t_keystore','t_zygisk','t_hide_mgr']) {
      const v = document.getElementById(id).checked ? '1' : '0';
      await writeConfig('flag_' + id, v);
    }
    const cur = await loadAllowlist();
    await saveAllowlist(cur.allow);
    toast('Saved', 'success');
  }

  function updateRootBadge() {
    const el = document.getElementById('rootBadge');
    if (readOnly) {
      el.textContent = 'browser (read-only)';
      document.getElementById('roBanner').classList.add('show');
    } else {
      exec('echo $KSU $APATCH $MAGISK_VER').then(r => {
        const o = (r.stdout || '');
        el.textContent = /true/.test(o)     ? 'KernelSU' :
                         /APATCH/.test(o)   ? 'APatch' :
                         /MAGISK/.test(o)   ? 'Magisk'  : 'unknown';
      });
    }
  }

  // ---------- wire-up ----------
  function wire() {
    document.getElementById('btnAdd').addEventListener('click', () =>
      addToAllowlist(document.getElementById('pkgInput').value)
    );
    document.getElementById('pkgInput').addEventListener('keydown', e => {
      if (e.key === 'Enter') document.getElementById('btnAdd').click();
    });
    document.getElementById('btnSaveAllowlist').addEventListener('click', async () => {
      renderAllowlist(await loadAllowlist());
      toast('Reloaded', 'success');
    });
    document.getElementById('btnPurgeAllowlist').addEventListener('click', clearAllowlist);
    document.getElementById('btnRefreshInstalled').addEventListener('click', refreshInstalled);
    document.getElementById('btnRefreshLogs').addEventListener('click', loadLogs);
    document.getElementById('btnClearLogs').addEventListener('click', clearLogs);
    document.getElementById('btnApplyHide').addEventListener('click', applyHide);
    document.getElementById('btnSaveFlags').addEventListener('click', saveToggles);
    document.getElementById('btnReloadPage').addEventListener('click', () => location.reload());

    ['t_spoof', 't_keystore', 't_zygisk', 't_hide_mgr'].forEach(id => {
      document.getElementById(id).addEventListener('change', () => {
        saveToggles();
      });
    });
  }

  async function boot() {
    updateRootBadge();
    await loadToggles();
    renderAllowlist(await loadAllowlist());
    await loadLogs();
    wire();
    setInterval(async () => {
      renderAllowlist(await loadAllowlist());
      if (!readOnly) loadLogs();
    }, 15000);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
