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

    // Unicode directional marks FLEx sprinkles through clipboard text. On Free/Lit
    // lines they bracket an optional writing-system code (e.g. <LRM>Eng<LRM>).
    var DIR_CLASS = '‎‏‪-‮';
    // Leading writing-system code: optional marks/spaces, a short alphabetic
    // token, then a directional mark. A genuine first word of a translation is
    // followed by a space (not a mark), so it never matches.
    var CODE_RE   = new RegExp('^[\\s' + DIR_CLASS + ']*[A-Za-z]{1,5}[' + DIR_CLASS + ']');

    // ── low-level helpers ────────────────────────────────────────────────────

    function stripInvisible(s) {
        return s.replace(/[\u200B\u200E\u200F\u202A-\u202E]/g, '');
    }

    function escapeLatex(s) {
        var ph = [];
        var M  = '\x00PH';
        s = s.replace(/\\[a-zA-Z]+\{[^}]*\}/g, function (m) {
            ph.push(m); return M + (ph.length - 1) + '\x00';
        });
        // Single pass so replacement text (which itself contains braces) is not
        // re-escaped. Covers _ % $ # & { } plus backslash, tilde, caret.
        s = s.replace(/[\\{}%$#&_~^]/g, function (ch) {
            switch (ch) {
                case '\\': return '\\textbackslash{}';
                case '~':  return '\\textasciitilde{}';
                case '^':  return '\\textasciicircum{}';
                case '{':  return '\\{';
                case '}':  return '\\}';
                default:   return '\\' + ch;     // % $ # & _
            }
        });
        s = s.replace(new RegExp(M + '(\\d+)\x00', 'g'),
            function (_, i) { return ph[Number(i)]; });
        return s;
    }

    function isGramGloss(s) {
        if (/^[A-Z\u014a\u014b]\.$/.test(s)) return false;
        return /^[^\w]*([0-9A-Z]+|[0-9]\w+)[^\w]*$/.test(s);
    }

    /**
     * Apply a case transform to a gloss abbreviation string.
     * @param  {string} s
     * @param  {string} caseOpt  'lowercase' | 'uppercase' | 'capitalize' | 'none'
     * @returns {string}
     */
    function applyGlossCase(s, caseOpt) {
        if (!s) return s;
        switch (caseOpt) {
            case 'uppercase':  return s.toUpperCase();
            case 'capitalize': return s.charAt(0).toUpperCase() + s.slice(1).toLowerCase();
            case 'none':       return s;
            default:           return s.toLowerCase();  // 'lowercase'
        }
    }

    /**
     * Wrap grammatical gloss segments in a LaTeX command, applying case transform.
     * Splits on morpheme dividers and '.'; non-grammatical segments are LaTeX-escaped.
     * @param  {string} token
     * @param  {string} glCmd      e.g. '\\textsc'
     * @param  {string} glossCase  'lowercase' | 'uppercase' | 'capitalize' | 'none'
     * @returns {string}
     */
    function wrapGlosses(token, glCmd, glossCase) {
        if (!token) return '';
        var parts = [];
        var cur   = '';
        for (var i = 0; i < token.length; i++) {
            var ch = token[i];
            if (MORPH_DIVS.indexOf(ch) !== -1 || ch === '.') {
                if (cur) {
                    parts.push(glCmd && isGramGloss(cur)
                        ? glCmd + '{' + applyGlossCase(cur, glossCase) + '}'
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
                ? glCmd + '{' + applyGlossCase(cur, glossCase) + '}'
                : escapeLatex(cur));
        }
        return parts.join('');
    }

    /**
     * Apply glossCase transform to grammatical segments within a plain gloss token
     * (no command wrapping — used for TSV output).
     * @param  {string} token
     * @param  {string} glossCase
     * @returns {string}
     */
    function transformGlossToken(token, glossCase) {
        if (!token) return '';
        var parts = [];
        var cur   = '';
        for (var i = 0; i < token.length; i++) {
            var ch = token[i];
            if (MORPH_DIVS.indexOf(ch) !== -1 || ch === '.') {
                if (cur) {
                    parts.push(isGramGloss(cur) ? applyGlossCase(cur, glossCase) : cur);
                    cur = '';
                }
                parts.push(ch);
            } else {
                cur += ch;
            }
        }
        if (cur) {
            parts.push(isGramGloss(cur) ? applyGlossCase(cur, glossCase) : cur);
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
    // Strip a leading writing-system code (mark-delimited) from a Free/Lit remainder.
    function stripWsCode(rest) {
        var m = CODE_RE.exec(rest);
        return m ? rest.slice(m[0].length) : rest;
    }

    function parseFLExBlock(raw) {
        var text     = raw.replace(/\r\n?/g, '\n');
        var blockEnd = text.indexOf('\n\n');
        if (blockEnd >= 0) text = text.substring(0, blockEnd);

        var lineTypes  = [];
        var colArrays  = [];
        var freeLines  = [];
        var litLines   = [];
        var lineNum    = null;
        var seenFree   = false;
        var lastLabel  = 'free';

        var rawLines = text.split('\n')
            // Strip trailing SPACES only — trailing tabs are significant columns
            // (FLEx pads short tiers with empty cells; trimming them drops glosses).
            .map(function (l) { return String(l).replace(/[ ]+$/, ''); })
            .filter(function (l) { return stripInvisible(l).trim() !== ''; });

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

            // Free / Lit translation line (marks preserved so a ws code can be
            // detected — FLEx brackets the code with directional marks).
            var head = l.replace(new RegExp('^[\\s' + DIR_CLASS + ']+'), '');
            var labelMatch = head.match(/^(Free\b|Lit\.)/i);
            if (labelMatch) {
                seenFree  = true;
                lastLabel = /^Lit/i.test(labelMatch[1]) ? 'lit' : 'free';
                var ft = stripInvisible(stripWsCode(head.slice(labelMatch[1].length))).trim();
                if (ft) (lastLabel === 'lit' ? litLines : freeLines).push(ft);
                continue;
            }

            // Continuation line carrying an additional writing system (e.g. " Ind …")
            if (seenFree && CODE_RE.test(l)) {
                var cont = stripInvisible(stripWsCode(l)).trim();
                if (cont) (lastLabel === 'lit' ? litLines : freeLines).push(cont);
                continue;
            }

            var lClean = stripInvisible(l).trim();
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
                 freeLines: freeLines, litLines: litLines, lineNum: lineNum };
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
    // Join a gathered gloss piece onto a morpheme's running gloss.
    // When the source has a morpheme tier, gathered pieces are within-morpheme
    // continuations (e.g. "go" + ".CMP") and are concatenated verbatim. When the
    // source has only a whole-word tier (no Morphemes/LexEntries), gathered pieces
    // can span DIFFERENT morphemes whose boundary marker is unknown; `wholeWord`
    // inserts a neutral "-" so glosses stay segmented (e.g. "go.CMP-lnk").
    function appendGloss(g, ng, wholeWord) {
        if (g === '') return ng;
        var c0 = ng.charAt(0);
        if (c0 === '.' || MORPH_DIVS.indexOf(c0) !== -1) return g + ng;
        if (MORPH_DIVS.indexOf(g.charAt(g.length - 1)) !== -1) return g + ng;
        return wholeWord ? g + '-' + ng : g + ng;
    }

    // Collapse padded columns into a list of { m, g } morphemes, gathering each
    // morpheme's multi-column gloss from the empty-morpheme columns that follow it.
    function collapseMorphemes(morphemes, lexGlosses, startIdx, wholeWord) {
        var N = Math.max(morphemes.length, lexGlosses.length);
        var list = [];
        var i = startIdx;
        while (i < N) {
            var m = (morphemes[i] || '').trim();
            var g = (lexGlosses[i] || '').trim();
            if (m !== '') {
                var j = i + 1;
                while (j < N && (morphemes[j] || '').trim() === '') {
                    var ng = (lexGlosses[j] || '').trim();
                    if (ng !== '') g = appendGloss(g, ng, wholeWord);
                    j++;
                }
                list.push({ m: m, g: g });
                i = j;
            } else {
                if (g !== '') list.push({ m: '', g: g });
                i++;
            }
        }
        return list;
    }

    // Group collapsed morphemes into words by divider DIRECTION:
    //   leading  - = ~ < >  → suffix/enclitic, attaches to the PREVIOUS word
    //   trailing - = ~ < >  → prefix/proclitic, attaches to the NEXT word
    //   no divider           → root, starts a new word
    function groupWordsFromColumns(morphemes, lexGlosses, startIdx, wholeWord) {
        var morphList = collapseMorphemes(morphemes, lexGlosses, startIdx, wholeWord);
        var words = [];
        var cur = null;
        var awaitHost = '';   // trailing divider of a prefix/proclitic awaiting its host
        function flush() { if (cur) { words.push(cur); cur = null; } awaitHost = ''; }

        for (var k = 0; k < morphList.length; k++) {
            var m = morphList[k].m, g = morphList[k].g;

            if (m === '') {
                // Orphan gloss with no morpheme form — standalone slot.
                flush();
                words.push({ form: '', glossParts: g !== '' ? [g] : [] });
                continue;
            }

            var lead  = MORPH_DIVS.indexOf(m.charAt(0)) !== -1 ? m.charAt(0) : '';
            var last  = m.charAt(m.length - 1);
            var trail = MORPH_DIVS.indexOf(last) !== -1 ? last : '';

            if (lead) {
                // Suffix / enclitic → attach to current word (left).
                if (cur) {
                    cur.form += m;
                    cur.glossParts.push(g !== '' ? lead + g : lead);
                } else {
                    cur = { form: m, glossParts: g !== '' ? [g] : [] };
                }
                continue;
            }

            if (trail) {
                // Prefix / proclitic → attaches to the NEXT word (right).
                if (cur && awaitHost) {
                    cur.form += m;
                    if (g !== '') cur.glossParts.push(awaitHost + g);
                    awaitHost = trail;
                } else {
                    flush();
                    cur = { form: m, glossParts: g !== '' ? [g] : [] };
                    awaitHost = trail;
                }
                continue;
            }

            // Pure root.
            if (cur && awaitHost) {
                cur.form += m;
                if (g !== '') cur.glossParts.push(awaitHost + g);
                awaitHost = '';
            } else {
                flush();
                cur = { form: m, glossParts: g !== '' ? [g] : [] };
            }
        }
        flush();
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

    // ── Tier selection + word building (shared by all renderers) ─────────────

    /**
     * Choose the object-language (form) tier and the gloss tier.
     * Forms:  Morphemes / LexEntries  (else Word).
     * Gloss:  LexGloss preferred (morpheme glosses — what IGT examples need);
     *         else WordGloss (whole-word gloss, e.g. a Word + Word Gloss export).
     * @returns {{ morphIdx:number, glossIdx:number, wholeWord:boolean }}
     */
    function pickTiers(ex) {
        var lt = ex.lineTypes, morphIdx = -1, glossIdx = -1;
        for (var t = 0; t < lt.length; t++) {
            if (morphIdx < 0 && (lt[t] === 'Morphemes' || lt[t] === 'LexEntries')) morphIdx = t;
            if (glossIdx < 0 && lt[t] === 'LexGloss') glossIdx = t;
        }
        if (morphIdx < 0) for (var a = 0; a < lt.length; a++) if (lt[a] === 'Word')      { morphIdx = a; break; }
        if (glossIdx < 0) for (var b = 0; b < lt.length; b++) if (lt[b] === 'WordGloss') { glossIdx = b; break; }
        // Whole-word source: forms come from a Word tier but glosses are
        // morpheme-level (no Morphemes/LexEntries tier to supply boundaries).
        var wholeWord = morphIdx >= 0 && lt[morphIdx] === 'Word'
                        && glossIdx >= 0 && lt[glossIdx] === 'LexGloss';
        return { morphIdx: morphIdx, glossIdx: glossIdx, wholeWord: wholeWord };
    }

    /**
     * Run tier selection + word grouping for a parsed block.
     * @returns {{ words: Array, hasGloss: boolean }|null}  null if no form tier.
     */
    function buildWords(ex) {
        var sel = pickTiers(ex);
        if (sel.morphIdx < 0) return null;
        var morphArr  = ex.colArrays[sel.morphIdx];
        var dataStart = 1;
        if (/^\d+$/.test(morphArr[dataStart] || '')) dataStart++;
        var glossArr  = sel.glossIdx >= 0 ? ex.colArrays[sel.glossIdx] : [];
        var words = groupWordsFromColumns(morphArr, glossArr, dataStart, sel.wholeWord);
        handleStandalonePunctuation(words);
        return { words: words, hasGloss: sel.glossIdx >= 0 };
    }

    // ── FLEx renderer ────────────────────────────────────────────────────────

    /**
     * Render a parsed FLEx block to a langsci-gb4e \gll block.
     * @param  {object} ex       Result of parseFLExBlock()
     * @param  {object} [opts]
     * @param  {string} [opts.glCmd='\\textsc']        Gloss abbreviation command
     * @param  {string} [opts.glossCase='capitalize']  Case transform for grammatical glosses: 'lowercase'|'uppercase'|'capitalize'|'none'
     * @param  {string} [opts.formCmd='\\textit']      Command to wrap the object-language tier ('' to omit)
     * @param  {string} [opts.txtrefCmd='%\\txtref']   Source-reference command ('' to omit)
     * @param  {string} [opts.txtrefPrefix='TXT:']    Prefix inside \txtref{}
     * @param  {boolean} [opts.wrapExe=true]          Wrap in \begin{exe}\ex...\end{exe}
     * @returns {string}
     */
    function renderFLEx(ex, opts) {
        opts = opts || {};
        var glCmd        = opts.glCmd        !== undefined ? opts.glCmd        : '\\textsc';
        var glossCase    = opts.glossCase    !== undefined ? opts.glossCase    : 'capitalize';
        var formCmd      = opts.formCmd      !== undefined ? opts.formCmd      : '\\textit';
        var txtrefCmd    = opts.txtrefCmd    !== undefined ? opts.txtrefCmd    : '%\\txtref';
        var txtrefPrefix = opts.txtrefPrefix !== undefined ? opts.txtrefPrefix : 'TXT:';
        var wrapExe      = opts.wrapExe      !== undefined ? opts.wrapExe      : true;

        var freeLines  = ex.freeLines;
        var lineNum    = ex.lineNum;

        var built = buildWords(ex);
        if (!built) return '% (no recognisable tier lines — check labels)';
        var words    = built.words;
        var hasGloss = built.hasGloss;

        var tier1 = [];
        var tier2 = [];
        var FLOAT_PUNCT = '-\u2012\u2013\u2014\u2015/|&\u2026...';

        for (var w = 0; w < words.length; w++) {
            var word = words[w];

            // Check for floating punctuation
            if (Array.from(word.form).length === 1 && FLOAT_PUNCT.indexOf(word.form) !== -1) {
                tier1.push(word.form);
                if (hasGloss) tier2.push('\\textasciitilde');
                continue;
            }

            // Empty form: use escaped ~ placeholder for gb4e
            if (word.form === '') {
                tier1.push('\\textasciitilde');
            } else {
                tier1.push(escapeLatex(word.form));
            }

            if (hasGloss) {
                tier2.push(wrapGlosses(word.glossParts.join(''), glCmd, glossCase));
            }
        }

        var tierCount = 1 + (hasGloss ? 1 : 0);
        var gCmd   = 'g' + Array(tierCount + 1).join('l');
        // NOTE: JS output intentionally uses indentation and \n newlines.
        // Output goes into a <textarea> and is copied as a block, so indents
        // are preserved correctly and do not trigger editor auto-indent.
        // The Rust path (tauri/src-tauri/src/convert.rs) deliberately has NO
        // indentation because it delivers output via enigo key events, where
        // pressing Return would cause editors (Sublime, VS Code, etc.) to
        // auto-indent subsequent lines. Do not "fix" this divergence: it is
        // load-bearing.
        var indent = Array(gCmd.length + 2).join(' ');

        var tier1Content = formCmd
            ? tier1.map(function (t) { return formCmd + '{' + t + '}'; }).join(' ')
            : tier1.join(' ');

        var lines = [];
        lines.push('\\' + gCmd + ' ' + tier1Content + ' \\\\');
        if (hasGloss) lines.push(indent + tier2.join(' ') + ' \\\\');

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
            glossCase:    opts.glossCase,
            formCmd:      opts.formCmd,
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
     * @param  {object} ex    Result of parseFLExBlock()
     * @param  {object} [opts]
     * @param  {string} [opts.glossCase='capitalize']  Case transform for grammatical glosses
     * @returns {string}
     */
    function renderFLExTSV(ex, opts) {
        opts = opts || {};
        var glossCase  = opts.glossCase !== undefined ? opts.glossCase : 'capitalize';

        var freeLines  = ex.freeLines;

        var built = buildWords(ex);
        if (!built) return '(no recognisable tier lines — check labels)';
        var words    = built.words;
        var hasGloss = built.hasGloss;

        var formCols  = [];
        var glossCols = [];

        for (var w = 0; w < words.length; w++) {
            var word = words[w];
            formCols.push(word.form);
            if (hasGloss) {
                glossCols.push(transformGlossToken(word.glossParts.join(''), glossCase));
            }
        }

        var rows = [];
        rows.push(formCols.join('\t'));
        if (hasGloss) rows.push(glossCols.join('\t'));
        if (freeLines.length > 0) rows.push(freeLines.join(' / '));

        return rows.join('\n');
    }

    /**
     * Render multiple parsed FLEx blocks to morpheme-aligned TSV.
     * Multiple blocks are separated by a blank line.
     * @param  {Array}  blocks  Result of parseFLExBlocks()
     * @param  {object} [opts]  Same options as renderFLExTSV()
     * @returns {string}
     */
    function renderFLExTSVAuto(blocks, opts) {
        return blocks.map(function (b) { return renderFLExTSV(b, opts); }).join('\n\n');
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
