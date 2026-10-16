"""POLARITY game data + 6502 code blocks.

Code is written with symbolic names (V_ variables, T_ tables, C_ constants)
which resolve() turns into plain hex, so the project JSON holds ordinary
assembly in the same style as the other bundled templates."""
import math, re
import font, rooms, sprites

# ------------------------------------------------------------------ memory map
# The project builds as PRG EXO: the crunched file unpacks into all 64K, so
# the maps and the sprite library can live under the I/O area and the
# KERNAL ROM. The code banks them in ($01) only while it copies from them.
SCREEN, COLRAM = 0x0400, 0xD800
CHR_ACTIVE = 0x3000                 # VIC charset (copied in per room)
SPR_BASE = 0x3800                   # SPRITE_SET (pointer $E0): 6 buffers + statics
TITLE_BMP = 0x4000                  # BITMAP ($4000 bmp, $6000 screen, $63E8 colour)
CHR_BASE = 0x8000                   # 5 x CHAR_SET (2K each, one per room group) $8000-$A7FF
T_TILECOL_ADDR = 0xA800             # 5 x 256 colour tables $A800-$ACFF
SMALL_TABLES = 0xAD00               # small BYTE_DATA tables, then MESSAGES2, up to $BFFF
VARS = 0xC000
COLPAGE = 0xC100                    # active charset's colour table (copied in)
FLIP_HR, FLIP_MC = 0xC200, 0xC300   # mirror tables (built at boot)
MSG_BASE = 0xC400                   # MESSAGES (variable length, 0-terminated) up to $CFFF
MAP_BASE = 0xD000                   # 11 x MAP_DATA 40x20 (800 bytes each), under I/O + KERNAL
SPR_LIB = 0xF280                    # sprite library blocks (64 bytes each), under the KERNAL
NUM_ROOMS = len(rooms.ROOM_NAMES)
assert MAP_BASE + NUM_ROOMS * 800 <= SPR_LIB
assert SPR_LIB + len(sprites.LIB) * 64 <= 0xFFFA, hex(SPR_LIB + len(sprites.LIB) * 64)

FLOOR_Y = 58 + rooms.FEET - 42     # sprite Y for the sisters standing (42 lines tall)
COIN_Y = 96
BEE_Y = 150
FRAMES_PER_10MIN = 150
JUMP = [0] + [round(40 * 4 * (t / 30.0) * (1 - t / 30.0)) for t in range(1, 30)]   # height per frame
REACH = 30                          # jump height that grabs a clue up high

V = {}
def _vars():
    names = """ROOM PX FACE FORM MOVING JOYID PREVJOY MHI MLO BAGS DAY HOUR MIN TICK
               NEED NEED1 NEED2 NEED3 NEED4 JOBLV JOBXP COIN COINX COINY BEE BEEX BEEY
               CASTING RNG OBJ MUSIC T0 T1 T2 DRAIN SWAPT STING FRAME SKYCOL SPLIT
               COINCD ZZZ HARD SPRX SPRHI T3 T4
               POSE POSET POSEY POSEPX SLEEPING GROUP GB GH GX GY MY
               JUMP GKEY GP T5 T6 NPC NPCX NPCT ITEM ITX ITY ITST CLUES NCLUE
               TALK TALK1 TALK2 TALK3""".split()
    for i, n in enumerate(names):
        V["V_" + n] = VARS + i
_vars()

ZP = {"Z_SCR": 0x50, "Z_COL": 0x52, "Z_SRC": 0x54, "Z_MSG": 0x56}

# ------------------------------------------------------------------ actions
NEEDS = ["FOOD", "REST", "WASH", "FUN", "CHAT"]
DECAY = [3, 2, 2, 3, 2]
SP_NONE, SP_SLEEP, SP_EAT, SP_GROCERY, SP_WORK, SP_TALK = range(6)
NPC_ID = {n: i for i, n in enumerate(sprites.NPC_NAMES)}
#           deltas (FOOD REST WASH FUN CHAT)  $   10min  special   (npc for SP_TALK)
ACTIONS = [
 ("SLEEP",    [0, 0, 0, 0, 0],        0,  0, SP_SLEEP),
 ("TV",       [-2, -2, 0, 16, 0],     0,  6, SP_NONE),
 ("EAT",      [24, 0, 0, 2, 0],       0,  3, SP_EAT),
 ("SHOWER",   [0, 0, 48, 2, 0],       0,  2, SP_NONE),
 ("BENCH",    [0, 6, 0, 2, 0],        0,  3, SP_NONE),
 ("PHONE",    [0, 0, 0, 2, 16],       1,  3, SP_NONE),
 ("GROCERY",  [0, 0, 0, 0, 0],        10, 2, SP_GROCERY),
 ("SWEETS",   [8, 0, 0, 8, 0],        3,  1, SP_NONE),
 ("OUTFIT",   [0, 0, 0, 30, 8],       30, 3, SP_NONE),
 ("WORK",     [-6, -8, -6, -6, 6],    0,  12, SP_WORK),
 ("COFFEE",   [10, 16, 0, 0, 4],      2,  1, SP_TALK, "MO"),
 ("SWING",    [-2, -4, -2, 16, 0],    0,  6, SP_NONE),
 ("SPLASH",   [0, 0, 12, 6, 0],       0,  2, SP_NONE),
 ("CHAT",     [0, 0, 0, 4, 20],       0,  6, SP_TALK, "PIP"),
 ("COMPUTER", [0, -2, 0, 14, 10],     0,  6, SP_NONE),
 ("SLIDE",    [0, -3, -2, 12, 0],     0,  2, SP_NONE),
 ("DUCKS",    [0, 0, 0, 10, 4],       1,  3, SP_NONE),
 ("GRAN",     [8, 0, 0, 2, 16],       0,  3, SP_TALK, "GRAN"),
 ("ARMCHAIR", [0, 10, 0, 0, 0],       0,  3, SP_NONE),
 ("FLOWERS",  [0, -2, -2, 12, 0],     0,  2, SP_NONE),
 ("FORAGE",   [10, -2, -2, 2, 0],     0,  2, SP_NONE),
 ("READ",     [0, 2, 0, 14, 2],       0,  4, SP_NONE),
 ("PAGE",     [0, 0, 0, 2, 12],       0,  2, SP_TALK, "PAGE"),
]

# Poses: what she does while an action runs (input waits until it ends).
P_NONE, P_SIT, P_SWING, P_SLIDE, P_LIE, P_PHONE, P_EAT, P_CHEER, P_SHOWER, P_WORK, P_CAST = range(11)
G = {n: i for i, n in enumerate(sprites.POSES)}       # sprite poses (library frames)
def seat_y(canvas_y):                    # sprite Y that puts her lap on a seat
    return 58 + canvas_y - 34
FY = FLOOR_Y
#           pose      PX   face  Y
POSES = {
 "SLEEP":    (P_LIE,    20, 0, 143),
 "TV":       (P_SIT,    21, 0, seat_y(112)),
 "EAT":      (P_EAT,    82, 0, FY),
 "SHOWER":   (P_SHOWER, 118, 0, FY),
 "BENCH":    (P_SIT,    64, 0, seat_y(116)),
 "PHONE":    (P_PHONE,  94, 0, FY),
 "GROCERY":  (P_CHEER,  16, 0, FY),
 "SWEETS":   (P_EAT,    54, 0, FY),
 "OUTFIT":   (P_CHEER,  92, 0, FY),
 "WORK":     (P_WORK,    6, 0, FY),
 "COFFEE":   (P_EAT,    40, 0, FY),
 "SWING":    (P_SWING,  19, 0, seat_y(112)),
 "SPLASH":   (P_CHEER,  86, 0, FY),
 "CHAT":     (P_SIT,   106, 0, seat_y(116)),
 "COMPUTER": (P_SIT,    72, 0, seat_y(116)),
 "SLIDE":    (P_SLIDE,  58, 0, seat_y(56)),
 "DUCKS":    (P_CAST,   46, 1, FY),
 "GRAN":     (P_NONE,    0, 0, FY),
 "ARMCHAIR": (P_SIT,   102, 0, seat_y(112)),
 "FLOWERS":  (P_CAST,  116, 0, FY),
 "FORAGE":   (P_EAT,    84, 0, FY),
 "READ":     (P_PHONE,  60, 0, FY),
 "PAGE":     (P_NONE,    0, 0, FY),
}
POSE_FRAMES = 90
SLEEP_FRAMES = 200
SWING_X = [round(7 * math.sin(2 * math.pi * k / 32)) for k in range(32)]
SWING_Y = [-round(3 * abs(math.sin(2 * math.pi * k / 32))) for k in range(32)]
SLIDE_X = [58 + round(k * 40 / 31) for k in range(32)]
SLIDE_Y = [seat_y(56) + round(k * (seat_y(131) - seat_y(56)) / 31) for k in range(32)]
ACT_ID = {a[0]: i for i, a in enumerate(ACTIONS)}

# ------------------------------------------------------------------ clues
# The sisters' past, one clue per place. Types: 0 lies on the ground (walk
# over it), 1 up high (jump for it), 2 out of reach (Sunny's ATTRACT pulls
# it down), 3 stuck in brambles (Hex's REPEL blasts it free), 4 a person
# gives it to you.
CL_GROUND, CL_HIGH, CL_ATTRACT, CL_REPEL, CL_GIFT = range(5)
#        name       room       type        PX   sprite Y
CLUES = [
 ("PHOTO",  "GRANS",   CL_GIFT,     0,   0),
 ("TIN",    "GARDEN",  CL_HIGH,     28,  58 + 44),
 ("DIARY",  "BEDROOM", CL_HIGH,     122, 58 + 33),
 ("LOCKET", "PARK",    CL_ATTRACT,  22,  58 + 28),
 ("TAGS",   "WOODS",   CL_REPEL,    122, 58 + 110),
 ("PAPER",  "LIBRARY", CL_GIFT,     0,   0),
]
assert [c[0] for c in CLUES] == sprites.CLUE_NAMES

# ------------------------------------------------------------------ messages
WHITE, YELLOW, CYAN, GREEN, LRED, PURPLE = 1, 7, 3, 5, 2, 4
MSGS = []          # (name, text, colour)
def msg(name, text, colour=WHITE):
    assert len(text) <= 40, (name, len(text), text)
    MSGS.append((name, text, colour))

def hint(i):
    """< left place      THIS PLACE      right place >"""
    names = rooms.ROOM_NAMES
    place = PLACE_TITLES[i]
    line = [" "] * 40
    if i > 0:
        left = "< " + PLACE_SHORT[i - 1]
        line[0:len(left)] = left
    if i < len(names) - 1:
        right = PLACE_SHORT[i + 1] + " >"
        line[40 - len(right):] = right
    x = (40 - len(place)) // 2
    line[x:x + len(place)] = place
    return "".join(line).rstrip()

PLACE_SHORT = ["GRAN'S", "GARDEN", "BEDROOM", "HOME", "STREET", "CAFE", "SHOP", "SWINGS", "PARK", "WOODS", "LIBRARY"]
PLACE_TITLES = ["GRAN'S", "THE GARDEN", "MY ROOM", "HOME", "THE STREET", "THE CAFE", "SUPER SHOP",
                "SWING PARK", "THE PARK", "THE WOODS", "LIBRARY"]

msg("BLANK", "")
msg("NOTHING", "NOTHING TO DO HERE. TRY ANOTHER SPOT.")
for _i in range(NUM_ROOMS):
    msg("HINT%d" % _i, hint(_i), CYAN)
