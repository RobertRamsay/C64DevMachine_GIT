"""POLARITY rooms: each place is drawn on a 160x160 multicolour canvas
(40x20 cells of 4x8 fat pixels), then sliced into deduplicated MC chars.

Pixel values: 0 = sky ($D021, changes with the clock), 1 = the group's
shared colour ($D022, see GROUP_D022), 2 = black ($D023), 3 = the cell's own
colour (0-7, colour RAM | 8). A cell can instead hold a hires font char.

The sisters are 42 lines tall and stand with their feet at canvas y 138,
in front of furniture whose feet sit on the back edge of the floor (y 134).

A charset holds at most 194 room tiles, shared by the rooms of its group,
so every texture repeats on a 4 or 8 pixel period, gradients change on cell
rows, and big objects sit on cell boundaries: the dithering then costs a
handful of tiles instead of one per cell."""
import math
import font

W, H = 160, 160          # fat pixels
CW, CH = 40, 20          # cells
BLACK, WHITE, RED, CYAN, PURPLE, GREEN, BLUE, YELLOW = range(8)
FEET = 138               # canvas y of the sisters' soles
BACK = 134               # canvas y furniture stands on

ROOM_NAMES = ["GRANS", "GARDEN", "BEDROOM", "HOME", "STREET", "CAFE", "SHOP", "SWINGS", "PARK", "WOODS", "LIBRARY"]
ROOM_GROUP = [1, 4, 0, 0, 2, 3, 3, 2, 4, 4, 1]
GROUP_NAMES = ["HOUSE", "COTTAGE", "TOWN", "SHOPS", "GREEN"]
GROUP_D022 = [8, 9, 12, 15, 13]        # $D022 per charset: wood, dark wood, grey, light grey, leaf
# Font chars (signs) in a room all use one colour: the map stores chars only.
GROUP_TEXT_COL = [WHITE, YELLOW, WHITE, YELLOW, WHITE]

B4 = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def bayer(x, y):
    return (B4[y & 3][x & 3] + 0.5) / 16.0


def mix(x, y, t, a, b):
    return b if t > bayer(x, y) else a


class Canvas:
    def __init__(self):
        self.p = [[0] * W for _ in range(H)]
        self.col = [[BLACK] * CW for _ in range(CH)]
        self.text = {}                       # (cx,cy) -> (screen code, colour)

    def px(self, x, y, v):
        if 0 <= x < W and 0 <= y < H and v is not None:
            self.p[y][x] = v

    def get(self, x, y):
        return self.p[y][x] if 0 <= x < W and 0 <= y < H else 0

    def rect(self, x0, y0, x1, y1, v):
        for y in range(max(0, y0), min(H - 1, y1) + 1):
            for x in range(max(0, x0), min(W - 1, x1) + 1):
                self.p[y][x] = v

    def frame(self, x0, y0, x1, y1, v):
        self.rect(x0, y0, x1, y0, v); self.rect(x0, y1, x1, y1, v)
        self.rect(x0, y0, x0, y1, v); self.rect(x1, y0, x1, y1, v)

    def box(self, x0, y0, x1, y1, fill, edge=2):
        self.rect(x0, y0, x1, y1, fill)
        self.frame(x0, y0, x1, y1, edge)

    def cells(self, cx0, cy0, cx1, cy1, colour):
        for cy in range(cy0, cy1 + 1):
            for cx in range(cx0, cx1 + 1):
                if 0 <= cx < CW and 0 <= cy < CH:
                    self.col[cy][cx] = colour

    def put_text(self, cx, cy, s, colour):
        for i, ch in enumerate(s):
            self.text[(cx + i, cy)] = (font.screen_code(ch), colour)

    def pattern(self, x0, y0, x1, y1, fn):
        for y in range(max(0, y0), min(H - 1, y1) + 1):
            for x in range(max(0, x0), min(W - 1, x1) + 1):
                v = fn(x, y)
                if v is not None:
                    self.p[y][x] = v

    def art(self, x0, y0, rows, key=None):
        key = key or {'o': 0, 'a': 1, 'b': 2, 'c': 3}
        for dy, r in enumerate(rows):
            for dx, ch in enumerate(r):
                if ch in key:
                    self.px(x0 + dx, y0 + dy, key[ch])


def checker(x, y):
    return (x + y) & 1


def shade_under(cv, x0, x1):
    """A soft cast shadow on the floor's back edge."""
    cv.pattern(x0, BACK + 1, x1, BACK + 3, lambda x, y: 2 if checker(x, y) else None)


# ------------------------------------------------------------------ indoors
def interior(cv, wall_col, paper, floor="wood", floor_col=YELLOW):
    """Cornice, wallpaper (shaded under the ceiling), skirting and floor."""
    paper(cv)
    cv.cells(0, 0, CW - 1, 15, wall_col)
    cv.rect(0, 0, W - 1, 4, 1)
    cv.pattern(0, 0, W - 1, 4, lambda x, y: 2 if (x % 8 == 7 and y < 4) or y == 4 else None)
    cv.pattern(0, 5, W - 1, 7, lambda x, y: 2 if checker(x, y) else None)          # shadow band
    cv.pattern(0, 8, W - 1, 11, lambda x, y: 2 if (x % 2 == 0 and y % 2 == 0) else None)
    cv.rect(0, 120, W - 1, 120, 2)                                             # skirting
    cv.rect(0, 121, W - 1, 126, 1)
    cv.rect(0, 121, W - 1, 121, 3)
    cv.rect(0, 127, W - 1, 127, 2)
    (wood_floor if floor == "wood" else tile_floor)(cv, floor_col)


def paper_stripes(cv):
    cv.pattern(0, 12, W - 1, 119, lambda x, y: 1 if x % 8 == 3 else (1 if (x % 8 == 7 and y % 8 == 4) else 3))
    cv.pattern(0, 5, W - 1, 11, lambda x, y: 1 if x % 8 == 3 else 3)


def paper_flowers(cv):
    motif = ["..b.", ".bab", "..b.", "...."]
    def p(x, y):
        yy, xx = y % 16, x % 8
        if yy < 4 and xx < 4:
            ch = motif[yy][xx]
        elif 8 <= yy < 12 and xx >= 4:
            ch = motif[yy - 8][xx - 4]
        else:
            ch = '.'
        return {'b': 2, 'a': 1}.get(ch, 3)
    cv.pattern(0, 5, W - 1, 119, p)


