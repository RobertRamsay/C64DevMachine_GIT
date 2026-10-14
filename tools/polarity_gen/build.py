"""Build POLARITY.json (the Dev Machine project) and a stand-alone test PRG.

    python build.py OUT.json [TEST.prg] [--test-input]

The test PRG replaces each macro node with equivalent stub code (no music)
so the game logic can be run in VICE without the editor. --test-input
reads the joystick from $02A7 instead of $DC00 (poke it from the monitor).
"""
import base64, copy, json, sys
import font, rooms, sprites, title, sound, game
from asm6502 import Assembler

import os
TEMPLATES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "C64DevMachine_win.yyp", "datafiles", "C64DMResources", "TEMPLATES")
GATE = os.path.join(TEMPLATES, "GATE_GAME.json")   # stock instrument set for the music / SFX
GROUP = "POLARITY"

def b64(data):
    return "b64:" + base64.b64encode(bytes(data)).decode()

def byte_string(data):
    return ", ".join("$%02X" % b for b in data)

def asset(name, typ, address, blob, meta):
    return {"name": name, "type": typ, "address": float(address), "blob": b64(blob), "meta": meta,
            "group": GROUP, "linked_assets": [], "file": "", "load_later": False, "d64_filename": "",
            "reu_used": 0.0, "reu_size": 0.0, "reu_filename": ""}

def byte_asset(name, address, data):
    return asset(name, "BYTE_DATA", address, data,
                 {"byte_string": byte_string(data), "is_save_file": False, "save_file_size": 256.0,
                  "tone_sorted": False, "ecm_bg1": 6.0, "ecm_bg2": 14.0})

