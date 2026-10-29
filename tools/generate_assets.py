"""Original, deterministic pixel art. Run with Python + Pillow; no remote assets.

tiles: 24 x 16px frames; decor: 10 x (32x48); villagers: 4 x 6 (16x24).
All sprites anchor at bottom-center. Rendering must use nearest-neighbor sampling.
"""
from pathlib import Path
import random
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parents[1] / "assets" / "art"
OUT.mkdir(parents=True, exist_ok=True)
PAL = {
    "ink": "#263b38", "deep": "#183c3a", "wood": "#795d40",
    "bark": "#886b49", "bark_l": "#ac8d5a", "cream": "#e7d8ad",
    "ivory": "#f3e6bb", "jade": "#719b82", "sage": "#a9b68a",
    "gold": "#d7b968", "red": "#a75e4d", "red_l": "#d18860",
    "roof": "#354f56", "roof_l": "#698286", "roof_h": "#9eaf9e",
}


def canvas(w, h):
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def rect(d, box, c):
    d.rectangle(box, fill=PAL.get(c, c))


def poly(d, pts, c):
    d.polygon(pts, fill=PAL.get(c, c))


def line(d, pts, c, width=1):
    d.line(pts, fill=PAL.get(c, c), width=width)


def shadow(d, box):
    d.ellipse(box, fill=(23, 51, 43, 85))


def make_tiles():
    atlas, _ = canvas(24 * 16, 16)
    colors = [
        ("#326a69", "#397572", "#498783", "#2a605f"),
        ("#c5bc8b", "#d0c697", "#b8b484", "#ded2a2"),
        ("#829b67", "#8ca770", "#a4b77c", "#748e5c"),
        ("#647e55", "#6e895d", "#8ca174", "#58744d"),
        ("#879487", "#96a291", "#b2bca6", "#758478"),
        ("#ae9c73", "#baa87b", "#ccbc8b", "#a18e68"),
    ]
    for group, shades in enumerate(colors):
        for variant in range(4):
            rng = random.Random(1301 + group * 53 + variant)
            tile = Image.new("RGBA", (16, 16), shades[0])
            d = ImageDraw.Draw(tile)
            if group == 0:
                for y, x in [(3, variant * 3 % 12), (10, (variant * 5 + 4) % 12)]:
                    line(d, [(x, y), (x + 3, y)], shades[1])
                    line(d, [(x + 1, y + 1), (x + 5, y + 1)], shades[2])
                rect(d, (1, 13, 4, 13), shades[3])
            else:
                for _ in range(8 if group in (2, 3) else 5):
                    x, y = rng.randrange(16), rng.randrange(16)
                    rect(d, (x, y, min(15, x + rng.choice([0, 1, 2])), y), rng.choice(shades[1:]))
                if group in (2, 3):
                    for _ in range(2):
                        x, y = rng.randrange(1, 14), rng.randrange(2, 14)
                        line(d, [(x - 1, y), (x, y + 1), (x + 1, y - 1)], shades[1])
                if group == 4:
                    line(d, [(3 + variant, 9), (5 + variant, 8), (7 + variant, 8)], shades[3])
            atlas.paste(tile, ((group * 4 + variant) * 16, 0))
    atlas.save(OUT / "tiles.png")
    return atlas


def pine(d):
    shadow(d, (5, 40, 28, 46))
    rect(d, (14, 22, 17, 42), "bark")
    rect(d, (14, 30, 14, 42), "bark_l")
    for cy, width in [(4, 7), (10, 10), (17, 13), (24, 15)]:
        poly(d, [(16, cy), (16-width, cy+13), (16-width+4, cy+14),
                 (16, cy+12), (16+width, cy+13), (16+width-3, cy+9)], "#345e4b")
        poly(d, [(16, cy+1), (16-width+2, cy+11), (15, cy+9),
                 (19, cy+10)], "#648463")
        line(d, [(16, cy+2), (16-width+4, cy+10)], "#8ba076")
        rect(d, (18, cy+9, 21, cy+10), "#477158")


