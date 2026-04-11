//! Rust port of docs/core.js — all conversion logic runs here so it can work
//! from background threads without a live webview.
//!
//! Based on the original TeXstudio macro code by Moss Doerksen (SIL PNG),
//! used by permission. JavaScript and Rust ports by Seth Johnston.

// ── constants ─────────────────────────────────────────────────────────────────

/// Internal morpheme-boundary sentinel inserted by massage_line().
const SENTINEL: char = '\u{2591}'; // ░
const MORPH_DIVS: &str = "-=~<>";

// ── low-level helpers ─────────────────────────────────────────────────────────

pub fn strip_invisible(s: &str) -> String {
    s.chars()
        .filter(|&c| !matches!(c,
            '\u{200E}' | '\u{200F}' | '\u{202A}'..='\u{202E}'
        ))
        .collect()
}

/// Escape LaTeX special characters, preserving existing \cmd{...} sequences.
pub fn escape_latex(s: &str) -> String {
    let chars: Vec<char> = s.chars().collect();
    let mut result = String::new();
    let mut i = 0;

    while i < chars.len() {
        // Protect \cmd{...} sequences (non-nested, matches the JS regex behaviour)
        if chars[i] == '\\' {
            let j = i + 1;
            let mut k = j;
            while k < chars.len() && chars[k].is_ascii_alphabetic() { k += 1; }
            if k > j && k < chars.len() && chars[k] == '{' {
                if let Some(off) = chars[k+1..].iter().position(|&c| c == '}') {
                    let end = k + 1 + off;
                    result.extend(chars[i..=end].iter());
                    i = end + 1;
                    continue;
                }
            }
        }
        match chars[i] {
            '%' | '$' | '#' | '&' | '_' | '{' | '}' => {
                result.push('\\');
                result.push(chars[i]);
            }
            c => result.push(c),
        }
        i += 1;
    }
    result
}

/// True if `s` looks like a grammatical gloss abbreviation (all-caps / digit-led).
fn is_gram_gloss(s: &str) -> bool {
    let chars: Vec<char> = s.chars().collect();

    // Single uppercase letter + period is NOT a gloss (e.g. "N.")
    if chars.len() == 2 && chars[1] == '.' {
        if chars[0].is_ascii_uppercase() || chars[0] == '\u{014A}' || chars[0] == '\u{014B}' {
            return false;
        }
    }

    // Strip leading/trailing non-word characters
    let start = chars.iter().position(|c| c.is_alphanumeric() || *c == '_').unwrap_or(chars.len());
    let end   = chars.iter().rposition(|c| c.is_alphanumeric() || *c == '_')
                    .map(|p| p + 1).unwrap_or(0);
    if start >= end { return false; }
    let inner = &chars[start..end];

    let first = inner[0];
    // Pattern: all digits+uppercase  OR  starts with digit (+ word chars)
    inner.iter().all(|&c| c.is_ascii_uppercase() || c.is_ascii_digit())
        || first.is_ascii_digit()
}

/// Wrap gloss tokens in `gl_cmd`, escaping non-gloss tokens.
pub fn wrap_glosses(token: &str, gl_cmd: &str) -> String {
    if token.is_empty() { return String::new(); }
    let mut parts: Vec<String> = Vec::new();
    let mut cur = String::new();

    for ch in token.chars() {
        if MORPH_DIVS.contains(ch) || ch == '.' {
            if !cur.is_empty() {
                parts.push(if !gl_cmd.is_empty() && is_gram_gloss(&cur) {
                    format!("{}{{{}}}", gl_cmd, cur.to_lowercase())
                } else {
                    escape_latex(&cur)
                });
                cur.clear();
            }
            parts.push(ch.to_string());
        } else {
            cur.push(ch);
        }
    }
    if !cur.is_empty() {
        parts.push(if !gl_cmd.is_empty() && is_gram_gloss(&cur) {
            format!("{}{{{}}}", gl_cmd, cur.to_lowercase())
        } else {
            escape_latex(&cur)
        });
    }
    parts.join("")
}

