/**
 * popup.js — LingTeX Tools desktop app (Tauri)
 *
 * Based on the browser extension popup.js, adapted for the Tauri desktop app:
 *   - chrome.storage.local is shimmed with localStorage (no extension runtime needed)
 *   - Clipboard writes go through Tauri's write_clipboard command (arboard, reliable)
 *   - The Rust backend emits "clipboard-changed" events from its background monitor;
 *     when auto re-copy is ON, incoming clipboard text is auto-converted and written back
 *   - Keyboard shortcuts fire Tauri global shortcuts OS-wide (registered via Rust)
 *   - No service worker, no online/offline, no browser extension APIs
 */

'use strict';

// ── chrome.storage shim ───────────────────────────────────────────────────────
// Maps chrome.storage.local to localStorage so popup.js logic is unchanged.

var ALL_KEYS = [
    'lingtex-profiles',
    'lingtex-active-profile',
    'lingtex-auto-convert',
    'lingtex-flex-config'
];

var chrome = {
    storage: {
        local: {
            get: function (keys, cb) {
                var result = {};
                var keyList = keys == null ? ALL_KEYS
                    : Array.isArray(keys) ? keys
                    : typeof keys === 'string' ? [keys]
                    : Object.keys(keys);
                keyList.forEach(function (k) {
                    var raw = localStorage.getItem(k);
                    if (raw !== null) {
                        try { result[k] = JSON.parse(raw); } catch (e) { result[k] = raw; }
                    }
                });
                cb(result);
            },
            set: function (obj, cb) {
                Object.keys(obj).forEach(function (k) {
                    localStorage.setItem(k, JSON.stringify(obj[k]));
                });
                if (cb) cb();
            }
        }
    }
};

// ── Default profiles ──────────────────────────────────────────────────────────

var DEFAULT_PROFILES = [
    { id: 'tsv-pa',  name: 'Phonology Assistant', isDefault: true,
      tmpl: '\\exampleentry{}{$WORD}{$GLOSS}{\\phonrec{$ID}}', skip: 'referenced' },
    { id: 'tsv-dek', name: 'Dekereke', isDefault: true,
      tmpl: '\\exampleentry{}{$COL2}{$COL3}{\\phonrec{$COL1}}', skip: 'referenced' }
];

var profiles    = DEFAULT_PROFILES.map(cloneProfile);
var activePanel = 'flex';

// ── Shortcut helper ───────────────────────────────────────────────────────────

function shortcutFromEvent(e) {
    var key = e.key;
    if (key === 'Control' || key === 'Alt' || key === 'Shift' || key === 'Meta') return null;
    var isMac = /Mac|iPhone|iPad/i.test(navigator.platform);
    var parts = [];
    if (isMac ? e.metaKey : e.ctrlKey) parts.push('Ctrl');
    if (e.altKey)   parts.push('Alt');
    if (e.shiftKey) parts.push('Shift');
    parts.push(key.length === 1 ? key.toUpperCase() : key);
    return parts.join('+');
}

function applyShortcutValue(input, value) {
    input.value = value || '';
    input.classList.toggle('has-value', !!value);
}

// ── Storage helpers ───────────────────────────────────────────────────────────

function storageGet(keys, cb) {
    chrome.storage.local.get(keys, cb);
}

function storageSet(obj) {
    chrome.storage.local.set(obj);
}

// ── Initialise ────────────────────────────────────────────────────────────────

document.addEventListener('DOMContentLoaded', function () {
    storageGet(null, function (data) {

        // Profiles
        if (data['lingtex-profiles'] && data['lingtex-profiles'].length) {
            profiles = data['lingtex-profiles'];
        }

        // Active panel
        if (data['lingtex-active-profile']) {
            activePanel = data['lingtex-active-profile'];
        }
        storageSet({ 'lingtex-active-profile': activePanel });

        // Auto re-copy toggle
        var autoCb = document.getElementById('auto-convert-cb');
        if (autoCb) autoCb.checked = !!data['lingtex-auto-convert'];

        // FLEx config
        var fc = data['lingtex-flex-config'] || {};
        if (fc.glCmd        !== undefined) document.getElementById('flex-gl').value       = fc.glCmd;
        if (fc.wrapExe      !== undefined) document.getElementById('flex-wrap-exe').value = fc.wrapExe ? 'yes' : 'no';
        if (fc.txtrefCmd    !== undefined) document.getElementById('flex-txtref').value   = fc.txtrefCmd;
        if (fc.txtrefPrefix !== undefined) document.getElementById('flex-txtpfx').value   = fc.txtrefPrefix;
        applyShortcutValue(document.getElementById('flex-shortcut'), fc.shortcut);

        renderAll();

        if (activePanel === 'flex' || !document.getElementById('panel-' + activePanel)) {
            activePanel = 'flex';
        } else {
            activatePanel(activePanel);
        }

        attachStaticListeners();
        initTauri();
    });
});

