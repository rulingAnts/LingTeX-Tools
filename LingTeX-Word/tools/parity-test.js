#!/usr/bin/env node
/**
 * LingTeX-Word — algorithm tests for reference.js
 *
 * Run:  node LingTeX-Word/tools/parity-test.js
 *
 * Two jobs:
 *
 * 1. PARITY. The golden vectors are extracted from ../../PROMPT.md at run time
 *    by substituting tabs for its `→` markers. They are NOT copied in here:
 *    hand-transcribing the empty-column runs in Example 2 got them wrong, and
 *    reading the spec means the vectors cannot drift from it. Each vector is
 *    checked against BOTH the expected output written in PROMPT.md and the live
 *    output of docs/core.js, so the spec and the reference implementation are
 *    held to each other.
 *
 * 2. ALGORITHMS. Exercises the parts that have no counterpart in core.js —
 *    segment projections, column editing, the Leipzig invariants and the wrap
 *    planner — so they are proven here before being hand-ported to VBA, which
 *    cannot be executed in CI.
 *
 * modTests.bas in ../src mirrors these cases. Keep the two in step.
 */

'use strict';

var fs   = require('fs');
var path = require('path');
var core = require('../../docs/core.js');
var R    = require('./reference.js');

var pass = 0, fail = 0;

function ok(name, cond, detail) {
    if (cond) { pass++; console.log('  PASS  ' + name); return true; }
    fail++;
    console.log('  FAIL  ' + name);
    if (detail) console.log(String(detail).replace(/^/gm, '          '));
    return false;
}

function eq(name, actual, expected) {
    return ok(name, actual === expected,
        'actual:   ' + JSON.stringify(actual) + '\nexpected: ' + JSON.stringify(expected));
}

function section(title) { console.log('\n' + title); }

// ── golden vectors, extracted from PROMPT.md ───────────────────────────────────

function loadVectors() {
    var mdPath = path.join(__dirname, '..', '..', 'PROMPT.md');
    var lines  = fs.readFileSync(mdPath, 'utf8').split('\n');

    var blocks = [], i = 0;
    while (i < lines.length) {
        if (lines[i].trim().indexOf('```') !== 0) { i++; continue; }
        var label = '';
        for (var b = i - 1; b >= 0; b--) {
            if (lines[b].trim() !== '') { label = lines[b].trim(); break; }
        }
        var body = [];
        i++;
        while (i < lines.length && lines[i].trim().indexOf('```') !== 0) body.push(lines[i++]);
        i++;
        blocks.push({ label: label, body: body });
    }

    // Inputs are the blocks holding tab markers; expectations are the blocks
    // introduced by an "Expected TSV output" line. Order pairs them up.
    var inputs = blocks.filter(function (x) {
        return x.body.some(function (l) { return l.indexOf('→') !== -1; });
    });
    var expects = blocks.filter(function (x) {
        return /Expected TSV output/i.test(x.label);
    });

    return inputs.map(function (inp, n) {
        return {
            name: 'PROMPT.md example ' + (n + 1),
            raw: inp.body.join('\n').replace(/→/g, '\t'),
            // Only the interlinear rows are compared; the free-translation row
            // is abbreviated with an ellipsis in the spec for example 2.
            expected: (expects[n] ? expects[n].body : []).slice(0, 2),
        };
    });
}

// ── 1. parity ─────────────────────────────────────────────────────────────────

var vectors = loadVectors();

section('Golden vectors (derived from PROMPT.md)');
ok('found 5 input vectors in PROMPT.md', vectors.length === 5, 'found ' + vectors.length);

// FLEx's end-of-segment sign "\u00A7" ends a line in some copies (its .flextext
// importer adds it; seen live 2026-09-28). A cell that is exactly "\u00A7" is
// dropped, with the column it leaves empty on every tier -- here the gloss
// row's trailing tab -- and a leading example number reads as Print View
// copies it.
(function () {
    var v2 = vectors[1];
    var ls = v2.raw.split('\n');
    var raw = '1.1\t' + ls[0] + '\t\u00A7\n' + ls[1] + '\t\n' + ls.slice(2).join('\n');
    var models = R.buildModels(raw, R.WORD_ALIGNED);
    ok('example 2 with a number and a trailing section sign parses to one block', models.length === 1, 'got ' + models.length);
    if (models.length === 1) {
        var rows = R.modelToTsv(models[0]).split('\n');
        eq('  its form row is example 2\'s', rows[0], v2.expected[0]);
        eq('  its gloss row is example 2\'s', rows[1], v2.expected[1]);
    }
})();

