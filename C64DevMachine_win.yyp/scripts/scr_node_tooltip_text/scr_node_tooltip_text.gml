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
                "show through any gaps left by a previous room."
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
                "WIDE X toggles the $D010 9th-bit MSB register so X",
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
                "the vector. Needs an IRQ SHELL elsewhere on the",
                "spine to actually dispatch to it."
            ]
        },

        "MACRO_IRQ_HANDLER": {
            title: "IRQ SHELL",
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