// ── Static event listeners ────────────────────────────────────────────────────

function attachStaticListeners() {

    document.getElementById('auto-convert-cb').addEventListener('change', function (e) {
        storageSet({ 'lingtex-auto-convert': e.target.checked });
    });

    document.getElementById('tab-flex').addEventListener('click', function () {
        switchTab('flex');
    });

    document.getElementById('tab-add-btn').addEventListener('click', addProfile);

    ['flex-gl', 'flex-wrap-exe', 'flex-txtref', 'flex-txtpfx'].forEach(function (id) {
        var el = document.getElementById(id);
        if (el) el.addEventListener('input',  function () { saveFLExConfig(); convertFlex(); });
        if (el) el.addEventListener('change', function () { saveFLExConfig(); convertFlex(); });
    });

    var flexScInput = document.getElementById('flex-shortcut');
    flexScInput.addEventListener('keydown', function (e) {
        e.preventDefault();
        e.stopImmediatePropagation();
        var sc = shortcutFromEvent(e);
        if (!sc) return;
        applyShortcutValue(flexScInput, sc);
        saveFLExConfig();
        tauriRegisterShortcut('flex', sc);
        flexScInput.blur();
    });
    document.getElementById('flex-shortcut-clear').addEventListener('click', function () {
        applyShortcutValue(flexScInput, '');
        saveFLExConfig();
        tauriRegisterShortcut('flex', '');
    });

    document.getElementById('flex-in').addEventListener('input', convertFlex);

    document.getElementById('flex-clear-btn').addEventListener('click', function () {
        clearTool('flex');
    });

    document.getElementById('flex-copy-btn').addEventListener('click', function () {
        copyOutput('flex-out', this);
    });

    var main = document.getElementById('main-content');

    main.addEventListener('keydown', function (e) {
        if (e.target.dataset.action !== 'shortcut') return;
        e.preventDefault();
        e.stopImmediatePropagation();
        var sc = shortcutFromEvent(e);
        if (!sc) return;
        applyShortcutValue(e.target, sc);
        var pid = pidOf(e.target);
        if (pid) { var p = getProfile(pid); if (p) { p.shortcut = sc; saveProfiles(); tauriRegisterShortcut(pid, sc); } }
        e.target.blur();
    });

    main.addEventListener('input', function (e) {
        var pid = pidOf(e.target);
        if (!pid) return;
        var action = e.target.dataset.action;
        if (action === 'tmpl' || action === 'skip') updateAndConvert(pid);
        if (action === 'test-in') convertTSV(pid);
        if (action === 'profile-name') renameProfile(pid, e.target.value);
    });

    main.addEventListener('change', function (e) {
        var pid = pidOf(e.target);
        if (!pid) return;
        if (e.target.dataset.action === 'skip') updateAndConvert(pid);
    });

    main.addEventListener('click', function (e) {
        var btn = e.target.closest('[data-action]');
        if (!btn) return;
        var pid    = pidOf(btn);
        var action = btn.dataset.action;
        if (action === 'delete-profile') deleteProfile(pid);
        if (action === 'clear-test')     clearTool(pid);
        if (action === 'copy-out' && pid) copyOutput(pid + '-out', btn);
        if (action === 'clear-shortcut' && pid) {
            var scInput = btn.closest('.shortcut-row').querySelector('.shortcut-input');
            if (scInput) applyShortcutValue(scInput, '');
            var p = getProfile(pid); if (p) { p.shortcut = ''; saveProfiles(); tauriRegisterShortcut(pid, ''); }
        }
    });
}