def paper_panels(cv):
    """Plain upper wall with a speckle, panelled wainscot under a dado rail."""
    cv.pattern(0, 5, W - 1, 87, lambda x, y: 1 if (x % 8 == 0 and y % 8 == 0) else 3)
    cv.rect(0, 88, W - 1, 88, 2); cv.rect(0, 89, W - 1, 90, 1); cv.rect(0, 91, W - 1, 91, 2)
    cv.pattern(0, 92, W - 1, 119, lambda x, y: 2 if x % 16 == 15 or y in (95, 116) else (1 if x % 16 == 0 else 3))
    cv.pattern(0, 96, W - 1, 115, lambda x, y: 2 if x % 16 == 14 and checker(x, y) else None)


def wood_floor(cv, colour):
    """Boards in perspective: a black seam every cell row, staggered joints,
    the far boards dithered dark."""
    cv.rect(0, 128, W - 1, H - 1, 1)
    for i, y0 in enumerate(range(128, 160, 8)):
        cv.rect(0, y0 + 7, W - 1, y0 + 7, 2)
        joint = 0 if i % 2 == 0 else 4
        cv.pattern(0, y0, W - 1, y0 + 6, lambda x, y: 2 if x % 8 == joint else None)
        cv.pattern(0, y0 + 1, W - 1, y0 + 1, lambda x, y: 3 if x % 4 == 2 else None)
    cv.pattern(0, 128, W - 1, 134, lambda x, y: 2 if checker(x, y) else None)
    cv.pattern(0, 136, W - 1, 140, lambda x, y: 2 if x % 2 == 0 and y % 2 == 0 else None)
    cv.cells(0, 16, CW - 1, 19, colour)