vectors.forEach(function (v) {
    var models = R.buildModels(v.raw, R.WORD_ALIGNED);
    ok(v.name + ': parses to exactly one block', models.length === 1, 'got ' + models.length);
    if (models.length !== 1) return;

    var rows = R.modelToTsv(models[0]).split('\n');

    // (a) against the expected output written in the spec
    eq(v.name + ': form row matches PROMPT.md',  rows[0], v.expected[0]);
    eq(v.name + ': gloss row matches PROMPT.md', rows[1], v.expected[1]);

    // (b) against the live reference implementation in docs/core.js
    var coreRows = core.renderFLExTSVAuto(core.parseFLExBlocks(v.raw),
                                          { glossCase: 'none' }).split('\n');
    eq(v.name + ': form row matches docs/core.js',  rows[0], coreRows[0]);
    eq(v.name + ': gloss row matches docs/core.js', rows[1], coreRows[1]);
});

// ── 2. projections ────────────────────────────────────────────────────────────

section('Projections (word-aligned vs morpheme-aligned)');

vectors.forEach(function (v) {
    var word  = R.buildModels(v.raw, R.WORD_ALIGNED)[0];
    var morph = R.buildModels(v.raw, R.MORPHEME_ALIGNED)[0];

    ok(v.name + ': morpheme-aligned has at least as many columns',
        R.colCount(morph) >= R.colCount(word),
        'word=' + R.colCount(word) + ' morpheme=' + R.colCount(morph));

    // Invariant 1 must hold by construction on a morpheme-aligned projection.
    var bad = R.checkExample(morph).filter(function (w) {
        return w.code === 'break-char-missing' || w.code === 'break-char-conflict';
    });
    ok(v.name + ': morpheme-aligned satisfies break-char agreement',
        bad.length === 0, JSON.stringify(bad, null, 1));

    // Merging every column of a word back down must reproduce word-alignment:
    // the two projections are views of one segment list, not separate parsers.
    var flags = R.noBreakFlags(morph);
    var rebuilt = JSON.parse(JSON.stringify(morph));
    for (var c = R.colCount(rebuilt) - 1; c > 0; c--) {
        if (flags[c]) R.mergeColumns(rebuilt, c - 1, c);
    }
    eq(v.name + ': merging continuations reproduces word-aligned forms',
        rebuilt.cells[0].join('\t'), word.cells[0].join('\t'));
    eq(v.name + ': merging continuations reproduces word-aligned glosses',
        rebuilt.cells[1].join('\t'), word.cells[1].join('\t'));
});

// ── 2a. ownership of a boundary across By Word and By Morpheme ───────────────

section('Ownership of a boundary across By Word and By Morpheme');

(function () {
    var v5 = vectors[4];
    var word  = R.buildModels(v5.raw, R.WORD_ALIGNED)[0];
    var morph = R.buildModels(v5.raw, R.MORPHEME_ALIGNED)[0];
    var encl  = R.buildModels(vectors[1].raw, R.WORD_ALIGNED)[0];
    ok('a proclitic\'s boundary is marked in the word-aligned cell', word.cells[0][2].indexOf(R.OWN_MARK) !== -1);
    ok('  and in its gloss', word.cells[1][2].indexOf(R.OWN_MARK) !== -1);
    ok('an enclitic\'s is not', encl.cells[0][2].indexOf(R.OWN_MARK) === -1);
    ok('one both sides own carries the mark on both sides', word.cells[0][0].indexOf(R.OWN_MARK + '=' + R.OWN_MARK) !== -1);

    var back = JSON.parse(JSON.stringify(word));
    R.projectToMorphemes(back);
    eq('re-splitting the word-aligned cells reproduces the morpheme-aligned forms', back.cells[0].join('\t'), morph.cells[0].join('\t'));
    eq('  and glosses', back.cells[1].join('\t'), morph.cells[1].join('\t'));
    ok('  and consumes every mark', (back.cells[0].join('') + back.cells[1].join('')).indexOf(R.OWN_MARK) === -1);

    var flags = R.noBreakFlags(back);
    for (var c = R.colCount(back) - 1; c > 0; c--) if (flags[c]) R.mergeColumns(back, c - 1, c);
    eq('merging back reproduces the word-aligned cells, marks and all',
        back.cells[0].join('\t') + '|' + back.cells[1].join('\t'),
        word.cells[0].join('\t') + '|' + word.cells[1].join('\t'));

    var legacy = JSON.parse(JSON.stringify(word));
    legacy.cells = legacy.cells.map(function (row) { return row.map(R.stripOwnMarks); });
    R.projectToMorphemes(legacy);
    eq('without a mark the right-hand morpheme keeps the boundary, as it always did', legacy.cells[0][3] + '|' + legacy.cells[0][4], 'ze|=zuvo');
    eq('an export shows no mark', R.modelToTsv(word).split('\n')[0], v5.expected[0]);
})();

