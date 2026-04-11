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
     * For tab-separated FLEx data: returns raw column arrays.
     * For space-separated fallback: returns token arrays (legacy path).
     * @param  {string} raw
     * @returns {{ lineTypes: string[], colArrays: string[][], freeLines: string[], lineNum: string|null }}
     */
    function parseFLExBlock(raw) {
        var text     = raw.replace(/\r\n?/g, '\n');
        var blockEnd = text.indexOf('\n\n');
        if (blockEnd >= 0) text = text.substring(0, blockEnd);

        var lineTypes  = [];
        var colArrays  = [];
        var freeLines  = [];
        var lineNum    = null;
        var seenFree   = false;

        var rawLines = text.split('\n')
            .map(function (l) { return String(l).replace(/[ \t]+$/, ''); })
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

            var cols;
            if (l.indexOf('\t') !== -1) {
                // Tab-column FLEx format: parse as raw column array
                var normalized = stripInvisible(l)
                    .replace(/Lex\. Entries/g, 'LexEntries')
                    .replace(/Lex\. Gloss/g,   'LexGloss')
                    .replace(/Word Gloss/g,    'WordGloss')
                    .replace(/Word Cat\./g,    'WordCat');
                cols = normalized.split('\t').map(function (c) { return c.trim(); });

                // If first column is empty, shift left (skip the leading empty column
                // that occurs when the tier label is in column 1)
                if (cols.length > 0 && cols[0] === '') {
                    cols.shift();
                }
            } else {
                // Space-separated fallback (legacy / non-FLEx sources)
                var massaged = massageLine(stripInvisible(l));
                cols = massaged.trim().split(/\s+/).filter(function (t) { return t !== ''; });
            }

            if (!cols || cols.length === 0) continue;
            lineTypes.push(cols[0]);
            colArrays.push(cols);
        }

        return { lineTypes: lineTypes, colArrays: colArrays,
                 freeLines: freeLines, lineNum: lineNum };
    }

    // ── Word-grouping algorithm (tab-format columns) ──────────────────────────

    /**
     * Run the word-grouping algorithm on raw column arrays.
     * Returns an array of word objects: { form, glossParts[] }.
     * Each glossParts element is a string (may include boundary markers).
     * @param  {string[]} morphemes   Column array for Morphemes tier
     * @param  {string[]} lexGlosses  Column array for LexGloss tier
     * @param  {number}  startIdx     Index of first data column (after label)
     * @returns {Array<{ form: string, glossParts: string[] }>}
     */
    function groupWordsFromColumns(morphemes, lexGlosses, startIdx) {
        var words = [];
        var currentWord = null;
        var N = morphemes.length;

        for (var col = startIdx; col < N; col++) {
            var m = (morphemes[col] || '').trim();
            var g = (lexGlosses[col] || '').trim();

            if (m !== '') {
                // Non-empty morpheme: check for boundary marker at start
                var boundary = m.length > 0 && MORPH_DIVS.indexOf(m[0]) !== -1 ? m[0] : '';
                var suffix   = boundary ? m.substring(1) : m;

                if (boundary !== '') {
                    // Attach to current word (suffix/enclitic or prefix boundary)
                    if (currentWord) {
                        currentWord.form += boundary + suffix;
                        if (g !== '') {
                            currentWord.glossParts.push(boundary + g);
                        } else {
                            currentWord.glossParts.push(boundary);
                        }
                    }
                } else {
                    // Start a new word (no boundary marker)
                    if (currentWord) words.push(currentWord);
                    currentWord = { form: m, glossParts: g !== '' ? [g] : [] };

                    // If direct gloss is empty, collect from following empty-morpheme columns
                    if (g === '') {
                        while (col + 1 < N && (morphemes[col + 1] || '').trim() === '') {
                            col++;
                            var nextG = (lexGlosses[col] || '').trim();
                            if (nextG !== '') currentWord.glossParts.push(nextG);
                        }
                    }
                }
            } else {
                // Empty morpheme: zero-morpheme standalone word slot
                if (currentWord) words.push(currentWord);
                if (g !== '') words.push({ form: '', glossParts: [g] });
                currentWord = null;
            }
        }

        if (currentWord) words.push(currentWord);
        return words;
    }

    /**
     * Special case: standalone punctuation (single char, empty gloss) appends
     * to preceding word's form only, no gloss contribution.
     * @param {Array} words  Mutated in place
     */
    function handleStandalonePunctuation(words) {
        var M = '\u2026,:;.!?-\u2012\u2013\u2014\u2015/|&';
        for (var i = 1; i < words.length; i++) {
            var w = words[i];
            if (w.form.length === 1 && M.indexOf(w.form) !== -1 && w.glossParts.length === 0) {
                // Append to preceding word's form, remove from list
                if (words[i - 1]) {
                    words[i - 1].form += w.form;
                }
                words.splice(i, 1);
                i--;
            }
        }
    }

    // ── FLEx renderer ────────────────────────────────────────────────────────

    /**
     * Render a parsed FLEx block to a langsci-gb4e \gll block.
     * @param  {object} ex       Result of parseFLExBlock()
     * @param  {object} [opts]
     * @param  {string} [opts.glCmd='\\textsc']       Gloss abbreviation command
     * @param  {string} [opts.txtrefCmd='\\txtref']  Source-reference command ('' to omit)
     * @param  {string} [opts.txtrefPrefix='TXT:']   Prefix inside \txtref{}
     * @param  {boolean} [opts.wrapExe=true]         Wrap in \begin{exe}\ex...\end{exe}
     * @returns {string}
     */
    function renderFLEx(ex, opts) {
        opts = opts || {};
        var glCmd        = opts.glCmd        !== undefined ? opts.glCmd        : '\\textsc';
        var txtrefCmd    = opts.txtrefCmd    !== undefined ? opts.txtrefCmd    : '\\txtref';
        var txtrefPrefix = opts.txtrefPrefix !== undefined ? opts.txtrefPrefix : 'TXT:';
        var wrapExe      = opts.wrapExe      !== undefined ? opts.wrapExe      : true;

        var lineTypes  = ex.lineTypes;
        var colArrays  = ex.colArrays;
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

        var morphemesArr = colArrays[morphIdx];
        var dataStart    = 1;
        if (/^\d+$/.test(morphemesArr[dataStart] || '')) dataStart++;

        var lexGlossesArr = lexGlossIdx >= 0 ? colArrays[lexGlossIdx] : [];
        var wordGlossesArr = wordGlossIdx >= 0 ? colArrays[wordGlossIdx] : [];

        // Run word-grouping algorithm on tab-format columns
        var words = groupWordsFromColumns(morphemesArr, lexGlossesArr, dataStart);
        handleStandalonePunctuation(words);

        var tier1 = [];
        var tier2 = [];
        var tier3 = [];
        var FLOAT_PUNCT = '-\u2012\u2013\u2014\u2015/|&\u2026...';

        for (var w = 0; w < words.length; w++) {
            var word = words[w];

            // Check for floating punctuation
            if (word.form.length === 1 && FLOAT_PUNCT.indexOf(word.form) !== -1) {
                tier1.push(word.form);
                if (lexGlossIdx  >= 0) tier2.push('\\textasciitilde');
                if (wordGlossIdx >= 0) tier3.push('\\textasciitilde');
                continue;
            }

            // Empty form: use escaped ~ placeholder for gb4e
            if (word.form === '') {
                tier1.push('\\textasciitilde');
            } else {
                tier1.push(escapeLatex(word.form));
            }

            if (lexGlossIdx >= 0) {
                var gStr = word.glossParts.join('');
                tier2.push(wrapGlosses(gStr, glCmd));
            }

            if (wordGlossIdx >= 0) {
                // WordGloss doesn't have a good mapping from word-grouping result
                // For now, emit empty placeholder
                tier3.push('\\textasciitilde');
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
     * @returns {Array<{ lineTypes: string[], colArrays: string[][], freeLines: string[], lineNum: string|null }>}
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
     * Render a parsed FLEx block to word-collapsed TSV.
     * Each word occupies a single tab-separated column; morpheme parts and
     * dividers are joined inline (e.g. di=de, deda-a).
     * @param  {object} ex  Result of parseFLExBlock()
     * @returns {string}
     */
    function renderFLExTSV(ex) {
        var lineTypes  = ex.lineTypes;
        var colArrays  = ex.colArrays;
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

        var morphemesArr = colArrays[morphIdx];
        var dataStart    = 1;
        if (/^\d+$/.test(morphemesArr[dataStart] || '')) dataStart++;

        var lexGlossesArr = lexGlossIdx >= 0 ? colArrays[lexGlossIdx] : [];
        var wordGlossesArr = wordGlossIdx >= 0 ? colArrays[wordGlossIdx] : [];

        // Run word-grouping algorithm
        var words = groupWordsFromColumns(morphemesArr, lexGlossesArr, dataStart);
        handleStandalonePunctuation(words);

        var formCols  = [];
        var glossCols = [];

        for (var w = 0; w < words.length; w++) {
            var word = words[w];
            formCols.push(word.form);
            if (lexGlossIdx >= 0) {
                glossCols.push(word.glossParts.join(''));
            }
        }

        var rows = [];
        rows.push(formCols.join('\t'));
        if (lexGlossIdx  >= 0) rows.push(glossCols.join('\t'));
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
        _escapeLatex:     escapeLatex,
        _isGramGloss:     isGramGloss,
        _wrapGlosses:     wrapGlosses,
        _massageLine:     massageLine
    };
}));
