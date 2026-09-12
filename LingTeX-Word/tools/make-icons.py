#!/usr/bin/env python3
"""make-icons.py -- LingTeX-Word

Draws the ribbon icons into src/icons/*.png.

The buttons act on interlinear examples, which are tables to Word but not to the
user, so the icons show what the user sees: a little page carrying a three-line
interlinear example (source, glosses, free translation), with a badge in the
corner for what the button does to it. Nothing here is a grid.

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


# -- the icons ---------------------------------------------------------------

def ic_insert():
    im = canvas(); d = ImageDraw.Draw(im)
    page(d); igt(d)
    badge(d, BLUE)
    d.rounded_rectangle((px(42.5), px(47.5), px(55.5), px(50.5)), radius=px(1), fill=WHITE)
    d.rounded_rectangle((px(47.5), px(42.5), px(50.5), px(55.5)), radius=px(1), fill=WHITE)
    return im


def ic_convert():
    im = canvas(); d = ImageDraw.Draw(im)
    page(d); igt(d)
    badge(d, BLUE)
    right_arrow(d, 41, 45.5, 16)
    right_arrow(d, 57, 53, -16)
    return im


def ic_rewrap_this():
    im = canvas(); d = ImageDraw.Draw(im)
    page(d); igt(d)
    cycle(d, BLUE)
    return im


def ic_rewrap_all():
    im = canvas(); d = ImageDraw.Draw(im)
    page(d, 12, 2, 60, 52)
    page(d, 4, 10, 52, 60)
    igt(d, x=9, y=14, lines=3, gap=13, src_px=11, gloss_px=9, free_px=10)
    cycle(d, BLUE, 51, 51, 12)
    return im


def ic_split():
    im = canvas(); d = ImageDraw.Draw(im)
    page(d); igt(d)
    badge(d, BLUE)
    d.rectangle((px(48.25), px(40.5), px(49.75), px(57.5)), fill=WHITE)
    right_arrow(d, 46.5, 49, -9, head=4.5, shaft=2.5)
    right_arrow(d, 51.5, 49, 9, head=4.5, shaft=2.5)
    return im


def ic_merge():
    im = canvas(); d = ImageDraw.Draw(im)
    page(d); igt(d)
    badge(d, BLUE)
    right_arrow(d, 38.5, 49, 9.5, head=4.5, shaft=2.5)
    right_arrow(d, 59.5, 49, -9.5, head=4.5, shaft=2.5)
    return im


def ic_by_word():
    im = canvas(); d = ImageDraw.Draw(im)
    page(d)
    fb = font(F_BOLD, 16)
    text(d, 11, 11, "kami", fb, SOURCE)
    underline(d, 11, 31, width(fb, "kami"), BLUE, 2.5)
    text(d, 11, 37, "1SG", font(F_REG, 13), GLOSS)
    return im


def ic_by_morpheme():
    im = canvas(); d = ImageDraw.Draw(im)
    page(d)
    fb = font(F_BOLD, 16)
    text(d, 11, 11, "ka-mi", fb, SOURCE)
    underline(d, 11, 31, width(fb, "ka"), BLUE, 2.5)
    underline(d, 11 + width(fb, "ka-"), 31, width(fb, "mi"), BLUE, 2.5)
    text(d, 11, 37, "1-SG", font(F_REG, 13), GLOSS)
    return im


def ic_rewrap_on_save():
    im = canvas(); d = ImageDraw.Draw(im)
    page(d); igt(d, source="ka-mi", gloss="1-ERG", free="\u2018I\u2019")
    d.text((px(41), px(2)), "\u21bb", font=font(F_SYM, 19), fill=BLUE)
    badge(d, GREEN)
    down_arrow(d, 49, 40, 11, head=5, shaft=3)                   # saved: into the tray
    d.rounded_rectangle((px(41), px(52), px(57), px(56)), radius=px(1), fill=WHITE)
    return im


def ic_rewrap_on_leave():
    im = canvas(); d = ImageDraw.Draw(im)
    page(d); igt(d, source="ka-mi", gloss="1-ERG", free="\u2018I\u2019")
    d.text((px(41), px(2)), "\u21bb", font=font(F_SYM, 19), fill=BLUE)
    badge(d, GREEN)
    d.rectangle((px(40), px(41), px(42), px(57)), fill=WHITE)   # the example's edge
    right_arrow(d, 44, 49, 14, head=5, shaft=3)                  # the cursor leaving it
    return im


def ic_numbers():
    im = canvas(); d = ImageDraw.Draw(im)
    page(d)
    text(d, 8, 6, "(1)", font(F_BOLD, 14), BLUE)
    igt(d, x=31, y=8, lines=3, source="ka-mi", gloss="1-ERG", free="‘I’")
    return im


def ic_initial_cap():
    im = canvas(); d = ImageDraw.Draw(im)
    page(d)
    text(d, 11, 7, "ka-mi", font(F_BOLD, 13), SOURCE)
    base = 37
    f1, f2, f3 = font(F_REG, 12), font(F_REG, 18), font(F_REG, 12)
    x = 11
    d.text((px(x), px(base)), "1-", font=f1, fill=GLOSS, anchor="ls")
    x += width(f1, "1-")
    d.text((px(x), px(base)), "E", font=f2, fill=BLUE, anchor="ls")
    x += width(f2, "E")
    d.text((px(x), px(base)), "RG", font=f3, fill=BLUE, anchor="ls")
    text(d, 11, 42, "\u2018I\u2019", font(F_ITAL, 12), FREE)
    return im


def ic_settings():
    im = canvas(); d = ImageDraw.Draw(im)
    page(d); igt(d)
    badge(d, SLATE)
    badge_text(d, "⚙", F_SYM, 22, 49, 49, dy=-0.5)
    return im


def ic_start():
    im = canvas(); d = ImageDraw.Draw(im)
    page(d); igt(d)
    badge(d, GREEN)
    arrow(d, [(44, 41), (44, 57), (57, 49)], WHITE)
    return im


def ic_reset_styles():
    im = canvas(); d = ImageDraw.Draw(im)
    page(d); igt(d)
    badge(d, ORANGE)
    badge_text(d, "¶", F_BOLD, 18, 49, 49, dy=-0.5)
    return im


def ic_install_keys():
    im = canvas(); d = ImageDraw.Draw(im)
    page(d, 6, 4, 58, 60)
    igt(d, lines=2, y=8, gap=14, src_px=12, gloss_px=10)
    keycap(d, 10, 36, 30, 56, "I")
    badge(d, BLUE, 47, 47, 12)
    d.rounded_rectangle((px(41), px(45.5), px(53), px(48.5)), radius=px(1), fill=WHITE)
    d.rounded_rectangle((px(45.5), px(41), px(48.5), px(53)), radius=px(1), fill=WHITE)
    return im


def ic_show_keys():
    im = canvas(); d = ImageDraw.Draw(im)
    page(d, 6, 4, 58, 60)
    igt(d, lines=2, y=8, gap=14, src_px=12, gloss_px=10)
    keycap(d, 10, 36, 30, 56, "I")
    keycap(d, 34, 36, 54, 56, "R")
    return im


def ic_check():
    im = canvas(); d = ImageDraw.Draw(im)
    page(d); igt(d)
    badge(d, GREEN)
    d.line([(px(42), px(49.5)), (px(47), px(54.5)), (px(56.5), px(43.5))],
           fill=WHITE, width=px(3.2), joint="curve")
    return im


ICONS = [
    # name, drawer, final size
    ("igtInsert", ic_insert, 64),
    ("igtConvert", ic_convert, 64),
    ("igtRewrapThis", ic_rewrap_this, 32),
    ("igtRewrapAll", ic_rewrap_all, 32),
    ("igtSplit", ic_split, 32),
    ("igtMerge", ic_merge, 32),
    ("igtByWord", ic_by_word, 32),
    ("igtByMorpheme", ic_by_morpheme, 32),
    ("igtRewrapOnSave", ic_rewrap_on_save, 32),
    ("igtRewrapOnLeave", ic_rewrap_on_leave, 32),
    ("igtNumbers", ic_numbers, 32),
    ("igtInitialCap", ic_initial_cap, 32),
    ("igtSettings", ic_settings, 32),
    ("igtStart", ic_start, 32),
    ("igtResetStyles", ic_reset_styles, 32),
    ("igtInstallKeys", ic_install_keys, 32),
    ("igtShowKeys", ic_show_keys, 32),
    ("igtCheck", ic_check, 64),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    finals = []
    for name, draw, size in ICONS:
        im = draw().resize((size, size), Image.LANCZOS)
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