/// Normalise a raw FLEx line: rename tier labels, insert SENTINEL around
/// morpheme-boundary characters, and clean up stray punctuation spacing.
fn massage_line(line: &str) -> String {
    let line = line
        .replace("Lex. Entries", "LexEntries")
        .replace("Lex. Gloss",   "LexGloss")
        .replace("Word Gloss",   "WordGloss")
        .replace("Word Cat.",    "WordCat");
    let line = strip_invisible(&line);

    let sp = match line.find(|c: char| c.is_whitespace()) {
        None    => return line,
        Some(i) => i,
    };
    let label = &line[..sp + 1];
    let mut body = line[sp + 1..].to_string();

    for (from, to) in [
        ("- ",  &format!("{}-{}", SENTINEL, SENTINEL)[..]),
        (" -",  &format!("{}-{}", SENTINEL, SENTINEL)),
        (" <",  &format!("{}<{}", SENTINEL, SENTINEL)),
        ("> ",  &format!("{}>{}", SENTINEL, SENTINEL)),
        ("= ",  &format!("{}={}", SENTINEL, SENTINEL)),
        (" =",  &format!("{}={}", SENTINEL, SENTINEL)),
        (" ~",  &format!("{}~{}", SENTINEL, SENTINEL)),
        ("~ ",  &format!("{}~{}", SENTINEL, SENTINEL)),
        // Punctuation
        (" .",  "."),
        (" \u{2026}", "\u{2026}"),
        (" ,",  ","),
        (" ?",  "?"),
        (" !",  "!"),
        (" :",  ":"),
        (" ;",  ";"),
        ("( ",  "("),
        (" )",  ")"),
        ("[ ",  "["),
        (" ]",  "]"),
    ] {
        body = body.replace(from, to);
    }
    format!("{}{}", label, body)
}

// ── FLEx block splitter ───────────────────────────────────────────────────────

/// Returns true if `stripped` (already stripped of invisibles and whitespace-trimmed)
/// looks like the start of a new numbered example block (e.g. "1 …", "2\t…", "3").
fn is_block_start(stripped: &str) -> bool {
    if stripped.is_empty() { return false; }
    let num_end = stripped.chars()
        .take_while(|c| c.is_ascii_digit() || *c == '.')
        .count();
    if num_end == 0 { return false; }
    let after = &stripped[num_end..];
    after.is_empty() || after.starts_with(char::is_whitespace)
}

/// Split `text` into chunks separated by blank (whitespace-only) lines.
fn split_on_blank_lines(text: &str) -> Vec<String> {
    let mut chunks: Vec<String> = Vec::new();
    let mut current: Vec<&str> = Vec::new();
    for line in text.lines() {
        if line.trim().is_empty() {
            if !current.is_empty() {
                chunks.push(current.join("\n"));
                current.clear();
            }
        } else {
            current.push(line);
        }
    }
    if !current.is_empty() { chunks.push(current.join("\n")); }
    chunks
}

/// Parse all interlinear blocks from raw FLEx clipboard text.
///
/// Phase 1: split on blank lines (including whitespace-only lines).
/// Phase 2 (fallback): if only one chunk, split on numbered-example boundaries
///   (lines matching /^\d+(\.\d+)?[\s]/) so that FLEx exports with no blank
///   separators between blocks are handled correctly.
pub fn parse_flex_blocks(raw: &str) -> Vec<FlexParsed> {
    let text = raw.replace("\r\n", "\n").replace('\r', "\n");

    // Phase 1 ─────────────────────────────────────────────────────────────────
    let chunks = split_on_blank_lines(&text);
    let valid: Vec<&str> = chunks.iter()
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .collect();

    if valid.len() > 1 {
        let blocks: Vec<FlexParsed> = valid.iter()
            .map(|c| parse_flex_block(c))
            .filter(|b| !b.line_types.is_empty())
            .collect();
        if !blocks.is_empty() { return blocks; }
    }

    // Phase 2 — split on numbered-line boundaries ─────────────────────────────
    let mut groups: Vec<Vec<String>> = vec![Vec::new()];
    for line in text.lines() {
        let stripped = strip_invisible(line.trim());
        let last_len = groups.last().map(|g| g.len()).unwrap_or(0);
        if last_len > 0 && is_block_start(&stripped) {
            groups.push(Vec::new());
        }
        groups.last_mut().unwrap().push(line.to_string());
    }

    groups.iter()
        .map(|g| g.join("\n"))
        .filter(|c| !c.trim().is_empty())
        .map(|c| parse_flex_block(&c))
        .filter(|b| !b.line_types.is_empty())
        .collect()
}