// ── 2b. FLEx vs plain TSV routing ────────────────────────────────────────────

section('Input routing');

ok('recognises FLEx text by its tier labels', R.looksLikeFlex(vectors[0].raw));
ok('recognises a space-separated labelled block',
    R.looksLikeFlex('Morphemes zomu -xa\nLexGloss go DIST'));
ok('recognises the spaced label spellings',
    R.looksLikeFlex('Morphemes\tzomu\n\tLex. Gloss\tgo'));
ok('does NOT mistake plain TSV for FLEx',
    R.looksLikeFlex('zomu-xa\tvu\ngo-DIST\tfox') === false);

(function () {
    // The FLEx parser treats column 0 as a tier label, so plain TSV routed
    // through it would lose the first cell of every row. This is the round trip
    // that matters: our own TSV output has to come back in unchanged.
    var tsv = 'zomu-xa\tvu\ngo-DIST\tfox\nHe went far away.';
    var m = R.buildModels(tsv, R.WORD_ALIGNED);
    ok('plain TSV parses to one model', m.length === 1, 'got ' + m.length);
    eq('plain TSV keeps its first column', m[0].cells[0].join('|'), 'zomu-xa|vu');
    eq('plain TSV keeps its gloss row',    m[0].cells[1].join('|'), 'go-DIST|fox');
    eq('plain TSV lifts the untabbed line to a free translation',
        m[0].freeLines.join('|'), 'He went far away.');
})();

(function () {
    // Full round trip: FLEx in, TSV out, TSV back in, same grid.
    var first = R.buildModels(vectors[0].raw, R.WORD_ALIGNED)[0];
    var again = R.buildModels(R.modelToTsv(first), R.WORD_ALIGNED)[0];
    eq('TSV round trip preserves the form row',
        again.cells[0].join('\t'), first.cells[0].join('\t'));
    eq('TSV round trip preserves the gloss row',
        again.cells[1].join('\t'), first.cells[1].join('\t'));
})();

// ── 2c. line breaks ───────────────────────────────────────────────────────────

section('Line breaks (CR LF and CR input parse as LF input does)');

(function () {
    // Mirrors TestLineBreaks in modTests.bas. "\r\n" is a real CR LF here; the
    // VBA builds it from Chr$(13) & Chr$(10), because vbCrLf in Word and
    // PowerPoint for Mac 16.112 is LF then CR.
    function sameExamples(name, lf, wantExamples) {
        var want = R.buildModels(lf, R.WORD_ALIGNED);
        eq(name + ': examples in the LF text', want.length, wantExamples);
        [['CR LF', '\r\n'], ['CR', '\r']].forEach(function (v) {
            var got = R.buildModels(lf.replace(/\n/g, v[1]), R.WORD_ALIGNED);
            eq(name + ', ' + v[0] + ': as many examples', got.length, want.length);
            got.forEach(function (m, i) {
                eq(name + ', ' + v[0] + ': example ' + (i + 1) + ' is the same',
                    JSON.stringify(m), JSON.stringify(want[i]));
            });
        });
    }
    sameExamples('FLEx block', vectors[0].raw, 1);
    sameExamples('TSV example', 'zomu-xa\tvu\ngo-DIST\tfox\nHe went far away.\n', 1);
    sameExamples('two FLEx examples', vectors[0].raw + '\n\n' + vectors[1].raw, 2);
})();

// ── 2d. text arriving from outside the model ─────────────────────────────────

