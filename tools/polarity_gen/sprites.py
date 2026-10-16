"""POLARITY sprites.

The sisters (and the people they meet) are three sprites each:
  * a multicolour body, Y-expanded to 42 lines: skin ($D025), hair ($D026,
    switched when the sisters swap) and the dress (the sprite's own colour);
  * two hires overlays in black on top of it, one for lines 0-20 (head and
    face) and one for lines 21-41 (body and legs): crisp line art over the
    chunky colour fills.
Each pose is drawn once as a 24x42 master ('K' line, 'H' hair, 'S' skin,
'D' dress) facing right; split() derives the three sprites and the game
mirrors them at run time when she faces left. The unique 64-byte blocks
go into SPR_LIB (under the KERNAL ROM); the game copies the current ones
into six buffer sprites in VIC bank 0.

The other sprites live in VIC bank 0 directly (POL_SPRITES, after the six
buffers): coins, bees, magic, the Zzz, bubbles and the six clues."""

SKIN = 10                          # $D025
HAIR = [7, 6]                      # $D026: Sunny blonde, Hex blue-black
DRESS = [2, 4]                     # body sprite colour: Sunny red, Hex purple
NPC_NAMES = ["MO", "GRAN", "PIP", "PAGE"]
NPC_COL = [5, 15, 3, 14]           # Mo's green apron, Gran's grey cardigan, Pip's cyan, Page's lilac
POSES = ["STAND", "WALK", "STEP", "JUMP", "CAST", "SIT_A", "SIT_B", "PHONE", "EAT", "CHEER", "LIE"]
SIDE_POSES = ("WALK", "STEP", "JUMP")    # drawn in profile (side heads)


SUNNY_HEAD = [
 "..............KKK.KKK...",
 "........KKKKKKDDDKDDDK..",
 "......KKHHHHHKKDDDDDK...",
 ".....KHHHHHHHHKKDDKK....",
 "....KHHHKHHHHHKDDKDDK...",
 "...KHHHKHHHHHHHKKHKKK...",
 "..KHHHKHHKHHHHKHHHKHHK..",
 "..KHHKHKKSSSSSSKKHKHHK..",
 ".KHHHKKSSSSSSSSSSKKHHHK.",
 "KHHHHKSSSSSSSSSSSSKHHHHK",
 "KHHHKSSKKSSSSSSKKSSKHHHK",
 "KHHHKSKKKKSSSSKKKKSKHHHK",
 "KHHHKSKKSKSSSSKKSKSKHHHK",
 "KHHHKSKKKKSSSSKKKKSKHHHK",
 "KHHHKSSKKSSSSSSKKSSKHHHK",
 "KHHHKKSSSSSSSSSSSSKKHHHK",
 ".KHHHKSSSSSKKSSSSSKHHHK.",
 ".KHHHHKKSSSSSSSSKKHHHHK.",
 "..KHHK.KKKSSSSKKK.KHHK..",
 "..KHHK....KSSK....KHHK..",
 "...KK.....KSSK.....KK...",
 "..........KSSK..........",
]
HEX_HEAD = [
 "...............KK.......",
 ".............KKDK.......",
 "...........KKDDK........",
 "..........KDDDDK........",
 ".........KDDDDDDK.......",
 "........KDDKKKKDDK......",
 ".KKKKKKKKKKKKKKKKKKKKKK.",
 "..KKHHHHHHHHHHHHHHHHKK..",
 "..KHHHKKKKKKKKKKKKHHHK..",
 "..KHHKSSSSSSSSSSSSKHHK..",
 "..KHHKSSKKSSSSSSKKSKHK..",
 "..KHHKSKKKKSSSSKKKKKHK..",
 "..KHHKSKKSKSSSSKKSKKHK..",
 "..KHHKSKKKKSSSSKKKKKHK..",
 "..KHHKSSKKSSSSSSKKSKHK..",
 "..KHHHKSSSSSSSSSSSSKHK..",
 "..KHHHKSSSSSKKSSSSKHHK..",
 "..KHHHHKKSSSSSSSSKKHHK..",
 "..KHHHHHHKKSSSSKKHHHHK..",
 "..KHHHHHHHKKSSKKHHHHHK..",
 "..KKHHHHHHKSSSSKHHHHKK..",
 "..........KSSK..........",
]

