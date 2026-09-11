/**
 * LingTeX-Word — JavaScript reference implementation
 *
 * This file is the *executable specification* for the VBA add-in in ../src/.
 * The VBA modules are a hand port of the functions here, and `parity-test.js`
 * is what proves the algorithms correct before any VBA is written.
 *
 *   reference.js  function      →  VBA
 *   ───────────────────────────────────────────────────────────
 *   groupSegments               →  modFlexParse.GroupSegmentsFromColumns
 *   handleStandalonePunctuation →  modFlexParse.HandleStandalonePunctuation
 *   buildModel                  →  modIgtModel.ModelFromFlex
 *   projectColumns              →  modIgtModel (projection helpers)
 *   mergeColumns / splitColumn  →  modIgtModel.MergeColumns / .SplitColumn
 *   checkExample                →  modLeipzig.CheckExample
 *   fixColumnBreakChars         →  modLeipzig.FixColumnBreakChars
 *   fixCellSpaces               →  modLeipzig.FixCellSpaces
 *   noBreakFlags                →  modWrap.NoBreakFlags
 *   computeWrapLines            →  modWrap.ComputeWrapLines
 *
 * IF YOU CHANGE AN ALGORITHM HERE, CHANGE IT IN THE MATCHING VBA PROCEDURE.
 * The split exists because VBA cannot be executed in CI and JavaScript can.
 *
 * Tier parsing itself is NOT duplicated here: it is delegated to
 * ../../docs/core.js, the repo's single source of truth for FLEx parsing.
 */

'use strict';

var core = require('../../docs/core.js');

// ── constants ────────────────────────────────────────────────────────────────

/** Morpheme boundary characters, per Leipzig rules 2 (-), 6 (=), 7 (~), 8 (<>). */
var MORPH_DIVS = '-=~<>';

/** Tier roles. FREE rows are exempt from every interlinear invariant. */
var ROLE_VERNACULAR = 'Vernacular';
var ROLE_MORPHEMES  = 'Morphemes';
var ROLE_GLOSS      = 'Gloss';
var ROLE_WORDGLOSS  = 'WordGloss';
var ROLE_CATEGORY   = 'Category';
var ROLE_FREE       = 'Free';

/** Granularity of the initial projection. */
var WORD_ALIGNED     = 'word';
var MORPHEME_ALIGNED = 'morpheme';

/**
 * Single-character punctuation that attaches to the preceding form.
 * Mirrors core.js handleStandalonePunctuation. Compared by code point, not
 * byte length — convert.rs gets this wrong for multi-byte characters.
 */
var ATTACH_PUNCT = '…,:;.!?-‒–—―/|&';

function isBoundary(ch) { return ch !== '' && MORPH_DIVS.indexOf(ch) !== -1; }

// ── segment grouping ─────────────────────────────────────────────────────────

/**
 * Group FLEx morpheme columns into words, KEEPING the per-morpheme segments.
 *
 * This extends core.js groupWordsFromColumns, which joins the form into one
 * string and so throws the form segments away. Keeping them is what lets a
 * column be an alignment slot of any size: word-aligned and morpheme-aligned
 * output are then two projections of the same segment list, not two algorithms.
 *
 * A segment is { bd, form, gloss }:
 *   bd     the boundary character introducing this segment ('' for the first)
 *   form   the morpheme form without its boundary character
 *   gloss  that morpheme's gloss, including any one-to-many continuation parts
 *          folded in (FLEx spreads `follow` `.CMP` over two columns; both
 *          belong to the single morpheme `levo`)
 *
 * @param  {string[]} morphemes  column array for the Morphemes/LexEntries tier
 * @param  {string[]} lexGlosses column array for the LexGloss tier
 * @param  {number}   startIdx   index of the first data column
 * @returns {Array<{segments: Array, startCol: number, endCol: number}>}
 */
