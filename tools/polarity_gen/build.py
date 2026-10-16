"""Build POLARITY.json (the Dev Machine project) and a stand-alone test PRG.

    python build.py OUT.json [TEST.prg] [--test-input] [--script=FILE]

The test PRG replaces each macro node with equivalent stub code (no music)
so the game logic can be run in VICE without the editor. It covers all
64K (maps and sprites live under the I/O area and the KERNAL), so crunch
it with Exomizer (sfx sys) before running it, as the PRG EXO build does.
--test-input reads the joystick from $02A7 instead of $DC00 (poke it from
the monitor); --script=FILE plays a joystick script instead: lines of
"frames value" (value = the $DC00 byte, e.g. 127 = nothing, 119 = right;
0 = freeze the game there, for screenshots). --room=N starts in room N,
--clues=MASK with those clues.
"""
import base64, copy, json, sys
import font, rooms, sprites, title, sound, game
from asm6502 import Assembler

import os
TEMPLATES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "C64DevMachine_win.yyp", "datafiles", "C64DMResources", "TEMPLATES")
GATE = os.path.join(TEMPLATES, "GATE_GAME.json")   # stock instrument set for the music / SFX
# Asset panel groups: every asset goes in one (build_assets checks).
ASSET_GROUPS = [
    ("TITLE SCREEN", ["TITLE_PIC"]),
    ("SPRITES", ["POL_SPRITES", "SPR_LIB"]),
    ("ROOM CHARSETS", ["CHARS_*", "TILE_COLOURS"]),
    ("ROOM MAPS", ["MAP_*"]),
    ("HUD", ["HUD_TOP", "HUD_BOT"]),
    ("MUSIC + SFX", ["POL_MUSIC", "POL_SFX"]),
    ("TEXT + MESSAGES", ["MESSAGES", "MESSAGES2", "MSGLO", "MSGHI", "MSGCOL"]),
    ("PAGES: HELP + ENDINGS", ["HELP_TEXT", "ENDING_TEXT", "TRUTH_TEXT", "PGL*", "PGTLO", "PGTHI",
                               "PGLLO", "PGLHI", "ROWLO", "ROWHI"]),
    ("TABLES: ROOMS", ["SKY", "SPAWN", "MAPLO", "MAPHI", "GROUP", "GCHRHI", "GD022", "OBJ", "ROOMOFS",
                       "HINT", "PLACES"]),
    ("TABLES: SISTERS", ["DRESS", "HAIR", "NAMECOL", "NAMES", "POWERS", "MAGCOL", "JUMP", "SFRM", "SFOFS"]),
    ("TABLES: ACTIONS + POSES", ["ACT", "ACTOFS", "PID", "PPX", "PFACE", "PY", "SWX", "SWY", "SLX", "SLY"]),
    ("TABLES: NEEDS + JOB", ["DECAY", "WARN", "WAGE", "PROMO"]),
    ("TABLES: PEOPLE + CLUES", ["NFRM", "NCOL", "NMSG", "RNPC", "RNPCX", "CLROOM", "CLTYPE", "CLX", "CLY",
                                "CLCOL", "CLMSG", "CLHINT", "BIT"]),
]

def group_of(name):
    import fnmatch
    hits = [g for g, pats in ASSET_GROUPS if any(fnmatch.fnmatchcase(name, p) for p in pats)]
    assert len(hits) == 1, ("asset needs exactly one group", name, hits)
    return hits[0]

def b64(data):
    return "b64:" + base64.b64encode(bytes(data)).decode()

def byte_string(data):
    return ", ".join("$%02X" % b for b in data)

def asset(name, typ, address, blob, meta):
    return {"name": name, "type": typ, "address": float(address), "blob": b64(blob), "meta": meta,
            "group": group_of(name), "linked_assets": [], "file": "", "load_later": False, "d64_filename": "",
            "reu_used": 0.0, "reu_size": 0.0, "reu_filename": ""}

def byte_asset(name, address, data):
    return asset(name, "BYTE_DATA", address, data,
                 {"byte_string": byte_string(data), "is_save_file": False, "save_file_size": 256.0,
                  "tone_sorted": False, "ecm_bg1": 6.0, "ecm_bg2": 14.0})


# ================================================================== pages
# (row, colour, text, x): x True = centred, a number = that column.
HELP_LINES = [
    (1, 7, "*  P O L A R I T Y  *", True),
    (3, 1, "TWO SISTERS, ONE LIFE, OPPOSITE POWERS", True),
    (5, 7, "SUNNY: SWEET & SASSY.  POWER: ATTRACT", True),
    (6, 4, "HEX: FEISTY & WITCHY.  POWER: REPEL", True),
    (8, 3, "LEFT/RIGHT  WALK        UP  JUMP", 3),
    (9, 3, "FIRE  USE OR TALK  (HOLD FOR MAGIC)", 3),
    (10, 3, "FIRE+DOWN  SWAP SISTERS", 3),
    (12, 1, "KEEP FOOD, REST, WASH, FUN, CHAT UP!", True),
    (13, 1, "MO'S COFFEE PERKS YOU UP. WORK FOR $.", True),
    (15, 5, "ARE WE REALLY SISTERS? FIND 6 CLUES.", True),
    (16, 1, "JUMP UP HIGH, ASK PEOPLE, USE MAGIC:", True),
    (17, 1, "SUNNY PULLS THINGS IN, HEX BLASTS!", True),
    (19, 1, "OR WORK HARD AND OWN THE CAFE.", True),
    (22, 7, "PRESS FIRE TO START", True),
]
WIN_LINES = [
    (4, 7, "*  DREAM COME TRUE  *", True),
    (8, 1, "SUNNY AND HEX NOW OWN THE CAFE!", True),
    (10, 3, "ATTRACTION AND REPULSION:", True),
    (11, 3, "TOGETHER, AN UNSTOPPABLE TEAM.", True),
    (13, 5, "BUT ARE THEY REALLY SISTERS...?", True),
    (game.DAYS_ROW, 1, "IT TOOK THEM    DAYS.", 10),
    (21, 7, "PRESS FIRE", True),
]
TRUTH_LINES = [
    (2, 7, "*  THE TRUTH  *", True),
    (5, 1, "A PHOTO. A TIN. A DIARY. A LOCKET.", True),
    (6, 1, "TWO HOSPITAL TAGS. AN OLD NEWSPAPER:", True),
    (8, 7, "TWINS BORN DURING THE GREAT ECLIPSE!", True),
    (10, 3, "SUNNY CAME FIRST, AS THE SUN WENT OUT.", True),
    (11, 4, "HEX CAME SECOND, IN THE DARK.", True),
    (13, 1, "OPPOSITES... AND REAL SISTERS.", True),
    (14, 5, "TWINS, IN FACT. ALWAYS TOGETHER.", True),
    (game.DAYS_ROW, 1, "IT TOOK THEM    DAYS.", 10),
    (21, 7, "PRESS FIRE", True),
]
# Each page is a TEXT_DATA asset (its lines back to back) + a line table
# (row, column, colour, length) that PrintPage walks.
TEXT_PAGES = [("HELP_TEXT", HELP_LINES), ("ENDING_TEXT", WIN_LINES), ("TRUTH_TEXT", TRUTH_LINES)]