PROMPTS = {
 "SLEEP": "FIRE: GO TO BED               REST+",
 "TV": "FIRE: WATCH TV                FUN+",
 "EAT": "FIRE: RAID THE FRIDGE         FOOD+",
 "SHOWER": "FIRE: TAKE A SHOWER           WASH+",
 "BENCH": "FIRE: SIT ON THE BENCH        REST+",
 "PHONE": "FIRE: PHONE GRAN  $1          CHAT+",
 "GROCERY": "FIRE: GROCERIES  $10          3 BAGS",
 "SWEETS": "FIRE: BUY SWEETS  $3      FOOD+ FUN+",
 "OUTFIT": "FIRE: NEW OUTFIT  $30         FUN++",
 "WORK": "FIRE: WORK A SHIFT  8:00 TO 18:00",
 "COFFEE": "FIRE: COFFEE FROM MO $2  REST+ FOOD+",
 "SWING": "FIRE: PLAY ON THE SWINGS      FUN+",
 "SPLASH": "FIRE: SPLASH IN THE FOUNTAIN  WASH+",
 "CHAT": "FIRE: CHAT WITH PIP           CHAT+",
 "COMPUTER": "FIRE: USE THE COMPUTER    FUN+ CHAT+",
 "SLIDE": "FIRE: GO DOWN THE SLIDE       FUN+",
 "DUCKS": "FIRE: FEED THE DUCKS  $1      FUN+",
 "GRAN": "FIRE: TEA WITH GRAN      CHAT+ FOOD+",
 "ARMCHAIR": "FIRE: NAP IN GRAN'S CHAIR     REST+",
 "FLOWERS": "FIRE: WATER THE FLOWERS       FUN+",
 "FORAGE": "FIRE: PICK MUSHROOMS          FOOD+",
 "READ": "FIRE: READ A BOOK             FUN+",
 "PAGE": "FIRE: TALK TO MISS PAGE       CHAT+",
}
for a in ACTIONS:
    msg("P_" + a[0], PROMPTS[a[0]], YELLOW)
RESULTS = {
 "SLEEP": ("ZZZ... GOOD MORNING, SUNSHINE!", "ZZZ... HEX WAKES UP GRUMPY. AS USUAL."),
 "TV": ("SUNNY GIGGLES AT THE CARTOONS!", "HEX WATCHES A CREEPY OLD MOVIE. FUN!"),
 "EAT": ("YUM! A YUMMY SANDWICH!", "HEX EATS COLD PIZZA. PERFECT."),
 "SHOWER": ("SPLISH SPLASH! SQUEAKY CLEAN!", "HEX SHOWERS. STILL LOOKS SPOOKY."),
 "BENCH": ("A NICE SIT DOWN. AAAH.", "HEX GLARES AT PIGEONS. RELAXING."),
 "PHONE": ("GRAN SAYS SUNNY IS A LITTLE ANGEL!", "GRAN SAYS HEX SHOULD SMILE MORE."),
 "GROCERY": ("BOUGHT 3 BAGS OF FOOD FOR THE FRIDGE!", "HEX HAGGLES. 3 BAGS OF FOOD!"),
 "SWEETS": ("MMM, CANDY! SUGAR RUSH!", "BLACK LIQUORICE. HEX APPROVES."),
 "OUTFIT": ("A CUTE NEW DRESS! TWIRL TWIRL!", "A POINTY NEW WITCH HAT. PERFECT."),
 "WORK": ("SUNNY CHARMS THE CUSTOMERS. TIPS!", "HEX SERVES AT LIGHTNING SPEED!"),
 "SWING": ("WHEEE! HIGHER! HIGHER!", "HEX SWINGS UPSIDE DOWN. WHY NOT."),
 "SPLASH": ("SUNNY SPLASHES ABOUT. REFRESHING!", "HEX MAKES THE FOUNTAIN BUBBLE. HEE!"),
 "COMPUTER": ("SUNNY VIDEO-CHATS WITH HER FRIENDS!", "HEX RESEARCHES ANCIENT SPELLS ONLINE."),
 "SLIDE": ("WHEEE! DOWN THE BIG SLIDE!", "HEX SLIDES DOWN HEAD FIRST. OF COURSE."),
 "DUCKS": ("THE DUCKS ADORE SUNNY! QUACK QUACK!", "HEX FEEDS THE DUCKS. THEY BOW TO HER."),
 "ARMCHAIR": ("A COSY NAP IN GRAN'S BIG CHAIR.", "HEX NAPS. GRAN'S CAT GLARES AT HER."),
 "FLOWERS": ("SUNNY SINGS TO THE FLOWERS. THEY GROW!", "HEX'S FLOWERS COME UP BLACK. LOVELY."),
 "FORAGE": ("SUNNY PICKS A BASKET OF MUSHROOMS!", "HEX KNOWS WHICH ONES ARE SAFE. MOSTLY."),
 "READ": ("A FAIRY TALE ABOUT TWO PRINCESSES.", "HEX READS A BOOK OF CURSES. CHARMING."),
}
for a in ACTIONS:
    s, h = RESULTS.get(a[0], ("", ""))
    if a[4] != SP_TALK:
        msg("S_" + a[0], s, WHITE)
        msg("H_" + a[0], h, WHITE)
# the people you meet: four lines each, in turn
NPC_LINES = {
 "MO": ["MO: ONE COFFEE! THAT'LL PERK YOU UP.",
        "MO: GRAN WAS HERE THE DAY YOU WERE BORN.",
        "MO: THE LIBRARY KEEPS EVERY OLD PAPER.",
        "MO: MILK? SUGAR? A SPRINKLE OF MAGIC?"],
 "GRAN": ["GRAN: TEA AND CAKE! YOU'RE BOTH SO THIN.",
          "GRAN: YOUR MUM HID THINGS IN THE GARDEN.",
          "GRAN: SHE KEPT A DIARY, YOU KNOW...",
          "GRAN: ONE IS DAY, ONE IS NIGHT. HMM!"],
 "PIP": ["PIP: SOMETHING SHINY IS UP IN THAT OAK!",
         "PIP: SPOOKY WOODS PAST THE GATE. EEK!",
         "PIP: YOU TWO ARE TOTAL OPPOSITES. LOL.",
         "PIP: CHAT AGAIN SOON. BEST FRIENDS!"],
 "PAGE": ["PAGE: SHH! FIND MORE CLUES FIRST, DEARS.",
          "PAGE: WE KEEP EVERY OLD NEWSPAPER. SHH!",
          "PAGE: FIND FIVE CLUES, THEN COME BACK.",
          "PAGE: A DIARY TELLS NO LIES."],
}
for n in sprites.NPC_NAMES:
    for k, line in enumerate(NPC_LINES[n]):
        msg("N_%s%d" % (n, k), line, CYAN)
CLUE_TEXT = {
 "PHOTO": ("GRAN GIVES YOU A PHOTO OF... TWO BABIES?", ""),
 "TIN": ("CLUE! A TIN: TWO TINY PAIRS OF SOCKS.", "IT'S UP ON THE SHED ROOF. JUMP FOR IT!"),
 "DIARY": ("CLUE! MUM'S DIARY: MY TWO LITTLE STARS", "SOMETHING ON THE WARDROBE... JUMP!"),
 "LOCKET": ("CLUE! A LOCKET WITH A SUN AND A MOON.", "IT GLINTS IN THE OAK. SUNNY: ATTRACT IT!"),
 "TAGS": ("CLUE! TWO HOSPITAL TAGS. SAME BIRTHDAY!", "CAUGHT IN THE BRAMBLES. HEX: BLAST IT!"),
 "PAPER": ("CLUE! TWINS BORN DURING THE ECLIPSE!", ""),
}
for n in sprites.CLUE_NAMES:
    msg("C_" + n, CLUE_TEXT[n][0], GREEN)
    if CLUE_TEXT[n][1]:
        msg("CH_" + n, CLUE_TEXT[n][1], CYAN)
msg("FREED", "HEX BLASTS THE BRAMBLES! SOMETHING FLIES", PURPLE)
msg("NAP", "A QUICK NAP. NOT REALLY SLEEPY YET.")
msg("NOMONEY", "NOT ENOUGH MONEY! GO TO WORK.", LRED)
msg("EMPTY", "THE FRIDGE IS EMPTY! GO SHOPPING.", LRED)
msg("CLOSED", "CAFE SHIFTS ARE 8:00 TO 18:00 ONLY.", LRED)
msg("TOOTIRED", "TOO TIRED TO WORK! GET SOME REST.", LRED)
msg("SCRUFFY", "THE BOSS SAYS: TAKE A SHOWER! NO XP.", LRED)
msg("NOMAGIC", "TOO TIRED FOR MAGIC...", LRED)
msg("COIN", "ATTRACTION! A COIN FLIES IN. +$5", YELLOW)
msg("COINAWAY", "OOPS! HEX REPELLED THE COIN AWAY...", CYAN)
msg("BEEGONE", "BEGONE, BUG! HEX REPELS THE BEE!", CYAN)
msg("BEELOVE", "UH OH! THE BEE IS ATTRACTED TO SUNNY!", YELLOW)
msg("OUCH_S", "OUCH! A BEE STUNG SUNNY!  FUN-", LRED)
msg("OUCH_H", "OUCH! A BEE STUNG HEX!  FUN-", LRED)
msg("SWAP_S", "SUNNY: MY TURN! HI EVERYONE!", YELLOW)
msg("SWAP_H", "HEX: STAND ASIDE, SIS. MY TURN.", CYAN)
msg("PROMO2", "PROMOTED! NOW A WAITRESS!", GREEN)
msg("PROMO3", "PROMOTED! NOW A BARISTA!", GREEN)
msg("PROMO4", "PROMOTED! NOW THE HEAD CHEF!", GREEN)
msg("PROMO5", "PROMOTED! THE CAFE IS YOURS!", GREEN)
msg("W_FOOD", "TUMMY RUMBLING! FIND SOMETHING TO EAT.", LRED)
msg("W_REST", "SO SLEEPY... BED OR COFFEE, QUICK!", LRED)
msg("W_WASH", "PHEW, SMELLY! TIME FOR A SHOWER.", LRED)
msg("W_FUN", "SO BORED... GO AND HAVE SOME FUN!", LRED)
msg("W_CHAT", "SO LONELY... VISIT GRAN OR SEE PIP!", LRED)
msg("FAINT", "SHE FAINTED! WOKE UP IN BED. DOCTOR $10", LRED)
msg("SLEEPING", "ZZZ... SWEET DREAMS.", CYAN)
msg("WELCOME", "ARE WE REALLY SISTERS? FIND 6 CLUES!", WHITE)
msg("EDGE", "NO WAY THROUGH THIS WAY.", CYAN)
msg("CLOSING", "THE CAFE IS CLOSING. GOOD WORK TODAY!", CYAN)
MSG_ID = {m[0]: i for i, m in enumerate(MSGS)}
assert len(MSGS) <= 256

def msg_codes(text):
    """A message: its screen codes, trailing spaces dropped, 0-terminated.
    PrintMsg pads the rest of the line with spaces."""
    return [font.screen_code(ch) for ch in text.rstrip()] + [0]

def place_messages(msg2_base):
    """Messages fill $C400-$CFFF, the rest go after the small tables.
    -> (addresses, MESSAGES bytes, MESSAGES2 bytes)"""
    addrs, blob1, blob2 = [], [], []
    a, second = MSG_BASE, False
    for _m in MSGS:
        codes = msg_codes(_m[1])
        if not second and a + len(codes) > 0xD000:
            second, a = True, msg2_base
        addrs.append(a)
        (blob2 if second else blob1).extend(codes)
        a += len(codes)
    assert not second or a <= 0xC000, hex(a)
    return addrs, blob1, blob2

# ------------------------------------------------------------------ tables
SKY = [6, 6, 6, 6, 6, 4, 4, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 10, 4, 6, 6, 6, 6]
NAMECOL = [7, 4]
#        GRAN GARD BED HOME STRT CAFE SHOP SWNG PARK WOOD LIBR  (bit0 coin, bit1 bee)
SPAWN = [0,   2,   0,  0,   3,   0,   1,   3,   1,   2,   0]
NAMES = ["SUNNY ", "HEX   "]
POWERS = ["ATTRACT", "REPEL  "]
PLACES = ["GRAN'S ", "GARDEN ", "BEDROOM", "HOME   ", "STREET ", "CAFE   ", "SHOP   ", "SWINGS ",
          "PARK   ", "WOODS  ", "LIBRARY"]