function groupSegments(morphemes, lexGlosses, startIdx) {
    var words = [];
    var cur   = null;
    var N     = morphemes.length;

    function flush() { if (cur) words.push(cur); cur = null; }

    for (var col = startIdx; col < N; col++) {
        var m = (morphemes[col]  || '').trim();
        var g = (lexGlosses[col] || '').trim();

        if (m !== '') {
            var bd     = isBoundary(m.charAt(0)) ? m.charAt(0) : '';
            var form   = bd ? m.substring(1) : m;

            if (bd !== '') {
                // Suffix, enclitic or reduplicant: another segment of this word.
                if (cur) {
                    cur.segments.push({ bd: bd, form: form, gloss: g });
                    cur.endCol = col;
                }
                continue;
            }

            // No boundary character: this starts a new word.
            flush();
            cur = { segments: [{ bd: '', form: form, gloss: g }],
                    startCol: col, endCol: col };

            if (g === '') {
                // The morpheme's own gloss column is empty, so the following
                // empty-morpheme columns are one-to-many continuation slots:
                // their glosses belong to THIS morpheme, not to new ones.
                while (col + 1 < N && (morphemes[col + 1] || '').trim() === '') {
                    col++;
                    var contG = (lexGlosses[col] || '').trim();
                    if (contG !== '') cur.segments[0].gloss += contG;
                    cur.endCol = col;
                }
            }
        } else {
            // Empty morpheme column with the previous gloss already satisfied:
            // a zero-morpheme slot that gets its own alignment column.
            flush();
            if (g !== '') {
                words.push({ segments: [{ bd: '', form: '', gloss: g }],
                             startCol: col, endCol: col });
            }
        }
    }

    flush();
    return words;
}

/**
 * Fold a word that is bare punctuation into the preceding word's last segment.
 * `ze` followed by `:` becomes the single form `ze:` with the gloss untouched.
 * @param {Array} words  mutated in place
 */
function handleStandalonePunctuation(words) {
    for (var i = 1; i < words.length; i++) {
        var w = words[i];
        if (w.segments.length !== 1) continue;
        var s = w.segments[0];
        if (s.gloss !== '' || s.bd !== '') continue;
        // Array.from gives code points, so U+2026 and the dashes match.
        if (Array.from(s.form).length !== 1 || ATTACH_PUNCT.indexOf(s.form) === -1) continue;

        var prev = words[i - 1];
        prev.segments[prev.segments.length - 1].form += s.form;
        prev.endCol = w.endCol;
        words.splice(i, 1);
        i--;
    }
}

// ── projections ──────────────────────────────────────────────────────────────

/** Word-aligned form: every segment of the word joined into one cell. */
function joinForm(segments) {
    return segments.map(function (s) { return s.bd + s.form; }).join('');
}

/**
 * Word-aligned gloss. The first segment contributes its gloss bare; later
 * segments contribute their boundary character plus gloss, so an empty-glossed
 * affix still leaves its boundary visible. Matches core.js glossParts.join('').
 */
function joinGloss(segments) {
    return segments.map(function (s, i) {
        return i === 0 ? s.gloss : s.bd + s.gloss;
    }).join('');
}

/**
 * Project grouped words onto alignment columns at the requested granularity.
 * Returns { forms: string[], glosses: string[], spans: Array<[start,end]> }
 * where spans maps each produced column back to its source column range, so
 * per-word tiers (WordGloss, Category) can be aligned to it.
 */
function projectColumns(words, granularity) {
    var forms = [], glosses = [], spans = [];

    words.forEach(function (w) {
        if (granularity === MORPHEME_ALIGNED) {
            w.segments.forEach(function (s, i) {
                // The boundary character leads BOTH cells, which is exactly
                // invariant 1 (column break-character agreement) by construction.
                forms.push(s.bd + s.form);
                glosses.push(s.bd + s.gloss);
                // Only the first segment of a word carries the word-level tiers.
                spans.push(i === 0 ? [w.startCol, w.endCol] : null);
            });
        } else {
            forms.push(joinForm(w.segments));
            glosses.push(joinGloss(w.segments));
            spans.push([w.startCol, w.endCol]);
        }
    });

    return { forms: forms, glosses: glosses, spans: spans };
}

