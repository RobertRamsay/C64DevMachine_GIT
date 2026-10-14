"""POLARITY game data + 6502 code blocks.

Code is written with symbolic names (V_ variables, T_ tables, C_ constants)
which resolve() turns into plain hex, so the project JSON holds ordinary
assembly in the same style as the other bundled templates."""
import re
import font, rooms, sprites

# ------------------------------------------------------------------ memory map
SCREEN, COLRAM = 0x0400, 0xD800
CHR_ACTIVE = 0x3000                 # VIC charset (copied in per room)
SPR_BASE = 0x3800                   # SPRITE_SET (pointer $E0)
TITLE_BMP = 0x4000                  # BITMAP ($4000 bmp, $6000 screen, $63E8 colour)
MAP_BASE = 0x8000                   # 5 x MAP_DATA 40x20 (800 bytes each)
CHR_BASE = 0x9000                   # 5 x CHAR_SET (2K each) $9000-$B7FF
T_TILECOL_ADDR = 0xB800             # 5 x 256 colour tables $B800-$BCFF
SMALL_TABLES = 0xBD00               # small BYTE_DATA tables
VARS = 0xC000
COLPAGE = 0xC100                    # active room colour table (copied in)
MSG_BASE = 0xC200                   # MESSAGES (40 bytes each)
PRINT_TEXT = 0x3D40                 # inline PRINT node texts (after the sprites)

FLOOR_Y = 166                       # sprite Y for the girls
COIN_Y = 108
BEE_Y = 146
FRAMES_PER_10MIN = 100

V = {}
def _vars():
    names = """ROOM PX FACE FORM MOVING JOYID PREVJOY MHI MLO BAGS DAY HOUR MIN TICK
               NEED NEED1 NEED2 NEED3 NEED4 JOBLV JOBXP COIN COINX COINY BEE BEEX BEEY
               CASTING RNG OBJ MUSIC T0 T1 T2 DRAIN SWAPT STING FRAME SKYCOL SPLIT
               COINCD ZZZ HARD SPRX SPRHI T3 T4""".split()
    for i, n in enumerate(names):
        V["V_" + n] = VARS + i
_vars()

ZP = {"Z_SCR": 0x50, "Z_COL": 0x52, "Z_SRC": 0x54, "Z_MSG": 0x56}

# ------------------------------------------------------------------ actions
NEEDS = ["FOOD", "REST", "WASH", "FUN", "CHAT"]
DECAY = [3, 2, 2, 3, 2]
SP_NONE, SP_SLEEP, SP_EAT, SP_GROCERY, SP_WORK, SP_CHAT = range(6)
#           deltas (FOOD REST WASH FUN CHAT)  $   10min  special
ACTIONS = [
 ("SLEEP",   [0, 0, 0, 0, 0],        0,  0, SP_SLEEP),
 ("TV",      [-2, -2, 0, 16, 0],     0,  6, SP_NONE),
 ("EAT",     [24, 0, 0, 2, 0],       0,  3, SP_EAT),
 ("SHOWER",  [0, 0, 48, 2, 0],       0,  2, SP_NONE),
 ("BENCH",   [0, 6, 0, 2, 0],        0,  3, SP_NONE),
 ("PHONE",   [0, 0, 0, 2, 16],       1,  3, SP_NONE),
 ("GROCERY", [0, 0, 0, 0, 0],        10, 2, SP_GROCERY),
 ("SWEETS",  [8, 0, 0, 8, 0],        3,  1, SP_NONE),
 ("OUTFIT",  [0, 0, 0, 30, 8],       30, 3, SP_NONE),
 ("WORK",    [-6, -10, -8, -6, 6],   0,  12, SP_WORK),
 ("COFFEE",  [2, 12, 0, 0, 2],       2,  1, SP_NONE),
 ("SWING",   [-2, -4, -2, 16, 0],    0,  6, SP_NONE),
 ("SPLASH",  [0, 0, 12, 6, 0],       0,  2, SP_NONE),
 ("CHAT",    [0, 0, 0, 4, 20],       0,  6, SP_CHAT),
]
ACT_ID = {a[0]: i for i, a in enumerate(ACTIONS)}

# ------------------------------------------------------------------ messages
WHITE, YELLOW, CYAN, GREEN, LRED = 1, 7, 3, 5, 2
MSGS = []          # (name, text, colour)
def msg(name, text, colour=WHITE):
    assert len(text) <= 40, (name, len(text))
    MSGS.append((name, text, colour))

