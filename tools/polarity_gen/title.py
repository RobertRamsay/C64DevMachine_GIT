"""POLARITY title screen: 160x200 multicolour bitmap (Koala layout).

Day (Sunny) on the left, night (Hex) on the right. Everything is shaded with
ordered (Bayer) dithering between neighbouring palette steps, or checkered
into black ($D021), which is free in every cell. to_koala() then picks the
best three colours per 4x8 cell."""
import math, random
from itertools import combinations
import font, logo

PAL = [0x000000,0xFFFFFF,0x68372B,0x70A4B2,0x6F3D86,0x588D43,0x352879,0xB8C76F,
       0x6F4F25,0x433900,0x9A6759,0x444444,0x6C6C6C,0x9AD284,0x6C5EB5,0x959595]
BG = 0
W, H = 160, 200
BLACK, WHITE, RED, CYAN, PURPLE, GREEN, BLUE, YELLOW = range(8)
ORANGE, BROWN, PINK, DGREY, GREY, LGREEN, LBLUE, LGREY = range(8, 16)

BAYER4 = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def rgb(c):
    v = PAL[c]
    return ((v >> 16) & 255, (v >> 8) & 255, v & 255)


def bayer(x, y):
    return (BAYER4[y & 3][x & 3] + 0.5) / 16.0


def mix(x, y, t, a, b):
    """Ordered dither from colour a (t=0) to colour b (t=1)."""
    return b if t > bayer(x, y) else a


def band(t, w=0.3):
    """Squeeze a 0..1 shade so only a narrow zone around 0.5 is dithered."""
    return min(1.0, max(0.0, (t - 0.5) / w + 0.5))


def checker(x, y):
    return (x + y) & 1


def ramp(x, y, v, stops):
    """Dithered gradient: stops = [(v, colour), ...] ascending in v."""
    if v <= stops[0][0]:
        return stops[0][1]
    for (v0, c0), (v1, c1) in zip(stops, stops[1:]):
        if v <= v1:
            return mix(x, y, (v - v0) / float(v1 - v0), c0, c1)
    return stops[-1][1]


class Pic:
    def __init__(self):
        self.p = [[BG] * W for _ in range(H)]

    def get(self, x, y):
        return self.p[y][x] if 0 <= x < W and 0 <= y < H else BG

    def px(self, x, y, c):
        if 0 <= x < W and 0 <= y < H and c is not None:
            self.p[y][x] = c

    def rect(self, x0, y0, x1, y1, c):
        for y in range(max(0, y0), min(H - 1, y1) + 1):
            for x in range(max(0, x0), min(W - 1, x1) + 1):
                self.p[y][x] = c

    def text(self, x, y, s, c, shadow=None):
        """Font glyphs, one fat pixel per font pixel. c may be f(x, y, row)."""
        for i, ch in enumerate(s):
            rows = font.glyph_bytes(font.screen_code(ch))
            for ry in range(8):
                for rx in range(8):
                    if rows[ry] >> (7 - rx) & 1:
                        X, Y = x + i * 8 + rx, y + ry
                        if shadow is not None:
                            self.px(X + 1, Y + 1, shadow)
                        self.px(X, Y, c(X, Y, ry) if callable(c) else c)


class Sprite:
    """A free-standing figure: drawn into a dict, then outlined in black."""
    def __init__(self):
        self.d = {}

    def px(self, x, y, c):
        self.d[(x, y)] = c

    def ellipse(self, cx, cy, rx, ry, colour, keep=None):
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
                u, v = (x - cx) / rx, (y - cy) / ry
                if u * u + v * v <= 1.0 and (keep is None or keep(x, y)):
                    self.d[(x, y)] = colour(x, y, u, v) if callable(colour) else colour

    def blit(self, pic, outline=BLACK):
        for (x, y), c in self.d.items():
            pic.px(x, y, c)
        if outline is None:
            return
        for (x, y) in self.d:
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if (nx, ny) not in self.d:
                    pic.px(nx, ny, outline)


# ------------------------------------------------------------------ scenery
SEAM = 80
DAY_SKY = [(44, BLACK), (52, BLUE), (62, LBLUE), (108, LBLUE), (124, CYAN)]
NIGHT_SKY = [(52, BLACK), (82, BLUE), (110, BLUE), (128, PURPLE)]


def sky(pic):
    for y in range(40, 160):
        for x in range(W):
            day = ramp(x, y, y, DAY_SKY)
            night = ramp(x, y, y, NIGHT_SKY)
            # soft seam: dither day into night across 2 cells
            t = (x - (SEAM - 6)) / 12.0
            pic.px(x, y, mix(x, y >> 1, t, day, night) if 0 < t < 1 else (day if t <= 0 else night))