TORSO = [
 "......KKDDDDDDDDKK......",
 ".....KDDDKDDDDKDDDK.....",
 "....KDDDDDKDDKDDDDDK....",
]
SKIRT = [
 "....KKKDDDDDDDDDDKKK....",
 "....KDDDDDDDDDDDDDDK....",
 "...KDDDDDDDDDDDDDDDDK...",
 "..KDDDDDDDDDDDDDDDDDDK..",
 "..KKKKKKKKKKKKKKKKKKKK..",
]
ARMS_DOWN = [
 "...KSKDDDDDKKDDDDDKSK...",
 "...KSKDDDDDDDDDDDDKSK...",
 "...KSKDDDDDDDDDDDDKSK...",
 "...KSKKDDDDDDDDDDKKSK...",
 "...KSSKKKKKKKKKKKKSSK...",
]
LEGS_STAND = [
 "........KSSK.KSSK.......",
 "........KSSK.KSSK.......",
 "........KSSK.KSSK.......",
 "........KSSK.KSSK.......",
 ".......KKKKK.KKKKK......",
 ".......KKKKKK.KKKKKK....",
 "........................",
]
# Walking and jumping are drawn in profile, facing right (mirrored for left).
SUNNY_SIDE = [
 "....KKK.KKK.............",
 "...KDDDKDDDK............",
 "...KDDDDDDDK.KKKKK......",
 "....KDDKDDKKKHHHHHKK....",
 ".....KKKKKHHHHHHHHHHK...",
 "......KHHHHHHHHHHHHHHK..",
 ".....KHHHHHHHHHHHHHHHHK.",
 ".....KHHHHHHHHHHHHHHHHK.",
 "....KHHHHHHHHHHHKHHKHHK.",
 "....KHHHHHHHHHHKSSKSSKK.",
 "....KHHHHHHHHHKSSSSSSSK.",
 "...KHHHHHHHHHKSSSKKSSSK.",
 "...KHHHHHHHHHKSSKKKKSSK.",
 "...KHHHHHHHHHKSSKKSKSSKK",
 "...KHHHHHHHHHKSSKKKKSSSK",
 "...KHHHHHHHHHKSSSKKSSSK.",
 "...KHHHHHHHHHKSSSSSSSK..",
 "..KHHHHHHHHHHKSSSSSKKK..",
 "..KHHHHHHHHHHKKSSSSSSK..",
 "..KHHHHHHHHHHHKKSSSKK...",
 "....KKKKKKKKKKSSKKK.....",
 ".............KSSK.......",
]
HEX_SIDE = [
 "..KK....................",
 "..KDKK..................",
 "...KDDKK................",
 "....KDDDKK..............",
 ".....KDDDDKK............",
 "......KDDDDDKK..........",
 ".....KDDDDDDDDK.........",
 "KKKKKKKKKKKKKKKKKKKKKKK.",
 "..KKHHHHHHHHHHHHHHHHHKK.",
 "...KHHHHHHHHHHHKHHKHHK..",
 "...KHHHHHHHHHHKSSKSSSK..",
 "...KHHHHHHHHHKSSSKKSSSK.",
 "...KHHHHHHHHHKSSKKKKSSK.",
 "...KHHHHHHHHHKSSKKSKSSKK",
 "...KHHHHHHHHHKSSKKKKSSSK",
 "...KHHHHHHHHHKSSSKKSSSK.",
 "...KHHHHHHHHHKSSSSSSSK..",
 "...KHHHHHHHHHKSSSSSKKK..",
 "...KHHHHHHHHHKKSSSSSSK..",
 "...KKHHHHHHHHHKKSSSKK...",
 ".....KKKKKKKKKSSKKK.....",
 ".............KSSK.......",
]
# bodies: 20 rows. Neck at cols 13-16 (KSSK).
SIDE_TORSO = [
 "..........KKDDDDKK......",
 ".........KDDDDDDDDK.....",
 ".........KDDDDKDDDK.....",
]
# open stride: drawn 2 rows short (the game lowers this frame 2 lines,
# so the feet still meet the floor and her head dips: the walking bob)
SIDE_WALK = SIDE_TORSO + [
 ".........KDDDKDDDDK.....",
 "........KDDDKSKDDDK.....",
 "........KDDDKSKDDDK.....",
 "........KDDDDKSKDDK.....",
 "........KKDDDKSSKDK.....",
 "........KKKDDDKSSKKK....",
 ".......KDDDDDDDKKDDDK...",
 "......KDDDDDDDDDDDDDDK..",
 ".....KDDDDDDDDDDDDDDDDK.",
 ".....KKKKKKKKKKKKKKKKKK.",
 "........KSSK....KSSK....",
 ".......KSSK......KSSK...",
 ".....KKKKK........KKKKK.",
 "....KKKKKK........KKKKKK",
 "........................",
 "........................",
 "........................",
]
# legs together (the high point of the step)
SIDE_STEP = SIDE_TORSO + [
 ".........KDDDKDDDDK.....",
 ".........KDDKSKDDDK.....",
 ".........KDDKSKDDDK.....",
 ".........KDDKSKDDDK.....",
 ".........KDDKSSKDDK.....",
 "........KKKDKSSKKKKK....",
 ".......KDDDDDKKDDDDDK...",
 "......KDDDDDDDDDDDDDDK..",
 ".....KDDDDDDDDDDDDDDDDK.",
 ".....KKKKKKKKKKKKKKKKKK.",
 "...........KSSK.........",
 "...........KSSK.........",
 "...........KSSK.........",
 "...........KSSK.........",
 "..........KKKKKK........",
 "..........KKKKKKK.......",
 "........................",
]
# side jump: arms flung up and forward, front knee up, back leg trailing
SIDE_JUMP = [
 "..........KKDDDDKK..KKK.",
 ".........KDDDDDDDDKKSSK.",
 ".........KDDDDKDDDKSSK..",
 ".........KDDDDDDDKSSK...",
 ".........KDDDDDDKSSK....",
 ".........KDDDDDDKKK.....",
 ".........KDDDDDDDDK.....",
 "........KKKDDDDDDKKK....",
 ".......KDDDDDDDDDDDDK...",
 "......KDDDDDDDDDDDDDDK..",
 ".....KDDDDDDDDDDDDDDDDK.",
 ".....KKKKKKKKKKKKKKKKKK.",
 "......KSSK....KSSSSSK...",
 ".....KSSK.....KKKKKSSK..",
 "....KSSK.........KKKKK..",
 "...KKKK..........KKKKKK.",
 "..KKKKK.................",
 "........................",
 "........................",
 "........................",
]