# ================================================================== assets
def build_assets():
    gate = json.load(open(GATE))
    GA = {a["name"]: a for a in gate["assets"]}
    assets, mem = [], {}           # mem: address -> byte (for the test PRG)
    def place(addr, data):
        for i, b in enumerate(data):
            mem[addr + i] = b

    map_addrs = [game.MAP_BASE + i * 800 for i in range(5)]
    chr_addrs = [game.CHR_BASE + i * 0x800 for i in range(5)]
    tilecol = []
    for i, rname in enumerate(rooms.ROOM_NAMES):
        tb, co, grid, cgrid, ogrid, used = rooms.build_room(i)
        # CHAR_SET: font + UI (0-71) then this room's MC tiles
        cs = []
        for code in range(256):
            if code < rooms.FIRST_TILE:
                cs += font.glyph_bytes(code)
            else:
                cs += tb.get(code, [0] * 8)
        cmeta = copy.deepcopy(GA["GATE_CHARS"]["meta"])
        cmeta.update({"format": "RAW", "char_count": 256.0, "total_size": 2048.0, "mc_mode": 1.0,
                      "mc_fg": 1.0, "mc_bg": 14.0, "mc_col1": 9.0, "mc_col2": 0.0, "bmp_mode": "MC",
                      "tile_types": [0.0] * 256})
        assets.append(asset("CHARS_" + rname, "CHAR_SET", chr_addrs[i], cs, cmeta))
        place(chr_addrs[i], cs)
        # MAP_DATA 40x20, RAW CHARS (char plane only; colours come from TILE_COLOURS)
        mmeta = {k: v for k, v in GA["GATE_LEVELS"]["meta"].items()
                 if k not in ("char_grid", "colour_grid", "override_grid")}
        mmeta.update({"map_w": 40.0, "map_h": 20.0, "grid_w": 40.0, "grid_h": 20.0,
                      "room_w": 40.0, "room_h": 20.0, "room_count": 1.0, "raw_chars": 1.0,
                      "map_mixed": 1.0, "mc_mode": 1.0, "mc_bg": 14.0, "mc_col1": 9.0, "mc_col2": 0.0,
                      "map_mc_bg": 14.0, "map_mc_col1": 9.0, "map_mc_col2": 0.0,
                      "chr_asset": "CHARS_" + rname, "active_char": 72.0, "erase_char": 32.0,
                      "char_grid": [float(c) for c in grid], "colour_grid": [float(c) for c in cgrid],
                      "override_grid": [float(c) for c in ogrid], "scroll_x": 0.0, "scroll_y": 0.0,
                      "room_view": [], "room_objects": [], "obj_regions": [], "tile_colours": []})
        colour_plane = [(c & 7) | (8 if o else 0) for c, o in zip(cgrid, ogrid)]
        blob = list(grid) + colour_plane + list(ogrid)
        assets.append(asset("MAP_" + rname, "MAP_DATA", map_addrs[i], blob, mmeta))
        place(map_addrs[i], grid)
        # colour table: font chars use the room's sign colour
        page = []
        for code in range(256):
            page.append(rooms.ROOM_TEXT_COL[i] if code < rooms.FIRST_TILE else co.get(code, 8))
        tilecol += page
    assets.append(byte_asset("TILE_COLOURS", game.T_TILECOL_ADDR, tilecol))
    place(game.T_TILECOL_ADDR, tilecol)

    tables = game.build_tables(map_addrs, chr_addrs)
    tables["T_TILECOL"] = (game.T_TILECOL_ADDR, tilecol)
    for name, (addr, data) in tables.items():
        if name == "T_TILECOL":
            continue
        assets.append(byte_asset(name[2:], addr, data))
        place(addr, data)
    msgs = []
    for _, text, _c in game.MSGS:
        msgs += game.msg_codes(text)
    assets.append(byte_asset("MESSAGES", game.MSG_BASE, msgs))
    place(game.MSG_BASE, msgs)

    # sprites
    sblob = []
    for _, data, _, _ in sprites.FRAMES:
        sblob += data
    smeta = copy.deepcopy(GA["CURSOR"]["meta"])
    smeta.update({"used_count": float(len(sprites.FRAMES)), "format": "RAW",
                  "sprite_mcs": [float(f[2]) for f in sprites.FRAMES],
                  "sprite_ucs": [float(f[3]) for f in sprites.FRAMES],
                  "bg_col": 14.0, "mc1_col": float(sprites.SKIN), "mc2_col": float(sprites.OUTLINE),
                  "mc_mode": 1.0, "mc_col1": float(sprites.SKIN), "mc_col2": float(sprites.OUTLINE)})
    smeta["compositor"] = {"active_layer": 0.0, "active_frame": 0.0, "active_cell": -1.0, "frames": [{"cells": []}]}
    assets.append(asset("POL_SPRITES", "SPRITE_SET", game.SPR_BASE, sblob, smeta))
    place(game.SPR_BASE, sblob)

    # title bitmap
    koala = title.to_koala(title.build_picture())
    bmeta = copy.deepcopy(GA["FRONT_END"]["meta"])
    bmeta.update({"bmp_mode": "MC", "bg_col": 0, "mc_mode": 1.0})
    assets.append(asset("TITLE_PIC", "BITMAP", game.TITLE_BMP, koala, bmeta))
    place(game.TITLE_BMP, koala[2:8002])
    place(0x6000, koala[8002:9002])
    place(0x63E8, koala[9002:10002])

    # HUDs
    assets.append(hud_top_asset())
    assets.append(hud_bot_asset())

    # sound
    assets.append(asset("POL_MUSIC", "MUSIC_MAKER", 0, [0], sound.music_meta(GA["GATE_MUSIC"]["meta"])))
    assets.append(asset("POL_SFX", "SFX_MAKER", 0, [0], sound.sfx_meta(GA["GATE_SFX"]["meta"])))
    return assets, mem, tables


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
            "char_grid": [float(c) for c in cg], "chr_asset": "CHARS_HOME",
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
    col = [7] * 6 + [1] + [7] * 7 + [1, 1] + [3] * 6 + [1] * 3 + [7] * 5 + [1] + [1] * 5 + [1] + [3] * 3
    col = (col + [1] * 40)[:40]
    fields = [field("NAME", 0, 0, 6, 0), field("POWER", 7, 0, 7, 0), field("PLACE", 16, 0, 6, 0),
              field("MHI", 26, 0, 2, 1), field("MLO", 28, 0, 2, 1), field("HH", 31, 0, 2, 1),
              field("MM", 34, 0, 1, 1), field("DAY", 38, 0, 2, 1)]
    return hud_asset("HUD_TOP", 0, [TOP_ROW], [col], fields)

