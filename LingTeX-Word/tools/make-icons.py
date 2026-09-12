#!/usr/bin/env python3
"""make-icons.py -- LingTeX-Word

Draws the ribbon icons into src/icons/*.png.

The buttons act on interlinear examples, which are tables to Word but not to the
user, so no icon shows a grid except Convert Table's, whose input really is one.
Insert shows what the user gets: a little page carrying a three-line interlinear
example (source, glosses, free translation). Every other button is one plain
symbol for what it does, big enough to tell apart at a glance: the re-wrap
family shares the cycle arrow and differs by a corner mark (all / on save / on
leave), the alignment pair is a word as one block or as two, the rest are the
obvious sign in a coloured disc.

Every icon is drawn at 4x and downsampled, so the edges are smooth at the size
Office shows them: 64 px for the large buttons (32 logical, sharp on Retina), 32
px for the small ones. build-dotm.sh embeds the PNGs in the template and writes
the relationships the ribbon's image="..." attributes refer to; the file's base
name is the relationship id, so src/customUI14.xml says image="igtInsert" for
src/icons/igtInsert.png.

Needs Pillow and the macOS system fonts (Arial and Apple Symbols); the PNGs are
committed, so nobody else needs to run this.

    python3 LingTeX-Word/tools/make-icons.py            # write src/icons/
    python3 LingTeX-Word/tools/make-icons.py sheet.png  # also a contact sheet
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "src", "icons")

S = 4                     # supersampling factor
BASE = 64                 # canvas in final pixels for the large icons
FONTS = "/System/Library/Fonts/Supplemental/"
F_REG = FONTS + "Arial.ttf"
F_BOLD = FONTS + "Arial Bold.ttf"
F_ITAL = FONTS + "Arial Italic.ttf"
F_SYM = "/System/Library/Fonts/Apple Symbols.ttf"

# palette: the page reads on a light and on a dark ribbon alike
PAGE = (255, 255, 255, 255)
PAGE_EDGE = (150, 150, 150, 255)
SOURCE = (33, 33, 33, 255)
GLOSS = (70, 80, 88, 255)
FREE = (26, 95, 180, 255)
BLUE = (43, 87, 154, 255)
GREEN = (46, 125, 50, 255)
ORANGE = (214, 106, 24, 255)
SLATE = (84, 94, 102, 255)
PURPLE = (94, 53, 177, 255)
WHITE = (255, 255, 255, 255)


def font(path, px):
    return ImageFont.truetype(path, int(px * S))


def canvas():
    return Image.new("RGBA", (BASE * S, BASE * S), (0, 0, 0, 0))


def px(v):
    return int(round(v * S))


def page(d, x0=6, y0=4, x1=58, y1=60):
    d.rounded_rectangle((px(x0), px(y0), px(x1), px(y1)), radius=px(4),
                        fill=PAGE, outline=PAGE_EDGE, width=px(1.5))


def text(d, x, y, s, f, colour):
    d.text((px(x), px(y)), s, font=f, fill=colour)


def width(f, s):
    return f.getlength(s) / S


def underline(d, x, y, w, colour, thick=1.5):
    d.rounded_rectangle((px(x), px(y), px(x + w), px(y + thick)),
                        radius=px(0.7), fill=colour)


def igt(d, x=11, y=8, lines=3, source="ka-mi na", gloss="1-ERG go",
        free="‘I go’", gap=14, src_px=12, gloss_px=10, free_px=11):
    """The motif: source line, gloss line, free translation."""
    text(d, x, y, source, font(F_BOLD, src_px), SOURCE)
    text(d, x, y + gap, gloss, font(F_REG, gloss_px), GLOSS)
    if lines >= 3:
        text(d, x, y + 2 * gap, free, font(F_ITAL, free_px), FREE)


def badge(d, colour, cx=49, cy=49, r=13):
    d.ellipse((px(cx - r), px(cy - r), px(cx + r), px(cy + r)), fill=colour)
    d.ellipse((px(cx - r), px(cy - r), px(cx + r), px(cy + r)),
              outline=WHITE, width=px(1.5))


def badge_text(d, s, path, size, cx=49, cy=49, dy=0):
    f = font(path, size)
    l, t, r, b = f.getbbox(s)
    w, h = (r - l) / S, (b - t) / S
    text(d, cx - w / 2 - l / S, cy - h / 2 - t / S + dy, s, f, WHITE)


def arrow(d, pts, colour):
    d.polygon([(px(x), px(y)) for x, y in pts], fill=colour)


def right_arrow(d, x, y, length=12, head=5, shaft=3, colour=WHITE):
    """Horizontal arrow whose tip is at (x+length, y); negative length points left."""
    sgn = 1 if length > 0 else -1
    L = abs(length)
    tip = x + sgn * L
    base = tip - sgn * head
    arrow(d, [(x, y - shaft / 2), (base, y - shaft / 2), (base, y - head),
              (tip, y), (base, y + head), (base, y + shaft / 2), (x, y + shaft / 2)],
          colour)


def down_arrow(d, x, y, length=10, head=5, shaft=3, colour=WHITE):
    tip = y + length
    base = tip - head
    arrow(d, [(x - shaft / 2, y), (x - shaft / 2, base), (x - head, base),
              (x, tip), (x + head, base), (x + shaft / 2, base), (x + shaft / 2, y)],
          colour)


def keycap(d, x0, y0, x1, y1, label):
    d.rounded_rectangle((px(x0), px(y0), px(x1), px(y1)), radius=px(3),
                        fill=WHITE, outline=SLATE, width=px(2))
    f = font(F_BOLD, (y1 - y0) * 0.6)
    l, t, r, b = f.getbbox(label)
    w, h = (r - l) / S, (b - t) / S
    text(d, (x0 + x1) / 2 - w / 2 - l / S, (y0 + y1) / 2 - h / 2 - t / S, label, f, SLATE)


def cycle(d, colour, cx=49, cy=49, r=13):
    """Badge with a re-wrap arrow (Apple Symbols U+21BB)."""
    badge(d, colour, cx, cy, r)
    badge_text(d, "↻", F_SYM, r * 1.7, cx, cy, dy=-0.5)


def disc(d, colour, cx=32, cy=32, r=26):
    """The main icon: a coloured disc with a white rim, readable on a light or dark ribbon."""
    badge(d, colour, cx, cy, r)


def mark(d, colour, cx=51, cy=51, r=11):
    """A corner mark on a disc, for the variants of one action."""
    badge(d, colour, cx, cy, r)


def chip(d, x0=4, y0=13, x1=60, y1=51):
    """A white tablet for text icons, so the text reads on either ribbon theme."""
    d.rounded_rectangle((px(x0), px(y0), px(x1), px(y1)), radius=px(5),
                        fill=PAGE, outline=PAGE_EDGE, width=px(2))


def grid(d, x0, y0, x1, y1, cols, rows):
    """A plain table: the one place a grid belongs."""
    d.rounded_rectangle((px(x0), px(y0), px(x1), px(y1)), radius=px(2),
                        fill=PAGE, outline=SLATE, width=px(2))
    for c in range(1, cols):
        x = x0 + (x1 - x0) * c / cols
        d.line([(px(x), px(y0)), (px(x), px(y1))], fill=SLATE, width=px(1.5))
    for r in range(1, rows):
        y = y0 + (y1 - y0) * r / rows
        d.line([(px(x0), px(y)), (px(x1), px(y))], fill=SLATE, width=px(1.5))


def glyph(d, s, path, size, cx, cy, colour=WHITE, dy=0):
    f = font(path, size)
    l, t, r, b = f.getbbox(s)
    w, h = (r - l) / S, (b - t) / S
    d.text((px(cx - w / 2 - l / S), px(cy - h / 2 - t / S + dy)), s, font=f, fill=colour)


# -- the icons ---------------------------------------------------------------

def ic_insert():
    im = canvas(); d = ImageDraw.Draw(im)
    page(d); igt(d)
    badge(d, BLUE)
    d.rounded_rectangle((px(42.5), px(47.5), px(55.5), px(50.5)), radius=px(1), fill=WHITE)
    d.rounded_rectangle((px(47.5), px(42.5), px(50.5), px(55.5)), radius=px(1), fill=WHITE)
    return im


def ic_convert():
    """A table becoming interlinear lines."""
    im = canvas(); d = ImageDraw.Draw(im)
    grid(d, 5, 3, 59, 25, 4, 2)
    down_arrow(d, 32, 27, 12, head=7, shaft=4, colour=BLUE)
    chip(d, 5, 40, 59, 62)
    text(d, 10, 41, "ka-mi na", font(F_BOLD, 9.5), SOURCE)
    text(d, 10, 51, "1-ERG go", font(F_REG, 8.5), GLOSS)
    return im


def ic_rewrap_this():
    im = canvas(); d = ImageDraw.Draw(im)
    disc(d, BLUE)
    glyph(d, "\u21bb", F_SYM, 46, 32, 32, dy=-1)
    return im


def ic_rewrap_all():
    im = canvas(); d = ImageDraw.Draw(im)
    disc(d, BLUE)
    glyph(d, "\u21bb", F_SYM, 46, 32, 32, dy=-1)
    mark(d, SLATE)
    for y in (46.5, 50.5, 54.5):                      # all of them: a list
        d.rounded_rectangle((px(45), px(y), px(57), px(y + 2)), radius=px(1), fill=WHITE)
    return im


def ic_split():
    im = canvas(); d = ImageDraw.Draw(im)
    disc(d, BLUE)
    d.rounded_rectangle((px(30.5), px(16), px(33.5), px(48)), radius=px(1), fill=WHITE)
    right_arrow(d, 27, 32, -16, head=8, shaft=5)
    right_arrow(d, 37, 32, 16, head=8, shaft=5)
    return im


def ic_merge():
    im = canvas(); d = ImageDraw.Draw(im)
    disc(d, BLUE)
    right_arrow(d, 11, 32, 18, head=8, shaft=5)
    right_arrow(d, 53, 32, -18, head=8, shaft=5)
    return im


def ic_by_word():
    """One word, one block."""
    im = canvas(); d = ImageDraw.Draw(im)
    disc(d, PURPLE)
    d.rounded_rectangle((px(13), px(27), px(51), px(37)), radius=px(3), fill=WHITE)
    return im


def ic_by_morpheme():
    """The same word in two pieces."""
    im = canvas(); d = ImageDraw.Draw(im)
    disc(d, PURPLE)
    d.rounded_rectangle((px(13), px(27), px(29), px(37)), radius=px(3), fill=WHITE)
    d.rounded_rectangle((px(35), px(27), px(51), px(37)), radius=px(3), fill=WHITE)
    return im


def ic_rewrap_on_save():
    im = canvas(); d = ImageDraw.Draw(im)
    disc(d, BLUE)
    glyph(d, "\u21bb", F_SYM, 46, 32, 32, dy=-1)
    mark(d, GREEN)
    down_arrow(d, 51, 43, 10, head=4.5, shaft=2.5)   # saved: into the tray
    d.rounded_rectangle((px(44.5), px(54), px(57.5), px(57)), radius=px(1), fill=WHITE)
    return im


def ic_rewrap_on_leave():
    im = canvas(); d = ImageDraw.Draw(im)
    disc(d, BLUE)
    glyph(d, "\u21bb", F_SYM, 46, 32, 32, dy=-1)
    mark(d, GREEN)
    d.rectangle((px(43.5), px(44), px(45.5), px(58)), fill=WHITE)   # the example's edge
    right_arrow(d, 47, 51, 11, head=4.5, shaft=2.5)                 # the cursor leaving it
    return im


def ic_numbers():
    im = canvas(); d = ImageDraw.Draw(im)
    disc(d, BLUE)
    glyph(d, "(1)", F_BOLD, 27, 32, 32, dy=-0.5)
    return im


def ic_initial_cap():
    """Erg: a full capital, then small capitals."""
    im = canvas(); d = ImageDraw.Draw(im)
    chip(d)
    f1, f2 = font(F_BOLD, 27), font(F_BOLD, 17)
    w = width(f1, "E") + width(f2, "RG")
    x = 32 - w / 2
    d.text((px(x), px(41)), "E", font=f1, fill=BLUE, anchor="ls")
    d.text((px(x + width(f1, "E")), px(41)), "RG", font=f2, fill=BLUE, anchor="ls")
    return im


def ic_settings():
    im = canvas(); d = ImageDraw.Draw(im)
    disc(d, SLATE)
    glyph(d, "\u2699", F_SYM, 44, 32, 32, dy=-1)
    return im


def ic_indent(outdent=False):
    """Lines of text pushed right (or back left) by an arrow."""
    im = canvas(); d = ImageDraw.Draw(im)
    disc(d, BLUE)
    for y in (20, 31, 42):
        d.rounded_rectangle((px(29), px(y), px(50), px(y + 3)), radius=px(1.5), fill=WHITE)
    if outdent:
        right_arrow(d, 26, 32.5, -12, head=5.5, shaft=3.5)
    else:
        right_arrow(d, 14, 32.5, 12, head=5.5, shaft=3.5)
    return im


def ic_outdent():
    return ic_indent(True)


def ic_reset_styles():
    im = canvas(); d = ImageDraw.Draw(im)
    disc(d, ORANGE)
    glyph(d, "\u00b6", F_BOLD, 36, 32, 32, dy=-1)
    return im


def ic_install_keys():
    im = canvas(); d = ImageDraw.Draw(im)
    keycap(d, 8, 8, 52, 52, "I")
    mark(d, GREEN, 50, 50, 12)
    d.rounded_rectangle((px(43.5), px(48.5), px(56.5), px(51.5)), radius=px(1), fill=WHITE)
    d.rounded_rectangle((px(48.5), px(43.5), px(51.5), px(56.5)), radius=px(1), fill=WHITE)
    return im


def ic_show_keys():
    """A keyboard."""
    im = canvas(); d = ImageDraw.Draw(im)
    d.rounded_rectangle((px(3), px(14), px(61), px(50)), radius=px(4),
                        fill=PAGE, outline=SLATE, width=px(2))
    for row, (y, n, off) in enumerate(((19, 8, 7), (26, 7, 10.5), (33, 6, 14))):
        for k in range(n):
            x = off + k * 7
            d.rounded_rectangle((px(x), px(y), px(x + 5), px(y + 5)), radius=px(1), fill=SLATE)
    d.rounded_rectangle((px(17.5), px(40), px(46.5), px(45)), radius=px(1), fill=SLATE)
    return im


def ic_check():
    """The glossing, checked."""
    im = canvas(); d = ImageDraw.Draw(im)
    chip(d, 4, 4, 60, 40)
    f1, f2 = font(F_BOLD, 24), font(F_BOLD, 15)
    w = width(f1, "E") + width(f2, "RG")
    x = 32 - w / 2 - 2
    d.text((px(x), px(30)), "E", font=f1, fill=BLUE, anchor="ls")
    d.text((px(x + width(f1, "E")), px(30)), "RG", font=f2, fill=BLUE, anchor="ls")
    badge(d, GREEN, 47, 47, 15)
    d.line([(px(39), px(47.5)), (px(44.5), px(53)), (px(55.5), px(41))],
           fill=WHITE, width=px(3.6), joint="curve")
    return im


ICONS = [
    # name, drawer, final size
    ("igtInsert", ic_insert, 64),
    ("igtConvert", ic_convert, 64),
    ("igtRewrapThis", ic_rewrap_this, 32),
    ("igtRewrapAll", ic_rewrap_all, 64),
    ("igtIndent", ic_indent, 32),
    ("igtOutdent", ic_outdent, 32),
    ("igtSplit", ic_split, 32),
    ("igtMerge", ic_merge, 32),
    ("igtByWord", ic_by_word, 32),
    ("igtByMorpheme", ic_by_morpheme, 32),
    ("igtRewrapOnSave", ic_rewrap_on_save, 32),
    ("igtRewrapOnLeave", ic_rewrap_on_leave, 32),
    ("igtNumbers", ic_numbers, 32),
    ("igtInitialCap", ic_initial_cap, 32),
    ("igtSettings", ic_settings, 32),
    ("igtResetStyles", ic_reset_styles, 32),
    ("igtInstallKeys", ic_install_keys, 32),
    ("igtShowKeys", ic_show_keys, 32),
    ("igtCheck", ic_check, 64),
]


def fit(im, margin=1.0):
    """Crop to what was drawn, squared and centred, so the symbol fills its
    frame; margin in final-size pixels."""
    l, t, r, b = im.getbbox()
    side = max(r - l, b - t) + 2 * px(margin)
    cx, cy = (l + r) / 2, (t + b) / 2
    box = (int(cx - side / 2), int(cy - side / 2), int(cx + side / 2), int(cy + side / 2))
    return im.crop(box)


def main():
    os.makedirs(OUT, exist_ok=True)
    finals = []
    for name, draw, size in ICONS:
        im = draw()
        if name in ("igtByWord", "igtByMorpheme"):   # Seth: these two a little larger
            im = fit(im)
        im = im.resize((size, size), Image.LANCZOS)
        im.save(os.path.join(OUT, name + ".png"), optimize=True)
        finals.append((name, im))
    print("wrote %d icons to %s" % (len(finals), os.path.relpath(OUT)))
    if len(sys.argv) > 1:
        # contact sheet: each icon at the size the ribbon shows it (64 and 32),
        # then at the logical size on a 1x display (32 and 16), on light and dark
        cell = 80
        sheet = Image.new("RGBA", (cell * len(finals), cell * 4), (0, 0, 0, 0))
        dd = ImageDraw.Draw(sheet)
        dd.rectangle((0, 0, sheet.width, cell * 2), fill=(243, 243, 243, 255))
        dd.rectangle((0, cell * 2, sheet.width, cell * 4), fill=(50, 50, 50, 255))
        for i, (name, im) in enumerate(finals):
            half = im.resize((im.width // 2, im.height // 2), Image.LANCZOS)
            for row, pic in ((0, im), (1, half), (2, im), (3, half)):
                x = i * cell + (cell - pic.width) // 2
                y = row * cell + (cell - pic.height) // 2
                sheet.alpha_composite(pic, (x, y))
        sheet.save(sys.argv[1])
        print("contact sheet:", sys.argv[1])


if __name__ == "__main__":
    main()