def page_layout(text_base):
    """-> [(asset name, address, text, [(row, col, colour, len)])]"""
    out, addr = [], text_base
    for name, lines in TEXT_PAGES:
        text, table = "", []
        for row, colour, t, x in lines:
            assert len(t) <= 40, t
            col = (40 - len(t)) // 2 if x is True else x
            table.append((row, col, colour, len(t)))
            text += t
        out.append((name, addr, text, table))
        addr += len(text) + 1                      # + the null the flush appends
    return out, addr


# ================================================================== assets
def build_assets():
    gate = json.load(open(GATE))
    GA = {a["name"]: a for a in gate["assets"]}
    assets, mem = [], {}           # mem: address -> byte (for the test PRG)
    def place(addr, data):
        for i, b in enumerate(data):
            mem[addr + i] = b

    nrooms, ngroups = len(rooms.ROOM_NAMES), len(rooms.GROUP_NAMES)
    map_addrs = [game.MAP_BASE + i * 800 for i in range(nrooms)]
    chr_addrs = [game.CHR_BASE + g * 0x800 for g in range(ngroups)]
    assert chr_addrs[-1] + 0x800 <= game.T_TILECOL_ADDR
    tilecol = []
    for g, gname in enumerate(rooms.GROUP_NAMES):
        tb, co, maps, used = rooms.build_group(g)
        # CHAR_SET: the font + UI glyphs, with this group's MC tiles in the
        # slots no text uses (rooms.TILE_CODES)
        cs = []
        for code in range(256):
            cs += tb[code] if code in tb else font.glyph_bytes(code)
        d022 = float(rooms.GROUP_D022[g])
        cmeta = copy.deepcopy(GA["GATE_CHARS"]["meta"])
        cmeta.update({"format": "RAW", "char_count": 256.0, "total_size": 2048.0, "mc_mode": 1.0,
                      "mc_fg": 1.0, "mc_bg": 14.0, "mc_col1": d022, "mc_col2": 0.0, "bmp_mode": "MC",
                      "tile_types": [0.0] * 256})
        assets.append(asset("CHARS_" + gname, "CHAR_SET", chr_addrs[g], cs, cmeta))
        place(chr_addrs[g], cs)
        for i, (grid, cgrid, ogrid) in maps.items():
            rname = rooms.ROOM_NAMES[i]
            # MAP_DATA 40x20, RAW CHARS (char plane only; colours come from TILE_COLOURS)
            mmeta = {k: v for k, v in GA["GATE_LEVELS"]["meta"].items()
                     if k not in ("char_grid", "colour_grid", "override_grid")}
            mmeta.update({"map_w": 40.0, "map_h": 20.0, "grid_w": 40.0, "grid_h": 20.0,
                          "room_w": 40.0, "room_h": 20.0, "room_count": 1.0, "raw_chars": 1.0,
                          "map_mixed": 1.0, "mc_mode": 1.0, "mc_bg": 14.0, "mc_col1": d022, "mc_col2": 0.0,
                          "map_mc_bg": 14.0, "map_mc_col1": d022, "map_mc_col2": 0.0,
                          "chr_asset": "CHARS_" + gname, "active_char": 72.0, "erase_char": 32.0,
                          "char_grid": [float(c) for c in grid], "colour_grid": [float(c) for c in cgrid],
                          "override_grid": [float(c) for c in ogrid], "scroll_x": 0.0, "scroll_y": 0.0,
                          "room_view": [], "room_objects": [], "obj_regions": [], "tile_colours": []})
            colour_plane = [(c & 7) | (8 if o else 0) for c, o in zip(cgrid, ogrid)]
            blob = list(grid) + colour_plane + list(ogrid)
            assets.append(asset("MAP_" + rname, "MAP_DATA", map_addrs[i], blob, mmeta))
            place(map_addrs[i], grid)
        # colour table: font chars use the group's sign colour
        tilecol += [co[c] if c in co else rooms.GROUP_TEXT_COL[g] for c in range(256)]
    assets.append(byte_asset("TILE_COLOURS", game.T_TILECOL_ADDR, tilecol))
    place(game.T_TILECOL_ADDR, tilecol)

    # tables, messages, then the page texts after them
    pages0, _ = page_layout(0)
    probe = game.build_tables(map_addrs, chr_addrs, [(0, p[3]) for p in pages0])
    text_base = max(a + len(d) for n, (a, d) in probe.items() if n != "MESSAGES")
    pages, text_end = page_layout(text_base)
    assert text_end <= 0xC000, hex(text_end)
    tables = game.build_tables(map_addrs, chr_addrs, [(p[1], p[3]) for p in pages])

    # no text may use a glyph slot that room tiles can take
    reclaimed = set(rooms.TILE_CODES) - set(range(rooms.FIRST_TILE, 256))
    texts = [m[1] for m in game.MSGS] + [p[2] for p in pages] + [TOP_ROW] + BOT_ROWS \
        + game.NAMES + game.POWERS + game.PLACES
    for t in texts:
        bad = [c for c in t if c not in "{}|" and font.screen_code(c) in reclaimed]
        assert not bad, ("text uses a reclaimed glyph", t, bad)

    for name, (addr, data) in tables.items():
        if name.startswith("MESSAGES"):
            assets.append(byte_asset(name, addr, data))
        else:
            assets.append(byte_asset(name[2:], addr, data))
        place(addr, data)

    # sprites: the bank 0 set (6 buffers + statics) and the library under the KERNAL
    sblob = []
    for _, data, _, _ in sprites.FRAMES:
        sblob += data
    smeta = copy.deepcopy(GA["CURSOR"]["meta"])
    smeta.update({"used_count": float(len(sprites.FRAMES)), "format": "RAW",
                  "sprite_mcs": [float(f[2]) for f in sprites.FRAMES],
                  "sprite_ucs": [float(f[3]) for f in sprites.FRAMES],
                  "bg_col": 14.0, "mc1_col": float(sprites.SKIN), "mc2_col": float(sprites.HAIR[0]),
                  "mc_mode": 1.0, "mc_col1": float(sprites.SKIN), "mc_col2": float(sprites.HAIR[0])})
    # compositor: the six buffers as they stand at the start (sister, Mo),
    # then the two-frame effects in sequence
    seq = [("BUFFERS", [figure(0, 1, 2), figure(3, 4, 5)])]
    I = sprites.INDEX
    for fx in ("COIN", "BEE", "HEARTS", "ZAP", "STAR"):
        seq.append((fx, [[cell(0, I[fx + "_A"])], [cell(0, I[fx + "_B"])]]))
    seq.append(("ZZZ + BUBBLES", [[cell(0, I["ZZZ"])], [cell(0, I["BUBBLES"])]]))
    seq.append(("CLUES", [[cell(0, I["CLUE_" + n])] for n in sprites.CLUE_NAMES]))
    smeta["compositor"], smeta["anim"], SPR_SEQS["POL_SPRITES"] = compositor(seq, "COIN", 6)
    assets.append(asset("POL_SPRITES", "SPRITE_SET", game.SPR_BASE, sblob, smeta))
    place(game.SPR_BASE, sblob)

    # the library: a SPRITE_SET too, so every frame shows in the sprite editor.
    # Overlays are hires black; bodies are multicolour in the dress / NPC
    # colour. $D026 (hair) is one colour per set: Sunny's, so Hex's hair shows
    # yellow here (the game switches $D026 when the sisters swap).
    look = {}
    for form, poses in enumerate(sprites.SISTER_FRAMES):
        for top, bot, body in poses:
            look.setdefault(top, (0, 0)); look.setdefault(bot, (0, 0))
            look.setdefault(body, (1, sprites.DRESS[form]))
    for n, (top, bot, body) in enumerate(sprites.NPC_FRAMES):
        look.setdefault(top, (0, 0)); look.setdefault(bot, (0, 0))
        look.setdefault(body, (1, sprites.NPC_COL[n]))
    assert sorted(look) == list(range(len(sprites.LIB))), "a library block nobody uses"
    assert len(sprites.LIB) <= 64
    lib = [b for blk in sprites.LIB for b in blk]
    lmeta = copy.deepcopy(smeta)
    lmeta.update({"used_count": float(len(sprites.LIB)),
                  "sprite_mcs": [float(look[i][0]) for i in range(len(sprites.LIB))],
                  "sprite_ucs": [float(look[i][1]) for i in range(len(sprites.LIB))]})
    # compositor: each figure is its body (Y-expanded) under the two
    # overlays; the game's animations follow one another (SPR_SEQS lists
    # where each starts), the playback range set to Sunny's walk
    seq = []
    P = {p: i for i, p in enumerate(sprites.POSES)}
    for name, poses in zip([n.strip() for n in game.NAMES], sprites.SISTER_FRAMES):
        f = lambda pose, yo=0: figure(*poses[P[pose]], yo=yo)
        seq += [
            (name + " WALK", [f("WALK", 2), f("STEP")]),       # the stride sits 2 lines lower
            (name + " JUMP", [f("STEP")] + [f("JUMP", -game.JUMP[i]) for i in range(0, len(game.JUMP), 3)]
                              + [f("STEP")]),
            (name + " MAGIC", [f("STAND"), f("CAST")]),
            (name + " CHEER", [f("CHEER"), f("CHEER", -2)]),
            (name + " EAT", [f("EAT"), f("STAND")]),
            (name + " SIT + SWING", [f("SIT_A"), f("SIT_B")]),
            (name + " PHONE", [f("PHONE")]),
            (name + " SLEEP", [f("LIE")]),
        ]
    for name, fr in zip(sprites.NPC_NAMES, sprites.NPC_FRAMES):
        seq.append((name + " TALK", [figure(*fr), figure(*fr, yo=-1)]))   # they bob as they talk
    lmeta["compositor"], lmeta["anim"], SPR_SEQS["SPR_LIB"] = compositor(seq, game.NAMES[0].strip() + " WALK", 6)
    assets.append(asset("SPR_LIB", "SPRITE_SET", game.SPR_LIB, lib, lmeta))
    place(game.SPR_LIB, lib)

    # title bitmap
    koala = title.to_koala(title.build_picture())
    bmeta = copy.deepcopy(GA["FRONT_END"]["meta"])
    bmeta.update({"bmp_mode": "MC", "bg_col": 0, "mc_mode": 1.0})
    assets.append(asset("TITLE_PIC", "BITMAP", game.TITLE_BMP, koala, bmeta))
    place(game.TITLE_BMP, koala[2:8002])
    place(0x6000, koala[8002:9002])
    place(0x63E8, koala[9002:10002])

    # page text (TEXT_DATA, read by PrintPage)
    for name, addr, text, _ in pages:
        codes = [font.screen_code(c) for c in text] + [0]
        assets.append(asset(name, "TEXT_DATA", addr, codes, {"text": text}))
        place(addr, codes)

    # HUDs
    assets.append(hud_top_asset())
    assets.append(hud_bot_asset())

    # sound
    assets.append(asset("POL_MUSIC", "MUSIC_MAKER", 0, [0], sound.music_meta(GA["GATE_MUSIC"]["meta"])))
    assets.append(asset("POL_SFX", "SFX_MAKER", 0, [0], sound.sfx_meta(GA["GATE_SFX"]["meta"])))
    return assets, mem, tables


