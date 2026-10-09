/// @desc scr_node_tooltip_text()
/// Returns a struct { title, lines[] } describing a node type, for the
/// header-hover tooltip system (hover the right 20% of a node's header
/// bar for ~1s with no mouse button held). Returns undefined for any
/// node_type with no entry yet, so unlisted nodes simply show nothing.
/// Covers MACRO_* nodes only — opcode nodes already have their own
/// tooltip via scr_opcode_helper().
function scr_node_tooltip_text(_node_type) {
    static _map = {

        "MACRO_VIC": {
            title: "VIC - UNIFIED MODE SETUP",
            lines: [
                "One-stop VIC-II mode setup: text, bitmap, multicolour, ECM and their combinations.",
                "",
                "SETS:",
                "Screen, char and bitmap base pointers, the $D011/$D016 mode bits, and the border and background colours, all in one node.",
                "",
                "WHERE:",
                "Usually the first macro on the spine after INIT. It can also be used for IRQ-based mode changes."
            ]
        },

        "MACRO_PRINT": {
            title: "PRINT",
            lines: [
                "Prints text to screen RAM at a given row and column.",
                "",
                "SOURCE:",
                "INLINE fixed text, or an ASSET (TEXT_DATA) read through a start/end byte window. Either end of the window can be a literal offset or a named VAR, so the printed slice can shift at runtime - e.g. paging through a longer block of asset text.",
                "",
                "X / Y / COL:",
                "LIT or VAR; old saves default to LIT. VAR X/Y clamp to 39/24. COL sets the single text colour (0-15); a VAR colour uses its low 4 bits.",
                "",
                "ALIGN:",
                "H/V alignment can auto left/centre/right and top/mid/bottom the text instead of a fixed X/Y. Alignment overrides X/Y; choose DEF for presets.",
                "",
                "PRE-CLEAR:",
                "Optionally wipes screen RAM before printing.",
                "",
                "NOTES:",
                "The runtime position also uses ZP $F5-$F8."
            ]
        },

        "MACRO_PRINT_EXT": {
            title: "PRINT EXT",
            lines: [
                "Prints a numeric value - a named VAR or a CPU register (A/X/Y/SP/FLAGS) - to screen RAM.",
                "",
                "FORMAT:",
                "DEC, HEX, BIN or BCD. FLAGS is always shown in binary with an N V - B D I Z C legend row underneath. Width follows the VAR's own size. Zero or space padding is available.",
                "",
                "X / Y / COL:",
                "LIT or VAR; old saves default to LIT. VAR X/Y clamp to 39/24; a VAR colour uses its low 4 bits.",
                "",
                "ALIGN:",
                "H/V alignment overrides X/Y; choose DEF for presets.",
                "",
                "NOTES:",
                "The runtime position also uses ZP $F5-$F8."
            ]
        },

        "MACRO_PLACE_CHAR": {
            title: "PLACE CHAR",
            lines: [
                "Writes one screencode, and optionally a colour, at a given row and column of screen and colour RAM.",
                "",
                "SET COL:",
                "LIT uses the palette; VAR reads a variable. A variable colour uses its low four bits (0-15).",
                "",
                "HOW IT WORKS:",
                "Address maths is shift-add (row*40 = row<<5 + row<<3), so it works against any screen base, not just $0400."
            ]
        },

        "MACRO_GET_CHAR": {
            title: "GET CHAR",
            lines: [
                "Reads the screencode, and optionally the colour, at a given row and column into named VARs.",
                "",
                "NOTES:",
                "The companion read to PLACE CHAR - same pointer maths, opposite direction."
            ]
        },

        "MACRO_CLR_SCREEN": {
            title: "CLR SCRN RAM",
            lines: [
                "Fills 1000 bytes of screen RAM with a fill byte, starting at a chosen base address.",
                "",
                "NOTES:",
                "Stops 8 bytes short of the full 1024-byte page so it never touches the sprite pointer table at base+$3F8-$3FF.",
                "FILL starts at $20, the space character. To clear with character / tile 0 instead, set FILL to 0."
            ]
        },

        "MACRO_BMP_OBJ": {
            title: "BMP OBJECT",
            lines: [
                "Draws one object of a BMP OBJECTS asset into a bitmap with its mask: the mask cuts a hole, the graphics fill it, so the background shows round the object.",
                "",
                "ASSET / OBJECT:",
                "Click ASSET to step through BMP OBJECTS assets (SHIFT+click goes back). OBJECT is the object's number in that asset, or take it from a byte VAR at runtime.",
                "",
                "BMP / COL / ROW:",
                "Bitmap address and the top-left cell (0-39, 0-24). COL and ROW can come from byte VARs, so one node can draw a moving object.",
                "",
                "MODE:",
                "DRAW just draws. SAVE + DRAW first saves the bitmap bytes it covers. RESTORE puts back what the SAVE + DRAW or MOVE node with the same SLOT saved. MOVE restores its own last save, then saves and draws at the new place - one node per moving object, once a frame.",
                "",
                "SCREEN:",
                "Screen RAM address. Objects with a fixed colour write it into the cells they cover; AUTO objects leave the cells alone. OFF writes no colour. A restore puts back bitmap bytes only.",
                "",
                "NOTES:",
                "Uses zero page $F0-$FD but saves and restores it, and keeps the IRQ flag as it was. Var values are not range-checked."
            ]
        },

        "MACRO_CLEAR_BMP_RECT": {
            title: "CLR BMP RECT",
            lines: [
                "Zeroes a rectangular block of bitmap data, given in char-cell col/row/width/height, not pixels.",
                "",
                "RESULT:",
                "Every zeroed bit pair renders as the background colour ($D021) whatever screen and colour RAM hold - a true wipe that doesn't touch either colour plane.",
                "",
                "COL / ROW / W / H:",
                "Each takes an optional byte VAR. With a var set the literal is ignored and the value is read at runtime, so one node can wipe a moving rect (a falling tile, a wipe transition). There is no grid trim in var mode - keep col+w <= 40 and row+h <= 25. A var of 0 for W or H clears nothing.",
                "",
                "TIP:",
                "Drop it before MOVE BMP BLK to pre-clear a room's target area, since MASK00 blending lets old pixels show through any gaps left by a previous room."
            ]
        },

        "MACRO_VWAIT": {
            title: "VWAIT",
            lines: [
                "Waits for one specific raster line.",
                "",
                "HOW IT WORKS:",
                "Gated on the $D011 bit 8 flag so it only fires in the top frame (lines 0-255), never on the phantom repeat in the lower border.",
                "",
                "USE:",
                "Syncs code to a precise scanline, e.g. before a raster-split trick."
            ]
        },

        "MACRO_NOP_REPEAT": {
            title: "NOP REPEAT",
            lines: [
                "Emits an unrolled run of NOP ($EA), 0-255 of them.",
                "",
                "COST:",
                "Exactly 1 byte and 2 cycles per NOP, so a count of 8 costs 8 bytes / 16 cycles. It touches no registers, no ZP and no flags - safe anywhere you need raster or cycle padding.",
                "",
                "COUNT:",
                "Literal only: the run is unrolled at build time, so a variable could not be resolved."
            ]
        },
        "MACRO_WAIT": {
            title: "WAIT",
            lines: [
                "Blocking delay measured in whole frames (PAL 50/s, NTSC 60/s), up to 255 frames (~5.1s PAL).",
                "",
                "HOW IT WORKS:",
                "Counts raster wraps at line 255, gated on $D011 bit 8 so only the top-frame instance is latched.",
                "",
                "REGISTERS:",
                "The counter lives in X - no ZP used. Clobbers A and X."
            ]
        },

        "MACRO_DISPLAY": {
            title: "DISPLAY",
            lines: [
                "Toggles the screen on or off via the DEN bit ($D011 bit 4).",
                "",
                "HOW IT WORKS:",
                "A read-modify-write that preserves every other bit in the register, so it is safe alongside VSCROLL, bitmap mode, ECM and the 9th raster bit.",
                "",
                "COST:",
                "Fixed 8 bytes."
            ]
        },

        "MACRO_TEXT_SCROLL": {
            title: "TXT SCROLL",
            lines: [
                "Scrolls a line of inline text across the screen at a chosen row, one character column per call.",
                "",
                "SETTINGS:",
                "Speed, direction, screen row and a working RAM buffer address are all set per node.",
                "",
                "COMMANDS:",
                "_col01, _spd03, _trk02 and _wait can be typed into the text. They are hidden and applied as the scroller meets them."
            ]
        },

        "MACRO_CHR": {
            title: "CHARSET",
            lines: [
                "Points the VIC at a custom character set asset and sets its base address in $D018.",
                "",
                "NOTES:",
                "Pair it with a MACRO_VIC node for full mode setup - this node only handles the charset pointer."
            ]
        },

        "MACRO_MAP": {
            title: "MAP",
            lines: [
                "Copies a flat char + colour map asset to screen RAM using a fast (zp),Y pointer-walk loop.",
                "",
                "SETTINGS:",
                "Map width, height and the destination screen base are all configurable.",
                "",
                "SEE ALSO:",
                "For the tileset-driven flow with per-room stamping, use METAMAP instead."
            ]
        },

        "MACRO_METAMAP": {
            title: "METAMAP",
            lines: [
                "Flattens a META_TILESET room to screen + colour RAM.",
                "",
                "LIT MODE:",
                "Bakes one chosen room at compile time and copies it to the screen with a MAP-style loop.",
                "",
                "VAR MODE:",
                "Every room is compiled as a placement list + stamp table. A runtime stamper reads a named VAR and draws whichever room it points to - re-run the node any time that var changes to redraw."
            ]
        },

        "MACRO_MAP_SWITCH": {
            title: "MAP SWITCH",
            lines: [
                "Points an existing MACRO_MAP node at a different MAP_DATA asset.",
                "",
                "HOW IT WORKS:",
                "Rewrites its ZP char and colour source pointers, resets the scroll position to zero, and calls the shared map redraw routine.",
                "",
                "NEEDS:",
                "A MACRO_MAP node already connected on the spine to read its ZP base from - this node only switches which map that setup points at."
            ]
        },

        "MACRO_SCROLL": {
            title: "MAP H-SCROLL",
            lines: [
                "Horizontal map scrolling with a unified delta core.",
                "",
                "HOW IT WORKS:",
                "scroll_fine (0-7) and scrollx (column) are the single source of truth. $D016 is only ever written from scroll_fine, never read back.",
                "",
                "LEFT / RIGHT:",
                "The variants only set the direction sign and share the same scrolling routine."
            ]
        },

        "MACRO_HUD": {
            title: "HUD - QUICK GUIDE",
            lines: [
                "Draws a HUD panel made in the asset editor and gives you routines to update its fields.",
                "",
                "SETUP:",
                "Create a HUD asset, paint its panel and add fields in the asset editor. Pick that asset here. Its position and size determine where it appears.",
                "",
                "SCR / COL:",
                "Set the destination screen and colour-memory bases (normally $0400 / $D800). COLOUR enables colour writes; turn it off to preserve existing colours.",
                "",
                "DRAW:",
                "AUTO DRAW stamps the panel when execution reaches this macro. With it off, call the hud<ID>_draw routine shown on the node after setting up the screen. Redraw if the panel is overwritten.",
                "",
                "FIELDS:",
                "For DIGITS or BAR fields, load the value into A, then JSR the field routine shown on the node. DIGITS displays a decimal byte value (0-255); BAR uses the field settings.",
                "",
                "TEXT:",
                "Text fields mark screen positions, not callable routines. Use the address shown on the node to write your own text.",
                "",
                "SCROLLING:",
                "Reserve HUD rows using the scroller's omit controls. Vertical fine scrolling still moves a character HUD; use a raster split or sprites to keep it steady."
            ]
        },

        "MACRO_METASCROLL": {
            title: "METASCROLL - QUICK GUIDE",
            lines: [
                "Four-way smooth scrolling over a META_TILESET room.",
                "",
                "SETUP:",
                "Pick TILESET and MAP. CLAMP ON stops the camera at the map edges.",
                "",
                "MOVE:",
                "Click MSC_L / MSC_R / MSC_U / MSC_D to create JSR nodes. Each call moves one pixel. Call MSC_Update once EVERY frame, after the movement calls, even when standing still.",
                "",
                "COLOUR:",
                "Click to cycle through four modes, described below.",
                "",
                "FIXED:",
                "Fastest and smallest. One colour-RAM value for the whole room. NIB AUTO chooses the most common value; choose a manual NIB to override it.",
                "",
                "ROW BANDS:",
                "One colour per map row. Useful for sky/ground layouts on a stock C64; horizontal scrolling needs no colour-RAM shift.",
                "",
                "SHIFT STOCK:",
                "Per-character colour on a stock C64 using two screens. Reserve an extra 1K; click BUF to change its address (default $3800). Keep it clear of code, charset and map data.",
                "",
                "SHIFT C64U:",
                "Per-character colour for a C64 Ultimate in turbo mode. Too slow for clean scrolling on a stock C64.",
                "",
                "PREVIEW:",
                "Use RUN VIEW in the tileset editor to check the selected colour mode. In FIXED, use NIB AUTO or pick a colour from the COLOUR strip.",
                "",
                "SPACE:",
                "PLANES sets the map-data address. ZP BASE reserves 10 zero-page bytes. Check the memory bar for overlaps, including the SHIFT STOCK buffer.",
                "",
                "EDGES / HUD:",
                "BLANK CH must be a blank tile in your charset. OMIT TOP / OMIT BOT remove 0-8 rows each from scrolling, leaving space for a HUD and reducing work.",
                "",
                "PERFORMANCE:",
                "Omitting top rows also gives extra raster time. The LINES estimate turns red when work exceeds the budget; verify timing on your target machine.",
                "",
                "LIMITS:",
                "Left/up edges can show a one-pixel pop. Vertical scrolling can pop at an omitted-row seam and also moves a character HUD; use a raster split or sprites for a steady HUD."
            ]
        },

        "MACRO_VSCROLL": {
            title: "V-SCROLL",
            lines: [
                "Vertical scrolling for an 18-column map centred on the 40-column screen (offset 11).",
                "",
                "WINDOW:",
                "Scrolls rows 1-22. Rows 0, 23 and 24 are blanked once at init.",
                "",
                "HOW IT WORKS:",
                "Chars and colour RAM scroll in lockstep. There are two entry points: one scrolls the content up, the other down."
            ]
        },

        "MACRO_BMP": {
            title: "BITMAP",
            lines: [
                "Auto-configures VIC bitmap mode from a Koala or raw bitmap asset.",
                "",
                "SETS:",
                "The bitmap base and screen base, and loads the asset's screen, colour and bitmap planes.",
                "",
                "USE:",
                "The simplest way to get a static hi-res or multicolour picture on screen."
            ]
        },

        "MACRO_VECTOR_BMP": {
            title: "VECTOR BMP",
            lines: [
                "Sets up the shared vector-bitmap runtime (interpreter + multicolour plot routine) and streams a VECTOR_BITMAP asset's PLOT / SETCOL / END command list into it.",
                "",
                "COST:",
                "The runtime is emitted once per build, however many VECTOR BMP / PAGE nodes use it.",
                "",
                "ORDER:",
                "Must sit before any VECTOR PAGE nodes that use the same asset."
            ]
        },

        "MACRO_VECTOR_PAGE": {
            title: "VECTOR PAGE",
            lines: [
                "Flips a multi-page VECTOR_BITMAP asset to a chosen page.",
                "",
                "HOW IT WORKS:",
                "Clears the bitmap, fills screen and colour RAM and the border from that page's 4 colours, then renders that page's command stream.",
                "",
                "NOTES:",
                "Doesn't touch the VIC mode registers - the VECTOR BMP setup node earlier on the spine owns those."
            ]
        },

        "MACRO_MOVE_BMP_BLOCK": {
            title: "MOVE BMP BLK",
            lines: [
                "Copies a rectangular block of bitmap data, in char-cell units, from one bitmap to another or within the same one. It can also copy the matching screen and colour RAM.",
                "",
                "X / Y OFFSET:",
                "Offset VARs (in cells) are added to the source and destination at runtime.",
                "",
                "SPEED:",
                "Self-modifying operands keep each row a single fast LDA/STA pair."
            ]
        },

        "MACRO_FLIP_X": {
            title: "FLIP X",
            lines: [
                "Flips selected sprites horizontally using a lookup table.",
                "",
                "HOW IT WORKS:",
                "Reads the sprite data from an asset address, writes the flipped copy to a temp block, and points the sprite pointer table at the flipped copy.",
                "",
                "MODES:",
                "Detects hi-res or multicolour per sprite via $D01C at runtime - both LUTs are emitted inline."
            ]
        },

        "MACRO_SPR": {
            title: "SPRITE",
            lines: [
                "Sets up one hardware sprite: pointer, X/Y position, colour and enable state.",
                "",
                "SEE ALSO:",
                "Combine it with MOVE, ANIMATE, PRIORITY, ENABLER and the other sprite macros for full behaviour."
            ]
        },

        "MACRO_MOVE": {
            title: "MOVE (SPRITE)",
            lines: [
                "Minimal-byte unison sprite movement: applies a per-frame X/Y delta to a group of sprites (chosen by bitmask), as a literal or a named VAR.",
                "",
                "VAR MODE:",
                "Reads the delta as a SIGNED byte. Its sign bit picks the direction at runtime, so one VAR can drive a sprite left/right or up/down just by changing sign - no separate direction flag needed.",
                "",
                "WRAP / BOUNDED:",
                "By default the position rolls over at the 8-bit edge. Enable STOP to clamp the movement at fixed screen walls instead.",
                "",
                "9TH BIT:",
                "Toggle the $D010 MSB register so X covers the full 0-343 sprite-visible width instead of wrapping at 0-255."
            ]
        },

        "MACRO_SEEK": {
            title: "SEEK",
            lines: [
                "Directional / AI seek movement: steers a sprite toward a target X/Y (literal or from named VARs).",
                "",
                "SETTINGS:",
                "A configurable speed, optional deceleration near the target, and a widening catch box.",
                "",
                "OUTPUT:",
                "Can also report the distance and angle to the target into named VARs for further logic."
            ]
        },

        "MACRO_COLLISION": {
            title: "COLLIDE",
            lines: [
                "Basic sprite-vs-map collision probe.",
                "",
                "HOW IT WORKS:",
                "Checks the map tile type under a sprite's position and reports a hit / type result into a named VAR."
            ]
        },

        "MACRO_COLL_ADV": {
            title: "COLL.ADV",
            lines: [
                "Advanced multi-point collision probe against map tile types, with per-edge and per-corner checks.",
                "",
                "DIRECT MODE:",
                "For bitmap hybrids. Reads the screen byte itself as the collision type - the same byte MOVE BMP BLK's WRITE COLL option writes from source tags - so no per-room tile-type table is needed.",
                "",
                "SCAN MODE:",
                "For char maps. Looks the screen byte up in the map's generated <map>_TILE_TYPES table instead."
            ]
        },

        "MACRO_PRIORITY": {
            title: "PRIORITY",
            lines: [
                "Sets whether a sprite draws in front of or behind the background characters.",
                "",
                "REGISTER:",
                "$D01B."
            ]
        },

        "MACRO_SPR_ENABLE": {
            title: "ENABLER",
            lines: [
                "Turns a hardware sprite on or off.",
                "",
                "REGISTER:",
                "$D015 - a clean single-purpose toggle rather than hand-rolling the bitmask each time."
            ]
        },

        "MACRO_SPR_EXPAND": {
            title: "EXPANDER",
            lines: [
                "Toggles X and/or Y double-size expansion for a sprite.",
                "",
                "REGISTERS:",
                "$D01D for X, $D017 for Y."
            ]
        },

        "MACRO_SPR_MASK": {
            title: "SPRITE MASK",
            lines: [
                "Hides sprites behind foreground parts of the scene. JSR <alias>_sub once per frame, after moving and animating. With nothing masked under the sprite, its real frames come back.",
                "",
                "SOURCE:",
                "A SPRITE_MASK asset for one fixed scene, or a ROOM_MAP to use the current room's mask (ROOMS fetches it into its MASK RAM).",
                "",
                "SPRITES:",
                "Slots to mask, e.g. 0 or 0,1. The first slot's position decides where the mask is read.",
                "",
                "HOT Y:",
                "The feet row inside the sprite (0-20). A cell painted with a Y line hides the sprite only while the feet are above that line. At or below it the sprite is in front.",
                "",
                "WORK:",
                "64-byte aligned address for the masked copies: 2 x 64 bytes per slot, in the sprites' VIC bank, not used by anything else.",
                "",
                "ZP:",
                "First of the 12 zero page bytes it borrows. They are saved and restored on every call.",
                "",
                "SYNC:",
                "OFF: the frame swaps when the routine ends, often mid-screen, so the mask can trail the sprite by a frame - a shimmer while it moves.",
                "",
                "ON: position and masked frame change together on line $FB. Use it for anything that moves. It waits for that line itself, so remove the loop's VWAIT.",
                "",
                "TIP:",
                "MC sprite over an MC bitmap: keep X even (move in steps of 2) or the mask edge flickers by a pixel."
            ]
        },
        "MACRO_COLL_LINE": {
            title: "COLL-LINE",
            lines: [
                "Tests one point against a LINE_COLL asset's lines and puts the TYPE (1-7) of the first line hit in RES, or 0 for no hit. It only reports - your nodes decide what a hit does (e.g. IF BYTE RES <> 0: put the old position back).",
                "",
                "LUT:",
                "The LINE_COLL asset, or a ROOM_MAP to use the current room's lines.",
                "",
                "PX / PY:",
                "Vars holding the point. HW_SPR0_X / HW_SPR0_Y read the sprite directly.",
                "",
                "OFF X / OFF Y:",
                "Optional signed offset vars added first, to move the point to the feet: -12 / -30 is a sprite's bottom centre on the bitmap.",
                "",
                "RES VAR:",
                "Var that receives the line type.",
                "",
                "THICK:",
                "EXACT: the point must land on the line. +/-1 to 3: that many units either side also count, so fast or diagonal moves can't slip through. Line ends stay exact.",
                "",
                "WIDE X:",
                "Set on the LINE_COLL asset. One X unit = 2 pixels so lines cover all 320. With a sprite X register as PX the 9th X bit is included.",
                "",
                "TIP:",
                "Check after every 1-pixel step (after each MOVE) so a diagonal can't cross a line between pixels. Uses ZP $F3-$FE as scratch, not restored."
            ]
        },

        "MACRO_ROOMS": {
            title: "ROOMS",
            lines: [
                "Loads the rooms of a ROOM_MAP asset (made in the asset panel's map view) and routes doors between them.",
                "",
                "ROOM:",
                "The byte holding the current room number.",
                "",
                "SPRITES:",
                "Player sprite slots moved to the arrival points, e.g. 0,1.",
                "",
                "HOT X / Y:",
                "The player's hotspot inside the sprite - the map's points are that pixel.",
                "",
                "HOOK:",
                "Optional label called after each room loads.",
                "",
                "ROUTINES:",
                "RM_<MAP>_start enters ROOM at its spawn point. RM_<MAP>_door takes A = the collider line type (2-7). RM_<MAP>_enter reloads ROOM at the last arrival point.",
                "",
                "TIP:",
                "Point a COLL_LINE at the ROOM_MAP to probe whichever room is current."
            ]
        },

        "MACRO_ANIM_SET": {
            title: "ANIM SET - SEQUENCES AND SPRITE LAYERS",
            lines: [
                "One player controls several named animation sequences. Each numbered row is a sequence, such as DOWN, RIGHT or LEAP. The frame lists beneath it describe the sprites to show at each animation step.",
                "",
                "EDIT / ASSET:",
                "[EDIT] opens the linked reusable ANIMATION asset. On a local node, it creates an asset from the existing sequences. Click ASSET beneath the rows to cycle through available animation assets or return to local data. Linked rows are edited in the asset editor; SELECT and ALIAS remain local to each node.",
                "",
                "SLOTS:",
                "How many hardware sprite slots have frame lists shown, from slot 0 upwards (1-8). It is NOT the number of frames or directions. For the layered CityCat, use 2: slot 0 is the outline and slot 1 is the colour layer. Four slots would give four sprite layers if you position them together. Slots can also animate separate sprites.",
                "",
                "FRAME LISTS:",
                "The left box is slot 0, the next is slot 1, and so on. Enter sprite indices from the loaded sprite bank, separated by commas. The lists advance together: first entry with first entry, second with second, etc. These are sprite indices, not screen positions or memory addresses.",
                "",
                "EXAMPLE:",
                "CityCat DOWN: outline (left) = 0,12,24,36. Colour (right) = 6,18,30,42. The four displayed pairs are (0 + 6), (12 + 18), (24 + 30), then (36 + 42). This matches the packed 48-sprite runtime bank in the example; use the indices of the bank actually loaded, not a differently arranged source sheet.",
                "",
                "DELAY:",
                "Player calls per animation step (1-255). Call the player once per game frame: lower delay is faster. DELAY 8 holds each step for 8 game frames, about 0.16 seconds at 50 Hz PAL. It is shared by all layers in that row.",
                "",
                "LOOP:",
                "On (green) repeats the row. Off plays once, holds the final frame, then sets <alias>_done to 1. Keep layer lists the same length for paired artwork. A shorter list repeats within a looping row, or holds its last entry in a one-shot row.",
                "",
                "SELECT:",
                "The address or variable containing the row number: 0 selects DOWN in this example, 1 selects DOWN_RIGHT, etc. Blank SELECT always chooses row 0. Changing the value restarts the newly selected row. An out-of-range value pauses updates; it does not hide the sprites.",
                "",
                "ALIAS:",
                "Names the callable player, for example cc_anim. Call JSR cc_anim_sub once per game frame. JSR cc_anim_reset restarts the selected row on the next player call. Read cc_anim_done for one-shot completion. Row names are descriptions; SELECT uses their numbered positions.",
                "",
                "SETUP:",
                "Use connected SPRITE nodes in the same ORG to configure the hardware slots, position, colours and hires/multicolour mode. Put the two CityCat slots at the same X/Y to align the layers. ANIM SET changes sprite pointers only; it does not position, mirror or move the cat. Its shared bank base comes from the connected slot-0 SPRITE asset.",
                "",
                "LIMITS:",
                "Up to 32 rows and 255 animation steps across the set (count each row by its longest layer list, not the sum of its layers). SLOTS controls the visible boxes; reducing it does not clear hidden frame lists. Clear an unwanted list before hiding its slot. X deletes a sequence and renumbers the rows below it, so check SELECT values afterwards."
            ]
        },

        "MACRO_ANIM": {
            title: "ANIMATE",
            lines: [
                "Per-sprite-slot animation: up to 8 slots, each with its own list of frame values and X/Y position offsets (+/-) to step through over time.",
                "",
                "SETUP:",
                "Place the node once before your core game loop. It exposes a JSR entry point that then appears in the picker on any JSR node, so the per-frame advance is called from wherever your loop needs it.",
                "",
                "DELAY:",
                "A frame counter, not a speed value: a lower DELAY advances sooner, so lower = faster animation."
            ]
        },

        "MACRO_LETTERS": {
            title: "KEYS A-Z",
            lines: [
                "Direct CIA1 matrix scan: a column is driven low on $DC00 and the rows are read back from $DC01, so any number of keys can be held at once.",
                "",
                "BITS:",
                "Each enabled key sets its own bit in the ZP block and can JSR a label. Bit 0 is the first key in the grid, reading left to right.",
                "",
                "NOT SCANNABLE:",
                "RESTORE (it is on the NMI line), and F2/F4/F6/F8 (these are SHIFT plus F1/F3/F5/F7, not matrix positions)."
            ]
        },

        "MACRO_FNNUMBERS": {
            title: "KEYS 0-9 / Fn",
            lines: [
                "Direct CIA1 matrix scan: a column is driven low on $DC00 and the rows are read back from $DC01, so any number of keys can be held at once.",
                "",
                "BITS:",
                "Each enabled key sets its own bit in the ZP block and can JSR a label. Bit 0 is the first key in the grid, reading left to right.",
                "",
                "NOT SCANNABLE:",
                "RESTORE (it is on the NMI line), and F2/F4/F6/F8 (these are SHIFT plus F1/F3/F5/F7, not matrix positions)."
            ]
        },

        "MACRO_MISCKEYS": {
            title: "KEYS MISC",
            lines: [
                "Direct CIA1 matrix scan: a column is driven low on $DC00 and the rows are read back from $DC01, so any number of keys can be held at once.",
                "",
                "BITS:",
                "Each enabled key sets its own bit in the ZP block and can JSR a label. Bit 0 is the first key in the grid, reading left to right.",
                "",
                "CURSOR KEYS:",
                "KUP/KDN/KLF/KRT are the cursor DIRECTIONS: the CRSR key with the shift test built in (KUP = CRSR U/D + shift, KDN = CRSR U/D with no shift, and so on).",
                "",
                "NOT SCANNABLE:",
                "RESTORE (it is on the NMI line), and F2/F4/F6/F8 (these are SHIFT plus F1/F3/F5/F7, not matrix positions)."
            ]
        },

        "MACRO_MOUSE": {
            title: "MOUSE (1351)",
            lines: [
                "Reads a Commodore 1351 in proportional mode. POTX/POTY give a 6-bit delta each frame, which is sign-extended and added to a signed 16-bit X/Y held in zero page.",
                "",
                "ZP:",
                "Names a 7 byte block: +2/+3 is X, +4/+5 is Y - those are the addresses your own code reads.",
                "",
                "LF / RT / UP / DN:",
                "Fire once per frame while the mouse is moving on that axis. They are a movement report, not a held direction like the joystick's.",
                "",
                "NOTES:",
                "Call this once per frame. Reading the pots needs CIA1 $DC00 bits 6-7 pointed at the port, which the KERNAL keyboard scan also writes."
            ]
        },

        "MACRO_JOY": {
            title: "JOYSTICK",
            lines: [
                "Reads a CIA joystick port and dispatches to JMP targets based on which direction and fire bits are set, via an AND/BNE test per bit.",
                "",
                "USE:",
                "Connect JMP-target nodes for whichever directions or fire button you want to react to."
            ]
        },

        "MACRO_SID": {
            title: "SID",
            lines: [
                "Full SID music setup with a raster IRQ: configures the player, hooks a raster interrupt, and starts playback of an imported SID_MUSIC or SID_SFX asset.",
                "",
                "SEE ALSO:",
                "For the built-in MUSIC_MAKER tool instead of an imported .sid file - with multi-song support, hard restart and tempo control - use SID SONG."
            ]
        },

        "MACRO_SID_SONG": {
            title: "SID SONG",
            lines: [
                "Multi-song player driven by the built-in MUSIC_MAKER tool (an asset you compose songs in), with hard-restart support, per-asset tempo, and a write-only SID register shadow so playback never read-modify-writes $D400-$D41C.",
                "",
                "MEMORY:",
                "Banks BASIC ROM out permanently at init ($01=$36), keeping the KERNAL in so $0314/$0315 IRQ chaining still works, and frees $03-$8F for player state.",
                "",
                "PATTERNS:",
                "$FF = REST (gate off, the tail still runs), $FE = HOLD (the ringing note continues), 0-95 = chromatic note index."
            ]
        },

        "MACRO_SID_SOUND": {
            title: "SID SOUND",
            lines: [
                "Plays a single note or sound on a chosen SID voice. Waveform, frequency, ADSR and pulse width can each be a literal or a named VAR.",
                "",
                "WAVE:",
                "$D404 carries both the waveform bits and the gate bit, and is always written last so the note gates on only once everything else is set.",
                "",
                "NOTE LIST:",
                "The note can also come from a TEXT_DATA asset acting as a note list, indexed at runtime."
            ]
        },

        "MACRO_SFX": {
            title: "SFX",
            lines: [
                "Choose SFX MAKER for native effects, or SFX DATA for the existing GoatTracker/Zed import workflow.",
                "",
                "SFX MAKER:",
                "Pick an effect and SID voice, then click ACTION to choose PLAY, UPDATE, STOP or INIT. Use the same asset and voice on all those nodes.",
                "",
                "ACTIONS:",
                "INIT once before music starts sets the volume and clears this effect voice. UPDATE runs once per video frame. PLAY triggers once on your game event; STOP cancels.",
                "",
                "WITH MUSIC:",
                "In Music Maker, turn OFF that voice with VOICES. Example: music on 1+2, effects on 3. Song position and memory banking are untouched by SFX calls.",
                "",
                "PRIORITY:",
                "Higher priority interrupts; equal priority restarts. Lower priority waits for your next trigger. Imported SFX DATA keeps its existing SID player path."
            ]
        },

        "MACRO_TRACK": {
            title: "TRACK",
            lines: [
                "Runtime music track switcher: polls GETIN each frame and swaps to a different SID or track on input.",
                "",
                "SAFETY:",
                "SEI/CLI guards stop an IRQ firing mid-init or mid-GETIN.",
                "",
                "NEEDS:",
                "sid_getin must resolve to $FFE4 at build time."
            ]
        },

        "MACRO_SID_PAUSE": {
            title: "SID PAUSE",
            lines: [
                "Stops and restarts the music tick. PAUSE sets a flag that every SID play call is guarded by, so the IRQ keeps firing - raster splits and everything else in the handler are untouched - and only the music stops advancing.",
                "",
                "USE:",
                "Hands all three SID voices to whatever you want them for: VOI64 speech, sound effects, a jingle. RESUME gives them straight back.",
                "",
                "PAUSE:",
                "Also silences the three voices, because a note with a long release would otherwise drone on underneath.",
                "",
                "RESUME:",
                "Nothing needs restoring: SID players rewrite the whole register set every frame, so the first tick after puts the chip back. The tune continues from where it paused rather than restarting - its counters live in RAM and were never touched.",
                "",
                "COST:",
                "Nothing unless used: with no SID PAUSE node in the project the guards are not emitted at all."
            ]
        },

        "MACRO_VOI64_MASTER": {
            title: "VOI64 MASTER",
            lines: [
                "Sets the SID up for speech and emits the Voi64 player once. Every VOI64 SAY in the project needs one of these connected - without it a SAY emits nothing.",
                "",
                "PITCH:",
                "The glottal rate in Hz.",
                "",
                "THROAT / MOUTH:",
                "THROAT scales the first formant (deeper, chestier). MOUTH scales the second and third (brighter, more forward).",
                "",
                "SPEED:",
                "0-255 with 128 nominal. HIGHER IS FASTER.",
                "",
                "BLOCKING:",
                "The player owns the CPU until the phrase ends, so no raster effects and no music while it speaks.",
                "",
                "VOICES:",
                "V3 is a silent pitch source, V1 is the first formant hard-synced to it, V2 is the second. On unvoiced sounds V3 switches to noise and carries the frication."
            ]
        },

        "MACRO_VOI64_SAY": {
            title: "VOI64 SAY",
            lines: [
                "Speaks a phrase.",
                "",
                "TEXT / PHONEME:",
                "TEXT mode runs English letter-to-sound on the PC at build time, so the C64 never sees a letter - only the finished frames. PHONEME mode takes a phoneme string verbatim, which is how you fix a word the rules get wrong.",
                "",
                "SOURCE:",
                "Typed inline or a TEXT_DATA asset. Both are known at build time, which is what keeps the runtime cost to eight bytes per glottal period.",
                "",
                "LINE FROM / TO:",
                "In TEXT DATA mode these pick a slice of the asset - one phrase per line, so a single asset becomes a phrase bank several SAY nodes share. Leave both blank for the whole thing. Lines rather than the byte offsets PRINT uses: the asset never reaches the C64, so a byte range would only let you cut a word in half.",
                "",
                "VAR RANGE:",
                "Either end can be a byte VAR instead of a number, so the program picks its line at runtime - set the var, call the macro. Line 1-255.",
                "",
                "COST:",
                "A var-driven SAY compiles EVERY line of the asset and indexes them through a pointer table, because the range is not known until the program runs. A fixed range compiles only the lines it names.",
                "",
                "OVERRIDES:",
                "PITCH / SPEED / THROAT / MOUTH show a dash when they are inherited from the master. Type a value to override it for this phrase only.",
                "",
                "PREVIEW:",
                "PREVIEW VOICE plays it through the tool using the same phoneme string the build will emit."
            ]
        },

        "MACRO_RANDOM": {
            title: "RANDOM",
            lines: [
                "Random numbers from the SID voice-3 noise generator.",
                "",
                "HOW IT WORKS:",
                "Optionally sets the oscillator up once, reads $D41B, and can clamp the result branchlessly into a [MIN,MAX] range.",
                "",
                "OUTPUT:",
                "Left in A and/or stored to a named VAR."
            ]
        },

        "MACRO_MATH": {
            title: "MATH",
            lines: [
                "ADD / SUB / MUL / DIV / ONE-MINUS / INVERT-SIGN on named VARs, signed two's complement throughout.",
                "",
                "WIDTH:",
                "Each operand's width follows its own VAR meta (byte or word).",
                "",
                "CODE:",
                "ADD / SUB / ONEMINUS / INVSIGN are inlined. MUL / DIV call a shared math_mul16 / math_div16 routine emitted once per build.",
                "",
                "ZP:",
                "Works in $F2-$F8, chosen to avoid the MACRO_MAP reservation ($FB-$FE) and the vector-bmp scratch."
            ]
        },

        "MACRO_UCI_REU": {
            title: "UCI LOAD REU",
            lines: [
                "Asks a 1541 Ultimate / Ultimate 64 to load a .reu image from its OWN storage into REU memory.",
                "",
                "WHEN:",
                "For a PRG run from the Ultimate's file browser, with no PC involved. VICE gets its image on the command line instead, and F6 pushes one over the network - this node does nothing under emulation.",
                "",
                "FILE:",
                "Follows the chosen LOAD_REU asset unless you type an override, so a rename cannot leave it pointing at a file that is no longer written.",
                "",
                "STAT:",
                "Optionally stores the first status byte. $30 '0' = OK. $38 '8' = 84 REU NOT ENABLED or 85 FILE NOT OPENED. $FF = no status seen (no Ultimate, or no reply).",
                "",
                "FLOW:",
                "Falls through to the next node on every path, including when no Ultimate is present."
            ]
        },
        "MACRO_MOVE_MEM": {
            title: "MOVE MEM",
            lines: [
                "Copies a byte range [src_start..src_end) to a destination address at runtime.",
                "",
                "CODE:",
                "Unrolled inline for 8 bytes or fewer, otherwise a page-aware loop (capped at 1024 bytes).",
                "",
                "WARNING:",
                "Forward copy only - overlapping ranges where the destination is above the source will corrupt data."
            ]
        },

        "MACRO_IRQ": {
            title: "IRQ",
            lines: [
                "Declares one raster interrupt: the line it fires on, and optionally a JSR into SID music playback.",
                "",
                "LABELS:",
                "Exposes two labels other nodes can JSR to: the handler entry point, and an init routine that hooks the vector.",
                "",
                "NEEDS:",
                "An IRQ HANDLER elsewhere on the spine to dispatch to it."
            ]
        },

        "MACRO_IRQ_HANDLER": {
            title: "IRQ HANDLER",
            lines: [
                "Emits the unified table-driven raster IRQ dispatcher.",
                "",
                "HOW IT WORKS:",
                "Reads every connected IRQ node, sorts them by raster line, builds the raster / target lookup tables, and emits a self-modifying JSR dispatch handler.",
                "",
                "VECTOR:",
                "KERNAL-chained ($0314/$0315) or the direct hardware vector ($FFFE/$FFFF)."
            ]
        },

        "MACRO_CODE": {
            title: "CODE",
            lines: [
                "A freeform block of hand-written 6502 assembly, assembled inline exactly where the node sits on the spine.",
                "",
                "USE:",
                "The escape hatch for anything the macro library doesn't cover yet - labels, opcodes and directives all work as normal."
            ]
        },

        "MACRO_LOADER": {
            title: "MACRO LOADER",
            lines: [
                "Loads one file from a LOAD_ORG D64 image on demand.",
                "",
                "HOW IT WORKS:",
                "KERNAL SETLFS / SETNAM / LOAD with secondary address $01, so the file loads to the address in its own PRG header.",
                "",
                "WHERE:",
                "Call it wherever it's needed on the spine - there's no fixed load-order requirement."
            ]
        },

        "MACRO_LOAD_GAME": {
            title: "LOAD GAME",
            lines: [
                "Loads a save file from a LOAD_ORG D64 back into RAM at runtime, restoring whatever it holds.",
                "",
                "NEEDS:",
                "A BYTE_DATA asset with USE AS SAVE FILE enabled and linked into the LOAD_ORG. That block is where your persisted VARs live - lives, coins, stats, or anything else you want to survive a reset."
            ]
        },

        "MACRO_SAVE_GAME": {
            title: "SAVE GAME",
            lines: [
                "Writes a BYTE_DATA asset's current contents to disk via a LOAD_ORG D64, persisting it between sessions.",
                "",
                "NEEDS:",
                "The asset must have USE AS SAVE FILE enabled and be linked into the LOAD_ORG. That's the block your game's persistent VARs (lives, coins, stats, etc.) should read from and write to."
            ]
        },

        "MACRO_REU": {
            title: "REU - RAM EXPANSION UNIT",
            lines: [
                "DMA transfer between C64 RAM and REU RAM, via registers $DF00-$DF0A.",
                "",
                "OP:",
                "STASH copies C64 -> REU. FETCH copies REU -> C64. SWAP exchanges both directions. COMPARE verifies only, with no write.",
                "",
                "ADDRESSES:",
                "C64 is the 16-bit start address in C64 RAM. REU is the 16-bit start address in REU RAM. BANK is the REU bank, 0-255 (most units: bank 0 only). LEN is the bytes to move; $0000 = 65536.",
                "",
                "AUTOLOAD:",
                "Reloads the start addresses once the transfer finishes, so the node can fire again without re-setting anything.",
                "",
                "FIX C64 / FIX REU:",
                "Hold that side's address still during the transfer - use for fills or repeated single-byte reads and writes.",
                "",
                "NOTES:",
                "FF00-disable is always set on the command byte: without it, a stray write to $FF00 can re-trigger the last queued transfer."
            ]
        }
    };

    if (variable_struct_exists(_map, _node_type)) {
        return _map[$ _node_type];
    }
    return undefined;
}