BODIES = {
 "STAND": TORSO + ARMS_DOWN + SKIRT + LEGS_STAND,
 "WALK": SIDE_WALK,
 "STEP": SIDE_STEP,
 "JUMP": SIDE_JUMP,
 "CAST": TORSO[:2] + [
  "....KDDDDDKDDKDDDDDKKKKK",
  "...KSKDDDDDKKDDDDDKSSSSK",
  "...KSKDDDDDDDDDDDDKKKKKK",
  "...KSKDDDDDDDDDDDDK.....",
  "...KSKKDDDDDDDDDDKK.....",
  "...KSSKKKKKKKKKKKK......",
 ] + SKIRT + LEGS_STAND,
 "SIT_A": TORSO + ARMS_DOWN + [
  "....KKKDDDDDDDDDDKKK....",
  "....KDDDDDDDDDDDDDDKKKK.",
  "...KDDDDDDDDDDDDDDDDDDK.",
  "...KKKKKKKKKKKKKKKKKKKK.",
  "...................KSSK.",
  "...................KSSK.",
  "...................KSSK.",
  "...................KSSK.",
  "..................KKKKK.",
  "..................KKKKKK",
  "........................",
  "........................",
 ],
 "SIT_B": TORSO + ARMS_DOWN + [
  "....KKKDDDDDDDDDDKKK....",
  "....KDDDDDDDDDDDDDDKKKK.",
  "...KDDDDDDDDDDDDDDDDDDK.",
  "...KKKKKKKKKKKKKKKKKKKK.",
  "....................KSSK",
  "....................KSSK",
  ".....................KSK",
  ".....................KSK",
  ".....................KKK",
  "......................KK",
  "........................",
  "........................",
 ],
 "PHONE": TORSO + [
  "...KSKDDDDDKKDDDDDKSK...",
  "...KSKDDDDDDDDDDDDKSK...",
  "...KSKDDDDDDDDDDDDKK....",
  "...KSKKDDDDDDDDDDKK.....",
  "...KSSKKKKKKKKKKKK......",
 ] + SKIRT + LEGS_STAND,
 "EAT": TORSO + [
  "...KSKDDDDDKKDDDDKSK....",
  "...KSKDDDDDDDDDDKSK.....",
  "...KSKDDDDDDDDDKSK......",
  "...KSKKDDDDDDDDKK.......",
  "...KSSKKKKKKKKKKK.......",
 ] + SKIRT + LEGS_STAND,
 "CHEER": TORSO + [
  "....KKDDDDDKKDDDDDKK....",
  "....KDDDDDDDDDDDDDDK....",
  "....KDDDDDDDDDDDDDDK....",
  "....KKDDDDDDDDDDDDKK....",
  ".....KKKKKKKKKKKKKK.....",
 ] + SKIRT + LEGS_STAND,
}
# arm pixels that reach into the head rows: (row, col, text)
STAMPS = {
 "PHONE": [(14, 18, "KK"), (15, 17, "KDDK"), (16, 18, "KDDK"), (17, 19, "KSK"), (18, 19, "KSK"),
           (19, 19, "KSK"), (20, 19, "KSK"), (21, 19, "KSK"), (13, 19, "KKK"), (14, 20, "KK")],
 "EAT": [(15, 14, "KKKK"), (16, 13, "KDDDDK"), (17, 13, "KKKKKK"), (18, 15, "KSK"), (19, 15, "KSK"),
         (20, 15, "KSK"), (21, 16, "KSK")],
 "CHEER": [(6, 0, "KK"), (7, 0, "KSK"), (8, 0, "KSK"), (9, 0, "KSK"), (10, 1, "KSK"), (11, 1, "KSK"),
           (12, 1, "KSK"), (13, 2, "KSK"), (14, 2, "KSK"), (15, 2, "KSK"), (16, 2, "KSK"), (17, 2, "KSK"),
           (18, 3, "KSK"), (19, 3, "KSK"), (20, 3, "KSK"), (21, 3, "KSK"),
           (6, 22, "KK"), (7, 21, "KSK"), (8, 21, "KSK"), (9, 21, "KSK"), (10, 20, "KSK"), (11, 20, "KSK"),
           (12, 20, "KSK"), (13, 19, "KSK"), (14, 19, "KSK"), (15, 19, "KSK"), (16, 19, "KSK"), (17, 19, "KSK"),
           (18, 18, "KSK"), (19, 18, "KSK"), (20, 18, "KSK"), (21, 18, "KSK")],
}
LIE_BASE = ["." * 24] * 22 + [
 "........................",
 "..KKKK..................",
 ".KHHHHKK................",
 "KHHHHHHHK...............",
 "KHHKKKKKHK..............",
 "KHKSSSSSKHK.............",
 "KHKSKKSSSKHKKKKKKKKKKKKK",
 "KHKSSSSKKKKDDDDDDDDDDDDK",
 "KHKSKKSSKDDDDDDDDDDDDDDK",
 "KHKSSSSSKDDKDDDDDDKDDDDK",
 ".KHKSSSKKDDDDDDDDDDDDDDK",
 "..KKKKKKDDDDDKDDDDDDDKDK",
 "......KDDDDDDDDDDDDDDDDK",
 "......KKKKKKKKKKKKKKKKKK",
 "........................",
 "........................",
 "........................",
 "........................",
 "........................",
 "........................",
]