// ── model ────────────────────────────────────────────────────────────────────

/**
 * An IgtExample is a tier × column grid plus free-translation lines.
 *   tiers:     string[]      role of each row
 *   cells:     string[][]    cells[tierIdx][colIdx]
 *   freeLines: string[]
 *   lineNum:   string|null
 * A column is an alignment slot: a word, a morpheme, or part of a word.
 * Nothing downstream may assume which.
 */
function makeModel(tiers, cells, freeLines, lineNum) {
    return { tiers: tiers, cells: cells,
             freeLines: freeLines || [], lineNum: lineNum || null };
}

function colCount(model) { return model.cells.length ? model.cells[0].length : 0; }

/** True for rows subject to the interlinear invariants (i.e. not Free). */
function isInterlinearTier(role) { return role !== ROLE_FREE; }

/**
 * Build a model from one parsed FLEx block.
 * Tier roles come from the FLEx labels; tiers with no data are dropped.
 */
function modelFromBlock(block, granularity) {
    var lineTypes = block.lineTypes, colArrays = block.colArrays;
    var morphIdx = -1, glossIdx = -1, wordGlossIdx = -1, catIdx = -1, wordIdx = -1;

    for (var t = 0; t < lineTypes.length; t++) {
        var lt = lineTypes[t];
        if ((lt === 'Morphemes' || lt === 'LexEntries') && morphIdx     < 0) morphIdx     = t;
        if (lt === 'LexGloss'                          && glossIdx     < 0) glossIdx     = t;
        if (lt === 'WordGloss'                         && wordGlossIdx < 0) wordGlossIdx = t;
        if (lt === 'WordCat'                           && catIdx       < 0) catIdx       = t;
        if (lt === 'Word'                              && wordIdx      < 0) wordIdx      = t;
    }
    var formIdx = morphIdx >= 0 ? morphIdx : wordIdx;
    if (formIdx < 0) return null;

    var formArr  = colArrays[formIdx];
    var glossArr = glossIdx >= 0 ? colArrays[glossIdx] : [];

    // Skip the tier label, and an example number if FLEx put one in column 1.
    var dataStart = 1;
    if (/^\d+$/.test(formArr[dataStart] || '')) dataStart++;

    var words = groupSegments(formArr, glossArr, dataStart);
    handleStandalonePunctuation(words);

    var proj = projectColumns(words, granularity);
    var n    = proj.forms.length;

    var tiers = [], cells = [];

    // The form tier keeps the role FLEx gave it, so the rendered paragraph
    // style says whether this row is surface words or a morpheme breakdown.
    tiers.push(morphIdx >= 0 ? ROLE_MORPHEMES : ROLE_VERNACULAR);
    cells.push(proj.forms);

    if (glossIdx >= 0) { tiers.push(ROLE_GLOSS); cells.push(proj.glosses); }

    // Per-word tiers: collect the non-empty source cells inside each column's
    // span. core.js emits a placeholder here instead; this renders them properly.
    function perWordTier(srcIdx) {
        var src = colArrays[srcIdx], out = [];
        for (var c = 0; c < n; c++) {
            var span = proj.spans[c];
            if (!span) { out.push(''); continue; }
            var parts = [];
            for (var k = span[0]; k <= span[1] && k < src.length; k++) {
                var v = (src[k] || '').trim();
                if (v !== '') parts.push(v);
            }
            out.push(parts.join('.'));
        }
        return out;
    }

    if (wordGlossIdx >= 0) { tiers.push(ROLE_WORDGLOSS); cells.push(perWordTier(wordGlossIdx)); }
    if (catIdx       >= 0) { tiers.push(ROLE_CATEGORY);  cells.push(perWordTier(catIdx)); }
    if (morphIdx >= 0 && wordIdx >= 0) {
        // Both a surface-word tier and a morpheme tier are present: keep the
        // surface words as their own row above the breakdown.
        tiers.unshift(ROLE_VERNACULAR);
        cells.unshift(perWordTier(wordIdx));
    }

    // Drop tiers that ended up with no data at all.
    for (var d = tiers.length - 1; d >= 0; d--) {
        var any = cells[d].some(function (v) { return v !== ''; });
        if (!any) { tiers.splice(d, 1); cells.splice(d, 1); }
    }

    return makeModel(tiers, cells, block.freeLines, block.lineNum);
}