// ── FLEx parser ───────────────────────────────────────────────────────────────

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct FlexParsed {
    pub line_types:  Vec<String>,
    pub line_arrays: Vec<Vec<String>>,
    pub free_lines:  Vec<String>,
    pub line_num:    Option<String>,
}

/// Parse one tab-column FLEx line into [label, tok1, tok2, …].
///
/// Each tab-separated column is one morpheme or boundary marker.  An empty
/// column marks a word boundary.  Adjacent non-empty columns where a MORPH_DIVS
/// character is flanked on both sides by morphemes are collapsed into a single
/// sentinel-marked token (e.g. deda + = + di → "deda░=░di").  A boundary
/// marker with no following morpheme in the same run is emitted standalone.
fn flex_tab_line_toks(l: &str) -> Vec<String> {
    let cols: Vec<&str> = l.split('\t').collect();
    let label = cols[0].trim();
    if label.is_empty() { return Vec::new(); }

    let mut toks: Vec<String> = vec![label.to_string()];
    let mut i = 1usize;

    while i < cols.len() {
        if cols[i].trim().is_empty() { i += 1; continue; }

        // Collect a non-empty run (word group)
        let mut run: Vec<String> = Vec::new();
        while i < cols.len() && !cols[i].trim().is_empty() {
            run.push(cols[i].trim().to_string());
            i += 1;
        }

        // Collapse run into word tokens
        let mut j = 0usize;
        while j < run.len() {
            let col = &run[j];
            let is_div = col.len() == 1 && MORPH_DIVS.contains(col.chars().next().unwrap());
            if is_div {
                // Standalone boundary (no preceding morpheme absorbed this pass)
                toks.push(col.clone());
                j += 1;
            } else {
                // Regular morpheme — greedily absorb following boundary+morpheme pairs
                let mut word = col.clone();
                j += 1;
                while j < run.len() {
                    let next = &run[j];
                    let next_is_div = next.len() == 1
                        && MORPH_DIVS.contains(next.chars().next().unwrap());
                    if !next_is_div { break; }
                    // Boundary present — check that a morpheme follows it
                    if j + 1 >= run.len() { break; }
                    let after = &run[j + 1];
                    let after_is_div = after.len() == 1
                        && MORPH_DIVS.contains(after.chars().next().unwrap());
                    if after_is_div { break; }
                    // Absorb: word + SENTINEL + boundary + SENTINEL + morpheme
                    word.push(SENTINEL);
                    word.push_str(next);
                    word.push(SENTINEL);
                    word.push_str(after);
                    j += 2;
                }
                toks.push(word);
            }
        }
    }

    toks
}