def tile_floor(cv, colour):
    """Chequerboard, one cell per tile, shaded at the back."""
    for y in range(128, H):
        for x in range(W):
            cv.p[y][x] = 3 if ((x // 4) + (y - 128) // 8) % 2 == 0 else 1
    for y0 in range(135, 160, 8):
        cv.rect(0, y0, W - 1, y0, 2)
    cv.pattern(0, 128, W - 1, 134, lambda x, y: 2 if checker(x, y) else None)
    cv.cells(0, 16, CW - 1, 19, colour)


def window(cv, cx, cy, w=3, h=4, curtain=None):
    """Window w x h cells on cell boundaries: sky glass, black frame + bars."""
    x0, y0, x1, y1 = cx * 4, cy * 8, cx * 4 + w * 4 - 1, cy * 8 + h * 8 - 1
    cv.rect(x0, y0, x1, y1, 0)
    cv.frame(x0, y0, x1, y1, 2)
    cv.rect(x0 + (w // 2) * 4, y0, x0 + (w // 2) * 4, y1, 2)
    cv.rect(x0, y0 + (h // 2) * 8, x1, y0 + (h // 2) * 8, 2)
    cv.pattern(x0 + 1, y0 + 1, x1 - 1, y0 + 2, lambda x, y: 1 if checker(x, y) else None)    # glint
    cv.rect(x0, y1 + 1, x1, y1 + 2, 1); cv.rect(x0, y1 + 3, x1, y1 + 3, 2)                  # sill
    if curtain is not None:
        for sx in (x0 - 4, x1 + 1):
            cv.pattern(sx, y0 - 4, sx + 3, y1 + 7, lambda x, y: 2 if (x % 4 == 2 and checker(x, y)) else
                       (1 if x % 4 == 0 else 3))
        cv.rect(x0 - 4, y0 - 5, x1 + 4, y0 - 5, 2)
        cv.cells(cx - 1, cy - 1, cx - 1, cy + h, curtain)
        cv.cells(cx + w, cy - 1, cx + w, cy + h, curtain)


def door(cv, cx, colour=RED, w=3, top=64):
    """Panelled door, w cells wide, from y top to the floor."""
    x0, x1, y1 = cx * 4, cx * 4 + w * 4 - 1, 127
    cv.rect(x0, top, x1, y1, 3)
    cv.frame(x0, top, x1, y1 + 0, 2)
    cv.pattern(x0 + 1, top + 1, x0 + 1, y1, lambda x, y: 1)
    for py0, py1 in ((top + 8, top + 31), (top + 40, y1 - 8)):
        cv.frame(x0 + 2, py0, x1 - 2, py1, 2)
        cv.pattern(x1 - 3, py0 + 1, x1 - 3, py1 - 1, lambda x, y: 2 if checker(x, y) else None)
    cv.rect(x1 - 3, top + 35, x1 - 2, top + 36, 1)
    cv.cells(cx, top // 8, cx + w - 1, 15, colour)


def doorway(cv, cx, w=3):
    x0, x1 = cx * 4, cx * 4 + w * 4 - 1
    cv.rect(x0, 64, x1, 127, 2)
    cv.rect(x0, 64, x1, 64, 1)
    cv.pattern(x0, 65, x1, 127, lambda x, y: 1 if x in (x0, x1) and checker(x, y) else None)


def picture(cv, cx, cy, w, h, colour, scene):
    x0, y0, x1, y1 = cx * 4, cy * 8, cx * 4 + w * 4 - 1, cy * 8 + h * 8 - 1
    cv.box(x0, y0, x1, y1, 1)
    cv.rect(x0 + 2, y0 + 2, x1 - 2, y1 - 2, 3)
    cv.art(x0 + 2, y0 + 2, scene)
    cv.cells(cx, cy, cx + w - 1, cy + h - 1, colour)


def lamp(cv, cx, colour=YELLOW):
    x = cx * 4
    cv.art(x - 2, 88, ["...cccc...", "..cccccc..", ".ccacccc..", "ccaccccccc", "cccccccccc", ".bbbbbbbb."])
    cv.rect(x + 1, 94, x + 2, BACK - 1, 2)
    cv.rect(x - 1, BACK - 1, x + 4, BACK, 2)
    cv.cells(cx - 1, 11, cx + 1, 11, colour)


def plant(cv, cx):
    x = cx * 4
    cv.art(x, 96, ["..c..c..", ".cc.cc.c", "ccc.ccc.", ".cccccc.", "c.cbcc.c", ".cccccc.", "..cbcc..", "..cccc.."])
    cv.box(x + 1, 104, x + 6, BACK, 1)
    cv.rect(x + 2, 105, x + 5, 105, 2)
    cv.cells(cx, 12, cx + 1, 12, GREEN)


# ------------------------------------------------------------------ outdoors
def sky_clouds(cv, spots):
    """White clouds w cells wide: a scalloped top that repeats per cell,
    rounded ends, the underside dithered into the sky."""
    for cx, cy, w in spots:
        x0, y0 = cx * 4, cy * 8
        for x in range(x0, x0 + w * 4):
            i = x - x0
            bump = [1, 3, 3, 1][x % 4] + 2
            if i < 3:
                bump = [0, 1, 3][i]
            if i >= w * 4 - 3:
                bump = [3, 1, 0][i - (w * 4 - 3)]
            for y in range(y0 + 8 - bump, y0 + 14):
                if y >= y0 + 12:
                    v = 3 if checker(x, y) and y == y0 + 12 else None
                else:
                    v = 3
                cv.px(x, y, v)
        cv.cells(cx, cy, cx + w - 1, cy + 1, WHITE)


def far_hills(cv, y0, colour):
    """Rolling hills repeating every 32 px (8 cells), lit top, dithered base."""
    for x in range(W):
        top = y0 + int(round(5 * math.sin((x % 32) / 32.0 * 2 * math.pi)))
        for y in range(top, 128):
            d = y - top
            cv.p[y][x] = 1 if d == 0 else (mix(x, y, (d - 1) / 5.0, 1, 3) if d < 6 else 3)
    cv.cells(0, (y0 - 6) // 8, CW - 1, 15, colour)


def grass_ground(cv, colour=GREEN):
    """Lawn: tufts every 4 px, light back edge, dark front."""
    for x in range(W):
        tuft = [0, 2, 1, 0][x % 4]
        for y in range(126 - tuft, H):
            d = y - 128
            if d < 0:
                v = 1
            elif d < 8:
                v = mix(x, y, d / 8.0, 1, 3)
            elif d < 22:
                v = 1 if (x % 8 == 3 and y % 8 == 3) else 3
            else:
                v = mix(x, y, (d - 22) / 10.0, 3, 2)
            cv.p[y][x] = v
    cv.cells(0, 15, CW - 1, 19, colour)


def pavement(cv, colour=WHITE):
    cv.rect(0, 128, W - 1, H - 1, 1)
    for i, y0 in enumerate(range(128, 152, 8)):
        cv.rect(0, y0 + 7, W - 1, y0 + 7, 2)
        joint = 0 if i % 2 == 0 else 8
        cv.pattern(0, y0, W - 1, y0 + 6, lambda x, y: 2 if x % 16 == joint else None)
        cv.pattern(0, y0, W - 1, y0, lambda x, y: 3 if x % 2 == 0 else None)
    cv.pattern(0, 128, W - 1, 134, lambda x, y: 2 if checker(x, y) else None)
    cv.rect(0, 152, W - 1, 153, 3)                                   # kerb
    cv.pattern(0, 154, W - 1, H - 1, lambda x, y: mix(x, y, (y - 154) / 6.0, 1, 2))
    cv.cells(0, 16, CW - 1, 19, colour)


def tree(cv, cx, top, colour=GREEN, w=8, shade=True):
    """A round tree: canopy lit from the top left (dithered), cell-aligned trunk.
    shade=False: a plain checker shadow instead of the Bayer ramp (fewer tiles)."""
    x0 = cx * 4
    cx0, cy0, rx, ry = x0 + w * 2, top + 20, w * 2, 20
    for y in range(top, top + 40):
        for x in range(x0, x0 + w * 4):
            u, v = (x + 0.5 - cx0) / rx, (y + 0.5 - cy0) / ry
            if u * u + v * v <= 1:
                light = 0.55 - 0.5 * u - 0.5 * v
                c = 3
                if light > 0.75:
                    c = 1 if checker(x, y) else 3
                if light < 0.25:
                    c = mix(x, y, (0.25 - light) * 3, 3, 2) if shade else (2 if light < 0.1 and checker(x, y) else 3)
                if shade and (x % 8 == 5 and y % 8 == 2) and light > 0.2:
                    c = 1                                  # leaf glints
                cv.px(x, y, c)
    tx = cx0 - 4
    cv.rect(tx, top + 38, tx + 7, BACK, 3)
    cv.pattern(tx, top + 38, tx + 7, BACK, lambda x, y: 2 if x >= tx + 6 or (x == tx + 5 and checker(x, y)) else
               (1 if x == tx + 1 else None))
    cv.cells(cx, top // 8, cx + w - 1, (top + 37) // 8, colour)
    cv.cells(tx // 4, (top + 40) // 8, tx // 4 + 1, 16, RED)


def fence(cv, y0, colour=WHITE):
    """Picket fence: one picket per 8 px."""
    for x in range(W):
        if x % 8 in (1, 2, 3):
            for y in range(y0, BACK + 1):
                cv.px(x, y, 2 if x % 8 == 3 else 3)
            if x % 8 == 2:
                cv.px(x, y0 - 1, 3)
    for ry in (y0 + 6, y0 + 18):
        cv.rect(0, ry, W - 1, ry + 1, 3); cv.rect(0, ry + 2, W - 1, ry + 2, 2)
    cv.cells(0, (y0 - 1) // 8, CW - 1, BACK // 8, colour)


def flowers(cv, cx0, cx1, colours=(YELLOW, RED, PURPLE, WHITE)):
    for i, cx in enumerate(range(cx0, cx1 + 1)):
        cv.art(cx * 4, 120, [".c.", "cac", ".c.", ".b.", "bbb", ".b."])
        cv.cells(cx, 15, cx, 15, colours[i % len(colours)])


def bench(cv, cx, w=5):
    x0, x1 = cx * 4, cx * 4 + w * 4 - 1
    for y in (104, 109):
        cv.rect(x0, y, x1, y + 2, 3); cv.rect(x0, y + 3, x1, y + 3, 2)
    cv.rect(x0, 116, x1, 118, 3); cv.rect(x0, 116, x1, 116, 1); cv.rect(x0, 119, x1, 119, 2)
    for x in (x0 + 1, x1 - 2):
        cv.rect(x, 103, x + 1, BACK, 2)
    shade_under(cv, x0, x1)
    cv.cells(cx, 13, cx + w - 1, 14, RED)


def lamp_post(cv, cx, colour=YELLOW):
    x = cx * 4
    cv.art(x - 2, 48, ["..bbbb..", ".bccccb.", "bcaaaacb", "bcaaaacb", ".bccccb.", "..bbbb.."])
    cv.rect(x + 1, 54, x + 2, BACK, 2)
    cv.rect(x, BACK - 3, x + 3, BACK, 2)
    cv.cells(cx - 1, 6, cx + 1, 6, colour)


# ------------------------------------------------------------------ rooms
def room_grans():
    cv = Canvas()
    interior(cv, YELLOW, paper_flowers, floor_col=RED)
    # fireplace (cols 2-11): brick surround, a dithered fire in the grate
    cv.rect(8, 72, 47, 127, 3)
    cv.pattern(8, 72, 47, 127, lambda x, y: 2 if y % 8 == 7 or (x % 8 == (0 if (y // 8) % 2 else 4)) else None)
    cv.rect(4, 64, 51, 71, 1); cv.rect(4, 71, 51, 71, 2); cv.rect(4, 64, 51, 64, 2)
    cv.rect(20, 96, 35, 127, 2)
    fire = ["....c...c.......", "...cc..cc...c...", "..cac.cac..cc...", "..caccaacccac...",
            ".caaaaaaaaaaac..", ".caaaaaaaaaaaac.", "ccaaaaaaaaaaaacc", "bbbbbbbbbbbbbbbb"]
    cv.art(20, 112, fire)
    cv.cells(2, 9, 11, 15, RED)
    cv.cells(5, 14, 8, 15, YELLOW)
    # clock on the mantel, the family photos on the wall
    cv.art(24, 52, ["..bbbb..", ".bccccb.", "bcccbccb", "bccbcccb", "bcccccb.", ".bccccb.", "..bbbb..", "...bb..."])
    cv.cells(6, 6, 7, 7, WHITE)
    picture(cv, 15, 4, 3, 2, CYAN, ["..bb......", ".bbbb..bb.", "..bb..bbbb", ".bbbb..bb.", "bbbbbbbbbb"])
    picture(cv, 20, 3, 2, 3, PURPLE, ["..bb..", ".bbbb.", "..bb..", ".bbbb.", "bbbbbb", "bbbbbb"])
    window(cv, 30, 4, 3, 5, curtain=RED)
    # armchair (cols 25-28)
    cv.box(100, 96, 115, 120, 3)
    cv.pattern(101, 97, 114, 119, lambda x, y: 1 if x % 4 == 0 and y % 8 == 0 else None)
    cv.box(96, 108, 99, 127, 3); cv.box(116, 108, 119, 127, 3)
    cv.box(100, 112, 115, 127, 3)
    cv.rect(98, 128, 99, BACK, 2); cv.rect(116, 128, 117, BACK, 2)
    cv.cells(24, 12, 29, 15, PURPLE)
    shade_under(cv, 96, 119)
    # rag rug in front of the hearth (cols 2-13)
    cv.rect(8, 144, 55, 151, 3)
    cv.pattern(8, 144, 55, 151, lambda x, y: 1 if (x % 8 < 4) == (y < 148) else 3)
    cv.frame(8, 144, 55, 151, 2)
    lamp(cv, 37)
    return cv


def room_garden():
    cv = Canvas()
    sky_clouds(cv, [(3, 1, 4), (18, 2, 3), (31, 1, 4)])
    far_hills(cv, 88, GREEN)
    fence(cv, 104, WHITE)
    # garden shed (cols 3-14): the tin box sits up on its roof
    for i in range(12):
        cv.rect(12 + i * 2 - 4, 56 + i * 2, 60 - i * 2 + 4, 57 + i * 2, 3)
    for y in range(56, 80):
        for x in range(8, 64):
            if cv.get(x, y) == 3 and y % 4 == 3:
                cv.px(x, y, 2)
    cv.cells(2, 7, 15, 9, RED)
    cv.rect(12, 80, 59, BACK, 3)
    cv.pattern(12, 80, 59, BACK, lambda x, y: 2 if x % 8 == 7 else (1 if x % 8 == 0 else None))
    cv.rect(12, 80, 59, 80, 2)
    cv.rect(28, 88, 43, BACK, 2); cv.rect(29, 89, 42, BACK, 1)
    cv.rect(40, 108, 41, 109, 2)
    cv.rect(48, 88, 55, 103, 0); cv.frame(48, 88, 55, 103, 2)
    cv.cells(3, 10, 14, 16, RED)
    shade_under(cv, 12, 59)
    # washing line with a dress and a shirt (cols 18-29)
    cv.rect(72, 72, 73, BACK, 2); cv.rect(118, 72, 119, BACK, 2)
    cv.rect(74, 76, 117, 76, 2)
    cv.art(80, 77, ["..bb..", "cccccc", "cccccc", ".cccc.", ".cccc.", "cccccc", "cccccc"])
    cv.art(100, 77, ["cc..cc", "cccccc", "cccccc", "cccccc", "cccccc", "cccccc"])
    cv.cells(20, 9, 21, 10, PURPLE)
    cv.cells(25, 9, 26, 10, YELLOW)
    # flower bed + watering can (cols 31-38)
    cv.rect(124, 124, 155, 127, 2)
    flowers(cv, 31, 38)
    cv.art(148, 112, ["....bb.", "..bbccb", ".bccccb", "bbccccb", "..bbbb."])
    cv.cells(37, 14, 38, 14, CYAN)
    grass_ground(cv)
    return cv


def room_bedroom():
    cv = Canvas()
    interior(cv, CYAN, paper_stripes, floor_col=YELLOW)
    doorway(cv, 0)
    window(cv, 8, 3, 3, 4, curtain=PURPLE)
    # bed (cols 4-14): headboard left, quilt, pillow
    cv.box(16, 96, 19, BACK, 1)
    cv.rect(16, 96, 19, 99, 3)
    cv.box(20, 104, 31, 111, 1)
    cv.rect(21, 105, 30, 106, 3)
    cv.rect(20, 112, 59, 123, 3)
    cv.pattern(20, 112, 59, 123, lambda x, y: 1 if (x % 8 < 4) != (y % 8 < 4) else 3)
    cv.rect(20, 112, 59, 112, 2); cv.rect(59, 112, 59, 127, 2)
    cv.rect(20, 124, 59, 127, 1); cv.rect(20, 127, 59, 127, 2)
    cv.rect(24, 128, 25, BACK, 2); cv.rect(56, 128, 57, BACK, 2)
    cv.cells(4, 12, 14, 15, RED)
    cv.cells(4, 13, 14, 15, RED)
    shade_under(cv, 16, 59)
    # desk + home computer (cols 16-24)
    cv.rect(64, 100, 99, 103, 1); cv.rect(64, 104, 99, 104, 2)
    cv.rect(64, 105, 65, BACK, 2); cv.rect(96, 105, 99, BACK, 1); cv.frame(88, 105, 99, BACK, 2)
    cv.rect(91, 112, 96, 112, 2); cv.rect(91, 120, 96, 120, 2)
    cv.box(68, 72, 87, 95, 1)
    cv.rect(70, 74, 85, 92, 3)
    cv.pattern(70, 74, 85, 92, lambda x, y: 2 if y % 4 == 0 and x % 2 == 0 else None)
    cv.rect(76, 96, 79, 99, 2)
    cv.cells(17, 9, 21, 12, CYAN)
    # stool in front of the desk (her seat for the COMPUTER pose)
    cv.rect(72, 115, 83, 115, 2); cv.rect(72, 116, 83, 118, 1); cv.rect(72, 119, 83, 119, 2)
    cv.rect(73, 120, 73, BACK, 2); cv.rect(82, 120, 82, BACK, 2); cv.rect(74, 126, 81, 126, 2)
    shade_under(cv, 64, 99)
    picture(cv, 13, 2, 2, 2, BLUE, ["..aa..", "aaaaaa", ".aaaa.", "aa..aa"])
    # tall wardrobe (cols 28-35): the diary is up on top
    cv.rect(112, 48, 143, BACK, 3)
    cv.rect(112, 48, 143, 55, 1); cv.rect(112, 56, 143, 56, 2)
    cv.frame(112, 48, 143, BACK, 2)
    cv.rect(127, 57, 128, BACK - 8, 2)
    cv.pattern(113, 57, 126, BACK - 8, lambda x, y: 1 if x == 113 else (2 if x == 126 and checker(x, y) else None))
    cv.pattern(129, 57, 142, BACK - 8, lambda x, y: 1 if x == 129 else (2 if x == 142 and checker(x, y) else None))
    cv.rect(123, 88, 124, 91, 1); cv.rect(131, 88, 132, 91, 1)
    cv.rect(112, BACK - 7, 143, BACK - 7, 2)
    cv.cells(28, 6, 35, 15, RED)
    shade_under(cv, 112, 143)
    return cv


def room_home():
    cv = Canvas()
    interior(cv, CYAN, paper_stripes, floor_col=YELLOW)
    doorway(cv, 0)
    window(cv, 13, 3, 3, 4, curtain=PURPLE)
    # sofa (cols 3-11)
    cv.rect(12, 92, 43, 111, 3)
    cv.pattern(12, 92, 43, 111, lambda x, y: 2 if x % 16 == 11 else (1 if y < 96 and checker(x, y) else None))
    cv.frame(12, 92, 43, 111, 2)
    cv.box(8, 104, 15, 124, 3); cv.box(40, 104, 47, 124, 3)
    cv.rect(16, 112, 39, 122, 3); cv.rect(16, 112, 39, 112, 1); cv.rect(27, 113, 28, 122, 2)
    cv.pattern(16, 119, 39, 122, lambda x, y: 2 if checker(x, y) else None)
    cv.rect(8, 125, 47, 127, 2); cv.rect(12, 128, 13, BACK, 2); cv.rect(42, 128, 43, BACK, 2)
    cv.cells(2, 11, 11, 15, RED)
    shade_under(cv, 8, 47)
    # TV on a cabinet (cols 13-17)
    cv.box(52, 112, 71, BACK, 1)
    cv.rect(61, 114, 62, BACK - 2, 2)
    cv.box(52, 88, 71, 111, 2)
    cv.rect(55, 91, 68, 108, 3)
    cv.pattern(55, 91, 68, 108, lambda x, y: 1 if y % 4 == 0 else (2 if x % 4 == 1 and y % 2 else None))
    cv.art(56, 80, ["..b......b..", "...b....b...", "....b..b....", ".....bb....."])
    cv.cells(13, 11, 17, 13, BLUE)
    # kitchen: fridge (cols 20-22), counter with a pot (cols 23-26)
    cv.rect(80, 72, 91, BACK, 3)
    cv.frame(80, 72, 91, BACK, 2)
    cv.rect(80, 95, 91, 95, 2)
    cv.rect(88, 80, 88, 90, 1); cv.rect(88, 100, 88, 120, 1)
    cv.pattern(81, 73, 82, BACK - 1, lambda x, y: 1)
    cv.cells(20, 9, 22, 16, WHITE)
    cv.rect(92, 104, 107, BACK, 1)
    cv.rect(92, 104, 107, 104, 2); cv.frame(95, 108, 104, 128, 2)
    cv.art(94, 94, [".bbbbbbbbbb.", "bccccccccccb", "bccccccccccb", ".bbbbbbbbbb."])
    cv.cells(23, 11, 26, 12, RED)
    shade_under(cv, 80, 107)
    # shower (cols 28-34)
    cv.rect(112, 56, 139, 57, 2)
    cv.art(132, 58, ["aaaa", ".aa.", ".aa."])
    cv.pattern(112, 58, 123, 111, lambda x, y: 2 if (x % 4 == 0 and checker(x, y)) else (1 if x % 4 == 2 else 3))
    cv.box(112, 112, 139, 126, 3)
    cv.rect(113, 113, 138, 113, 1)
    cv.rect(116, 127, 117, BACK, 2); cv.rect(134, 127, 135, BACK, 2)
    cv.cells(28, 7, 30, 13, PURPLE)
    cv.cells(28, 14, 34, 15, WHITE)
    door(cv, 36, RED)
    return cv


def room_street():
    cv = Canvas()
    sky_clouds(cv, [(3, 1, 4), (20, 1, 3), (33, 2, 3)])
    # our house (cols 0-13): tiled roof, rendered wall, door + windows
    for i in range(8):
        cv.rect(i * 4 - 4, 24 + i * 4, 60 - i * 4, 27 + i * 4, 3)
    cv.pattern(0, 24, 59, 55, lambda x, y: 2 if cv.get(x, y) == 3 and (y % 4 == 3 or (x + (y // 4) * 4) % 8 == 0) else None)
    cv.rect(0, 56, 55, 127, 1)
    cv.pattern(0, 56, 55, 127, lambda x, y: 3 if (y % 8 == 0) or ((x + (y // 8) * 4) % 8 == 0) else None)
    cv.cells(0, 3, 14, 6, RED)
    cv.cells(0, 7, 13, 15, WHITE)
    window(cv, 1, 9, 3, 3)
    window(cv, 10, 9, 3, 3)
    door(cv, 5, YELLOW, 3, 72)
    # bench + lamp post (cols 15-22)
    bench(cv, 15, 5)
    lamp_post(cv, 22)
    # phone box (cols 24-26)
    cv.rect(96, 64, 107, BACK, 3)
    cv.rect(96, 64, 107, 71, 2)
    for y0 in (72, 88, 104):
        cv.rect(98, y0, 105, y0 + 11, 0); cv.frame(98, y0, 105, y0 + 11, 2)
    cv.rect(101, 72, 102, 115, 2)
    cv.cells(24, 8, 26, 16, RED)
    shade_under(cv, 96, 107)
    # the cafe front (cols 28-39)
    cv.rect(112, 32, 159, 127, 3)
    cv.pattern(112, 32, 159, 63, lambda x, y: 1 if x % 8 == 0 and y % 8 == 0 else None)
    cv.rect(112, 32, 112, 127, 2)
    cv.cells(28, 4, 39, 15, CYAN)
    cv.put_text(31, 5, "CAFE", BLACK)
    for x in range(112, 160):                                   # striped awning
        for y in range(64, 72):
            cv.px(x, y, 3 if (x // 4) % 2 == 0 else 1)
        cv.px(x, 72 + (x // 2) % 2, 2)
    cv.cells(28, 8, 39, 9, RED)
    window(cv, 29, 10, 4, 3)
    window(cv, 35, 10, 4, 3)
    pavement(cv)
    return cv


def room_cafe():
    cv = Canvas()
    interior(cv, RED, paper_stripes, floor="tile", floor_col=YELLOW)
    cv.put_text(17, 2, "CAFE", WHITE)
    cv.put_text(22, 2, "#", WHITE)
    # menu board (cols 2-9)
    cv.rect(8, 24, 39, 63, 2)
    cv.frame(8, 24, 39, 63, 1)
    cv.put_text(3, 4, "MENU", WHITE)
    cv.put_text(3, 5, "COFFEE", YELLOW)
    cv.put_text(3, 6, "CAKE", YELLOW)
    # counter (cols 1-14) with the coffee machine; Mo works behind it
    cv.rect(4, 112, 59, BACK, 1)
    cv.pattern(4, 112, 59, BACK, lambda x, y: 2 if x % 8 == 3 else (3 if x % 8 == 4 else None))
    cv.rect(0, 104, 63, 111, 3); cv.rect(0, 104, 63, 104, 1); cv.rect(0, 111, 63, 111, 2)
    cv.cells(0, 13, 15, 13, WHITE)
    cv.cells(1, 14, 14, 16, RED)
    cv.rect(44, 80, 55, 103, 3); cv.frame(44, 80, 55, 103, 2)
    cv.rect(46, 84, 53, 90, 2); cv.rect(48, 92, 49, 98, 1)
    cv.art(47, 99, ["bccb", ".bb."])
    cv.cells(11, 10, 13, 12, WHITE)
    cv.art(16, 98, [".bbb..", "bcccbb", "bccc.b", "bcccbb", ".bbb.."])   # cups
    cv.art(28, 96, ["..cc..", ".cccc.", "cccccc", "bbbbbb"])               # cake
    cv.cells(4, 12, 8, 12, YELLOW)
    shade_under(cv, 4, 59)
    # tables with chairs and flowers (cols 19-23, 29-33)
    for cx in (20, 30):
        x0 = cx * 4
        cv.rect(x0, 104, x0 + 19, 107, 3); cv.rect(x0, 104, x0 + 19, 104, 1); cv.rect(x0, 107, x0 + 19, 107, 2)
        cv.rect(x0 + 9, 108, x0 + 10, BACK, 2); cv.rect(x0 + 5, BACK - 1, x0 + 14, BACK, 2)
        cv.art(x0 + 7, 94, ["..c..", ".cac.", "..c..", ".bbb.", ".bbb."])
        cv.cells(cx, 11, cx + 4, 13, WHITE)
        for chx in (x0 - 8, x0 + 20):
            cv.rect(chx + (0 if chx < x0 else 6), 92, chx + (1 if chx < x0 else 7), BACK, 2)
            cv.rect(chx, 112, chx + 7, 114, 1); cv.rect(chx, 115, chx + 7, 115, 2)
            cv.rect(chx + (6 if chx < x0 else 0), 116, chx + (7 if chx < x0 else 1), BACK, 2)
        shade_under(cv, x0 - 8, x0 + 27)
    window(cv, 36, 3, 3, 4, curtain=YELLOW)
    return cv


def room_shop():
    cv = Canvas()
    interior(cv, GREEN, paper_stripes, floor="tile", floor_col=WHITE)
    cv.put_text(14, 2, "SUPER SHOP", YELLOW)
    def shelf(cx0, cx1, colour, goods):
        x0, x1 = cx0 * 4, cx1 * 4 + 3
        cv.rect(x0, 48, x1, BACK, 1); cv.frame(x0, 48, x1, BACK, 2)
        for i, y in enumerate((64, 80, 96, 112, 128)):
            cv.rect(x0 + 1, y - 14, x1 - 1, y - 1, 2)
            cv.rect(x0, y, x1, y + 1, 1)
            for x in range(x0 + 4, x1 - 3, 8):
                g = goods[(x // 8 + i) % len(goods)]
                cv.art(x, y - len(g), g)
        cv.cells(cx0, 6, cx1, 16, colour)
        shade_under(cv, x0, x1)
    tin = [".cc.", "cbbc", "cccc", "cbbc", "cccc", "cccc", ".cc."]
    box = ["bbbb", "bccb", "bcab", "bccb", "bccb", "bccb", "bbbb"]
    jar = [".bb.", "bbbb", "cccc", "caac", "cccc", "cccc", ".cc."]
    shelf(1, 9, RED, [tin, box])
    shelf(12, 18, YELLOW, [jar, tin])
    # clothes rail (cols 21-27) with dresses
    cv.rect(84, 56, 111, 57, 2)
    cv.rect(84, 56, 85, BACK, 2); cv.rect(110, 56, 111, BACK, 2)
    for x in range(88, 108, 8):
        cv.art(x, 58, ["..b..", ".b.b.", "ccccc", "cbcbc", ".ccc.", ".ccc.", "ccccc", "ccccc", "ccccc", "ccccc",
                       "ccccc", "cbcbc"])
    cv.cells(21, 7, 27, 9, PURPLE)
    cv.put_text(23, 11, "NEW", WHITE)
    # counter + till (cols 30-37)
    cv.rect(120, 104, 151, BACK, 1); cv.frame(120, 104, 151, BACK, 2)
    cv.rect(120, 104, 151, 105, 2)
    cv.art(136, 88, ["bbbbbbbbbb", "bccccccccb", "bcbcbcbcbb", "bccccccccb", "bbbbbbbbbb", "...bbbb..."])
    cv.cells(34, 11, 36, 12, CYAN)
    cv.put_text(31, 14, "$$$", YELLOW)
    window(cv, 32, 3, 4, 4)
    return cv


def room_swings():
    cv = Canvas()
    sky_clouds(cv, [(4, 1, 3), (19, 1, 4), (32, 2, 3)])
    far_hills(cv, 96, GREEN)
    cv.put_text(17, 4, "SWINGS", WHITE)
    # swing frame (cols 2-10), seat at y 112
    cv.rect(8, 48, 43, 50, 2)
    cv.rect(8, 48, 10, BACK, 2); cv.rect(41, 48, 43, BACK, 2)
    cv.rect(17, 51, 17, 111, 1); cv.rect(33, 51, 33, 111, 1)
    cv.rect(15, 112, 35, 114, 3); cv.rect(15, 115, 35, 115, 2)
    cv.cells(3, 14, 8, 14, RED)
    # slide (cols 14-26): ladder up the left, chute down to the right
    for y in range(64, BACK, 8):
        cv.rect(56, y, 63, y, 2)
    cv.rect(56, 56, 56, BACK, 2); cv.rect(63, 56, 63, BACK, 2)
    cv.rect(56, 56, 71, 58, 3); cv.rect(56, 59, 71, 59, 2)
    for i in range(0, 72):
        y = 60 + i
        xx = 64 + (i * 40) // 72
        cv.rect(xx, y, xx + 4, y, 3)
        cv.px(xx, y + 1, 2); cv.px(xx + 4, y, 1)
    cv.cells(14, 7, 27, 16, YELLOW)
    # see-saw (cols 29-36)
    for i in range(32):
        cv.rect(116 + i, 118 - i // 4, 116 + i, 119 - i // 4, 3)
    cv.art(128, 116, ["..bb..", ".bbbb.", "bbbbbb", "bbbbbb"])
    cv.rect(129, 120, 134, BACK, 2)
    cv.cells(29, 13, 37, 15, RED)
    lamp_post(cv, 38)
    grass_ground(cv)
    return cv


def room_park():
    cv = Canvas()
    sky_clouds(cv, [(14, 1, 4), (30, 2, 3)])
    far_hills(cv, 96, GREEN)
    grass_ground(cv)
    cv.put_text(30, 4, "PARK", WHITE)
    # the big oak: a locket glints up in its branches (cols 2-11)
    tree(cv, 2, 16, GREEN, 8, shade=False)
    # duck pond (cols 1-12)
    for y in range(144, 152):                     # one char row, cell-aligned: few tiles
        inset = 2 if y in (144, 151) else 0
        for x in range(8 + inset, 48 - inset):
            cv.px(x, y, 1 if (x % 4 == 2 and y % 4 == 2) else 3)
    for dx in (16, 32):
        cv.art(dx, 144, ["...bb.", "..baab", ".aaaa.", "aaaaa."])
    cv.cells(2, 18, 11, 18, BLUE)
    # fountain (cols 19-24)
    cv.art(80, 72, [
        "........cc..........",
        ".......c..c.........",
        "......c.cc.c........",
        ".....c..cc..c.......",
        "....c...cc...c......",
        "........cc..........",
        ".......bbbb.........",
        "........bb..........",
        "........bb..........",
        "........bb..........",
        "........bb..........",
        "........bb..........",
        "....bbbbbbbbbb......",
        "...bccccccccccb.....",
        "..bccccccccccccb....",
        "..bbbbbbbbbbbbbb....",
    ])
    cv.rect(84, 104, 99, BACK, 1)
    cv.pattern(84, 104, 99, BACK, lambda x, y: 2 if y % 8 == 7 or x % 8 == (0 if (y // 8) % 2 else 4) else None)
    cv.cells(19, 9, 25, 12, CYAN)
    # bench where Pip hangs out (cols 27-32)
    bench(cv, 27, 6)
    # open gate on the right: the path to the woods
    cv.rect(148, 96, 149, BACK, 2); cv.rect(148, 94, 151, 95, 2)
    cv.cells(37, 11, 37, 16, WHITE)
    return cv


def room_woods():
    cv = Canvas()
    # canopy: dithered dark leaves hiding the sky, a ragged edge every 8 px
    for x in range(W):
        edge = 32 + [0, 2, 3, 2, 0, -2, -3, -2][x % 8] + (4 if (x // 8) % 3 == 1 else 0)
        for y in range(0, edge):
            cv.p[y][x] = mix(x, y, (y - (edge - 16)) / 16.0, 3, 2) if y > edge - 16 else (1 if (x % 8 == 1 and y % 8 == 5) else 3)
    cv.cells(0, 0, CW - 1, 5, GREEN)
    # distant trunks in the mist (dithered black on the sky)
    for x in range(W):
        if x % 16 in (5, 6, 7):
            for y in range(28, 128):
                cv.px(x, y, 2 if checker(x, y) or x % 16 == 6 else None)
    cv.pattern(0, 112, W - 1, 127, lambda x, y: 2 if (y % 2 == 0 and x % 2 == 0) or y > 123 else None)
    # trunks on cell boundaries
    for tcx in (2, 9, 17, 26, 35):
        tx = tcx * 4
        cv.rect(tx, 24, tx + 11, BACK, 3)
        cv.pattern(tx, 24, tx + 11, BACK, lambda x, y: 1 if x == tx + 1 else
                   (2 if x >= tx + 10 or (x == tx + 9 and checker(x, y)) or (x % 4 == 2 and y % 8 == 0) else None))
        cv.cells(tcx, 3, tcx + 2, 16, RED)
    # ferns along the ground
    for x0 in range(0, W, 16):
        if not 112 <= x0 < 144 and not 76 <= x0 < 104:
            cv.art(x0 + 4, 120, ["c...c...", ".c.c.c.c", "..ccc.c.", "...cc...", "...bc..."])
    cv.cells(0, 15, CW - 1, 15, GREEN)
    # owl in a hollow
    cv.art(108, 56, [".bbbb.", "baabaa", "bccbcc", ".bbbb.", ".bccb.", "..bb.."])
    cv.cells(27, 7, 28, 7, YELLOW)
    # mushrooms (forage spot cols 20-25)
    for x0 in (80, 88, 96):
        cv.art(x0, 122, [".cccc.", "cacacc", "cccccc", "..aa..", "..aa..", ".aaaa."])
    cv.cells(20, 15, 25, 16, RED)
    # brambles: the bracelet is caught in them (cols 29-34)
    for x in range(116, 140):
        for y in range(104, BACK + 1):
            v = [".bcb", "cb.b", "bcbc", "b.cb"][y % 4][x % 4]
            if v != '.' and not (y < 108 and x % 8 > 5):
                cv.px(x, y, 2 if v == 'b' else 3)
    cv.cells(29, 13, 34, 16, PURPLE)
    # forest floor: leaf litter dithered into the dark
    for y in range(128, H):
        for x in range(W):
            if not (116 <= x < 140 and y <= BACK) and not (80 <= x < 104 and y < 128):
                d = y - 128
                cv.p[y][x] = 3 if (x % 8 == 2 and y % 8 == 3) else mix(x, y, d / 32.0, 1, 2)
    cv.cells(0, 16, CW - 1, 19, RED)
    return cv


def room_library():
    cv = Canvas()
    interior(cv, BLUE, paper_panels, floor="wood", floor_col=RED)
    cv.put_text(16, 2, "LIBRARY", YELLOW)
    def case(cx0, cx1, colour):
        x0, x1 = cx0 * 4, cx1 * 4 + 3
        cv.rect(x0, 32, x1, BACK, 1); cv.frame(x0, 32, x1, BACK, 2)
        for y in (48, 64, 80, 96, 112, 128):
            cv.rect(x0 + 1, y - 14, x1 - 1, y - 1, 2)
            cv.pattern(x0 + 1, y - 12, x1 - 1, y - 1, lambda x, yy: (3 if x % 8 in (0, 1, 3, 4, 6) else 1)
                       if (yy >= y - 12 + (x % 8 == 4) * 2) and x % 8 != 7 else None)
            cv.rect(x0, y, x1, y + 1, 1)
        cv.cells(cx0, 4, cx1, 16, colour)
        shade_under(cv, x0, x1)
    case(1, 10, RED)
    case(29, 38, PURPLE)
    # reading table with a lamp (cols 13-20)
    cv.rect(52, 104, 83, 107, 1); cv.rect(52, 107, 83, 107, 2)
    cv.rect(54, 108, 55, BACK, 2); cv.rect(80, 108, 81, BACK, 2)
    cv.art(56, 98, ["bbbbbbbb", "baaaaaab", "bbbbbbbb"])
    cv.art(72, 86, ["..ccc..", ".ccccc.", "ccccccc", "...b...", "...b...", "..bbb.."])
    cv.cells(18, 10, 19, 11, YELLOW)
    cv.cells(13, 12, 20, 13, WHITE)
    shade_under(cv, 52, 83)
    # the librarian's desk (cols 22-27) with a stack of old newspapers
    cv.rect(88, 104, 111, BACK, 1); cv.frame(88, 104, 111, BACK, 2)
    cv.rect(86, 102, 113, 103, 2)
    cv.art(92, 92, ["aaaaaaaa", "abbbbbba", "aaaaaaaa", "abbbbba.", "aaaaaaaa", "abbbbbba", "aaaaaaaa"])
    cv.cells(22, 11, 27, 12, WHITE)
    window(cv, 13, 3, 4, 4, curtain=RED)
    return cv


ROOM_BUILDERS = [room_grans, room_garden, room_bedroom, room_home, room_street, room_cafe,
                 room_shop, room_swings, room_park, room_woods, room_library]

# Things you can use in each room: (first col, last col, action id)
# Action ids are defined in game.py (ACTIONS).
OBJECTS = [
    [(12, 16, "GRAN"), (23, 30, "ARMCHAIR")],
    [(30, 38, "FLOWERS")],
    [(3, 14, "SLEEP"), (16, 23, "COMPUTER")],
    [(2, 11, "TV"), (19, 26, "EAT"), (28, 34, "SHOWER")],
    [(15, 20, "BENCH"), (23, 27, "PHONE")],
    [(1, 6, "WORK"), (8, 11, "COFFEE")],
    [(1, 9, "GROCERY"), (11, 18, "SWEETS"), (20, 27, "OUTFIT")],
    [(2, 10, "SWING"), (13, 22, "SLIDE")],
    [(1, 11, "DUCKS"), (18, 24, "SPLASH"), (25, 28, "CHAT")],
    [(19, 26, "FORAGE")],
    [(12, 19, "READ"), (20, 23, "PAGE")],
]
# Who stands where: room -> (npc index in sprites.NPCS, PX)
# Each person stands just right of their talk spot, so the sister talking
# to them does not cover them up.
ROOM_NPC = {0: (1, 74), 5: (0, 54), 8: (2, 120), 10: (3, 102)}


FIRST_TILE = 72
# Room tiles may use these codes: the font glyphs no text in the game uses
# ([ frown ] " % moon sun and the spare UI slots), then 72-255.
# build.py checks that no message / HUD / page text uses one of them.
TILE_CODES = [27, 28, 29, 34, 37, 67, 68, 69, 70, 71] + list(range(FIRST_TILE, 256))


def build_group(g):
    """All rooms of charset group g -> (tile bytes {code: rows}, colour table
    {code: col|8}, {room: (char grid, colour grid, MC-override grid)}).
    Tiles are numbered from FIRST_TILE, shared by the group's rooms."""
    tiles, tile_bytes, colour_of = {}, {}, {}
    free = list(TILE_CODES)
    out = {}
    tcol = GROUP_TEXT_COL[g]
    for idx in [r for r in range(len(ROOM_BUILDERS)) if ROOM_GROUP[r] == g]:
        cv = ROOM_BUILDERS[idx]()
        grid, cgrid, ogrid = [], [], []
        for cy in range(CH):
            for cx in range(CW):
                if (cx, cy) in cv.text:
                    code, _ = cv.text[(cx, cy)]
                    grid.append(code); cgrid.append(tcol); ogrid.append(0)
                    continue
                rows = []
                for y in range(8):
                    bb = 0
                    for x in range(4):
                        bb = (bb << 2) | cv.p[cy * 8 + y][cx * 4 + x]
                    rows.append(bb)
                col = cv.col[cy][cx]
                if all(r == 0 for r in rows):
                    grid.append(32); cgrid.append(tcol); ogrid.append(0)
                    continue
                uses_c = any(((r >> sh) & 3) == 3 for r in rows for sh in (0, 2, 4, 6))
                key = (tuple(rows), col if uses_c else -1)
                if key not in tiles:
                    if not free:
                        raise ValueError("charset group %s needs more than %d tiles" % (GROUP_NAMES[g], len(TILE_CODES)))
                    code = free.pop(0)
                    tiles[key] = code
                    tile_bytes[code] = rows
                    colour_of[code] = (col if uses_c else 0) | 8
                code = tiles[key]
                grid.append(code); cgrid.append(colour_of[code] & 7); ogrid.append(1)
        out[idx] = (grid, cgrid, ogrid)
    return tile_bytes, colour_of, out, len(TILE_CODES) - len(free)


if __name__ == "__main__":
    for g in range(len(GROUP_NAMES)):
        print(GROUP_NAMES[g], build_group(g)[3])