BOT_ROWS = [
    "||||||||||||||||||||||||||||||||||||||||",
    "FOOD }}}}}}   REST }}}}}}   WASH }}}}}} ",
    "FUN  }}}}}}   CHAT }}}}}}   JOB 1  BAG 1",
    "",
]
def hud_bot_asset():
    div = [4] * 40
    r1 = [3] * 5 + [5] * 6 + [1] * 3 + [3] * 5 + [6 if False else 3] * 0 + [3] * 0
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
              field("JOB", 32, 2, 1, 1), field("BAGS", 39, 2, 1, 1), field("MSG", 0, 3, 40, 0)]
    return hud_asset("HUD_BOT", 21, BOT_ROWS, [div, r1, r2, r3], fields)


# ================================================================== nodes
NEXT_UID = [600000]
def uid():
    NEXT_UID[0] += 1
    return NEXT_UID[0]

HEIGHT = {"ORG": 80, "INIT": 80, "LABEL": 40, "NORMAL": 60, "MACRO_CODE": 100}

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

def joy_code():
    rows = [["macro_joy", 2.0, 248.0]]
    for m, _ in JOY_ROWS_DEFAULT:
        rows.append([float(m), "Unused", 0.0])
    for m, l in ((16, "JoyFire"), (1, "JoyUp"), (2, "JoyDown"), (4, "JoyLeft"), (8, "JoyRight"), (255, "JoyNone")):
        rows.append([float(m), l, 1.0])
    return rows

def print_code(x, y, colour, text, addr, centre=False):
    return [["macro_print", float(x), float(y), float(colour), 0.0, text, float(addr), 2.0 if centre else 0.0,
             0.0, 0.0, "", 0.0, 0.0, 1024.0, 0.0, "", 0.0, "", 0.0, "", 0.0, "", 0.0, ""]]

HELP_LINES = [
    (1, 7, "*  P O L A R I T Y  *", True),
    (3, 1, "TWO SISTERS, ONE LIFE, OPPOSITE POWERS", True),
    (5, 7, "SUNNY: SWEET & SASSY.  POWER: ATTRACT", False),
    (6, 3, "HEX: FEISTY & WITCHY.  POWER: REPEL", False),
    (8, 1, "LEFT/RIGHT  WALK TO THE NEXT PLACE", False),
    (9, 1, "UP          USE THE THING YOU STAND AT", False),
    (10, 1, "DOWN        SWAP SISTERS", False),
    (11, 1, "FIRE        HOLD FOR MAGIC (COSTS REST)", False),
    (13, 5, "KEEP FOOD, REST, WASH, FUN, CHAT UP!", False),
    (14, 7, "SUNNY PULLS IN COINS... AND BEES!", False),
    (15, 3, "HEX BLASTS BEES AWAY... AND COINS!", False),
    (17, 1, "WORK AT THE CAFE 8:00-18:00 FOR $.", False),
    (18, 1, "SUNNY EARNS TIPS. HEX LEARNS 2X FASTER.", False),
    (19, 1, "4 PROMOTIONS AND THE CAFE IS YOURS!", False),
    (22, 7, "PRESS FIRE TO START", True),
]
WIN_LINES = [
    (4, 7, "*  DREAM COME TRUE  *", True),
    (8, 1, "SUNNY AND HEX NOW OWN THE CAFE!", True),
    (10, 3, "ATTRACTION AND REPULSION:", True),
    (11, 3, "TOGETHER, AN UNSTOPPABLE TEAM.", True),
    (14, 1, "IT TOOK THEM    DAYS.", 10),
    (20, 7, "PRESS FIRE", True),
]

