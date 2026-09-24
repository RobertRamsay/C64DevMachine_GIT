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
                "One-stop VIC-II mode configuration: text, bitmap,",
                "multicolour, ECM, and their combinations.",
                "",
                "Sets screen/char/bitmap base pointers, $D011/$D016",
                "mode bits, and border/background colours in one node.",
                "Usually the first macro on the spine after INIT.",
				"Or IRQ based mode changes."
            ]
        },

        "MACRO_PRINT": {
            title: "PRINT",
            lines: [
                "X / Y / COL: LIT or VAR; old saves default to LIT.",
                "VAR X/Y clamp to 39/24; colour uses low 4 bits.",
                "Alignment overrides X/Y; choose DEF for presets.",
                "Runtime position also uses ZP $F5-$F8.",
                "Prints text to screen RAM at a given row/column.",
                "",
                "SOURCE: INLINE fixed text, or an ASSET (TEXT_DATA)",
                "read through a start/end byte window. Either end of",
                "that window can be a literal offset or a named VAR,",
                "so the printed slice can shift at runtime - e.g.",
                "paging through a longer block of asset text.",
                "",
                "COL sets the single text colour (0-15),",
                "\n",
                "PRE-CLEAR optionally wipes screen RAM before printing.",
				"\n",
                "H/V alignment can auto-left/centre/right and",
                "top/mid/bottom the text instead of a fixed X/Y."
            ]
        },

        "MACRO_PRINT_EXT": {
            title: "PRINT EXT",
            lines: [
                "X / Y / COL: LIT or VAR; old saves default to LIT.",
                "VAR X/Y clamp to 39/24; colour uses low 4 bits.",
                "Alignment overrides X/Y; choose DEF for presets.",
                "Runtime position also uses ZP $F5-$F8.",
                "Prints a numeric value - a named VAR or a CPU",
                "register (A/X/Y/SP/FLAGS) - to screen RAM.",
                "",
                "FORMAT: DEC, HEX, BIN, or BCD. FLAGS is always",
                "shown in binary with an N V - B D I Z C legend",
                "row underneath. Width follows the VAR's own size.",
                "Zero- or space-padding and H/V alignment options."
            ]
        },

        "MACRO_PLACE_CHAR": {
            title: "PLACE CHAR",
            lines: [
                "Writes one screencode (and optionally a colour) at",
                "a given row/column of screen + colour RAM.",
                "SET COL: LIT uses the palette; VAR reads a variable.",
                "Variable colour uses its low four bits (0-15).",
                "",
                "Address maths is shift-add (row*40 = row<<5 + row<<3),",
                "so it works against any screen base, not just $0400."
            ]
        },

        "MACRO_GET_CHAR": {
            title: "GET CHAR",
            lines: [
                "Reads the screencode (and optionally the colour)",
                "at a given row/column into named VARs.",
                "",
                "Companion read to PLACE CHAR - same pointer maths,",
                "opposite direction."
            ]
        },

        "MACRO_CLR_SCREEN": {
            title: "CLR SCRN RAM",
            lines: [
                "Fills 1000 bytes of screen RAM with a fill byte,",
                "starting at a chosen base address.",
                "",
                "Stops 8 bytes short of the full 1024-byte page so",
                "it never touches the sprite pointer table living",
                "at base+$3F8-$3FF."
            ]
        },

        "MACRO_CLEAR_BMP_RECT": {
            title: "CLR BMP RECT",
            lines: [
                "Zeroes a rectangular block of bitmap data, given in",
                "char-cell col/row/width/height, not pixels.",
                "",
                "Every zeroed bit-pair renders as background colour",
                "($D021) regardless of screen/colour RAM contents -",
                "a true wipe that doesn't touch either palette plane.",
                "",
                "Drop it before MOVE BMP BLK to pre-clear a room's",
                "target area, since MASK00 blending lets old pixels",
                "show through any gaps left by a previous room.",
                "",
                "COL/ROW/W/H each take an optional byte VAR. With a",
                "var set the literal is ignored and the value is read",
                "at runtime, so one node can wipe a moving rect (a",
                "falling tile, a wipe transition). No grid trim in",
                "var mode - keep col+w <= 40 and row+h <= 25. A var",
                "of 0 for W or H clears nothing."
            ]
        },

        "MACRO_VWAIT": {
            title: "VWAIT",
            lines: [
                "Waits for one specific raster line, gated on the",
                "$D011 bit-8 flag so it only fires in the top frame",
                "(lines 0-255), never the phantom repeat in the",
                "lower border.",
                "",
                "Use to sync code to a precise scanline, e.g. before",
                "a raster-split IRQ trick."
            ]
        },

        "MACRO_NOP_REPEAT": {
            title: "NOP REPEAT",
            lines: [
                "Emits an unrolled run of NOP ($EA), 0-255 of them.",
                "Cost is exactly 1 byte and 2 cycles per NOP, so a",
                "count of 8 costs 8 bytes / 16 cycles.",
                "",
                "Touches no registers, no ZP and no flags - safe to",
                "drop anywhere you need raster or cycle padding.",
                "",
                "Count is literal only: the run is unrolled at build",
                "time, so a variable could not be resolved."
            ]
        },
        "MACRO_WAIT": {
            title: "WAIT",
            lines: [
                "Blocking delay measured in whole frames (PAL 50/s,",
                "NTSC 60/s), up to 255 frames (~5.1s PAL).",
                "",
                "Counts raster wraps at line 255, gated on $D011 bit",
                "8 so only the top-frame instance is latched.",
                "Counter lives in X - no ZP used; clobbers A and X."
            ]
        },

        "MACRO_DISPLAY": {
            title: "DISPLAY",
            lines: [
                "Toggles the screen on/off via the DEN bit ($D011",
                "bit 4), a read-modify-write that preserves every",
                "other bit in the register.",
                "",
                "Safe alongside VSCROLL, bitmap mode, ECM, and the",
                "9th raster bit. Fixed cost: 8 bytes."
            ]
        },

        "MACRO_TEXT_SCROLL": {
            title: "TXT SCROLL",
            lines: [
                "Scrolls a line of inline text across the screen at",
                "a chosen row, one character-column per call.",
                "",
                "Speed, direction, screen row, and a working RAM",
                "buffer address are all configurable per node.",
				"\n",
				"_col01 , _spd03 , _trk02 , _wait : are current commands you can",
				"add, they become hidden and applied as the scroller meets them."
				
		
            ]
        },

        "MACRO_CHR": {
            title: "CHARSET",
            lines: [
                "Points the VIC at a custom character set asset and",
                "sets its base address in $D018.",
                "",
                "Pair with a MACRO_VIC node for full mode setup -",
                "this node only handles the charset pointer."
            ]
        },

        "MACRO_MAP": {
            title: "MAP",
            lines: [
                "Copies a flat char+colour map asset to screen RAM",
                "using a fast (zp),Y pointer-walk loop.",
                "",
                "Map width/height and the destination screen base",
                "are all configurable. For the newer tileset-driven",
                "flow with per-room stamping, see METAMAP instead."
            ]
        },

        "MACRO_METAMAP": {
            title: "METAMAP",
            lines: [
                "Flattens a META_TILESET room to screen + colour RAM.",
                "",
                "LIT mode: bakes one chosen room at compile time,",
                "copied to screen with a MAP-style loop.",
                "",
                "VAR mode: every room is compiled as a placement",
                "list + stamp table; a runtime stamper reads a named",
                "VAR and draws whichever room it points to - re-run",
                "the node any time that var changes to redraw."
            ]
        },

        "MACRO_MAP_SWITCH": {
            title: "MAP SWITCH",
            lines: [
                "Points an existing MACRO_MAP node at a different",
                "MAP_DATA asset: rewrites its ZP char/colour source",
                "pointers, resets scroll position to zero, and calls",
                "the shared map redraw routine.",
                "",
                "Needs a MACRO_MAP node already connected on the",
                "spine to read its ZP base from - this node only",
                "switches which map that setup is pointing at."
            ]
        },

        "MACRO_SCROLL": {
            title: "MAP H-SCROLL",
            lines: [
                "Horizontal map scrolling with a unified delta core:",
                "scroll_fine (0-7) and scrollx (column) are the",
                "single source of truth. $D016 is only ever written",
                "from scroll_fine, never read back.",
                "",
                "Left/right variants just set the direction sign",
                "and share the same scrolling routine."
            ]
        },

        "MACRO_METASCROLL": {
            title: "METASCROLL - QUICK GUIDE",
            lines: [
                "SETUP: Four-way smooth scrolling over a META_TILESET room. Pick TILESET and MAP. CLAMP ON stops the camera at the map edges.",
                "",
                "MOVE: Click MSC_L / MSC_R / MSC_U / MSC_D to create JSR nodes. Each call moves one pixel. Call MSC_Update once EVERY frame, after movement calls, even when standing still.",
                "",
                "COLOUR: Click to cycle through FOUR modes:",
                "",
                "FIXED - Fastest and smallest. One colour-RAM value for the whole room. NIB AUTO chooses the most common value; choose a manual NIB to override it.",
                "",
                "ROW BANDS - One colour per map row. Useful for sky/ground layouts on a stock C64; horizontal scrolling needs no colour-RAM shift.",
                "",
                "SHIFT STOCK - Per-character colour on a stock C64 using two screens. Reserve an extra 1K; click BUF to change its address (default $3800). Keep it clear of code, charset and map data.",
                "",
                "SHIFT C64U - Per-character colour for a C64 Ultimate in turbo mode. Too slow for clean scrolling on a stock C64.",
                "",
                "PREVIEW: Use RUN VIEW in the tileset editor to check the selected colour mode. In FIXED, use NIB AUTO or pick a colour from the COLOUR strip.",
                "",
                "SPACE: PLANES sets the map-data address. ZP BASE reserves 10 zero-page bytes. Check the memory bar for overlaps, including the SHIFT STOCK buffer.",
                "",
                "EDGES / HUD: BLANK CH must be a blank tile in your charset. OMIT TOP / OMIT BOT remove 0-8 rows each from scrolling, leaving space for a HUD and reducing work.",
                "",
                "PERFORMANCE: Omitting top rows also gives extra raster time. The LINES estimate turns red when work exceeds the budget; verify timing on your target machine.",
                "",
                "LIMITS: Left/up edges can show a one-pixel pop. Vertical scrolling can pop at an omitted-row seam and also moves a character HUD; use a raster split or sprites for a steady HUD."
            ]
        },

        "MACRO_VSCROLL": {
            title: "V-SCROLL",
            lines: [
                "Vertical scrolling for an 18-column map centred on",
                "the 40-column screen (offset 11). Scroll window is",
                "rows 1-22; rows 0/23/24 are blanked once at init.",
                "",
                "Chars and colour RAM scroll in lockstep. Two entry",
                "points: one scrolls content up, the other down."
            ]
        },

        "MACRO_BMP": {
            title: "BITMAP",
            lines: [
                "Auto-configures VIC bitmap mode from a Koala / raw",
                "bitmap asset: sets bitmap base, screen base, and",
                "loads the asset's screen+colour+bitmap planes.",
                "",
                "Simplest way to get a static hi-res or multicolour",
                "picture on screen."
            ]
        },

        "MACRO_VECTOR_BMP": {
            title: "VECTOR BMP",
            lines: [
                "Sets up the shared vector-bitmap runtime (interpreter",
                "+ multicolour plot routine) and streams a VECTOR_",
                "BITMAP asset's PLOT/SETCOL/END command list into it.",
                "",
                "The runtime is emitted once per build no matter how",
                "many VECTOR BMP/PAGE nodes reference it. Must sit",
                "before any VECTOR PAGE nodes that use the same asset."
            ]
        },

        "MACRO_VECTOR_PAGE": {
            title: "VECTOR PAGE",
            lines: [
                "Flips a multi-page VECTOR_BITMAP asset to a chosen",
                "page: clears the bitmap, fills screen/colour RAM +",
                "border from that page's 4 colours, then renders",
                "that page's command stream.",
                "",
                "Doesn't touch VIC mode registers - the VECTOR BMP",
                "setup node earlier on the spine owns that."
            ]
        },

        "MACRO_MOVE_BMP_BLOCK": {
            title: "MOVE BMP BLK",
            lines: [
                "Copies a rectangular block of bitmap data (char-cell",
                "units) from one bitmap to another, or within the",
                "same one. Optionally copies the matching screen +",
                "colour RAM too.",
                "",
                "X/Y offset VARs (in cells) are added to source and",
                "dest at runtime. Self-modifying operands keep each",
                "row a single fast LDA/STA pair."
            ]
        },

        "MACRO_FLIP_X": {
            title: "FLIP X",
            lines: [
                "Flips selected sprites horizontally using a lookup",
                "table: reads sprite data from an asset address,",
                "writes the flipped copy to a temp block, and points",
                "the sprite pointer table at the flipped copy.",
                "",
                "Auto-detects hi-res vs multicolour per sprite via",
                "$D01C at runtime - both LUTs are emitted inline."
            ]
        },

        "MACRO_SPR": {
            title: "SPRITE",
            lines: [
                "Sets up one hardware sprite: pointer, X/Y position,",
                "colour, and enable state.",
                "",
                "Combine with MOVE, ANIMATE, PRIORITY, ENABLER and",
                "the other sprite macros for full behaviour."
            ]
        },

        "MACRO_MOVE": {
            title: "MOVE (SPRITE)",
            lines: [
                "Minimal-byte unison sprite movement: applies a",
                "per-frame X/Y delta to a group of sprites (chosen",
                "by bitmask), as a literal or a named VAR.",
                "",
                "VAR mode reads the delta as a SIGNED byte: its sign",
                "bit picks the move direction at runtime, so one VAR",
                "can drive a sprite left/right or up/down just by",
                "changing sign - no separate direction flag needed.",
                "",
                "WRAP vs BOUNDED: by default the position simply",
                "rolls over at the 8-bit edge. Enable STOP to clamp",
                "movement at fixed screen walls instead.",
                "",
                "Toggle the $D010 9th-bit MSB register so X",
                "can range the full 0-343 sprite-visible width rather",
                "than wrapping at the 8-bit 0-255 boundary."
            ]
        },

        "MACRO_SEEK": {
            title: "SEEK",
            lines: [
                "Directional / AI seek movement: steers a sprite",
                "toward a target X/Y (literal or from named VARs),",
                "at a configurable speed with optional deceleration",
                "near the target and a widening catch box.",
                "",
                "Can also report distance/angle to the target into",
                "named VARs for further logic."
            ]
        },

        "MACRO_COLLISION": {
            title: "COLLIDE",
            lines: [
                "Basic sprite-vs-map collision probe: checks the map",
                "tile type under a sprite's position and reports a",
                "hit/type result into a named VAR."
            ]
        },

        "MACRO_COLL_ADV": {
            title: "COLL.ADV",
            lines: [
                "Advanced multi-point collision probe against map",
                "tile types, with per-edge/per-corner checks.",
                "",
                "DIRECT mode (bitmap hybrid): reads the screen byte",
                "itself as the collision type - the same byte that",
                "MOVE BMP BLK's WRITE COLL option writes from source",
                "tags - so no per-room tile-type table is needed.",
                "SCAN mode (char maps): looks the screen byte up in",
                "the map's generated <map>_TILE_TYPES table instead."
            ]
        },

        "MACRO_PRIORITY": {
            title: "PRIORITY",
            lines: [
                "Sets whether a sprite draws in front of or behind",
                "background characters, via $D01B."
            ]
        },

        "MACRO_SPR_ENABLE": {
            title: "ENABLER",
            lines: [
                "Turns a hardware sprite on or off via $D015 -",
                "a clean single-purpose toggle rather than hand-",
                "rolling the bitmask each time."
            ]
        },

        "MACRO_SPR_EXPAND": {
            title: "EXPANDER",
            lines: [
                "Toggles X and/or Y double-size expansion for a",
                "sprite via $D01D / $D017."
            ]
        },

        "MACRO_ANIM": {
            title: "ANIMATE",
            lines: [
                "Per-sprite-slot animation: up to 8 slots, each with",
                "its own list of frame values and X/Y position",
                "offsets (+/-) to step through over time.",
                "",
                "Place the node once before your core game loop to",
                "set it up - it exposes a JSR entry point that then",
                "appears in the picker on any JSR node, so the",
                "actual per-frame advance is called from wherever",
                "your loop needs it.",
                "",
                "DELAY is a frame counter, not a speed value: a lower",
                "DELAY advances sooner, so lower = faster animation."
            ]
        },

        "MACRO_LETTERS": {
            title: "KEYS A-Z",
            lines: [
                "Direct CIA1 matrix scan: a column is driven low on",
                "$DC00 and the rows read back from $DC01, so any",
                "number of keys can be held at once.",
                "",
                "Each enabled key sets its own bit in the ZP block",
                "and can JSR a label. Bit 0 is the first key in the",
                "grid, reading left to right.",
                "",
                "Not scannable: RESTORE (NMI line), and F2/F4/F6/F8",
                "(SHIFT plus F1/F3/F5/F7, not matrix positions)."
            ]
        },

        "MACRO_FNNUMBERS": {
            title: "KEYS 0-9 / Fn",
            lines: [
                "Direct CIA1 matrix scan: a column is driven low on",
                "$DC00 and the rows read back from $DC01, so any",
                "number of keys can be held at once.",
                "",
                "Each enabled key sets its own bit in the ZP block",
                "and can JSR a label. Bit 0 is the first key in the",
                "grid, reading left to right.",
                "",
                "Not scannable: RESTORE (NMI line), and F2/F4/F6/F8",
                "(SHIFT plus F1/F3/F5/F7, not matrix positions)."
            ]
        },

        "MACRO_MISCKEYS": {
            title: "KEYS MISC",
            lines: [
                "Direct CIA1 matrix scan: a column is driven low on",
                "$DC00 and the rows read back from $DC01, so any",
                "number of keys can be held at once.",
                "",
                "Each enabled key sets its own bit in the ZP block",
                "and can JSR a label. Bit 0 is the first key in the",
                "grid, reading left to right.",
                "",
                "KUP/KDN/KLF/KRT are the cursor DIRECTIONS: the CRSR",
                "key with the shift test built in (KUP = CRSR U/D +",
                "shift, KDN = CRSR U/D with no shift, and so on).",
                "",
                "Not scannable: RESTORE (NMI line), and F2/F4/F6/F8",
                "(SHIFT plus F1/F3/F5/F7, not matrix positions)."
            ]
        },

        "MACRO_MOUSE": {
            title: "MOUSE (1351)",
            lines: [
                "Reads a Commodore 1351 in proportional mode.",
                "POTX/POTY give a 6-bit delta each frame, which is",
                "sign-extended and added to a signed 16-bit X/Y",
                "held in zero page.",
                "",
                "ZP names a 7 byte block: +2/+3 is X, +4/+5 is Y —",
                "those are the addresses your own code reads.",
                "",
                "LF/RT/UP/DN fire once per frame while the mouse is",
                "moving on that axis — they are a movement report,",
                "not a held direction like the joystick's.",
                "",
                "Call this once per frame. Reading the pots needs",
                "CIA1 $DC00 bits 6-7 pointed at the port, which the",
                "KERNAL keyboard scan also writes."
            ]
        },

        "MACRO_JOY": {
            title: "JOYSTICK",
            lines: [
                "Reads a CIA joystick port and dispatches to JMP",
                "targets based on which direction/fire bits are",
                "set, via an AND/BNE test per bit.",
                "",
                "Connect JMP-target nodes for whichever directions/",
                "fire button you want to react to."
            ]
        },

        "MACRO_SID": {
            title: "SID",
            lines: [
                "Full SID music setup with a raster IRQ: configures",
                "the player, hooks a raster interrupt, and starts",
                "playback of an imported SID_MUSIC or SID_SFX asset.",
                "",
                "For the built-in MUSIC_MAKER authoring tool instead",
                "of an imported .sid file - with multi-song support,",
                "hard restart and tempo control - see SID SONG."
            ]
        },

        "MACRO_SID_SONG": {
            title: "SID SONG",
            lines: [
                "Multi-song player driven by the built-in MUSIC_MAKER",
                "authoring tool (an asset you compose songs in), with",
                "hard-restart support, per-asset tempo, and a write-",
                "only SID register shadow so playback never read-",
                "modify-writes $D400-$D41C.",
                "",
                "Banks BASIC ROM out permanently at init ($01=$36),",
                "keeping the KERNAL in so $0314/$0315 IRQ chaining",
                "still works, freeing $03-$8F for player state.",
                "",
                "Pattern sentinels: $FF = REST (gate off, tail still",
                "runs), $FE = HOLD (ringing note continues), 0-95 =",
                "chromatic note index."
            ]
        },

        "MACRO_SID_SOUND": {
            title: "SID SOUND",
            lines: [
                "Plays a single note/sound on a chosen SID voice:",
                "waveform, frequency, ADSR, and pulse width are all",
                "configurable as literals or named VARs.",
                "",
                "WAVE ($D404) carries both the waveform bits and the",
                "gate bit, and is always written last so the note",
                "gates on only once everything else is set.",
                "",
                "Note can also come from a TEXT_DATA asset acting as",
                "a note list, indexed at runtime."
            ]
        },

        "MACRO_SFX": {
            title: "SFX",
            lines: [
                "Plays a compiled INS2SND2 sound-effect binary blob",
                "asset - a pre-authored SFX rather than a single",
                "note built from raw ADSR/waveform fields."
            ]
        },

        "MACRO_TRACK": {
            title: "TRACK",
            lines: [
                "Runtime music track switcher: polls GETIN each",
                "frame and swaps to a different SID/track on input.",
                "",
                "SEI/CLI guards prevent an IRQ firing mid-init or",
                "mid-GETIN. Requires sid_getin to resolve to $FFE4",
                "at build time."
            ]
        },

        "MACRO_SID_PAUSE": {
            title: "SID PAUSE",
            lines: [
                "Stops and restarts the music tick. PAUSE sets a flag that",
                "every SID play call is guarded by, so the IRQ keeps firing",
                "- raster splits and everything else in the handler are",
                "untouched - and only the music stops advancing.",
                "",
                "That hands all three SID voices to whatever you want them",
                "for: VOI64 speech, sound effects, a jingle. RESUME gives",
                "them straight back.",
                "",
                "PAUSE also silences the three voices, because a note with",
                "a long release would otherwise drone on underneath.",
                "",
                "Nothing needs restoring on RESUME: SID players rewrite the",
                "whole register set every frame, so the first tick after",
                "puts the chip back. The tune continues from where it",
                "paused rather than restarting - its counters live in RAM",
                "and were never touched.",
                "",
                "Costs nothing unless used: with no SID PAUSE node in the",
                "project the guards are not emitted at all."
            ]
        },

        "MACRO_VOI64_MASTER": {
            title: "VOI64 MASTER",
            lines: [
                "Sets the SID up for speech and emits the Voi64 player",
                "once. Every VOI64 SAY in the project needs one of these",
                "connected - without it a SAY emits nothing.",
                "",
                "PITCH is the glottal rate in Hz. THROAT scales the first",
                "formant (deeper / chestier), MOUTH scales the second and",
                "third (brighter / more forward). SPEED is 0-255 with 128",
                "nominal, and HIGHER IS FASTER.",
                "",
                "The player is BLOCKING: it owns the CPU until the phrase",
                "ends, so no raster effects and no music while it speaks.",
                "",
                "Voices: V3 is a silent pitch source, V1 is the first",
                "formant hard-synced to it, V2 is the second. On unvoiced",
                "sounds V3 switches to noise and carries the frication."
            ]
        },

        "MACRO_VOI64_SAY": {
            title: "VOI64 SAY",
            lines: [
                "Speaks a phrase. TEXT mode runs English letter-to-sound",
                "on the PC at build time, so the C64 never sees a letter -",
                "only the finished frames. PHONEME mode takes a phoneme",
                "string verbatim, which is how you fix a word the rules",
                "get wrong.",
                "",
                "Source is either typed inline or a TEXT_DATA asset. Both",
                "are known at build time, which is what keeps the runtime",
                "cost to eight bytes per glottal period.",
                "",
                "In TEXT DATA mode, LINE FROM / LINE TO pick a slice of the",
                "asset - one phrase per line, so a single asset becomes a",
                "phrase bank several SAY nodes share. Leave both blank for",
                "the whole thing. Lines rather than the byte offsets PRINT",
                "uses: the asset never reaches the C64, so a byte range",
                "would only let you cut a word in half.",
                "",
                "Either end can be a byte VAR instead of a number, so the",
                "program picks its line at runtime - set the var, call the",
                "macro. Line 1-255.",
                "",
                "COST: a var-driven SAY compiles EVERY line of the asset",
                "and indexes them through a pointer table, because the",
                "range is not known until the program runs. A fixed range",
                "compiles only the lines it names.",
                "",
                "PITCH / SPEED / THROAT / MOUTH show a dash when they are",
                "inherited from the master. Type a value to override it",
                "for this phrase only.",
                "",
                "PREVIEW VOICE plays it through the tool using the same",
                "phoneme string the build will emit."
            ]
        },

        "MACRO_RANDOM": {
            title: "RANDOM",
            lines: [
                "SID voice-3 noise generator RNG: optionally sets up",
                "the oscillator once, reads $D41B, and can clamp the",
                "result branchlessly into a [MIN,MAX] range.",
                "",
                "Result is left in A and/or stored to a named VAR."
            ]
        },

        "MACRO_MATH": {
            title: "MATH",
            lines: [
                "ADD / SUB / MUL / DIV / ONE-MINUS / INVERT-SIGN on",
                "named VARs, signed two's-complement throughout.",
                "",
                "Each operand's width follows its own VAR meta (byte",
                "or word). ADD/SUB/ONEMINUS/INVSIGN are inlined; MUL/",
                "DIV call a shared math_mul16 / math_div16 routine",
                "emitted once per build.",
                "",
                "Working ZP: $F2-$F8, chosen to avoid the MACRO_MAP",
                "reservation ($FB-$FE) and vector-bmp scratch."
            ]
        },

        "MACRO_UCI_REU": {
            title: "UCI LOAD REU",
            lines: [
                "Asks a 1541 Ultimate / Ultimate 64 to load a .reu",
                "image from its OWN storage into REU memory.",
                "",
                "For a PRG run from the Ultimate's file browser, with",
                "no PC involved. VICE gets its image on the command",
                "line instead, and F6 pushes one over the network -",
                "this node does nothing under emulation.",
                "",
                "FILE follows the chosen LOAD_REU asset unless you",
                "type an override, so a rename cannot leave it",
                "pointing at a file that is no longer written.",
                "",
                "STAT optionally stores the first status byte:",
                "  $30 '0' = OK",
                "  $38 '8' = 84 REU NOT ENABLED / 85 FILE NOT OPENED",
                "  $FF     = no status seen (no Ultimate, or no reply)",
                "",
                "Falls through to the next node on every path,",
                "including when no Ultimate is present."
            ]
        },
        "MACRO_MOVE_MEM": {
            title: "MOVE MEM",
            lines: [
                "Copies a byte range [src_start..src_end) to a",
                "destination address at runtime.",
                "",
                "Unrolled inline if 8 bytes or fewer, otherwise a",
                "page-aware loop (capped at 1024 bytes).",
                "",
                "Forward copy only - overlapping ranges where dest",
                "is above source will corrupt data."
            ]
        },

        "MACRO_IRQ": {
            title: "IRQ",
            lines: [
                "Declares one raster interrupt: the line it fires on,",
                "and optionally a JSR into SID music playback.",
                "",
                "Exposes two labels other nodes can JSR to: the",
                "handler entry point, and an init routine that hooks",
                "the vector. Needs an IRQ HANDLER elsewhere on the",
                "spine to actually dispatch to it."
            ]
        },

        "MACRO_IRQ_HANDLER": {
            title: "IRQ HANDLER",
            lines: [
                "Emits the unified table-driven raster IRQ dispatcher.",
                "",
                "Reads every connected IRQ node, sorts them by raster",
                "line, builds the raster/target lookup tables, and",
                "emits a self-modifying JSR dispatch handler.",
                "",
                "Vector mode: Kernal-chained ($0314/$0315) or direct",
                "hardware vector ($FFFE/$FFFF)."
            ]
        },

        "MACRO_CODE": {
            title: "CODE",
            lines: [
                "A freeform block of hand-written 6502 assembly,",
                "assembled inline exactly where the node sits on",
                "the spine.",
                "",
                "Escape hatch for anything the macro library doesn't",
                "cover yet - labels, opcodes and directives all work",
                "as normal."
            ]
        },

        "MACRO_LOADER": {
            title: "MACRO LOADER",
            lines: [
                "Loads one file from a LOAD_ORG D64 image on demand,",
                "via KERNAL SETLFS/SETNAM/LOAD with secondary $01,",
                "so the file loads to its own embedded PRG header",
                "address.",
                "",
                "Called wherever it's needed on the spine - there's",
                "no fixed load-order requirement for this macro."
            ]
        },

        "MACRO_LOAD_GAME": {
            title: "LOAD GAME",
            lines: [
                "Loads a save file from a LOAD_ORG D64 back into RAM",
                "at runtime, restoring whatever it holds.",
                "",
                "Relies on a BYTE_DATA asset with USE AS SAVE FILE",
                "enabled and linked into the LOAD_ORG. That block is",
                "where your persisted VARs actually live - lives,",
                "coins, stats, or anything else you want to survive",
                "a reset."
            ]
        },

        "MACRO_SAVE_GAME": {
            title: "SAVE GAME",
            lines: [
                "Writes a BYTE_DATA asset's current contents to disk",
                "via a LOAD_ORG D64, persisting it between sessions.",
                "",
                "The asset must have USE AS SAVE FILE enabled and be",
                "linked into the LOAD_ORG - that's the block your",
                "game's persistent VARs (lives, coins, stats, etc.)",
                "should be reading from and writing to."
            ]
        },

        "MACRO_REU": {
            title: "REU - RAM EXPANSION UNIT",
            lines: [
                "DMA transfer between C64 RAM and REU RAM,",
                "via registers $DF00-$DF0A.",
                "",
                "OP  STASH  copies C64 -> REU",
                "    FETCH  copies REU -> C64",
                "    SWAP   exchanges both directions",
                "    COMPARE verifies only, no write",
                "",
                "C64   16-bit start address in C64 RAM",
                "REU   16-bit start address in REU RAM",
                "BANK  REU bank, 0-255 (most units: bank 0 only)",
                "LEN   bytes to move, $0000 = 65536",
                "",
                "AUTOLOAD reloads the start addresses once the",
                "transfer finishes, so the node can fire again",
                "without re-setting anything.",
                "",
                "FIX C64 / FIX REU hold that side's address",
                "still during the transfer - use for fills or",
                "repeated single-byte reads/writes.",
                "",
                "FF00-disable is always set on the command byte:",
                "without it, a stray write to $FF00 can",
                "re-trigger the last queued transfer."
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
    for (var _p = 0; _p < array_length(_paragraphs); _p++) {
        if (_p > 0) array_push(_rows, "");
        var _line = "";
        var _text = _paragraphs[_p];
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

    var _preferred_w = (array_length(_info.lines) <= 14) ? 800 : 1440;
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
                if (_part == "") {
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
    node_info_page = clamp(node_info_page + mouse_wheel_down() - mouse_wheel_up(), 0, _pages - 1);

    draw_set_alpha(0.98);
    draw_set_color(make_color_rgb(12, 12, 22));
    draw_rectangle(_x, _y, _x + _w, _y + _h, false);
    draw_set_alpha(1);
    draw_set_color(make_color_rgb(80, 140, 220));
    draw_rectangle(_x, _y, _x + _w, _y + _h, true);
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
        draw_text_transformed(_x + _pad + _col * (_cw + _gap),
            _top + _row * _lh - scr_lang_lift() * _scale,
            node_info_rows[_first + _i], _scale, _scale, 0);
    }
    draw_set_color(make_color_rgb(140, 170, 205));
    draw_set_halign(fa_right);
    var _footer = (_pages > 1)
        ? L("Mouse wheel: pages") + "   " + string(node_info_page + 1) + " / " + string(_pages)
        : L("Read down each column");
    var _footer_scale = min(1, (_w - 2 * _pad) / max(1, string_width(_footer)));
    draw_text_transformed(_x + _w - _pad, _y + _h - _pad - _lh,
        _footer, _footer_scale, _footer_scale, 0);
    draw_set_font(_old_font);
    draw_set_halign(_old_ha);
    draw_set_valign(_old_va);
}

