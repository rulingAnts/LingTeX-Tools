/**
 * content.js — LingTeX Tools browser extension
 *
 * Runs on every page. Per-profile keyboard shortcuts convert the clipboard
 * and insert the resulting LaTeX at the cursor — no clipboard modification,
 * no paste interception.
 *
 * Settings are read from chrome.storage.local and kept in sync via onChanged.
 * The core conversion logic is provided by core.js (loaded first by the manifest).
 */

(function () {
    'use strict';

    // ── Default profiles (mirrors web app defaults) ──────────────────────────

    var DEFAULT_PROFILES = [
        { id: 'tsv-pa',  name: 'Phonology Assistant', isDefault: true,
          tmpl: '\\exampleentry{}{$WORD}{$GLOSS}{\\phonrec{$ID}}', skip: 'referenced', trimLeading: true },
        { id: 'tsv-dek', name: 'Dekereke', isDefault: true,
          tmpl: '\\exampleentry{}{$COL2}{$COL3}{\\phonrec{$COL1}}', skip: 'referenced', trimLeading: false }
    ];

    // ── Cached settings ───────────────────────────────────────────────────────
    // Populated on load and kept current by the storage.onChanged listener.

    var cfg = {
        activeProfileId: 'tsv-pa',
        profiles:        DEFAULT_PROFILES,
        flexConfig: {
            glCmd:        '\\textsc',
            glossCase:    'capitalize',
            formCmd:      '\\textit',
            wrapExe:      true,
            txtrefCmd:    '%\\txtref',
            txtrefPrefix: 'TXT:',
            shortcut:     'Ctrl+Shift+V'
        }
    };

    chrome.storage.local.get(null, applyCfg);

    chrome.storage.onChanged.addListener(function (changes) {
        var patch = {};
        for (var k in changes) patch[k] = changes[k].newValue;
        applyCfg(patch);
    });

    function applyCfg(data) {
        if (data['lingtex-active-profile'] !== undefined) cfg.activeProfileId = data['lingtex-active-profile'];
        if (data['lingtex-profiles']       !== undefined) cfg.profiles        = data['lingtex-profiles'];
        if (data['lingtex-flex-config']    !== undefined) cfg.flexConfig      = data['lingtex-flex-config'];
    }

    // ── Conversion ────────────────────────────────────────────────────────────

    function convert(text) {
        if (!text || !text.trim()) return null;
        return cfg.activeProfileId === 'flex' ? convertFLEx(text) : convertTSV(text);
    }

    function convertFLEx(text) {
        try {
            var blocks = LingTeXCore.parseFLExBlocks(text);
            if (!blocks || !blocks.length) return null;
            return LingTeXCore.renderFLExAuto(blocks, cfg.flexConfig);
        } catch (e) { return null; }
    }

    function convertTSV(text) {
        var profile = cfg.profiles.filter(function (p) { return p.id === cfg.activeProfileId; })[0];
        if (!profile) return null;

        var tmpl = profile.tmpl || '';
        var usedCols = [];

        if (profile.skip === 'referenced') {
            if (/\$WORD\b/.test(tmpl))  addUniq(usedCols, 2);
            if (/\$GLOSS\b/.test(tmpl)) addUniq(usedCols, 3);
            if (/\$ID\b/.test(tmpl))    addUniq(usedCols, 6);
            var m, re = /\$COL(\d+)/g;
            while ((m = re.exec(tmpl)) !== null) addUniq(usedCols, parseInt(m[1], 10));
        }

        var results = text.replace(/\r\n?/g, '\n').split('\n')
            .filter(function (l) { return l.trim(); })
            .reduce(function (acc, line) {
                var fields = LingTeXCore.parseTSVRow(line);
                if (profile.trimLeading) {
                    if (fields.length >= 2 && fields[0] === '' && fields[1] === '') fields.shift();
                }
                if (profile.skip === 'referenced' && usedCols.length) {
                    if (usedCols.some(function (n) { return !fields[n - 1]; })) return acc;
                }
                if (profile.skip === 'col1' && !fields[0]) return acc;
                acc.push(LingTeXCore.applyRowTemplate(tmpl, fields));
                return acc;
            }, []);

        return results.length ? results.join('\n') : null;
    }

    function addUniq(arr, v) { if (arr.indexOf(v) === -1) arr.push(v); }

    // ── Shortcut helpers ──────────────────────────────────────────────────────

    // Normalise a KeyboardEvent into a canonical shortcut string, e.g. "Ctrl+Shift+1".
    // "Ctrl" means Cmd on Mac and Ctrl elsewhere.  Returns null for modifier-only presses.
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

    function findProfileForShortcut(shortcut) {
        if (cfg.flexConfig && cfg.flexConfig.shortcut === shortcut) return 'flex';
        for (var i = 0; i < cfg.profiles.length; i++) {
            if (cfg.profiles[i].shortcut === shortcut) return cfg.profiles[i].id;
        }
        return null;
    }

    // ── Insert at cursor ──────────────────────────────────────────────────────
    // Works for plain textarea/input, and for contenteditable editors (Overleaf/
    // CodeMirror). execCommand('insertText') is deprecated but remains the most
    // reliable cross-browser way to inject text into a contenteditable.

    function insertAtCursor(text) {
        var el = document.activeElement;
        if (!el) return;

        if (el.tagName === 'TEXTAREA' ||
            (el.tagName === 'INPUT' && el.type !== 'checkbox' && el.type !== 'radio')) {
            var s = el.selectionStart, e = el.selectionEnd;
            el.value = el.value.slice(0, s) + text + el.value.slice(e);
            el.selectionStart = el.selectionEnd = s + text.length;
            el.dispatchEvent(new Event('input', { bubbles: true }));
            return;
        }

        // ContentEditable / CodeMirror 6 (Overleaf) — triggers beforeinput
        if (!document.execCommand('insertText', false, text)) {
            // Last-resort fallback: raw DOM insertion
            var sel = window.getSelection();
            if (sel && sel.rangeCount) {
                var range = sel.getRangeAt(0);
                range.deleteContents();
                var node = document.createTextNode(text);
                range.insertNode(node);
                range.setStartAfter(node);
                range.collapse(true);
                sel.removeAllRanges();
                sel.addRange(range);
            }
        }
    }

    // ── Smart-paste shortcut  Ctrl+Shift+V / Cmd+Shift+V ─────────────────────
    // Arms a keydown listener: reads the clipboard, converts, and inserts the
    // resulting LaTeX directly at the cursor. The clipboard itself is never written.

    document.addEventListener('keydown', function (e) {
        // ── Per-profile shortcuts ─────────────────────────────────────────────
        // Each profile can have a custom shortcut (e.g. Ctrl+Shift+1).
        // Pressing it reads the clipboard, converts, and inserts at the cursor.
        var shortcut = shortcutFromEvent(e);
        if (!shortcut) return;

        var matched = findProfileForShortcut(shortcut);
        if (!matched) return;

        e.preventDefault();
        e.stopImmediatePropagation();
        cfg.activeProfileId = matched;
        chrome.storage.local.set({ 'lingtex-active-profile': matched });
        navigator.clipboard.readText().then(function (text) {
            var out = convert(text);
            if (out) insertAtCursor(out);
        }).catch(function () {});
    }, true);

}());