def sun(pic, cx, cy):
    for y in range(cy - 22, cy + 23):
        for x in range(cx - 12, cx + 13):
            r = math.hypot((x - cx) * 2, y - cy)
            if r <= 8.5:
                c = WHITE if math.hypot((x - cx + 1.2) * 2, y - cy + 2.5) <= 4.5 else YELLOW
                pic.px(x, y, c)
            elif r <= 19:
                # glow: yellow fading out with an ordered dither
                if 1.0 - (r - 8.5) / 10.5 > bayer(x, y) * 1.6:
                    pic.px(x, y, YELLOW)
    for a in range(0, 360, 30):           # dotted rays
        for r in (21, 24):
            pic.px(cx + int(round(r * math.cos(math.radians(a)) / 2)),
                   cy + int(round(r * math.sin(math.radians(a)))), YELLOW)


def moon(pic, cx, cy):
    for y in range(cy - 20, cy + 21):
        for x in range(cx - 11, cx + 12):
            r = math.hypot((x - cx) * 2, y - cy)
            bite = math.hypot((x - cx - 3) * 2, y - cy + 3)
            if r <= 9 and bite > 7.5:
                # lit crescent, shaded towards the terminator
                pic.px(x, y, mix(x, y, (8.8 - bite) / 2.5 + 0.2, LGREY, WHITE))
            elif r <= 18 and bite > 7.5 and pic.get(x, y) == BLACK:
                if 1.0 - (r - 9) / 9.0 > bayer(x, y) * 1.4:
                    pic.px(x, y, BLUE)           # halo against the black sky


def twinkle(pic, x, y, c, arm=LGREY, size=2):
    pic.px(x, y, c)
    for i in range(1, size + 1):
        a = c if i == 1 else arm
        pic.px(x - i, y, a); pic.px(x + i, y, a)
        pic.px(x, y - i * 2 + 1, a); pic.px(x, y + i * 2 - 1, a)
        pic.px(x, y - i * 2, a); pic.px(x, y + i * 2, a)


def stars(pic):
    rnd = random.Random(7)
    for _ in range(60):
        x, y = rnd.randint(SEAM + 4, 157), rnd.randint(42, 112)
        if math.hypot((x - 118) * 2, y - 70) < 24 or pic.get(x, y) not in (BLACK, BLUE):
            continue
        pic.px(x, y, rnd.choice((WHITE, LGREY, LGREY, CYAN)))
    for x, y in ((92, 52), (146, 92), (138, 54), (100, 98)):
        twinkle(pic, x, y, WHITE)


def cloud(pic, cx, cy, s=1.0):
    puffs = [(-7, 1, 6, 5), (0, -2, 7, 7), (7, 0, 6, 6), (13, 2, 5, 4), (-12, 3, 4, 3)]
    for y in range(cy - 12, cy + 8):
        for x in range(cx - 20, cx + 22):
            for dx, dy, rx, ry in puffs:
                u, v = (x - cx - dx * s) / (rx * s), (y - cy - dy * s) / (ry * s)
                if u * u + v * v <= 1:
                    flat = y >= cy + 3 * s
                    shade = (y - (cy - 4 * s)) / (8.0 * s)
                    pic.px(x, y, BLACK if flat and y > cy + 3 * s else mix(x, y, shade, WHITE, LGREY))
                    break


def hills(pic):
    for x in range(W):
        day = x < SEAM
        top = 128 + int(5 * math.sin(x / 9.0 + (0 if day else 2.0)) + 3 * math.sin(x / 4.3))
        for y in range(top, 150):
            d = y - top
            if day:
                c = LGREEN if d == 0 else mix(x, y, (d - 1) / 9.0, LGREEN, GREEN)
            else:
                c = GREY if d == 0 else mix(x, y, (d - 1) / 9.0, DGREY, BLUE)
            pic.px(x, y, c)


def ground(pic):
    for y in range(146, H):
        for x in range(W):
            day = x < SEAM
            # grass tufts: a ragged top edge
            edge = 146 + (2 if (x * 7 + 3) % 5 < 2 else 0) + (1 if x % 3 == 0 else 0)
            if y < edge:
                continue
            d = y - 146
            if day:
                c = ramp(x, y, d, [(2, LGREEN), (6, GREEN), (16, GREEN), (30, BLACK)])
            else:
                c = ramp(x, y, d, [(2, GREEN), (6, DGREY), (12, DGREY), (26, BLACK)])
            pic.px(x, y, c)
    rnd = random.Random(3)                     # flowers in the day grass
    for _ in range(14):
        x, y = rnd.randint(2, SEAM - 6), rnd.randint(150, 160)
        pic.px(x, y, rnd.choice((WHITE, YELLOW, PINK)))