SPR_SEQS = {}          # sprite set -> [(animation, first frame, last frame)]

def cell(layer, slot, yo=0, expand="none", row=1):
    """A compositor placement in column 1 of the editor's 4x4 grid."""
    return {"layer": float(layer), "row": float(row), "col": 1.0, "slot": float(slot),
            "xo": 0.0, "yo": float(yo), "expand": expand}

def figure(top, bot, body, yo=0):
    """A character: the body Y-expanded at the back, the two hires overlays
    over it (the bottom one 21 lines down), all raised / lowered by yo.
    Anchored on grid row 2, so a jump (yo up to -40) stays on the grid."""
    return [cell(0, body, yo, "y", 2), cell(1, top, yo, row=2), cell(2, bot, yo + 21, row=2)]

def compositor(seq, play, fps):
    """Sprite editor compositor + animation state from [(name, [frame cells])]:
    the animations one after another; the playback range is animation
    `play`. Returns (compositor, anim, [(name, first, last)])."""
    frames, spans = [], []
    for name, cells in seq:
        spans.append((name, len(frames), len(frames) + len(cells) - 1))
        frames += [{"cells": c} for c in cells]
    _, start, end = [sp for sp in spans if sp[0] == play][0]
    comp = {"active_layer": 0.0, "active_frame": float(start), "active_cell": -1.0, "frames": frames}
    anim = {"playing": False, "direction": "fwd", "speed": float(fps), "start": float(start), "ender": float(end)}
    return comp, anim, spans