section('Clipboard and selection normalising');

(function () {
    // LingTeX-PowerPoint's acceptance vectors (modPptTests.bas SectionLineBreaks),
    // run here because VBA cannot run in CI and PowerPoint's rig is blocked on a
    // container grant. The fixture is the one its rig uses.
    var fixture = fs.readFileSync(path.join(__dirname, '..', 'samples', 'checklist-sample.txt'), 'utf8');
    var lf = normalize(fixture);                       // as LF, trailing break kept
    function normalize(s) { return String(s).replace(/\r\n/g, '\n').replace(/\r/g, '\n'); }
    function withBreaks(text, seq) { return text.replace(/\n/g, seq); }

    function blocks(raw) {
        return core.parseFLExBlocks(R.normalizeClipboardText(raw));
    }
    function check(name, raw, wantBlocks) {
        var bs = blocks(raw);
        if (!ok(name + ': blocks', bs.length === wantBlocks, 'got ' + bs.length)) return;
        ok(name + ': every block has its tiers and its free line',
            bs.every(function (b) { return b.lineTypes.length >= 2 && b.freeLines.length === 1; }),
            JSON.stringify(bs.map(function (b) { return [b.lineTypes.length, b.freeLines.length]; })));
    }

    // One example, every convention. CR CR is what TextRange2.Paste produces on
    // the Mac; LF CR is what vbCrLf IS there.
    check('one example, LF', lf, 1);
    check('one example, CR LF', withBreaks(lf, '\r\n'), 1);
    check('one example, CR', withBreaks(lf, '\r'), 1);
    check('one example, doubled CR CR', withBreaks(lf, '\r\r'), 1);
    check('one example, LF CR', withBreaks(lf, '\n\r'), 1);
    check('one example, rows split by a vertical tab', withBreaks(lf, '\u000B'), 1);

    // Two examples with one blank line between them: two blocks, never one.
    var two = lf + '\n' + lf;
    check('two examples, LF', two, 2);
    check('two examples, CR LF', withBreaks(two, '\r\n'), 2);
    check('two examples, doubled CR CR', withBreaks(two, '\r\r'), 2);
    check('two examples, LF CR', withBreaks(two, '\n\r'), 2);

    // What PowerPoint's paste reports for a CR LF copy that ends in a break: the
    // internal breaks doubled, the trailing one single, because the box's last
    // paragraph has no terminator (measured 2026-09-28, its section 4). A run at
    // either end of the payload is a terminator, not structure, and must not
    // veto the collapse.
    var pasted = withBreaks(lf, '\r\r').replace(/\r\r$/, '\r');
    check('one example, doubled CR CR, trailing CR', pasted, 1);
    check('two examples, doubled CR CR, trailing CR', withBreaks(lf, '\r\r') + '\r\r' + pasted, 2);
    eq('run profile of that two-example text',
        R.lineBreakRunProfile(withBreaks(lf, '\r\r') + '\r\r' + pasted), '1x1,2x4,4x1');

    // The number PowerPoint's rig asserts, on the same fixture.
    eq('run profile of the doubled two-example text',
        R.lineBreakRunProfile(withBreaks(two, '\r\r')), '2x5,4x1');

    // Applied twice is applied once: after a collapse the shortest run is 1.
    eq('normalising twice equals normalising once',
        R.normalizeClipboardText(R.normalizeClipboardText(withBreaks(two, '\r\r'))),
        R.normalizeClipboardText(withBreaks(two, '\r\r')));

    // Not FLEx: the blank line is left alone. Halving is justified by a fact
    // about FLEx output, so it may not be applied to a hand-built table.
    var tsv = 'one\ttwo\n\nthree\tfour';
    eq('a blank line in plain TSV survives', R.normalizeClipboardText(tsv), tsv);
    eq('a doubled-looking TSV is not collapsed either',
        R.normalizeClipboardText('one\ttwo\r\r\rthree\tfour'), 'one\ttwo\n\n\nthree\tfour');
})();

// ── 3. column editing ─────────────────────────────────────────────────────────

section('Column split and merge');

function model(tiers, rows, free) {
    return R.makeModel(tiers, rows.map(function (r) { return r.slice(); }), free || []);
}