function pidOf(el) {
    var panel = el.closest('.tsv-panel');
    return panel ? panel.dataset.profileId : null;
}

// ── FLEx config persistence ───────────────────────────────────────────────────

function saveFLExConfig() {
    storageSet({
        'lingtex-flex-config': {
            glCmd:        document.getElementById('flex-gl').value.trim(),
            wrapExe:      document.getElementById('flex-wrap-exe').value === 'yes',
            txtrefCmd:    document.getElementById('flex-txtref').value.trim(),
            txtrefPrefix: document.getElementById('flex-txtpfx').value,
            shortcut:     document.getElementById('flex-shortcut').value
        }
    });
    syncConfigWithTauri();
}

// ── Tab switching ─────────────────────────────────────────────────────────────

function switchTab(panelId) {
    activePanel = panelId;
    storageSet({ 'lingtex-active-profile': panelId });
    document.querySelectorAll('.tab').forEach(function (b) {
        b.classList.toggle('active', b.dataset.panel === panelId || b.dataset.profile === panelId);
    });
    document.querySelectorAll('.panel').forEach(function (p) {
        p.classList.toggle('active', p.id === 'panel-' + panelId);
    });
}

function activatePanel(panelId) {
    switchTab(panelId);
}

// ── Profile helpers ───────────────────────────────────────────────────────────

function cloneProfile(p) {
    return { id: p.id, name: p.name, tmpl: p.tmpl, skip: p.skip, isDefault: !!p.isDefault };
}

function getProfile(id) {
    return profiles.filter(function (p) { return p.id === id; })[0] || null;
}

function saveProfiles() {
    storageSet({ 'lingtex-profiles': profiles });
    syncConfigWithTauri();
}