def broadleaf(d):
    shadow(d, (4, 40, 29, 46))
    poly(d, [(12, 43), (14, 27), (8, 21), (11, 20), (16, 26),
             (20, 22), (22, 23), (18, 31), (18, 42)], "bark")
    line(d, [(14, 40), (15, 29), (11, 24)], "bark_l")
    clusters = [(4, 10, 19, 27), (13, 10, 29, 29), (5, 5, 23, 23), (1, 17, 16, 31), (14, 20, 28, 32)]
    for box in clusters:
        d.ellipse(box, fill="#4b7153")
    for box in [(4, 11, 17, 24), (9, 6, 22, 22), (16, 13, 27, 25), (3, 18, 13, 27)]:
        d.ellipse(box, fill="#75905f")
    for x, y in [(7, 13), (13, 8), (18, 12), (6, 21), (20, 23)]:
        rect(d, (x, y, x+3, y+1), "#a2b47b")
    rect(d, (12, 18, 15, 19), "#849c66")


def bamboo(d):
    shadow(d, (4, 40, 28, 45))
    for x, top in [(9, 9), (17, 3), (24, 13)]:
        rect(d, (x, top, x+1, 42), "#688e62")
        rect(d, (x, top+1, x, 40), "#b0bd7a")
        for y in range(top+5, 40, 7):
            rect(d, (x-1, y, x+2, y), "#3f6c50")
            for dx, dy in [(-7, -5), (7, -4), (-5, 3)]:
                line(d, [(x, y-1), (x+dx, y+dy)], "#486f4e")
                poly(d, [(x+dx, y+dy), (x+dx//2, y+dy-2), (x+dx//2+1, y+dy+2)], "#8ba26b")


def rocks(d):
    shadow(d, (1, 37, 31, 46))
    poly(d, [(3, 39), (5, 25), (12, 18), (20, 20), (26, 36), (22, 43), (9, 44)], "#586e66")
    poly(d, [(5, 26), (12, 18), (20, 20), (17, 34), (6, 38)], "#b3bda3")
    poly(d, [(17, 34), (20, 20), (26, 36), (22, 40)], "#879d8b")
    poly(d, [(1, 40), (4, 34), (10, 33), (14, 42), (7, 45)], "#879889")
    line(d, [(7, 27), (11, 23), (14, 23)], "#d0d0ac")
    poly(d, [(20, 42), (24, 31), (29, 34), (31, 42), (27, 45)], "#7b9180")
    rect(d, (6, 39, 11, 40), "#668a5a")
    rect(d, (17, 41, 23, 42), "#759363")


def roof(d, y, wide=True, color="roof"):
    # Concave silhouette, raised eaves, stepped ridge and readable tile rows.
    left, right = (0, 31) if wide else (3, 28)
    poly(d, [(left, y+6), (left+3, y+8), (8, y+5), (12, y), (20, y),
             (24, y+5), (right-3, y+8), (right, y+6), (right-1, y+11),
             (left+1, y+11)], "ink")
    poly(d, [(left+2, y+8), (9, y+6), (13, y+1), (19, y+1),
             (23, y+6), (right-2, y+8), (right-2, y+9), (left+2, y+9)], color)
    line(d, [(10, y+5), (22, y+5)], "roof_l")
    line(d, [(6, y+8), (26, y+8)], "roof_l")
    rect(d, (12, y, 20, y+1), "roof_h")
    for x in [10, 14, 18, 22]:
        rect(d, (x, y+6, x, y+7), "roof_h")
    line(d, [(1, y+10), (30, y+10)], "#799288")


def house(d):
    shadow(d, (0, 39, 31, 47))
    rect(d, (5, 22, 27, 41), "ink")
    rect(d, (6, 23, 26, 39), "cream")
    rect(d, (6, 25, 26, 27), "#b8b18b")
    rect(d, (6, 28, 26, 29), "#d8cca3")
    rect(d, (5, 24, 6, 41), "wood")
    rect(d, (25, 24, 26, 41), "wood")
    rect(d, (13, 30, 20, 41), "wood")
    rect(d, (15, 31, 19, 40), "#344e46")
    rect(d, (8, 30, 11, 35), "roof")
    rect(d, (9, 31, 10, 33), "#b0c0a0")
    rect(d, (21, 30, 24, 35), "roof")
    rect(d, (22, 31, 23, 33), "#b0c0a0")
    rect(d, (3, 41, 29, 43), "#839181")
    rect(d, (12, 44, 23, 45), "#b1b59b")
    roof(d, 12)
    rect(d, (26, 27, 28, 31), "red_l")
    rect(d, (27, 32, 27, 34), "gold")


def temple(d):
    shadow(d, (0, 39, 31, 47))
    rect(d, (4, 20, 27, 40), "#79554a")
    rect(d, (7, 21, 24, 39), "#e0ce9c")
    rect(d, (10, 30, 21, 40), "#3b4e46")
    rect(d, (11, 31, 15, 39), "#765b42")
    rect(d, (17, 31, 20, 39), "#765b42")
    for x in [5, 24]:
        rect(d, (x, 23, x+2, 41), "red")
        rect(d, (x, 24, x, 39), "red_l")
        rect(d, (x-1, 40, x+3, 41), "gold")
    roof(d, 17)
    rect(d, (9, 10, 23, 18), "red")
    rect(d, (12, 12, 20, 17), "cream")
    roof(d, 2, False)
    rect(d, (12, 27, 20, 30), "#365c50")
    rect(d, (14, 28, 18, 28), "gold")
    rect(d, (2, 42, 29, 43), "#7c8e80")
    rect(d, (0, 44, 31, 45), "#a6ae94")
    rect(d, (7, 46, 25, 47), "#c0bfa0")


def lantern(d):
    shadow(d, (7, 39, 25, 45))
    rect(d, (13, 14, 15, 43), "wood")
    rect(d, (14, 15, 14, 41), "bark_l")
    rect(d, (12, 12, 24, 14), "wood")
    rect(d, (23, 13, 23, 18), "ink")
    rect(d, (20, 19, 26, 27), "red")
    rect(d, (19, 20, 27, 26), "red")
    rect(d, (21, 20, 25, 26), "#d49a65")
    rect(d, (23, 20, 24, 26), "#f0d08a")
    rect(d, (20, 18, 26, 19), "gold")
    rect(d, (20, 27, 26, 28), "gold")
    rect(d, (23, 29, 23, 32), "red")
    rect(d, (11, 42, 18, 43), "ink")


def herbs(d):
    shadow(d, (4, 39, 27, 45))
    for x, y in [(10, 40), (18, 39), (23, 42)]:
        line(d, [(x, y), (x, y-9)], "#608563")
        for sign in [-1, 1]:
            poly(d, [(x, y-3), (x+sign*5, y-8), (x+sign*5, y-5)], "#8ca772")
            poly(d, [(x, y-6), (x+sign*3, y-11), (x+sign*4, y-8)], "#a3b784")
        rect(d, (x-1, y-12, x+1, y-10), "#b6b6cf")
        rect(d, (x, y-13, x, y-11), "#e0d4de")


def willow(d):
    shadow(d, (4, 40, 29, 46))
    poly(d, [(14, 44), (12, 28), (15, 17), (18, 15), (16, 30), (18, 43)], "wood")
    line(d, [(15, 42), (14, 29), (17, 19)], "bark_l")
    poly(d, [(2, 18), (4, 10), (11, 6), (23, 7), (29, 12), (31, 22),
             (25, 28), (20, 23), (10, 24), (5, 29)], "#537f5b")
    for x, top, bottom in [(3, 15, 34), (6, 10, 32), (10, 9, 29), (22, 9, 31), (26, 12, 36), (29, 17, 33)]:
        line(d, [(x, top), (x-1, bottom-3), (x+1, bottom)], "#8fa66e")
        for y in range(top+2, bottom, 4):
            rect(d, (x-2, y, x, y+2), "#9eb77c")
    poly(d, [(7, 12), (13, 7), (21, 9), (24, 14), (14, 13)], "#91a775")
    rect(d, (12, 8, 18, 9), "#b1bf8c")


def sign(d):
    shadow(d, (5, 40, 27, 45))
    rect(d, (14, 26, 16, 43), "wood")
    rect(d, (15, 27, 15, 41), "bark_l")
    poly(d, [(6, 20), (23, 20), (28, 25), (23, 29), (6, 29)], "ink")
    poly(d, [(7, 21), (22, 21), (26, 25), (22, 27), (7, 27)], "bark_l")
    line(d, [(10, 24), (20, 24)], "wood")
    rect(d, (9, 22, 10, 22), "cream")
    rect(d, (8, 28, 20, 28), "wood")


def make_decor():
    atlas, _ = canvas(320, 48)
    for i, fn in enumerate([pine, broadleaf, bamboo, rocks, house, temple, lantern, herbs, willow, sign]):
        im, d = canvas(32, 48)
        fn(d)
        atlas.paste(im, (i*32, 0))
    atlas.save(OUT / "decor.png")
    return atlas


def make_villagers():
    atlas, _ = canvas(64, 144)
    robes = [("#c8ba94", "#e7d8ad", "#9d947c"), ("#56877d", "#8db4a0", "#3e6863"),
             ("#b37559", "#d59d70", "#84594a"), ("#646d92", "#979db7", "#4c526d"),
             ("#91a277", "#b7c397", "#6a805f"), ("#b79a51", "#dcc781", "#8c7c4c")]
    for row, (base, light, dark) in enumerate(robes):
        for col in range(4):
            im, d = canvas(16, 24)
            sit = col == 3
            dy = 3 if sit else (1 if col == 2 else 0)
            shadow(d, (2, 20, 14, 23))
            # Bun and cap-like black hair; a tiny contrasting tie remains visible.
            rect(d, (6, 1+dy, 9, 4+dy), "ink")
            rect(d, (7, 1+dy, 8, 1+dy), "#647469")
            rect(d, (5, 4+dy, 10, 9+dy), "#293e39")
            rect(d, (6, 6+dy, 10, 10+dy), "#dcb78a")
            rect(d, (7, 6+dy, 10, 8+dy), "#efd0a0")
            rect(d, (6, 5+dy, 9, 6+dy), "ink")
            rect(d, (9, 8+dy, 9, 8+dy), "ink")
            if sit:
                poly(d, [(5, 13), (10, 13), (14, 20), (12, 22), (3, 22), (1, 20)], dark)
                poly(d, [(5, 13), (10, 13), (12, 20), (3, 20)], base)
                rect(d, (4, 19, 12, 20), light)
                rect(d, (6, 15, 9, 16), "ivory")
                rect(d, (5, 18, 7, 18), "#dcb78a")
                rect(d, (9, 18, 11, 18), "#dcb78a")
            else:
                poly(d, [(5, 11+dy), (10, 11+dy), (12, 19), (11, 21), (4, 21), (3, 19)], dark)
                poly(d, [(5, 11+dy), (10, 11+dy), (11, 19), (5, 20)], base)
                rect(d, (5, 13+dy, 5, 18), light)
                poly(d, [(5, 11+dy), (7, 14+dy), (9, 11+dy)], "ivory")
                rect(d, (5, 16+dy, 10, 16+dy), "wood")
                arm_y = 12+dy
                rect(d, (3 if col != 1 else 2, arm_y, 4, 17), base)
                rect(d, (11, arm_y, 12 if col != 2 else 13, 17), light)
                rect(d, (3, 18, 4, 18), "#dcb78a")
                rect(d, (11, 18, 12, 18), "#dcb78a")
                rect(d, (5, 21, 6, 22 if col != 1 else 21), "ink")
                rect(d, (9, 21, 10, 22 if col != 2 else 21), "ink")
            atlas.paste(im, (col*16, row*24))
    atlas.save(OUT / "villagers.png")
    return atlas


def make_portrait():
    im = Image.new("RGB", (48, 48), "#24433e")
    d = ImageDraw.Draw(im)
    # Flat stepped landscape shapes frame a carefully lit, hand-built face.
    poly(d, [(0, 28), (6, 20), (11, 25), (15, 14), (25, 29), (31, 18), (40, 27), (48, 20), (48, 48), (0, 48)], "#365b4e")
    rect(d, (37, 7, 40, 10), "#bdbe91")
    rect(d, (36, 8, 41, 9), "#bdbe91")
    poly(d, [(7, 47), (9, 37), (18, 33), (31, 33), (40, 39), (44, 47)], "#263b38")
    poly(d, [(9, 47), (11, 38), (20, 34), (30, 34), (38, 39), (41, 47)], "#72937b")
    poly(d, [(11, 39), (17, 36), (16, 47), (9, 47)], "#8fa48a")
    poly(d, [(30, 35), (35, 37), (39, 47), (29, 47)], "#557b69")
    poly(d, [(18, 31), (29, 31), (30, 35), (23, 42), (16, 35)], "#c0b38a")
    poly(d, [(18, 33), (23, 37), (29, 33), (31, 35), (23, 43), (15, 36)], "ivory")
    poly(d, [(23, 43), (30, 35), (32, 38), (28, 47), (21, 47)], "#a9b995")
    # Hair silhouette and topknot.
    poly(d, [(14, 29), (12, 20), (14, 13), (19, 10), (29, 10), (34, 15), (34, 28), (30, 33), (17, 33)], "#233832")
    poly(d, [(19, 11), (17, 6), (19, 3), (25, 3), (28, 6), (26, 11)], "#263931")
    rect(d, (20, 4, 24, 4), "#516150")
    rect(d, (17, 9, 28, 10), "gold")
    poly(d, [(16, 18), (20, 14), (28, 15), (31, 19), (30, 28), (26, 33), (21, 33), (17, 28)], "#d6b185")
    poly(d, [(20, 17), (28, 17), (30, 20), (28, 28), (24, 31), (20, 28)], "#edcea0")
    poly(d, [(16, 18), (19, 13), (28, 13), (32, 18), (26, 17), (23, 15), (19, 19)], "#253b33")
    rect(d, (17, 21, 20, 21), "#56604a")
    rect(d, (26, 21, 29, 21), "#56604a")
    rect(d, (19, 22, 20, 23), "ink")
    rect(d, (27, 22, 28, 23), "ink")
    rect(d, (24, 23, 24, 26), "#c19a73")
    rect(d, (22, 29, 26, 29), "#a87660")
    rect(d, (22, 30, 25, 30), "#d1a782")
    rect(d, (15, 22, 16, 25), "#c69c75")
    rect(d, (31, 22, 32, 25), "#c69c75")
    line(d, [(13, 18), (14, 26), (16, 30)], "#445346")
    line(d, [(34, 19), (33, 31), (30, 35)], "#172e2a")
    rect(d, (32, 41, 33, 45), "gold")
    rect(d, (31, 42, 34, 43), "gold")
    im = im.resize((96, 96), Image.Resampling.NEAREST)
    im.save(OUT / "portrait.png")
    return im


def contact_sheet(tiles, decor, villagers, portrait):
    sheet = Image.new("RGB", (800, 520), "#e6dec1")
    d = ImageDraw.Draw(sheet)
    d.text((20, 15), "CLOUDS & MORTALS / original pixel asset study", fill="#294b43")
    d.text((20, 42), "TERRAIN: water / sand / grass / forest / mountain / path", fill="#596d57")
    sheet.paste(tiles.resize((768, 32), Image.Resampling.NEAREST), (16, 62))
    d.text((20, 112), "WORLD OBJECTS / 32 x 48px frames / bottom-center anchor", fill="#596d57")
    deco_large = decor.resize((640, 96), Image.Resampling.NEAREST)
    sheet.paste(deco_large, (20, 137), deco_large)
    names = ["PINE", "TREE", "BAMBOO", "ROCKS", "HOUSE", "SHRINE", "LANTERN", "HERBS", "WILLOW", "SIGN"]
    for i, name in enumerate(names):
        d.text((20+i*64, 244), name, fill="#596d57")
    d.text((20, 280), "VILLAGERS / idle, step A, step B, meditation", fill="#596d57")
    people = villagers.resize((128, 288), Image.Resampling.NEAREST)
    # Lay out six robe-color rows side by side for a compact review sheet.
    for row in range(6):
        frame = people.crop((0, row*48, 128, row*48+48))
        sheet.paste(frame, (20+(row%3)*150, 311+(row//3)*75), frame)
    d.text((520, 280), "TRAVELER PORTRAIT / 48px at 2x", fill="#596d57")
    sheet.paste(portrait.resize((144, 144), Image.Resampling.NEAREST), (550, 310))
    d.text((20, 482), "Palette: jade foliage / ink-teal water / parchment / slate roofs / warm redwood", fill="#596d57")
    sheet.save(OUT / "contact_sheet.png")


if __name__ == "__main__":
    contact_sheet(make_tiles(), make_decor(), make_villagers(), make_portrait())
    for path in sorted(OUT.glob("*.png")):
        with Image.open(path) as im:
            print(f"{path.name}: {im.width}x{im.height} {im.mode}")