(function () {
    var m = model([R.ROLE_MORPHEMES, R.ROLE_GLOSS, R.ROLE_FREE],
                  [['zomu-xa', 'vu'], ['go-DIST', 'fox'], ['He went far away.', '']]);
    var res = R.splitColumn(m, 0, 1);
    ok('split: reports success', res.ok, JSON.stringify(res));
    eq('split: form pieces',  m.cells[0].slice(0, 2).join('|'), 'zomu|-xa');
    eq('split: gloss pieces', m.cells[1].slice(0, 2).join('|'), 'go|-DIST');
    ok('split: boundary leads both new cells, so invariant 1 holds',
        R.checkExample(m).filter(function (w) {
            return w.code.indexOf('break-char') === 0;
        }).length === 0);
    eq('split: free row untouched', m.cells[2][0], 'He went far away.');

    R.mergeColumns(m, 0, 1);
    eq('merge: restores the form',  m.cells[0][0], 'zomu-xa');
    eq('merge: restores the gloss', m.cells[1][0], 'go-DIST');
})();

(function () {
    // A tier with fewer boundaries than asked for must NOT be guessed at.
    var m = model([R.ROLE_MORPHEMES, R.ROLE_GLOSS],
                  [['zomu-xa'], ['gone']]);
    var res = R.splitColumn(m, 0, 1);
    ok('split: reports the tier that had no boundary',
        res.ok === false && res.shortTiers.join() === R.ROLE_GLOSS,
        JSON.stringify(res));
    eq('split: short tier keeps its cell whole on the left', m.cells[1][0], 'gone');
    eq('split: short tier leaves the right column empty',    m.cells[1][1], '');
})();

(function () {
    // Leading boundary characters are part of the column, not split points.
    var m = model([R.ROLE_MORPHEMES, R.ROLE_GLOSS], [['=ve=zi'], ['=ABL=REL']]);
    R.splitColumn(m, 0, 1);
    eq('split: does not split on a leading boundary',
        m.cells[0].slice(0, 2).join('|'), '=ve|=zi');
})();

// ── 4. Leipzig invariants ─────────────────────────────────────────────────────

section('Leipzig checks');

function codes(m) {
    return R.checkExample(m).map(function (w) { return w.code; });
}

(function () {
    var m = model([R.ROLE_MORPHEMES, R.ROLE_GLOSS], [['-xa'], ['DIST']]);
    ok('detects a column where only some cells carry the break character',
        codes(m).indexOf('break-char-missing') !== -1, codes(m).join());
    ok('auto-fix adds the agreed character', R.fixColumnBreakChars(m, 0));
    eq('auto-fix result', m.cells[1][0], '-DIST');
    ok('no break-char warning remains',
        codes(m).filter(function (c) { return c.indexOf('break-char') === 0; }).length === 0,
        codes(m).join());
})();

(function () {
    var m = model([R.ROLE_MORPHEMES, R.ROLE_GLOSS], [['-xa'], ['=DIST']]);
    ok('detects conflicting break characters',
        codes(m).indexOf('break-char-conflict') !== -1, codes(m).join());
    ok('auto-fix refuses to pick one', R.fixColumnBreakChars(m, 0) === false);
})();

(function () {
    var m = model([R.ROLE_MORPHEMES, R.ROLE_GLOSS, R.ROLE_FREE],
                  [['zomu'], ['went away'], ['He went away.']]);
    ok('detects a space inside an interlinear cell',
        codes(m).indexOf('space-in-cell') !== -1, codes(m).join());
    eq('space fix count', R.fixCellSpaces(m, '.'), 1);
    eq('space fix result', m.cells[1][0], 'went.away');
    ok('free row keeps its spaces', m.cells[2][0] === 'He went away.');
    ok('no space warning remains', codes(m).indexOf('space-in-cell') === -1, codes(m).join());
})();

(function () {
    // Rule 2 counts segmentable boundaries only; rule 4's `.` and `:` do not
    // need a counterpart in the form.
    var okCase  = model([R.ROLE_MORPHEMES, R.ROLE_GLOSS], [['rixu=xo'], ['stack.CMP=SEQ']]);
    var badCase = model([R.ROLE_MORPHEMES, R.ROLE_GLOSS], [['rixu=xo'], ['stack-CMP=SEQ']]);
    ok('rule 2 ignores "." and ":"',
        codes(okCase).indexOf('boundary-parity') === -1, codes(okCase).join());
    ok('rule 2 flags a real boundary mismatch',
        codes(badCase).indexOf('boundary-parity') !== -1, codes(badCase).join());
})();

