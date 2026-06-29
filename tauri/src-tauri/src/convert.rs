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
            '\u{200B}' | '\u{200E}' | '\u{200F}' | '\u{202A}'..='\u{202E}'
        ))
        .collect()
}

/// True for a Unicode directional mark (the marks FLEx uses to bracket a
/// writing-system code on Free/Lit lines). Excludes ZWSP, matching DIR_CLASS in
/// docs/core.js.
fn is_dir(c: char) -> bool {
    matches!(c, '\u{200E}' | '\u{200F}' | '\u{202A}'..='\u{202E}')
}

/// Strip leading whitespace and directional marks; return the remaining slice.
fn trim_leading_ws_dir(s: &str) -> &str {
    let mut idx = 0;
    for c in s.chars() {
        if c.is_whitespace() || is_dir(c) { idx += c.len_utf8(); } else { break; }
    }
    &s[idx..]
}

/// Byte length of a leading writing-system code (incl. its trailing mark), or 0.
/// Pattern: optional ws/dir marks, 1–5 ASCII letters, then a directional mark.
/// A genuine first word of a translation is followed by a space, not a mark, so
/// it never matches. Mirrors CODE_RE in docs/core.js.
fn ws_code_len(s: &str) -> usize {
    let mut chars = s.char_indices().peekable();
    let mut consumed = 0usize; // byte length skipped so far
    // leading ws / dir marks
    while let Some(&(i, c)) = chars.peek() {
        if c.is_whitespace() || is_dir(c) { consumed = i + c.len_utf8(); chars.next(); } else { break; }
    }
    // 1–5 ASCII letters
    let mut n = 0;
    let mut end = consumed;
    while let Some(&(i, c)) = chars.peek() {
        if c.is_ascii_alphabetic() && n < 5 { n += 1; end = i + c.len_utf8(); chars.next(); } else { break; }
    }
    if n == 0 { return 0; }
    // immediately followed by a directional mark
    if let Some(&(i, c)) = chars.peek() {
        if is_dir(c) { return i + c.len_utf8(); }
    }
    let _ = end;
    0
}

/// If `head` (already ws/dir-trimmed) starts with a Free/Lit label, return its
/// byte length and whether it is a literal-translation line. Mirrors the
/// /^(Free\b|Lit\.)/i test in docs/core.js.
fn match_free_label(head: &str) -> Option<(usize, bool)> {
    let lower = head.to_lowercase();
    if lower.starts_with("lit.") { return Some((4, true)); }
    if lower.starts_with("free") {
        let next = head[4..].chars().next();
        let boundary = match next { None => true, Some(c) => !(c.is_alphanumeric() || c == '_') };
        if boundary { return Some((4, false)); }
    }
    None
}