def layout():
    """Returns (columns, comments). A column: dict(name, x, org, items).
    Items: ('code', block) | ('label', name) | ('op', mnem, operand)
         | ('macro', TYPE, title, code_rows[, stable_uid])"""
    S = sound.SFX_ID
    sfx = lambda n: ('macro', 'MACRO_SFX', 'SFX ' + n, [["macro_sfx", "POL_SFX", float(S[n]), 3.0, 0.0]])
    text_addr = [game.PRINT_TEXT]
    def pr(lines):
        out = []
        for row, col, text, centre in lines:
            assert len(text) <= 39, text
            x = (40 - len(text)) // 2 if centre is True else (1 if centre is False else centre)
            out.append(('macro', 'MACRO_PRINT', 'PRINT', print_code(x, row, col, text, text_addr[0])))
            text_addr[0] += len(text)
        assert text_addr[0] <= 0x4000, hex(text_addr[0])
        return out
    vic_game = ["macro_vic", "MCT", 0.0, 1024.0, 12288.0, 0.0, 14.0, 9.0, 0.0, 0.0]
    vic_text = ["macro_vic", "MCT", 0.0, 1024.0, 12288.0, 0.0, 0.0, 9.0, 0.0, 0.0]
    F = lambda n: float(sprites.INDEX[n])
    cols = [
        dict(name="01 BOOT", x=360, org=None, items=[('code', 'BOOT')]),
        dict(name="02 TITLE + HOW TO PLAY", x=680, org=0x0900, items=[
            ('label', 'Title'),
            ('macro', 'MACRO_BMP', 'TITLE PICTURE', [["macro_bmp", "TITLE_PIC", 16384.0, 1.0, 0.0]]),
            ('macro', 'MACRO_SID_SONG', 'POLARITY THEME', [["macro_sid_song", "POL_MUSIC", 1.0, 3.0, 2.0, 0.0, 0.0]], game.UID_SONG),
            ('macro', 'MACRO_SFX', 'SFX INIT', [["macro_sfx", "POL_SFX", 0.0, 3.0, 3.0]]),
            ('code', 'TITLE_IRQ'),
            ('label', 'TitlePic'),
            ('macro', 'MACRO_BMP', 'TITLE PICTURE', [["macro_bmp", "TITLE_PIC", 16384.0, 1.0, 0.0]]),
            ('code', 'TITLE_HOLD'),
            ('label', 'ShowHelp'),
            ('code', 'HELP_PREP'),
            ('macro', 'MACRO_VIC', 'TEXT SCREEN', [vic_text]),
            ('macro', 'MACRO_CLR_SCREEN', 'CLEAR SCREEN', [["macro_clr_screen", 1024.0, 32.0]]),
        ] + pr(HELP_LINES) + [('op', 'rts', 0.0)]),
        dict(name="03 FRAME SYNC / IRQ / SOUNDS", x=1000, org=0x2600, items=[
            ('label', 'FrameTick'),
            ('macro', 'MACRO_VWAIT', 'FRAME SYNC', [["macro_vwait", 248.0, 0.0, ""]]),
            ('op', 'rts', 0.0),
            ('label', 'IrqMusic'),
            ('code', 'FRAME_IRQ'),
            ('macro', 'MACRO_SFX', 'SFX UPDATE', [["macro_sfx", "POL_SFX", 0.0, 3.0, 1.0]]),
            ('code', 'FRAME_IRQ_END'),
        ] + sum([[('label', 'Snd' + lbl), sfx(n), ('op', 'rts', 0.0)] for lbl, n in
                 (("Coin", "COIN"), ("Use", "USE"), ("Magic", "MAGIC"), ("Swap", "SWAP"), ("Ouch", "OUCH"),
                  ("Promote", "PROMOTE"), ("Error", "ERROR"), ("Sleep", "SLEEP"))], [])),
        dict(name="04 NEW LIFE: SCREEN, SPRITES, HUD", x=1320, org=0x6800, items=[
            ('label', 'StartGame'),
            ('macro', 'MACRO_VIC', 'GAME SCREEN (MC TEXT)', [vic_game]),
            ('macro', 'MACRO_CLR_SCREEN', 'CLEAR SCREEN', [["macro_clr_screen", 1024.0, 32.0]]),
            ('macro', 'MACRO_SPR', 'HAIR (SPRITE 0)', [["macro_spr", "POL_SPRITES", 0.0, 104.0, float(game.FLOOR_Y), F("SUNNY_R"), 1.0]]),
            ('macro', 'MACRO_SPR', 'BODY (SPRITE 1)', [["macro_spr", "POL_SPRITES", 1.0, 104.0, float(game.FLOOR_Y), F("BODY_R_A"), 1.0]]),
            ('macro', 'MACRO_SPR', 'MAGIC (SPRITE 2)', [["macro_spr", "POL_SPRITES", 2.0, 124.0, float(game.FLOOR_Y), F("HEARTS_A"), 1.0]]),
            ('macro', 'MACRO_SPR', 'COIN (SPRITE 3)', [["macro_spr", "POL_SPRITES", 3.0, 150.0, float(game.COIN_Y), F("COIN_A"), 1.0]]),
            ('macro', 'MACRO_SPR', 'BEE (SPRITE 4)', [["macro_spr", "POL_SPRITES", 4.0, 200.0, float(game.BEE_Y), F("BEE_A"), 1.0]]),
            ('macro', 'MACRO_HUD', 'STATUS ROW', [["macro_hud", "HUD_TOP", 1024.0, 55296.0, 1.0, 1.0]], game.UID_HUD_TOP),
            ('macro', 'MACRO_HUD', 'NEEDS PANEL', [["macro_hud", "HUD_BOT", 1024.0, 55296.0, 1.0, 1.0]], game.UID_HUD_BOT),
            ('code', 'NEW_GAME'),
        ]),
        dict(name="05 ROOMS", x=1640, org=0x6E00, items=[('code', 'ROOM')]),
        dict(name="06 MAIN LOOP + JOYSTICK", x=1960, org=0x7000, items=[
            ('label', 'MainLoop'),
            ('op', 'jsr', 'FrameTick'),
            ('code', 'MAIN_PRE'),
            ('macro', 'MACRO_JOY', 'JOYSTICK', joy_code()),
            ('code', 'MAIN_UPDATE'),
            ('op', 'jmp_abs', 'MainLoop'),
            ('code', 'JOY'),
        ]),
        dict(name="07 SISTERS, MAGIC, COIN, BEE", x=2280, org=0x7200, items=[('code', 'SPRITES'), ('code', 'THINGS')]),
        dict(name="08 CLOCK, NEEDS, ACTIONS", x=2600, org=0x7600, items=[('code', 'CLOCK'), ('code', 'ACTIONS')]),
        dict(name="09 MONEY, MESSAGES, HUD", x=2920, org=0x7A00, items=[('code', 'HUD')]),
        dict(name="10 DREAM COME TRUE", x=3240, org=0x7C00, items=[
            ('label', 'WinGame'),
            ('code', 'WIN_PREP'),
            ('macro', 'MACRO_VIC', 'TEXT SCREEN', [vic_text]),
            ('macro', 'MACRO_CLR_SCREEN', 'CLEAR SCREEN', [["macro_clr_screen", 1024.0, 32.0]]),
        ] + pr(WIN_LINES) + [('code', 'WIN_END')]),
    ]
    comments = {
        "01 BOOT": "POLARITY - a sisterly life sim.\nBOOT: BASIC off, CIA IRQs off,\nthen the title.",
        "02 TITLE + HOW TO PLAY": "Title picture + theme tune.\nAlternates with HOW TO PLAY.\nFIRE starts a new life.",
        "03 FRAME SYNC / IRQ / SOUNDS": "FrameTick: frame wait.\nIrqMusic: raster IRQ chain\n(tune, SFX, sky/HUD split).",
        "04 NEW LIFE: SCREEN, SPRITES, HUD": "MC text screen, 5 sprites,\nstatus row + needs panel HUDs.\nReset the sisters' life.",
        "05 ROOMS": "Each place: own CHAR_SET +\nMAP (40x20) + colour table.\nHOME STREET SHOP CAFE PARK",
        "06 MAIN LOOP + JOYSTICK": "Once per frame: sync, joystick\n(walk/use/swap/magic), update.",
        "07 SISTERS, MAGIC, COIN, BEE": "Sunny ATTRACTS, Hex REPELS:\ncoins float out of reach,\nbees chase and sting.",
        "08 CLOCK, NEEDS, ACTIONS": "2 s = 10 minutes. Needs drop\nhourly. UP uses an object:\nACTION table drives it.",
        "09 MONEY, MESSAGES, HUD": "Money in base-100 bytes.\nMessage line + HUD field\nroutines from the HUD nodes.",
        "10 DREAM COME TRUE": "Job level 5: the sisters\nown the cafe. FIRE: title.",
    }
    return cols, comments


