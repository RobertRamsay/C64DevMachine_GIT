"""POLARITY title screen: 160x200 multicolour bitmap (Koala layout)."""
import math, random
import font, sprites

PAL = [0x000000,0xFFFFFF,0x68372B,0x70A4B2,0x6F3D86,0x588D43,0x352879,0xB8C76F,
       0x6F4F25,0x433900,0x9A6759,0x444444,0x6C6C6C,0x9AD284,0x6C5EB5,0x959595]
BG = 0
W, H = 160, 200


def rgb(c):
    v = PAL[c]
    return ((v >> 16) & 255, (v >> 8) & 255, v & 255)


class Pic:
    def __init__(self):
        self.p = [[BG] * W for _ in range(H)]

    def px(self, x, y, c):
        if 0 <= x < W and 0 <= y < H:
            self.p[y][x] = c

    def rect(self, x0, y0, x1, y1, c):
        for y in range(max(0, y0), min(H - 1, y1) + 1):
            for x in range(max(0, x0), min(W - 1, x1) + 1):
                self.p[y][x] = c

    def text(self, x, y, s, c, sx=1, sy=1, shadow=None):
        for i, ch in enumerate(s):
            rows = font.glyph_bytes(font.screen_code(ch))
            for ry in range(8):
                for rx in range(8):
                    if rows[ry] >> (7 - rx) & 1:
                        for dy in range(sy):
                            for dx in range(sx):
                                X = x + (i * 8 + rx) * sx + dx
                                Y = y + ry * sy + dy
                                if shadow is not None:
                                    self.px(X + 1, Y + 1, shadow)
                                self.px(X, Y, c(Y) if callable(c) else c)


def draw_sprite_mc(pic, rows, x0, y0, dress, scale, mirror=False):
    for r, line in enumerate(rows):
        line = line.ljust(12, '.')
        if mirror:
            line = line[::-1]
        for cidx, ch in enumerate(line):
            if ch == '.':
                continue
            col = {'1': sprites.SKIN, '2': dress, '3': sprites.OUTLINE}[ch]
            pic.rect(x0 + cidx * scale, y0 + r * scale, x0 + cidx * scale + scale - 1, y0 + r * scale + scale - 1, col)


def draw_sprite_hr(pic, rows, x0, y0, col, scale, mirror=False):
    # hires pixels are half a fat pixel wide: scale/2 fat px each
    for r, line in enumerate(rows):
        line = line.ljust(24, '.')
        if mirror:
            line = line[::-1]
        for cidx, ch in enumerate(line):
            if ch != '#':
                continue
            fx = x0 + (cidx * scale) // 2
            pic.rect(fx, y0 + r * scale, fx + scale // 2 - 1, y0 + r * scale + scale - 1, col)


def build_picture():
    random.seed(7)
    pic = Pic()
    # sky band: sunny day (left) / moonlit night (right)
    pic.rect(0, 48, 79, 103, 14)
    pic.rect(80, 48, 159, 103, 6)
    for y in range(48, 104):                       # soft wavy border
        off = int(2 * math.sin(y / 5.0))
        for x in range(76 + off, 84 + off):
            pic.px(x, y, 14 if x < 80 + off else 6)
    # sun + rays
    for y in range(-10, 11):
        for x in range(-6, 7):
            if (x * 2) ** 2 + y * y <= 90:
                pic.px(20 + x, 66 + y, 7)
    for a in range(0, 360, 45):
        for r in range(13, 18):
            pic.px(20 + int(r * math.cos(math.radians(a)) / 2), 66 + int(r * math.sin(math.radians(a))), 7)
    # clouds
    for cx, cy in ((44, 58), (60, 82)):
        for y in range(-4, 5):
            for x in range(-9, 10):
                if (x / 9.0) ** 2 + (y / 4.0) ** 2 <= 1:
                    pic.px(cx + x, cy + y, 1)
    # moon + stars
    for y in range(-10, 11):
        for x in range(-6, 7):
            if (x * 2) ** 2 + y * y <= 90 and not ((x * 2 + 6) ** 2 + (y + 3) ** 2 <= 70):
                pic.px(138 + x, 66 + y, 1)
    for _ in range(26):
        pic.px(random.randint(84, 158), random.randint(50, 101), random.choice((1, 7, 15)))
    # logo
    def grad(y):
        return [7, 7, 10, 10, 14, 14][min(5, max(0, (y - 10) // 4))]
    pic.text(8, 10, "POLARITY", grad, sx=2, sy=3, shadow=4)
    # girls on brick ground
    scale = 4
    gy = 168 - 21 * scale + 4
    draw_sprite_mc(pic, sprites.BODY_A, 6, gy, 2, scale)
    draw_sprite_hr(pic, sprites.SUNNY_HAIR, 6, gy, 7, scale)
    draw_sprite_mc(pic, sprites.BODY_A, 106, gy, 4, scale, mirror=True)
    draw_sprite_hr(pic, sprites.HEX_HAIR, 106, gy, 11, scale, mirror=True)
    # horseshoe magnet between them, + and - poles
    for y in range(110, 152):
        for x in range(62, 98):
            dx, dy = (x - 80) * 2, y - 132
            r = math.hypot(dx, dy)
            if dy <= 0 and 22 <= r <= 38:
                pic.px(x, y, 2 if x < 80 else 6)
            if dy > 0 and (62 <= x <= 69 or 90 <= x <= 97) and y <= 150:
                pic.px(x, y, 2 if x < 80 else 6)
    pic.rect(62, 144, 69, 151, 15); pic.rect(90, 144, 97, 151, 15)
    pic.text(62, 152, "+", 7); pic.text(90, 152, "-", 14)
    for sx, sy in ((74, 150), (80, 156), (86, 150), (78, 162)):
        pic.px(sx, sy, 1); pic.px(sx - 1, sy, 10); pic.px(sx + 1, sy, 10)
    # captions
    pic.text(0, 40, "SUNNY", 7)
    pic.text(120, 40, "HEX", 4)
    # brick ground (platform style)
    for y in range(168, 184):
        for x in range(W):
            yy = (y - 168) % 8
            xx = (x + (4 if (y - 168) // 8 else 0)) % 8
            pic.px(x, y, 0 if (yy == 7 or xx == 7) else (9 if (yy == 0 or xx == 0) else 2))
    pic.text(40, 188, "PRESS FIRE", 1)
    return pic


def to_koala(pic):
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
            chosen = [c for c, _ in sorted(counts.items(), key=lambda kv: -kv[1])][:3]
            while len(chosen) < 3:
                chosen.append(0)
            lut = {BG: 0, chosen[0]: 1, chosen[1]: 2, chosen[2]: 3}
            for y in range(8):
                b = 0
                for x in range(4):
                    c = pic.p[cy * 8 + y][cx * 4 + x]
                    if c not in lut:
                        best = min([BG] + chosen, key=lambda k: dist(k, c))
                        v = 0 if best == BG else chosen.index(best) + 1
                    else:
                        v = lut[c]
                    b = (b << 2) | v
                bitmap[(cy * 40 + cx) * 8 + y] = b
            screen[cy * 40 + cx] = ((chosen[0] & 15) << 4) | (chosen[1] & 15)
            colour[cy * 40 + cx] = chosen[2] & 15
    return bytes([0x00, 0x60]) + bytes(bitmap) + bytes(screen) + bytes(colour) + bytes([BG])


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
    k = to_koala(build_picture())
    render_koala(k, "../title_preview.png")
    print(len(k))