(function () {
    var m = model([R.ROLE_MORPHEMES, R.ROLE_GLOSS], [['k<um>ain'], ['eat<INF']]);
    ok('detects an unmatched infix bracket',
        codes(m).indexOf('unmatched-angle') !== -1, codes(m).join());
})();

// ── 5. isGramGloss boundary table ─────────────────────────────────────────────
// Verbatim from word_processing_tools/FLExToWord_TestChecklist.md section 11.

section('Grammatical-gloss detection (no abbreviation allow-list)');

// Cases from word_processing_tools/FLExToWord_TestChecklist.md section 11, with
// one correction. That table claims `3sg` is NOT a grammatical gloss while also
// claiming `1s` IS one "(digit-initial)" — it contradicts itself. docs/core.js
// settles it: the second branch of its isGramGloss pattern is `[0-9]\w+`, whose
// docblock reads "OR digit-initial (3sg, 1pl)", so any digit-initial token is
// grammatical. That is also the right answer typographically: someone writing
// `3sg` means the same category as `3SG` and wants it in small caps.
//
// The last case is the point of "no allow-list": an abbreviation nobody has ever
// published is still recognised, because recognition is structural.
[['FOC', true], ['3SG', true], ['3sg', true], ['bark', false],
 ['P.N.', false], ['N.', false], ['A.', false], ['DIST', true],
 ['CMP', true], ['ERG', true], ['1s', true],
 ['POSS', true], ['NOTALEIPZIGABBREVIATION', true]
].forEach(function (c) {
    ok('isGramGloss(' + JSON.stringify(c[0]) + ') === ' + c[1],
        R.isGramGloss(c[0]) === c[1], 'got ' + R.isGramGloss(c[0]));
});

// ── 6. wrap planner ───────────────────────────────────────────────────────────

section('Wrap planner');

var noFlags = function (n) { return new Array(n).fill(false); };

eq('exact fit stays on one line',
    R.computeWrapLines([10, 10, 10], noFlags(3), 30, 0, 0).join(), '0');
eq('one column over the budget wraps',
    R.computeWrapLines([10, 10, 10], noFlags(3), 25, 0, 0).join(), '0,2');
eq('three wrap lines',
    R.computeWrapLines([10, 10, 10, 10, 10, 10], noFlags(6), 25, 0, 0).join(), '0,2,4');
eq('an over-wide single column gets its own line and overflows',
    R.computeWrapLines([10, 100, 10], noFlags(3), 25, 0, 0).join(), '0,1,2');
eq('widening pulls columns back up (same input, bigger budget)',
    R.computeWrapLines([10, 10, 10, 10], noFlags(4), 100, 0, 0).join(), '0');
eq('continuation indent shrinks later lines',
    R.computeWrapLines([10, 10, 10, 10], noFlags(4), 25, 0, 10).join(), '0,2,3');

(function () {
    // A leading-boundary column must never start a line: the break moves back
    // so `zomu` and `-xa` stay together.
    var widths = [10, 10, 10];
    var flags  = [false, false, true];   // column 2 is "-xa"
    eq('a wrap line never starts on a continuation column',
        R.computeWrapLines(widths, flags, 25, 0, 0).join(), '0,1');
    eq('backing up is abandoned rather than emptying a line',
        R.computeWrapLines([10, 10], [false, true], 15, 0, 0).join(), '0,1');
})();

(function () {
    var m = R.buildModels(vectors[1].raw, R.MORPHEME_ALIGNED)[0];
    var flags = R.noBreakFlags(m);
    ok('noBreakFlags never flags the first column', flags[0] === false);
    ok('noBreakFlags flags the enclitic columns of example 2',
        flags.filter(Boolean).length > 0, JSON.stringify(flags));
})();

eq('wrapRanges splits the column list',
    JSON.stringify(R.wrapRanges([0, 2, 4], 6)), '[[0,1],[2,3],[4,5]]');

// ── summary ───────────────────────────────────────────────────────────────────

console.log('\n' + (fail === 0 ? 'ALL PASS' : 'FAILURES') +
            ' — ' + pass + ' passed, ' + fail + ' failed');
process.exit(fail === 0 ? 0 : 1);