pub fn parse_flex_block(raw: &str) -> FlexParsed {
    // Normalise line endings only — preserve tabs for column-aware parsing
    let text = raw.replace("\r\n", "\n").replace('\r', "\n");
    // Take only the first block (up to the first blank line)
    let text = match text.find("\n\n") {
        Some(i) => text[..i].to_string(),
        None    => text,
    };

    let mut line_types:  Vec<String> = Vec::new();
    let mut line_arrays: Vec<Vec<String>> = Vec::new();
    let mut free_lines:  Vec<String> = Vec::new();
    let mut line_num:    Option<String> = None;
    let mut seen_free = false;

    let raw_lines: Vec<&str> = text.lines()
        .map(|l| l.trim_end_matches(|c: char| c == ' ' || c == '\t'))
        .filter(|l| !l.trim().is_empty())
        .collect();

    for raw_line in raw_lines {
        let mut l = raw_line.to_string();

        // Extract leading example number (e.g. "1" or "1.2") if not yet found
        if line_num.is_none() {
            let trimmed = l.trim();
            let num_end = trimmed.chars()
                .take_while(|c| c.is_ascii_digit() || *c == '.')
                .count();
            if num_end > 0 {
                let after = &trimmed[num_end..];
                if after.is_empty() || after.starts_with(char::is_whitespace) {
                    line_num = Some(trimmed[..num_end].to_string());
                    let remainder = after.trim();
                    if remainder.is_empty() { continue; }
                    l = remainder.to_string();
                }
            }
        }

        let l_clean = strip_invisible(l.trim());

        // Free translation line
        let free_match = {
            let lc = l_clean.to_lowercase();
            lc.starts_with("free")
                && l_clean.as_bytes().get(4).map_or(true, |b| !b.is_ascii_alphabetic())
        };
        if free_match {
            seen_free = true;
            let after_free = l_clean[4..].trim_start();
            let ft = if after_free.split_whitespace().next()
                         .map_or(false, |w| w.len() >= 2 && w.len() <= 8
                                          && w.chars().all(|c| c.is_ascii_alphabetic())) {
                after_free.splitn(2, char::is_whitespace).nth(1).unwrap_or("").trim().to_string()
            } else {
                after_free.to_string()
            };
            if !ft.is_empty() { free_lines.push(ft); }
            continue;
        }

        if seen_free {
            let parts: Vec<&str> = l_clean.splitn(2, char::is_whitespace).collect();
            if !parts.is_empty() {
                let tag = parts[0];
                if tag.len() >= 2 && tag.len() <= 8
                    && tag.chars().all(|c| c.is_ascii_alphabetic())
                {
                    let ft = parts.get(1).unwrap_or(&"").trim();
                    if !ft.is_empty() { free_lines.push(ft.to_string()); }
                    continue;
                }
            }
        }

        let toks: Vec<String> = if l.contains('\t') {
            // Tab-column FLEx format: column-aware parsing
            let normalized = strip_invisible(&l)
                .replace("Lex. Entries", "LexEntries")
                .replace("Lex. Gloss",   "LexGloss")
                .replace("Word Gloss",   "WordGloss")
                .replace("Word Cat.",    "WordCat");
            flex_tab_line_toks(&normalized)
        } else {
            // Space-separated fallback (legacy / non-FLEx sources)
            let massaged = massage_line(&strip_invisible(&l));
            massaged.split_whitespace()
                .filter(|t| !t.is_empty())
                .map(|t| t.to_string())
                .collect()
        };

        if toks.is_empty() { continue; }
        line_types.push(toks[0].clone());
        line_arrays.push(toks);
    }

    FlexParsed { line_types, line_arrays, free_lines, line_num }
}

// ── FLEx renderer ─────────────────────────────────────────────────────────────

#[derive(Debug, Clone, serde::Deserialize, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FlexOpts {
    pub gl_cmd:        String,
    pub wrap_exe:      bool,
    pub txtref_cmd:    String,
    pub txtref_prefix: String,
}

impl Default for FlexOpts {
    fn default() -> Self {
        FlexOpts {
            gl_cmd:        "\\gl".to_string(),
            wrap_exe:      true,
            txtref_cmd:    "\\txtref".to_string(),
            txtref_prefix: "TXT:".to_string(),
        }
    }
}

