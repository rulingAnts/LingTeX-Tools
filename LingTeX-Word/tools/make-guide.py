#!/usr/bin/env python3
"""make-guide.py -- LingTeX-Word

Renders GUIDE.md, the user guide, to a PDF with the ribbon icons inline, so
the guide that ships with a release is built from the same Markdown that
GitHub shows, and the icons in it are the ones on the ribbon.

    python3 LingTeX-Word/tools/make-guide.py                       # build/LingTeX-Word-Guide.pdf
    python3 LingTeX-Word/tools/make-guide.py --version word-v0.1.0-beta.4 --out out/Guide.pdf

Needs python-markdown, reportlab and Pillow (pip install markdown reportlab
pillow); nothing else, so the release workflow can run it on a bare runner
in seconds. Word is not involved.

The Markdown subset is what GUIDE.md uses: headings, paragraphs, bullet and
numbered lists (nested), tables, fenced code, inline bold / italic / code /
links, and images. An image inside a paragraph is drawn inline at text height
(that is how the icons appear next to a button's name); an image alone in a
paragraph is drawn as a block. Text is set in Helvetica, whose repertoire is
Windows-1252: a character outside it is reported and replaced, so write the
guide within it (curly quotes and the en dash are fine; arrows and IPA are
not).
"""
import argparse
import datetime
import html
import os
import sys
from html.parser import HTMLParser

try:
    import markdown
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.styles import ParagraphStyle
    from reportlab.lib.units import mm
    from reportlab.pdfbase.pdfmetrics import stringWidth
    from reportlab.platypus import (HRFlowable, Image, KeepTogether, ListFlowable,
                                    ListItem, PageBreak, Paragraph, Preformatted,
                                    SimpleDocTemplate, Spacer, Table, TableStyle)
except ImportError as e:  # pragma: no cover
    sys.exit("make-guide: missing a library (%s); pip install markdown reportlab pillow" % e)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GUIDE = os.path.join(ROOT, "GUIDE.md")

BODY_SIZE = 10.5
LEADING = 14.5
ICON_PT = 13          # inline icon height, a little over the x-height plus ascender

# -- styles ------------------------------------------------------------------
BASE = ParagraphStyle("body", fontName="Helvetica", fontSize=BODY_SIZE, leading=LEADING,
                      spaceAfter=6)
STYLES = {
    "title": ParagraphStyle("title", parent=BASE, fontName="Helvetica-Bold", fontSize=26,
                            leading=32, spaceAfter=6),
    "subtitle": ParagraphStyle("subtitle", parent=BASE, fontName="Helvetica-Oblique",
                               fontSize=13, leading=18, textColor=colors.HexColor("#444444"),
                               spaceAfter=18),
    "h1": ParagraphStyle("h1", parent=BASE, fontName="Helvetica-Bold", fontSize=18, leading=23,
                         spaceBefore=18, spaceAfter=8, keepWithNext=True),
    "h2": ParagraphStyle("h2", parent=BASE, fontName="Helvetica-Bold", fontSize=13.5,
                         leading=18, spaceBefore=12, spaceAfter=5, keepWithNext=True),
    "h3": ParagraphStyle("h3", parent=BASE, fontName="Helvetica-BoldOblique", fontSize=11,
                         leading=15, spaceBefore=8, spaceAfter=3, keepWithNext=True),
    "p": BASE,
    "cell": ParagraphStyle("cell", parent=BASE, fontSize=9.5, leading=12.5, spaceAfter=0),
    "cellhead": ParagraphStyle("cellhead", parent=BASE, fontName="Helvetica-Bold",
                               fontSize=9.5, leading=12.5, spaceAfter=0),
    "li": ParagraphStyle("li", parent=BASE, spaceAfter=2),
    "quote": ParagraphStyle("quote", parent=BASE, fontName="Helvetica-Oblique",
                            leftIndent=12, textColor=colors.HexColor("#333333")),
    "pre": ParagraphStyle("pre", parent=BASE, fontName="Courier", fontSize=8.8, leading=11,
                          leftIndent=8, backColor=colors.HexColor("#F3F3F3"), spaceBefore=4,
                          spaceAfter=8),
    "footer": ParagraphStyle("footer", parent=BASE, fontSize=8.5, leading=10,
                             textColor=colors.HexColor("#666666")),
}


# -- a tiny HTML tree --------------------------------------------------------
class Node:
    def __init__(self, tag, attrs=None):
        self.tag = tag
        self.attrs = dict(attrs or [])
        self.children = []   # Node or str

    def text(self):
        return "".join(c if isinstance(c, str) else c.text() for c in self.children)