FACE = [   # rows 8-17 shared face: eyes + mouth line (talk variant swaps row 16)
 "..KKKSSSSSSSSSSSSSSKKK..",
 "...KSSKKSSSSSSSKKSSK....",
]
MO = [   # barista: black quiff, green apron over a white-less shirt (skin arms)
 "........................",
 "........KKKKKKKK........",
 "......KKKKKKKKKKKK......",
 ".....KKKKKKKKKKKKKKK....",
 "....KKKKKKKKKKKKKKKKK...",
 "....KKKKKKKKKKKKKKKKK...",
 "....KKKKSSSSSSKKKKKKK...",
 "....KKKSSSSSSSSSSKKKK...",
 "....KKSSSSSSSSSSSSSKK...",
 "....KKSSKKSSSSSSKKSSK...",
 "....KSSKKKKSSSSKKKKSK...",
 "....KSSKKSKSSSSKKSKSK...",
 "....KSSKKKKSSSSKKKKSK...",
 "....KSSSKKSSSSSSKKSSK...",
 ".....KSSSSSSSSSSSSSK....",
 ".....KSSSSSSSSSSSSSK....",
 "......KSSSSKKKKSSSK.....",
 "......KKSSSSSSSSSKK.....",
 "........KKSSSSSKK.......",
 "..........KSSK..........",
 "..........KSSK..........",
 "......KKKKKSSKKKKK......",
]
GRAN = [
 "..........KKKK..........",
 ".........KDDDDK.........",
 "........KDDKDDDK........",
 ".......KKDDDDDDKK.......",
 "......KDDDDKDDDDDK......",
 ".....KDDDKDDDDKDDDK.....",
 "....KDDDKDDDDDDKDDDK....",
 "....KDDKSSSSSSSSKDDK....",
 "....KDKSSSSSSSSSSKDK....",
 "....KDKSSSSSSSSSSSKDK...",
 "....KKKKKKKSSKKKKKKK....",
 "....KSKSSSKKKKSSSKSK....",
 "....KSKKKKKSSKKKKKSK....",
 "....KSSSSSSSSSSSSSSK....",
 "....KSSSSSSSSSSSSSSK....",
 ".....KSSSSSSSSSSSSK.....",
 "......KSSSKKKKSSSK......",
 "......KKSSSSSSSSKK......",
 "........KKSSSSKK........",
 "..........KSSK..........",
 "..........KSSK..........",
 "......KKKKKSSKKKKK......",
]
PIP = [
 "........................",
 "........KKKKKKKK........",
 "......KKDDDDDDDDKK......",
 ".....KDDDDDKKDDDDDK.....",
 "....KDDDDDDDDDDDDDDK....",
 "....KKKKKKKKKKKKKKKKKKK.",
 "....KKKSSSSSSSSSSSKKKKK.",
 "....KKSSSSSSSSSSSSSKK...",
 "....KSSSSSSSSSSSSSSSK...",
 "....KSSKKSSSSSSKKSSSK...",
 "....KSKKKKSSSSKKKKSSK...",
 "....KSKKSKSSSSKKSKSSK...",
 "....KSKKKKSSSSKKKKSSK...",
 "....KSSKKSSSSSSKKSSSK...",
 ".....KSSSSSSSSSSSSSK....",
 ".....KSSSSSSSSSSSSSK....",
 "......KSSSKKKKSSSSK.....",
 "......KKSSSSSSSSSKK.....",
 "........KKSSSSSKK.......",
 "..........KSSK..........",
 "..........KSSK..........",
 "......KKKKKSSKKKKK......",
]
PAGE = [
 "........KKKKKK..........",
 ".......KKKKKKKK.........",
 "........KKKKKK..........",
 "......KKKKKKKKKK........",
 ".....KKKKKKKKKKKKK......",
 "....KKKKKKKKKKKKKKK.....",
 "....KKKKSSSSSSSSKKKK....",
 "....KKKSSSSSSSSSSKKK....",
 "....KKSSSSSSSSSSSSKK....",
 "....KKKKKKKSSKKKKKKK....",
 "....KKSSSKKKKKSSSKKK....",
 "....KKKKKKKSSKKKKKKK....",
 "....KKSSSSSSSSSSSSKK....",
 "....KKSSSSSSSSSSSSKK....",
 "....KKSSSSSSSSSSSSKK....",
 ".....KSSSSSSSSSSSSK.....",
 "......KSSSKKKKSSSK......",
 "......KKSSSSSSSSKK......",
 "........KKSSSSKK........",
 "..........KSSK..........",
 "..........KSSK..........",
 "......KKKKKSSKKKKK......",
]
NPC_BODY = [
 ".....KDDDDDKKDDDDDDK....",
 "....KDDDDDDKKDDDDDDDK...",
 "...KSKDDDDDDDDDDDDKSK...",
 "...KSKDDDDDDDDDDDDKSK...",
 "...KSKDDDDDDDDDDDDKSK...",
 "...KSKDDDDDDDDDDDDKSK...",
 "...KSSKDDDDDDDDDDKSSK...",
 "....KKKDDDDDDDDDDKKK....",
 "......KDDDDDDDDDDK......",
 "......KDDDDDDDDDDK......",
 "......KDDDDDDDDDDK......",
 "......KDDDDDDDDDDK......",
 "......KKKKKKKKKKKK......",
 ".......KSSK..KSSK.......",
 ".......KSSK..KSSK.......",
 ".......KSSK..KSSK.......",
 ".......KSSK..KSSK.......",
 "......KKKKK..KKKKK......",
 "......KKKKKK.KKKKKK.....",
 "........................",
]
TALK_MOUTH = {16: "......KSSSKSSKSSSK......", 17: "......KKSSSKKSSSKK......"}
COIN_A = [
 "........................",
 "........................",
 "........................",
 ".........######.........",
 ".......##########.......",
 "......####....####......",
 "......###.####.###......",
 ".....####.##....###.....",
 ".....#####.###.####.....",
 ".....####...##.####.....",
 ".....####.####.###......",
 "......###.....####......",
 "......####...####.......",
 ".......##########.......",
 ".........######.........",
]
COIN_B = [
 "........................",
 "........................",
 "........................",
 "...........##...........",
 "..........####..........",
 ".........##..##.........",
 ".........#.##.#.........",
 ".........#.#..#.........",
 ".........##.#.#.........",
 ".........#..#.#.........",
 ".........#.##.#.........",
 ".........##..##.........",
 "..........####..........",
 "...........##...........",
]
HEARTS_A = [
 "........................",
 "..##.##.................",
 ".#######..........##.##.",
 ".#######.........#######",
 "..#####..........#######",
 "...###............#####.",
 "....#..............###..",
 "....................#...",
 "........................",
 "..........##.##.........",
 ".........#######........",
 ".........#######........",
 "..........#####.........",
 "...........###..........",
 "............#...........",
]
HEARTS_B = [
 "........................",
 "........................",
 "......##.##.............",
 ".....#######...##.##....",
 ".....#######..#######...",
 "......#####...#######...",
 ".......###.....#####....",
 "........#.......###.....",
 "#.#..............#......",
 "#####...................",
 "#####..............##.##",
 ".###..............######",
 "..#................####.",
 "....................##..",
]
ZAP_A = [
 "........................",
 "...#...........#........",
 "....#.........#.........",
 ".....#.......#..........",
 "..........#.............",
 "#.........#.........#...",
 ".##......###......##....",
 "...##...#####...##......",
 ".........###............",
 "..........#.............",
 "...##...........##......",
 ".##...............##....",
 "#...................#...",
 "....#.........#.........",
 "...#...........#........",
]
ZAP_B = [
 "........................",
 "#..........#..........#.",
 ".#.........#.........#..",
 "..#........#........#...",
 "........................",
 "..........###...........",
 "#####....#####....#####.",
 "..........###...........",
 "........................",
 "..#........#........#...",
 ".#.........#.........#..",
 "#..........#..........#.",
]
STAR_A = [
 "...........#............",
 "...........#............",
 "..........###...........",
 "....#.....###.....#.....",
 ".....##..#####..##......",
 "......###########.......",
 "#######################.",
 "......###########.......",
 ".....##..#####..##......",
 "....#.....###.....#.....",
 "..........###...........",
 "...........#............",
 "...........#............",
]
STAR_B = [
 "........................",
 "..#.....................",
 "...#.......#.......#....",
 "....#.....###.....#.....",
 "..........###...........",
 "........#######.........",
 "...######.....######....",
 "........#######.........",
 "..........###...........",
 "....#.....###.....#.....",
 "...#.......#.......#....",
 "..#.....................",
]
ZZZ = [
 "..............########..",
 "..............########..",
 "..................###...",
 ".................###....",
 "................###.....",
 "...............########.",
 "...............########.",
 "........######..........",
 "........######..........",
 "...........##...........",
 "..........##............",
 ".........######.........",
 ".........######.........",
 "..#####.................",
 "..#####.................",
 "....##..................",
 "...##...................",
 "..#####.................",
 "..#####.................",
]
BUBBLES = [
 "........................",
 "..........###...........",
 ".........#...#.....##...",
 ".........#...#....#..#..",
 "..##......###.....#..#..",
 ".#..#..............##...",
 ".#..#......##...........",
 "..##......#..#..........",
 "..........#..#.....###..",
 "...........##.....#...#.",
 "....###...........#...#.",
 "...#...#...........###..",
 "...#...#................",
 "....###.................",
]
BEE_A = [
 "........................",
 "........##..##..........",
 ".......#..##..#.........",
 ".......#..##..#.........",
 "........##..##..........",
 ".......#########........",
 "......###.##.####.......",
 "......###.##.#####......",
 "......###.##.####.......",
 ".......#########........",
 "...............#........",
]
BEE_B = [
 "........................",
 "........................",
 "........................",
 "......###....###........",
 ".....#...####...#.......",
 "......###....###........",
 ".......#########........",
 "......###.##.####.......",
 "......###.##.#####......",
 ".......#########........",
 "...............#........",
]
# the six clues about the sisters' past (hires, one colour each)
CLUE_ART = {
 "PHOTO": [
  "........................", "........................", "........................",
  "......############......", "......#..........#......", "......#.##....##.#......",
  "......#.##....##.#......", "......#..........#......", "......#.#..##..#.#......",
  "......#.########.#......", "......#..........#......", "......############......",
  "......############......"],
 "TIN": [
  "........................", "........................", "........................",
  "........................", ".......##########.......", "......############......",
  "......#..........#......", "......#.#.#..#.#.#......", "......#..........#......",
  "......#.#.#..#.#.#......", "......#..........#......", "......############......"],
 "DIARY": [
  "........................", "........................", "........................",
  ".......##########.......", ".......#.#######.#......", ".......#.#.....#.#......",
  ".......#.#.###.#.#......", ".......#.#.....#.#......", ".......#.#.##..#.#......",
  ".......#.#######.#......", ".......#..........#.....", ".......###########......"],
 "LOCKET": [
  "........................", "...........#............", "..........#.#...........",
  ".........#...#..........", "..........#.#...........", "........#######.........",
  ".......##.....##........", "......##..###..##.......", "......#..#.#.#..#.......",
  "......#..#####..#.......", "......##..###..##.......", ".......##.....##........",
  "........#######........."],
 "TAGS": [
  "........................", "........................", "........................",
  "....#######..#######....", "...#.......##.......#...", "...#.#####.##.#####.#...",
  "...#.......##.......#...", "....#######..#######....", "........................",
  ".....#...#......#...#...", "....#.....#....#.....#..", ".....#...#......#...#..."],
 "PAPER": [
  "........................", "........................", "......############......",
  "......#.########.#......", "......#..........#......", "......#.###..###.#......",
  "......#.#.#..###.#......", "......#.###..###.#......", "......#..........#......",
  "......#.########.#......", "......#.########.#......", "......#..........#......",
  "......############......"],
}
CLUE_NAMES = ["PHOTO", "TIN", "DIARY", "LOCKET", "TAGS", "PAPER"]
CLUE_COL = [1, 15, 10, 7, 3, 1]