def hud_asset(name, y, rows, colours, fields):
    w, h = 40, len(rows)
    cg, kg = [], []
    for r, line in enumerate(rows):
        codes = [font.screen_code(c) if c not in "{}|" else {"{": font.BAR_EMPTY, "}": font.BAR_FULL,
                 "|": font.DIVIDER}[c] for c in line.ljust(40)]
        cg += codes
        kg += colours[r]
    meta = {"hud_x": 0.0, "hud_y": float(y), "hud_w": float(w), "hud_h": float(h),
            "fields": fields, "sel_field": -1.0, "hud_mc_mode": 0.0, "hud_mc_bg": 0.0,
            "hud_mc_col1": 9.0, "hud_mc_col2": 0.0, "show_grid": True, "cur_x": 0.0, "cur_y": 0.0,
            "char_grid": [float(c) for c in cg], "chr_asset": "CHARS_HOUSE",
            "colour_grid": [float(c) for c in kg], "zoom": 2.0, "active_char": 32.0,
            "active_colour": 1.0, "paint_mc": 0.0}
    a = asset(name, "HUD", 0, cg + kg, meta)
    return a

def field(name, fx, fy, flen, kind):
    f = {"name": name, "fx": float(fx), "fy": float(fy), "flen": float(flen), "kind": float(kind),
         "base": 48.0, "pad": 0.0, "full": float(font.BAR_FULL), "empty": float(font.BAR_EMPTY)}
    return f

TOP_ROW = "SUNNY  ATTRACT  HOME     $0020 08:00 D01"
def hud_top_asset():
    col = [7] * 6 + [1] + [7] * 7 + [1, 1] + [3] * 7 + [1] * 2 + [7] * 5 + [1] + [1] * 5 + [1] + [3] * 3
    col = (col + [1] * 40)[:40]
    fields = [field("NAME", 0, 0, 6, 0), field("POWER", 7, 0, 7, 0), field("PLACE", 16, 0, 7, 0),
              field("MHI", 26, 0, 2, 1), field("MLO", 28, 0, 2, 1), field("HH", 31, 0, 2, 1),
              field("MM", 34, 0, 1, 1), field("DAY", 38, 0, 2, 1)]
    return hud_asset("HUD_TOP", 0, [TOP_ROW], [col], fields)

BOT_ROWS = [
    "|" * 15 + " CLUES 0/6 " + "|" * 14,
    "FOOD }}}}}}   REST }}}}}}   WASH }}}}}} ",
    "FUN  }}}}}}   CHAT }}}}}}   JOB 1  BAG 1",
    "",
]
assert len(BOT_ROWS[0]) == 40
def hud_bot_asset():
    div = [4] * 15 + [7] * 11 + [4] * 14
    def bar_row(lbl_cols):
        c = [1] * 40
        for (x0, x1, colr) in lbl_cols:
            for x in range(x0, x1 + 1):
                c[x] = colr
        return c
    r1 = bar_row([(0, 3, 3), (5, 10, 5), (14, 17, 3), (19, 24, 7), (28, 31, 3), (33, 38, 3)])
    r2 = bar_row([(0, 3, 3), (5, 10, 2), (14, 17, 3), (19, 24, 4), (28, 30, 3), (32, 32, 7), (35, 37, 3), (39, 39, 7)])
    r3 = [1] * 40
    fields = [field("FOOD", 5, 1, 6, 2), field("REST", 19, 1, 6, 2), field("WASH", 33, 1, 6, 2),
              field("FUN", 5, 2, 6, 2), field("CHAT", 19, 2, 6, 2),
              field("JOB", 32, 2, 1, 1), field("BAGS", 39, 2, 1, 1), field("CLUE", 22, 0, 1, 1),
              field("MSG", 0, 3, 40, 0)]
    return hud_asset("HUD_BOT", 21, BOT_ROWS, [div, r1, r2, r3], fields)


# ================================================================== nodes
NEXT_UID = [600000]
def uid():
    NEXT_UID[0] += 1
    return NEXT_UID[0]

# Node heights as the editor lays them out (read back from a live load), so
# the column boxes fit their nodes.
HEIGHT = {"ORG": 80, "INIT": 80, "LABEL": 40, "NORMAL": 60, "MACRO_CODE": 100,
          "MACRO_PRINT": 180, "MACRO_HUD": 200, "MACRO_SID_SONG": 140, "MACRO_VIC": 120,
          "MACRO_JOY": 120, "MACRO_VWAIT": 60}

def node(typ, title, code, x, y, parent=None, stable=None, custom=""):
    n = {"binary_blob": "", "x": float(x), "y": float(y), "type": typ, "params": [],
         "custom_title": custom, "stable_uid": float(stable or uid()),
         "wire_in_source": -1.0, "wire_out_target": -1.0, "org_uid": -1.0,
         "show_only_used": False, "code_descriptor": "", "scroll_alias": "", "anim_alias": "",
         "helper_text": "", "comment_h": 0.0, "comment_w": 0.0, "comment_w_mult": 1.0, "x_indent": 0.0,
         "proxy": False, "collapsed": False, "end_address": 0.0, "pc_address": 0.0,
         "height": float(HEIGHT.get(typ, 100)), "title": title, "connected": typ != "COMMENT",
         "org_parent_x": -1.0, "org_parent_y": -1.0, "has_org_parent": False, "code": code}
    if parent is not None:
        n["has_org_parent"] = True
        n["org_parent_x"], n["org_parent_y"] = float(parent[0]), float(parent[1])
    return n

JOY_ROWS_DEFAULT = [(0x19, "URF"), (0x15, "ULF"), (0x1A, "DRF"), (0x16, "DLF"), (0x09, "UPR"), (0x05, "UPL"),
                    (0x0A, "DNR"), (0x06, "DNL"), (0x11, "UPF"), (0x12, "DNF"), (0x14, "LFF"), (0x18, "RTF")]
JOY_USED = {0x09: "JoyUpRight", 0x05: "JoyUpLeft",     # diagonal jumps
            0x12: "JoySwap"}                          # FIRE + DOWN swaps the sisters

def joy_code():
    rows = [["macro_joy", 2.0, 248.0]]
    for m, _ in JOY_ROWS_DEFAULT:
        rows.append([float(m), JOY_USED[m], 1.0] if m in JOY_USED else [float(m), "Unused", 0.0])
    for m, l in ((16, "JoyFire"), (1, "JoyUp"), (4, "JoyLeft"), (8, "JoyRight"), (255, "JoyNone")):
        rows.append([float(m), l, 1.0])
    return rows

SFX_LABELS = (("Coin", "COIN"), ("Use", "USE"), ("Magic", "MAGIC"), ("Swap", "SWAP"), ("Ouch", "OUCH"),
              ("Promote", "PROMOTE"), ("Error", "ERROR"), ("Sleep", "SLEEP"), ("Jump", "JUMP"), ("Clue", "CLUE"))