pub fn render_flex(ex: &FlexParsed, opts: &FlexOpts) -> String {
    let n = ex.line_types.len();

    let mut morph_idx:     Option<usize> = None;
    let mut lex_gloss_idx: Option<usize> = None;
    let mut word_gloss_idx:Option<usize> = None;

    for t in 0..n {
        let lt = &ex.line_types[t];
        if morph_idx.is_none() && (lt == "Morphemes" || lt == "LexEntries") { morph_idx = Some(t); }
        if lex_gloss_idx.is_none()  && lt == "LexGloss"  { lex_gloss_idx  = Some(t); }
        if word_gloss_idx.is_none() && lt == "WordGloss" { word_gloss_idx = Some(t); }
    }
    if morph_idx.is_none() {
        for t in 0..n {
            if ex.line_types[t] == "Word" { morph_idx = Some(t); break; }
        }
    }
    let morph_idx = match morph_idx {
        None    => return "% (no recognisable tier lines — check labels)".to_string(),
        Some(i) => i,
    };

    let primary_arr = &ex.line_arrays[morph_idx];
    let mut data_start = 1usize;
    if primary_arr.get(data_start).map_or(false, |s| s.parse::<u64>().is_ok()) {
        data_start += 1;
    }

    let mut tier1:             Vec<String> = Vec::new();
    let mut tier2:             Vec<String> = Vec::new();
    let mut tier3:             Vec<String> = Vec::new();
    let mut lex_gloss_offset:  isize = 0;

    let float_punct = "-\u{2012}\u{2013}\u{2014}\u{2015}/|&\u{2026}...";

    for w in data_start..primary_arr.len() {
        let wt = &primary_arr[w];

        // Floating punctuation token
        if wt.chars().count() == 1 {
            let c = wt.chars().next().unwrap();
            if float_punct.contains(c) {
                tier1.push(wt.clone());
                if lex_gloss_idx.is_some()  { tier2.push("{}".to_string()); }
                if word_gloss_idx.is_some() { tier3.push("{}".to_string()); }
                continue;
            }
        }

        // tier1 — word/morpheme token without sentinels
        tier1.push(escape_latex(&wt.replace(SENTINEL, "")));

        // tier2 — lex gloss
        if let Some(lgi) = lex_gloss_idx {
            let l_arr = &ex.line_arrays[lgi];
            if wt.contains(SENTINEL) {
                let parts: Vec<&str> = wt.split(SENTINEL).collect();
                let part_count = parts.len() as isize - 1;
                let mut g_parts: Vec<String> = Vec::new();
                for (y, part) in parts.iter().enumerate() {
                    if part.is_empty() { continue; }
                    if part.len() == 1 && MORPH_DIVS.contains(part.chars().next().unwrap()) {
                        g_parts.push(part.to_string());
                        lex_gloss_offset -= 1;
                    } else {
                        let gi = (w as isize - data_start as isize)
                                  + lex_gloss_offset + y as isize;
                        let raw = l_arr.get((gi + data_start as isize) as usize)
                            .map(|s| s.as_str()).unwrap_or("");
                        g_parts.push(wrap_glosses(raw, &opts.gl_cmd));
                    }
                }
                tier2.push(g_parts.join(""));
                lex_gloss_offset += part_count;
            } else {
                let gi2  = (w as isize - data_start as isize) + lex_gloss_offset;
                let raw2 = l_arr.get((gi2 + data_start as isize) as usize)
                    .map(|s| s.as_str()).unwrap_or("");
                tier2.push(wrap_glosses(raw2, &opts.gl_cmd));
            }
        }

        // tier3 — word gloss
        if let Some(wgi) = word_gloss_idx {
            let wg_arr = &ex.line_arrays[wgi];
            let wi = w - data_start;
            tier3.push(wrap_glosses(
                wg_arr.get(wi + data_start).map(|s| s.as_str()).unwrap_or(""),
                &opts.gl_cmd,
            ));
        }
    }

    // Build LaTeX lines
    // JS: gCmd = 'g' + Array(tierCount+1).join('l')  →  "g" + "l"*tierCount
    let tier_count = 1
        + if lex_gloss_idx.is_some()  { 1 } else { 0 }
        + if word_gloss_idx.is_some() { 1 } else { 0 };
    let g_cmd  = format!("g{}", "l".repeat(tier_count));       // e.g. "gll"
    // JS: indent = Array(gCmd.length + 2).join(' ')  →  ' ' * (gCmd.len + 1)
    let indent = " ".repeat(g_cmd.len() + 1);                  // e.g. "    "

    let mut lines: Vec<String> = Vec::new();
    lines.push(format!("\\{} {} \\\\", g_cmd, tier1.join(" ")));
    if lex_gloss_idx.is_some()  { lines.push(format!("{}{} \\\\", indent, tier2.join(" "))); }
    if word_gloss_idx.is_some() { lines.push(format!("{}{} \\\\", indent, tier3.join(" "))); }

    let txtref = if !opts.txtref_cmd.is_empty() {
        match &ex.line_num {
            Some(num) => format!(" {}{{{}{}}}", opts.txtref_cmd, opts.txtref_prefix, num),
            None      => String::new(),
        }
    } else {
        String::new()
    };

    if !ex.free_lines.is_empty() {
        let ft = ex.free_lines.iter().map(|l| escape_latex(l)).collect::<Vec<_>>().join(" / ");
        lines.push(format!("\\glt '{}'{}", ft, txtref));
    } else if !txtref.is_empty() {
        lines.push(format!("\\glt{}", txtref));
    }

    let body = lines.join("\n");
    if !opts.wrap_exe { return body; }

    format!(
        "\n% Interlinear example\n\n\\begin{{exe}}\n\\ex % \\label{{ex:KEY}}\n{}\n\\end{{exe}}\n",
        body
    )
}