def build_nodes(tables):
    cols, comments = layout()
    nodes, orgs, boxes = [], [], []
    org_uid = 1
    for ci, c in enumerate(cols):
        x = c["x"]
        y = 340
        comment = node("COMMENT", "COMMENT", [["Comment", comments[c["name"]]]], x, 160)
        nodes.append(comment)
        parent = None
        if c["org"] is None:
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
        return "vwa%d:\nLDA $D012\nCMP #248\nBEQ vwa%d\nvwb%d:\nLDA $D012\nCMP #248\nBNE vwb%d\n" % (u, u, u, u)
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
        s += "LDA #$%02X\nSTA $%04X\nLDA #$%02X\nSTA $D025\nLDA #$%02X\nSTA $D026\n" % (f[3], 0xD027 + slot, sprites.SKIN, sprites.OUTLINE)
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
    if typ == 'MACRO_PRINT':
        x, y, colr, text = int(r[1]), int(r[2]), int(r[3]), r[5]
        codes = [font.screen_code(c) for c in text]
        k = "pr%d_" % u
        return ("JMP %ss\n%sd:\n.byte %s\n%ss:\nLDX #$00\n%sl:\nLDA %sd,X\nSTA $%04X,X\nLDA #$%02X\nSTA $%04X,X\nINX\nCPX #%d\nBNE %sl\n"
                % (k, k, ",".join(str(c) for c in codes), k, k, k, 0x0400 + y * 40 + x, colr, 0xD800 + y * 40 + x, len(codes), k))
    raise ValueError(typ)