JOB_WAGE = [0, 8, 11, 14, 17, 20]
assert len(SPAWN) == len(PLACES) == NUM_ROOMS
for r in rooms.ROOM_NPC:
    assert not SPAWN[r] & 2, "no bees where somebody stands (they share sprite 5)"


def build_tables(map_addrs, chr_addrs, pages):
    """pages: [(text address, [(row, col, colour, length), ...]), ...]"""
    """name -> (address, list of bytes) for every small BYTE_DATA table."""
    t = {}
    addr = SMALL_TABLES
    def add(name, data):
        nonlocal addr
        t[name] = (addr, [d & 255 for d in data])
        addr += len(data)
    add("T_SKY", SKY)
    add("T_DRESS", sprites.DRESS)
    add("T_HAIR", sprites.HAIR)
    add("T_NAMECOL", NAMECOL)
    add("T_SPAWN", SPAWN)
    add("T_DECAY", DECAY)
    add("T_MAPLO", [a & 255 for a in map_addrs])
    add("T_MAPHI", [a >> 8 for a in map_addrs])
    add("T_GROUP", rooms.ROOM_GROUP)
    add("T_GCHRHI", [a >> 8 for a in chr_addrs])
    add("T_GD022", rooms.GROUP_D022)
    add("T_NAMES", sum((font.text_codes(n) for n in NAMES), []))
    add("T_POWERS", sum((font.text_codes(n) for n in POWERS), []))
    add("T_PLACES", sum((font.text_codes(n) for n in PLACES), []))
    add("T_WAGE", JOB_WAGE)
    objs = []
    for room in rooms.OBJECTS:
        row = []
        for c0, c1, a in room:
            row += [c0, c1, ACT_ID[a]]
        row += [0xFF] * (12 - len(row))
        objs += row
    add("T_OBJ", objs)
    add("T_ROOMOFS", [i * 12 for i in range(NUM_ROOMS)])
    # per action: d0..d4, cost, time, msgS, msgH, special, prompt, npc
    act = []
    for a in ACTIONS:
        name, d, cost, tm, sp = a[:5]
        npc = NPC_ID[a[5]] if len(a) > 5 else 0
        ms = MSG_ID.get("S_" + name, MSG_ID["NOTHING"])
        mh = MSG_ID.get("H_" + name, MSG_ID["NOTHING"])
        act.append([x & 255 for x in d] + [cost, tm, ms, mh, sp, MSG_ID["P_" + name], npc])
    # column by column (T_ACT+n,X reads column n of action X; resolve()
    # scales the n), so the table can grow past 21 actions
    add("T_ACT", [row[c] for c in range(12) for row in act])
    add("T_ACTOFS", list(range(len(ACTIONS))))
    add("T_MSGLO", [0] * len(MSGS))       # filled in below, once the tables' end is known
    add("T_MSGHI", [0] * len(MSGS))
    add("T_MSGCOL", [m[2] for m in MSGS])
    add("T_WARN", [MSG_ID["W_" + n] for n in NEEDS])
    add("T_HINT", [MSG_ID["HINT%d" % i] for i in range(NUM_ROOMS)])
    add("T_PID", [POSES[a[0]][0] for a in ACTIONS])
    add("T_PPX", [POSES[a[0]][1] for a in ACTIONS])
    add("T_PFACE", [POSES[a[0]][2] for a in ACTIONS])
    add("T_PY", [POSES[a[0]][3] for a in ACTIONS])
    add("T_SWX", SWING_X)
    add("T_SWY", SWING_Y)
    add("T_SLX", SLIDE_X)
    add("T_SLY", SLIDE_Y)
    add("T_MAGCOL", [10, 14])
    add("T_PROMO", [0, 0, MSG_ID["PROMO2"], MSG_ID["PROMO3"], MSG_ID["PROMO4"], MSG_ID["PROMO5"]])
    add("T_JUMP", JUMP)
    # sprite library: (top, bottom, body) block per sister and pose, per NPC
    add("T_SFRM", [b for sis in sprites.SISTER_FRAMES for f in sis for b in f])
    add("T_SFOFS", [0, len(sprites.POSES) * 3])
    add("T_NFRM", [b for f in sprites.NPC_FRAMES for b in f])
    add("T_NCOL", sprites.NPC_COL)
    add("T_NMSG", [MSG_ID["N_%s0" % n] for n in sprites.NPC_NAMES])
    add("T_RNPC", [rooms.ROOM_NPC[r][0] if r in rooms.ROOM_NPC else 0xFF for r in range(NUM_ROOMS)])
    add("T_RNPCX", [rooms.ROOM_NPC[r][1] if r in rooms.ROOM_NPC else 0 for r in range(NUM_ROOMS)])
    # clues
    add("T_CLROOM", [rooms.ROOM_NAMES.index(c[1]) for c in CLUES])
    add("T_CLTYPE", [c[2] for c in CLUES])
    add("T_CLX", [c[3] for c in CLUES])
    add("T_CLY", [c[4] for c in CLUES])
    add("T_CLCOL", sprites.CLUE_COL)
    add("T_CLMSG", [MSG_ID["C_" + c[0]] for c in CLUES])
    add("T_CLHINT", [MSG_ID.get("CH_" + c[0], MSG_ID["BLANK"]) for c in CLUES])
    add("T_BIT", [1, 2, 4, 8, 16, 32, 64, 128])
    # pages: screen row addresses + per page line table / text pointers
    add("T_ROWLO", [(r * 40) & 255 for r in range(25)])
    add("T_ROWHI", [(r * 40) >> 8 for r in range(25)])
    line_addrs = []
    for i, (_, lines) in enumerate(pages):
        line_addrs.append(addr)
        add("T_PGL%d" % i, [b for ln in lines for b in ln] + [0xFF])
    add("T_PGTLO", [p[0] & 255 for p in pages])
    add("T_PGTHI", [p[0] >> 8 for p in pages])
    add("T_PGLLO", [a & 255 for a in line_addrs])
    add("T_PGLHI", [a >> 8 for a in line_addrs])
    addrs, blob1, blob2 = place_messages(addr)
    t["T_MSGLO"] = (t["T_MSGLO"][0], [a & 255 for a in addrs])
    t["T_MSGHI"] = (t["T_MSGHI"][0], [a >> 8 for a in addrs])
    t["MESSAGES"] = (MSG_BASE, blob1)
    t["MESSAGES2"] = (addr, blob2)
    assert addr + len(blob2) <= 0xC000, hex(addr + len(blob2))
    return t


# ------------------------------------------------------------------ code
# Labels made by macro nodes that the code calls (stable uids set in build.py)
UID_SONG = 501000
UID_HUD_TOP = 502000
UID_HUD_BOT = 502001
def hud_top(f): return "hud%d_%s" % (UID_HUD_TOP, f)
def hud_bot(f): return "hud%d_%s" % (UID_HUD_BOT, f)
SONG_PLAY = "sng%d_play" % UID_SONG