def master(heads, pose):
    """The 24x42 master of a pose: head rows (front or side) + body rows
    (+ arm stamps). heads = (front head, side head)."""
    head = heads[1] if pose in SIDE_POSES else heads[0]
    rows = [list(r) for r in (LIE_BASE if pose == "LIE" else head + BODIES[pose])]
    for (r, c, t) in STAMPS.get(pose, []):
        for i, ch in enumerate(t):
            rows[r][c + i] = ch
    m = ["".join(r) for r in rows]
    assert len(m) == 42 and all(len(r) == 24 for r in m), (pose, [len(r) for r in m])
    return m


def split(m):
    """Master -> (MC body 12x21, top overlay 24x21, bottom overlay 24x21).
    Each MC pixel covers 2x2 master pixels: the commonest fill wins; a block
    that is mostly clear (or only line art) stays clear."""
    mc = []
    for r in range(21):
        row = ""
        for c in range(12):
            blk = [m[r * 2 + dy][c * 2 + dx] for dy in (0, 1) for dx in (0, 1)]
            fills = [p for p in blk if p in "HSD"]
            row += "." if (not fills or blk.count('.') >= 2) else max("SDH", key=fills.count)
        mc.append(row)
    top = ["".join('#' if ch == 'K' else '.' for ch in m[r]) for r in range(21)]
    bot = ["".join('#' if ch == 'K' else '.' for ch in m[r]) for r in range(21, 42)]
    return mc, top, bot