# Where each column's code goes. The 64K map: $0801 boot, $0900 title +
# tune, $20C0 pages, $2600 IRQ + sounds, $3000 charset, $3800 sprites,
# $4000 title picture, $6800-$7FFF the game, $8000 charsets / tables /
# messages, $C000 variables, $D000 maps + sprite library (under ROM).
ORGS = {
    "02 TITLE + THEME TUNE": 0x0900,
    "11 HOW TO PLAY + PAGES": 0x20C0,
    "03 FRAME SYNC / IRQ / SOUNDS": 0x2600,
    "04 NEW LIFE: SCREEN, SPRITES, HUD": 0x6800,
    "12 ENDINGS": 0x2200,
}

def layout():
    """Returns (columns, comments). A column: dict(name, x, org, items).
    Items: ('code', block) | ('label', name) | ('op', mnem, operand)
         | ('macro', TYPE, title, code_rows[, stable_uid])"""
    S = sound.SFX_ID
    sfx = lambda n: ('macro', 'MACRO_SFX', 'SFX ' + n, [["macro_sfx", "POL_SFX", float(S[n]), 3.0, 0.0]])
    vic_game = ["macro_vic", "MCT", 0.0, 1024.0, 12288.0, 0.0, 14.0, float(rooms.GROUP_D022[0]), 0.0, 0.0]
    vic_text = ["macro_vic", "MCT", 0.0, 1024.0, 12288.0, 0.0, 0.0, 9.0, 0.0, 0.0]
    F = lambda n: float(sprites.INDEX[n])
    spr = lambda title_, slot, n, y: ('macro', 'MACRO_SPR', title_, [["macro_spr", "POL_SPRITES", float(slot), 104.0, float(y), F(n), 1.0]])
    cols = [
        dict(name="01 BOOT", x=360, org=None, items=[('code', 'BOOT')]),
        dict(name="02 TITLE + THEME TUNE", x=680, items=[
            ('label', 'Title'),
            ('macro', 'MACRO_BMP', 'TITLE PICTURE', [["macro_bmp", "TITLE_PIC", 16384.0, 1.0, 0.0]]),
            # SFX INIT first: it writes $D418 = $0F (filter mode off). The song's
            # init then sets $D418 = $1F, so the low-pass filter on the bass
            # voice stays on. The other way round, the bass voice is silent.
            ('macro', 'MACRO_SFX', 'SFX INIT', [["macro_sfx", "POL_SFX", 0.0, 3.0, 3.0]]),
            ('macro', 'MACRO_SID_SONG', 'POLARITY THEME', [["macro_sid_song", "POL_MUSIC", 1.0, 3.0, 2.0, 0.0, 0.0]], game.UID_SONG),
            ('code', 'TITLE_IRQ'),
            ('label', 'TitlePic'),
            ('macro', 'MACRO_BMP', 'TITLE PICTURE', [["macro_bmp", "TITLE_PIC", 16384.0, 1.0, 0.0]]),
            ('code', 'TITLE_HOLD'),
        ]),
        dict(name="03 FRAME SYNC / IRQ / SOUNDS", x=1000, items=[
            ('label', 'FrameTick'),
            ('macro', 'MACRO_VWAIT', 'FRAME SYNC', [["macro_vwait", 248.0, 0.0, ""]]),
            ('op', 'rts', 0.0),
            ('label', 'IrqMusic'),
            ('code', 'FRAME_IRQ'),
            ('macro', 'MACRO_SFX', 'SFX UPDATE', [["macro_sfx", "POL_SFX", 0.0, 3.0, 1.0]]),
            ('code', 'FRAME_IRQ_END'),
        ] + sum([[('label', 'Snd' + lbl), sfx(n), ('op', 'rts', 0.0)] for lbl, n in SFX_LABELS], [])),
        dict(name="04 NEW LIFE: SCREEN, SPRITES, HUD", x=1320, items=[
            ('label', 'StartGame'),
            ('macro', 'MACRO_VIC', 'GAME SCREEN (MC TEXT)', [vic_game]),
            ('macro', 'MACRO_CLR_SCREEN', 'CLEAR SCREEN', [["macro_clr_screen", 1024.0, 32.0]]),
            spr('SISTER TOP (SPRITE 0)', 0, "BUF_TOP", game.FLOOR_Y),
            spr('SISTER LEGS (SPRITE 1)', 1, "BUF_BOT", game.FLOOR_Y + 21),
            spr('SISTER BODY (SPRITE 2)', 2, "BUF_BODY", game.FLOOR_Y),
            spr('MAGIC (SPRITE 3)', 3, "HEARTS_A", game.FLOOR_Y),
            spr('COIN / CLUE (SPRITE 4)', 4, "COIN_A", game.COIN_Y),
            spr('BEE (SPRITE 5)', 5, "BEE_A", game.BEE_Y),
            ('macro', 'MACRO_HUD', 'STATUS ROW', [["macro_hud", "HUD_TOP", 1024.0, 55296.0, 1.0, 1.0]], game.UID_HUD_TOP),
            ('macro', 'MACRO_HUD', 'NEEDS PANEL', [["macro_hud", "HUD_BOT", 1024.0, 55296.0, 1.0, 1.0]], game.UID_HUD_BOT),
            ('code', 'NEW_GAME'),
        ]),
        dict(name="05 ROOMS", x=1640, items=[('code', 'ROOM')]),
        dict(name="06 MAIN LOOP + JOYSTICK", x=1960, items=[
            ('label', 'MainLoop'),
            ('op', 'jsr', 'FrameTick'),
            ('code', 'MAIN_PRE'),
            ('macro', 'MACRO_JOY', 'JOYSTICK', joy_code()),
            ('code', 'MAIN_UPDATE'),
            ('op', 'jmp_abs', 'MainLoop'),
            ('code', 'JOY'),
        ]),
        dict(name="07 THE SISTERS + MAGIC", x=2280, items=[('code', 'SPRITES')]),
        dict(name="08 COINS, CLUES, PEOPLE, BEES", x=2600, items=[('code', 'THINGS')]),
        dict(name="09 CLOCK, NEEDS, ACTIONS", x=2920, items=[('code', 'CLOCK'), ('code', 'ACTIONS')]),
        dict(name="10 MONEY, MESSAGES, HUD", x=3240, items=[('code', 'HUD')]),
        dict(name="12 ENDINGS", x=3880, items=[
            ('label', 'WinGame'),
            ('code', 'WIN_PREP'),
            ('macro', 'MACRO_VIC', 'TEXT SCREEN', [vic_text]),
            ('macro', 'MACRO_CLR_SCREEN', 'CLEAR SCREEN', [["macro_clr_screen", 1024.0, 32.0]]),
            ('code', 'WIN_DRAW'),
            ('label', 'ShowTruth'),
            ('code', 'WIN_PREP'),
            ('macro', 'MACRO_VIC', 'TEXT SCREEN', [vic_text]),
            ('macro', 'MACRO_CLR_SCREEN', 'CLEAR SCREEN', [["macro_clr_screen", 1024.0, 32.0]]),
            ('code', 'TRUTH_DRAW'),
            ('code', 'WIN_END'),
        ]),
        # HOW TO PLAY and PrintPage live in the gap after the title column
        dict(name="11 HOW TO PLAY + PAGES", x=3560, items=[
            ('label', 'ShowHelp'),
            ('code', 'HELP_PREP'),
            ('macro', 'MACRO_VIC', 'TEXT SCREEN', [vic_text]),
            ('macro', 'MACRO_CLR_SCREEN', 'CLEAR SCREEN', [["macro_clr_screen", 1024.0, 32.0]]),
            ('code', 'HELP_DRAW'),
            ('code', 'PAGES'),
        ]),
    ]
    for c in cols:
        if "org" not in c:
            c["org"] = ORGS.get(c["name"])
    comments = {
        "01 BOOT": "POLARITY - a sisterly life sim.\nBOOT: BASIC off, CIA IRQs off,\nmirror tables, then the title.",
        "02 TITLE + THEME TUNE": "Title picture + theme tune.\nAlternates with HOW TO PLAY.\nFIRE starts a new life.",
        "03 FRAME SYNC / IRQ / SOUNDS": "FrameTick: frame wait.\nIrqMusic: raster IRQ chain\n(tune, SFX, sky/HUD split).",
        "04 NEW LIFE: SCREEN, SPRITES, HUD": "MC text screen, 6 sprites,\nstatus row + needs panel HUDs.\nReset the sisters' life.",
        "05 ROOMS": "11 places: 5 CHAR_SETs, MAPs\nunder the I/O + KERNAL, the\nperson and clue in each.",
        "06 MAIN LOOP + JOYSTICK": "Once per frame: sync, joystick\n(walk/jump/use/swap/magic).",
        "07 THE SISTERS + MAGIC": "3 sprites a sister: 2x high\nMC body + 2 hires overlays,\ncopied from SPR_LIB, mirrored.",
        "08 COINS, CLUES, PEOPLE, BEES": "Sunny ATTRACTS, Hex REPELS.\n6 clues: jump, pull, blast,\nor ask Gran / Miss Page.",
        "09 CLOCK, NEEDS, ACTIONS": "3 s = 10 minutes. Needs drop\nhourly. FIRE uses an object:\nACTION table drives it.",
        "10 MONEY, MESSAGES, HUD": "Money in base-100 bytes.\nMessage line + HUD field\nroutines from the HUD nodes.",
        "11 HOW TO PLAY + PAGES": "HOW TO PLAY page, and\nPrintPage: one loop prints\nevery page from its table.",
        "12 ENDINGS": "Job level 5: own the cafe.\nAll 6 clues: THE TRUTH.\nFIRE: back to the title.",
    }
    return cols, comments