# ------------------------------------------------------------------ the sisters
def girl(cx, fy, hair, hair_shade, sheen, dress, dress_lit, shoes, style, face=1, dots=None):
    """A chibi sister. face=+1 looks right, -1 left."""
    s = Sprite()
    hy = fy - 60                      # head centre
    f = face

    def shade_ball(lit, dark, lx=-0.5, ly=-0.6):
        def c(x, y, u, v):
            # lit from the upper side she faces; only the far rim is shaded
            k = -(u * lx * f + v * ly) * 0.7 + 0.15 * (1 - u * u - v * v) + 0.45
            return mix(x, y, band(1 - k, 0.18), lit, dark)
        return c

    # back hair
    if style == "tails":
        for side in (-1, 1):
            s.ellipse(cx + side * 11.5, hy + 12, 3.5, 14, shade_ball(hair, hair_shade))
            s.ellipse(cx + side * 10, hy - 2, 2.5, 4, dress_lit)          # ribbon
        s.ellipse(cx, hy - 1, 9.5, 16, shade_ball(hair, hair_shade))
    else:
        s.ellipse(cx, hy - 1, 10.5, 17, shade_ball(hair, hair_shade))
        for y in range(hy, fy - 26):
            wave = int(round(math.sin(y / 3.0) * 1.0))
            w = 10 + (y - hy) // 10
            for x in range(cx - w + wave, cx + w + 1 + wave):
                t = abs(x - cx) / float(w) + (y - hy) / 70.0
                s.px(x, y, mix(x, y, band(t, 0.25), hair, hair_shade))

    # legs, socks, shoes
    for lx in (cx - 3, cx + 2):
        for y in range(fy - 16, fy - 3):
            for x in (lx, lx + 1):
                s.px(x, y, WHITE if y >= fy - 7 else PINK)
        for x in range(lx - (1 if f < 0 else 0), lx + 2 + (1 if f > 0 else 0)):
            s.px(x, fy - 3, shoes); s.px(x, fy - 2, shoes)
    # dress: A-line, lit from the front
    top, hem = fy - 44, fy - 15
    for y in range(top, hem + 1):
        k = (y - top) / float(hem - top)
        hw = 5 + k * 7.5
        for x in range(int(cx - hw), int(math.ceil(cx + hw)) + 1):
            u = (x - cx) / hw
            lit = 0.6 - u * 0.7 * f - k * 0.3
            c = mix(x, y, band(lit, 0.25), dress, dress_lit)
            if dots and (y - top) % 6 == 3 and (x - cx + ((y - top) // 6) * 2) % 4 == 0 and abs(u) < 0.85:
                c = dots
            if y == hem or (y == hem - 1 and (x + y) % 3 == 0):
                c = WHITE                                             # lace hem
            s.px(x, y, c)
    for x in range(cx - 1, cx + 2):                                   # collar
        s.px(x, top, WHITE)
    s.px(cx - 2, top, WHITE); s.px(cx + 2, top, WHITE); s.px(cx, top + 1, WHITE)
    # puff sleeves + arms
    for side in (-1, 1):
        s.ellipse(cx + side * 6, top + 3, 2.6, 4, shade_ball(dress_lit, dress))
        for y in range(top + 6, top + 19):
            ax = cx + side * (8 + (y - top - 6) // 3)
            s.px(ax, y, PINK)
            s.px(ax - side, y, BLACK)
        hx = cx + side * (8 + 12 // 3)
        s.px(hx, top + 19, PINK); s.px(hx + side, top + 18, PINK); s.px(hx, top + 20, PINK)
    # head
    s.ellipse(cx, hy, 8.5, 14.5, PINK)
    for y in range(int(hy + 9), int(hy + 15)):                       # neck + chin shade
        for x in range(cx - 1, cx + 2):
            s.px(x, y, PINK)
    # fringe: scalloped bangs
    for x in range(cx - 9, cx + 10):
        edge = hy - 6 + int(round(2.2 * abs(math.sin((x - cx) * 0.75 + (0.6 if style == "tails" else 0)))))
        for y in range(hy - 16, edge + 1):
            if (x, y) in s.d and s.d[(x, y)] == PINK or (abs(x - cx) <= 8 and y > hy - 15):
                t = (y - (hy - 15)) / 20.0 - 0.45 * (x - cx) * f / 9.0 + 0.1
                s.px(x, y, mix(x, y, band(t, 0.15), hair, hair_shade))
    for x in range(cx - 5, cx + 4, 3):                                # sheen arc
        s.px(x + (1 if f > 0 else 0), hy - 11 + abs(x - cx) // 3, sheen)
        s.px(x + 1 + (1 if f > 0 else 0), hy - 11 + abs(x - cx) // 3, sheen)
    # face: big eyes with a highlight, lashes, blush, tiny smile
    for side in (-1, 1):
        ex = cx + side * 4 + (1 if f > 0 else 0) - 1
        for y in range(hy - 1, hy + 5):
            s.px(ex, y, BLACK); s.px(ex + 1, y, BLACK)
        s.px(ex, hy, WHITE)
        s.px(ex + 1, hy + 3, WHITE if side == f else BLACK)
        s.px(ex + (2 if side > 0 else -1), hy - 1, BLACK)             # lash flick
        for x in (ex - (1 if side < 0 else 0), ex + 1 + (1 if side > 0 else 0)):
            if checker(x, hy + 7):
                s.px(x, hy + 7, RED)                                  # blush
    mx = cx + (1 if f > 0 else 0)
    s.px(mx - 1, hy + 8, BLACK); s.px(mx, hy + 9, BLACK); s.px(mx + 1, hy + 8, BLACK)
    return s


def sisters(pic):
    sunny = girl(26, 160, YELLOW, ORANGE, WHITE, RED, PINK, RED, "tails", face=1, dots=WHITE)
    sunny.blit(pic)
    hexg = girl(134, 160, BLUE, BLACK, LBLUE, PURPLE, LBLUE, BLUE, "long", face=-1, dots=None)
    # a star hair clip
    for (x, y) in ((126, 85), (125, 86), (126, 86), (127, 86), (126, 87)):
        hexg.px(x, y, YELLOW)
    hexg.blit(pic)


# ------------------------------------------------------------------ magnet
def magnet(pic):
    cx, cy = 80, 120
    m = Sprite()
    for y in range(cy - 22, 150):
        for x in range(cx - 14, cx + 15):
            dx, dy = (x - cx) * 2, y - cy
            r = math.hypot(dx, dy)
            leg = dy > 0 and (abs(dx) >= 12 and abs(dx) <= 27)
            if (dy <= 0 and 12 <= r <= 27.5) or leg:
                left = x < cx
                base, hi = (RED, PINK) if left else (BLUE, LBLUE)
                # tube shading across the band: highlight stripe near the outside
                band = (r - 12) / 15.5 if dy <= 0 else (abs(dx) - 12) / 15.5
                t = 1 - abs(band - 0.35) * 2.2
                c = mix(x, y, t, base, hi)
                if y >= 140:
                    c = mix(x, y, (y - 140) / 3.0 + 0.2, WHITE, LGREY) if y < 147 else GREY
                m.px(x, y, c)
    m.blit(pic)
    # pole marks, cut into the tips
    for x, y in ((73, 143), (73, 144), (73, 145), (72, 144), (74, 144)):
        pic.px(x, y, BLACK)
    for x in (86, 87, 88):
        pic.px(x, 144, BLACK)
    # field: dotted arcs reaching out to each sister
    for side, c in ((-1, YELLOW), (1, CYAN)):
        for a in range(0, 70, 4):
            for rr in (34, 42):
                ang = math.radians(a)
                x = cx + side * int(round((rr * math.cos(ang)) / 2))
                y = 148 - int(round(rr * math.sin(ang) * 0.7))
                if pic.get(x, y) not in (BLACK,) or True:
                    if (a // 4 + rr) % 2 == 0:
                        pic.px(x, y, c)
    twinkle(pic, 80, 104, WHITE, size=1)
    twinkle(pic, 66, 100, YELLOW, size=1)
    twinkle(pic, 95, 99, CYAN, size=1)


# ------------------------------------------------------------------ logo + text
LOGO_X, LOGO_Y = 6, 2
# sunset: day at the top of the letters, night at the bottom. Stops sit on
# cell rows so each row of cells only ever mixes two of them (+ the outline).
LOGO_RAMP = [(8, WHITE), (16, YELLOW), (24, YELLOW), (32, PINK), (40, PURPLE)]


def draw_logo(pic):
    rows = logo.LOGO
    on = lambda x, y: 0 <= y < len(rows) and 0 <= x < len(rows[0]) and rows[y][x] == '#'
    # drop shadow + outline in dark blue, then the dithered candy fill
    for y in range(-2, len(rows) + 3):
        for x in range(-2, len(rows[0]) + 3):
            if on(x, y):
                continue
            near = any(on(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1))
            drop = on(x - 1, y - 2) or on(x - 1, y - 1)
            if near or drop:
                X = LOGO_X + x
                pic.px(X, LOGO_Y + y, BLUE)
    for y, line in enumerate(rows):
        for x, ch in enumerate(line):
            if ch == '#':
                X, Y = LOGO_X + x, LOGO_Y + y
                pic.px(X, Y, ramp(X, Y, Y, LOGO_RAMP))
    twinkle(pic, 116, 4, WHITE)
    twinkle(pic, 20, 36, WHITE, size=1)


def text_ramp(top, bottom):
    return lambda x, y, row: mix(x, y, (row - 1) / 5.0, top, bottom)


def build_picture():
    pic = Pic()
    sky(pic)
    sun(pic, 52, 74)
    cloud(pic, 18, 70, 0.8)
    cloud(pic, 60, 100, 0.7)
    moon(pic, 112, 70)
    stars(pic)
    hills(pic)
    ground(pic)
    magnet(pic)
    sisters(pic)
    draw_logo(pic)
    pic.text(6, 170, "SUNNY", text_ramp(WHITE, YELLOW))
    pic.text(130, 170, "HEX", text_ramp(LBLUE, PURPLE))
    pic.text(40, 186, "PRESS FIRE", text_ramp(WHITE, LGREY))
    return pic


# ------------------------------------------------------------------ Koala
def to_koala(pic):
    """Per 4x8 cell: the three colours (plus BG) that reproduce it best."""
    bitmap = bytearray(8000)
    screen = bytearray(1000)
    colour = bytearray(1000)
    dist = lambda a, b: sum((x - y) ** 2 for x, y in zip(rgb(a), rgb(b)))
    for cy in range(25):
        for cx in range(40):
            counts = {}
            for y in range(8):
                for x in range(4):
                    c = pic.p[cy * 8 + y][cx * 4 + x]
                    if c != BG:
                        counts[c] = counts.get(c, 0) + 1
            used = sorted(counts, key=lambda c: -counts[c])
            if len(used) <= 3:
                chosen = used
            else:
                def cost(trio):
                    return sum(n * min(dist(c, k) for k in (BG,) + trio) for c, n in counts.items())
                chosen = list(min(combinations(used, 3), key=cost))
            while len(chosen) < 3:
                chosen.append(0)
            for y in range(8):
                b = 0
                for x in range(4):
                    c = pic.p[cy * 8 + y][cx * 4 + x]
                    if c == BG:
                        v = 0
                    elif c in chosen:
                        v = chosen.index(c) + 1
                    else:
                        best = min([BG] + chosen, key=lambda k: dist(k, c))
                        v = 0 if best == BG else chosen.index(best) + 1
                    b = (b << 2) | v
                bitmap[(cy * 40 + cx) * 8 + y] = b
            screen[cy * 40 + cx] = ((chosen[0] & 15) << 4) | (chosen[1] & 15)
            colour[cy * 40 + cx] = chosen[2] & 15
    return bytes([0x00, 0x60]) + bytes(bitmap) + bytes(screen) + bytes(colour) + bytes([BG])


def clashes(pic):
    """Cells that need more than BG + 3 colours (lossy after conversion)."""
    out = []
    for cy in range(25):
        for cx in range(40):
            cols = {pic.p[cy * 8 + y][cx * 4 + x] for y in range(8) for x in range(4)} - {BG}
            if len(cols) > 3:
                out.append((cx, cy, sorted(cols)))
    return out


def render_koala(blob, path):
    from PIL import Image
    bm, sc, co, bg = blob[2:8002], blob[8002:9002], blob[9002:10002], blob[10002]
    im = Image.new('RGB', (320, 200))
    for cy in range(25):
        for cx in range(40):
            cols = [bg, sc[cy * 40 + cx] >> 4, sc[cy * 40 + cx] & 15, co[cy * 40 + cx] & 15]
            for y in range(8):
                b = bm[(cy * 40 + cx) * 8 + y]
                for x in range(4):
                    c = rgb(cols[(b >> (6 - 2 * x)) & 3])
                    im.putpixel((cx * 8 + 2 * x, cy * 8 + y), c)
                    im.putpixel((cx * 8 + 2 * x + 1, cy * 8 + y), c)
    im.resize((640, 400), Image.NEAREST).save(path)


if __name__ == "__main__":
    import sys
    pic = build_picture()
    k = to_koala(pic)
    render_koala(k, sys.argv[1] if len(sys.argv) > 1 else "../title_preview.png")
    bad = clashes(pic)
    print(len(k), "bytes,", len(bad), "clashing cells")
    for c in bad:
        print("  ", c)