/**
 * Does this text carry FLEx tier labels?
 *
 * It matters because the FLEx parser treats column 0 of every row as a tier
 * label. Plain TSV -- a hand-built table, or this add-in's own TSV pasted back
 * in -- has no label there, so running it through the FLEx path would silently
 * swallow the first cell of every row.
 */
function looksLikeFlex(raw) {
    var labels = ['Word', 'Morphemes', 'LexEntries', 'LexGloss', 'WordGloss', 'WordCat'];
    var lines = String(raw).replace(/\r\n?/g, '\n').split('\n');
    for (var i = 0; i < lines.length; i++) {
        var l = lines[i].replace(/Lex\. Entries/g, 'LexEntries').replace(/Lex\. Gloss/g, 'LexGloss')
             .replace(/Word Gloss/g, 'WordGloss').replace(/Word Cat\./g, 'WordCat');
        var first = (l.indexOf('\t') !== -1 ? l.split('\t') : l.split(/\s+/))
            .filter(function (x) { return x.trim() !== ''; })[0];
        if (first === undefined) continue;
        first = first.trim();
        if (labels.indexOf(first) !== -1) return true;
        if (/^Free\b/i.test(first)) return true;
    }
    return false;
}

/** Build a model from plain TSV: one row per tier, roles assigned positionally. */
function modelFromTsv(raw) {
    var lines = String(raw).replace(/\r\n?/g, '\n').split('\n');
    var roles = [ROLE_VERNACULAR, ROLE_GLOSS, ROLE_WORDGLOSS, ROLE_CATEGORY];
    var tiers = [], cells = [], free = [], maxCols = 0;

    lines.forEach(function (l) {
        if (l.trim() === '') return;
        if (l.indexOf('\t') === -1) { free.push(l.trim()); return; }
        var cols = l.split('\t').map(function (c) { return c.trim(); });
        tiers.push(roles[Math.min(cells.length, roles.length - 1)]);
        cells.push(cols);
        if (cols.length > maxCols) maxCols = cols.length;
    });
    if (!cells.length) return null;
    cells.forEach(function (row) {
        while (row.length < maxCols) row.push('');
    });
    return makeModel(tiers, cells, free, null);
}

/**
 * Parse raw text into one model per block, choosing the FLEx path or the plain
 * TSV path by inspection.
 */
function buildModels(raw, granularity) {
    if (!looksLikeFlex(raw)) {
        var m = modelFromTsv(raw);
        return m ? [m] : [];
    }
    return core.parseFLExBlocks(raw)
        .map(function (b) { return modelFromBlock(b, granularity || WORD_ALIGNED); })
        .filter(function (m) { return m !== null; });
}

/** Render a model back to TSV: one row per tier, then the free lines. */
function modelToTsv(model) {
    var rows = model.cells.map(function (row) { return row.join('\t'); });
    if (model.freeLines.length) rows.push(model.freeLines.join(' / '));
    return rows.join('\n');
}

// ── column editing ───────────────────────────────────────────────────────────

/** Concatenate columns first..last into one. Free rows are left alone. */
function mergeColumns(model, first, last) {
    if (last <= first) return false;
    model.cells.forEach(function (row, t) {
        if (!isInterlinearTier(model.tiers[t])) return;
        row.splice(first, last - first + 1, row.slice(first, last + 1).join(''));
    });
    // Free rows are prose, not aligned slots, but their length must stay in
    // step with the grid. Empty cells are dropped so the join cannot leave
    // stray double spaces.
    model.cells.forEach(function (row, t) {
        if (isInterlinearTier(model.tiers[t])) return;
        var joined = row.slice(first, last + 1).filter(function (v) {
            return v !== '';
        }).join(' ');
        row.splice(first, last - first + 1, joined);
    });
    return true;
}