msg("BLANK", "")
msg("NOTHING", "NOTHING TO DO HERE. TRY ANOTHER SPOT.")
msg("HINT0", " HOME SWEET HOME!     WALK RIGHT TO GO >", CYAN)
msg("HINT1", "< HOME          THE STREET        SHOP >", CYAN)
msg("HINT2", "< STREET        SUPER SHOP        CAFE >", CYAN)
msg("HINT3", "< SHOP           THE CAFE         PARK >", CYAN)
msg("HINT4", "< CAFE           THE PARK", CYAN)
PROMPTS = {
 "SLEEP": "~ UP: GO TO BED              REST+",
 "TV": "~ UP: WATCH TV               FUN+",
 "EAT": "~ UP: RAID THE FRIDGE        FOOD+",
 "SHOWER": "~ UP: TAKE A SHOWER          WASH+",
 "BENCH": "~ UP: SIT ON THE BENCH       REST+",
 "PHONE": "~ UP: PHONE GRAN  $1         CHAT+",
 "GROCERY": "~ UP: GROCERIES  $10         3 BAGS",
 "SWEETS": "~ UP: BUY SWEETS  $3     FOOD+ FUN+",
 "OUTFIT": "~ UP: NEW OUTFIT  $30        FUN++",
 "WORK": "~ UP: WORK A SHIFT  8:00 TO 18:00",
 "COFFEE": "~ UP: BUY A COFFEE  $2       REST+",
 "SWING": "~ UP: PLAY ON THE SWINGS     FUN+",
 "SPLASH": "~ UP: SPLASH IN THE FOUNTAIN WASH+",
 "CHAT": "~ UP: CHAT WITH PIP          CHAT+",
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
 "COFFEE": ("A STRONG COFFEE. BZZZT! WIDE AWAKE!", "BLACK COFFEE, LIKE HEX'S HEART."),
 "SWING": ("WHEEE! HIGHER! HIGHER!", "HEX SWINGS UPSIDE DOWN. WHY NOT."),
 "SPLASH": ("SUNNY SPLASHES ABOUT. REFRESHING!", "HEX MAKES THE FOUNTAIN BUBBLE. HEE!"),
 "CHAT": ("PIP ADORES SUNNY! BEST FRIENDS!", "HEX AND PIP SHARE SPOOKY GOSSIP."),
}
for a in ACTIONS:
    s, h = RESULTS[a[0]]
    msg("S_" + a[0], s, WHITE)
    msg("H_" + a[0], h, WHITE)
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
msg("W_CHAT", "SO LONELY... PHONE GRAN OR SEE PIP!", LRED)
msg("FAINT", "SHE FAINTED! WOKE AT HOME. DOCTOR $10", LRED)
msg("WELCOME", "A NEW LIFE! KEEP ALL FIVE NEEDS HAPPY.", WHITE)
msg("FENCE", "THE PARK FENCE. NO WAY THROUGH.", CYAN)
msg("CLOSING", "THE CAFE IS CLOSING. GOOD WORK TODAY!", CYAN)
MSG_ID = {m[0]: i for i, m in enumerate(MSGS)}
assert MSG_BASE + len(MSGS) * 40 <= 0xD000, len(MSGS)

def msg_codes(text):
    out = []
    for ch in text.ljust(40):
        out.append(30 if ch == '~' else font.screen_code(ch))
    return out

# ------------------------------------------------------------------ tables
SKY = [6, 6, 6, 6, 6, 4, 4, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 10, 4, 6, 6, 6, 6]
DRESS = [2, 4]      # Sunny red, Hex purple (body sprite colour)
HAIR = [7, 0]       # blonde, black
NAMECOL = [7, 4]
SPAWN = [0, 3, 1, 0, 3]     # bit0 coin, bit1 bee
NAMES = ["SUNNY ", "HEX   "]
POWERS = ["ATTRACT", "REPEL  "]
PLACES = ["HOME  ", "STREET", "SHOP  ", "CAFE  ", "PARK  "]
JOB_WAGE = [0, 8, 11, 14, 17, 20]