/// Render multiple parsed FLEx blocks into a langsci-gb4e xlist environment.
/// Each block becomes one `\ex` sub-item inside `\begin{xlist}…\end{xlist}`.
pub fn render_flex_xlist(blocks: &[FlexParsed], opts: &FlexOpts) -> String {
    let sub_opts = FlexOpts { wrap_exe: false, ..opts.clone() };
    let items: Vec<String> = blocks.iter().map(|block| {
        let body = render_flex(block, &sub_opts);
        let indented = body.trim().lines()
            .map(|l| format!("    {}", l))
            .collect::<Vec<_>>()
            .join("\n");
        format!("\\ex % \\label{{ex:KEY}}\n{}", indented)
    }).collect();

    format!(
        "\n% Interlinear examples\n\n\\begin{{exe}}\n\\ex % \\label{{ex:KEY}}\n\\begin{{xlist}}\n{}\n\\end{{xlist}}\n\\end{{exe}}\n",
        items.join("\n\n")
    )
}

/// Auto-detect single vs. multiple blocks and render accordingly.
/// - One block  → render_flex()       (\begin{exe}\ex …\end{exe})
/// - Many blocks → render_flex_xlist() (\begin{exe}\ex\begin{xlist}…\end{xlist}\end{exe})
pub fn render_flex_auto(blocks: &[FlexParsed], opts: &FlexOpts) -> String {
    if blocks.len() == 1 {
        render_flex(&blocks[0], opts)
    } else {
        render_flex_xlist(blocks, opts)
    }
}

// ── FLEx → TSV renderer ───────────────────────────────────────────────────────

/// Render a parsed FLEx block to word-collapsed TSV.
/// Each word occupies a single tab-separated column; morpheme parts and
/// dividers are joined inline (e.g. di=de, deda-a). Gloss assembly mirrors
/// render_flex() exactly but without LaTeX escaping or command wrapping.
pub fn render_flex_tsv(ex: &FlexParsed) -> String {
    let n = ex.line_types.len();

    let mut morph_idx:      Option<usize> = None;
    let mut lex_gloss_idx:  Option<usize> = None;
    let mut word_gloss_idx: Option<usize> = None;

    for t in 0..n {
        let lt = &ex.line_types[t];
        if morph_idx.is_none() && (lt == "Morphemes" || lt == "LexEntries") { morph_idx = Some(t); }
        if lex_gloss_idx.is_none()  && lt == "LexGloss"  { lex_gloss_idx  = Some(t); }
        if word_gloss_idx.is_none() && lt == "WordGloss" { word_gloss_idx = Some(t); }
    }
    if morph_idx.is_none() {
        for t in 0..n {
            if ex.line_types[t] == "Word" { morph_idx = Some(t); break; }
        }
    }
    let morph_idx = match morph_idx {
        None    => return "(no recognisable tier lines — check labels)".to_string(),
        Some(i) => i,
    };

    let primary_arr = &ex.line_arrays[morph_idx];
    let mut data_start = 1usize;
    if primary_arr.get(data_start).map_or(false, |s| s.parse::<u64>().is_ok()) {
        data_start += 1;
    }

    let mut form_cols:   Vec<String> = Vec::new();
    let mut gloss_cols:  Vec<String> = Vec::new();
    let mut wgloss_cols: Vec<String> = Vec::new();
    let mut lex_gloss_offset: isize  = 0;

    for w in data_start..primary_arr.len() {
        let wt = &primary_arr[w];

        // Word-collapsed form: strip sentinels so dividers appear inline
        form_cols.push(wt.replace(SENTINEL, ""));

        if let Some(lgi) = lex_gloss_idx {
            let l_arr = &ex.line_arrays[lgi];
            if wt.contains(SENTINEL) {
                // Segmented word: assemble gloss inline, same algorithm as render_flex
                let parts: Vec<&str> = wt.split(SENTINEL).collect();
                let part_count = parts.len() as isize - 1;
                let mut g_parts: Vec<String> = Vec::new();
                for (y, part) in parts.iter().enumerate() {
                    if part.is_empty() { continue; }
                    if part.len() == 1 && MORPH_DIVS.contains(part.chars().next().unwrap()) {
                        g_parts.push(part.to_string());
                        lex_gloss_offset -= 1;
                    } else {
                        let gi = (w as isize - data_start as isize)
                                  + lex_gloss_offset + y as isize;
                        let raw = l_arr.get((gi + data_start as isize) as usize)
                            .map(|s| s.as_str()).unwrap_or("");
                        g_parts.push(raw.replace(SENTINEL, ""));
                    }
                }
                gloss_cols.push(g_parts.join(""));
                lex_gloss_offset += part_count;
            } else {
                let gi2 = (w as isize - data_start as isize) + lex_gloss_offset;
                let raw = l_arr.get((gi2 + data_start as isize) as usize)
                    .map(|s| s.as_str()).unwrap_or("");
                gloss_cols.push(raw.replace(SENTINEL, ""));
            }
        }

        if let Some(wgi) = word_gloss_idx {
            let wg_arr = &ex.line_arrays[wgi];
            let wi = w - data_start;
            let raw = wg_arr.get(wi + data_start)
                .map(|s| s.as_str()).unwrap_or("");
            wgloss_cols.push(raw.replace(SENTINEL, ""));
        }
    }

    let mut rows: Vec<String> = Vec::new();
    rows.push(form_cols.join("\t"));
    if lex_gloss_idx.is_some()  { rows.push(gloss_cols.join("\t")); }
    if word_gloss_idx.is_some() { rows.push(wgloss_cols.join("\t")); }
    if !ex.free_lines.is_empty() { rows.push(ex.free_lines.join(" / ")); }

    rows.join("\n")
}

