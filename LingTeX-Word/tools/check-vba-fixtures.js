#!/usr/bin/env node
/**
 * LingTeX-Word — do modTests.bas's golden vectors still say what the parser says?
 *
 * Run:  node LingTeX-Word/tools/check-vba-fixtures.js
 *
 * THE SEAM THIS COVERS. The golden vectors exist in three places:
 *
 *   PROMPT.md              the spec, and the only copy anything derives from
 *   reference.js/core.js   the JavaScript implementations
 *   src/modTests.bas       hand-copied VBA fixtures, checked by CheckVector
 *                          — inside Word, which no CI runner has
 *
 * parity-test.js holds the first two to each other: it extracts the vectors from
 * PROMPT.md at run time and never reads modTests.bas. modTests.bas keeps its own
 * copies, with a comment asking whoever edits them to keep the two in step. That
 * by-hand seam is unchecked by anything, and it is where a real defect lived: a
 * bulk edit of the example data (2026-09-16) rewrote Vector1Raw but left
 * Vector1Forms and Vector1Glosses matching the old text, which broke CheckVector
 * at six release tags while parity-test.js stayed green throughout — it never
 * looks at the VBA.
 *
 * So this asks, outside Word, the question CheckVector asks inside it: parse the
 * VBA's own Vector*Raw() with the reference implementation, and compare the form
 * row, the gloss row and the free translation against what the VBA asserts. The
 * raw fixture is also compared with PROMPT.md, so a fixture cannot drift from the
 * spec either.
 *
 * It reads modTests.bas as text and evaluates the VBA string expressions —
 * literals, T (tab), vbLf, line continuations, apostrophes inside strings — so
 * nothing has to be transcribed here and this file cannot drift in its turn.
 *
 * Exit 0 all agree, 1 otherwise.
 */

'use strict';

var fs = require('fs');
var path = require('path');

var here = __dirname;
var root = path.join(here, '..', '..');
var R = require(path.join(here, 'reference.js'));
var bas = fs.readFileSync(path.join(here, '..', 'src', 'modTests.bas'), 'latin1');

/** A VBA source region with its line continuations joined. */
function joined(text) {
    return text.replace(/\r/g, '').split('\n')
        .map(function (l) { return l.trim(); })
        .filter(function (l) { return l && l.charAt(0) !== "'"; })
        .join('\n').replace(/_\n/g, '');
}

/** Evaluate a VBA string expression: literals, T, vbTab, vbLf, vbCr, joined by &. */
function vbaString(expr, where) {
    var out = '', i = 0;
    while (i < expr.length) {
        var c = expr.charAt(i);
        if (c === '"') {
            i++;
            while (i < expr.length) {
                if (expr.charAt(i) === '"' && expr.charAt(i + 1) === '"') { out += '"'; i += 2; continue; }
                if (expr.charAt(i) === '"') { i++; break; }
                out += expr.charAt(i++);
            }
        } else if (/[A-Za-z]/.test(c)) {
            var w = '';
            while (i < expr.length && /[A-Za-z0-9_]/.test(expr.charAt(i))) w += expr.charAt(i++);
            if (w === 'T' || w === 'vbTab') out += '\t';
            else if (w === 'vbLf') out += '\n';
            else if (w === 'vbCr') out += '\r';
            else throw new Error('unknown token "' + w + '" in ' + where);
        } else i++;                      // & and whitespace
    }
    return out;
}

/** The string a Private Function Name() As String returns. */
function vbaFunc(name) {
    var m = bas.match(new RegExp('Private Function ' + name + '\\(\\) As String([\\s\\S]*?)End Function'));
    if (!m) throw new Error('no such function in modTests.bas: ' + name);
    var body = joined(m[1]);
    return vbaString(body.slice(body.indexOf('=') + 1), name);
}

/** The free translation each CheckVector call asserts, by vector number. */
function expectedFree() {
    var m = bas.match(/Private Sub TestGoldenVectors\(\)([\s\S]*?)End Sub/);
    if (!m) throw new Error('TestGoldenVectors not found in modTests.bas');
    var body = joined(m[1]);
    var out = {}, call;
    var re = /CheckVector\s+"[^"]*",\s*Vector(\d)Raw\(\),\s*Vector\d+Forms\(\),\s*Vector\d+Glosses\(\),\s*("(?:[^"]|"")*")/g;
    while ((call = re.exec(body)) !== null) out[call[1]] = vbaString(call[2], 'CheckVector');
    return out;
}

/** The raw vectors in PROMPT.md, as parity-test.js derives them. */
function promptVectors() {
    var lines = fs.readFileSync(path.join(root, 'PROMPT.md'), 'utf8').split('\n');
    var blocks = [], i = 0;
    while (i < lines.length) {
        if (lines[i].trim().indexOf('```') !== 0) { i++; continue; }
        var body = [];
        i++;
        while (i < lines.length && lines[i].trim().indexOf('```') !== 0) body.push(lines[i++]);
        i++;
        blocks.push(body);
    }
    return blocks.filter(function (b) {
        return b.some(function (l) { return l.indexOf('→') !== -1; });
    }).map(function (b) { return b.join('\n').replace(/→/g, '\t'); });
}

var bad = 0;

function eq(label, actual, expected) {
    if (actual === expected) { console.log('  OK    ' + label); return; }
    bad++;
    console.log('  FAIL  ' + label);
    console.log('        parser:   ' + JSON.stringify(actual));
    console.log('        modTests: ' + JSON.stringify(expected));
}

var free = expectedFree();
var prompts = promptVectors();

[1, 2].forEach(function (n) {
    console.log('modTests.bas golden vector ' + n);
    var raw = vbaFunc('Vector' + n + 'Raw');
    var models = R.buildModels(raw, R.WORD_ALIGNED);
    if (models.length !== 1) {
        bad++;
        console.log('  FAIL  parses to ' + models.length + ' blocks, not 1');
        return;
    }
    var rows = R.modelToTsv(models[0]).split('\n');
    eq('form row', rows[0], vbaFunc('Vector' + n + 'Forms'));
    eq('gloss row', rows[1], vbaFunc('Vector' + n + 'Glosses'));

    var lines = models[0].freeLines || [];
    if (lines.length !== 1) {
        bad++;
        console.log('  FAIL  free translation: ' + lines.length + ' lines, CheckVector expects 1');
    } else if (free[String(n)] === undefined) {
        bad++;
        console.log('  FAIL  no CheckVector call found for vector ' + n);
    } else {
        eq('free translation', lines[0], free[String(n)]);
    }

    // The fixture against the spec: only the interlinear rows, since PROMPT.md
    // abbreviates example 2's free translation with an ellipsis.
    var spec = (prompts[n - 1] || '').split('\n').slice(0, 2).join('\n');
    if (spec === raw.split('\n').slice(0, 2).join('\n')) {
        console.log('  OK    raw fixture matches PROMPT.md example ' + n);
    } else {
        bad++;
        console.log('  FAIL  raw fixture has drifted from PROMPT.md example ' + n);
    }
});

console.log('');
console.log(bad ? 'PROBLEMS -- ' + bad
                : 'ALL PASS -- the VBA fixtures, the reference implementation and PROMPT.md agree');
process.exit(bad ? 1 : 0);