def build_test_prg(tables, mem, path, test_input):
    cols, _ = layout()
    a = Assembler()
    sizes = {}
    for c in cols:
        org = 0x080E if c["org"] is None else c["org"]
        a.pc = org
        start = org
        if c["org"] is None:
            a.add_block("SEI\nLDA #$00\nSTA $D020\nSTA $D021\n" + ("LDA #$FF\nSTA $02A7\n" if test_input else ""), where="INIT")
        for it in c["items"]:
            if it[0] == 'code':
                text = game.resolve(game.BLOCKS[it[1]], tables)
                if test_input:
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
        sizes[c["name"]] = (start, a.pc)
    for name, (s, e) in sizes.items():
        print("  %-38s $%04X-$%04X (%d bytes)" % (name, s, e - 1, e - s))
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


def main():
    out = sys.argv[1]
    assets, mem, tables = build_assets()
    nodes, boxes = build_nodes(tables)
    proj = {
        "ignored_conflicts": [], "asset_groups": [GROUP],
        "next_stable_uid": float(NEXT_UID[0] + 10), "map_tile_bank_sel": -1.0, "map_tile_bank": [],
        "code_editor_font_index": 1.0, "creator_locked": False, "build_target": 0.0,
        "kernal_unlocked": False, "basic_unlocked": True, "asset_sort_mode": "ADDR",
        "nodes": nodes, "boxes": boxes, "assets": assets, "map_global_mixed": 1.0,
    }
    with open(out, "w") as f:
        json.dump(proj, f, separators=(",", ":"))
    print("wrote", out, "nodes", len(nodes), "assets", len(assets))
    if len(sys.argv) > 2:
        build_test_prg(tables, mem, sys.argv[2], "--test-input" in sys.argv)
        print("wrote", sys.argv[2])

if __name__ == "__main__":
    main()