def enc_mc(rows):
    """'.' clear, 'S' skin ($D025, %01), 'D' own colour (%10), 'H' hair ($D026, %11)."""
    out = []
    for r in (list(rows) + ["." * 12] * 21)[:21]:
        bits = 0
        for ch in r.ljust(12, '.'):
            bits = (bits << 2) | {'.': 0, 'S': 1, 'D': 2, 'H': 3}[ch]
        out += [(bits >> 16) & 255, (bits >> 8) & 255, bits & 255]
    return out + [0]


def enc_hr(rows):
    rows = [(r or '').ljust(24, '.') for r in rows] + ["." * 24] * (21 - len(rows))
    out = []
    for r in rows[:21]:
        bits = int(r.replace('#', '1').replace('.', '0'), 2)
        out += [(bits >> 16) & 255, (bits >> 8) & 255, bits & 255]
    return out + [0]


# ---------------------------------------------------------------- library
LIB = []
def _lib(block):
    if block not in LIB:
        LIB.append(block)
    return LIB.index(block)

def _three(m):
    mc, top, bot = split(m)
    return (_lib(enc_hr(top)), _lib(enc_hr(bot)), _lib(enc_mc(mc)))

# [sister][pose] and [npc] -> (top, bottom, body) library block numbers
SISTER_FRAMES = [[_three(master(h, p)) for p in POSES]
                 for h in ((SUNNY_HEAD, SUNNY_SIDE), (HEX_HEAD, HEX_SIDE))]