/// Wrap translated help paragraphs, including long tokens and CJK text.
function scr_node_info_wrap(_paragraphs, _width) {
    var _rows = [];
    var _after_heading = false;
    for (var _p = 0; _p < array_length(_paragraphs); _p++) {
        var _text = _paragraphs[_p];
        // Heading (chr(1) marker): one row, kept with the paragraph under it.
        if (string_char_at(_text, 1) == chr(1)) {
            if (_p > 0) array_push(_rows, "");
            array_push(_rows, _text);
            _after_heading = true;
            continue;
        }
        if (_p > 0 && !_after_heading) array_push(_rows, "");
        _after_heading = false;
        var _line = "";
        for (var _i = 1; _i <= string_length(_text); _i++) {
            var _ch = string_char_at(_text, _i);
            if (_line != "" && string_width(_line + _ch) > _width) {
                var _space = string_last_pos(" ", _line);
                if (_space > 0 && _ch != " " && ord(_ch) < 128) {
                    array_push(_rows, string_copy(_line, 1, _space - 1));
                    _line = string_delete(_line, 1, _space);
                } else {
                    array_push(_rows, _line);
                    _line = "";
                }
            }
            if (_line != "" || _ch != " ") _line += _ch;
        }
        if (_line != "") array_push(_rows, _line);
    }
    return _rows;
}