function escHtml(s) {
    return String(s)
        .replace(/&/g, '&amp;').replace(/</g, '&lt;')
        .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

// ── Render ────────────────────────────────────────────────────────────────────

function renderAll() {
    renderTSVTabs();
    renderTSVPanels();
}

function renderTSVTabs() {
    var nav    = document.getElementById('tab-nav');
    var addBtn = document.getElementById('tab-add-btn');
    nav.querySelectorAll('[data-profile]').forEach(function (el) { el.remove(); });

    profiles.forEach(function (p) {
        var btn = document.createElement('button');
        btn.className = 'tab' + (activePanel === p.id ? ' active' : '');
        btn.setAttribute('role', 'tab');
        btn.dataset.profile = p.id;
        btn.textContent = p.name;
        btn.addEventListener('click', function () { switchTab(p.id); });
        nav.insertBefore(btn, addBtn);
    });
}

function renderTSVPanels() {
    var main = document.getElementById('main-content');
    main.querySelectorAll('.tsv-panel').forEach(function (el) { el.remove(); });

    profiles.forEach(function (p) {
        var sec = document.createElement('section');
        sec.id                = 'panel-' + p.id;
        sec.className         = 'panel tsv-panel' + (activePanel === p.id ? ' active' : '');
        sec.dataset.profileId = p.id;
        sec.setAttribute('role', 'tabpanel');
        sec.innerHTML         = buildPanelHTML(p);
        main.appendChild(sec);
    });
}

function buildPanelHTML(p) {
    var id   = escHtml(p.id);
    var tmpl = escHtml(p.tmpl || '');

    var skipOpts   = ['referenced', 'col1', 'none'];
    var skipLabels = {
        referenced: 'any column used in template is empty',
        col1:       'column 1 is empty',
        none:       'never skip (include all rows)'
    };
    var skipHtml = skipOpts.map(function (v) {
        return '<option value="' + v + '"' + (p.skip === v ? ' selected' : '') + '>' +
               skipLabels[v] + '</option>';
    }).join('');

    return '' +
        '<details class="cfg">' +
        '  <summary>Configuration</summary>' +
        '  <div class="cfg-body">' +

        (!p.isDefault
            ? '    <div class="cfg-row">' +
              '      <label>Tab name</label>' +
              '      <input class="profile-name-input" type="text" value="' + escHtml(p.name) + '"' +
              '        data-action="profile-name">' +
              '    </div>'
            : '') +

        '    <div class="cfg-full">' +
        '      <label>Row template</label>' +
        '      <textarea data-action="tmpl" spellcheck="false">' + tmpl + '</textarea>' +
        '      <div class="cfg-hint">' +
        '        Named: <code>$WORD</code>=col 2 · <code>$GLOSS</code>=col 3 · <code>$ID</code>=col 6<br>' +
        '        Positional: <code>$COL<em>n</em></code> = any column by number (1-based).' +
        '      </div>' +
        '    </div>' +

        '    <div class="cfg-row">' +
        '      <label>Skip rows where</label>' +
        '      <select data-action="skip">' + skipHtml + '</select>' +
        '    </div>' +

        '    <div class="cfg-row">' +
        '      <label>Keyboard shortcut</label>' +
        '      <div class="shortcut-row">' +
        '        <input type="text" class="shortcut-input' + (p.shortcut ? ' has-value' : '') + '"' +
        '          data-action="shortcut" placeholder="Click, then press keys…" readonly' +
        '          value="' + escHtml(p.shortcut || '') + '">' +
        '        <button class="btn btn-ghost" data-action="clear-shortcut" title="Clear shortcut">✕</button>' +
        '      </div>' +
        '    </div>' +
        '    <div class="cfg-hint">' +
        '      Press this shortcut anywhere to instantly read the clipboard, convert' +
        '      using this profile, and re-copy the result.<br>' +
        '      <strong>Note:</strong> keyboard shortcuts and <em>Auto re-copy</em> cannot' +
        '      be used at the same time — turn off Auto re-copy when using shortcuts.' +
        '    </div>' +

        (!p.isDefault
            ? '    <div class="cfg-row">' +
              '      <label></label>' +
              '      <button class="btn btn-secondary btn-danger" data-action="delete-profile">' +
              '        Delete this tab' +
              '      </button>' +
              '    </div>'
            : '') +

        '  </div>' +
        '</details>' +

        '<div class="io-row">' +
        '  <div class="io-label">' +
        '    <span>Test input</span>' +
        '    <div class="io-actions">' +
        '      <button class="btn btn-ghost" data-action="clear-test">Clear</button>' +
        '    </div>' +
        '  </div>' +
        '  <textarea class="tall" data-action="test-in" spellcheck="false"' +
        '    placeholder="Paste tab-separated rows here to test…"></textarea>' +
        '</div>' +

        '<div class="io-row">' +
        '  <div class="io-label">' +
        '    <span>Output — LaTeX</span>' +
        '    <div class="io-actions">' +
        '      <button class="btn btn-secondary" data-action="copy-out">Copy Result</button>' +
        '    </div>' +
        '  </div>' +
        '  <textarea id="' + id + '-out" class="out" readonly spellcheck="false"' +
        '    placeholder="LaTeX output will appear here…"></textarea>' +
        '  <div id="' + id + '-status" class="status"></div>' +
        '  <div id="' + id + '-errbox" style="display:none" class="errbox"></div>' +
        '</div>';
}

// ── Profile actions ───────────────────────────────────────────────────────────

function addProfile() {
    var newP = {
        id:   'tsv-' + Date.now(),
        name: 'New Tab',
        tmpl: '$COL1',
        skip: 'referenced'
    };
    profiles.push(newP);
    saveProfiles();
    renderAll();
    switchTab(newP.id);
    setTimeout(function () {
        var nameIn = document.querySelector('#panel-' + newP.id + ' [data-action="profile-name"]');
        if (nameIn) { nameIn.select(); nameIn.focus(); }
    }, 30);
}

function deleteProfile(id) {
    var p = getProfile(id);
    if (p && p.isDefault) {
        alert('The Phonology Assistant and Dekereke tabs are always present and cannot be deleted.');
        return;
    }
    if (p && p.shortcut) tauriRegisterShortcut(id, ''); // unregister OS shortcut
    profiles = profiles.filter(function (q) { return q.id !== id; });
    saveProfiles();
    if (activePanel === id) activePanel = profiles[0] ? profiles[0].id : 'flex';
    renderAll();
    switchTab(activePanel);
}

function renameProfile(id, name) {
    var p = getProfile(id);
    if (!p) return;
    p.name = name.trim() || 'Untitled';
    saveProfiles();
    var btn = document.querySelector('[data-profile="' + id + '"]');
    if (btn) btn.textContent = p.name;
}

function updateAndConvert(id) {
    var p = getProfile(id);
    if (!p) return;
    var panel = document.getElementById('panel-' + id);
    if (!panel) return;
    var tmplEl = panel.querySelector('[data-action="tmpl"]');
    var skipEl = panel.querySelector('[data-action="skip"]');
    if (tmplEl) p.tmpl = tmplEl.value;
    if (skipEl) p.skip = skipEl.value;
    saveProfiles();
    convertTSV(id);
}

// ── Converters ────────────────────────────────────────────────────────────────

function convertFlex() {
    var raw    = document.getElementById('flex-in').value;
    var outEl  = document.getElementById('flex-out');
    var statEl = document.getElementById('flex-status');

    if (!raw.trim()) {
        outEl.value = '';
        statEl.textContent = '';
        statEl.className = 'status';
        return;
    }

    try {
        var blocks = LingTeXCore.parseFLExBlocks(raw);
        if (!blocks.length) {
            outEl.value = '';
            setStatus('flex', 'No recognisable interlinear tiers found.', 'err');
            return;
        }
        var latex = LingTeXCore.renderFLExAuto(blocks, {
            glCmd:        document.getElementById('flex-gl').value.trim(),
            wrapExe:      document.getElementById('flex-wrap-exe').value === 'yes',
            txtrefCmd:    document.getElementById('flex-txtref').value.trim(),
            txtrefPrefix: document.getElementById('flex-txtpfx').value
        });
        outEl.value = latex;
        var words = (blocks[0].lineArrays[0] || []).length - 1;
        var msg = blocks.length > 1
            ? 'Converted ' + blocks.length + ' blocks'
            : 'Converted ' + words + ' word(s)';
        setStatus('flex', msg, 'ok');
    } catch (e) {
        outEl.value = '';
        setStatus('flex', 'Error: ' + e.message, 'err');
    }
}

function convertTSV(id) {
    var panel  = document.getElementById('panel-' + id);
    if (!panel) return;

    var inEl   = panel.querySelector('[data-action="test-in"]');
    var outEl  = document.getElementById(id + '-out');
    var errEl  = document.getElementById(id + '-errbox');
    var tmplEl = panel.querySelector('[data-action="tmpl"]');
    var skipEl = panel.querySelector('[data-action="skip"]');
    if (!inEl || !outEl) return;

    var raw  = inEl.value;
    var tmpl = tmplEl ? tmplEl.value : '';
    var skip = skipEl ? skipEl.value : 'referenced';

    if (!raw.trim()) {
        outEl.value = '';
        if (errEl) errEl.style.display = 'none';
        setStatus(id, '', '');
        return;
    }

    var usedCols = [];
    if (skip === 'referenced') {
        if (/\$WORD\b/.test(tmpl))  addUniq(usedCols, 2);
        if (/\$GLOSS\b/.test(tmpl)) addUniq(usedCols, 3);
        if (/\$ID\b/.test(tmpl))    addUniq(usedCols, 6);
        var m, re = /\$COL(\d+)/g;
        while ((m = re.exec(tmpl)) !== null) addUniq(usedCols, parseInt(m[1], 10));
    }

    var lines   = raw.replace(/\r\n?/g, '\n').split('\n').filter(function (l) { return l.trim(); });
    var results = [], errors = [];

    lines.forEach(function (line, i) {
        var fields = LingTeXCore.parseTSVRow(line);
        var rowNum = i + 1;

        if (skip === 'referenced' && usedCols.length) {
            var empty = usedCols.filter(function (n) { return !fields[n - 1]; });
            if (empty.length) {
                errors.push('Row ' + rowNum + ': skipped (col ' + empty.join(', ') + ' empty)');
                return;
            }
        }
        if (skip === 'col1' && !fields[0]) {
            errors.push('Row ' + rowNum + ': skipped (col 1 empty)');
            return;
        }

        results.push(LingTeXCore.applyRowTemplate(tmpl, fields));
    });

    outEl.value = results.join('\n');

    if (results.length === 0) {
        setStatus(id, 'No output — ' + errors.length + ' row(s) skipped.', 'err');
    } else {
        setStatus(id, 'Converted ' + results.length + ' row(s)' +
            (errors.length ? ' · ' + errors.length + ' skipped' : ''), errors.length ? '' : 'ok');
    }

    if (errEl) {
        errEl.textContent   = errors.join('\n');
        errEl.style.display = errors.length ? 'block' : 'none';
    }
}

function addUniq(arr, v) { if (arr.indexOf(v) === -1) arr.push(v); }

// ── Utility ───────────────────────────────────────────────────────────────────

function setStatus(id, msg, cls) {
    var el = document.getElementById(id + '-status');
    if (!el) return;
    el.textContent = msg;
    el.className   = 'status' + (cls ? ' ' + cls : '');
}

function clearTool(id) {
    var panel = id === 'flex'
        ? document.getElementById('panel-flex')
        : document.getElementById('panel-' + id);
    if (!panel) return;

    var inEl  = id === 'flex'
        ? document.getElementById('flex-in')
        : panel.querySelector('[data-action="test-in"]');
    var outEl = id === 'flex'
        ? document.getElementById('flex-out')
        : document.getElementById(id + '-out');
    var errEl = document.getElementById(id + '-errbox');

    if (inEl)  inEl.value  = '';
    if (outEl) outEl.value = '';
    if (errEl) { errEl.style.display = 'none'; errEl.textContent = ''; }
    setStatus(id, '', '');
}

function copyOutput(outId, btn) {
    var el = document.getElementById(outId);
    if (!el || !el.value.trim()) return;
    var text = el.value;
    var orig = btn.textContent;

    if (window.__TAURI__) {
        window.__TAURI__.core.invoke('write_clipboard', { text: text })
            .then(function () {
                btn.textContent = 'Copied!';
                setTimeout(function () { btn.textContent = orig; }, 1500);
            })
            .catch(function () {
                alert('Could not copy to clipboard.');
            });
    } else {
        navigator.clipboard.writeText(text)
            .then(function () {
                btn.textContent = 'Copied!';
                setTimeout(function () { btn.textContent = orig; }, 1500);
            })
            .catch(function () {
                alert('Could not copy. Please select the output text and copy manually.');
            });
    }
}

// ── Convert for profile (used by auto re-copy) ────────────────────────────────
// Converts raw text with the given profile without touching the test UI.

function convertForProfile(profileId, text) {
    if (!text || !text.trim()) return null;

    if (profileId === 'flex') {
        try {
            var blocks = LingTeXCore.parseFLExBlocks(text);
            if (!blocks.length) return null;
            return LingTeXCore.renderFLExAuto(blocks, {
                glCmd:        document.getElementById('flex-gl').value.trim(),
                wrapExe:      document.getElementById('flex-wrap-exe').value === 'yes',
                txtrefCmd:    document.getElementById('flex-txtref').value.trim(),
                txtrefPrefix: document.getElementById('flex-txtpfx').value
            });
        } catch (e) { return null; }
    }

    var p = getProfile(profileId);
    if (!p) return null;

    var tmpl = p.tmpl;
    var skip = p.skip;

    var usedCols = [];
    if (skip === 'referenced') {
        if (/\$WORD\b/.test(tmpl))  addUniq(usedCols, 2);
        if (/\$GLOSS\b/.test(tmpl)) addUniq(usedCols, 3);
        if (/\$ID\b/.test(tmpl))    addUniq(usedCols, 6);
        var m, re = /\$COL(\d+)/g;
        while ((m = re.exec(tmpl)) !== null) addUniq(usedCols, parseInt(m[1], 10));
    }

    var lines   = text.replace(/\r\n?/g, '\n').split('\n').filter(function (l) { return l.trim(); });
    var results = [];

    lines.forEach(function (line) {
        var fields = LingTeXCore.parseTSVRow(line);
        if (skip === 'referenced' && usedCols.length) {
            var empty = usedCols.filter(function (n) { return !fields[n - 1]; });
            if (empty.length) return;
        }
        if (skip === 'col1' && !fields[0]) return;
        results.push(LingTeXCore.applyRowTemplate(tmpl, fields));
    });

    return results.length ? results.join('\n') : null;
}

// ── Tauri integration ─────────────────────────────────────────────────────────

var lastAutoClip = null;

// Register (or unregister) a global OS shortcut for one profile.
// shortcut = '' → unregisters any existing shortcut for that profile.
// Safe to call when not running in Tauri (no-ops silently).
function tauriRegisterShortcut(profileId, shortcut) {
    if (!window.__TAURI__) return;
    window.__TAURI__.core.invoke('register_profile_shortcut', {
        profileId:   profileId,
        shortcutStr: shortcut || ''
    }).catch(function (e) {
        console.warn('[LingTeX] shortcut registration failed (' + profileId + '):', e);
    });
}

// Push the current conversion config (FLEx opts + TSV profile templates) to
// the Rust backend so that global shortcut handlers can convert clipboard text
// without the webview needing to be active or focused.
// Called on startup and whenever settings change.
function syncConfigWithTauri() {
    if (!window.__TAURI__) return;
    var flexOpts = {
        glCmd:        document.getElementById('flex-gl').value.trim(),
        wrapExe:      document.getElementById('flex-wrap-exe').value === 'yes',
        txtrefCmd:    document.getElementById('flex-txtref').value.trim(),
        txtrefPrefix: document.getElementById('flex-txtpfx').value
    };
    var tsvProfiles = profiles.map(function (p) {
        return { id: p.id, tmpl: p.tmpl || '', skip: p.skip || 'referenced' };
    });
    window.__TAURI__.core.invoke('sync_config', {
        flexOpts:    flexOpts,
        tsvProfiles: tsvProfiles
    }).catch(function (e) {
        console.warn('[LingTeX] sync_config failed:', e);
    });
}

// On startup, re-register every shortcut that was previously configured.
// Called once from initTauri() after profiles and flex config are loaded.
function syncShortcutsWithTauri() {
    var flexSc = document.getElementById('flex-shortcut');
    if (flexSc && flexSc.value) tauriRegisterShortcut('flex', flexSc.value);
    profiles.forEach(function (p) {
        if (p.shortcut) tauriRegisterShortcut(p.id, p.shortcut);
    });
}

function initTauri() {
    if (!window.__TAURI__) return;

    var tauri = window.__TAURI__;

    // Push current config and re-register all shortcuts with the OS
    syncConfigWithTauri();
    syncShortcutsWithTauri();

    // Listen for clipboard changes from the Rust background monitor.
    // When auto re-copy is ON, convert with active profile and write back.
    tauri.event.listen('clipboard-changed', function (e) {
        var text = e.payload;
        if (!text || !text.trim() || text === lastAutoClip) return;
        lastAutoClip = text;

        var autoCb = document.getElementById('auto-convert-cb');
        if (!autoCb || !autoCb.checked) return;

        var out = convertForProfile(activePanel, text);
        if (!out || !out.trim() || out === text) return;

        // Write the converted LaTeX back to the clipboard
        tauri.core.invoke('write_clipboard', { text: out })
            .then(function () {
                lastAutoClip = out; // prevent re-processing our own write
                setStatus(activePanel, 'Auto re-copied ✓', 'ok');
                setTimeout(function () {
                    var el = document.getElementById(activePanel + '-status');
                    if (el && el.textContent === 'Auto re-copied ✓') {
                        el.textContent = '';
                        el.className = 'status';
                    }
                }, 3000);
            })
            .catch(function () {});
    });

    // Listen for profile shortcut completions from the Rust global shortcut handler.
    // Rust has already converted the clipboard text and simulated a paste —
    // we just need to switch tabs and show a status message.
    // Payload: { profileId: string }
    tauri.event.listen('profile-shortcut', function (e) {
        var profileId = e.payload.profileId;
        // Switch to the relevant tab so the user sees the right panel
        switchTab(profileId);
        setStatus(profileId, 'Converted & pasted ✓', 'ok');
        setTimeout(function () {
            var el = document.getElementById(profileId + '-status');
            if (el && el.textContent === 'Converted & pasted ✓') {
                el.textContent = '';
                el.className = 'status';
            }
        }, 3000);
    });
}