class TreeBuilder(HTMLParser):
    VOID = {"img", "br", "hr"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node("root")
        self.stack = [self.root]

    def handle_starttag(self, tag, attrs):
        node = Node(tag, attrs)
        self.stack[-1].children.append(node)
        if tag not in self.VOID:
            self.stack.append(node)

    def handle_startendtag(self, tag, attrs):
        self.stack[-1].children.append(Node(tag, attrs))

    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i].tag == tag:
                del self.stack[i:]
                return

    def handle_data(self, data):
        self.stack[-1].children.append(data)


# -- inline markup -----------------------------------------------------------
class Guide:
    def __init__(self, md_path, version, out):
        self.md_path = md_path
        self.base = os.path.dirname(os.path.abspath(md_path))
        self.version = version
        self.out = out
        self.bad_chars = set()
        # The text column: the page less the margins less the frame's own 6pt
        # of padding each side, which paragraphs respect and a Table sized to
        # the bare column would overhang (the review, 2026-09-14).
        self.width = A4[0] - 2 * 22 * mm - 12

    def esc(self, s):
        # Helvetica is WinAnsi; say what falls outside rather than print a box.
        out = []
        for ch in s:
            try:
                ch.encode("cp1252")
                out.append(ch)
            except UnicodeEncodeError:
                self.bad_chars.add(ch)
                out.append("?")
        return html.escape("".join(out), quote=False)

    def img_path(self, src):
        p = src if os.path.isabs(src) else os.path.normpath(os.path.join(self.base, src))
        if not os.path.exists(p):
            sys.exit("make-guide: image not found: %s (from %s)" % (p, src))
        return p

    def inline(self, node):
        """A node's children as reportlab paragraph markup."""
        parts = []
        for c in node.children:
            if isinstance(c, str):
                parts.append(self.esc(c))
                continue
            t = c.tag
            if t in ("strong", "b"):
                parts.append("<b>%s</b>" % self.inline(c))
            elif t in ("em", "i"):
                parts.append("<i>%s</i>" % self.inline(c))
            elif t == "code":
                parts.append('<font face="Courier" size="%.1f">%s</font>'
                             % (BODY_SIZE - 1, self.esc(c.text())))
            elif t == "a":
                href = c.attrs.get("href", "")
                parts.append('<a href="%s" color="#1a5fb4"><u>%s</u></a>'
                             % (html.escape(href, quote=True), self.inline(c)))
            elif t == "img":
                p = self.img_path(c.attrs.get("src", ""))
                w, h = self.image_size(p, ICON_PT)
                parts.append('<img src="%s" width="%.1f" height="%.1f" valign="-3"/>'
                             % (p, w, h))
            elif t == "br":
                parts.append("<br/>")
            elif t == "kbd":
                parts.append('<font face="Courier" size="%.1f">%s</font>'
                             % (BODY_SIZE - 1, self.esc(c.text())))
            else:
                parts.append(self.inline(c))
        return "".join(parts)

    @staticmethod
    def image_size(path, height=None, max_width=None):
        from PIL import Image as PILImage
        with PILImage.open(path) as im:
            w, h = im.size
        if height is not None:
            return height * w / h, height
        if max_width is not None and w > max_width:
            return max_width, max_width * h / w
        return w * 0.75, h * 0.75      # 96 dpi pixels to points

    # -- blocks ----------------------------------------------------------------
    def blocks(self, node, story, in_list=0):
        for c in node.children:
            if isinstance(c, str):
                if c.strip():
                    story.append(Paragraph(self.esc(c.strip()), STYLES["p"]))
                continue
            t = c.tag
            if t == "h1":
                story.append(Paragraph(self.inline(c), STYLES["h1"]))
            elif t == "h2":
                story.append(Paragraph(self.inline(c), STYLES["h2"]))
            elif t in ("h3", "h4"):
                story.append(Paragraph(self.inline(c), STYLES["h3"]))
            elif t == "p":
                imgs = [x for x in c.children if not isinstance(x, str) and x.tag == "img"]
                only_img = imgs and not "".join(
                    x for x in c.children if isinstance(x, str)).strip() and len(c.children) == len(imgs)
                if only_img:
                    for im in imgs:
                        p = self.img_path(im.attrs.get("src", ""))
                        w, h = self.image_size(p, max_width=self.width * 0.6)
                        story.append(Image(p, width=w, height=h, hAlign="LEFT"))
                        story.append(Spacer(1, 6))
                else:
                    story.append(Paragraph(self.inline(c), STYLES["li"] if in_list else STYLES["p"]))
            elif t in ("ul", "ol"):
                story.append(self.list_flowable(c, ordered=(t == "ol"), depth=in_list))
            elif t == "table":
                story.append(self.table(c))
                story.append(Spacer(1, 8))
            elif t == "pre":
                # Wrapped at the frame: a fenced line longer than the page would
                # otherwise run into the margin.
                code = c.text().rstrip("\n")
                per_line = int((self.width - STYLES["pre"].leftIndent - 4) / (0.6 * STYLES["pre"].fontSize))
                story.append(Preformatted(self.esc_plain(code), STYLES["pre"], maxLineLength=per_line))
            elif t == "hr":
                story.append(HRFlowable(width="100%", thickness=0.6, color=colors.HexColor("#BBBBBB"),
                                        spaceBefore=6, spaceAfter=10))
            elif t == "blockquote":
                for ch in c.children:
                    if not isinstance(ch, str):
                        story.append(Paragraph(self.inline(ch), STYLES["quote"]))
            elif t in ("div", "section", "body", "html"):
                self.blocks(c, story, in_list)
            else:
                story.append(Paragraph(self.inline(c), STYLES["p"]))

    def esc_plain(self, s):
        out = []
        for ch in s:
            try:
                ch.encode("cp1252")
                out.append(ch)
            except UnicodeEncodeError:
                self.bad_chars.add(ch)
                out.append("?")
        return "".join(out)

    def list_flowable(self, node, ordered, depth):
        items = []
        for li in node.children:
            if isinstance(li, str) or li.tag != "li":
                continue
            inner = []
            # inline text directly in the li, then any nested blocks
            direct = Node("p")
            for ch in li.children:
                if isinstance(ch, str) or ch.tag not in ("ul", "ol", "p", "pre", "table"):
                    direct.children.append(ch)
            if direct.text().strip() or any(not isinstance(x, str) for x in direct.children):
                inner.append(Paragraph(self.inline(direct), STYLES["li"]))
            for ch in li.children:
                if not isinstance(ch, str) and ch.tag in ("ul", "ol", "p", "pre", "table"):
                    self.blocks(Node("x", None) if False else self._wrap(ch), inner, depth + 1)
            items.append(ListItem(inner, leftIndent=14 + 12 * depth))
        return ListFlowable(items, bulletType="1" if ordered else "bullet",
                            start=None if not ordered else 1,
                            bulletFontName="Helvetica", bulletFontSize=BODY_SIZE - 1,
                            leftIndent=14 + 12 * depth, spaceAfter=4)

    @staticmethod
    def _wrap(node):
        w = Node("root")
        w.children.append(node)
        return w

    def table(self, node):
        rows, header = [], []
        for sect in node.children:
            if isinstance(sect, str):
                continue
            if sect.tag in ("thead", "tbody"):
                trs = [x for x in sect.children if not isinstance(x, str) and x.tag == "tr"]
            elif sect.tag == "tr":
                trs = [sect]
            else:
                continue
            for tr in trs:
                cells = [x for x in tr.children if not isinstance(x, str) and x.tag in ("th", "td")]
                is_head = sect.tag == "thead" or all(x.tag == "th" for x in cells)
                row = []
                for x in cells:
                    # The paragraph, and beside it the plain words the widths are
                    # measured from -- never the markup, whose image path would
                    # count as one very long word.
                    only_code = (len([ch for ch in x.children if not isinstance(ch, str)
                                      or ch.strip()]) == 1
                                 and any(not isinstance(ch, str) and ch.tag == "code"
                                         for ch in x.children))
                    row.append((Paragraph(self.inline(x), STYLES["cellhead" if is_head else "cell"]),
                                x.text().strip(), only_code))
                (header if is_head else rows).append(row)
        data = header + rows
        if not data:
            return Spacer(1, 1)
        ncols = max(len(r) for r in data)
        for r in data:
            while len(r) < ncols:
                r.append((Paragraph("", STYLES["cell"]), "", False))
        # Column widths: every column gets at least its longest single word
        # (measured, so nothing breaks mid-word), and the rest of the table's
        # width is shared in proportion to how much text each column holds,
        # clipped so one wordy column cannot squeeze the others to nothing.
        pad = 10
        mins, wants = [], []
        for ci in range(ncols):
            words, texts = [0.0], [0.0]
            for r in data:
                _, txt, code = r[ci]
                face = "Courier" if code else "Helvetica"
                has_icon = "<img " in r[ci][0].text
                texts.append(stringWidth(txt, face, 9.5) + (ICON_PT + 4 if has_icon else 0))
                for w in txt.split():
                    words.append(stringWidth(w, face, 9.5) + (ICON_PT + 4 if has_icon else 0))
            mins.append(max(words) + pad)
            wants.append(min(max(texts) + pad, self.width * 0.55))
        # A column is never narrower than its longest word, so nothing breaks
        # mid-word -- unless the words alone do not fit the page, when every
        # column is scaled and something has to. The old 0.4 cap split
        # LingTeXToggleRewrapOnSelectionChange across two lines.
        spare = self.width - sum(mins)
        if spare <= 0:
            widths = [self.width * m / sum(mins) for m in mins]
        else:
            extra = [max(w - m, 0) for w, m in zip(wants, mins)]
            total_extra = sum(extra) or 1.0
            widths = [m + spare * e / total_extra for m, e in zip(mins, extra)]
            # Whatever the wordy columns did not need goes to everyone equally.
            left = self.width - sum(widths)
            widths = [w + left / ncols for w in widths]
        t = Table([[c[0] for c in r] for r in data], colWidths=widths,
                  repeatRows=1 if header else 0, hAlign="LEFT")
        style = [
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("LINEBELOW", (0, 0), (-1, -1), 0.4, colors.HexColor("#CCCCCC")),
            ("TOPPADDING", (0, 0), (-1, -1), 3),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
            ("LEFTPADDING", (0, 0), (-1, -1), 4),
            ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ]
        if header:
            style += [("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#EEEEEE")),
                      ("LINEBELOW", (0, 0), (-1, 0), 0.8, colors.HexColor("#888888"))]
        t.setStyle(TableStyle(style))
        return t

    # -- the document ------------------------------------------------------------
    def build(self):
        with open(self.md_path, encoding="utf-8") as f:
            md = f.read()
        # The first H1 and the italic line under it become the title page.
        html_text = markdown.markdown(md, extensions=["tables", "fenced_code", "sane_lists"])
        tb = TreeBuilder()
        tb.feed(html_text)
        root = tb.root

        story = []
        # Markdown's HTML has newlines between blocks; they are not content.
        root.children = [c for c in root.children if not (isinstance(c, str) and not c.strip())]
        first = root.children[0] if root.children else None
        if first is not None and not isinstance(first, str) and first.tag == "h1":
            story.append(Spacer(1, 60 * mm))
            story.append(Paragraph(self.inline(first), STYLES["title"]))
            root.children.pop(0)
            nxt = root.children[0] if root.children else None
            if nxt is not None and not isinstance(nxt, str) and nxt.tag == "p":
                story.append(Paragraph(self.inline(nxt), STYLES["subtitle"]))
                root.children.pop(0)
            story.append(Paragraph(self.esc(self.version), STYLES["p"]))
            story.append(Paragraph(self.esc(datetime.date.today().strftime("%d %B %Y")), STYLES["p"]))
            story.append(PageBreak())
        self.blocks(root, story)

        version = self.version

        def footer(canvas, doc):
            canvas.saveState()
            canvas.setFont("Helvetica", 8.5)
            canvas.setFillColor(colors.HexColor("#666666"))
            canvas.drawString(22 * mm + 6, 13 * mm, "LingTeX-Word User Guide  -  " + version)
            canvas.drawRightString(A4[0] - 22 * mm - 6, 13 * mm, str(doc.page))
            canvas.restoreState()

        os.makedirs(os.path.dirname(os.path.abspath(self.out)), exist_ok=True)
        doc = SimpleDocTemplate(self.out, pagesize=A4, leftMargin=22 * mm, rightMargin=22 * mm,
                                topMargin=20 * mm, bottomMargin=22 * mm,
                                title="LingTeX-Word User Guide", author="LingTeX Tools")
        doc.build(story, onFirstPage=footer, onLaterPages=footer)
        print("make-guide: wrote %s (%d pages)" % (self.out, doc.page))
        if self.bad_chars:
            # Loud, so a release cannot ship a guide with question marks in it.
            sys.exit("make-guide: characters outside Helvetica's repertoire were replaced with ?: "
                     + " ".join("U+%04X" % ord(c) for c in sorted(self.bad_chars))
                     + " -- rewrite them in GUIDE.md")


def main():
    ap = argparse.ArgumentParser(description="Render GUIDE.md to PDF.")
    ap.add_argument("--version", default="development build",
                    help="the release tag to print on the title page and in the footer")
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "LingTeX-Word-Guide.pdf"))
    ap.add_argument("--source", default=GUIDE)
    a = ap.parse_args()
    Guide(a.source, a.version, a.out).build()


if __name__ == "__main__":
    main()