/**
 * Split column `col` at the nth (1-based) segmentable boundary in each
 * interlinear cell. The boundary character goes to the START of the right-hand
 * piece, which satisfies invariant 1 by construction.
 *
 * `.` and `:` are Leipzig rule 4 one-to-many markers inside a single gloss and
 * are never split points.
 *
 * Returns { ok, shortTiers } — ok is false when some tier had fewer boundaries
 * than asked for; that cell stays whole on the left and the caller surfaces a
 * warning rather than guessing where the morpheme break should have been.
 */
function splitColumn(model, col, occurrence) {
    occurrence = occurrence || 1;
    var shortTiers = [];

    var pieces = model.cells.map(function (row, t) {
        if (!isInterlinearTier(model.tiers[t])) return [row[col], row[col]];
        var cell = row[col] || '', seen = 0, at = -1;
        // Start at 1: a leading boundary belongs to this column, not a split.
        for (var i = 1; i < cell.length; i++) {
            if (isBoundary(cell.charAt(i))) {
                seen++;
                if (seen === occurrence) { at = i; break; }
            }
        }
        if (at < 0) { shortTiers.push(model.tiers[t]); return [cell, '']; }
        return [cell.substring(0, at), cell.substring(at)];
    });

    model.cells.forEach(function (row, t) {
        row.splice(col, 1, pieces[t][0], pieces[t][1]);
    });

    return { ok: shortTiers.length === 0, shortTiers: shortTiers };
}

function insertColumn(model, at) {
    model.cells.forEach(function (row) { row.splice(at, 0, ''); });
}

function deleteColumn(model, at) {
    model.cells.forEach(function (row) { row.splice(at, 1); });
}

// ── Leipzig checks ───────────────────────────────────────────────────────────

function leadChar(s)  { return s && isBoundary(s.charAt(0))            ? s.charAt(0) : ''; }
function trailChar(s) { return s && isBoundary(s.charAt(s.length - 1)) ? s.charAt(s.length - 1) : ''; }

/** Count only segmentable boundaries: `.` and `:` are rule 4, not rule 2. */
function countBoundaries(s) {
    var n = 0;
    for (var i = 0; i < s.length; i++) if (isBoundary(s.charAt(i))) n++;
    return n;
}

/** Rows subject to the invariants, as [tierIndex, role] pairs. */
function interlinearRows(model) {
    var out = [];
    model.tiers.forEach(function (role, t) {
        if (isInterlinearTier(role)) out.push(t);
    });
    return out;
}

/**
 * Check a model against the two invariants and the Leipzig conventions that can
 * be decided mechanically. Returns warnings; never mutates.
 *
 * Grammatical glosses are recognised structurally (core.js isGramGloss: all-caps
 * or digit-initial). There is deliberately NO allow-list of approved
 * abbreviations — linguists coin their own constantly, and the published Leipzig
 * list is examples, not a vocabulary.
 */
