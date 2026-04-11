/**
 * popup.js — LingTeX Tools browser extension popup
 *
 * Adapted from the web app (docs/index.html) with these key differences:
 *   - chrome.storage.local replaces localStorage (async, shared with content script)
 *   - No inline event handlers (MV3 CSP); all binding done via event delegation
 *   - No service worker / offline logic
 */

'use strict';

// ── Default profiles ──────────────────────────────────────────────────────────

var DEFAULT_PROFILES = [
    { id: 'tsv-pa',  name: 'Phonology Assistant', isDefault: true,
      tmpl: '\\exampleentry{}{$WORD}{$GLOSS}{\\phonrec{$ID}}', skip: 'referenced', trimLeading: true },
    { id: 'tsv-dek', name: 'Dekereke', isDefault: true,
      tmpl: '\\exampleentry{}{$COL2}{$COL3}{\\phonrec{$COL1}}', skip: 'referenced', trimLeading: false }
];

var profiles    = DEFAULT_PROFILES.map(cloneProfile);
var activeMode  = 'latex';
var activePanel = 'flex';

// ── Shortcut helpers ──────────────────────────────────────────────────────────

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

function getAllShortcutBindings() {
    var out = [];
    var fs = document.getElementById('flex-shortcut');
    if (fs && fs.value) out.push({ id: 'flex',     label: 'FLEx Interlinear', sc: fs.value });
    var fts = document.getElementById('flex-tsv-shortcut');
    if (fts && fts.value) out.push({ id: 'flex-tsv', label: 'FLEx → Table',  sc: fts.value });
    profiles.forEach(function (p) {
        if (p.shortcut) out.push({ id: p.id, label: p.name, sc: p.shortcut });
    });
    return out;
}

function showShortcutMsg(msgEl, text) {
    if (!msgEl) return;
    msgEl.textContent = text;
    setTimeout(function () { if (msgEl.textContent === text) msgEl.textContent = ''; }, 4000);
}

function updateShortcutWarning() {
    var hasAny = !!(document.getElementById('flex-shortcut').value ||
                    document.getElementById('flex-tsv-shortcut').value ||
                    profiles.some(function (p) { return p.shortcut; }));
    var warn = document.getElementById('shortcut-warning');
    if (warn) warn.style.display = hasAny ? 'none' : '';
}

function clearShortcutForId(id) {
    if (id === 'flex') {
        applyShortcutValue(document.getElementById('flex-shortcut'), '');
        saveFLExConfig();
    } else if (id === 'flex-tsv') {
        applyShortcutValue(document.getElementById('flex-tsv-shortcut'), '');
        saveFlexTSVConfig();
    } else {
        var p = getProfile(id);
        if (p) { p.shortcut = ''; saveProfiles(); }
        var panel = document.getElementById('panel-' + id);
        if (panel) {
            var scIn = panel.querySelector('[data-action="shortcut"]');
            if (scIn) applyShortcutValue(scIn, '');
        }
    }
}