/// Cached, screen-bounded help. Read down each column, then across.
function scr_node_info_panel_draw(_type, _gw, _gh) {
    var _info = scr_node_tooltip_text(_type);
    if (is_undefined(_info)) return;
    var _old_font = draw_get_font();
    var _old_ha = draw_get_halign();
    var _old_va = draw_get_valign();
    draw_set_font_l(fnt_c64_code);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);

    // Size by the amount of text: paragraphs are single source strings now,
    // so the line count no longer says how long the help is.
    var _info_chars = 0;
    for (var _ic = 0; _ic < array_length(_info.lines); _ic++) {
        _info_chars += string_length(_info.lines[_ic]);
    }
    var _preferred_w = 1440;
    if (_info_chars <= 700) {
        _preferred_w = 800;
    }
    var _w = max(1, min(_preferred_w, _gw - 48, (_gh - 48) * 16 / 9));
    var _h = _w * 9 / 16;
    var _x = (_gw - _w) / 2;
    var _y = (_gh - _h) / 2;
    var _pad = min(24, _w * 0.025);
    var _scale = (_w >= 1000) ? 1.2 : 1.0;
    var _lh = max(16, string_height("Ag")) * _scale;
    var _cols = clamp(floor(_w / 500), 1, 3);
    var _gap = 28;
    var _cw = (_w - 2 * _pad - (_cols - 1) * _gap) / _cols;
    var _rows_per_col = max(1, floor((_h - 2 * _pad - _lh * 3) / _lh));
    var _key = _type + ":" + string(global.lang) + ":" + string(_w) + ":" + string(draw_get_font());
    if (!variable_instance_exists(id, "node_info_layout_key") || node_info_layout_key != _key) {
        // The help source uses manual line breaks. Join each paragraph before
        // wrapping so wide panels use the space instead of retaining narrow lines.
        var _paragraphs = [];
        var _paragraph = "";
        for (var _i = 0; _i < array_length(_info.lines); _i++) {
            var _parts = string_split(L(_info.lines[_i]), "\n");
            for (var _j = 0; _j < array_length(_parts); _j++) {
                var _part = string_trim(_parts[_j]);
                // A short line ending in ':' (e.g. "SOURCE:") is a heading on
                // its own row; the text under it starts on the next row.
                var _is_heading = (_part != "" && string_char_at(_part, string_length(_part)) == ":"
                                   && string_length(_part) <= 24);
                if (_is_heading) {
                    if (_paragraph != "") array_push(_paragraphs, _paragraph);
                    _paragraph = "";
                    array_push(_paragraphs, chr(1) + _part);
                } else if (_part == "") {
                    if (_paragraph != "") array_push(_paragraphs, _paragraph);
                    _paragraph = "";
                } else {
                    if (_paragraph != "") _paragraph += " ";
                    _paragraph += _part;
                }
            }
        }
        if (_paragraph != "") array_push(_paragraphs, _paragraph);
        node_info_rows = scr_node_info_wrap(_paragraphs, _cw / _scale);
        node_info_layout_key = _key;
        node_info_page = 0;
    }
    if (!variable_instance_exists(id, "node_info_active_type") || node_info_active_type != _type) {
        node_info_page = 0;
        node_info_active_type = _type;
    }
    var _capacity = _cols * _rows_per_col;
    var _pages = max(1, ceil(array_length(node_info_rows) / _capacity));
    node_info_page = clamp(node_info_page + scr_workspace_mouse_wheel_down() - scr_workspace_mouse_wheel_up(), 0, _pages - 1);

    draw_set_alpha(0.98);
    draw_set_color(make_color_rgb(12, 12, 22));
    draw_rectangle(_x, _y, _x + _w, _y + _h, false);
    draw_set_alpha(1);
    draw_set_color(make_color_rgb(80, 140, 220));
    draw_rectangle(_x, _y, _x + _w, _y + _h, true);
    draw_set_color(c_yellow);
    // Separate columns with a quiet rule, inset 5% from each panel edge.
    draw_set_color(make_color_rgb(45, 65, 90));
    for (var _divider = 1; _divider < _cols; _divider++) {
        var _divider_x = _x + _pad + _divider * (_cw + _gap) - _gap / 2;
        draw_line(_divider_x, _y + _h * 0.05, _divider_x, _y + _h * 0.95);
    }
    draw_set_color(c_yellow);
    var _title = L(_info.title);
    var _title_scale = min(_scale * 1.15, (_w - 2 * _pad) / max(1, string_width(_title)));
    draw_text_transformed(_x + _pad, _y + _pad, _title, _title_scale, _title_scale, 0);
    var _top = _y + _pad + _lh * 2;
    var _first = node_info_page * _capacity;
    var _count = min(_capacity, array_length(node_info_rows) - _first);
    var _balanced_rows = max(1, ceil(_count / _cols));
    draw_set_color(c_white);
    for (var _i = 0; _i < _count; _i++) {
        var _col = _i div _balanced_rows;
        var _row = _i mod _balanced_rows;
        var _row_txt = node_info_rows[_first + _i];
        draw_set_color(c_white);
        if (string_char_at(_row_txt, 1) == chr(1)) {
            _row_txt = string_delete(_row_txt, 1, 1);
            draw_set_color(make_color_rgb(110, 220, 255));
        }
        draw_text_transformed(_x + _pad + _col * (_cw + _gap),
            _top + _row * _lh - scr_lang_lift() * _scale,
            _row_txt, _scale, _scale, 0);
    }
    draw_set_color(make_color_rgb(140, 170, 205));
    draw_set_halign(fa_right);
    var _footer = (_pages > 1)
        ? L("Mouse wheel: pages") + "   " + string(node_info_page + 1) + " / " + string(_pages)
        : "";
    var _footer_scale = min(1, (_w - 2 * _pad) / max(1, string_width(_footer)));
    draw_text_transformed(_x + _w - _pad, _y + _h - _pad - _lh,
        _footer, _footer_scale, _footer_scale, 0);
    draw_set_font(_old_font);
    draw_set_halign(_old_ha);
    draw_set_valign(_old_va);
}