function checkExample(model) {
    var warnings = [];
    var rows = interlinearRows(model);
    var n = colCount(model);

    function warn(code, col, tier, message) {
        warnings.push({ code: code, col: col, tier: tier, message: message });
    }

    for (var c = 0; c < n; c++) {
        var leads = [], trails = [], nonEmpty = [];

        rows.forEach(function (t) {
            var cell = model.cells[t][c] || '';
            if (cell !== '') nonEmpty.push(t);
            leads.push({ t: t, ch: leadChar(cell), empty: cell === '' });
            trails.push({ t: t, ch: trailChar(cell), empty: cell === '' });

            if (cell.indexOf(' ') !== -1) {
                warn('space-in-cell', c, model.tiers[t],
                    'Interlinear cells may not contain spaces; use "." or "_".');
            }
            var opens = (cell.match(/</g) || []).length;
            var closes = (cell.match(/>/g) || []).length;
            if (opens !== closes) {
                warn('unmatched-angle', c, model.tiers[t],
                    'Unmatched infix bracket (Leipzig rule 8).');
            }
        });

        // Invariant 1, at each end independently.
        [['lead', leads], ['trail', trails]].forEach(function (pair) {
            var end = pair[0], list = pair[1];
            var present = list.filter(function (x) { return !x.empty && x.ch !== ''; });
            var absent  = list.filter(function (x) { return !x.empty && x.ch === ''; });
            if (!present.length) return;

            var distinct = [];
            present.forEach(function (x) {
                if (distinct.indexOf(x.ch) === -1) distinct.push(x.ch);
            });
            if (distinct.length > 1) {
                warn('break-char-conflict', c, null,
                    'Cells in this column disagree about the ' + end +
                    'ing break character (' + distinct.join(' vs ') +
                    '); pick one by hand.');
            } else if (absent.length) {
                warn('break-char-missing', c, null,
                    'This column ' + end + 's with "' + distinct[0] +
                    '" on some tiers but not all; every interlinear cell in a ' +
                    'column must agree.');
            }
        });

        // Leipzig rule 2: the form and its gloss must show the same number of
        // segmentable boundaries inside the cell.
        var fIdx = rows[0];
        var gIdx = model.tiers.indexOf(ROLE_GLOSS);
        if (gIdx >= 0 && fIdx !== gIdx) {
            var fc = model.cells[fIdx][c] || '', gc = model.cells[gIdx][c] || '';
            if (fc !== '' && gc !== '' && countBoundaries(fc) !== countBoundaries(gc)) {
                warn('boundary-parity', c, null,
                    'Form "' + fc + '" and gloss "' + gc + '" show a different ' +
                    'number of morpheme breaks (Leipzig rule 2).');
            }
        }

        if (nonEmpty.length && nonEmpty.length < rows.length) {
            warn('empty-cell', c, null,
                'Some interlinear tiers are empty in this column.');
        }
    }

    return warnings;
}

/**
 * Invariant-1 auto-fix: give every non-empty interlinear cell in the column the
 * column's agreed leading and trailing break characters. Returns false without
 * touching anything when the cells disagree about which character it should be —
 * that needs a human decision.
 */
function fixColumnBreakChars(model, col) {
    var rows = interlinearRows(model);
    var changed = false;

    [['lead', leadChar], ['trail', trailChar]].forEach(function (pair) {
        var end = pair[0], get = pair[1];
        var distinct = [];
        rows.forEach(function (t) {
            var ch = get(model.cells[t][col] || '');
            if (ch !== '' && distinct.indexOf(ch) === -1) distinct.push(ch);
        });
        if (distinct.length !== 1) return;          // absent, or conflicting
        var ch = distinct[0];
        rows.forEach(function (t) {
            var cell = model.cells[t][col] || '';
            if (cell === '' || get(cell) === ch) return;
            model.cells[t][col] = end === 'lead' ? ch + cell : cell + ch;
            changed = true;
        });
    });

    return changed;
}

/** Replace spaces inside interlinear cells. Returns how many cells changed. */
function fixCellSpaces(model, replacement) {
    replacement = replacement === undefined ? '.' : replacement;
    var fixed = 0;
    interlinearRows(model).forEach(function (t) {
        model.cells[t].forEach(function (cell, c) {
            if (cell.indexOf(' ') === -1) return;
            model.cells[t][c] = cell.split(' ').filter(function (p) {
                return p !== '';
            }).join(replacement);
            fixed++;
        });
    });
    return fixed;
}

// ── wrapping ────────────────────────────────────────────────────────────────

/**
 * Flag columns a wrap line must not start on.
 *
 * A column whose interlinear cells begin with a boundary character is a
 * continuation of the column before it, so breaking there would split a word
 * across two lines. This is the whole reason a morpheme-aligned example still
 * wraps at word boundaries even though nothing in the engine knows what a word
 * is. Bare-punctuation columns get the same treatment.
 */