def place_columns(cols, sizes):
    """Fill in the ORG of every column without a fixed one: the game columns
    pack one after another from $6800 (after column 04), leaving headroom
    for macro nodes whose editor size differs from the test stubs."""
    fixed_end = {}
    pc = None
    for c in cols:
        if c["name"] == "04 NEW LIFE: SCREEN, SPRITES, HUD":
            pc = c["org"] + sizes[c["name"]] + 160      # the HUD / SPR macros run larger in the editor
        elif c["org"] is None and c["name"] != "01 BOOT":
            c["org"] = (pc + 15) & ~15
            pc = c["org"] + sizes[c["name"]] + 8
    return cols


def build_nodes(tables, cols, comments):
    nodes, orgs, boxes = [], [], []
    org_uid = 1
    for ci, c in enumerate(cols):
        x = c["x"]
        y = 340
        comment = node("COMMENT", "COMMENT", [["Comment", comments[c["name"]]]], x, 160)
        nodes.append(comment)
        parent = None
        if c["name"] == "01 BOOT":
            init = node("INIT", "SYSTEM INIT", [["sei", 0.0], ["lda_imm", 0.0], ["sta_abs", 53280.0], ["sta_abs", 53281.0]], x, y)
            nodes.append(init)
            y += 80
        else:
            o = node("ORG", "ORG BLOCK", [["org", 0.0]], x, y)
            o["pc_address"] = float(c["org"])
            o["org_uid"] = float(org_uid)
            org_uid += 1
            o["connected"] = False
            orgs.append(o)
            parent = (x, y)
            y += 80
        for it in c["items"]:
            if it[0] == 'code':
                text = game.resolve(game.BLOCKS[it[1]], tables)
                n = node("MACRO_CODE", "CODE BLOCK", [["code_block", text]], x, y, parent)
                n["custom_title"] = it[1].replace("_", " ")
            elif it[0] == 'label':
                n = node("LABEL", "ADDRESS LABEL", [["label", it[1]]], x, y, parent)
            elif it[0] == 'op':
                n = node("NORMAL", "Opcode", [[it[1], it[2]]], x, y, parent)
            else:
                _, typ, ttl, code = it[:4]
                n = node(typ, ttl, code, x, y, parent, stable=it[4] if len(it) > 4 else None)
            nodes.append(n)
            y += int(n["height"])
        boxes.append({"x": float(x - 20), "y": 120.0, "panel_links": [], "is_panel": False,
                      "box_col_idx": float(ci % 8), "box_name": c["name"],
                      "box_h": float(y - 120 + 40), "box_w": 280.0})
    return orgs + nodes, boxes