/// Byte length of a leading example number matching \d+(\.\d+)? else 0.
fn lead_num_len(s: &str) -> usize {
    let b = s.as_bytes();
    let mut i = 0;
    while i < b.len() && b[i].is_ascii_digit() { i += 1; }
    if i == 0 { return 0; }
    if i < b.len() && b[i] == b'.' {
        let mut j = i + 1;
        while j < b.len() && b[j].is_ascii_digit() { j += 1; }
        if j > i + 1 { i = j; }
    }
    i
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
            '\\' => result.push_str("\\textbackslash{}"),
            '~'  => result.push_str("\\textasciitilde{}"),
            '^'  => result.push_str("\\textasciicircum{}"),
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

/// Apply a case transform to a gloss abbreviation string.
/// `case_opt`: "lowercase" | "uppercase" | "capitalize" | "none"
fn apply_gloss_case(s: &str, case_opt: &str) -> String {
    match case_opt {
        "uppercase"  => s.to_uppercase(),
        "capitalize" => {
            let mut chars = s.chars();
            match chars.next() {
                None    => String::new(),
                Some(c) => c.to_uppercase().to_string() + &chars.as_str().to_lowercase(),
            }
        }
        "none"       => s.to_string(),
        _            => s.to_lowercase(),  // "lowercase" (default)
    }
}

/// Apply gloss case transform to grammatical segments in a plain token
/// (no command wrapping — used for TSV output).
fn transform_gloss_token(token: &str, gloss_case: &str) -> String {
    if token.is_empty() { return String::new(); }
    let mut parts: Vec<String> = Vec::new();
    let mut cur = String::new();

    for ch in token.chars() {
        if MORPH_DIVS.contains(ch) || ch == '.' {
            if !cur.is_empty() {
                parts.push(if is_gram_gloss(&cur) {
                    apply_gloss_case(&cur, gloss_case)
                } else {
                    cur.clone()
                });
                cur.clear();
            }
            parts.push(ch.to_string());
        } else {
            cur.push(ch);
        }
    }
    if !cur.is_empty() {
        parts.push(if is_gram_gloss(&cur) {
            apply_gloss_case(&cur, gloss_case)
        } else {
            cur.clone()
        });
    }
    parts.join("")
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

/// Wrap grammatical gloss segments in `gl_cmd`, applying `gloss_case` transform.
/// Non-gloss segments are LaTeX-escaped. Splits on morpheme dividers and '.'.
pub fn wrap_glosses(token: &str, gl_cmd: &str, gloss_case: &str) -> String {
    if token.is_empty() { return String::new(); }
    let mut parts: Vec<String> = Vec::new();
    let mut cur = String::new();

    for ch in token.chars() {
        if MORPH_DIVS.contains(ch) || ch == '.' {
            if !cur.is_empty() {
                parts.push(if !gl_cmd.is_empty() && is_gram_gloss(&cur) {
                    format!("{}{{{}}}", gl_cmd, apply_gloss_case(&cur, gloss_case))
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
            format!("{}{{{}}}", gl_cmd, apply_gloss_case(&cur, gloss_case))
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

// ── Word-grouping algorithm (tab-format columns) ──────────────────────────────

#[derive(Debug, Clone)]
struct Word {
    form: String,
    gloss_parts: Vec<String>,
}

struct Morph { m: String, g: String }

/// Join a gathered gloss piece onto a morpheme's running gloss. See docs/core.js
/// appendGloss: gathered pieces are within-morpheme continuations unless the
/// source has only a whole-word tier (`whole_word`), where a neutral "-" is
/// inserted between distinct morpheme glosses.
fn append_gloss(g: &str, ng: &str, whole_word: bool) -> String {
    if g.is_empty() { return ng.to_string(); }
    let c0 = ng.chars().next().unwrap_or('\0');
    if c0 == '.' || MORPH_DIVS.contains(c0) { return format!("{}{}", g, ng); }
    if MORPH_DIVS.contains(g.chars().last().unwrap_or('\0')) { return format!("{}{}", g, ng); }
    if whole_word { format!("{}-{}", g, ng) } else { format!("{}{}", g, ng) }
}

/// Collapse padded columns into morphemes, gathering each morpheme's multi-column
/// gloss from the empty-morpheme columns that follow it. Iterates to the longer
/// of the two arrays so trailing gloss columns are never dropped.
fn collapse_morphemes(
    morphemes: &[String],
    lex_glosses: &[String],
    start_idx: usize,
    whole_word: bool,
) -> Vec<Morph> {
    let n = morphemes.len().max(lex_glosses.len());
    let mut list: Vec<Morph> = Vec::new();
    let mut i = start_idx;
    while i < n {
        let m = morphemes.get(i).map(|s| s.trim()).unwrap_or("");
        let mut g = lex_glosses.get(i).map(|s| s.trim()).unwrap_or("").to_string();
        if !m.is_empty() {
            let mut j = i + 1;
            while j < n && morphemes.get(j).map(|s| s.trim().is_empty()).unwrap_or(true) {
                let ng = lex_glosses.get(j).map(|s| s.trim()).unwrap_or("");
                if !ng.is_empty() { g = append_gloss(&g, ng, whole_word); }
                j += 1;
            }
            list.push(Morph { m: m.to_string(), g });
            i = j;
        } else {
            if !g.is_empty() { list.push(Morph { m: String::new(), g }); }
            i += 1;
        }
    }
    list
}

fn new_word(m: &str, g: &str) -> Word {
    Word { form: m.to_string(), gloss_parts: if g.is_empty() { Vec::new() } else { vec![g.to_string()] } }
}

/// Group collapsed morphemes into words by divider DIRECTION:
///   leading  - = ~ < >  → suffix/enclitic, attaches to the PREVIOUS word
///   trailing - = ~ < >  → prefix/proclitic, attaches to the NEXT word
///   no divider           → root, starts a new word
fn group_words_from_columns(
    morphemes: &[String],
    lex_glosses: &[String],
    start_idx: usize,
    whole_word: bool,
) -> Vec<Word> {
    let morph_list = collapse_morphemes(morphemes, lex_glosses, start_idx, whole_word);
    let mut words: Vec<Word> = Vec::new();
    let mut cur: Option<Word> = None;
    let mut await_host: char = '\0'; // trailing divider of a prefix/proclitic awaiting its host

    for mo in &morph_list {
        let (m, g) = (mo.m.as_str(), mo.g.as_str());

        if m.is_empty() {
            if let Some(cw) = cur.take() { words.push(cw); }
            await_host = '\0';
            words.push(new_word("", g));
            continue;
        }

        let first = m.chars().next().unwrap();
        let last  = m.chars().last().unwrap();
        let lead  = MORPH_DIVS.contains(first);
        let trail = MORPH_DIVS.contains(last);

        if lead {
            // suffix / enclitic → attach to current word (left)
            if let Some(ref mut cw) = cur {
                cw.form.push_str(m);
                cw.gloss_parts.push(if g.is_empty() { first.to_string() } else { format!("{}{}", first, g) });
            } else {
                cur = Some(new_word(m, g));
            }
            continue;
        }

        if trail {
            // prefix / proclitic → attaches to the NEXT word (right)
            if cur.is_some() && await_host != '\0' {
                if let Some(ref mut cw) = cur {
                    cw.form.push_str(m);
                    if !g.is_empty() { cw.gloss_parts.push(format!("{}{}", await_host, g)); }
                }
            } else {
                if let Some(cw) = cur.take() { words.push(cw); }
                cur = Some(new_word(m, g));
            }
            await_host = last;
            continue;
        }

        // pure root
        if cur.is_some() && await_host != '\0' {
            if let Some(ref mut cw) = cur {
                cw.form.push_str(m);
                if !g.is_empty() { cw.gloss_parts.push(format!("{}{}", await_host, g)); }
            }
            await_host = '\0';
        } else {
            if let Some(cw) = cur.take() { words.push(cw); }
            cur = Some(new_word(m, g));
        }
    }

    if let Some(cw) = cur { words.push(cw); }
    words
}

/// Special case: standalone punctuation (single char, empty gloss) appends
/// to preceding word's form only, no gloss contribution.
fn handle_standalone_punctuation(words: &mut Vec<Word>) {
    let punct_chars = "\u{2026},:;.!?-\u{2012}\u{2013}\u{2014}\u{2015}/|&";
    let mut i = 1;
    while i < words.len() {
        let single = words[i].form.chars().next();
        let is_punct = words[i].form.chars().count() == 1
            && single.map_or(false, |c| punct_chars.contains(c))
            && words[i].gloss_parts.is_empty();
        if is_punct {
            let punct_form = words[i].form.clone();
            words[i - 1].form.push_str(&punct_form);
            words.remove(i);
        } else {
            i += 1;
        }
    }
}

// ── FLEx parser ───────────────────────────────────────────────────────────────

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct FlexParsed {
    pub line_types:  Vec<String>,
    pub col_arrays:  Vec<Vec<String>>,
    pub free_lines:  Vec<String>,
    pub lit_lines:   Vec<String>,
    pub line_num:    Option<String>,
}

/// Parse one tab-column FLEx line into [label, tok1, tok2, …].
///
/// (This function is no longer used; replaced by column-aware parsing in parse_flex_block.)
fn _unused_flex_tab_line_toks(l: &str) -> Vec<String> {
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
    let mut col_arrays:  Vec<Vec<String>> = Vec::new();
    let mut free_lines:  Vec<String> = Vec::new();
    let mut lit_lines:   Vec<String> = Vec::new();
    let mut line_num:    Option<String> = None;
    let mut seen_free = false;
    let mut last_lit  = false;

    // Strip trailing SPACES only — trailing tabs are significant columns (FLEx
    // pads short tiers with empty cells; trimming them drops trailing glosses).
    let raw_lines: Vec<&str> = text.lines()
        .map(|l| l.trim_end_matches(' '))
        .filter(|l| !strip_invisible(l).trim().is_empty())
        .collect();

    for raw_line in raw_lines {
        let mut l = raw_line.to_string();

        // Extract leading example number (e.g. "1" or "1.2") if not yet found
        if line_num.is_none() {
            let trimmed = l.trim();
            let num_end = lead_num_len(trimmed);
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

        // Free / Lit translation line. Marks are preserved so a writing-system
        // code can be detected — FLEx brackets the code with directional marks,
        // while a genuine first word of the translation is followed by a space.
        let head = trim_leading_ws_dir(&l);
        if let Some((label_len, is_lit)) = match_free_label(head) {
            seen_free = true;
            last_lit  = is_lit;
            let rest = &head[label_len..];
            let ft = strip_invisible(&rest[ws_code_len(rest)..]).trim().to_string();
            if !ft.is_empty() {
                if is_lit { lit_lines.push(ft); } else { free_lines.push(ft); }
            }
            continue;
        }

        // Continuation line carrying an additional writing system (e.g. " Ind …").
        if seen_free {
            let code = ws_code_len(&l);
            if code > 0 {
                let cont = strip_invisible(&l[code..]).trim().to_string();
                if !cont.is_empty() {
                    if last_lit { lit_lines.push(cont); } else { free_lines.push(cont); }
                }
                continue;
            }
        }

        let mut cols: Vec<String> = if l.contains('\t') {
            // Tab-column FLEx format: return raw column array
            let normalized = strip_invisible(&l)
                .replace("Lex. Entries", "LexEntries")
                .replace("Lex. Gloss",   "LexGloss")
                .replace("Word Gloss",   "WordGloss")
                .replace("Word Cat.",    "WordCat");
            normalized.split('\t')
                .map(|c| c.trim().to_string())
                .collect()
        } else {
            // Space-separated fallback (legacy / non-FLEx sources)
            let massaged = massage_line(&strip_invisible(&l));
            massaged.split_whitespace()
                .filter(|t| !t.is_empty())
                .map(|t| t.to_string())
                .collect()
        };

        // If first column is empty, shift left (skip the leading empty column
        // that occurs when the tier label is in column 1)
        if !cols.is_empty() && cols[0].is_empty() {
            cols.remove(0);
        }

        if cols.is_empty() { continue; }
        line_types.push(cols[0].clone());
        col_arrays.push(cols);
    }

    FlexParsed { line_types, col_arrays, free_lines, lit_lines, line_num }
}

// ── FLEx renderer ─────────────────────────────────────────────────────────────

#[derive(Debug, Clone, serde::Deserialize, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FlexOpts {
    pub gl_cmd:        String,
    pub gloss_case:    String,
    pub form_cmd:      String,
    pub wrap_exe:      bool,
    pub txtref_cmd:    String,
    pub txtref_prefix: String,
}

impl Default for FlexOpts {
    fn default() -> Self {
        FlexOpts {
            gl_cmd:        "\\textsc".to_string(),
            gloss_case:    "capitalize".to_string(),
            form_cmd:      "\\textit".to_string(),
            wrap_exe:      true,
            txtref_cmd:    "%\\txtref".to_string(),
            txtref_prefix: "TXT:".to_string(),
        }
    }
}

/// Choose the form tier (Morphemes/LexEntries, else Word) and the gloss tier
/// (LexGloss preferred — morpheme glosses; else WordGloss). Returns the form
/// index, optional gloss index, and whether the source is whole-word only.
fn pick_tiers(ex: &FlexParsed) -> Option<(usize, Option<usize>, bool)> {
    let lt = &ex.line_types;
    let mut morph_idx: Option<usize> = None;
    let mut gloss_idx: Option<usize> = None;
    for t in 0..lt.len() {
        if morph_idx.is_none() && (lt[t] == "Morphemes" || lt[t] == "LexEntries") { morph_idx = Some(t); }
        if gloss_idx.is_none() && lt[t] == "LexGloss" { gloss_idx = Some(t); }
    }
    if morph_idx.is_none() {
        for t in 0..lt.len() { if lt[t] == "Word" { morph_idx = Some(t); break; } }
    }
    if gloss_idx.is_none() {
        for t in 0..lt.len() { if lt[t] == "WordGloss" { gloss_idx = Some(t); break; } }
    }
    let mi = morph_idx?;
    let whole_word = lt[mi] == "Word" && gloss_idx.map_or(false, |gi| lt[gi] == "LexGloss");
    Some((mi, gloss_idx, whole_word))
}

/// Run tier selection + word grouping. Returns (words, has_gloss).
fn build_words(ex: &FlexParsed) -> Option<(Vec<Word>, bool)> {
    let (morph_idx, gloss_idx, whole_word) = pick_tiers(ex)?;
    let morphemes_arr = &ex.col_arrays[morph_idx];
    let mut data_start = 1usize;
    if morphemes_arr.get(data_start).map_or(false, |s| s.parse::<u64>().is_ok()) {
        data_start += 1;
    }
    let empty = Vec::new();
    let gloss_arr = gloss_idx.map(|i| &ex.col_arrays[i]).unwrap_or(&empty);
    let mut words = group_words_from_columns(morphemes_arr, gloss_arr, data_start, whole_word);
    handle_standalone_punctuation(&mut words);
    Some((words, gloss_idx.is_some()))
}

pub fn render_flex(ex: &FlexParsed, opts: &FlexOpts) -> String {
    let (words, has_gloss) = match build_words(ex) {
        None      => return "% (no recognisable tier lines — check labels)".to_string(),
        Some(v)   => v,
    };

    let mut tier1: Vec<String> = Vec::new();
    let mut tier2: Vec<String> = Vec::new();

    let float_punct = "-\u{2012}\u{2013}\u{2014}\u{2015}/|&\u{2026}...";

    for word in &words {
        // Check for floating punctuation
        if word.form.chars().count() == 1 && float_punct.contains(&word.form) {
            tier1.push(word.form.clone());
            if has_gloss { tier2.push("\\textasciitilde".to_string()); }
            continue;
        }

        // Empty form: use escaped ~ placeholder for gb4e
        if word.form.is_empty() {
            tier1.push("\\textasciitilde".to_string());
        } else {
            tier1.push(escape_latex(&word.form));
        }

        if has_gloss {
            tier2.push(wrap_glosses(&word.gloss_parts.join(""), &opts.gl_cmd, &opts.gloss_case));
        }
    }

    // Build LaTeX lines
    let tier_count = 1 + if has_gloss { 1 } else { 0 };
    let g_cmd  = format!("g{}", "l".repeat(tier_count));       // e.g. "gll"
    // NOTE: No indentation here intentionally.
    // The Rust path delivers output via enigo key events (Return between lines),
    // not as a clipboard paste. Indented lines would trigger editor auto-indent
    // (Sublime Text, VS Code, etc.) and produce doubled/wrong indentation.
    // The JS/web path DOES use indentation because its output goes into a
    // <textarea> and is copied as a block — see docs/core.js render functions.
    // Do not "fix" this divergence: it is load-bearing.
    let indent = "";

    let tier1_content = if opts.form_cmd.is_empty() {
        tier1.join(" ")
    } else {
        tier1.iter()
            .map(|t| format!("{}{{{}}}", opts.form_cmd, t))
            .collect::<Vec<_>>()
            .join(" ")
    };

    let mut lines: Vec<String> = Vec::new();
    lines.push(format!("\\{} {} \\\\", g_cmd, tier1_content));
    if has_gloss { lines.push(format!("{}{} \\\\", indent, tier2.join(" "))); }

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
    // NOTE: No indentation applied to xlist items — see comment in render_flex.
    let items: Vec<String> = blocks.iter().map(|block| {
        let body = render_flex(block, &sub_opts);
        format!("\\ex % \\label{{ex:KEY}}\n{}", body.trim())
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
/// dividers are joined inline (e.g. vu=ve, levo-z).
/// `opts.gloss_case` controls the case transform applied to grammatical gloss segments.
pub fn render_flex_tsv(ex: &FlexParsed, opts: &FlexOpts) -> String {
    let (words, has_gloss) = match build_words(ex) {
        None    => return "(no recognisable tier lines — check labels)".to_string(),
        Some(v) => v,
    };

    let mut form_cols:  Vec<String> = Vec::new();
    let mut gloss_cols: Vec<String> = Vec::new();

    for word in &words {
        form_cols.push(word.form.clone());
        if has_gloss {
            gloss_cols.push(transform_gloss_token(&word.gloss_parts.join(""), &opts.gloss_case));
        }
    }

    let mut rows: Vec<String> = Vec::new();
    rows.push(form_cols.join("\t"));
    if has_gloss { rows.push(gloss_cols.join("\t")); }
    if !ex.free_lines.is_empty() { rows.push(ex.free_lines.join(" / ")); }

    rows.join("\n")
}

/// Render multiple parsed FLEx blocks to morpheme-aligned TSV.
/// Multiple blocks are separated by a blank line.
pub fn render_flex_tsv_auto(blocks: &[FlexParsed], opts: &FlexOpts) -> String {
    blocks.iter()
        .map(|b| render_flex_tsv(b, opts))
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
