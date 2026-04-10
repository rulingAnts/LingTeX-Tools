/**
 * LingTeX Tools — shared core logic
 *
 * Based on the original TeXstudio macro code by Moss Doerksen (SIL PNG),
 * used by permission. JavaScript and Rust ports by Seth Johnston.
 *
 * Platform-agnostic JavaScript module used by:
 *   - the web app  (webapp/)
 *   - browser extensions  (extension/)
 *
 * The TeXstudio macros (texstudio/) inline this logic directly
 * because TeXstudio's scripting environment does not support modules.
 *
 * Exports (CommonJS + browser global):
 *   parseFLExBlock(rawText)  → parsed example object
 *   renderFLEx(parsed, opts) → LaTeX string
 *   parsePhonologyAssistant(rawText) → array of entry objects
 *   renderPhonologyAssistant(entries, opts) → LaTeX string
 *   wrapCommand(text, cmd)   → LaTeX string
 */

(function (root, factory) {
    if (typeof module !== 'undefined' && module.exports) {
        module.exports = factory();           // CommonJS / Node
    } else {
        root.LingTeXCore = factory();         // browser global
    }
}(typeof self !== 'undefined' ? self : this, function () {

    // ── constants ────────────────────────────────────────────────────────────

    var SENTINEL   = '\u2591';    // ░  internal morpheme-boundary sentinel
    var MORPH_DIVS = '-=~<>';

    // ── low-level helpers ────────────────────────────────────────────────────

    function stripInvisible(s) {
        return s.replace(/[\u200E\u200F\u202A-\u202E]/g, '');
    }

    function escapeLatex(s) {
        var ph = [];
        var M  = '\x00PH';
        s = s.replace(/\\[a-zA-Z]+\{[^}]*\}/g, function (m) {
            ph.push(m); return M + (ph.length - 1) + '\x00';
        });
        s = s.replace(/([%$#&_{}])/g, '\\$1');
        s = s.replace(new RegExp(M + '(\\d+)\x00', 'g'),
            function (_, i) { return ph[Number(i)]; });
        return s;
    }

    function isGramGloss(s) {
        if (/^[A-Z\u014a\u014b]\.$/.test(s)) return false;
        return /^[^\w]*([0-9A-Z]+|[0-9]\w+)[^\w]*$/.test(s);
    }

    function wrapGlosses(token, glCmd) {
        if (!token) return '';
        var parts = [];
        var cur   = '';
        for (var i = 0; i < token.length; i++) {
            var ch = token[i];
            if (MORPH_DIVS.indexOf(ch) !== -1 || ch === '.') {
                if (cur) {
                    parts.push(glCmd && isGramGloss(cur)
                        ? glCmd + '{' + cur.toLowerCase() + '}'
                        : escapeLatex(cur));
                    cur = '';
                }
                parts.push(ch);
            } else {
                cur += ch;
            }
        }
        if (cur) {
            parts.push(glCmd && isGramGloss(cur)
                ? glCmd + '{' + cur.toLowerCase() + '}'
                : escapeLatex(cur));
        }
        return parts.join('');
    }

    function massageLine(line) {
        line = line.replace(/Lex\. Entries/g, 'LexEntries');
        line = line.replace(/Lex\. Gloss/g,  'LexGloss');
        line = line.replace(/Word Gloss/g,   'WordGloss');
        line = line.replace(/Word Cat\./g,   'WordCat');
        line = stripInvisible(line);

        var sp = line.search(/\s/);
        if (sp < 0) return line;
        var label = line.substring(0, sp + 1);
        var body  = line.substring(sp + 1);

        body = body.replace(/- /g,  SENTINEL + '-' + SENTINEL);
        body = body.replace(/ -/g,  SENTINEL + '-' + SENTINEL);
        body = body.replace(/ </g,  SENTINEL + '<' + SENTINEL);
        body = body.replace(/> /g,  SENTINEL + '>' + SENTINEL);
        body = body.replace(/= /g,  SENTINEL + '=' + SENTINEL);
        body = body.replace(/ =/g,  SENTINEL + '=' + SENTINEL);
        body = body.replace(/ ~/g,  SENTINEL + '~' + SENTINEL);
        body = body.replace(/~ /g,  SENTINEL + '~' + SENTINEL);

        body = body.replace(/ \./g, '.').replace(/ \u2026/g, '\u2026');
        body = body.replace(/ ,/g,  ',').replace(/ \?/g, '?');
        body = body.replace(/ !/g,  '!').replace(/ :/g,  ':').replace(/ ;/g, ';');
        body = body.replace(/\( /g, '(').replace(/ \)/g, ')');
        body = body.replace(/\[ /g, '[').replace(/ \]/g, ']');

        return label + body;
    }

    // ── FLEx parser ──────────────────────────────────────────────────────────

    /**
     * Parse the first interlinear block from raw FLEx clipboard text.
     * @param  {string} raw
     * @returns {{ lineTypes: string[], lineArrays: string[][], freeLines: string[], lineNum: string|null }}
     */
    function parseFLExBlock(raw) {
        var text = raw.replace(/\r\n?/g, '\n').replace(/\t/g, ' ');
        var blockEnd = text.indexOf('\n\n');
        if (blockEnd >= 0) text = text.substring(0, blockEnd);

        var lineTypes  = [];
        var lineArrays = [];
        var freeLines  = [];
        var lineNum    = null;
        var seenFree   = false;

        var rawLines = text.split('\n')
            .map(function (l) { return String(l).replace(/\s+$/, ''); })
            .filter(function (l) { return l.replace(/^\s+/, '') !== ''; });

        for (var i = 0; i < rawLines.length; i++) {
            var l = rawLines[i];

            if (lineNum === null) {
                var numMatch = l.trim().match(/^(\d+(?:\.\d+)?)(\s|$)/);
                if (numMatch) {
                    lineNum = numMatch[1];
                    var remainder = l.trim().substring(numMatch[0].length).trim();
                    if (remainder === '') continue;
                    l = remainder;
                }
            }

            var lClean = stripInvisible(l).trim();

            if (/^Free\b/i.test(lClean)) {
                seenFree = true;
                var ft = lClean.replace(/^Free\b(\s+[A-Za-z]{2,8})?\s*/i, '').trim();
                if (ft) freeLines.push(ft);
                continue;
            }

            if (seenFree && /^[A-Za-z]{2,8}(\s|$)/.test(lClean)) {
                var ft2 = lClean.replace(/^[A-Za-z]{2,8}\s*/, '').trim();
                if (ft2) freeLines.push(ft2);
                continue;
            }

            l = massageLine(stripInvisible(l));
            var toks = l.trim().split(/\s+/).filter(function (t) { return t !== ''; });
            if (toks.length === 0) continue;

            lineTypes.push(toks[0]);
            lineArrays.push(toks);
        }

        return { lineTypes: lineTypes, lineArrays: lineArrays,
                 freeLines: freeLines, lineNum: lineNum };
    }

    // ── FLEx renderer ────────────────────────────────────────────────────────

    /**
     * Render a parsed FLEx block to a langsci-gb4e \gll block.
     * @param  {object} ex       Result of parseFLExBlock()
     * @param  {object} [opts]
     * @param  {string} [opts.glCmd='\\gl']          Gloss abbreviation command
     * @param  {string} [opts.txtrefCmd='\\txtref']  Source-reference command ('' to omit)
     * @param  {string} [opts.txtrefPrefix='TXT:']   Prefix inside \txtref{}
     * @param  {boolean} [opts.wrapExe=true]         Wrap in \begin{exe}\ex...\end{exe}
     * @returns {string}
     */
    function renderFLEx(ex, opts) {
        opts = opts || {};
        var glCmd        = opts.glCmd        !== undefined ? opts.glCmd        : '\\gl';
        var txtrefCmd    = opts.txtrefCmd    !== undefined ? opts.txtrefCmd    : '\\txtref';
        var txtrefPrefix = opts.txtrefPrefix !== undefined ? opts.txtrefPrefix : 'TXT:';
        var wrapExe      = opts.wrapExe      !== undefined ? opts.wrapExe      : true;

        var lineTypes  = ex.lineTypes;
        var lineArrays = ex.lineArrays;
        var freeLines  = ex.freeLines;
        var lineNum    = ex.lineNum;
        var n          = lineTypes.length;

        var morphIdx     = -1;
        var lexGlossIdx  = -1;
        var wordGlossIdx = -1;

        for (var t = 0; t < n; t++) {
            var lt = lineTypes[t];
            if ((lt === 'Morphemes' || lt === 'LexEntries') && morphIdx    < 0) morphIdx    = t;
            if (lt === 'LexGloss'                           && lexGlossIdx < 0) lexGlossIdx = t;
            if (lt === 'WordGloss'                          && wordGlossIdx < 0) wordGlossIdx = t;
        }
        if (morphIdx < 0) {
            for (var t2 = 0; t2 < n; t2++) {
                if (lineTypes[t2] === 'Word') { morphIdx = t2; break; }
            }
        }
        if (morphIdx < 0) return '% (no recognisable tier lines — check labels)';

        var primaryArr = lineArrays[morphIdx];
        var dataStart  = 1;
        if (/^\d+$/.test(primaryArr[dataStart] || '')) dataStart++;

        var tier1          = [];
        var tier2          = [];
        var tier3          = [];
        var lexGlossOffset = 0;
        var FLOAT_PUNCT    = '-\u2012\u2013\u2014\u2015/|&\u2026...';

        for (var w = dataStart; w < primaryArr.length; w++) {
            var wt = primaryArr[w];

            if (wt.length === 1 && FLOAT_PUNCT.indexOf(wt) !== -1) {
                tier1.push(wt);
                if (lexGlossIdx  >= 0) tier2.push('{}');
                if (wordGlossIdx >= 0) tier3.push('{}');
                continue;
            }

            tier1.push(escapeLatex(wt.split(SENTINEL).join('')));

            if (lexGlossIdx >= 0) {
                var lArr = lineArrays[lexGlossIdx];
                if (wt.indexOf(SENTINEL) !== -1) {
                    var parts     = wt.split(SENTINEL);
                    var partCount = parts.length - 1;
                    var gParts    = [];
                    for (var y = 0; y < parts.length; y++) {
                        var part = parts[y];
                        if (part === '') continue;
                        if (MORPH_DIVS.indexOf(part) !== -1) {
                            gParts.push(part);
                            lexGlossOffset--;
                        } else {
                            var gi  = (w - dataStart) + lexGlossOffset + y;
                            var raw = lArr[gi + dataStart] || '';
                            gParts.push(wrapGlosses(raw, glCmd));
                        }
                    }
                    tier2.push(gParts.join(''));
                    lexGlossOffset += partCount;
                } else {
                    var gi2  = (w - dataStart) + lexGlossOffset;
                    var raw2 = lArr[gi2 + dataStart] || '';
                    tier2.push(wrapGlosses(raw2, glCmd));
                }
            }

            if (wordGlossIdx >= 0) {
                var wgArr = lineArrays[wordGlossIdx];
                var wi    = w - dataStart;
                tier3.push(wrapGlosses(wgArr[wi + dataStart] || '', glCmd));
            }
        }

        var tierCount = 1
            + (lexGlossIdx  >= 0 ? 1 : 0)
            + (wordGlossIdx >= 0 ? 1 : 0);
        var gCmd   = 'g' + Array(tierCount + 1).join('l');
        var indent = Array(gCmd.length + 2).join(' ');

        var lines = [];
        lines.push('\\' + gCmd + ' ' + tier1.join(' ') + ' \\\\');
        if (lexGlossIdx  >= 0) lines.push(indent + tier2.join(' ') + ' \\\\');
        if (wordGlossIdx >= 0) lines.push(indent + tier3.join(' ') + ' \\\\');

        var txtref = '';
        if (txtrefCmd && lineNum) {
            txtref = ' ' + txtrefCmd + '{' + txtrefPrefix + lineNum + '}';
        }
        if (freeLines.length > 0) {
            lines.push("\\glt '" + freeLines.map(escapeLatex).join(' / ') + "'" + txtref);
        } else if (txtref) {
            lines.push('\\glt' + txtref);
        }

        var body = lines.join('\n');
        if (!wrapExe) return body;

        return '\n% Interlinear example\n\n'
             + '\\begin{exe}\n'
             + '\\ex % \\label{ex:KEY}\n'
             + body + '\n'
             + '\\end{exe}\n';
    }

    // ── Multi-block FLEx support ─────────────────────────────────────────────

    /**
     * Parse all interlinear blocks from raw FLEx clipboard text.
     * Blocks are separated by one or more blank lines.
     * Returns an array of parsed block objects (result of parseFLExBlock).
     * Blocks with no recognisable tier lines are silently dropped.
     * @param  {string} raw
     * @returns {Array<{ lineTypes: string[], lineArrays: string[][], freeLines: string[], lineNum: string|null }>}
     */
    function parseFLExBlocks(raw) {
        var text = raw.replace(/\r\n?/g, '\n');

        // Phase 1: split on blank lines (including whitespace-only lines)
        var chunks = text.split(/\n[ \t]*\n+/);
        chunks = chunks.filter(function (c) { return c.trim() !== ''; });

        // Phase 2: if still only one chunk, blocks may not be separated by blank
        // lines at all — split on numbered-example boundaries instead.
        if (chunks.length <= 1) {
            var lines = text.split('\n');
            var groups = [[]];
            for (var i = 0; i < lines.length; i++) {
                var stripped = stripInvisible(lines[i]).trim();
                if (groups[groups.length - 1].length > 0 &&
                        /^\d+(?:\.\d+)?(\s|$)/.test(stripped)) {
                    groups.push([]);
                }
                groups[groups.length - 1].push(lines[i]);
            }
            chunks = groups.map(function (g) { return g.join('\n'); });
        }

        var blocks = [];
        for (var j = 0; j < chunks.length; j++) {
            var chunk = chunks[j].trim();
            if (!chunk) continue;
            var parsed = parseFLExBlock(chunk);
            if (parsed.lineTypes.length > 0) blocks.push(parsed);
        }
        return blocks;
    }

    /**
     * Render multiple parsed FLEx blocks into a langsci-gb4e xlist environment.
     * Each block becomes one \ex sub-item inside \begin{xlist}...\end{xlist}.
     * @param  {Array}  blocks  Result of parseFLExBlocks()
     * @param  {object} [opts]  Same options as renderFLEx(); wrapExe is ignored here
     * @returns {string}
     */
    function renderFLExXlist(blocks, opts) {
        opts = opts || {};
        var subOpts = {
            glCmd:        opts.glCmd,
            txtrefCmd:    opts.txtrefCmd,
            txtrefPrefix: opts.txtrefPrefix,
            wrapExe:      false
        };
        var items = blocks.map(function (block) {
            var body = renderFLEx(block, subOpts).trim();
            var indented = body.split('\n').map(function (l) { return '    ' + l; }).join('\n');
            return '\\ex % \\label{ex:KEY}\n' + indented;
        });
        return '\n% Interlinear examples\n\n'
             + '\\begin{exe}\n'
             + '\\ex % \\label{ex:KEY}\n'
             + '\\begin{xlist}\n'
             + items.join('\n\n') + '\n'
             + '\\end{xlist}\n'
             + '\\end{exe}\n';
    }

    /**
     * Auto-detect single vs. multiple FLEx blocks and render accordingly.
     * - One block  → renderFLEx()   (existing \begin{exe}\ex...\end{exe})
     * - Many blocks → renderFLExXlist()  (\begin{exe}\ex\begin{xlist}...\end{xlist}\end{exe})
     * @param  {Array}  blocks  Result of parseFLExBlocks()
     * @param  {object} [opts]  Same options as renderFLEx()
     * @returns {string}
     */
    function renderFLExAuto(blocks, opts) {
        if (blocks.length === 1) return renderFLEx(blocks[0], opts);
        return renderFLExXlist(blocks, opts);
    }

    // ── FLEx → TSV renderer ──────────────────────────────────────────────────

    /**
     * Render a parsed FLEx block to morpheme-aligned TSV.
     * Each morpheme and morpheme-boundary divider occupy a separate tab-separated
     * column, so the output can be pasted into a spreadsheet for aligned display.
     * No LaTeX escaping or command wrapping — output is plain text.
     * @param  {object} ex  Result of parseFLExBlock()
     * @returns {string}
     */
    function renderFLExTSV(ex) {
        var lineTypes  = ex.lineTypes;
        var lineArrays = ex.lineArrays;
        var freeLines  = ex.freeLines;
        var n          = lineTypes.length;

        var morphIdx     = -1;
        var lexGlossIdx  = -1;
        var wordGlossIdx = -1;

        for (var t = 0; t < n; t++) {
            var lt = lineTypes[t];
            if ((lt === 'Morphemes' || lt === 'LexEntries') && morphIdx    < 0) morphIdx    = t;
            if (lt === 'LexGloss'                           && lexGlossIdx < 0) lexGlossIdx = t;
            if (lt === 'WordGloss'                          && wordGlossIdx < 0) wordGlossIdx = t;
        }
        if (morphIdx < 0) {
            for (var t2 = 0; t2 < n; t2++) {
                if (lineTypes[t2] === 'Word') { morphIdx = t2; break; }
            }
        }
        if (morphIdx < 0) return '(no recognisable tier lines — check labels)';

        var primaryArr     = lineArrays[morphIdx];
        var dataStart      = 1;
        if (/^\d+$/.test(primaryArr[dataStart] || '')) dataStart++;

        var formCols       = [];
        var glossCols      = [];
        var wglossCols     = [];
        var lexGlossOffset = 0;
        var FLOAT_PUNCT    = '-\u2012\u2013\u2014\u2015/|&\u2026...';

        for (var w = dataStart; w < primaryArr.length; w++) {
            var wt = primaryArr[w];

            // Floating punctuation: one column, empty gloss cells
            if (wt.length === 1 && FLOAT_PUNCT.indexOf(wt) !== -1) {
                formCols.push(wt);
                if (lexGlossIdx  >= 0) glossCols.push('');
                if (wordGlossIdx >= 0) wglossCols.push('');
                continue;
            }

            if (wt.indexOf(SENTINEL) !== -1) {
                // Multi-morpheme token: expand into per-morpheme columns
                var parts     = wt.split(SENTINEL);
                var partCount = parts.length - 1;
                var firstMorph = true;

                for (var y = 0; y < parts.length; y++) {
                    var part = parts[y];
                    if (part === '') continue;

                    if (MORPH_DIVS.indexOf(part) !== -1) {
                        // Divider column: same character in both form and gloss rows
                        formCols.push(part);
                        if (lexGlossIdx  >= 0) glossCols.push(part);
                        if (wordGlossIdx >= 0) wglossCols.push('');
                        lexGlossOffset--;
                    } else {
                        // Morpheme form column
                        formCols.push(part);
                        if (lexGlossIdx >= 0) {
                            var lArr = lineArrays[lexGlossIdx];
                            var gi   = (w - dataStart) + lexGlossOffset + y;
                            glossCols.push((lArr[gi + dataStart] || '').split(SENTINEL).join(''));
                        }
                        if (wordGlossIdx >= 0) {
                            if (firstMorph) {
                                var wgArr = lineArrays[wordGlossIdx];
                                var wi    = w - dataStart;
                                wglossCols.push((wgArr[wi + dataStart] || '').split(SENTINEL).join(''));
                                firstMorph = false;
                            } else {
                                wglossCols.push('');
                            }
                        }
                    }
                }
                lexGlossOffset += partCount;

            } else {
                // Unsegmented word: single column
                formCols.push(wt.split(SENTINEL).join(''));
                if (lexGlossIdx >= 0) {
                    var lArr2 = lineArrays[lexGlossIdx];
                    var gi2   = (w - dataStart) + lexGlossOffset;
                    glossCols.push((lArr2[gi2 + dataStart] || '').split(SENTINEL).join(''));
                }
                if (wordGlossIdx >= 0) {
                    var wgArr2 = lineArrays[wordGlossIdx];
                    var wi2    = w - dataStart;
                    wglossCols.push((wgArr2[wi2 + dataStart] || '').split(SENTINEL).join(''));
                }
            }
        }

        var rows = [];
        rows.push(formCols.join('\t'));
        if (lexGlossIdx  >= 0) rows.push(glossCols.join('\t'));
        if (wordGlossIdx >= 0) rows.push(wglossCols.join('\t'));
        if (freeLines.length > 0) rows.push(freeLines.join(' / '));

        return rows.join('\n');
    }

    /**
     * Render multiple parsed FLEx blocks to morpheme-aligned TSV.
     * Multiple blocks are separated by a blank line.
     * @param  {Array} blocks  Result of parseFLExBlocks()
     * @returns {string}
     */
    function renderFLExTSVAuto(blocks) {
        return blocks.map(renderFLExTSV).join('\n\n');
    }

    // ── Phonology Assistant parser/renderer ──────────────────────────────────

    /**
     * Parse tab-separated Phonology Assistant clipboard rows.
     * @param  {string} raw
     * @returns {Array<{word: string, gloss: string, id: string}|{error: string, row: number}>}
     */
    function parsePhonologyAssistant(raw) {
        var lines = raw.split('\n').filter(function (l) { return l.trim() !== ''; });
        var results = [];
        for (var i = 0; i < lines.length; i++) {
            var fields = lines[i].split('\t');
            var rowNum = i + 1;
            if (fields.length < 6) {
                results.push({ error: 'expected 6+ fields, got ' + fields.length, row: rowNum });
            } else if (fields[0].trim() !== '') {
                results.push({ error: 'expected leading tab (first field should be empty)', row: rowNum });
            } else if (!fields[1] || fields[1].trim() === '') {
                results.push({ error: 'word field (column 2) is empty', row: rowNum });
            } else if (!fields[2] || fields[2].trim() === '') {
                results.push({ error: 'gloss field (column 3) is empty', row: rowNum });
            } else if (!/^\d+$/.test(fields[5].trim())) {
                results.push({ error: 'record ID should be numeric, got: [' + fields[5] + ']', row: rowNum });
            } else {
                results.push({
                    word:  fields[1].trim(),
                    gloss: fields[2].trim(),
                    id:    fields[5].trim()
                });
            }
        }
        return results;
    }

    /**
     * Render parsed Phonology Assistant entries to LaTeX rows.
     * @param  {Array}  entries  Result of parsePhonologyAssistant()
     * @param  {object} [opts]
     * @param  {string} [opts.entryCmd='\\exampleentry']  Row command
     * @param  {string} [opts.phonrecCmd='\\phonrec']     Source-ref command ('' to use bare ID)
     * @returns {{ latex: string, errors: string[] }}
     */
    function renderPhonologyAssistant(entries, opts) {
        opts = opts || {};
        var entryCmd  = opts.entryCmd  !== undefined ? opts.entryCmd  : '\\exampleentry';
        var phonrecCmd = opts.phonrecCmd !== undefined ? opts.phonrecCmd : '\\phonrec';

        var lines  = [];
        var errors = [];

        for (var i = 0; i < entries.length; i++) {
            var e = entries[i];
            if (e.error) {
                errors.push('Row ' + e.row + ': ' + e.error);
            } else {
                var ref = phonrecCmd ? phonrecCmd + '{' + e.id + '}' : e.id;
                lines.push(entryCmd + '{}{' + e.word + '}{' + e.gloss + '}{' + ref + '}');
            }
        }

        return { latex: lines.join('\n'), errors: errors };
    }

    // ── Generic TSV row template API ─────────────────────────────────────────
    // Used by the web app and browser extensions for Phonology Assistant,
    // Dekereke exports, and any other tab-separated source.

    /**
     * Parse one tab-separated line into an array of trimmed field values.
     * Index 0 = column 1, index 1 = column 2, etc. (1-based in templates).
     * @param  {string} line
     * @returns {string[]}
     */
    function parseTSVRow(line) {
        return line.split('\t').map(function (f) { return f.trim(); });
    }

    /**
     * Apply a row template to an array of TSV field values.
     *
     * Supported placeholders (all 1-based, missing columns → empty string):
     *   $COLn   — column n by position, e.g. $COL1, $COL3
     *   $WORD   — convenience alias for column 2  (Phonology Assistant word field)
     *   $GLOSS  — convenience alias for column 3  (Phonology Assistant gloss field)
     *   $ID     — convenience alias for column 6  (Phonology Assistant record ID)
     *
     * Named aliases are resolved first so they cannot be partially shadowed by $COLn.
     *
     * @param  {string}   tmpl    e.g. '\\exampleentry{}{$WORD}{$GLOSS}{\\phonrec{$ID}}'
     *                        or  '\\item $COL2 — $COL3'
     * @param  {string[]} fields  Result of parseTSVRow()
     * @returns {string}
     */
    function applyRowTemplate(tmpl, fields) {
        return tmpl
            .replace(/\$WORD/g,           fields[1] || '')   // col 2
            .replace(/\$GLOSS/g,          fields[2] || '')   // col 3
            .replace(/\$ID/g,             fields[5] || '')   // col 6
            .replace(/\$COL(\d+)/g, function (_, n) {
                return fields[parseInt(n, 10) - 1] || '';
            });
    }

    // ── simple wrap helper ───────────────────────────────────────────────────

    /**
     * Wrap text in a LaTeX command: \cmd{text}
     * @param  {string} text
     * @param  {string} cmd   e.g. '\\gl', '\\langdata'
     * @param  {string} [transform]  'lowercase' | 'uppercase' | 'none'
     * @returns {string}
     */
    function wrapCommand(text, cmd, transform) {
        if (transform === 'lowercase') text = text.toLowerCase();
        else if (transform === 'uppercase') text = text.toUpperCase();
        return cmd + '{' + text + '}';
    }

    // ── public API ───────────────────────────────────────────────────────────

    return {
        parseFLExBlock:            parseFLExBlock,
        parseFLExBlocks:           parseFLExBlocks,
        renderFLEx:                renderFLEx,
        renderFLExXlist:           renderFLExXlist,
        renderFLExAuto:            renderFLExAuto,
        renderFLExTSV:             renderFLExTSV,
        renderFLExTSVAuto:         renderFLExTSVAuto,
        parsePhonologyAssistant:   parsePhonologyAssistant,   // old fixed-column API
        renderPhonologyAssistant:  renderPhonologyAssistant,  // old fixed-column API
        parseTSVRow:               parseTSVRow,               // generic TSV API
        applyRowTemplate:          applyRowTemplate,          // generic TSV API
        wrapCommand:               wrapCommand,
        // expose internals for testing
        _escapeLatex:  escapeLatex,
        _isGramGloss:  isGramGloss,
        _wrapGlosses:  wrapGlosses,
        _massageLine:  massageLine
    };
}));
