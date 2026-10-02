#!/usr/bin/env node
/**
 * LingTeX-Word site — does docs/assets/word-release.js choose a release that
 * has its files?
 *
 * Run:  node LingTeX-Word/tools/word-release.test.mjs
 * Exit: 0 all pass, 1 otherwise. No network: the GitHub reply is a fixture.
 *
 * Issue #7 (2026-09-21): both download buttons said "Not Found". The page's
 * written links named beta.6, whose files had been deleted, and the script that
 * moves them chose the newest word-v release by date alone, which was that same
 * empty beta.6, so it moved nothing. The script now skips releases without
 * their files. This runs its wordLinks() against the real API reply of
 * 2026-10-02 (word-release-fixture-2026-10-02.json, trimmed to the fields the
 * script reads) and variations of it, then runs the whole script against a fake
 * page built from the data-word links of docs/word/index.html and
 * docs/index.html, so "nothing changes" is checked on the links themselves.
 *
 * The script is loaded as a function in this realm (not require()), so it runs
 * the same whatever package.json sits above the clone.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const docs = fileURLToPath(new URL('../../docs/', import.meta.url));
const scriptPath = docs + 'assets/word-release.js';
const src = readFileSync(scriptPath, 'utf8');
const fixture = JSON.parse(readFileSync(new URL('word-release-fixture-2026-10-02.json', import.meta.url), 'utf8'));
// (module, window, document, fetch) shadow node's own globals inside the script.
const run = vm.runInThisContext('(function (module, window, document, fetch) {' + src + '\n})',
                                { filename: scriptPath });

let bad = 0;
function ok(what) { console.log('  OK    ' + what); }
function fail(what) { bad++; console.log('  FAIL  ' + what); }
function eq(what, got, want) {
    if (got === want) ok(what);
    else fail(what + ': got ' + JSON.stringify(got) + ', want ' + JSON.stringify(want));
}

const mod = { exports: {} };
run(mod, undefined, undefined, undefined);
const { wordLinks } = mod.exports;
if (typeof wordLinks !== 'function') {
    console.log('  FAIL  word-release.js exports no wordLinks() when module.exports exists');
    process.exit(1);
}

const R = 'https://github.com/rulingAnts/LingTeX-Tools/releases/';
const B10 = {
    version: '0.1.0-beta.10',
    release: R + 'tag/word-v0.1.0-beta.10',
    exe:     R + 'download/word-v0.1.0-beta.10/LingTeX-Word-Setup-word-v0.1.0-beta.10.exe',
    winzip:  R + 'download/word-v0.1.0-beta.10/LingTeX-Word-word-v0.1.0-beta.10-windows.zip',
    maczip:  R + 'download/word-v0.1.0-beta.10/LingTeX-Word-word-v0.1.0-beta.10-macos.dmg',
    guide:   R + 'download/word-v0.1.0-beta.10/LingTeX-Word-Guide-word-v0.1.0-beta.10.pdf',
    macext:  '.dmg'
};
function isB10(what, links) {
    if (!links) { fail(what + ': chose no release'); return; }
    Object.keys(B10).forEach(function (k) { eq(what + ' -> ' + k, links[k], B10[k]); });
    const extra = Object.keys(links).filter(function (k) { return !(k in B10); });
    if (extra.length) fail(what + ': unexpected keys ' + extra.join(', '));
}
function word(tag, published, names, more) {
    return Object.assign({
        tag_name: tag, draft: false, prerelease: true, published_at: published,
        html_url: R + 'tag/' + tag,
        assets: names.map(function (n) {
            return { name: n.replace(/TAG/g, tag), browser_download_url: R + 'download/' + tag + '/' + n.replace(/TAG/g, tag) };
        })
    }, more || {});
}
const ALL = ['LingTeX-Word-Guide-TAG.pdf', 'LingTeX-Word-Setup-TAG.exe',
             'LingTeX-Word-TAG-macos.dmg', 'LingTeX-Word-TAG-windows.zip', 'LingTeX-Word.dotm'];

console.log('wordLinks(), the choice');

// 1. Today's reply: beta.10 for every key. (The API lists beta.10 third, so this
//    also proves the choice is by date, not by list order.)
isB10('2026-10-02 reply', wordLinks(fixture));

// 2. The reply as it stood when #7 was filed: only the empty beta.1, beta.2 and
//    beta.6 among the word-v releases, so no release qualifies and nothing moves.
const issueTime = '2026-09-21T19:49:00Z';
const atIssue = fixture.filter(function (r) { return r.published_at < issueTime; });
eq('#7-time reply holds word-v releases, all empty',
   atIssue.filter(function (r) { return /^word-v/.test(r.tag_name); })
          .map(function (r) { return r.tag_name + ':' + r.assets.length; }).join(' '),
   'word-v0.1.0-beta.6:0 word-v0.1.0-beta.2:0 word-v0.1.0-beta.1:0');
eq('#7-time reply -> no release chosen', wordLinks(atIssue), null);

// 3. The newest word-v release is empty: skipped for the next one with files.
isB10('newest has 0 assets', wordLinks(fixture.concat([word('word-v0.1.0-beta.11', '2026-10-01T00:00:00Z', [])])));
//    ...or has only some of them: skipped too, so version and downloads agree.
isB10('newest has only the exe', wordLinks(fixture.concat([
    word('word-v0.1.0-beta.11', '2026-10-01T00:00:00Z', ['LingTeX-Word-Setup-TAG.exe'])])));
isB10('newest lacks the Mac file', wordLinks(fixture.concat([
    word('word-v0.1.0-beta.11', '2026-10-01T00:00:00Z', ['LingTeX-Word-Setup-TAG.exe', 'LingTeX-Word-TAG-windows.zip'])])));
//    A release with every download but no guide is chosen; the guide keeps its written link.
const noGuide = wordLinks(fixture.concat([word('word-v0.1.0-beta.11', '2026-10-01T00:00:00Z', ALL.slice(1))]));
eq('newest lacks only the guide -> chosen', noGuide && noGuide.version, '0.1.0-beta.11');
eq('newest lacks only the guide -> no guide key', noGuide && ('guide' in noGuide), false);

// 4. A draft is never chosen, even when newest and complete.
isB10('newest is a complete draft', wordLinks(fixture.concat([
    word('word-v0.1.0-beta.12', '2026-10-01T00:00:00Z', ALL, { draft: true })])));
isB10('draft without a date (as the API gives them)', wordLinks(fixture.concat([
    word('word-v0.1.0-beta.12', null, ALL, { draft: true })])));

// 5. Unexpected JSON: nothing chosen, nothing thrown.
[['null', null], ['an object', { message: 'API rate limit exceeded' }], ['empty list', []],
 ['list of junk', [null, 1, 'x', {}, { tag_name: 'word-v9', published_at: '2027-01-01T00:00:00Z' }]]]
    .forEach(function (c) {
        try { eq(c[0] + ' -> no release chosen', wordLinks(c[1]), null); }
        catch (e) { fail(c[0] + ' threw ' + e); }
    });
//    Download links that are not this repository's releases are not used.
isB10('newest points off-site', wordLinks(fixture.concat([Object.assign(
    word('word-v0.1.0-beta.11', '2026-10-01T00:00:00Z', ALL),
    { html_url: 'https://example.com/x' })])));
const offsite = word('word-v0.1.0-beta.11', '2026-10-01T00:00:00Z', ALL);
offsite.assets[1].browser_download_url = 'javascript:alert(1)';
isB10('newest exe link is not a release URL', wordLinks(fixture.concat([offsite])));

// The whole script against a fake page made of the real pages' data-word links.
console.log('');
console.log('the script on the pages\' links');

// stale: every link and text says STALE instead of what is written, so any
// rewrite shows, whichever release the page names.
function fakePage(file, stale) {
    const html = readFileSync(docs + file, 'utf8');
    const els = [];
    const re = /<(a|span)\b([^>]*\bdata-word="([a-z]+)"[^>]*)>([^<]*)/g;
    let m;
    while ((m = re.exec(html))) {
        const href = /\bhref="([^"]*)"/.exec(m[2]);
        els.push({ key: m[3], href: href ? (stale ? 'STALE' : href[1]) : undefined,
                   textContent: stale ? 'STALE' : m[4],
                   getAttribute: function () { return this.key; } });
    }
    return { file: file, els: els,
             document: { querySelectorAll: function (sel) {
                 if (sel !== '[data-word]') throw new Error('unexpected selector ' + sel);
                 return els;
             } } };
}
function snapshot(page) {
    return page.els.map(function (e) { return e.key + '=' + (e.href !== undefined ? e.href : e.textContent); }).join('\n');
}
async function onPage(file, fetchImpl) {
    const page = fakePage(file, true);
    const before = snapshot(page);
    run(undefined, { fetch: fetchImpl }, page.document, fetchImpl);
    await new Promise(function (r) { setTimeout(r, 0); });
    return { page: page, before: before, after: snapshot(page) };
}
function replying(status, body) {
    return function () {
        return Promise.resolve({ ok: status === 200, status: status,
                                 json: function () { return Promise.resolve(body); } });
    };
}

for (const file of ['word/index.html', 'index.html']) {
    const keys = fakePage(file).els.map(function (e) { return e.key; });
    if (!keys.length) { fail(file + ': no data-word links found'); continue; }

    // The written links are what anyone gets whom the script misses, so they too
    // must name one release (whether its files answer is check-site-links.sh's job).
    const tags = {};
    fakePage(file).els.forEach(function (e) {
        const t = e.href !== undefined ? /\/(?:download|tag)\/(word-v[^/]+)/.exec(e.href) : [0, 'word-v' + e.textContent];
        tags[t ? t[1] : '(' + e.key + ': no word-v tag in ' + e.href + ')'] = 1;
    });
    eq(file + ' written links all name one release', Object.keys(tags).length, 1);
    if (Object.keys(tags).length !== 1) console.log('        ' + Object.keys(tags).join(', '));

    const today = await onPage(file, replying(200, fixture));
    today.page.els.forEach(function (e) {
        eq(file + ' 2026-10-02 reply -> ' + e.key, e.href !== undefined ? e.href : e.textContent, B10[e.key]);
    });

    const cases = [
        ['#7-time reply', replying(200, atIssue)],
        ['403 rate limit', replying(403, { message: 'API rate limit exceeded' })],
        ['network failure', function () { return Promise.reject(new TypeError('Failed to fetch')); }],
        ['body that is not JSON', function () {
            return Promise.resolve({ ok: true, json: function () { return Promise.reject(new SyntaxError('bad JSON')); } });
        }],
        ['an object, not a list', replying(200, { message: 'Not Found' })]
    ];
    for (const c of cases) {
        const r = await onPage(file, c[1]);
        eq(file + ' ' + c[0] + ' -> written links kept', r.after, r.before);
    }

    // No fetch at all (very old browsers): nothing runs.
    const page = fakePage(file, true);
    const before = snapshot(page);
    run(undefined, {}, page.document, undefined);
    eq(file + ' no window.fetch -> written links kept', snapshot(page), before);
}

console.log('');
console.log(bad ? 'PROBLEMS -- ' + bad
                : 'ALL PASS -- word-release.js chooses the newest Word release that has its files');
process.exit(bad ? 1 : 0);
