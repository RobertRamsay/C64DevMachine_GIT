"""POLARITY rooms: each location is drawn on a 160x160 multicolour canvas
(40x20 cells of 4x8 fat pixels), then sliced into deduplicated MC chars.

Pixel values: 0 = sky ($D021, changes with the clock), 1 = brown ($D022),
2 = black ($D023), 3 = the cell's own colour (0-7, colour RAM | 8).
A cell can instead hold a hires font char (text on signs)."""
import font

W, H = 160, 160          # fat pixels
CW, CH = 40, 20          # cells
BLACK, WHITE, RED, CYAN, PURPLE, GREEN, BLUE, YELLOW = range(8)

ROOM_NAMES = ["HOME", "STREET", "SHOP", "CAFE", "PARK"]
# Font chars (signs) in a room all use one colour: the map stores chars only.
ROOM_TEXT_COL = [WHITE, WHITE, YELLOW, WHITE, WHITE]


class Canvas:
    def __init__(self):
        self.p = [[0] * W for _ in range(H)]
        self.col = [[BLACK] * CW for _ in range(CH)]
        self.text = {}                       # (cx,cy) -> (screen code, colour)

    def px(self, x, y, v):
        if 0 <= x < W and 0 <= y < H:
            self.p[y][x] = v

    def rect(self, x0, y0, x1, y1, v):
        for y in range(max(0, y0), min(H - 1, y1) + 1):
            for x in range(max(0, x0), min(W - 1, x1) + 1):
                self.p[y][x] = v

    def frame(self, x0, y0, x1, y1, v):
        self.rect(x0, y0, x1, y0, v); self.rect(x0, y1, x1, y1, v)
        self.rect(x0, y0, x0, y1, v); self.rect(x1, y0, x1, y1, v)

    def cells(self, cx0, cy0, cx1, cy1, colour):
        for cy in range(cy0, cy1 + 1):
            for cx in range(cx0, cx1 + 1):
                if 0 <= cx < CW and 0 <= cy < CH:
                    self.col[cy][cx] = colour

    def put_text(self, cx, cy, s, colour):
        for i, ch in enumerate(s):
            self.text[(cx + i, cy)] = (font.screen_code(ch), colour)
            self.rect((cx + i) * 4, cy * 8, (cx + i) * 4 + 3, cy * 8 + 7, 0)

    def pattern(self, x0, y0, x1, y1, fn):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                v = fn(x, y)
                if v is not None:
                    self.p[y][x] = v

    def art(self, x0, y0, rows, key):
        """Stamp ascii art; key maps chars to pixel values ('.' = leave)."""
        for dy, r in enumerate(rows):
            for dx, ch in enumerate(r):
                if ch in key:
                    self.px(x0 + dx, y0 + dy, key[ch])


K = {'.': None, ' ': None, 'o': 0, 'a': 1, 'b': 2, 'c': 3}
def art(cv, x, y, rows):
    cv.art(x, y, rows, {k: v for k, v in K.items() if v is not None})