# ================================================================== test PRG
def stub(item, test_input):
    """Assembly that stands in for a macro node in the test PRG."""
    _, typ, ttl, code = item[:4]
    r = code[0]
    u = item[4] if len(item) > 4 else id(item)
    if typ == 'MACRO_BMP':
        s = "LDA $DD00\nAND #$FC\nORA #$02\nSTA $DD00\nLDA #$80\nSTA $D018\nLDA #$3B\nSTA $D011\nLDA #$18\nSTA $D016\nLDA #$00\nSTA $D020\nSTA $D021\nLDX #$00\n"
        s += "bm%d:\n" % u
        for o in (0, 250, 500, 750):
            s += "LDA $%04X,X\nSTA $%04X,X\n" % (0x63E8 + o, 0xD800 + o)
        s += "INX\nCPX #250\nBNE bm%d\nCLI\n" % u
        return s
    if typ == 'MACRO_SID_SONG':
        k = "sng%d_" % u
        return "JMP %srt\n%sinit:\n%splay:\n%sseek:\nRTS\n%srt:\n" % (k, k, k, k, k)
    if typ in ('MACRO_SFX',):
        return ""
    if typ == 'MACRO_VWAIT':
        s = "vwa%d:\nLDA $D012\nCMP #248\nBEQ vwa%d\nvwb%d:\nLDA $D012\nCMP #248\nBNE vwb%d\n" % (u, u, u, u)
        if SCRIPT:
            s += "INC $02\nBNE vwc%d\nINC $03\nvwc%d:\n" % (u, u)        # frame counter for the script
        return s
    if typ == 'MACRO_VIC':
        _, mode, bank, scr, chr_, brd, b0, b1, b2, b3 = r
        return ("SEI\nLDA $DD00\nORA #$03\nSTA $DD00\nLDA #$1C\nSTA $D018\nLDA #$1B\nSTA $D011\nLDA #$18\nSTA $D016\n"
                "LDA #$%02X\nSTA $D020\nLDA #$%02X\nSTA $D021\nLDA #$%02X\nSTA $D022\nLDA #$%02X\nSTA $D023\nCLI\n"
                % (int(brd), int(b0), int(b1), int(b2)))
    if typ == 'MACRO_CLR_SCREEN':
        return ("LDA #$20\nLDX #$00\ncl%d:\nSTA $0400,X\nSTA $0500,X\nSTA $0600,X\nSTA $06E8,X\nINX\nBNE cl%d\n" % (u, u))
    if typ == 'MACRO_SPR':
        _, nm, slot, x, y, frame, _g = r
        slot, x, y, frame = int(slot), int(x), int(y), int(frame)
        f = sprites.FRAMES[frame]
        bit = 1 << slot
        s = "LDA #$%02X\nSTA $%04X\nLDA #$%02X\nSTA $%04X\nLDA #$%02X\nSTA $%04X\n" % (
            (game.SPR_BASE // 64 + frame) & 255, 0x07F8 + slot, x & 255, 0xD000 + slot * 2, y, 0xD001 + slot * 2)
        s += "LDA $D010\n" + ("ORA #$%02X\n" % bit if x > 255 else "AND #$%02X\n" % (255 - bit)) + "STA $D010\n"
        s += "LDA $D015\nORA #$%02X\nSTA $D015\n" % bit
        s += "LDA $D01C\n" + ("ORA #$%02X\n" % bit if f[2] else "AND #$%02X\n" % (255 - bit)) + "STA $D01C\n"
        s += "LDA #$%02X\nSTA $%04X\nLDA #$%02X\nSTA $D025\nLDA #$%02X\nSTA $D026\n" % (f[3], 0xD027 + slot, sprites.SKIN, sprites.HAIR[0])
        return s
    if typ == 'MACRO_HUD':
        a = hud_top_asset() if r[1] == "HUD_TOP" else hud_bot_asset()
        m = a["meta"]
        k = "hud%d_" % u
        hy, hh = int(m["hud_y"]), int(m["hud_h"])
        s = "JMP %sdskip\n%sdata:\n" % (k, k)
        cg = [int(c) for c in m["char_grid"]]
        kg = [int(c) for c in m["colour_grid"]]
        for i in range(0, len(cg), 20):
            s += ".byte " + ",".join("$%02X" % c for c in cg[i:i + 20]) + "\n"
        s += "%scol:\n" % k
        for i in range(0, len(kg), 20):
            s += ".byte " + ",".join("$%02X" % c for c in kg[i:i + 20]) + "\n"
        s += "%sdskip:\nJMP %srtskip\n%sdraw:\nLDX #$00\n%sl:\n" % (k, k, k, k)
        s += "LDA %sdata,X\nSTA $%04X,X\nLDA %scol,X\nSTA $%04X,X\nINX\nCPX #%d\nBNE %sl\nRTS\n" % (
            k, 0x0400 + hy * 40, k, 0xD800 + hy * 40, hh * 40, k)
        for f in m["fields"]:
            fa = 0x0400 + (hy + int(f["fy"])) * 40 + int(f["fx"])
            fl, n = int(f["flen"]), k + f["name"]
            if f["kind"] == 1:
                s += "%s:\nLDX #$FF\nSEC\n%s_h:\nINX\nSBC #100\nBCS %s_h\nADC #100\n" % (n, n, n)
                s += "LDX #$FF\nSEC\n%s_t:\nINX\nSBC #10\nBCS %s_t\nADC #10\n" % (n, n)
                if fl >= 2:
                    s += "PHA\nTXA\nCLC\nADC #48\nSTA $%04X\nPLA\n" % (fa + fl - 2)
                s += "CLC\nADC #48\nSTA $%04X\nRTS\n" % (fa + fl - 1)
            elif f["kind"] == 2:
                s += ("%s:\nTAX\nLDY #$00\n%s_l:\nCPY #%d\nBEQ %s_e\nLDA #%d\nCPX #$00\nBEQ %s_p\nLDA #%d\nDEX\n"
                      "%s_p:\nSTA $%04X,Y\nINY\nJMP %s_l\n%s_e:\nRTS\n") % (n, n, fl, n, int(f["empty"]), n, int(f["full"]), n, fa, n, n)
        s += "%srtskip:\n" % k
        if r[4]:
            s += "JSR %sdraw\n" % k
        return s
    if typ == 'MACRO_JOY':
        if SCRIPT:
            s = "JSR TestJoy\nSTA $F8\n"
        else:
            src = "$02A7" if test_input else "$DC00"
            s = "jrd:\nLDA %s\nSTA $F8\n" % src
        i = 0
        for row in code[1:]:
            m, lbl, en = int(row[0]), row[1], row[2]
            if not en:
                continue
            if m == 255:
                s += "JSR %s\n" % lbl
                continue
            s += "LDA $F8\nAND #$%02X\nBNE js%d\nJSR %s\nJMP joy_done\njs%d:\n" % (m, i, lbl, i)
            i += 1
        s += "joy_done:\n"
        return s
    raise ValueError(typ)


SCRIPT = []           # [(frame, $DC00 value)] for --script test runs
TEST_ROOM = None      # --room=N: a new life starts in room N (test PRG only)
TEST_CLUES = 0        # --clues=MASK: ...holding these clues (bit n = clue n)

def test_joy_code():
    """TestJoy: A = the scripted joystick for the frame counter at $02/$03."""
    s = "TestJoy:\nSTX $04\nLDX #$00\ntjl:\nLDA tjt_hi,X\nCMP $03\nBCC tjn\nBNE tjv\nLDA tjt_lo,X\nCMP $02\nBCC tjn\nBEQ tjn\ntjv:\nLDA tjt_v,X\nBEQ tjv\nLDX $04\nRTS\ntjn:\nINX\nCPX #%d\nBNE tjl\nLDA #$7F\nLDX $04\nRTS\n" % len(SCRIPT)
    s += "tjt_lo:\n.byte " + ",".join("$%02X" % (f & 255) for f, _ in SCRIPT) + "\n"
    s += "tjt_hi:\n.byte " + ",".join("$%02X" % (f >> 8) for f, _ in SCRIPT) + "\n"
    s += "tjt_v:\n.byte " + ",".join("$%02X" % v for _, v in SCRIPT) + "\n"
    return s


def assemble(tables, cols, test_input=False):
    """Assemble every column (macros as stubs) -> (assembler, sizes)."""
    a = Assembler()
    sizes = {}
    for c in cols:
        org = 0x080E if c["name"] == "01 BOOT" else c["org"]
        a.pc = org
        start = org
        if c["name"] == "01 BOOT":
            a.add_block("SEI\nLDA #$00\nSTA $D020\nSTA $D021\n" + ("LDA #$FF\nSTA $02A7\n" if test_input else "")
                        + ("LDA #$00\nSTA $02\nSTA $03\n" if SCRIPT else ""), where="INIT")
        for it in c["items"]:
            if it[0] == 'code':
                src = game.BLOCKS[it[1]]
                if TEST_CLUES and it[1] == "NEW_GAME":
                    src = src.replace("STA V_ITEM\n", "STA V_ITEM\nLDA #$%02X\nSTA V_CLUES\nLDA #%d\nSTA V_NCLUE\nLDA #$00\n"
                                      % (TEST_CLUES, bin(TEST_CLUES).count("1")), 1)
                if TEST_ROOM is not None and it[1] == "NEW_GAME":
                    src = src.replace("LDA #C_HOME            ; a new life starts at HOME", "LDA #%d" % TEST_ROOM)
                text = game.resolve(src, tables)
                if SCRIPT:
                    text = text.replace("LDA $DC00", "JSR TestJoy")
                elif test_input:
                    text = text.replace("LDA $DC00", "LDA $02A7")
                a.add_block(text, where=it[1])
            elif it[0] == 'label':
                a.add_block(it[1] + ":", where="label")
            elif it[0] == 'op':
                mn, opd = it[1], it[2]
                mn = mn.replace("_abs", "").upper()
                a.add_block("%s %s" % (mn, "" if opd == 0.0 else opd), where="op")
            else:
                a.add_block(stub(it, test_input), where=it[2])
        if c["name"] == "11 HOW TO PLAY + PAGES" and SCRIPT:
            a.add_block(test_joy_code(), where="testjoy")
        sizes[c["name"]] = a.pc - start
    return a, sizes


def build_test_prg(tables, mem, cols, path, test_input):
    a, sizes = assemble(tables, cols, test_input)
    for c in cols:
        org = 0x080E if c["name"] == "01 BOOT" else c["org"]
        print("  %-38s $%04X-$%04X (%d bytes)" % (c["name"], org, org + sizes[c["name"]] - 1, sizes[c["name"]]))
    code = a.link()
    allm = dict(mem)
    for k, v in code.items():
        if k in allm:
            raise SystemExit("code overlaps data at $%04X" % k)
        allm[k] = v
    top = max(allm)
    prg = bytearray([0x01, 0x08])
    stubb = [0x0B, 0x08, 0x0A, 0x00, 0x9E, 0x32, 0x30, 0x36, 0x32, 0x00, 0x00, 0x00, 0x00]
    img = bytearray(top + 1 - 0x0801)
    img[0:13] = bytes(stubb)
    for k, v in allm.items():
        if k >= 0x0801:
            img[k - 0x0801] = v
    open(path, "wb").write(prg + img)
    return sizes, a.labels


def check_layout(cols, sizes):
    """No column may run into the next one or into data."""
    spans = sorted((0x080E if c["name"] == "01 BOOT" else c["org"], sizes[c["name"]], c["name"]) for c in cols)
    for (s0, n0, a), (s1, _, b) in zip(spans, spans[1:]):
        assert s0 + n0 <= s1, "%s ($%04X-$%04X) runs into %s ($%04X)" % (a, s0, s0 + n0, b, s1)
    limits = {"02 TITLE + THEME TUNE": 0x20C0, "11 HOW TO PLAY + PAGES": 0x2200, "12 ENDINGS": 0x2600,
              "03 FRAME SYNC / IRQ / SOUNDS": 0x3000}   # the SFX data runs to ~$2DF4 in the editor
    for s, n, name in spans:
        if name in limits:
            assert s + n <= limits[name], "%s ends at $%04X" % (name, s + n)
        elif s >= 0x6800:
            assert s + n <= 0x8000, "%s ends at $%04X (the game must stay below $8000)" % (name, s + n)


def main():
    out = sys.argv[1]
    global TEST_ROOM, TEST_CLUES
    for arg in sys.argv[2:]:
        if arg.startswith("--clues="):
            TEST_CLUES = int(arg.split("=", 1)[1], 0)
        if arg.startswith("--room="):
            TEST_ROOM = int(arg.split("=", 1)[1])
        if arg.startswith("--script="):
            for line in open(arg.split("=", 1)[1]):
                parts = line.split("#")[0].split()
                if len(parts) == 2:
                    SCRIPT.append((int(parts[0]), int(parts[1])))
    assets, mem, tables = build_assets()
    cols, comments = layout()
    # first pass with temporary ORGs to measure the columns, then pack them
    for c in cols:
        if c["org"] is None and c["name"] != "01 BOOT":
            c["org"] = 0x6800
    _, sizes = assemble(tables, cols)
    for c in cols:
        if c["name"] not in ORGS and c["name"] != "01 BOOT":
            c["org"] = None
    place_columns(cols, sizes)
    _, sizes = assemble(tables, cols)
    check_layout(cols, sizes)
    nodes, boxes = build_nodes(tables, cols, comments)
    proj = {
        "ignored_conflicts": [], "asset_groups": [g for g, _ in ASSET_GROUPS],
        "next_stable_uid": float(NEXT_UID[0] + 10), "map_tile_bank_sel": -1.0, "map_tile_bank": [],
        "code_editor_font_index": 1.0, "creator_locked": False, "build_target": 2.0,
        "kernal_unlocked": False, "basic_unlocked": True, "asset_sort_mode": "ADDR",
        "nodes": nodes, "boxes": boxes, "assets": assets, "map_global_mixed": 1.0,
    }
    with open(out, "w") as f:
        json.dump(proj, f, separators=(",", ":"))
    print("wrote", out, "nodes", len(nodes), "assets", len(assets))
    if len(sys.argv) > 2 and not sys.argv[2].startswith("--"):
        build_test_prg(tables, mem, cols, sys.argv[2], "--test-input" in sys.argv)
        print("wrote", sys.argv[2])

if __name__ == "__main__":
    main()