/// Render multiple parsed FLEx blocks to morpheme-aligned TSV.
/// Multiple blocks are separated by a blank line.
pub fn render_flex_tsv_auto(blocks: &[FlexParsed]) -> String {
    blocks.iter()
        .map(|b| render_flex_tsv(b))
        .collect::<Vec<_>>()
        .join("\n\n")
}

// ── TSV row template ──────────────────────────────────────────────────────────

/// Split a tab-separated line into trimmed fields. Index 0 = column 1.
pub fn parse_tsv_row(line: &str) -> Vec<String> {
    line.split('\t').map(|f| f.trim().to_string()).collect()
}

/// Apply a row template, substituting $WORD, $GLOSS, $ID, $COLn.
pub fn apply_row_template(tmpl: &str, fields: &[String]) -> String {
    let get = |i: usize| -> &str { fields.get(i).map(|s| s.as_str()).unwrap_or("") };

    // Resolve named aliases first (matching JS order)
    let s = tmpl
        .replace("$WORD",  get(1))  // col 2
        .replace("$GLOSS", get(2))  // col 3
        .replace("$ID",    get(5)); // col 6

    // Resolve $COLn patterns with a manual scan
    let chars: Vec<char> = s.chars().collect();
    let mut result = String::new();
    let mut i = 0;
    while i < chars.len() {
        if chars[i] == '$'
            && chars.get(i+1) == Some(&'C')
            && chars.get(i+2) == Some(&'O')
            && chars.get(i+3) == Some(&'L')
        {
            let mut j = i + 4;
            while j < chars.len() && chars[j].is_ascii_digit() { j += 1; }
            if j > i + 4 {
                let num: usize = chars[i+4..j].iter().collect::<String>().parse().unwrap_or(0);
                result.push_str(get(num.saturating_sub(1)));
                i = j;
                continue;
            }
        }
        result.push(chars[i]);
        i += 1;
    }
    result
}

/// Return the 1-based column numbers referenced in the template (for skip logic).
pub fn referenced_cols(tmpl: &str) -> Vec<usize> {
    let mut cols: Vec<usize> = Vec::new();
    let mut add = |n: usize| { if !cols.contains(&n) { cols.push(n); } };

    if tmpl.contains("$WORD")  { add(2); }
    if tmpl.contains("$GLOSS") { add(3); }
    if tmpl.contains("$ID")    { add(6); }

    let chars: Vec<char> = tmpl.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        if chars[i] == '$'
            && chars.get(i+1) == Some(&'C')
            && chars.get(i+2) == Some(&'O')
            && chars.get(i+3) == Some(&'L')
        {
            let mut j = i + 4;
            while j < chars.len() && chars[j].is_ascii_digit() { j += 1; }
            if j > i + 4 {
                let n: usize = chars[i+4..j].iter().collect::<String>().parse().unwrap_or(0);
                add(n);
            }
            i = j;
        } else {
            i += 1;
        }
    }
    cols
}