function checkAndHandleDuplicateShortcut(newSc, currentId, msgEl) {
    var conflict = null;
    getAllShortcutBindings().forEach(function (b) {
        if (b.sc === newSc && b.id !== currentId) conflict = b;
    });
    if (!conflict) return;
    clearShortcutForId(conflict.id);
    showShortcutMsg(msgEl, '\u26a0 Removed from ' + conflict.label);
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
    // Load everything from storage, then build the UI
    storageGet(null, function (data) {

        // Profiles
        if (data['lingtex-profiles'] && data['lingtex-profiles'].length) {
            profiles = data['lingtex-profiles'];
        }

        // Active mode and panel
        if (data['lingtex-active-profile']) {
            activePanel = data['lingtex-active-profile'];
        }
        if (data['lingtex-active-mode']) {
            activeMode = data['lingtex-active-mode'];
        } else if (activePanel === 'flex-tsv') {
            // Migrate: old stored panel was the TSV tab — move it to TSV mode
            activeMode  = 'tsv';
            activePanel = 'flex';
        }
        storageSet({ 'lingtex-active-profile': activePanel });

        // FLEx config
        var fc = data['lingtex-flex-config'] || {};
        if (fc.glCmd        !== undefined) document.getElementById('flex-gl').value          = fc.glCmd;
        if (fc.glossCase    !== undefined) document.getElementById('flex-gloss-case').value = fc.glossCase;
        if (fc.formCmd      !== undefined) document.getElementById('flex-form-cmd').value   = fc.formCmd;
        if (fc.wrapExe      !== undefined) document.getElementById('flex-wrap-exe').value   = fc.wrapExe ? 'yes' : 'no';
        if (fc.txtrefCmd    !== undefined) document.getElementById('flex-txtref').value     = fc.txtrefCmd;
        if (fc.txtrefPrefix !== undefined) document.getElementById('flex-txtpfx').value     = fc.txtrefPrefix;
        // Default FLEx shortcut on first install; respect explicit blank if user cleared it
        var flexShortcut = fc.shortcut !== undefined ? fc.shortcut : 'Ctrl+Shift+V';
        applyShortcutValue(document.getElementById('flex-shortcut'), flexShortcut);
        if (fc.shortcut === undefined) saveFLExConfig();

        // FLEx TSV config
        var ftc = data['lingtex-flex-tsv-config'] || {};
        applyShortcutValue(document.getElementById('flex-tsv-shortcut'), ftc.shortcut);

        renderAll();
        switchMode(activeMode);

        attachStaticListeners();
        updateShortcutWarning();
    });
});

// ── Static event listeners (attached once after DOMContentLoaded) ─────────────

