/// @desc scr_node_spawn(node_type, xx, yy)
/// @param {string} node_type
/// @param {real}   xx
/// @param {real}   yy
/// Creates and initialises a c64 node of the given type at the given position.
/// Returns the created instance.

function scr_node_spawn(_type, _xx, _yy) {

    var _n        = instance_create_layer(_xx, _yy, "Layer_Nodes", obj_c64_node);
    _n.node_type  = _type;

    switch (_type) {

        // -------------------------------------------------------
        // LABEL
        // -------------------------------------------------------
case "LABEL": {
            _n.node_title = "ADDRESS LABEL";
            _n.pc_address = global.start_pc;
            // Find a unique default label name with hex suffix
            var _base    = "target";
            var _name    = _base;
            var _counter = 0;
            var _found   = true;
            while (_found && _counter < 256) {
                _found = false;
                with (obj_c64_node) {
                    if (node_type == "LABEL" && string(instructions[0][1]) == _name) {
                        _found = true;
                        break;
                    }
                }
                if (_found) {
                    var _h = decimal_to_hex(_counter);
                    while (string_length(_h) < 2) _h = "0" + _h;
                    _name = _base + "_" + string_upper(_h);
                    _counter++;
                }
            }
            _n.instructions = [["label", _name]];
            break;
        }

        // -------------------------------------------------------
        // COMMENT
        // -------------------------------------------------------
        case "COMMENT":
            _n.node_title   = "COMMENT";
            _n.instructions = [["Comment", ""]];
            _n.width        = 240;
            _n.pc_address   = 0x1200;
            break;

        // -------------------------------------------------------
        // ORG
        // -------------------------------------------------------
        case "ORG":
            _n.node_title   = "ORG BLOCK";
            _n.instructions = [["org", 0]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

        // -------------------------------------------------------
        // MACRO_DISPLAY
        // [0] mnem   [1] mode (0 = OFF, 1 = ON)
        // RMW on $D011 bit 4 — leaves every other bit untouched.
        // -------------------------------------------------------
        case "MACRO_DISPLAY":
            _n.node_title   = "DISPLAY";
            _n.instructions = [["macro_display", 1]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

        // -------------------------------------------------------
        // MACRO_WAIT
        // [0] mnem
        // [1] frames_lit  (1-255, stored as FRAMES not hundredths)
        // [2] use_var     (0 = LIT, 1 = VAR)
        // [3] var_name    (UV byte)
        // Counter lives in X — no ZP used. Clobbers A and X.
        // -------------------------------------------------------
        case "MACRO_WAIT":
            _n.node_title   = "WAIT";
            _n.instructions = [["macro_wait", 50, 0, ""]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

        // -------------------------------------------------------
        // MACRO_VWAIT
        // -------------------------------------------------------
        case "MACRO_VWAIT":
            _n.node_title   = "VWAIT";
            //                              [0]          [1]   [2]use_var [3]var_name
            _n.instructions = [["macro_vwait", 0xFB, 0, ""]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

        case "MACRO_PRINT":
            _n.node_title   = "PRINT";
            // Indices:
            //   0  mnem
            //   1  X            2  Y           3  col         4  pre-clear
            //   5  inline text  6  inline addr 7  align_h     8  align_v
            //   9  src mode (0=inline, 1=asset)
            //  10  asset name   11 start off   12 end off (0=auto)
            _n.instructions = [["macro_print", 0, 0, 1, 0, "", 0x2000, 0, 0, 0, "", 0, 0, 0x0400, 0, "", 0, ""]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

        case "MACRO_PRINT_EXT":
            _n.node_title   = "PRINT EXT";
            // Indices:
            //   0  mnem
            //   1  sx           2  sy          3  col         4  pre-clear
            //   5  src_mode (0=VAR, 1=REGISTER)
            //   6  var_name     7  reg_id (0=A 1=X 2=Y 3=SP 4=FLAGS)
            //   8  fmt (0=DEC 1=HEX 2=BIN 3=BCD)
            //   9  align_h      10 align_v     11 pad (0=zeros, 1=spaces)
            _n.instructions = [["macro_print_ext", 0, 0, 1, 0, 0, "", 0, 1, 0, 0, 0]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

		// -------------------------------------------------------
		// MACRO_SPR
		// -------------------------------------------------------
		case "MACRO_SPR":
		    _n.node_title   = "SPRITE";
		    _n.instructions = [["macro_spr", "", 0, 175, 128, 0, 1]];
		    //                       ^name ^slot ^x ^y ^frame ^set_globals
		    _n.pc_address   = global.start_pc;
		    with (_n) { event_user(0); }
		    break;

        // -------------------------------------------------------
        // MACRO_METAMAP
		// -------------------------------------------------------
	    // instructions[0]: ["macro_metamap", tileset_name, map_index, base_addr, col_row_start, zp_base]
	case "MACRO_METAMAP":
        _n.node_title   = "METAMAP";
        _n.node_type    = "MACRO_METAMAP";
        // slot 6 = src_mode (0 = LIT map index, 1 = VAR map index)
	// slot 7 = map_var name (UV_ byte var) when src_mode == 1
	_n.instructions = [["macro_metamap", "", 0, 0x8000, 0, 0x50, 0, ""]];
        _n.pc_address   = global.start_pc;
        with (_n) { event_user(0); }
        break;
		// -------------------------------------------------------
	    // MACRO_SID
        // -------------------------------------------------------
	     case "MACRO_SID":
		    _n.node_title   = "SID MUSIC";
		    _n.instructions = [["macro_sid", "", 0, 12]];
		    _n.pc_address   = global.start_pc;
		    with (_n) { event_user(0); }
		    break;

        // -------------------------------------------------------
        // MACRO_TRACK
        // -------------------------------------------------------
        case "MACRO_TRACK":
            _n.node_title   = "TRACK";
            _n.instructions = [["macro_track", 0]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;
			
			
        // -------------------------------------------------------
        // MACRO_SCROLL
        // -------------------------------------------------------
		case "MACRO_SCROLL":
            _n.node_title   = "MAP H SCROLL";
            _n.instructions = [["MACRO_SCROLL", 0, 25, 1, 1, 1, "", 0]];
            _n.pc_address   = global.start_pc;
            _n.scroll_alias = "scr" + string(instance_number(obj_c64_node));
            with (_n) { event_user(0); }
            break;
			
		case "MACRO_VSCROLL":
            _n.node_title   = "MAP V SCROLL";
            _n.scroll_alias = "";
            _n.instructions = [["MACRO_VSCROLL", 0, 40, 1]];
			with (_n) { event_user(0); }
        break;
			
		// -------------------------------------------------------
        // MACRO_TEXT_SCROLL
        // -------------------------------------------------------
		
		case "MACRO_TEXT_SCROLL":
		    _n.node_title   = "TEXT SCROLL";
		    _n.instructions = [["macro_text_scroll", 23, 1, 2, 0, 0xC000, "HELLO WORLD ", 6, 27]];
		    _n.pc_address   = global.start_pc;
		    with (_n) { event_user(0); }
		    break;

		// -------------------------------------------------------
		// MACRO_JOY
		// -------------------------------------------------------
		case "MACRO_JOY":
		    _n.node_title   = "JOYSTICK";
		    _n.instructions = [
				["macro_joy", 2, 0xF8],     // name, port, ZP
				[0x19, "URF",  0],          // 1: UP+RT+FIRE
		        [0x15, "ULF",  0],          // 2: UP+LF+FIRE
		        [0x1A, "DRF",  0],          // 3: DN+RT+FIRE
		        [0x16, "DLF",  0],          // 4: DN+LF+FIRE
		        [0x09, "UPR",  0],          // 5: UP+RT
		        [0x05, "UPL",  0],          // 6: UP+LF
		        [0x0A, "DNR",  0],          // 7: DN+RT
		        [0x06, "DNL",  0],          // 8: DN+LF
		        [0x11, "UPF",  0],          // 9: UP+FIRE
		        [0x12, "DNF",  0],          // 10: DN+FIRE
		        [0x14, "LFF",  0],          // 11: LF+FIRE
		        [0x18, "RTF",  0],          // 12: RT+FIRE
		        [0x10, "FR",   0],          // 13: FIRE
		        [0x01, "UP",   0],          // 14: UP
		        [0x02, "DN",   0],          // 15: DOWN
		        [0x04, "LF",   0],          // 16: LEFT
		        [0x08, "RT",   0],          // 17: RIGHT
		        [0xFF, "NON",  0]           // 18: NO INPUT (nothing pressed)
				//[0xFF, "joy_done",    1],   // FALLBACK
		    ];
		    _n.pc_address = global.start_pc;
		    with (_n) { event_user(0); }
		    break;

        // -------------------------------------------------------
        // MACRO_BMP
		// instructions[0]: ["macro_bmp", asset_name, bmp_addr, force_vic_bank]
        // -------------------------------------------------------
        case "MACRO_BMP":
            _n.node_title   = "BITMAP";
            //                              [1]asset [2]bmp_addr [3]force_vic_bank [4]preclear
            _n.instructions = [["macro_bmp", "", 0x4000, 0, 0]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

        // -------------------------------------------------------
        // DATA_SID
        // -------------------------------------------------------
        case "DATA_SID":
            _n.node_title   = "SID MUSIC";
            _n.instructions = [["sid_file", "", 0, 0, 0, 0, 0, ""]];
            _n.pc_address   = 0x1000;
            with (_n) { event_user(0); }
            break;

        // -------------------------------------------------------
        // SPR64
        // -------------------------------------------------------
        case "SPR64":
            _n.node_title   = "SPR64";
            _n.instructions = [["spr", "", "", 0, "SPRITES", 0, 0, 0]];
            _n.pc_address   = 0x7000;
            with (_n) { event_user(0); }
            break;

        // -------------------------------------------------------
        // BITMAP_KLA
        // -------------------------------------------------------
        case "BITMAP_KLA":
            _n.node_title   = "BITMAP KLA";
            _n.instructions = [["bitmap_kla", "", 0]];
            _n.pc_address   = 0x4000;
            with (_n) { event_user(0); }
            break;
			
		// -------------------------------------------------------
        // MACRO VIC - SETUP THE VIC
        // -------------------------------------------------------
		case "MACRO_VIC":
		    _n.node_title   = "MACRO VIC";
		    _n.instructions = [["macro_vic", "TEXT", 0, 0x0400, 0x2000, 0, 0, 0, 0, 0]];
		    _n.pc_address   = global.start_pc;
		    with (_n) { event_user(0); }
		    break;

        // -------------------------------------------------------
        // RAW_DATA
        // -------------------------------------------------------
        case "RAW_DATA":
            _n.node_title   = "RAW DATA";
            _n.instructions = [["raw", "FF,FF,FF"]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;
			
		case "NAMED_LOC":
		    _n.node_title    = "NAMED LOC";
		    _n.instructions  = [["named_loc", ""]];
		    _n.pc_address    = 0;
		    _n.is_draggable  = false;
		    break;

		case "GET_VAR":
		    _n.node_title    = "GET VAR";
		    //                  [0]      [1]name [2]src_mode [3]asset [4]off_mode [5]off_lit [6]off_var
		    //                  src_mode: 0=named var, 1=BYTE_DATA asset
		    //                  off_mode: 0=none/literal, 1=UV var, 2=X, 3=Y
		    _n.instructions  = [["var_op", "", 0, "", 0, 0, ""]];
		    _n.pc_address    = global.start_pc;
		    _n.is_draggable  = false;
		    break;

		case "SET_VAR":
		    _n.node_title    = "SET VAR";
		    //                  [0]      [1]name [2]val [3]mode [4]sign [5]src_mode [6]srcV1 [7]ptr_byte_mode [8]offset_x
		    _n.instructions  = [["var_op", "", 0, 0, 0, 0, "", 0, 0]];
		    _n.pc_address    = global.start_pc;
		    _n.is_draggable  = false;
		    break;

		case "INC_VAR":
		    _n.node_title    = "INC VAR";
		    _n.instructions  = [["var_op", ""]];
		    _n.pc_address    = global.start_pc;
		    _n.is_draggable  = false;
		    break;

		case "DEC_VAR":
		    _n.node_title    = "DEC VAR";
		    _n.instructions  = [["var_op", ""]];
		    _n.pc_address    = global.start_pc;
		    _n.is_draggable  = false;
		    break;

		// -------------------------------------------------------
		// COPY_VAR — copy SRC var to DST var
		// instructions[0]: ["copy_var", src_name, dst_name]
		// -------------------------------------------------------
		case "COPY_VAR":
		    _n.node_title    = "COPY VAR";
		    _n.instructions  = [["copy_var", "-src var-", "-dest var-"]];
		    _n.pc_address    = global.start_pc;
		    _n.is_draggable  = false;
		    break;
		
		// -------------------------------------------------------
		// MACRO_PRIORITY
		// -------------------------------------------------------
			
		case "MACRO_PRIORITY":
		    _n.node_title   = "PRIORITY";
		    _n.instructions = [["macro_priority", 0, 0]];
		    _n.pc_address   = global.start_pc;
		    with (_n) { event_user(0); }
		    break;

		// -------------------------------------------------------
		// MACRO_SPR_ENABLE
		// -------------------------------------------------------
		case "MACRO_SPR_ENABLE":
		    _n.node_title   = "ENABLER";
		    _n.instructions = [["macro_spr_enable", 0, 0]];
		    _n.pc_address   = global.start_pc;
		    with (_n) { event_user(0); }
		    break;
			
		// -------------------------------------------------------
		// MACRO_SPR_EXPAND
		// -------------------------------------------------------
		case "MACRO_SPR_EXPAND":
		    _n.node_title   = "EXPANDER";
		    _n.instructions = [["macro_spr_expand", 0, 0]];
		    _n.pc_address   = global.start_pc;
		    with (_n) { event_user(0); }
		    break;

		// -------------------------------------------------------
        // MACRO_FLIP_X
        // -------------------------------------------------------
        case "MACRO_FLIP_X":
            _n.node_title   = "FLIP SPR X";
            _n.instructions = [["macro_flip_x", 0x2800, 1]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;
		// -------------------------------------------------------
		// BANK_SWITCH
		// instructions[0]: ["bank_switch", v01, keep_irq_off, write_ddr, mode_index]
		//   v01         = value written to $01 (config byte)
		//   keep_irq_off= 1 = omit CLI (leave IRQs disabled), 0 = emit CLI
		//   write_ddr   = 1 = emit $00 = $2F setup first, 0 = skip
		//   mode_index  = index into named mode table (0-7 = modes 24-31), -1 = RAW
		// -------------------------------------------------------
		case "BANK_SWITCH":
		    _n.node_title   = "BANK SWITCH";
		    _n.instructions = [["bank_switch", 0x37, 0, 1, 7]];
		    _n.pc_address   = global.start_pc;
		    with (_n) { event_user(0); }
		    break;

		// -------------------------------------------------------
		// MACRO_REU
		// REU (RAM Expansion Unit) DMA transfer — $DF00-$DF0A.
		// instructions[0]: ["macro_reu", op, c64_addr, reu_addr, bank, len, autoload, fix_c64, fix_reu]
		//   op       = 0 STASH (C64->REU), 1 FETCH (REU->C64), 2 SWAP, 3 COMPARE
		//   c64_addr = 16-bit C64 RAM address
		//   reu_addr = 16-bit REU RAM address (within the bank)
		//   bank     = REU bank (0-255, most REUs only populate bank 0)
		//   len      = 16-bit transfer length ($0000 = 65536 bytes)
		//   autoload = 1 = reload start addresses after the transfer completes
		//   fix_c64  = 1 = don't advance the C64 address (fill/scan pattern)
		//   fix_reu  = 1 = don't advance the REU address (fill/scan pattern)
		// -------------------------------------------------------
		case "MACRO_REU":
		    _n.node_title   = "REU";
		    _n.instructions = [["macro_reu", 0, 0xC000, 0x0000, 0, 0x0100, 0, 0, 0]];
		    _n.pc_address   = global.start_pc;
		    with (_n) { event_user(0); }
		    break;

		// -------------------------------------------------------
        // COND_IF
        // -------------------------------------------------------
        case "COND_IF":
            _n.node_title   = "IF BYTE";
            _n.instructions = [["cond_if", "", 0, "", "eq", false]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

		// -----------------------------------------------------------------
        // COND_IF_WORD
        // Same field layout as COND_IF, but both the source var and the
        // compare var are 16-bit ("word" encoding). The compare emits a
        // two-stage 6502 sequence (high half, then low half) so values up
        // to $FFFF are reachable. Pickers filter to word vars only, so a
        // byte/word mismatch is structurally impossible.
        // [1] var_name  [2] cmp_value (0-65535)  [3] goto_label
        // [4] mode (eq/ne/lt/gte/gt/lte)  [5] cmp_var
        // -----------------------------------------------------------------
        case "COND_IF_WORD":
            _n.node_title   = "IF WORD";
            _n.instructions = [["cond_if_word", "", 0, "", "eq", false]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;
			
		// -------------------------------------------------------
        // MACRO_CODE
        // -------------------------------------------------------
        case "MACRO_CODE":
            _n.node_title      = "Code Block";
            _n.instructions    = [["code_block", ""]];
            _n.code_descriptor = "Code Block";
            _n.pc_address      = global.start_pc;
            with (_n) { event_user(0); }
            break;

        // -------------------------------------------------------
        // MACRO_SEEK
        // -------------------------------------------------------
        case "MACRO_SEEK":
            _n.node_title   = "SEEK";
            // [name, mask, tx, ty, spd, near, spdn, widex, bound, mode,
            //  tx_uv, tx_vnm, ty_uv, ty_vnm, dist_uv, dist_vnm, ang_uv, ang_vnm]
            _n.instructions = [["macro_seek", 1, 160, 120, 2, 0, 1, 0, 0, 0, 0, "", 0, "", 0, "", 0, "", 0]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

        // -------------------------------------------------------
        // MACRO_MOVE_BMP_BLOCK
        // -------------------------------------------------------
        case "MACRO_MOVE_BMP_BLOCK":
            _n.node_title   = "MOVE BMP BLOCK";
            // [0]  name
            // [1]  src_bmp    [2]  dst_bmp
            // [3]  sx         [4]  sy
            // [5]  dx         [6]  dy
            // [7]  w          [8]  h
            // [9]  sxv        [10] syv
            // [11] dxv        [12] dyv
            // [13] copy_col   (colour RAM  — src cell's col3)
            // [14] blend      (0 = MASK00 transparent, 1 = OPAQUE clobber)
            // [15] copy_scr   (screen RAM  — src cell's col1/col2)
            //
            // Default: MASK00 + both palette writes. The source cell owns the
            // palette; its %00 pairs are holes and let the destination show
            // through. Surviving destination pixels are repainted into the
            // source cell's colours (unavoidable — one screen/colour byte per
            // cell), which is invisible when the destination pixels are %00.
            // [16] src_mode   0 = LIT (one block, params on the node)
            //                 1 = ASSET (walk a BYTE_DATA list of 6-byte records)
            // [17] asset_name BYTE_DATA asset holding the record list
            // [18] start_idx  record index to start walking from
            // [19] rec_count  0 = walk until the $FF terminator, else exact count
            //
            // ASSET record layout (6 bytes, stride 6):
            //   [0] sc  [1] sr  [2] dc  [3] dr  [4] w  [5] h
            // Terminator: $FF in byte [0].
            // blend / copy_scr / copy_col are NODE-level and apply to every record.
            // [16] src_mode   0 = LIT (one block, params on the node)
            //                 1 = ASSET (walk a BYTE_DATA list of 6-byte records)
            // [17] asset_name BYTE_DATA asset holding the record list
            // [18] entry_var  VAR holding the record index to start from.
            //                 "" = start at record 0 (no runtime multiply emitted).
            //
            // ASSET record layout (6 bytes, stride 6):
            //   [0] sx  [1] sy  [2] dx  [3] dy  [4] w  [5] h
            // Terminator: $FF in byte [0].
            //
            // With an entry VAR the asset becomes a BANK of scenes: several
            // record runs, each ending in its own $FF. Point the VAR at a run's
            // first record and the walker draws that run and stops. Same shape
            // as MACRO_METAMAP's VAR room selection.
            //
            // blend / copy_scr / copy_col are NODE-level and apply to every record.
			_n.instructions = [["macro_move_bmp_block", 0x8000, 0x4000, 0, 0, 0, 0, 1, 1, "", "", "", "", 1, 0, 1, 0, "", "", 0, ""]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;


        // -------------------------------------------------------
        // MACRO_PLACE_CHAR
        // [0] mnem
        // [1] col_lit   [2] col_vmode   [3] col_var
        // [4] row_lit   [5] row_vmode   [6] row_var
        // [7] char_src (0=LIT 1=VAR 2=BYTE_DATA)
        // [8] char_lit  [9] char_var    [10] char_asset
        // [11] idx_vmode (0=LIT 1=VAR)  [12] idx_lit  [13] idx_var
        // [14] set_col  [15] col_val
        // [16] scr_base [17] zp_base
        // -------------------------------------------------------
        case "MACRO_PLACE_CHAR":
            _n.node_title   = "PLACE CHAR";
            _n.instructions = [["macro_place_char", 0, 0, "", 0, 0, "", 0, 32, "", "", 0, 0, "", 1, 1, 0x0400, 0xFB]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

        // -------------------------------------------------------
        // MACRO_CLR_SCREEN
        // [0] mnem  [1] scr_base (hex)  [2] fill (0-255)
        // -------------------------------------------------------
        case "MACRO_CLR_SCREEN":
            _n.node_title   = "CLR SCRN RAM";
            _n.instructions = [["macro_clr_screen", 0x0400, 0]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;
			
			
		// -------------------------------------------------------
        // MACRO_MATH
        // [0] mnem  [1] op (0=ADD 1=SUB 2=MUL 3=DIV 4=ONEMINUS 5=INVSIGN)
        // [2] in_var  [3] operand_mode (0=LIT 1=VAR)  [4] operand_lit (signed)
        // [5] operand_var  [6] result_var
        // -------------------------------------------------------
        case "MACRO_MATH":
            _n.node_title   = "MATH";
            _n.instructions = [["macro_math", 0, "", 0, 0, "", ""]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

			
        /// -------------------------------------------------------
        // MACRO_GET_CHAR
        // [0] mnem
        // [1] col_lit   [2] col_vmode   [3] col_var
        // [4] row_lit   [5] row_vmode   [6] row_var
        // [7] dst_var   [8] get_col     [9] dst_col_var
        // [10] scr_base [11] zp_base
        // -------------------------------------------------------
        case "MACRO_GET_CHAR":
            _n.node_title   = "GET CHAR";
            _n.instructions = [["macro_get_char", 0, 0, "", 0, 0, "", "", 0, "", 0x0400, 0xFB]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

        // -------------------------------------------------------
        // MACRO_SID_SOUND
        // Plays a note on a selectable SID voice. WAVE is the $D404
        // control byte (waveform bits + gate bit 0), written last.
        // [1] voice_mode [2] voice_lit [3] voice_var
        // [4] note_mode  [5] note_lit  [6] note_var   (16-bit freq)
        // [7] wave_mode  [8] wave_lit  [9] wave_var
        // [10] ad_mode   [11] ad_lit   [12] ad_var
        // [13] sr_mode   [14] sr_lit   [15] sr_var
        // [16] pulse_on
        // [17] pw_mode   [18] pw_lit   [19] pw_var    (12-bit width)
        // [20] zp_base   (1 byte, VAR-voice offset compute only)
        // [21] note_asset (TEXT_DATA name, ASSET note mode)
        // [22] off_mode   [23] off_lit  [24] off_var
        // note_mode [4]: 0 = LIT freq, 1 = VAR freq, 2 = ASSET note list.
        // ASSET mode compiles the TEXT_DATA into three tables (lo/hi/gate)
        // and indexes them with Y, leaving X free for the VAR-voice offset.
        // Defaults: V1, C-4 ($1168), tri+gate ($11), AD $00, SR $F0, pulse off.
        // -------------------------------------------------------
        case "MACRO_SID_SOUND":
            _n.node_title   = "SID SOUND";
            _n.instructions = [["macro_sid_sound",
                0, 0, "",
                0, 0x1168, "",
                0, 0x11, "",
                0, 0x00, "",
                0, 0xF0, "",
                0,
                0, 0x0800, "",
                0xF2,
                "", 0, 0, "",
                "", 0, 0, ""]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

       
	   // -------------------------------------------------------
        // MACRO_SID_SONG
        // Plays a SOUND_EDITOR song across all 3 SID voices. One picker —
        // patterns, instruments, order, speed and loop point all come from
        // the asset's meta at compile time.
        // [1] asset_name  (SOUND_EDITOR)
        // [2] auto_init   (1 = JSR <key>_init on the spine where the node sits)
        // [3] zp_base     (27 bytes; defaults to $A0, BASIC's FP scratch,
        //                  which init frees by banking BASIC out via $01=$36)
        // [4] reserved    [5] reserved  (byte/text table export, not yet wired)
        //
        // The node only inits. Call <key>_play once per frame from your main
        // loop or a MACRO_IRQ handler — the label is shown on the node.
        // -------------------------------------------------------
        case "MACRO_SID_SONG":
            _n.node_title   = "SID SONG";
            //                                              [4] = hard restart frames
            _n.instructions = [["macro_sid_song", "", 1, 0x03, 2, ""]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

	   
	   // -------------------------------------------------------
        // MACRO_RANDOM
        // [0] mnem
        // [1] init_osc  (0/1 emit voice-3 noise setup)
        // [2] freq      (16-bit oscillator frequency)
        // [3] clamp_on  (0/1)
        // [4] clamp_min (0-255)   [5] clamp_max (0-255)
        // [6] dst_mode  (0 = A, 1 = VAR)
        // [7] dst_var   [8] zp_base
        // -------------------------------------------------------
        case "MACRO_RANDOM":
            _n.node_title   = "RANDOM";
            _n.instructions = [["macro_random", 1, 0xFFFF, 0, 0, 255, 0, "", 0xFB]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

        // -------------------------------------------------------
        // MACRO_MOVE
        // -------------------------------------------------------
        case "MACRO_MOVE":
            _n.node_title   = "MACRO MOVE";
            _n.instructions = [["macro_move", 1, 0, 0, 0, 0, 0, 0, "", 0, ""]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

        // -------------------------------------------------------
        // MACRO_MAP
        // -------------------------------------------------------
        case "MACRO_MAP":
            _n.node_title   = "MACRO MAP";
            _n.instructions = [["macro_map", "", 40, 25, 0, 0, 0x50]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

        // -------------------------------------------------------
        // MACRO_MAP_SWITCH
        // -------------------------------------------------------
        case "MACRO_MAP_SWITCH":
            _n.node_title   = "MAP SWITCH";
            _n.instructions = [["macro_map_switch", "", 0]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

        // -------------------------------------------------------
        // MACRO_CHR
        // -------------------------------------------------------
        case "MACRO_CHR":
            _n.node_title   = "MACRO CHARSET";
            _n.instructions = [["macro_chr", "", 0]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

        // -------------------------------------------------------
        // MACRO_LOADER
        // -------------------------------------------------------
        case "MACRO_LOADER":
            _n.node_title   = "MACRO LOADER";
            _n.instructions = [["macro_loader", "", "", 0]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

        case "MACRO_SAVE_GAME":
            _n.node_title   = "SAVE GAME";
            _n.instructions = [["macro_save_game", "", "", 0]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

        case "MACRO_LOAD_GAME":
            _n.node_title   = "LOAD GAME";
            _n.instructions = [["macro_load_game", "", "", 0]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

        // -------------------------------------------------------
        // MACRO_IRQ
        // -------------------------------------------------------
        case "MACRO_IRQ":
            _n.node_title   = "MACRO IRQ";
            _n.instructions = [["macro_irq", 0x60, 0, "", "", "", 1, ""]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

        // -------------------------------------------------------
        // MACRO_IRQ_HANDLER
        // -------------------------------------------------------
        case "MACRO_IRQ_HANDLER":
            _n.node_title   = "IRQ HANDLER";
            _n.instructions = [["macro_irq_handler", 0]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

        // -------------------------------------------------------
        // MACRO_COLLISION
        // -------------------------------------------------------
        case "MACRO_COLLISION":
            _n.node_title   = "COLLISION";
            _n.instructions = [["macro_collision", 0, 0, "", 0, 0]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

        // -------------------------------------------------------
        // MACRO_COLL_ADV
        // -------------------------------------------------------
        // [26] direct — 0 = SCAN <map>_TILE_TYPES for the screen byte (char mode)
        //               1 = the screen byte at $0400 IS the type (bitmap hybrid)
        // In DIRECT mode the probe reads $0400 + row*40 + col and uses that byte
        // as the collision type outright, skipping the TILE_TYPES scan. That's
        // the byte MACRO_MOVE_BMP_BLOCK's WRITE COLL wrote from the source tags —
        // so bitmap collision needs no table scan and no per-room storage.
        case "MACRO_COLL_ADV":
            _n.node_title   = "COLL-ADV";
            _n.instructions = [["macro_coll_adv", 0, 0, 0, "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", 0]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

        // -------------------------------------------------------
        // MACRO_ANIM
        // -------------------------------------------------------
        case "MACRO_ANIM":
            _n.node_title   = "ANIMATE";
            _n.instructions = [["macro_anim", 8, "", "", "", "", "", "", "", ""]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

        // -------------------------------------------------------
        // MACRO_SFX
        // -------------------------------------------------------
        case "MACRO_SFX":
            _n.node_title   = "SFX";
            _n.instructions = [["macro_sfx", "", 0]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

        // -------------------------------------------------------
        // MACRO_MOVE_MEM6
        // -------------------------------------------------------
        case "MACRO_MOVE_MEM":
            _n.node_title   = "MOVE MEM";
            _n.instructions = [["macro_move_mem", 0xC000, 0xC100, 0x0500]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;
			
			
		// MACRO_VECTOR_PAGE
		// instructions[0]: ["macro_vector_page", asset_name, page_index]
		//   asset_name = VECTOR_BITMAP asset to flip (must have a setup node earlier)
		//   page_index = which page to clear-and-render
		case "MACRO_VECTOR_PAGE":
			_n.node_title   = "VECTOR PAGE";
			_n.instructions = [["macro_vector_page", "", 0]];
			_n.pc_address   = global.start_pc;
			with (_n) { event_user(0); }
			break;

        // -------------------------------------------------------
        // MACRO_VECTOR_BMP
        // instructions[0]: ["macro_vector_bmp", asset_name, fill_stack_addr, render_now]
        //   asset_name      = VECTOR_BITMAP asset to render
        //   fill_stack_addr = flood-fill RAM stack override (0 = use asset/default $C000)
        //   render_now      = 1 = JSR vbmp_render inline, 0 = emit routine+stream only
        // -------------------------------------------------------
        case "MACRO_VECTOR_BMP":
            _n.node_title   = "VECTOR BMP";
            _n.instructions = [["macro_vector_bmp", "", 0, 1]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;
			
		// -------------------------------------------------------
        // MACRO_CLEAR_BMP_RECT
        // Zeroes a rectangular block of bitmap data, in char cells. Every
        // bit-pair in the cleared cells becomes %00, which the VIC renders as
        // $D021 (background) whatever screen/colour RAM hold — so it's a true
        // background wipe that touches neither palette plane.
        //
        // Drop it before a MACRO_MOVE_BMP_BLOCK to pre-clear the region a
        // room's stamps land in: MASK00 blend lets the destination show through
        // the source's holes, so without a wipe the previous room's pixels
        // survive in the gaps.
        //
        // [0] name  [1] bmp_addr  [2] col  [3] row  [4] w  [5] h
        // Defaults to the whole 40x25 screen at the same bitmap MOVE_BMP_BLOCK
        // defaults its DEST to.
        // -------------------------------------------------------
        case "MACRO_CLEAR_BMP_RECT":
            _n.node_title   = "CLEAR BMP RECT";
            _n.instructions = [["macro_clear_bmp_rect", 0x4000, 0, 0, 40, 25]];
            _n.pc_address   = global.start_pc;
            with (_n) { event_user(0); }
            break;

        // -------------------------------------------------------
        // NORMAL (default fallback)
        // -------------------------------------------------------
        default:
            _n.node_title   = "CUSTOM LOGIC";
            _n.instructions = [["lda_imm", 0], ["sta_abs", 0xD020]];
            _n.pc_address   = global.start_pc;
            break;
    }

    return _n;
}