/**
 * popup.js — LingTeX Tools browser extension popup
 *
 * Adapted from the web app (docs/index.html) with these key differences:
 *   - chrome.storage.local replaces localStorage (async, shared with content script)
 *   - No inline event handlers (MV3 CSP); all binding done via event delegation
 *   - No service worker / offline logic
 *   - Includes the auto-convert toggle (controls content.js paste interception)
 *   - FLEx config changes are persisted to storage for the content script to use
 */

'use strict';

// ── Default profiles ──────────────────────────────────────────────────────────

var DEFAULT_PROFILES = [
    { id: 'tsv-pa',  name: 'Phonology Assistant', isDefault: true,
      tmpl: '\\exampleentry{}{$WORD}{$GLOSS}{\\phonrec{$ID}}', skip: 'referenced' },
    { id: 'tsv-dek', name: 'Dekereke', isDefault: true,
      tmpl: '\\exampleentry{}{$COL2}{$COL3}{\\phonrec{$COL1}}', skip: 'referenced' }
];

var profiles    = DEFAULT_PROFILES.map(cloneProfile);
var activePanel = 'flex';

// ── Storage helpers ───────────────────────────────────────────────────────────

function storageGet(keys, cb) {
    chrome.storage.local.get(keys, cb);
}

function storageSet(obj) {
    chrome.storage.local.set(obj);
}

// ── Initialise ────────────────────────────────────────────────────────────────

document.addEventListener('DOMContentLoaded', function () {
    // Load everything from storage, then build the UI
    storageGet(null, function (data) {

        // Profiles
        if (data['lingtex-profiles'] && data['lingtex-profiles'].length) {
            profiles = data['lingtex-profiles'];
        }

        // Active panel
        if (data['lingtex-active-profile']) {
            activePanel = data['lingtex-active-profile'];
        }

        // Auto-convert toggle
        var autoCb = document.getElementById('auto-convert-cb');
        if (autoCb) autoCb.checked = !!data['lingtex-auto-convert'];

        // FLEx config
        var fc = data['lingtex-flex-config'] || {};
        if (fc.glCmd        !== undefined) document.getElementById('flex-gl').value       = fc.glCmd;
        if (fc.wrapExe      !== undefined) document.getElementById('flex-wrap-exe').value = fc.wrapExe ? 'yes' : 'no';
        if (fc.txtrefCmd    !== undefined) document.getElementById('flex-txtref').value   = fc.txtrefCmd;
        if (fc.txtrefPrefix !== undefined) document.getElementById('flex-txtpfx').value   = fc.txtrefPrefix;

        renderAll();

        // Activate stored panel (or default to flex)
        if (activePanel === 'flex' || !document.getElementById('panel-' + activePanel)) {
            activePanel = 'flex';
        } else {
            activatePanel(activePanel);
        }

        attachStaticListeners();
    });
});

// ── Static event listeners (attached once after DOMContentLoaded) ─────────────

