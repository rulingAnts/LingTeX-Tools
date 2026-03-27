/**
 * content.js — LingTeX Tools browser extension
 *
 * Runs on every page. Provides two ways to convert clipboard/pasted data to LaTeX:
 *
 *   1. Smart-paste shortcut  Ctrl+Shift+V (Win/Linux) / Cmd+Shift+V (Mac)
 *      Reads the clipboard, converts using the active profile, inserts at cursor.
 *      Always available regardless of the auto-convert toggle.
 *
 *   2. Auto-convert paste  (only when the toggle is ON in the popup)
 *      Intercepts regular Ctrl+V / right-click Paste, converts before inserting.
 *
 * Settings are read from chrome.storage.local and kept in sync via onChanged.
 * The core conversion logic is provided by core.js (loaded first by the manifest).
 */

(function () {
    'use strict';

    // ── Default profiles (mirrors web app defaults) ──────────────────────────

    var DEFAULT_PROFILES = [
        { id: 'tsv-pa',  name: 'Phonology Assistant', isDefault: true,
          tmpl: '\\exampleentry{}{$WORD}{$GLOSS}{\\phonrec{$ID}}', skip: 'referenced' },
        { id: 'tsv-dek', name: 'Dekereke', isDefault: true,
          tmpl: '\\exampleentry{}{$COL2}{$COL3}{\\phonrec{$COL1}}', skip: 'referenced' }
    ];

    // ── Cached settings ───────────────────────────────────────────────────────
    // Populated on load and kept current by the storage.onChanged listener.

    var cfg = {
        autoConvert:     false,
        activeProfileId: 'tsv-pa',
        profiles:        DEFAULT_PROFILES,
        flexConfig: {
            glCmd:        '\\gl',
            wrapExe:      true,
            txtrefCmd:    '\\txtref',
            txtrefPrefix: 'TXT:'
        }
    };

    chrome.storage.local.get(null, applyCfg);

    chrome.storage.onChanged.addListener(function (changes) {
        var patch = {};
        for (var k in changes) patch[k] = changes[k].newValue;
        applyCfg(patch);
    });

    function applyCfg(data) {
        if (data['lingtex-auto-convert']   !== undefined) cfg.autoConvert     = !!data['lingtex-auto-convert'];
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
            var parsed = LingTeXCore.parseFLExBlock(text);
            if (!parsed || !parsed.lineTypes || parsed.lineTypes.length === 0) return null;
            return LingTeXCore.renderFLEx(parsed, cfg.flexConfig);
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
    // Captured at the top of the event chain so it fires regardless of which
    // element has focus, and before the page or editor can intercept the key.

    document.addEventListener('keydown', function (e) {
        var isMac = /Mac|iPhone|iPad/i.test(navigator.platform);
        var mod   = isMac ? e.metaKey : e.ctrlKey;
        if (!mod || !e.shiftKey || e.key !== 'V') return;

        e.preventDefault();
        e.stopImmediatePropagation();

        navigator.clipboard.readText().then(function (text) {
            insertAtCursor(convert(text) || text);
        }).catch(function () {
            // Clipboard permission denied — nothing we can do here
        });
    }, true);

    // ── Auto-convert paste intercept ──────────────────────────────────────────
    // Only active when cfg.autoConvert is true (set via the popup toggle).
    // If conversion produces no output (e.g. unrecognised format), falls through
    // to normal paste behaviour.

    document.addEventListener('paste', function (e) {
        if (!cfg.autoConvert) return;
        var text = e.clipboardData && e.clipboardData.getData('text/plain');
        if (!text) return;

        var out = convert(text);
        if (!out || out === text) return;   // nothing changed — let it fall through

        e.preventDefault();
        e.stopImmediatePropagation();
        insertAtCursor(out);
    }, true);

    // ── Message from background service worker ────────────────────────────────
    // Background forwards the keyboard-command event here as a fallback for
    // cases where the keydown listener might be suppressed by the page.

    chrome.runtime.onMessage.addListener(function (msg) {
        if (msg.type !== 'SMART_PASTE') return;
        navigator.clipboard.readText().then(function (text) {
            insertAtCursor(convert(text) || text);
        }).catch(function () {});
    });

}());