C = {
    "C_FLOORY": FLOOR_Y, "C_COINY": COIN_Y, "C_BEEY": BEE_Y,
    "C_TICKS": FRAMES_PER_10MIN, "C_SPRPTR": SPR_BASE // 64 & 255,
    "C_JUMPLEN": len(JUMP), "C_REACH": REACH, "C_SKIN": sprites.SKIN,
    "C_LIBLO": SPR_LIB & 255, "C_LIBHI": SPR_LIB >> 8,
}
for n, i in sprites.INDEX.items():
    C["C_F_" + n] = (SPR_BASE // 64 + i) & 255
for k, v in MSG_ID.items():
    C["C_M_" + k] = v
C["C_A_SLEEP"] = ACT_ID["SLEEP"]
C["C_LASTROOM"] = NUM_ROOMS - 1
C["C_NACT"] = len(ACTIONS)
C["C_CAFE"] = rooms.ROOM_NAMES.index("CAFE")
C["C_HOME"] = rooms.ROOM_NAMES.index("HOME")
C["C_BEDROOM"] = rooms.ROOM_NAMES.index("BEDROOM")
C["C_POSET"] = POSE_FRAMES
C["C_SLEEPT"] = SLEEP_FRAMES
for _i, _n in enumerate(["NONE", "SIT", "SWING", "SLIDE", "LIE", "PHONE", "EAT", "CHEER", "SHOWER", "WORK", "CAST"]):
    C["C_P_" + _n] = _i
for _n, _i in G.items():
    C["C_G_" + _n] = _i
for i, n in enumerate(["NONE", "SLEEP", "EAT", "GROCERY", "WORK", "TALK"]):
    C["C_SP_" + n] = i
for i, n in enumerate(["GROUND", "HIGH", "ATTRACT", "REPEL", "GIFT"]):
    C["C_CL_" + n] = i
C["C_NPC_GRAN"] = NPC_ID["GRAN"]
C["C_NPC_PAGE"] = NPC_ID["PAGE"]
C["C_NCLUES"] = len(CLUES)

def screen(row, col):
    return SCREEN + row * 40 + col


BLOCKS = {}

BLOCKS["BOOT"] = """
; ---------------------------------------------------------------
; BOOT - runs once after SYSTEM INIT.
; Bank BASIC out ($01=$36): the charsets/tables above $A000 are RAM.
; Quiet the CIA timer interrupts: only our raster interrupts run.
; Build the two mirror tables the sprite code uses to flip the sisters.
; ---------------------------------------------------------------
LDA #$36
STA $01
LDA #$7F
STA $DC0D
STA $DD0D
LDA $DC0D
LDA $DD0D
LDA #$01
STA V_MUSIC
LDA #$00
STA V_SPLIT
STA $D015
LDA #$A7
STA V_RNG
LDA #C_HOME
STA V_ROOM
LDA #$FF               ; no charset copied into VIC memory yet
STA V_GROUP
LDX #$00
BTFlip:
TXA                    ; hires: reverse the 8 bits
STA V_T0
LDY #8
BTHr:
LSR V_T0
ROL
DEY
BNE BTHr
STA $C200,X
TXA                    ; multicolour: reverse the 4 bit pairs
STA V_T0
LDA #$00
STA V_T1
LDY #4
BTMc:
ASL V_T1
ASL V_T1
LDA V_T0
AND #$03
ORA V_T1
STA V_T1
LSR V_T0
LSR V_T0
DEY
BNE BTMc
LDA V_T1
STA $C300,X
INX
BNE BTFlip
JMP Title
"""

BLOCKS["TITLE_IRQ"] = """
; ---------------------------------------------------------------
; TITLE: the picture, the tune and the SFX player are set up above.
; Start the raster interrupt chain (IrqMusic plays the tune and SFX
; every frame), then hold the title screen.
; ---------------------------------------------------------------
SEI
LDA #<IrqMusic
STA $0314
LDA #>IrqMusic
STA $0315
LDA #$FB
STA $D012
LDA $D011
AND #$7F
STA $D011
LDA #$01
STA $D01A
STA $D019
CLI
JMP TitleHold
"""

BLOCKS["TITLE_HOLD"] = """
; ---------------------------------------------------------------
; TITLE CYCLE: the picture for 5 seconds, then HOW TO PLAY for 12
; seconds, then back to the picture. FIRE on either starts a new life.
; ---------------------------------------------------------------
TitleHold:
LDA #$00
STA $D015
STA V_SPLIT
THRelease:
JSR FrameTick
LDA $DC00
AND #$10
BEQ THRelease
LDA #$FA               ; 250 frames = 5 seconds
STA V_T0
LDA #$00
STA V_T1
THPic:
JSR FrameTick
JSR TitleFire
JSR TitleCount
BNE THPic
JSR ShowHelp
LDA #$58               ; 600 frames = 12 seconds
STA V_T0
LDA #$02
STA V_T1
THHelp:
JSR FrameTick
JSR TitleFire
JSR TitleCount
BNE THHelp
JMP TitlePic

; TitleCount: 16-bit countdown in T0/T1, Z set when it reaches zero.
TitleCount:
LDA V_T0
BNE TCLow
DEC V_T1
TCLow:
DEC V_T0
LDA V_T0
ORA V_T1
RTS

; TitleFire: FIRE pressed? wait for release, then start the game.
TitleFire:
LDA $DC00
AND #$10
BEQ TFGo
RTS
TFGo:
JSR FrameTick
LDA $DC00
AND #$10
BEQ TFGo
LDX #$FF
TXS
LDA $D012
EOR V_RNG
ORA #$01
STA V_RNG
JMP StartGame
"""

BLOCKS["HELP_PREP"] = """
; ---------------------------------------------------------------
; HOW TO PLAY page: copy a room charset (they all hold the font) into
; VIC memory; the VIC / CLEAR nodes below set the screen up, then
; PrintPage draws the lines.
; ---------------------------------------------------------------
LDA #$00
STA $D015
STA V_SPLIT
JSR CopyRoomGfx
"""

BLOCKS["HELP_DRAW"] = """
LDX #$00               ; page 0: HOW TO PLAY
JMP PrintPage
"""

BLOCKS["PAGES"] = """
// @asset HELP_TEXT
// @asset ENDING_TEXT
// @asset TRUTH_TEXT
; ---------------------------------------------------------------
; PrintPage: X = page (0 how to play, 1 dream come true, 2 the truth).
; One small loop instead of a PRINT node per line: each line of the page
; table gives row, column, colour and length; its text follows on in
; the page's TEXT_DATA asset. A row of $FF ends the page.
; ---------------------------------------------------------------
PrintPage:
LDA T_PGTLO,X
STA $58
LDA T_PGTHI,X
STA $59
LDA T_PGLLO,X
STA $5C
LDA T_PGLHI,X
STA $5D
PPLine:
LDY #$00
LDA ($5C),Y            ; row
CMP #$FF
BEQ PPDone
TAX
INY
LDA T_ROWLO,X
CLC
ADC ($5C),Y            ; + column
STA $5A
STA $5E
LDA T_ROWHI,X
ADC #$00
STA $5B
CLC
ADC #$D8
STA $5F                ; $5E = colour RAM
LDA $5B
CLC
ADC #$04
STA $5B                ; $5A = screen
INY
LDA ($5C),Y
STA V_T5               ; colour
INY
LDA ($5C),Y
STA V_T6               ; length
LDY #$00
PPChar:
CPY V_T6
BEQ PPNext
LDA ($58),Y
STA ($5A),Y
LDA V_T5
STA ($5E),Y
INY
BNE PPChar
PPNext:
LDA $58
CLC
ADC V_T6
STA $58
BCC PPText
INC $59
PPText:
LDA $5C
CLC
ADC #4
STA $5C
BCC PPLine
INC $5D
JMP PPLine
PPDone:
RTS
"""

BLOCKS["FRAME_IRQ"] = """
; ---------------------------------------------------------------
; IrqMusic (raster line 251): ack, play the tune (when on), set up the
; next interrupt of the chain, then the SFX UPDATE node below runs and
; JMP $EA81 returns.  Chain: 251 music -> 58 sky colour -> 218 black.
; The sky / black split gives the HUD rows a black background while the
; scene in between shows the sky colour of the current hour.
; ---------------------------------------------------------------
LDA #$FF
STA $D019
LDA V_MUSIC
BEQ IrqNoTune
JSR """ + SONG_PLAY + """
IrqNoTune:
LDA #<IrqSky
STA $0314
LDA #>IrqSky
STA $0315
LDA #58
STA $D012
"""

BLOCKS["FRAME_IRQ_END"] = """
JMP $EA81              ; KERNAL: pull Y, X, A and RTI

; IrqSky (line 58): the scene rows show the sky colour.
IrqSky:
LDA #$FF
STA $D019
LDA V_SPLIT
BEQ ISkyNext
LDA V_SKYCOL
STA $D021
ISkyNext:
LDA #<IrqHud
STA $0314
LDA #>IrqHud
STA $0315
LDA #218
STA $D012
JMP $EA81

; IrqHud (line 218): black behind the bottom HUD and the top status row.
IrqHud:
LDA #$FF
STA $D019
LDA V_SPLIT
BEQ IHudNext
LDA #$00
STA $D021
IHudNext:
LDA #<IrqMusic
STA $0314
LDA #>IrqMusic
STA $0315
LDA #$FB
STA $D012
JMP $EA81
"""

BLOCKS["NEW_GAME"] = """
; ---------------------------------------------------------------
; NEW LIFE: the VIC, sprite, clear and HUD nodes above set the screen up.
; Reset the sisters' needs, money, clock, job and clues, then walk into
; HOME. Sprites: 0/1 her hires overlays, 2 her body (multicolour, double
; height), 3 magic, 4 coin or clue, 5 bee, 5-7 the person in the room.
; ---------------------------------------------------------------
LDA #$00
STA V_FACE
STA V_FORM
STA V_MIN
STA V_TICK
STA V_JOBXP
STA V_COIN
STA V_BEE
STA V_SWAPT
STA V_STING
STA V_ZZZ
STA V_COINCD
STA V_MHI
STA V_PREVJOY
STA V_JOYID
STA V_POSE
STA V_SLEEPING
STA V_JUMP
STA V_CLUES
STA V_NCLUE
STA V_ITEM
STA V_TALK
STA V_TALK1
STA V_TALK2
STA V_TALK3
LDA #20
STA V_MLO
LDA #$01
STA V_DAY
STA V_JOBLV
STA V_BAGS
LDA #C_HOME            ; a new life starts at HOME
STA V_ROOM
LDA #8
STA V_HOUR
LDA #36
LDX #4
NGNeeds:
STA V_NEED,X
DEX
BPL NGNeeds
LDA #60
STA V_PX
LDA #$84               ; bodies multicolour and double height
STA $D01C
STA $D017
LDA #$00
STA $D01D
STA $D01B
LDA #$07               ; only the girl is on
STA $D015
JSR SetGirlCols
LDA #$01
STA V_SPLIT
JSR SetSky
JSR RefreshHud
LDA #C_M_WELCOME
JSR PrintMsg
LDA #$FF               ; no prompt yet: the welcome line stays up
STA V_OBJ
JMP EnterRoomKeep
"""

BLOCKS["ROOM"] = ("\n" + "".join("// @asset CHARS_%s\n" % g for g in rooms.GROUP_NAMES)
                  + "".join("// @asset MAP_%s\n" % r for r in rooms.ROOM_NAMES) + "// @asset SPR_LIB\n") + """
; (these lines tell the build to include every place's charset and map
;  and the sprite library: this code copies them in itself)
; ---------------------------------------------------------------
; ENTER ROOM: blank the screen, copy this place's charset + colours,
; draw its 40x20 map into rows 1-20, name it, bring in its person,
; its clue, a coin / bee.
; Reset the stack: room changes jump here from inside joystick handlers.
; ---------------------------------------------------------------
EnterRoom:
LDX #$FF
TXS
LDA #$FE
STA V_OBJ              ; next frame shows this spot's prompt / hint
EnterRoomKeep:
LDA $D011
AND #$EF
STA $D011
JSR CopyRoomGfx
JSR DrawRoom
JSR PlaceName
JSR SetupNpc
JSR SetupClue
JSR SpawnThings
JSR SetSky
JSR FrameTick
LDA $D011
ORA #$10
STA $D011
JMP MainLoop

; CopyRoomGfx: this room's CHAR_SET -> $3000 (2K), its colour table -> $C100,
; its shared colour -> $D022. Rooms of a group share one charset.
CopyRoomGfx:
LDX V_ROOM
LDA T_GROUP,X
CMP V_GROUP
BNE CRGNew
RTS
CRGNew:
STA V_GROUP
TAX
LDA T_GD022,X
STA $D022
LDA T_GCHRHI,X
STA $55
LDA #$00
STA $54
STA $50
LDA #$30
STA $51
LDX #$08
LDY #$00
CRGLoop:
LDA ($54),Y
STA ($50),Y
INY
BNE CRGLoop
INC $55
INC $51
DEX
BNE CRGLoop
LDA V_GROUP
CLC
ADC #>T_TILECOL
STA $55
LDY #$00
CRGCol:
LDA ($54),Y
STA $C100,Y
INY
BNE CRGCol
RTS

; DrawRoom: the map (40x20 chars = 800 bytes) lives under the I/O area /
; KERNAL, so copy it to screen rows 1-20 with all RAM banked in
; (interrupts off), then colour every cell from the charset's colours.
DrawRoom:
LDX V_ROOM
LDA T_MAPLO,X
STA $54
LDA T_MAPHI,X
STA $55
LDA #$28
STA $50
STA $52
LDA #$04
STA $51
LDA #$D8
STA $53
SEI
LDA #$34
STA $01
LDX #$03               ; 3 pages + 32 bytes
LDY #$00
DRCopy:
LDA ($54),Y
STA ($50),Y
INY
BNE DRCopy
INC $55
INC $51
DEX
BNE DRCopy
DRTail:
LDA ($54),Y
STA ($50),Y
INY
CPY #32
BNE DRTail
LDA #$36
STA $01
CLI
LDA #$04
STA $51
LDA #$03
STA V_T0
LDY #$00
DRCol:
LDA ($50),Y
TAX
LDA $C100,X
STA ($52),Y
INY
BNE DRCol
INC $51
INC $53
DEC V_T0
BNE DRCol
DRColTail:
LDA ($50),Y
TAX
LDA $C100,X
STA ($52),Y
INY
CPY #32
BNE DRColTail
RTS

; PlaceName: 7-char place name into the top status row.
PlaceName:
LDA V_ROOM
ASL
ASL
ASL
SEC
SBC V_ROOM
TAX
LDY #$00
PNLoop:
LDA T_PLACES,X
STA """ + "$%04X" % screen(0, 16) + """,Y
LDA #$03
STA """ + "$%04X" % (COLRAM + 16) + """,Y
INX
INY
CPY #7
BNE PNLoop
RTS

; SpawnThings: maybe a floating coin (street, shop, swings, park) and a
; bee (garden, street, swings, woods, daytime). Coins have a 2 hour
; cooldown after a catch, and stay away while a clue is in the room.
SpawnThings:
LDA #$00
STA V_COIN
STA V_BEE
LDX V_ROOM
LDA T_SPAWN,X
STA V_T1
AND #$01
BEQ STBee
LDA V_ITEM
BNE STBee
LDA V_COINCD
BNE STBee
JSR Rand
AND #$01
BEQ STBee
LDA #$01
STA V_COIN
JSR Rand
AND #$3F
CLC
ADC #40
STA V_COINX
LDA #C_COINY
STA V_COINY
STBee:
LDA V_T1
AND #$02
BEQ STDone
LDA V_HOUR
CMP #7
BCC STDone
CMP #20
BCS STDone
JSR Rand
AND #$03
BEQ STDone
LDA #$01
STA V_BEE
LDA #C_BEEY
STA V_BEEY
LDA #29
STA V_STING            ; a moment's grace before it can sting
LDA V_PX
CMP #74
BCS STBeeLeft
LDA #140
STA V_BEEX
RTS
STBeeLeft:
LDA #6
STA V_BEEX
STDone:
RTS

; Rand: 8-bit Galois LFSR -> A
Rand:
LDA V_RNG
ASL
BCC RandNo
EOR #$1D
RandNo:
STA V_RNG
RTS

; SetSky: sky colour for the current hour (the raster split shows it).
SetSky:
LDX V_HOUR
LDA T_SKY,X
STA V_SKYCOL
RTS
"""

BLOCKS["MAIN_PRE"] = """
; ---------------------------------------------------------------
; MAIN LOOP (once per frame, after FrameTick): clear the per-frame
; flags, then the JOYSTICK node calls one handler (JoyFire, JoyUp ...).
; ---------------------------------------------------------------
LDA V_JOYID
STA V_PREVJOY
LDA #$00
STA V_JOYID
STA V_CASTING
STA V_MOVING
INC V_FRAME
"""

BLOCKS["MAIN_UPDATE"] = """
; ---------------------------------------------------------------
; Per-frame update: clock, the girl, magic, coin / clue, bee, the
; person in the room, prompts, faint.
; ---------------------------------------------------------------
JSR ClockTick
JSR DrawGirl
JSR DrawMagic
JSR UpdateCoin
JSR UpdateBee
JSR UpdateNpc
JSR CheckSpot
JSR CheckFaint
"""

BLOCKS["JOY"] = """
; ---------------------------------------------------------------
; JOYSTICK HANDLERS (JSR'd by the JOYSTICK node; each must RTS).
; UP jumps (UP+LEFT/RIGHT jumps across). FIRE uses the thing she
; stands at, or talks to the person there; anywhere else, holding FIRE
; is magic. FIRE+DOWN swaps sisters. JOYID / PREVJOY give edge detection.
; ---------------------------------------------------------------
JoyFire:
LDA #$01
STA V_JOYID
LDA V_POSE             ; busy (sitting, sleeping...): no input
BNE JFDone
LDA V_OBJ
CMP #$FE
BCS JFMagic            ; nothing here: magic
LDA V_JUMP             ; no using things mid-air
BNE JFDone
LDA V_PREVJOY
CMP #$01
BEQ JFDone             ; one use per press
JMP DoAction
JFMagic:
LDA V_NEED1
CMP #2
BCS JFCast
LDA V_PREVJOY
CMP #$01
BEQ JFDone
LDA #C_M_NOMAGIC
JMP PrintMsg
JFCast:
LDA #$01
STA V_CASTING
LDA V_PREVJOY
CMP #$01
BEQ JFDrain
JSR SndMagic
JFDrain:
INC V_DRAIN            ; magic costs 1 REST every 64 frames
LDA V_DRAIN
AND #$3F
BNE JFDone
DEC V_NEED1
JMP RefreshBars
JFDone:
RTS

JoyUpRight:
JSR JoyUp
JMP JoyRight
JoyUpLeft:
JSR JoyUp
JMP JoyLeft

JoyUp:
LDA #$02
STA V_JOYID
LDA V_POSE
BNE JUDone
LDA V_JUMP
BNE JUDone
LDA #$01               ; jump! (DrawGirl runs the arc)
STA V_JUMP
JMP SndJump
JUDone:
RTS

JoySwap:               ; FIRE + DOWN
LDA #$03
STA V_JOYID
LDA V_POSE
BNE JDDone
LDA V_PREVJOY
CMP #$03
BEQ JDDone
LDA V_FORM             ; SWAP SISTERS
EOR #$01
STA V_FORM
LDA #30
STA V_SWAPT
JSR SetGirlCols
JSR SndSwap
JSR RefreshNames
LDA V_FORM
CLC
ADC #C_M_SWAP_S
JMP PrintMsg
JDDone:
RTS

JoyLeft:
LDA #$04
STA V_JOYID
LDA V_POSE
BNE JLWall
LDA #$01
STA V_FACE
STA V_MOVING
LDA V_PX
CMP #$02
BCC JLEdge
DEC V_PX
RTS
JLEdge:
LDA V_ROOM
BEQ JLEnd
DEC V_ROOM
LDA #145
STA V_PX
JMP EnterRoom
JLEnd:
LDA V_PREVJOY
CMP #$04
BEQ JLWall
LDA #C_M_EDGE
JMP PrintMsg
JLWall:
RTS

JoyRight:
LDA #$05
STA V_JOYID
LDA V_POSE
BNE JRDone
LDA #$00
STA V_FACE
LDA #$01
STA V_MOVING
LDA V_PX
CMP #146
BCS JREdge
INC V_PX
RTS
JREdge:
LDA V_ROOM
CMP #C_LASTROOM
BEQ JREnd
INC V_ROOM
LDA #$02
STA V_PX
JMP EnterRoom
JREnd:
LDA V_PREVJOY
CMP #$05
BEQ JRDone
LDA #C_M_EDGE
JMP PrintMsg
JRDone:
RTS

JoyNone:
RTS
"""

BLOCKS["SPRITES"] = """
; ---------------------------------------------------------------
; DrawGirl: pick her pose (stand / walk / jump / cast) and height.
; The jump follows T_JUMP, one step a frame.
; ---------------------------------------------------------------
DrawGirl:
LDA V_POSE
BEQ DGNormal
JMP DrawPose
DGNormal:
LDA V_PX
STA V_GX
LDA #C_FLOORY
STA V_GY
LDA V_JUMP
BEQ DGGround
TAX
LDA #C_FLOORY
SEC
SBC T_JUMP,X
STA V_GY
INC V_JUMP
LDA V_JUMP
CMP #C_JUMPLEN
BCC DGAir
LDA #$00
STA V_JUMP
DGAir:
LDA #C_G_JUMP
LDX V_CASTING
BEQ DGSet
LDA #C_G_CAST
JMP DGSet
DGGround:
LDA #C_G_CAST
LDX V_CASTING
BNE DGSet
LDA V_MOVING
BEQ DGStand
LDA V_FRAME            ; walk (in profile): stride / legs together, 8 frames each
AND #$08
BNE DGStep
LDA V_GY               ; the stride sits 2 lines lower: her head bobs
CLC
ADC #2
STA V_GY
LDA #C_G_WALK
JMP DGSet
DGStep:
LDA #C_G_STEP
JMP DGSet
DGStand:
LDA #C_G_STAND
DGSet:
STA V_GP

; ---------------------------------------------------------------
; ShowGirl: show her as pose GP at GX (half pixels), GY (raster).
; A new pose, sister or facing copies its three library blocks into the
; bank 0 buffers (mirrored when she faces left): sprite 0 = top overlay,
; 1 = bottom overlay (21 lines lower), 2 = the double-height body.
; ---------------------------------------------------------------
ShowGirl:
LDA V_FORM
ASL
ASL
ASL
ASL
ORA V_GP
LDX V_FACE
BEQ SGKey
ORA #$80
SGKey:
CMP V_GKEY
BEQ SGPlace
STA V_GKEY
LDX V_FORM
LDA T_SFOFS,X
STA V_T5
LDA V_GP               ; row = form*30 + pose*3
ASL
CLC
ADC V_GP
CLC
ADC V_T5
STA V_T6
TAX
LDA T_SFRM,X
LDY #$00
JSR CopyBlock
LDX V_T6
LDA T_SFRM+1,X
LDY #$01
JSR CopyBlock
LDX V_T6
LDA T_SFRM+2,X
LDY #$02
JSR CopyBlock
LDA V_FACE
BEQ SGPlace
LDY #$00               ; facing left: mirror the three buffers
JSR BufPtr
JSR MirrorHR
LDY #$01
JSR BufPtr
JSR MirrorHR
LDY #$02
JSR BufPtr
JSR MirrorMC
SGPlace:
LDA V_GX
JSR SprX
STA $D000
STA $D002
STA $D004
LDA $D010
AND #$F8
LDX V_SPRHI
BEQ SGHi
ORA #$07
SGHi:
STA $D010
LDA V_GY
STA $D001
STA $D005
CLC
ADC #21
STA $D003
RTS

; SetGirlCols: this sister's hair ($D026) and dress (body colour);
; the overlays are black, $D025 is skin. Forces a fresh copy.
SetGirlCols:
LDX V_FORM
LDA T_HAIR,X
STA $D026
LDA T_DRESS,X
STA $D029
LDA #C_SKIN
STA $D025
LDA #$00
STA $D027
STA $D028
LDA #$FF
STA V_GKEY
RTS

; BufPtr: Y = buffer (0-5) -> $5A/$5B = its address in bank 0.
BufPtr:
TYA
LSR
LSR
CLC
ADC #$38
STA $5B
TYA
AND #$03
LSR
ROR
ROR
STA $5A
RTS

; CopyBlock: A = library block, Y = buffer (0-5). The library sits under
; the KERNAL ROM: bank it out (interrupts off) for the 63-byte copy.
CopyBlock:
LDX #$00
STX $59
ASL
ROL $59
ASL
ROL $59
ASL
ROL $59
ASL
ROL $59
ASL
ROL $59
ASL
ROL $59
CLC
ADC #C_LIBLO
STA $58
LDA $59
ADC #C_LIBHI
STA $59
JSR BufPtr
SEI
LDA #$35
STA $01
LDY #62
CBLoop:
LDA ($58),Y
STA ($5A),Y
DEY
BPL CBLoop
LDA #$36
STA $01
CLI
RTS

; MirrorHR / MirrorMC: flip the sprite at ($5A) left-right, row by row:
; swap the outer bytes and reverse the bits (or the bit pairs) of all 3.
MirrorHR:
LDY #60
MHLoop:
LDA ($5A),Y
TAX
LDA $C200,X
STA V_T5
INY
INY
LDA ($5A),Y
TAX
LDA $C200,X
DEY
DEY
STA ($5A),Y
INY
INY
LDA V_T5
STA ($5A),Y
DEY
LDA ($5A),Y
TAX
LDA $C200,X
STA ($5A),Y
DEY
DEY
DEY
DEY
BPL MHLoop
RTS

MirrorMC:
LDY #60
MMLoop:
LDA ($5A),Y
TAX
LDA $C300,X
STA V_T5
INY
INY
LDA ($5A),Y
TAX
LDA $C300,X
DEY
DEY
STA ($5A),Y
INY
INY
LDA V_T5
STA ($5A),Y
DEY
LDA ($5A),Y
TAX
LDA $C300,X
STA ($5A),Y
DEY
DEY
DEY
DEY
BPL MMLoop
RTS

; ---------------------------------------------------------------
; DrawPose: she is busy with an action (T_PID gives the pose). Sitting
; swings its legs, the swing rocks on an arc, the slide runs down a path,
; work paces behind the counter, eating munches, cheering hops.
; ---------------------------------------------------------------
DrawPose:
LDA V_PX
STA V_GX
LDA V_POSEY
STA V_GY
LDA $D015
ORA #$07
STA $D015
LDA V_POSE
CMP #C_P_SIT
BNE DPNotSit
DPSitFrame:
LDA V_POSET            ; legs swing
LSR
LSR
LSR
AND #$01
CLC
ADC #C_G_SIT_A
JMP DPSet
DPNotSit:
CMP #C_P_SWING
BNE DPNotSwing
LDA V_POSET
AND #$1F
TAX
LDA V_PX
CLC
ADC T_SWX,X
STA V_GX
LDA V_POSEY
CLC
ADC T_SWY,X
STA V_GY
JMP DPSitFrame
DPNotSwing:
CMP #C_P_SLIDE
BNE DPNotSlide
LDA V_POSET            ; 90..67 sit at the top, 66..35 slide, then cheer
CMP #67
BCS DPSitFrame
CMP #35
BCC DPSlideEnd
SEC
SBC #35
EOR #$1F
TAX
LDA T_SLX,X
STA V_GX
LDA T_SLY,X
STA V_GY
JMP DPSitFrame
DPSlideEnd:
LDA T_SLX+31
STA V_GX
STA V_PX               ; she ends the pose at the bottom
LDA #C_FLOORY
STA V_GY
LDA #C_G_CHEER
JMP DPSet
DPNotSlide:
CMP #C_P_LIE
BNE DPNotLie
LDA #C_G_LIE
JMP DPSet
DPNotLie:
CMP #C_P_SHOWER
BNE DPNotShower
LDA $D015              ; behind the curtain: just bubbles
AND #$F8
STA $D015
JMP DPTick
DPNotShower:
CMP #C_P_WORK
BNE DPNotWork
LDA V_FRAME            ; pace behind the counter
AND #$01
BNE DPWorkDraw
LDA V_FACE
BNE DPWorkLeft
INC V_PX
LDA V_PX
SEC
SBC V_POSEPX
CMP #22
BCC DPWorkDraw
LDA #$01
STA V_FACE
JMP DPWorkDraw
DPWorkLeft:
DEC V_PX
LDA V_PX
CMP V_POSEPX
BNE DPWorkDraw
LDA #$00
STA V_FACE
DPWorkDraw:
LDA V_PX
STA V_GX
LDA V_FRAME
LSR
LSR
LSR
AND #$01
JMP DPSet
DPNotWork:
CMP #C_P_CAST
BNE DPNotCast
LDA #C_G_CAST
JMP DPSet
DPNotCast:
CMP #C_P_CHEER
BNE DPNotCheer
LDA V_POSET            ; hop
AND #$08
BEQ DPCheer
DEC V_GY
DEC V_GY
DPCheer:
LDA #C_G_CHEER
JMP DPSet
DPNotCheer:
CMP #C_P_PHONE
BNE DPEat
LDA #C_G_PHONE
JMP DPSet
DPEat:
LDA V_POSET            ; munch
AND #$10
BEQ DPEat2
LDA #C_G_EAT
JMP DPSet
DPEat2:
LDA #C_G_STAND
DPSet:
STA V_GP
JSR ShowGirl
DPTick:
DEC V_POSET
BNE DPDone
JMP EndPose
DPDone:
RTS

; StartPose: X = action -> her pose, spot, facing and height for it.
StartPose:
LDA T_PID,X
BEQ SPDone
STA V_POSE
LDA T_PPX,X
STA V_PX
STA V_POSEPX
LDA T_PFACE,X
STA V_FACE
LDA T_PY,X
STA V_POSEY
LDA #C_POSET
STA V_POSET
LDA #$00
STA V_JUMP
SPDone:
RTS

; EndPose: back to normal; a finished night's sleep wakes her up.
EndPose:
LDA #$00
STA V_POSE
LDA $D015
ORA #$07
STA $D015
LDA V_SLEEPING
BEQ EPDone
JMP WakeUp
EPDone:
RTS

; SprX: A = position (0-159 half pixels) -> A = low byte of A*2+24,
; SPRHI = bit 8.
SprX:
ASL
STA V_T1
LDA #$00
ROL
STA V_SPRHI
LDA V_T1
CLC
ADC #24
BCC SXDone
INC V_SPRHI
SXDone:
RTS

; SetHi: A = sprite bit mask, SPRHI -> set or clear those bits of $D010.
SetHi:
LDX V_SPRHI
BEQ SHClear
ORA $D010
STA $D010
RTS
SHClear:
EOR #$FF
AND $D010
STA $D010
RTS

; SprOn / SprOff: A = sprite bit mask
SprOn:
ORA $D015
STA $D015
RTS
SprOff:
EOR #$FF
AND $D015
STA $D015
RTS

; ---------------------------------------------------------------
; DrawMagic (sprite 3): the swap sparkle, the sleep Zzz, the shower
; bubbles, or the magic itself in front of her while FIRE is held -
; hearts for Sunny's ATTRACTION, zaps for Hex's REPULSION.
; ---------------------------------------------------------------
DrawMagic:
LDA V_POSE
CMP #C_P_LIE
BNE DMNotZzz
JMP DMZzz
DMNotZzz:
CMP #C_P_SHOWER
BNE DMNotBub
JMP DMBubbles
DMNotBub:
LDA V_SWAPT
BEQ DMNoSwap
DEC V_SWAPT
LDA V_FRAME
LSR
LSR
AND #$01
CLC
ADC #C_F_STAR_A
STA $07FB
LDA #$01
STA $D02A
LDA V_GY
CLC
ADC #10
STA V_MY
LDA V_PX
JMP DMShowY
DMNoSwap:
LDA V_CASTING
BNE DMCast
LDA #$08
JMP SprOff
DMCast:
LDA V_FRAME
LSR
LSR
LSR
AND #$01
STA V_T0
LDA V_FORM
ASL
CLC
ADC V_T0
CLC
ADC #C_F_HEARTS_A
STA $07FB
LDX V_FORM
LDA T_MAGCOL,X
STA $D02A
LDA V_GY
CLC
ADC #12
STA V_MY
LDA V_FACE
BNE DMLeft
LDA V_PX
CLC
ADC #12
JMP DMShowY
DMLeft:
LDA V_PX
SEC
SBC #12
BCS DMShowY
LDA #$00
DMShowY:
JSR SprX
STA $D006
LDA #$08
JSR SetHi
LDA V_MY
STA $D007
LDA #$08
JMP SprOn

DMZzz:
LDA #C_F_ZZZ
STA $07FB
LDA #$01
STA $D02A
LDA V_FRAME
LSR
LSR
LSR
LSR
AND #$03
STA V_T0
LDA V_POSEY
SEC
SBC #4
SEC
SBC V_T0
STA V_MY
LDA V_PX
CLC
ADC #8
JMP DMShowY

DMBubbles:
LDA #C_F_BUBBLES
STA $07FB
LDA #$01
STA $D02A
LDA V_FRAME
LSR
LSR
LSR
AND #$03
STA V_T0
LDA V_POSEY
CLC
ADC #8
SEC
SBC V_T0
STA V_MY
LDA V_PX
JMP DMShowY
"""

BLOCKS["THINGS"] = """
; ---------------------------------------------------------------
; UpdateCoin (sprite 4): it floats out of reach. Sunny's ATTRACTION pulls
; it down to her (+$5); Hex's REPULSION pushes it away for good.
; A clue in the room takes sprite 4 instead (UpdateItem).
; ---------------------------------------------------------------
UpdateCoin:
LDA V_ITEM
BEQ UCNoItem
JMP UpdateItem
UCNoItem:
LDA V_COIN
BNE UCOn
LDA #$10
JMP SprOff
UCOn:
LDA V_CASTING
BEQ UCFloat
LDA V_FORM
BNE UCRepel
LDA V_COINX            ; ATTRACT: towards her...
CMP V_PX
BEQ UCDown
BCS UCLeft
INC V_COINX
JMP UCDown
UCLeft:
DEC V_COINX
UCDown:
LDA V_COINY            ; ...and down to her hands
CMP #168
BCS UCCatch
INC V_COINY
INC V_COINY
JMP UCCatch
UCRepel:
LDA V_COINX
CMP V_PX
BCC UCPushL
INC V_COINX
INC V_COINX
LDA V_COINX
CMP #150
BCS UCGone
JMP UCDraw
UCPushL:
DEC V_COINX
DEC V_COINX
LDA V_COINX
CMP #4
BCC UCGone
JMP UCDraw
UCGone:
LDA #$00
STA V_COIN
LDA #C_M_COINAWAY
JSR PrintMsg
LDA #$10
JMP SprOff
UCFloat:
LDA V_COINY            ; drift back up, bob gently
CMP #C_COINY
BCC UCDraw
BEQ UCDraw
LDA V_FRAME
AND #$03
BNE UCDraw
DEC V_COINY
JMP UCDraw
UCCatch:
LDA V_COINY
CMP #160
BCC UCDraw
JSR NearX              ; A = |COINX - PX|
CMP #6
BCS UCDraw
LDA #$00               ; caught it!
STA V_COIN
LDA #$02
STA V_COINCD
LDA #5
JSR AddMoney
JSR RefreshMoney
JSR SndCoin
LDA #C_M_COIN
JSR PrintMsg
LDA #$10
JMP SprOff
UCDraw:
LDA V_FRAME
LSR
LSR
LSR
AND #$01
CLC
ADC #C_F_COIN_A
STA $07FC
LDA #$07
STA $D02B
LDA V_COINX
JSR SprX
STA $D008
LDA #$10
JSR SetHi
LDA V_FRAME
AND #$10
LSR
LSR
LSR
LSR
CLC
ADC V_COINY
STA $D009
LDA #$10
JMP SprOn

; NearX: A = |COINX - PX| (the coin and clue share COINX via ITX).
NearX:
LDA V_COINX
SEC
SBC V_PX
BCS NXDone
EOR #$FF
ADC #$01
NXDone:
RTS

; ---------------------------------------------------------------
; SetupClue: the clue still hidden in this room (if any) -> ITEM
; (clue number + 1), its spot and its state.
; UpdateItem (sprite 4): walk over it, jump for it, pull it down with
; Sunny's ATTRACT or blast it out of the brambles with Hex's REPEL.
; ---------------------------------------------------------------
SetupClue:
LDA #$00
STA V_ITEM
STA V_ITST
LDX #C_NCLUES-1
SCLoop:
LDA T_CLROOM,X
CMP V_ROOM
BNE SCNext
LDA T_CLTYPE,X
CMP #C_CL_GIFT
BEQ SCNext
LDA V_CLUES
AND T_BIT,X
BNE SCNext
INX
STX V_ITEM
DEX
LDA T_CLX,X
STA V_ITX
LDA T_CLY,X
STA V_ITY
RTS
SCNext:
DEX
BPL SCLoop
RTS

UpdateItem:
LDX V_ITEM
DEX
STX V_T5               ; clue number
LDA V_ITX
STA V_COINX
JSR NearX
STA V_T6               ; how far she is from it
LDA T_CLTYPE,X
CMP #C_CL_HIGH
BNE UINotHigh
LDA V_T6               ; up high: grab it at the top of a jump
CMP #8
BCS UIToDraw
LDX V_JUMP
BEQ UIToDraw
LDA T_JUMP,X
CMP #C_REACH
BCC UIToDraw
JMP UIGot
UIToDraw:
JMP UIDraw
UINotHigh:
CMP #C_CL_ATTRACT
BNE UINotPull
LDA V_CASTING          ; Sunny's attraction pulls it to her hands
BEQ UIToDraw
LDA V_FORM
BNE UIToDraw
LDA V_T6
CMP #48
BCS UIToDraw
LDA V_ITX
CMP V_PX
BEQ UIPullY
BCS UIPullL
INC V_ITX
JMP UIPullY
UIPullL:
DEC V_ITX
UIPullY:
LDA V_ITY
CMP #170
BCS UIGround
INC V_ITY
INC V_ITY
JMP UIDraw
UINotPull:
CMP #C_CL_REPEL
BNE UIGround
LDA V_ITST
BNE UIFalling
LDA V_CASTING          ; stuck: Hex's repulsion blasts it out
BEQ UIDraw
LDA V_FORM
BEQ UIDraw
LDA V_T6
CMP #48
BCS UIDraw
LDA #$01
STA V_ITST
LDA #130               ; it flies up...
STA V_ITY
JSR SndOuch
LDA #C_M_FREED
JSR PrintMsg
JMP UIDraw
UIFalling:
LDA V_ITY              ; ...and falls back to the ground
CMP #170
BCS UIGround
INC V_ITY
JMP UIDraw
UIGround:
LDA V_ITY              ; on the ground: walk over it
CMP #160
BCC UIDraw
LDA V_T6
CMP #6
BCS UIDraw
UIGot:
LDA #$10
JSR SprOff
LDA #$00
STA V_ITEM
LDX V_T5
JMP GiveClue
UIDraw:
LDA V_T5
CLC
ADC #C_F_CLUE_PHOTO
STA $07FC
LDX V_T5               ; twinkle: white for 16 frames in 256
LDA T_CLCOL,X
LDY V_FRAME
CPY #$F0
BCC UICol
LDA #$01
UICol:
STA $D02B
LDA V_ITX
JSR SprX
STA $D008
LDA #$10
JSR SetHi
LDA V_FRAME
AND #$10
LSR
LSR
LSR
LSR
CLC
ADC V_ITY
STA $D009
LDA #$10
JMP SprOn

; GiveClue: X = clue. Note it, cheer, show what it says; all six -> the truth.
GiveClue:
STX V_T5
LDA T_BIT,X
ORA V_CLUES
STA V_CLUES
INC V_NCLUE
JSR SndClue
LDX V_T5
LDA T_CLMSG,X
JSR PrintMsg
JSR RefreshClues
LDA V_NCLUE
CMP #C_NCLUES
BCC GCDone
LDA #200
JSR Pause
JMP ShowTruth
GCDone:
RTS

; ---------------------------------------------------------------
; SetupNpc: the person who lives in this room (T_RNPC) -> copy their
; three library blocks into buffers 3-5 and stand them on sprites 5-7.
; UpdateNpc: they bob while they talk to you.
; ---------------------------------------------------------------
SetupNpc:
LDX V_ROOM
LDA T_RNPC,X
STA V_NPC
CMP #$FF
BNE SNOn
LDA #$E0
JMP SprOff
SNOn:
STA V_T6
ASL
CLC
ADC V_T6
STA V_T6               ; npc * 3
TAX
LDA T_NFRM,X
LDY #$03
JSR CopyBlock
LDX V_T6
LDA T_NFRM+1,X
LDY #$04
JSR CopyBlock
LDX V_T6
LDA T_NFRM+2,X
LDY #$05
JSR CopyBlock
LDX V_NPC
LDA T_NCOL,X
STA $D02E
LDA #$00
STA $D02C
STA $D02D
STA V_NPCT
LDA #C_F_NPC_TOP
STA $07FD
LDA #C_F_NPC_BOT
STA $07FE
LDA #C_F_NPC_BODY
STA $07FF
LDX V_ROOM
LDA T_RNPCX,X
STA V_NPCX
JSR SprX
STA $D00A
STA $D00C
STA $D00E
LDA #$E0
JSR SetHi
LDA #C_FLOORY
STA $D00B
STA $D00F
CLC
ADC #21
STA $D00D
LDA #$E0
JMP SprOn

UpdateNpc:
LDA V_NPC
CMP #$FF
BEQ UNDone
LDA V_NPCT
BEQ UNDone
DEC V_NPCT
LDA V_FRAME            ; bob while talking
LSR
LSR
AND #$01
EOR #$FF
SEC
ADC #C_FLOORY
STA $D00B
STA $D00F
CLC
ADC #21
STA $D00D
UNDone:
RTS

; ---------------------------------------------------------------
; UpdateBee (sprite 5): drifts after her and stings (FUN-8). Hex's
; REPULSION blasts it away for good; Sunny's ATTRACTION reels it in!
; (No bees where a person stands: they share sprite 5.)
; ---------------------------------------------------------------
UpdateBee:
LDA V_NPC
CMP #$FF
BNE UBDone
LDA V_BEE
BNE UBOn
LDA #$20
JMP SprOff
UBDone:
RTS
UBOn:
LDA V_STING
BEQ UBNoCool
DEC V_STING
UBNoCool:
LDA V_CASTING
BEQ UBDrift
LDA V_FORM
BEQ UBLove
LDA V_BEEX             ; REPEL: three steps away per frame
CMP V_PX
BCC UBRepL
CLC
ADC #3
STA V_BEEX
CMP #150
BCS UBGone
JMP UBDraw
UBRepL:
SEC
SBC #3
STA V_BEEX
BCC UBGone
CMP #4
BCC UBGone
JMP UBDraw
UBGone:
LDA #$00
STA V_BEE
LDA #6
LDX #3
JSR AddNeed
JSR RefreshBars
JSR SndUse
LDA #C_M_BEEGONE
JSR PrintMsg
LDA #$20
JMP SprOff
UBLove:
LDA V_PREVJOY          ; ATTRACT: it comes for her, fast
CMP #$01
BEQ UBLove2
LDA #C_M_BEELOVE
JSR PrintMsg
UBLove2:
JSR BeeToward
JSR BeeToward
JMP UBSting
UBDrift:
LDA V_STING            ; just stung: back off a little
BEQ UBChase
CMP #30
BCC UBChase
LDA V_BEEX
CMP V_PX
BCC UBBackL
CMP #146
BCS UBBackDone
INC V_BEEX
JMP UBDraw
UBBackL:
CMP #4
BCC UBBackDone
DEC V_BEEX
UBBackDone:
JMP UBDraw
UBChase:
LDA V_FRAME
AND #$01
BNE UBSting
JSR BeeToward
UBSting:
LDA V_STING
BNE UBDraw
LDA V_BEEX
SEC
SBC V_PX
BCS UBAbs
EOR #$FF
ADC #$01
UBAbs:
CMP #5
BCS UBDraw
LDA #100               ; STING!
STA V_STING
LDA #$F8
LDX #3
JSR AddNeedSoft
JSR RefreshBars
JSR SndOuch
LDA V_FORM
CLC
ADC #C_M_OUCH_S
JSR PrintMsg
UBDraw:
LDA V_FRAME
LSR
LSR
AND #$01
CLC
ADC #C_F_BEE_A
STA $07FD
LDA #$07
STA $D02C
LDA V_BEEX
JSR SprX
STA $D00A
LDA #$20
JSR SetHi
LDA V_FRAME
LSR
LSR
LSR
AND #$03
CLC
ADC V_BEEY
STA $D00B
LDA #$20
JMP SprOn

BeeToward:
LDA V_BEEX
CMP V_PX
BEQ BTDone
BCS BTLeft
INC V_BEEX
RTS
BTLeft:
DEC V_BEEX
BTDone:
RTS
"""

BLOCKS["CLOCK"] = """
; ---------------------------------------------------------------
; ClockTick: every 150 frames (3 s) = 10 game minutes.
; Each hour the needs drop a little (T_DECAY) and the sky changes.
; ---------------------------------------------------------------
ClockTick:
LDA V_SLEEPING         ; the clock stands still while she sleeps
BEQ CTRun
RTS
CTRun:
INC V_TICK
LDA V_TICK
CMP #C_TICKS
BCC CTDone
LDA #$00
STA V_TICK
LDA #$01               ; a real-time hour can empty a need (faint);
STA V_HARD             ; hours spent inside an action stop at 1
JSR AddTime
LDA #$00
STA V_HARD
JMP RefreshClock
CTDone:
RTS

; AddTime: A = how many 10-minute steps pass.
AddTime:
STA V_T3
ATLoop:
LDA V_T3
BEQ ATDone
DEC V_T3
INC V_MIN
LDA V_MIN
CMP #6
BCC ATLoop
LDA #$00
STA V_MIN
JSR NextHour
JMP ATLoop
ATDone:
RTS

NextHour:
INC V_HOUR
LDA V_HOUR
CMP #24
BCC NHDecay
LDA #$00
STA V_HOUR
INC V_DAY
NHDecay:
LDA V_COINCD
BEQ NHCool
DEC V_COINCD
NHCool:
LDX #4
NHNeed:
LDA T_DECAY,X
EOR #$FF
CLC
ADC #$01
STX V_T4
LDY V_HARD
BEQ NHSoft
JSR AddNeed
JMP NHNext
NHSoft:
JSR AddNeedSoft
NHNext:
LDX V_T4
DEX
BPL NHNeed
JSR RefreshBars
JSR SetSky
LDA V_HOUR             ; cafe closing time while she is there
CMP #18
BNE NHWarn
LDA V_ROOM
CMP #C_CAFE
BNE NHWarn
LDA #C_M_CLOSING
JMP PrintMsg
NHWarn:
LDX #$00               ; first need running low -> warning
NHWLoop:
LDA V_NEED,X
CMP #8
BCC NHWShow
INX
CPX #5
BNE NHWLoop
RTS
NHWShow:
LDA T_WARN,X
JSR PrintMsg
JMP SndError

; AddNeed: X = need (0-4), A = signed change. Result clamped 0-48.
AddNeed:
CLC
ADC V_NEED,X
BMI ANZero
CMP #49
BCC ANStore
LDA #48
JMP ANStore
ANZero:
LDA #$00
ANStore:
STA V_NEED,X
RTS

; AddNeedSoft: as AddNeed, but never below 1. Actions, stings, sleep and
; magic can run a need low; only the hourly drop can empty it (faint).
AddNeedSoft:
JSR AddNeed
LDA V_NEED,X
BNE ANSDone
LDA #$01
STA V_NEED,X
ANSDone:
RTS
"""

BLOCKS["ACTIONS"] = """
; ---------------------------------------------------------------
; CheckSpot: which object (if any) is she standing at? When it changes,
; show its prompt (or the room's hint / the clue's hint).
; ---------------------------------------------------------------
CheckSpot:
LDA V_POSE             ; busy: keep the action's message up
BEQ CSFree
RTS
CSFree:
LDA V_PX
CLC
ADC #6
LSR
LSR
STA V_T0               ; her centre column
LDX V_ROOM
LDA T_ROOMOFS,X
TAX
LDY #4
CSLoop:
LDA T_OBJ,X
CMP #$FF
BEQ CSNone
LDA V_T0
CMP T_OBJ,X
BCC CSNext
LDA T_OBJ+1,X
CMP V_T0
BCC CSNext
LDA T_OBJ+2,X
JMP CSFound
CSNext:
INX
INX
INX
DEY
BNE CSLoop
CSNone:
LDA #$FF
CSFound:
CMP V_OBJ
BEQ CSSame
STA V_OBJ
CMP #$FF
BEQ CSHint
TAX
LDA T_ACTOFS,X
TAX
LDA T_ACT+10,X
JMP PrintMsg
CSHint:
LDX V_ITEM             ; a clue here? its hint, else the room's
BEQ CSRoom
LDA T_CLHINT-1,X
JMP PrintMsg
CSRoom:
LDX V_ROOM
LDA T_HINT,X
JMP PrintMsg
CSSame:
RTS

; ---------------------------------------------------------------
; DoAction (FIRE): use the object she stands at. The action table gives
; need changes, the price, the time it takes and the messages; special
; actions (sleep, eat, groceries, work, talk) add their own rules.
; ---------------------------------------------------------------
DoAction:
LDA V_OBJ
CMP #C_A_SLEEP
BNE DANotSleep
JMP DoSleep
DANotSleep:
TAX
LDA T_ACTOFS,X
STA V_T2               ; T2 = offset of this action's row
TAX
LDA T_ACT+9,X
CMP #C_SP_EAT
BNE DANotEat
LDA V_BAGS
BNE DAEatOk
LDA #C_M_EMPTY
JMP DAFail
DAEatOk:
DEC V_BAGS
JMP DAPay
DANotEat:
CMP #C_SP_WORK
BNE DAPay
LDA V_HOUR
CMP #8
BCC DAClosed
CMP #18
BCS DAClosed
LDA V_NEED1
CMP #10
BCS DAPay
LDA #C_M_TOOTIRED
JMP DAFail
DAClosed:
LDA #C_M_CLOSED
JMP DAFail
DAPay:
LDX V_T2
LDA T_ACT+5,X
BEQ DANeeds
JSR HaveMoney
BCS DAPayOk
LDA #C_M_NOMONEY
JMP DAFail
DAPayOk:
LDX V_T2
LDA T_ACT+5,X
JSR SubMoney
DANeeds:
LDA #$00
STA V_T4
LDA V_T2
PHA
DANLoop:
LDX V_T2               ; need T4's column, then step to the next
LDA T_ACT,X
LDX V_T4
JSR AddNeedSoft
LDA V_T2
CLC
ADC #C_NACT
STA V_T2
INC V_T4
LDA V_T4
CMP #5
BNE DANLoop
PLA
STA V_T2
LDX V_OBJ              ; act it out
JSR StartPose
LDX V_T2
LDA T_ACT+9,X
CMP #C_SP_TALK
BNE DANotTalk
JMP DoTalk
DANotTalk:
CMP #C_SP_GROCERY
BNE DANotGroc
LDA V_BAGS
CLC
ADC #3
CMP #10
BCC DAGrocOk
LDA #9
DAGrocOk:
STA V_BAGS
JMP DATime
DANotGroc:
CMP #C_SP_WORK
BNE DATime
JSR DoWork
DATime:
LDX V_T2
LDA T_ACT+6,X
JSR AddTime
JSR SndUse
LDX V_T2
LDA V_FORM
BNE DAHexMsg
LDA T_ACT+7,X
JMP DAMsg
DAHexMsg:
LDA T_ACT+8,X
DAMsg:
JSR PrintMsg
JSR RefreshHud
LDA V_JOBLV            ; the fifth job level is the dream come true
CMP #5
BCC DADone
JMP WinGame
DADone:
RTS
DAFail:
JSR PrintMsg
JMP SndError

; DoTalk: chat with the person here. Gran hands over the baby photo the
; first time; Miss Page has the old newspaper once you hold five clues.
; Otherwise they say their next line (four each, in turn).
DoTalk:
LDX V_T2
LDA T_ACT+11,X
STA V_T6               ; who
LDA #60
STA V_NPCT             ; they bob while they talk
LDX V_T2
LDA T_ACT+6,X
JSR AddTime
JSR RefreshHud
LDA V_T6
CMP #C_NPC_GRAN
BNE DTNotGran
LDA V_CLUES
AND #$01
BNE DTLine
LDX #$00
JMP GiveClue
DTNotGran:
CMP #C_NPC_PAGE
BNE DTLine
LDA V_CLUES
AND #$20
BNE DTLine
LDA V_NCLUE
CMP #5
BCC DTLine
LDX #$05
JMP GiveClue
DTLine:
JSR SndUse
LDX V_T6
LDA V_TALK,X           ; this line...
CLC
ADC T_NMSG,X
PHA
LDA V_TALK,X           ; ...and the next one next time
CLC
ADC #$01
AND #$03
STA V_TALK,X
PLA
JMP PrintMsg

; DoWork: pay the wage (+tips for Sunny), job XP (Hex works double hard),
; promotion every 6 XP. No XP when scruffy (WASH low).
DoWork:
LDX V_JOBLV
LDA T_WAGE,X
LDX V_FORM
BNE DWPay
CLC
ADC #4                 ; Sunny's tips
DWPay:
JSR AddMoney
LDA V_NEED2
CMP #12
BCS DWXp
PLA                    ; skip the normal result message
PLA
LDX V_T2
LDA T_ACT+6,X
JSR AddTime
JSR RefreshHud
LDA #C_M_SCRUFFY
JSR PrintMsg
JMP SndError
DWXp:
INC V_JOBXP
LDA V_FORM
BEQ DWCheck
INC V_JOBXP
DWCheck:
LDA V_JOBXP
CMP #6
BCC DWDone
LDA #$00
STA V_JOBXP
INC V_JOBLV
PLA                    ; promotion replaces the normal message
PLA
LDX V_T2
LDA T_ACT+6,X
JSR AddTime
JSR RefreshHud
JSR SndPromote
LDX V_JOBLV
LDA T_PROMO,X
JSR PrintMsg
LDA V_JOBLV
CMP #5
BCC DWDone
LDA #150
JSR Pause
JMP WinGame
DWDone:
RTS

; DoSleep: in bed at night (20:00-5:59) or when very tired: sleep till
; 7:00 next morning, REST full. Otherwise just a nap. Either way she lies
; in bed (the LIE pose) with a Zzz; the clock stands still while she sleeps.
DoSleep:
LDA V_HOUR
CMP #20
BCS DSSleep
CMP #6
BCC DSSleep
LDA V_NEED1
CMP #16
BCC DSSleep
LDA #12
LDX #1
JSR AddNeedSoft
LDA #6
JSR AddTime
JSR SndUse
LDA #C_M_NAP
JSR PrintMsg
JSR RefreshHud
LDX #C_A_SLEEP
JMP StartPose
DSSleep:
JSR SndSleep
LDA #$00
STA V_COIN
STA V_BEE
LDA $D015              ; no coin or bee while she sleeps
AND #$0F
STA $D015
LDX #C_A_SLEEP
JSR StartPose
LDA #C_SLEEPT
STA V_POSET
LDA #$01
STA V_SLEEPING
LDA #$06               ; night sky
STA V_SKYCOL
LDA #C_M_SLEEPING
JMP PrintMsg

; WakeUp: the night is over (the LIE pose ended).
WakeUp:
LDA #$00
STA V_SLEEPING
LDA V_HOUR
CMP #7
BCC WUSameDay
INC V_DAY
WUSameDay:
LDA #7
STA V_HOUR
LDA #$00
STA V_MIN
STA V_TICK
LDA #48
STA V_NEED1
LDA #$F6
LDX #0
JSR AddNeedSoft
LDA #$F8
LDX #2
JSR AddNeedSoft
JSR SetSky
JSR RefreshHud
LDX V_FORM
LDA #C_M_S_SLEEP
CPX #$00
BEQ WUMsg
LDA #C_M_H_SLEEP
WUMsg:
JMP PrintMsg

; Pause: A = frames to wait (music keeps playing).
Pause:
STA V_T3
PLoop:
JSR FrameTick
DEC V_T3
BNE PLoop
RTS

; CheckFaint: a need at zero -> she faints, wakes in bed 4 hours later.
CheckFaint:
LDX #4
CFLoop:
LDA V_NEED,X
BEQ CFFaint
DEX
BPL CFLoop
RTS
CFFaint:
JSR SndOuch
LDA #C_M_FAINT
JSR PrintMsg
LDA #$00
STA $D015
STA V_POSE
STA V_SLEEPING
STA V_JUMP
LDA #120
JSR Pause
LDA #24                ; 4 hours pass while she recovers...
JSR AddTime
LDX #4                 ; ...then she wakes with every need at 16+
CFFix:
LDA V_NEED,X
CMP #16
BCS CFOk
LDA #16
STA V_NEED,X
CFOk:
DEX
BPL CFFix
LDA #10
JSR HaveMoney
BCC CFBroke
LDA #10
JSR SubMoney
JMP CFHome
CFBroke:
LDA #$00
STA V_MLO
CFHome:
LDA #C_M_FAINT
JSR PrintMsg
LDA #$07
STA $D015
LDA #C_BEDROOM         ; she wakes up in the bedroom
STA V_ROOM
LDA #40
STA V_PX
JSR RefreshHud
LDA #$FF
STA V_OBJ              ; keep the faint message up
LDX #$FF
TXS
JMP EnterRoomKeep
"""

BLOCKS["HUD"] = """
; ---------------------------------------------------------------
; MONEY is two base-100 bytes (MHI = hundreds of $, MLO = $0-99).
; ---------------------------------------------------------------
AddMoney:
CLC
ADC V_MLO
CMP #100
BCC AMStore
SBC #100
INC V_MHI
LDX V_MHI
CPX #100
BCC AMStore
LDA #99
STA V_MHI
AMStore:
STA V_MLO
RTS

SubMoney:
STA V_T0
LDA V_MLO
SEC
SBC V_T0
BCS SMStore
ADC #100
DEC V_MHI
SMStore:
STA V_MLO
RTS

; HaveMoney: A = price (< $100) -> carry set when she can pay.
HaveMoney:
STA V_T0
LDA V_MHI
BNE HMYes
LDA V_MLO
CMP V_T0
RTS
HMYes:
SEC
RTS

; PrintMsg: A = message number -> bottom row, in its colour.
PrintMsg:
TAX
LDA T_MSGLO,X
STA $56
LDA T_MSGHI,X
STA $57
LDA T_MSGCOL,X
STA V_T0
LDY #$00
PMLoop:
LDA ($56),Y            ; 0 ends the message...
BEQ PMPad
STA """ + "$%04X" % screen(24, 0) + """,Y
LDA V_T0
STA """ + "$%04X" % (COLRAM + 24 * 40) + """,Y
INY
CPY #40
BNE PMLoop
RTS
PMPad:
LDA #$20               ; ...and spaces fill the rest of the line
STA """ + "$%04X" % screen(24, 0) + """,Y
INY
CPY #40
BNE PMPad
RTS

; RefreshHud: every HUD field (the HUD nodes give the field routines).
RefreshHud:
JSR RefreshBars
JSR RefreshMoney
JSR RefreshClock
JSR RefreshNames
JSR RefreshClues
LDA V_JOBLV
JSR """ + hud_bot("JOB") + """
LDA V_BAGS
JMP """ + hud_bot("BAGS") + """

RefreshClues:
LDA V_NCLUE
JMP """ + hud_bot("CLUE") + """

RefreshBars:
LDA V_NEED
LSR
LSR
LSR
JSR """ + hud_bot("FOOD") + """
LDA V_NEED1
LSR
LSR
LSR
JSR """ + hud_bot("REST") + """
LDA V_NEED2
LSR
LSR
LSR
JSR """ + hud_bot("WASH") + """
LDA V_NEED3
LSR
LSR
LSR
JSR """ + hud_bot("FUN") + """
LDA V_NEED4
LSR
LSR
LSR
JMP """ + hud_bot("CHAT") + """

RefreshMoney:
LDA V_MHI
JSR """ + hud_top("MHI") + """
LDA V_MLO
JMP """ + hud_top("MLO") + """

RefreshClock:
LDA V_HOUR
JSR """ + hud_top("HH") + """
LDA V_MIN
JSR """ + hud_top("MM") + """
LDA V_DAY
JMP """ + hud_top("DAY") + """

; RefreshNames: SUNNY/ATTRACT or HEX/REPEL in her colour.
RefreshNames:
LDX V_FORM
LDA T_NAMECOL,X
STA V_T0
TXA
ASL
STA V_T1
ASL
CLC
ADC V_T1
TAX                    ; FORM*6
LDY #$00
RNName:
LDA T_NAMES,X
STA $0400,Y
LDA V_T0
STA $D800,Y
INX
INY
CPY #6
BNE RNName
LDA V_FORM
ASL
ASL
ASL
SEC
SBC V_FORM
TAX                    ; FORM*7
LDY #$00
RNPow:
LDA T_POWERS,X
STA $0407,Y
LDA V_T0
STA $D807,Y
INX
INY
CPY #7
BNE RNPow
RTS
"""

DAYS_ROW = 18
BLOCKS["WIN_PREP"] = """
; ---------------------------------------------------------------
; WinGame (job level 5) / ShowTruth (all six clues): sprites off, no
; sky split; the VIC / CLEAR nodes below set the screen up, PrintPage
; draws the page and EndPage adds the day count.
; ---------------------------------------------------------------
LDX #$FF
TXS
LDA #$00
STA $D015
STA V_SPLIT
JSR SndPromote
"""

BLOCKS["WIN_DRAW"] = """
LDX #$01               ; page 1: DREAM COME TRUE
JSR PrintPage
JMP EndPage
"""

BLOCKS["TRUTH_DRAW"] = """
LDX #$02               ; page 2: THE TRUTH
JSR PrintPage
JMP EndPage
"""

BLOCKS["WIN_END"] = """
; ---------------------------------------------------------------
; EndPage: put the day count into the sentence, then FIRE goes back to
; the title.
; ---------------------------------------------------------------
EndPage:
LDA V_DAY              ; days taken -> two digits in the sentence
LDX #$2F
SEC
WEDiv:
INX
SBC #10
BCS WEDiv
ADC #58
STA """ + "$%04X" % screen(DAYS_ROW, 24) + """
CPX #$30               ; no leading zero
BNE WETens
LDX #$20
WETens:
STX """ + "$%04X" % screen(DAYS_ROW, 23) + """
LDA #$07
STA """ + "$%04X" % (COLRAM + DAYS_ROW * 40 + 23) + """
STA """ + "$%04X" % (COLRAM + DAYS_ROW * 40 + 24) + """
LDA #$32
JSR Pause
WERelease:
JSR FrameTick
LDA $DC00
AND #$10
BEQ WERelease
WEWait:
JSR FrameTick
LDA $DC00
AND #$10
BNE WEWait
JMP Title
"""


def resolve(text, tables):
    """Replace V_/T_/C_/Z_ names (optionally +n / -n) with hex."""
    sym = dict(V)
    sym.update(ZP)
    sym["T_TILECOL"] = T_TILECOL_ADDR
    text = re.sub(r"\bT_ACT\+(\d+)", lambda m: "T_ACT+%d" % (int(m.group(1)) * len(ACTIONS)), text)
    for k, (a, _) in tables.items():
        sym[k] = a
    for k, v in C.items():
        sym[k] = v
    def rep(m):
        name, off = m.group(1), m.group(2)
        if name not in sym:
            raise KeyError("unknown symbol " + name)
        val = sym[name] + (int(off) if off else 0)
        if name.startswith("C_"):
            return "$%02X" % val
        return ("$%04X" % val) if val > 255 or name.startswith(("V_", "T_")) else "$%02X" % val
    text = re.sub(r"\b((?:V|T|C|Z)_[A-Z0-9_]+)([+-]\d+)?", rep, text)
    # #>T_xxx / #<T_xxx were turned into #>$hhhh: fold them to immediates
    text = re.sub(r"#>\$([0-9A-F]{4})", lambda m: "#$%02X" % (int(m.group(1), 16) >> 8), text)
    text = re.sub(r"#<\$([0-9A-F]{4})", lambda m: "#$%02X" % (int(m.group(1), 16) & 255), text)
    return text