function attachStaticListeners() {

    // Mode buttons
    document.getElementById('mode-latex').addEventListener('click', function () {
        switchMode('latex');
    });
    document.getElementById('mode-tsv').addEventListener('click', function () {
        switchMode('tsv');
    });
    document.getElementById('mode-xlingpaper').addEventListener('click', function () {
        switchMode('xlingpaper');
    });

    // Tab: FLEx
    document.getElementById('tab-flex').addEventListener('click', function () {
        switchTab('flex');
    });

    // Add profile button
    document.getElementById('tab-add-btn').addEventListener('click', addProfile);

    // FLEx config inputs → persist + re-convert test area
    ['flex-gl', 'flex-gloss-case', 'flex-form-cmd', 'flex-wrap-exe', 'flex-txtref', 'flex-txtpfx'].forEach(function (id) {
        var el = document.getElementById(id);
        if (el) el.addEventListener('input',  function () { saveFLExConfig(); convertFlex(); if (id === 'flex-gloss-case') convertFlexTSV(); });
        if (el) el.addEventListener('change', function () { saveFLExConfig(); convertFlex(); if (id === 'flex-gloss-case') convertFlexTSV(); });
    });

    // FLEx shortcut input — capture keydown so the pressed keys are recorded,
    // not typed into the field
    var flexScInput = document.getElementById('flex-shortcut');
    var flexScMsg   = document.getElementById('flex-shortcut-msg');
    flexScInput.addEventListener('keydown', function (e) {
        e.preventDefault();
        e.stopImmediatePropagation();
        var sc = shortcutFromEvent(e);
        if (!sc) return;
        checkAndHandleDuplicateShortcut(sc, 'flex', flexScMsg);
        applyShortcutValue(flexScInput, sc);
        saveFLExConfig();
        updateShortcutWarning();
        flexScInput.blur();
    });
    document.getElementById('flex-shortcut-clear').addEventListener('click', function () {
        applyShortcutValue(flexScInput, '');
        saveFLExConfig();
        updateShortcutWarning();
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

    // FLEx TSV shortcut input
    var flexTsvScInput = document.getElementById('flex-tsv-shortcut');
    var flexTsvScMsg   = document.getElementById('flex-tsv-shortcut-msg');
    flexTsvScInput.addEventListener('keydown', function (e) {
        e.preventDefault();
        e.stopImmediatePropagation();
        var sc = shortcutFromEvent(e);
        if (!sc) return;
        checkAndHandleDuplicateShortcut(sc, 'flex-tsv', flexTsvScMsg);
        applyShortcutValue(flexTsvScInput, sc);
        saveFlexTSVConfig();
        updateShortcutWarning();
        flexTsvScInput.blur();
    });
    document.getElementById('flex-tsv-shortcut-clear').addEventListener('click', function () {
        applyShortcutValue(flexTsvScInput, '');
        saveFlexTSVConfig();
        updateShortcutWarning();
    });

    // FLEx TSV test input
    document.getElementById('flex-tsv-in').addEventListener('input', convertFlexTSV);

    // FLEx TSV clear button
    document.getElementById('flex-tsv-clear-btn').addEventListener('click', function () {
        clearTool('flex-tsv');
    });

    // FLEx TSV copy button
    document.getElementById('flex-tsv-copy-btn').addEventListener('click', function () {
        copyOutput('flex-tsv-out', this);
    });

    // Event delegation for dynamically generated TSV panels
    var main = document.getElementById('main-content');

    main.addEventListener('keydown', function (e) {
        if (e.target.dataset.action !== 'shortcut') return;
        e.preventDefault();
        e.stopImmediatePropagation();
        var sc = shortcutFromEvent(e);
        if (!sc) return;
        var pid   = pidOf(e.target);
        var msgEl = e.target.parentElement.querySelector('.shortcut-msg');
        checkAndHandleDuplicateShortcut(sc, pid, msgEl);
        applyShortcutValue(e.target, sc);
        if (pid) { var p = getProfile(pid); if (p) { p.shortcut = sc; saveProfiles(); } }
        updateShortcutWarning();
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
        var action = e.target.dataset.action;
        if (action === 'skip' || action === 'trim-leading') updateAndConvert(pid);
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
            var p = getProfile(pid); if (p) { p.shortcut = ''; saveProfiles(); }
            updateShortcutWarning();
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
            glossCase:    document.getElementById('flex-gloss-case').value,
            formCmd:      document.getElementById('flex-form-cmd').value.trim(),
            wrapExe:      document.getElementById('flex-wrap-exe').value === 'yes',
            txtrefCmd:    document.getElementById('flex-txtref').value.trim(),
            txtrefPrefix: document.getElementById('flex-txtpfx').value,
            shortcut:     document.getElementById('flex-shortcut').value
        }
    });
}

function saveFlexTSVConfig() {
    storageSet({
        'lingtex-flex-tsv-config': {
            shortcut: document.getElementById('flex-tsv-shortcut').value
        }
    });
}

// ── Mode switching ────────────────────────────────────────────────────────────

function switchMode(mode) {
    activeMode = mode;
    storageSet({ 'lingtex-active-mode': mode });

    document.querySelectorAll('.mode-btn').forEach(function (b) {
        b.classList.toggle('active', b.dataset.mode === mode);
    });

    var tabNav = document.getElementById('tab-nav');
    tabNav.style.display = (mode === 'latex') ? '' : 'none';

    if (mode === 'latex') {
        // Ensure the stored latex panel is valid
        if (!activePanel || activePanel === 'flex-tsv' ||
                !document.getElementById('panel-' + activePanel)) {
            activePanel = 'flex';
        }
        switchTab(activePanel);
    } else {
        // Deactivate all inner tabs
        document.querySelectorAll('.tab').forEach(function (b) {
            b.classList.remove('active');
        });
        // Show the mode's panel
        var targetId = (mode === 'tsv') ? 'panel-flex-tsv' : 'panel-' + mode;
        document.querySelectorAll('.panel').forEach(function (p) {
            p.classList.toggle('active', p.id === targetId);
        });
    }
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
    return { id: p.id, name: p.name, tmpl: p.tmpl, skip: p.skip,
             trimLeading: !!p.trimLeading, isDefault: !!p.isDefault };
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

        // Auto-detect grouped view
        '    <div class="cfg-row">' +
        '      <label class="cb-label"><input type="checkbox" data-action="trim-leading"' +
               (p.trimLeading ? ' checked' : '') + '> ' +
        '        Auto-detect and trim extra column from grouped view</label>' +
        '      <span class="cfg-hint-inline">When enabled, automatically strips the extra blank leading column that Phonology Assistant adds in grouped/minimal-pair view — has no effect on normal view rows</span>' +
        '    </div>' +

        // Keyboard shortcut
        '    <div class="cfg-row">' +
        '      <label>Keyboard shortcut</label>' +
        '      <div class="shortcut-row">' +
        '        <input type="text" class="shortcut-input' + (p.shortcut ? ' has-value' : '') + '"' +
        '          data-action="shortcut" placeholder="Click, then press keys…" readonly' +
        '          value="' + escHtml(p.shortcut || '') + '">' +
        '        <button class="btn btn-ghost" data-action="clear-shortcut" title="Clear shortcut">✕</button>' +
        '        <span class="shortcut-msg"></span>' +
        '      </div>' +
        '    </div>' +
        '    <div class="cfg-hint">' +
        '      Press this shortcut anywhere to instantly read the clipboard, convert' +
        '      using this profile, and insert at the cursor.' +
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
        id:          'tsv-' + Date.now(),
        name:        'New Tab',
        tmpl:        '$COL1',
        skip:        'referenced',
        trimLeading: false
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
    var tmplEl        = panel.querySelector('[data-action="tmpl"]');
    var skipEl        = panel.querySelector('[data-action="skip"]');
    var trimLeadingEl = panel.querySelector('[data-action="trim-leading"]');
    if (tmplEl)        p.tmpl        = tmplEl.value;
    if (skipEl)        p.skip        = skipEl.value;
    if (trimLeadingEl) p.trimLeading = trimLeadingEl.checked;
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
            glossCase:    document.getElementById('flex-gloss-case').value,
            formCmd:      document.getElementById('flex-form-cmd').value.trim(),
            wrapExe:      document.getElementById('flex-wrap-exe').value === 'yes',
            txtrefCmd:    document.getElementById('flex-txtref').value.trim(),
            txtrefPrefix: document.getElementById('flex-txtpfx').value
        });
        outEl.value = latex;
        var words = (blocks[0].colArrays[0] || []).length - 1;
        var msg = blocks.length > 1
            ? 'Converted ' + blocks.length + ' blocks'
            : 'Converted ' + words + ' word(s)';
        setStatus('flex', msg, 'ok');
    } catch (e) {
        outEl.value = '';
        setStatus('flex', 'Error: ' + e.message, 'err');
    }
}

