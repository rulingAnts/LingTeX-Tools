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
ok('found 2 input vectors in PROMPT.md', vectors.length === 2, 'found ' + vectors.length);

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

// ── 2b. FLEx vs plain TSV routing ────────────────────────────────────────────

section('Input routing');

ok('recognises FLEx text by its tier labels', R.looksLikeFlex(vectors[0].raw));
ok('recognises a space-separated labelled block',
    R.looksLikeFlex('Morphemes kata -bi\nLexGloss go DIST'));
ok('recognises the spaced label spellings',
    R.looksLikeFlex('Morphemes\tkata\n\tLex. Gloss\tgo'));
ok('does NOT mistake plain TSV for FLEx',
    R.looksLikeFlex('kata-bi\tdi\ngo-DIST\tpig') === false);

(function () {
    // The FLEx parser treats column 0 as a tier label, so plain TSV routed
    // through it would lose the first cell of every row. This is the round trip
    // that matters: our own TSV output has to come back in unchanged.
    var tsv = 'kata-bi\tdi\ngo-DIST\tpig\nHe went far away.';
    var m = R.buildModels(tsv, R.WORD_ALIGNED);
    ok('plain TSV parses to one model', m.length === 1, 'got ' + m.length);
    eq('plain TSV keeps its first column', m[0].cells[0].join('|'), 'kata-bi|di');
    eq('plain TSV keeps its gloss row',    m[0].cells[1].join('|'), 'go-DIST|pig');
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
    // VBA builds it from Chr$(13) & Chr$(10), because vbCrLf in PowerPoint for
    // Mac 16.112 is LF then CR.
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
    sameExamples('TSV example', 'kata-bi\tdi\ngo-DIST\tpig\nHe went far away.\n', 1);
    sameExamples('two FLEx examples', vectors[0].raw + '\n\n' + vectors[1].raw, 2);
})();

// ── 3. column editing ─────────────────────────────────────────────────────────

section('Column split and merge');

function model(tiers, rows, free) {
    return R.makeModel(tiers, rows.map(function (r) { return r.slice(); }), free || []);
}

(function () {
    var m = model([R.ROLE_MORPHEMES, R.ROLE_GLOSS, R.ROLE_FREE],
                  [['kata-bi', 'di'], ['go-DIST', 'pig'], ['He went far away.', '']]);
    var res = R.splitColumn(m, 0, 1);
    ok('split: reports success', res.ok, JSON.stringify(res));
    eq('split: form pieces',  m.cells[0].slice(0, 2).join('|'), 'kata|-bi');
    eq('split: gloss pieces', m.cells[1].slice(0, 2).join('|'), 'go|-DIST');
    ok('split: boundary leads both new cells, so invariant 1 holds',
        R.checkExample(m).filter(function (w) {
            return w.code.indexOf('break-char') === 0;
        }).length === 0);
    eq('split: free row untouched', m.cells[2][0], 'He went far away.');

    R.mergeColumns(m, 0, 1);
    eq('merge: restores the form',  m.cells[0][0], 'kata-bi');
    eq('merge: restores the gloss', m.cells[1][0], 'go-DIST');
})();

(function () {
    // A tier with fewer boundaries than asked for must NOT be guessed at.
    var m = model([R.ROLE_MORPHEMES, R.ROLE_GLOSS],
                  [['kata-bi'], ['gone']]);
    var res = R.splitColumn(m, 0, 1);
    ok('split: reports the tier that had no boundary',
        res.ok === false && res.shortTiers.join() === R.ROLE_GLOSS,
        JSON.stringify(res));
    eq('split: short tier keeps its cell whole on the left', m.cells[1][0], 'gone');
    eq('split: short tier leaves the right column empty',    m.cells[1][1], '');
})();

(function () {
    // Leading boundary characters are part of the column, not split points.
    var m = model([R.ROLE_MORPHEMES, R.ROLE_GLOSS], [['=de=di'], ['=ABL=REL']]);
    R.splitColumn(m, 0, 1);
    eq('split: does not split on a leading boundary',
        m.cells[0].slice(0, 2).join('|'), '=de|=di');
})();

// ── 4. Leipzig invariants ─────────────────────────────────────────────────────

section('Leipzig checks');

function codes(m) {
    return R.checkExample(m).map(function (w) { return w.code; });
}

(function () {
    var m = model([R.ROLE_MORPHEMES, R.ROLE_GLOSS], [['-bi'], ['DIST']]);
    ok('detects a column where only some cells carry the break character',
        codes(m).indexOf('break-char-missing') !== -1, codes(m).join());
    ok('auto-fix adds the agreed character', R.fixColumnBreakChars(m, 0));
    eq('auto-fix result', m.cells[1][0], '-DIST');
    ok('no break-char warning remains',
        codes(m).filter(function (c) { return c.indexOf('break-char') === 0; }).length === 0,
        codes(m).join());
})();

(function () {
    var m = model([R.ROLE_MORPHEMES, R.ROLE_GLOSS], [['-bi'], ['=DIST']]);
    ok('detects conflicting break characters',
        codes(m).indexOf('break-char-conflict') !== -1, codes(m).join());
    ok('auto-fix refuses to pick one', R.fixColumnBreakChars(m, 0) === false);
})();

(function () {
    var m = model([R.ROLE_MORPHEMES, R.ROLE_GLOSS, R.ROLE_FREE],
                  [['kata'], ['went away'], ['He went away.']]);
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
    var okCase  = model([R.ROLE_MORPHEMES, R.ROLE_GLOSS], [['kada=te'], ['carry.CMP=SEQ']]);
    var badCase = model([R.ROLE_MORPHEMES, R.ROLE_GLOSS], [['kada=te'], ['carry-CMP=SEQ']]);
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
    // so `kata` and `-bi` stay together.
    var widths = [10, 10, 10];
    var flags  = [false, false, true];   // column 2 is "-bi"
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