function noBreakFlags(model) {
    var rows = interlinearRows(model);
    var n = colCount(model);
    var flags = [];

    for (var c = 0; c < n; c++) {
        var flag = false;
        for (var r = 0; r < rows.length && !flag; r++) {
            var cell = model.cells[rows[r]][c] || '';
            if (cell === '') continue;
            if (leadChar(cell) !== '') flag = true;
            else if (Array.from(cell).length === 1 && ATTACH_PUNCT.indexOf(cell) !== -1) flag = true;
        }
        flags.push(c > 0 && flag);
    }
    return flags;
}

/**
 * Greedy first-fit wrap. Returns the starting column index of each wrap line.
 *
 * Recomputed from the full column list on every re-wrap, never diffed against
 * the existing layout. That is what makes pulling columns back up after a
 * margin, font or content change fall out for free, with no separate code path
 * and no limit on the number of wrap lines. Do not turn this into an
 * incremental differ.
 *
 * @param {number[]}  colWidths     rendered width of each column, in points
 * @param {boolean[]} noBreakBefore from noBreakFlags()
 * @param {number}    availWidth    usable text width, in points
 * @param {number}    firstIndent   indent of the first wrap line
 * @param {number}    contIndent    indent of every later wrap line
 * @returns {number[]}
 */
function computeWrapLines(colWidths, noBreakBefore, availWidth, firstIndent, contIndent) {
    var n = colWidths.length;
    if (n === 0) return [];

    firstIndent = firstIndent || 0;
    contIndent  = contIndent  || 0;

    var lines = [];
    var cur = 0;
    var curW = colWidths[0];

    for (var i = 1; i < n; i++) {
        var budget = availWidth - (lines.length === 0 ? firstIndent : contIndent);

        if (curW + colWidths[i] <= budget) { curW += colWidths[i]; continue; }

        // Back up past any column that must not start a line.
        var k = i;
        while (k > cur && noBreakBefore[k]) k--;
        // If backing up would leave the line empty, break here after all:
        // an over-wide single unit has to overflow and wrap inside its cell.
        if (k === cur) k = i;

        lines.push(cur);
        cur = k;
        curW = 0;
        for (var j = cur; j <= i; j++) curW += colWidths[j];
    }

    lines.push(cur);
    return lines;
}

/** Split a column list into per-wrap-line ranges: [[start, endInclusive], …]. */
function wrapRanges(lineStarts, n) {
    return lineStarts.map(function (s, i) {
        return [s, (i + 1 < lineStarts.length ? lineStarts[i + 1] : n) - 1];
    });
}

module.exports = {
    MORPH_DIVS: MORPH_DIVS, ATTACH_PUNCT: ATTACH_PUNCT,
    ROLE_VERNACULAR: ROLE_VERNACULAR, ROLE_MORPHEMES: ROLE_MORPHEMES,
    ROLE_GLOSS: ROLE_GLOSS, ROLE_WORDGLOSS: ROLE_WORDGLOSS,
    ROLE_CATEGORY: ROLE_CATEGORY, ROLE_FREE: ROLE_FREE,
    WORD_ALIGNED: WORD_ALIGNED, MORPHEME_ALIGNED: MORPHEME_ALIGNED,
    isBoundary: isBoundary, isGramGloss: core._isGramGloss,
    groupSegments: groupSegments,
    handleStandalonePunctuation: handleStandalonePunctuation,
    joinForm: joinForm, joinGloss: joinGloss, projectColumns: projectColumns,
    makeModel: makeModel, colCount: colCount, isInterlinearTier: isInterlinearTier,
    modelFromBlock: modelFromBlock, buildModels: buildModels,
    looksLikeFlex: looksLikeFlex, modelFromTsv: modelFromTsv, modelToTsv: modelToTsv,
    mergeColumns: mergeColumns, splitColumn: splitColumn,
    insertColumn: insertColumn, deleteColumn: deleteColumn,
    leadChar: leadChar, trailChar: trailChar, countBoundaries: countBoundaries,
    interlinearRows: interlinearRows, checkExample: checkExample,
    fixColumnBreakChars: fixColumnBreakChars, fixCellSpaces: fixCellSpaces,
    noBreakFlags: noBreakFlags, computeWrapLines: computeWrapLines,
    wrapRanges: wrapRanges,
};