function convertFlexTSV() {
    var raw    = document.getElementById('flex-tsv-in').value;
    var outEl  = document.getElementById('flex-tsv-out');

    if (!raw.trim()) {
        outEl.value = '';
        setStatus('flex-tsv', '', '');
        return;
    }

    try {
        var blocks = LingTeXCore.parseFLExBlocks(raw);
        if (!blocks.length) {
            outEl.value = '';
            setStatus('flex-tsv', 'No recognisable interlinear tiers found.', 'err');
            return;
        }
        var tsv = LingTeXCore.renderFLExTSVAuto(blocks, {
            glossCase: document.getElementById('flex-gloss-case').value
        });
        outEl.value = tsv;
        var msg = blocks.length > 1
            ? 'Converted ' + blocks.length + ' blocks'
            : 'Converted ' + ((blocks[0].colArrays[0] || []).length - 1) + ' word(s)';
        setStatus('flex-tsv', msg, 'ok');
    } catch (e) {
        outEl.value = '';
        setStatus('flex-tsv', 'Error: ' + e.message, 'err');
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
    var p    = getProfile(id);
    var trimLeading = p ? !!p.trimLeading : false;

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
        if (trimLeading) {
            if (fields.length >= 2 && fields[0] === '' && fields[1] === '') fields.shift();
        }
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
    var panel = (id === 'flex' || id === 'flex-tsv')
        ? document.getElementById('panel-' + id)
        : document.getElementById('panel-' + id);
    if (!panel) return;

    var inEl  = (id === 'flex' || id === 'flex-tsv')
        ? document.getElementById(id + '-in')
        : panel.querySelector('[data-action="test-in"]');
    var outEl = document.getElementById(id + '-out');
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