# ------------------------------------------------------------------ pieces
def wallpaper(cv, colour, y0=8, y1=119):
    # pinstripe wallpaper with a little dot motif
    cv.pattern(0, y0, W - 1, y1, lambda x, y: 1 if x % 4 == 3 else (2 if (x % 4 == 1 and y % 8 == 3) else 3))
    cv.cells(0, y0 // 8, CW - 1, y1 // 8, colour)

def ceiling(cv):
    cv.rect(0, 0, W - 1, 5, 1)
    cv.rect(0, 6, W - 1, 7, 2)
    cv.pattern(0, 0, W - 1, 5, lambda x, y: 2 if (x % 8 == 7 and y < 5) else None)

def skirting(cv):
    cv.rect(0, 120, W - 1, 120, 2)
    cv.rect(0, 121, W - 1, 127, 1)

def wood_floor(cv):
    cv.rect(0, 128, W - 1, H - 1, 1)
    cv.rect(0, 128, W - 1, 128, 3)                       # polished edge
    for y in range(132, H, 6):
        cv.rect(0, y, W - 1, y, 2)
    def joints(x, y):
        band = (y - 129) // 6
        if (x + band * 6) % 16 == 0 and y > 128:
            return 2
        return None
    cv.pattern(0, 129, W - 1, H - 1, joints)
    cv.cells(0, 16, CW - 1, 19, YELLOW)

def tile_floor(cv, colour):
    cv.rect(0, 128, W - 1, 128, 2)
    cv.pattern(0, 129, W - 1, H - 1, lambda x, y: 3 if ((x // 4) + ((y - 129) // 8)) % 2 == 0 else 2)
    cv.cells(0, 16, CW - 1, 19, colour)

def bricks(cv, y0=136):
    """Chunky platform-game brick blocks."""
    def b(x, y):
        yy = (y - y0) % 8
        row = (y - y0) // 8
        xx = (x + (4 if row % 2 else 0)) % 8
        if yy == 7 or xx == 7:
            return 2
        if yy == 0 or xx == 0:
            return 1
        return 3
    cv.pattern(0, y0, W - 1, H - 1, b)
    cv.cells(0, y0 // 8, CW - 1, 19, RED)

def grass(cv, y=128):
    cv.rect(0, y + 2, W - 1, y + 7, 3)
    cv.pattern(0, y, W - 1, y + 1, lambda x, yy: 3 if (x * 7 + yy * 3) % 5 < 2 + (yy - y) else None)
    cv.rect(0, y + 7, W - 1, y + 7, 2)
    cv.cells(0, y // 8, CW - 1, y // 8, GREEN)

def pavement(cv, y=128):
    cv.rect(0, y, W - 1, y + 7, 1)
    cv.rect(0, y, W - 1, y, 2)
    cv.pattern(0, y + 1, W - 1, y + 7, lambda x, yy: 2 if x % 12 == 0 else None)
    cv.rect(0, y + 7, W - 1, y + 7, 2)

def cloud(cv, cx, cy, wide=3):
    x0, y0 = cx * 4, cy * 8
    w = wide * 4
    art(cv, x0, y0 + 1, [
        "...cc" + "." * (w - 5),
        ".cccccc" + "." * (w - 7),
        "c" * (w - 2) + "..",
        "c" * (w - 1) + ".",
        "." + "c" * (w - 2) + ".",
    ])
    cv.cells(cx, cy, cx + wide - 1, cy, WHITE)

def window(cv, cx, cy, curtain=None):
    """3x3 cell window: glass shows the sky."""
    x0, y0, x1, y1 = cx * 4, cy * 8, cx * 4 + 11, cy * 8 + 23
    cv.rect(x0, y0, x1, y1, 0)
    cv.frame(x0, y0, x1, y1, 2)
    cv.rect(x0 + 5, y0, x0 + 6, y1, 2)
    cv.rect(x0, y0 + 11, x1, y0 + 12, 2)
    cv.rect(x0 - 1, y1 + 1, x1 + 1, y1 + 2, 1)          # sill
    if curtain is not None:
        for side in (x0 - 3, x1 + 1):
            cv.rect(side, y0 - 1, side + 2, y1, 3)
            cv.pattern(side, y0 - 1, side + 2, y1, lambda x, y: 2 if (y % 4 == 0 and x == side + 1) else None)
        cv.cells(cx - 1, cy, cx - 1, cy + 2, curtain)
        cv.cells(cx + 3, cy, cx + 3, cy + 2, curtain)

def door(cv, cx, cy, colour=YELLOW):
    """3x6 cell door (bottom at row cy+5)."""
    x0, y0, x1, y1 = cx * 4, cy * 8, cx * 4 + 11, cy * 8 + 47
    cv.rect(x0 - 1, y0 - 2, x1 + 1, y1, 2)
    cv.rect(x0, y0, x1, y1, 1)
    cv.frame(x0 + 2, y0 + 3, x1 - 2, y0 + 19, 2)
    cv.frame(x0 + 2, y0 + 24, x1 - 2, y1 - 4, 2)
    cv.rect(x1 - 3, y0 + 21, x1 - 2, y0 + 22, 3)         # knob
    cv.cells(cx, cy, cx + 2, cy + 5, colour)

def lamp_post(cv, cx, top):
    x = cx * 4
    art(cv, x - 1, top * 8, [
        ".bbbb.",
        "bccccb",
        "bccccb",
        ".bbbb.",
    ])
    cv.rect(x + 1, top * 8 + 4, x + 2, 127, 2)
    cv.rect(x, 124, x + 3, 127, 2)
    cv.cells(cx - 1, top, cx + 1, top, YELLOW)

def bench(cv, cx, w=3):
    x0, x1 = cx * 4, cx * 4 + w * 4 - 1
    cv.rect(x0, 112, x1, 113, 1)                          # backrest
    cv.rect(x0, 117, x1, 118, 1)                          # seat
    cv.rect(x0, 119, x1, 119, 2)
    for x in (x0 + 1, x1 - 1):
        cv.rect(x, 112, x, 127, 2)

def tree(cv, cx, top, colour=GREEN):
    """Round bushy tree, 5 cells wide; trunk down to the grass."""
    x0 = cx * 4
    art(cv, x0, top * 8, [
        "......cccccc........",
        "....cccccccccc......",
        "...cccccbcccccc.....",
        "..cccccccccccbccc...",
        ".ccbccccccccccccc...",
        ".cccccccccbcccccccc.",
        "cccccccccccccccbccc.",
        "ccccbccccccccccccccc",
        "cccccccccccccccccccc",
        "cccccccbccccccbccccc",
        ".ccccccccccccccccccc",
        ".cccbcccccccccccccc.",
        "..ccccccccccbccccc..",
        "...cccccccccccccc...",
        "....ccccaaccccc.....",
        "......cc.aa.cc......",
    ])
    cv.rect(x0 + 9, top * 8 + 16, x0 + 10, 127, 1)
    cv.rect(x0 + 8, top * 8 + 16, x0 + 8, 127, 2)
    cv.rect(x0 + 7, 125, x0 + 12, 127, 1)
    cv.cells(cx, top, cx + 4, top + 1, colour)


# ------------------------------------------------------------------ rooms
def room_home():
    cv = Canvas()
    ceiling(cv)
    wallpaper(cv, CYAN)
    skirting(cv)
    wood_floor(cv)
    window(cv, 3, 4, curtain=PURPLE)
    window(cv, 29, 4, curtain=PURPLE)
    # picture frame
    cv.rect(56, 48, 67, 63, 1); cv.rect(58, 50, 65, 61, 3)
    art(cv, 58, 54, ["..b.....", ".bbb..b.", "bbbbbbbb"])
    cv.cells(14, 6, 16, 7, GREEN)
    # BED (cols 2-6, rows 13-15)
    cv.rect(8, 100, 10, 127, 1); cv.frame(8, 100, 10, 127, 2)       # headboard
    cv.rect(11, 112, 27, 119, 3)                                     # mattress / quilt
    cv.rect(11, 110, 15, 113, 3)                                     # pillow puff
    cv.rect(11, 120, 27, 121, 1)
    cv.rect(11, 122, 27, 122, 2)
    cv.rect(12, 123, 12, 127, 2); cv.rect(26, 123, 26, 127, 2)
    cv.rect(16, 111, 27, 111, 2)                                     # quilt edge
    cv.pattern(16, 112, 27, 119, lambda x, y: 1 if (x + y) % 6 == 0 else None)
    cv.cells(2, 13, 6, 15, RED)
    # TV on a cabinet (cols 9-11)
    cv.rect(36, 116, 47, 127, 1); cv.frame(36, 116, 47, 127, 2); cv.rect(41, 118, 42, 125, 2)
    cv.rect(37, 98, 46, 114, 2)
    cv.rect(39, 100, 44, 112, 3)
    cv.pattern(39, 100, 44, 112, lambda x, y: 1 if y % 3 == 0 else None)
    art(cv, 38, 90, ["..b....b..", "...b..b...", "....bb...."])
    cv.cells(9, 11, 11, 14, BLUE)
    # FRIDGE (cols 18-19, rows 12-15)
    cv.rect(72, 96, 79, 127, 3); cv.frame(72, 96, 79, 127, 2)
    cv.rect(72, 107, 79, 107, 2)
    cv.rect(77, 99, 77, 104, 1); cv.rect(77, 110, 77, 118, 1)
    cv.cells(18, 12, 19, 15, WHITE)
    # kitchen counter + pot (cols 20-22)
    cv.rect(80, 112, 91, 127, 1); cv.rect(80, 112, 91, 112, 2); cv.frame(82, 115, 89, 125, 2)
    art(cv, 83, 105, [".bbbbbb.", "bccccccb", "bccccccb", ".bbbbbb."])
    cv.cells(20, 13, 22, 13, RED)
    # SHOWER (cols 25-27, rows 10-15)
    cv.rect(98, 80, 113, 81, 2)                                      # rail
    art(cv, 110, 82, ["aaa", ".a.", ".a."])                          # shower head
    cv.rect(98, 82, 104, 111, 3)                                     # curtain
    cv.pattern(98, 82, 104, 111, lambda x, y: 2 if x % 3 == 0 else None)
    cv.rect(98, 112, 113, 123, 3); cv.frame(98, 112, 113, 123, 2)    # tub
    cv.rect(100, 124, 101, 127, 2); cv.rect(110, 124, 111, 127, 2)
    cv.cells(24, 10, 26, 13, PURPLE)
    cv.cells(24, 14, 28, 15, WHITE)
    # lamp
    art(cv, 128, 96, ["..cccc..", ".cccccc.", "cccccccc", "...bb...", "...bb..."])
    cv.rect(131, 101, 132, 125, 2); cv.rect(129, 126, 134, 127, 2)
    cv.cells(32, 12, 33, 12, YELLOW)
    # plant
    art(cv, 140, 100, [".c..c.", "cc.cc.", ".cccc.", "c.cc.c", ".cccc."])
    cv.rect(141, 105, 144, 111, 1); cv.frame(141, 105, 144, 111, 2)
    cv.cells(35, 12, 35, 12, GREEN)
    door(cv, 37, 10)
    return cv


def room_street():
    cv = Canvas()
    cloud(cv, 3, 1, 4); cloud(cv, 21, 2, 3); cloud(cv, 33, 1, 3)
    # house (cols 0-12)
    for i in range(6):                                               # roof
        cv.rect(2 + i * 2 - 2, 32 + i * 4, 50 - i * 2 + 2, 35 + i * 4, 1)
    cv.pattern(0, 32, 52, 55, lambda x, y: 2 if (cv.p[y][x] == 1 and (y % 4 == 0 or x % 6 == (y // 4) % 2 * 3)) else None)
    cv.rect(2, 56, 48, 127, 3)
    cv.rect(2, 56, 48, 57, 2)
    cv.cells(0, 7, 12, 15, WHITE)
    window(cv, 2, 8); window(cv, 8, 8)
    door(cv, 5, 10, colour=WHITE)
    # bench (cols 8-10 is home door area -> bench at 13-15)
    bench(cv, 14)
    lamp_post(cv, 19, 9)
    # phone box (cols 22-23, rows 9-15)
    cv.rect(88, 72, 95, 127, 3); cv.frame(88, 72, 95, 127, 2)
    cv.rect(89, 80, 94, 104, 0); cv.frame(89, 80, 94, 104, 2); cv.rect(91, 80, 91, 104, 2)
    cv.rect(88, 72, 95, 75, 2)
    cv.cells(22, 9, 23, 15, RED)
    # shop front (cols 27-39)
    cv.rect(108, 40, 159, 127, 3)
    cv.rect(108, 40, 159, 41, 2)
    cv.cells(27, 5, 39, 15, CYAN)
    cv.put_text(30, 6, "SHOP", BLACK)
    cv.pattern(108, 64, 159, 71, lambda x, y: 3 if (x // 4) % 2 == 0 else 1)   # awning
    cv.rect(108, 72, 159, 72, 2)
    cv.cells(27, 8, 39, 8, RED)
    window(cv, 28, 10); window(cv, 34, 10)
    pavement(cv)
    bricks(cv)
    return cv


def room_shop():
    cv = Canvas()
    ceiling(cv)
    wallpaper(cv, GREEN)
    skirting(cv)
    tile_floor(cv, WHITE)
    cv.put_text(14, 2, "SUPER SHOP", YELLOW)
    # grocery shelves (cols 3-8, rows 9-15)
    def shelf(cx0, cx1, colour, goods):
        x0, x1 = cx0 * 4, cx1 * 4 + 3
        cv.rect(x0, 72, x1, 127, 1); cv.frame(x0, 72, x1, 127, 2)
        for i, y in enumerate((80, 96, 112)):
            cv.rect(x0 + 1, y - 7, x1 - 1, y - 1, 0)
            cv.rect(x0, y, x1, y + 1, 2)
            for x in range(x0 + 2, x1 - 1, 4):
                g = goods[(x // 4 + i) % len(goods)]
                art(cv, x, y - 6, g)
        cv.cells(cx0, 9, cx1, 14, colour)
    tin = [".cc.", "cbbc", "cccc", "cbbc", "cccc", ".cc."]
    box = ["bbb.", "bcc.", "bcb.", "bcc.", "bcc.", "bbb."]
    jar = [".bb.", "cccc", "c.cc", "cc.c", "cccc", ".cc."]
    shelf(3, 8, RED, [tin, box])
    shelf(12, 16, YELLOW, [jar])
    # clothes rail (cols 21-26)
    cv.rect(84, 72, 107, 73, 2)
    cv.rect(85, 72, 85, 127, 2); cv.rect(106, 72, 106, 127, 2)
    for i, x in enumerate(range(88, 104, 5)):
        art(cv, x, 74, ["..b..", ".b.b.", "ccccc", "cc.cc", ".ccc.", ".ccc.", "ccccc", "ccccc", "ccccc", "ccccc"])
    cv.cells(21, 9, 26, 10, PURPLE)
    cv.put_text(22, 13, "NEW", WHITE)
    # counter + till (cols 30-36)
    cv.rect(120, 108, 147, 127, 1); cv.frame(120, 108, 147, 127, 2)
    cv.rect(120, 106, 147, 107, 2)
    art(cv, 136, 94, ["bbbbbbbb", "bccccccb", "bcbcbcbb", "bccccccb", "bbbbbbbb", "..bbbb.."])
    cv.cells(34, 11, 35, 12, CYAN)
    window(cv, 34, 4)
    cv.put_text(30, 14, "$$$", YELLOW)
    return cv


def room_cafe():
    cv = Canvas()
    ceiling(cv)
    wallpaper(cv, RED)
    skirting(cv)
    tile_floor(cv, YELLOW)
    cv.put_text(16, 2, "CAFE", WHITE)
    cv.put_text(21, 2, "#", RED)
    # menu board (cols 3-9, rows 4-7)
    cv.rect(12, 32, 39, 63, 2); cv.frame(12, 32, 39, 63, 1)
    cv.put_text(4, 5, "MENU", WHITE)
    cv.put_text(4, 6, "$2  ", YELLOW)
    # work counter (cols 2-9)
    cv.rect(8, 106, 39, 127, 1); cv.frame(8, 106, 39, 127, 2)
    cv.rect(6, 104, 41, 105, 2)
    cv.pattern(9, 108, 38, 126, lambda x, y: 2 if (x % 8 == 4) else None)
    art(cv, 14, 98, [".bb..", "bccb.", "bcc.b", "bccb.", ".bb.."])           # cup
    # coffee machine (cols 10-11)
    cv.rect(40, 88, 47, 127, 3); cv.frame(40, 88, 47, 127, 2)
    cv.rect(42, 92, 45, 96, 2); cv.rect(43, 100, 44, 104, 1)
    cv.rect(41, 110, 46, 111, 2)
    cv.cells(10, 11, 11, 15, WHITE)
    cv.cells(3, 12, 4, 12, WHITE)
    # tables
    for cx in (18, 28):
        x0 = cx * 4
        cv.rect(x0, 108, x0 + 15, 110, 3); cv.rect(x0, 111, x0 + 15, 111, 2)
        cv.rect(x0 + 7, 112, x0 + 8, 127, 2); cv.rect(x0 + 4, 126, x0 + 11, 127, 2)
        art(cv, x0 + 5, 101, ["..c..", ".ccc.", "bbbbb", ".bbb.", ".bbb.", "..b.."])     # flower vase
        cv.cells(cx, 12, cx + 3, 13, WHITE)
        for chx in (x0 - 6, x0 + 18):                                   # chairs
            cv.rect(chx, 96, chx + 1, 127, 1)
            cv.rect(chx, 112, chx + 5, 113, 1) if chx < x0 else cv.rect(chx - 4, 112, chx + 1, 113, 1)
    window(cv, 34, 4, curtain=YELLOW)
    return cv


def room_park():
    cv = Canvas()
    cloud(cv, 2, 1, 3); cloud(cv, 14, 2, 4); cloud(cv, 30, 1, 3)
    # sun-ish hills backdrop
    cv.pattern(0, 96, W - 1, 127, lambda x, y: 3 if y > 104 + int(8 * __import__('math').sin(x / 9.0)) else None)
    cv.cells(0, 12, CW - 1, 15, GREEN)
    tree(cv, 0, 7); tree(cv, 10, 6); tree(cv, 33, 7)
    # swings (cols 5-9)
    cv.rect(20, 72, 39, 73, 2)
    cv.rect(20, 72, 21, 127, 2); cv.rect(38, 72, 39, 127, 2)
    cv.rect(25, 74, 25, 110, 1); cv.rect(33, 74, 33, 110, 1)
    cv.rect(24, 111, 34, 112, 1)
    # fountain (cols 17-21)
    art(cv, 70, 84, [
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
        "........bb..........",
        "........bb..........",
        "....bbbbbbbbbb......",
        "...bccccccccccb.....",
        "..bccccccccccccb....",
        "..bbbbbbbbbbbbbb....",
        "...baaaaaaaaaab.....",
        "...baaaaaaaaaab.....",
        "...baaaaaaaaaab.....",
        "...baaaaaaaaaab.....",
        "...bbbbbbbbbbbb.....",
    ])
    cv.cells(17, 10, 21, 13, CYAN)
    cv.rect(73, 106, 85, 127, 1); cv.frame(73, 106, 85, 127, 2)
    # bench + friend (cols 26-30)
    bench(cv, 26, 4)
    art(cv, 110, 92, [            # a pal sitting on the bench, waving
        "...cccc....",
        "..cccccc...",
        "..ccbcbc..b",
        "..cccccc.b.",
        "...cccc.b..",
        "..bbbbbbb..",
        ".bbbbbbb...",
        ".bbbbbbb...",
        ".bbbbbbb...",
        "..bbbbbb...",
        "..aaaaa....",
        "..a...a....",
        "..a...a....",
        "..a...a....",
        ".bb..bb....",
    ])
    cv.cells(27, 11, 29, 12, YELLOW)
    # flowers
    cv.pattern(0, 120, W - 1, 127, lambda x, y: 3 if (y == 122 and x % 7 == 3) or (y == 121 and x % 7 == 3) else (1 if (y > 122 and x % 7 == 3) else None))
    cv.cells(0, 15, CW - 1, 15, YELLOW)
    # fence on the far right (no exit)
    for x in range(148, 160, 4):
        cv.rect(x, 104, x + 1, 127, 1); cv.rect(x, 103, x + 1, 103, 2)
    cv.rect(146, 108, 159, 109, 1); cv.rect(146, 118, 159, 119, 1)
    cv.put_text(30, 6, "PARK", WHITE)
    grass(cv)
    bricks(cv)
    return cv


ROOM_BUILDERS = [room_home, room_street, room_shop, room_cafe, room_park]

# Things you can use in each room: (first col, last col, action id)
# Action ids are defined in game.py (ACTIONS).
OBJECTS = [
    [(1, 7, "SLEEP"), (8, 12, "TV"), (17, 20, "EAT"), (23, 28, "SHOWER")],
    [(13, 17, "BENCH"), (21, 24, "PHONE")],
    [(2, 9, "GROCERY"), (11, 17, "SWEETS"), (20, 27, "OUTFIT")],
    [(1, 8, "WORK"), (9, 12, "COFFEE")],
    [(4, 10, "SWING"), (16, 22, "SPLASH"), (25, 31, "CHAT")],
]


FIRST_TILE = 72


def build_room(idx):
    """One room -> (tile bytes {code: 8 rows}, colour table {code: col|8},
    char grid, colour grid, MC-override grid). Tiles are numbered per room
    from FIRST_TILE: every room has its own CHAR_SET."""
    cv = ROOM_BUILDERS[idx]()
    tiles, tile_bytes, colour_of = {}, {}, {}
    nxt = FIRST_TILE
    grid, cgrid, ogrid = [], [], []
    for cy in range(CH):
        for cx in range(CW):
            if (cx, cy) in cv.text:
                code, _ = cv.text[(cx, cy)]
                grid.append(code); cgrid.append(ROOM_TEXT_COL[idx]); ogrid.append(0)
                continue
            rows = []
            for y in range(8):
                b = 0
                for x in range(4):
                    b = (b << 2) | cv.p[cy * 8 + y][cx * 4 + x]
                rows.append(b)
            col = cv.col[cy][cx]
            if all(r == 0 for r in rows):
                grid.append(32); cgrid.append(ROOM_TEXT_COL[idx]); ogrid.append(0)
                continue
            uses_c = any(((r >> s) & 3) == 3 for r in rows for s in (0, 2, 4, 6))
            key = (tuple(rows), col if uses_c else -1)
            if key not in tiles:
                if nxt > 255:
                    raise ValueError("room %s needs more than %d tiles" % (ROOM_NAMES[idx], 256 - FIRST_TILE))
                tiles[key] = nxt
                tile_bytes[nxt] = rows
                colour_of[nxt] = (col if uses_c else 0) | 8
                nxt += 1
            code = tiles[key]
            grid.append(code); cgrid.append(colour_of[code] & 7); ogrid.append(1)
    return tile_bytes, colour_of, grid, cgrid, ogrid, nxt - FIRST_TILE


if __name__ == "__main__":
    for i in range(len(ROOM_BUILDERS)):
        print(ROOM_NAMES[i], build_room(i)[5])