function attachStaticListeners() {

    // Auto-convert toggle → persist to storage (content.js reads this)
    document.getElementById('auto-convert-cb').addEventListener('change', function (e) {
        storageSet({ 'lingtex-auto-convert': e.target.checked });
    });

    // Tab: FLEx
    document.getElementById('tab-flex').addEventListener('click', function () {
        switchTab('flex');
    });

    // Add profile button
    document.getElementById('tab-add-btn').addEventListener('click', addProfile);

    // FLEx config inputs → persist + re-convert test area
    ['flex-gl', 'flex-wrap-exe', 'flex-txtref', 'flex-txtpfx'].forEach(function (id) {
        var el = document.getElementById(id);
        if (el) el.addEventListener('input', function () { saveFLExConfig(); convertFlex(); });
        if (el) el.addEventListener('change', function () { saveFLExConfig(); convertFlex(); });
    });

    // FLEx test input
    document.getElementById('flex-in').addEventListener('input', convertFlex);

    // FLEx clear button
    document.getElementById('flex-clear-btn').addEventListener('click', function () {
        clearTool('flex');
    });

    // FLEx copy button
    document.getElementById('flex-copy-btn').addEventListener('click', function () {
        copyOutput('flex-out', this);
    });

    // Event delegation for dynamically generated TSV panels
    var main = document.getElementById('main-content');

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
        var action = e.target.dataset.action;
        if (action === 'skip') updateAndConvert(pid);
    });

    main.addEventListener('click', function (e) {
        var btn = e.target.closest('[data-action]');
        if (!btn) return;
        var pid    = pidOf(btn);
        var action = btn.dataset.action;
        if (action === 'delete-profile') deleteProfile(pid);
        if (action === 'clear-test')     clearTool(pid);
        if (action === 'copy-out' && pid) copyOutput(pid + '-out', btn);
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
            txtrefPrefix: document.getElementById('flex-txtpfx').value
        }
    });
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
        sec.id                  = 'panel-' + p.id;
        sec.className           = 'panel tsv-panel' + (activePanel === p.id ? ' active' : '');
        sec.dataset.profileId   = p.id;
        sec.setAttribute('role', 'tabpanel');
        sec.innerHTML           = buildPanelHTML(p);
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

        // Tab name (user-created tabs only)
        (!p.isDefault
            ? '    <div class="cfg-row">' +
              '      <label>Tab name</label>' +
              '      <input class="profile-name-input" type="text" value="' + escHtml(p.name) + '"' +
              '        data-action="profile-name">' +
              '    </div>'
            : '') +

        // Row template (full width)
        '    <div class="cfg-full">' +
        '      <label>Row template</label>' +
        '      <textarea data-action="tmpl" spellcheck="false">' + tmpl + '</textarea>' +
        '      <div class="cfg-hint">' +
        '        Named: <code>$WORD</code>=col 2 · <code>$GLOSS</code>=col 3 · <code>$ID</code>=col 6<br>' +
        '        Positional: <code>$COL<em>n</em></code> = any column by number (1-based).' +
        '      </div>' +
        '    </div>' +

        // Skip logic
        '    <div class="cfg-row">' +
        '      <label>Skip rows where</label>' +
        '      <select data-action="skip">' + skipHtml + '</select>' +
        '    </div>' +

        // Delete button (user-created tabs only)
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

        // Test input
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

        // Test output
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
        var parsed = LingTeXCore.parseFLExBlock(raw);
        if (!parsed.lineTypes || parsed.lineTypes.length === 0) {
            outEl.value = '';
            setStatus('flex', 'No recognisable interlinear tiers found.', 'err');
            return;
        }
        var latex = LingTeXCore.renderFLEx(parsed, {
            glCmd:        document.getElementById('flex-gl').value.trim(),
            wrapExe:      document.getElementById('flex-wrap-exe').value === 'yes',
            txtrefCmd:    document.getElementById('flex-txtref').value.trim(),
            txtrefPrefix: document.getElementById('flex-txtpfx').value
        });
        outEl.value = latex;
        var words = (parsed.lineArrays[0] || []).length - 1;
        setStatus('flex', 'Converted ' + words + ' word(s)', 'ok');
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

    // Determine used columns for skip logic
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
    var outEl = document.getElementById(id + '-out') || document.getElementById('flex-out');
    var errEl = document.getElementById(id + '-errbox');

    if (inEl)  inEl.value  = '';
    if (outEl) outEl.value = '';
    if (errEl) { errEl.style.display = 'none'; errEl.textContent = ''; }
    setStatus(id, '', '');
}

async function copyOutput(outId, btn) {
    var el = document.getElementById(outId);
    if (!el || !el.value.trim()) return;
    try {
        await navigator.clipboard.writeText(el.value);
        var orig = btn.textContent;
        btn.textContent = 'Copied!';
        setTimeout(function () { btn.textContent = orig; }, 1500);
    } catch (e) {
        alert('Could not copy. Please select the output text and copy manually.');
    }
}