NPC_FRAMES = [_three(h + NPC_BODY) for h in (MO, GRAN, PIP, PAGE)]

# ---------------------------------------------------------------- bank 0
# (name, data, multicolour, colour). The first six are the buffers the game
# copies library blocks into: sister top / bottom / body, NPC top / bottom / body.
_s, _n = SISTER_FRAMES[0][0], NPC_FRAMES[0]
FRAMES = [
    ("BUF_TOP",    LIB[_s[0]], 0, 0),
    ("BUF_BOT",    LIB[_s[1]], 0, 0),
    ("BUF_BODY",   LIB[_s[2]], 1, DRESS[0]),
    ("NPC_TOP",    LIB[_n[0]], 0, 0),
    ("NPC_BOT",    LIB[_n[1]], 0, 0),
    ("NPC_BODY",   LIB[_n[2]], 1, NPC_COL[0]),
    ("COIN_A",     enc_hr(COIN_A),   0, 7),
    ("COIN_B",     enc_hr(COIN_B),   0, 7),
    ("BEE_A",      enc_hr(BEE_A),    0, 7),
    ("BEE_B",      enc_hr(BEE_B),    0, 7),
    ("HEARTS_A",   enc_hr(HEARTS_A), 0, 10),
    ("HEARTS_B",   enc_hr(HEARTS_B), 0, 10),
    ("ZAP_A",      enc_hr(ZAP_A),    0, 14),
    ("ZAP_B",      enc_hr(ZAP_B),    0, 14),
    ("STAR_A",     enc_hr(STAR_A),   0, 1),
    ("STAR_B",     enc_hr(STAR_B),   0, 1),
    ("ZZZ",        enc_hr(ZZZ),      0, 1),
    ("BUBBLES",    enc_hr(BUBBLES),  0, 1),
] + [("CLUE_" + n, enc_hr(CLUE_ART[n]), 0, c) for n, c in zip(CLUE_NAMES, CLUE_COL)]
assert len(FRAMES) <= 32, len(FRAMES)
INDEX = {n: i for i, (n, *_r) in enumerate(FRAMES)}