def build_tables(map_addrs, chr_addrs):
    """name -> (address, list of bytes) for every small BYTE_DATA table."""
    t = {}
    addr = SMALL_TABLES
    def add(name, data):
        nonlocal addr
        t[name] = (addr, [d & 255 for d in data])
        addr += len(data)
    add("T_SKY", SKY)
    add("T_DRESS", DRESS)
    add("T_HAIR", HAIR)
    add("T_NAMECOL", NAMECOL)
    add("T_SPAWN", SPAWN)
    add("T_DECAY", DECAY)
    add("T_MAPLO", [a & 255 for a in map_addrs])
    add("T_MAPHI", [a >> 8 for a in map_addrs])
    add("T_CHRHI", [a >> 8 for a in chr_addrs])
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
    add("T_ROOMOFS", [0, 12, 24, 36, 48])
    # per action: d0..d4, cost, time, msgS, msgH, special, prompt, pad
    act = []
    for name, d, cost, tm, sp in ACTIONS:
        act += [x & 255 for x in d] + [cost, tm, MSG_ID["S_" + name], MSG_ID["H_" + name], sp, MSG_ID["P_" + name], 0]
    add("T_ACT", act)
    add("T_ACTOFS", [i * 12 for i in range(len(ACTIONS))])
    add("T_MSGLO", [(MSG_BASE + i * 40) & 255 for i in range(len(MSGS))])
    add("T_MSGHI", [(MSG_BASE + i * 40) >> 8 for i in range(len(MSGS))])
    add("T_MSGCOL", [m[2] for m in MSGS])
    add("T_WARN", [MSG_ID["W_" + n] for n in NEEDS])
    add("T_HINT", [MSG_ID["HINT%d" % i] for i in range(5)])
    add("T_MAGCOL", [10, 14])
    add("T_PROMO", [0, 0, MSG_ID["PROMO2"], MSG_ID["PROMO3"], MSG_ID["PROMO4"], MSG_ID["PROMO5"]])
    assert addr <= 0xC000, hex(addr)
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
}
for n, i in sprites.INDEX.items():
    C["C_F_" + n] = (SPR_BASE // 64 + i) & 255
for k, v in MSG_ID.items():
    C["C_M_" + k] = v
C["C_A_SLEEP"] = ACT_ID["SLEEP"]
C["C_A_CHAT"] = ACT_ID["CHAT"]
for i, n in enumerate(["NONE", "SLEEP", "EAT", "GROCERY", "WORK", "CHAT"]):
    C["C_SP_" + n] = i

def screen(row, col):
    return SCREEN + row * 40 + col


BLOCKS = {}

BLOCKS["BOOT"] = """
; ---------------------------------------------------------------
; BOOT - runs once after SYSTEM INIT.
; Bank BASIC out ($01=$36): the charsets/maps/texts above $A000 are RAM.
; Quiet the CIA timer interrupts: only our raster interrupts run.
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
JMP Title
"""

BLOCKS["TITLE_IRQ"] = """
; ---------------------------------------------------------------
; TITLE: the picture, the tune and the SFX player are set up above.
; Start the raster interrupt chain (IrqMusic at line 251 plays the tune
; and SFX every frame), then hold the title screen.
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
; HOW TO PLAY page: copy the home charset (it holds the font) into
; VIC memory, then the VIC / CLEAR / PRINT nodes below draw the page.
; ---------------------------------------------------------------
LDA #$00
STA $D015
STA V_SPLIT
JSR CopyRoomGfx
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
; Reset the sisters' needs, money, clock and job, then walk into HOME.
; ---------------------------------------------------------------
LDA #$00
STA V_ROOM
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
LDA #20
STA V_MLO
LDA #$01
STA V_DAY
STA V_JOBLV
STA V_BAGS
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
LDA #$03               ; only the girl (hair + body) is on
STA $D015
LDA $D01C              ; hair = hires, body = multicolour, coin hires
AND #$E2
ORA #$12
STA $D01C
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

BLOCKS["ROOM"] = """
// @asset CHARS_HOME
// @asset CHARS_STREET
// @asset CHARS_SHOP
// @asset CHARS_CAFE
// @asset CHARS_PARK
// @asset MAP_HOME
// @asset MAP_STREET
// @asset MAP_SHOP
// @asset MAP_CAFE
// @asset MAP_PARK
; (these lines tell the build to include every place's charset and map:
;  this block copies them in itself, no node marks them as used)
; ---------------------------------------------------------------
; ENTER ROOM: blank the screen, copy this place's charset + colours,
; draw its 40x20 map into rows 1-20, name it, spawn a coin / bee.
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
JSR SpawnThings
JSR SetSky
JSR FrameTick
LDA $D011
ORA #$10
STA $D011
JMP MainLoop

; CopyRoomGfx: this room's CHAR_SET -> $3000 (2K), its colour table -> $C100.
CopyRoomGfx:
LDX V_ROOM
LDA T_CHRHI,X
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
LDA V_ROOM
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

; DrawRoom: map (40x20 chars) -> screen rows 1-20, colour from the table.
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
LDA #20
STA V_T0
DRRow:
LDY #$00
DRCol:
LDA ($54),Y
STA ($50),Y
TAX
LDA $C100,X
STA ($52),Y
INY
CPY #40
BNE DRCol
LDA $54
CLC
ADC #40
STA $54
BCC DRSrc
INC $55
DRSrc:
LDA $50
CLC
ADC #40
STA $50
STA $52
BCC DRDst
INC $51
INC $53
DRDst:
DEC V_T0
BNE DRRow
RTS

; PlaceName: 6-char place name into the top status row.
PlaceName:
LDA V_ROOM
ASL
STA V_T0
ASL
CLC
ADC V_T0
TAX
LDY #$00
PNLoop:
LDA T_PLACES,X
STA """ + "$%04X" % screen(0, 16) + """,Y
LDA #$03
STA """ + "$%04X" % (COLRAM + 16) + """,Y
INX
INY
CPY #6
BNE PNLoop
RTS

; SpawnThings: maybe a floating coin (street, shop, park) and a bee
; (street, park, daytime). Coins have a 2 hour cooldown after a catch.
SpawnThings:
LDA #$00
STA V_COIN
STA V_BEE
LDX V_ROOM
LDA T_SPAWN,X
STA V_T1
AND #$01
BEQ STBee
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
; Per-frame update: clock, the girl, magic, coin, bee, prompts, faint.
; ---------------------------------------------------------------
JSR ClockTick
JSR DrawGirl
JSR DrawMagic
JSR UpdateCoin
JSR UpdateBee
JSR CheckSpot
JSR CheckFaint
"""

BLOCKS["JOY"] = """
; ---------------------------------------------------------------
; JOYSTICK HANDLERS (JSR'd by the JOYSTICK node; each must RTS).
; JOYID / PREVJOY give edge detection for UP and DOWN.
; ---------------------------------------------------------------
JoyFire:
LDA #$01
STA V_JOYID
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

JoyUp:
LDA #$02
STA V_JOYID
LDA V_PREVJOY
CMP #$02
BEQ JUDone
JMP DoAction
JUDone:
RTS

JoyDown:
LDA #$03
STA V_JOYID
LDA V_PREVJOY
CMP #$03
BEQ JDDone
LDA V_FORM             ; SWAP SISTERS
EOR #$01
STA V_FORM
LDA #30
STA V_SWAPT
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
BEQ JLWall
DEC V_ROOM
LDA #145
STA V_PX
JMP EnterRoom
JLWall:
RTS

JoyRight:
LDA #$05
STA V_JOYID
LDA #$00
STA V_FACE
LDA #$01
STA V_MOVING
LDA V_PX
CMP #146
BCS JREdge
INC V_PX
LDA V_ROOM             ; just reached the park fence?
CMP #$04
BNE JRDone
LDA V_PX
CMP #146
BNE JRDone
LDA #C_M_FENCE
JMP PrintMsg
JREdge:
LDA V_ROOM
CMP #$04
BEQ JRFence
INC V_ROOM
LDA #$02
STA V_PX
JMP EnterRoom
JRFence:
LDA V_PREVJOY
CMP #$05
BEQ JRDone
LDA #C_M_FENCE
JMP PrintMsg
JRDone:
RTS

JoyNone:
RTS
"""

BLOCKS["SPRITES"] = """
; ---------------------------------------------------------------
; DrawGirl: sprite 0 = hair (hires), sprite 1 = body (multicolour).
; X = PX*2+24 (9 bits). Body frame: walk A/B, cast pose, facing L/R.
; ---------------------------------------------------------------
DrawGirl:
LDA V_PX
JSR SprX
STA $D000
STA $D002
LDA $D010
AND #$FC
LDX V_SPRHI
BEQ DGHi
ORA #$03
DGHi:
STA $D010
LDA #C_FLOORY
STA $D001
STA $D003
LDA V_FACE
ASL
STA V_T0               ; 0 right, 2 left
LDA V_CASTING
BEQ DGWalk
LDA V_FACE
CLC
ADC #C_F_BODY_R_CAST
JMP DGBody
DGWalk:
LDA V_MOVING
BEQ DGStand
LDA V_FRAME
LSR
LSR
LSR
AND #$01
CLC
ADC V_T0
JMP DGBodyA
DGStand:
LDA V_T0
DGBodyA:
CLC
ADC #C_F_BODY_R_A
DGBody:
STA $07F9
LDA V_FORM
ASL
CLC
ADC V_FACE
CLC
ADC #C_F_SUNNY_R
STA $07F8
LDX V_FORM
LDA T_HAIR,X
STA $D027
LDA T_DRESS,X
STA $D028
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

; SetHi: A = sprite bit mask, SPRHI -> set or clear that bit of $D010.
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
; DrawMagic (sprite 2): the swap sparkle, the sleep Zzz, or the magic
; itself in front of her while FIRE is held - hearts for Sunny's
; ATTRACTION, zaps for Hex's REPULSION.
; ---------------------------------------------------------------
DrawMagic:
LDA V_SWAPT
BEQ DMNoSwap
DEC V_SWAPT
LDA V_FRAME
LSR
LSR
AND #$01
CLC
ADC #C_F_STAR_A
STA $07FA
LDA #$01
STA $D029
LDA V_PX
JMP DMShow
DMNoSwap:
LDA V_CASTING
BNE DMCast
LDA #$04
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
STA $07FA
LDX V_FORM
LDA T_MAGCOL,X
STA $D029
LDA V_FACE
BNE DMLeft
LDA V_PX
CLC
ADC #10
JMP DMShow
DMLeft:
LDA V_PX
SEC
SBC #10
BCS DMShow
LDA #$00
DMShow:
JSR SprX
STA $D004
LDA #$04
JSR SetHi
LDA #C_FLOORY
STA $D005
LDA #$04
JMP SprOn
"""

BLOCKS["THINGS"] = """
; ---------------------------------------------------------------
; UpdateCoin (sprite 3): it floats out of reach. Sunny's ATTRACTION pulls
; it down to her (+$5); Hex's REPULSION pushes it away for good.
; ---------------------------------------------------------------
UpdateCoin:
LDA V_COIN
BNE UCOn
LDA #$08
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
CMP #160
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
LDA #$08
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
CMP #150
BCC UCDraw
LDA V_COINX
SEC
SBC V_PX
BCS UCAbs
EOR #$FF
ADC #$01
UCAbs:
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
LDA #$08
JMP SprOff
UCDraw:
LDA V_FRAME
LSR
LSR
LSR
AND #$01
CLC
ADC #C_F_COIN_A
STA $07FB
LDA #$07
STA $D02A
LDA V_COINX
JSR SprX
STA $D006
LDA #$08
JSR SetHi
LDA V_FRAME
AND #$10
LSR
LSR
LSR
LSR
CLC
ADC V_COINY
STA $D007
LDA #$08
JMP SprOn

; ---------------------------------------------------------------
; UpdateBee (sprite 4): drifts after her and stings (FUN-8). Hex's
; REPULSION blasts it away for good; Sunny's ATTRACTION reels it in!
; ---------------------------------------------------------------
UpdateBee:
LDA V_BEE
BNE UBOn
LDA #$10
JMP SprOff
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
LDA #$10
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
STA $07FC
LDA #$07
STA $D02B
LDA V_BEEX
JSR SprX
STA $D008
LDA #$10
JSR SetHi
LDA V_FRAME
LSR
LSR
LSR
AND #$03
CLC
ADC V_BEEY
STA $D009
LDA #$10
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
; ClockTick: every 100 frames (2 s) = 10 game minutes.
; Each hour the needs drop a little (T_DECAY) and the sky changes.
; ---------------------------------------------------------------
ClockTick:
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
CMP #3
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
; show its prompt (or the room hint) on the message line.
; ---------------------------------------------------------------
CheckSpot:
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
LDX V_ROOM
LDA T_HINT,X
JMP PrintMsg
CSSame:
RTS

; ---------------------------------------------------------------
; DoAction (UP): use the object she stands at. The action table gives
; need changes, the price, the time it takes and the messages; special
; actions (sleep, eat, groceries, work, chat) add their own rules.
; ---------------------------------------------------------------
DoAction:
LDA V_OBJ
CMP #$FF
BNE DAHave
LDA #C_M_NOTHING
JMP PrintMsg
DAHave:
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
DANLoop:
LDA V_T2
CLC
ADC V_T4
TAX
LDA T_ACT,X
LDX V_T4
JSR AddNeedSoft
INC V_T4
LDA V_T4
CMP #5
BNE DANLoop
LDX V_T2
LDA T_ACT+9,X
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
CMP #C_SP_CHAT
BNE DANotChat
LDA V_FORM             ; Sunny's attraction: everyone loves her
BNE DATime
LDA #8
LDX #4
JSR AddNeedSoft
JMP DATime
DANotChat:
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
; 7:00 next morning, REST full. Otherwise just a nap.
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
JMP RefreshHud
DSSleep:
JSR SndSleep
LDA #$00
STA V_COIN
STA V_BEE
LDA #$00
STA $D015              ; hide the girl: she is under the covers
LDA #C_F_ZZZ
STA $07FA
LDA #$00
STA $D029
LDA #20
JSR SprX
STA $D004
LDA #$04
JSR SetHi
LDA #132
STA $D005
LDA #$04
JSR SprOn
LDA #$06
STA V_SKYCOL
LDA #180
JSR Pause
LDA V_HOUR
CMP #7
BCC DSSameDay
INC V_DAY
DSSameDay:
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
LDA #$03
STA $D015
JSR SetSky
JSR RefreshHud
LDX V_FORM
LDA #C_M_S_SLEEP
CPX #$00
BEQ DSMsg
LDA #C_M_H_SLEEP
DSMsg:
JMP PrintMsg

; Pause: A = frames to wait (music keeps playing).
Pause:
STA V_T3
PLoop:
JSR FrameTick
DEC V_T3
BNE PLoop
RTS

; CheckFaint: a need at zero -> she faints, wakes at home 4 hours later.
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
LDA #$03
STA $D015
LDA #$00
STA V_ROOM
LDA #52
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
LDY #39
PMLoop:
LDA ($56),Y
STA """ + "$%04X" % screen(24, 0) + """,Y
LDA V_T0
STA """ + "$%04X" % (COLRAM + 24 * 40) + """,Y
DEY
BPL PMLoop
RTS

; RefreshHud: every HUD field (the HUD nodes give the field routines).
RefreshHud:
JSR RefreshBars
JSR RefreshMoney
JSR RefreshClock
JSR RefreshNames
LDA V_JOBLV
JSR """ + hud_bot("JOB") + """
LDA V_BAGS
JMP """ + hud_bot("BAGS") + """

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

BLOCKS["WIN_END"] = """
; ---------------------------------------------------------------
; DREAM COME TRUE: the PRINT nodes above wrote the page; add the day
; count, then FIRE goes back to the title.
; ---------------------------------------------------------------
LDA V_DAY              ; days taken -> two digits in the sentence
LDX #$2F
SEC
WEDiv:
INX
SBC #10
BCS WEDiv
ADC #58
STA """ + "$%04X" % screen(14, 24) + """
CPX #$30               ; no leading zero
BNE WETens
LDX #$20
WETens:
STX """ + "$%04X" % screen(14, 23) + """
LDA #$07
STA """ + "$%04X" % (COLRAM + 14 * 40 + 23) + """
STA """ + "$%04X" % (COLRAM + 14 * 40 + 24) + """
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

BLOCKS["WIN_PREP"] = """
; ---------------------------------------------------------------
; WinGame: the sisters own the cafe! Sprites off, no sky split; the
; VIC / CLEAR / PRINT nodes below draw the ending.
; ---------------------------------------------------------------
LDX #$FF
TXS
LDA #$00
STA $D015
STA V_SPLIT
JSR SndPromote
"""



def resolve(text, tables):
    """Replace V_/T_/C_/Z_ names (optionally +n) with hex."""
    sym = dict(V)
    sym.update(ZP)
    for k, (a, _) in tables.items():
        sym[k] = a
    for k, v in C.items():
        sym[k] = v
    def rep(m):
        name, off = m.group(1), m.group(2)
        if name not in sym:
            raise KeyError("unknown symbol " + name)
        val = sym[name] + (int(off[1:]) if off else 0)
        if name.startswith("C_"):
            return "$%02X" % val
        return ("$%04X" % val) if val > 255 or name.startswith(("V_", "T_")) else "$%02X" % val
    text = re.sub(r"\b((?:V|T|C|Z)_[A-Z0-9_]+)(\+\d+)?", rep, text)
    # #>T_xxx / #<T_xxx were turned into #>$hhhh: fold them to immediates
    text = re.sub(r"#>\$([0-9A-F]{4})", lambda m: "#$%02X" % (int(m.group(1), 16) >> 8), text)
    text = re.sub(r"#<\$([0-9A-F]{4})", lambda m: "#$%02X" % (int(m.group(1), 16) & 255), text)
    return text
